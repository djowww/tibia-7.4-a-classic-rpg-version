// NPC trade window: lists what an NPC sells and buys and runs the trade
// through the NPC's own confirmation rule, so prices, rarity protection and
// replies stay exactly as in the spoken dialogue.

#include "otpch.h"

#include "behaviourdatabase.h"
#include "game.h"
#include "networkmessage.h"
#include "npc.h"
#include "player.h"
#include "tools.h"

extern Game g_game;

namespace {

constexpr uint8_t NPC_TRADE_OPCODE = 130;
constexpr int32_t MAX_TRADE_COUNT = 100;
constexpr int64_t TRADE_INTERVAL = 200;

enum TopicKind : int {
	TOPIC_CONFLICT = -1,
	TOPIC_BUY = 1,
	TOPIC_SELL = 2,
};

bool containsType(const NpcBehaviourNode* node, NpcBehaviourType_t type)
{
	if (!node) {
		return false;
	}
	return node->type == type || containsType(node->left, type) || containsType(node->right, type);
}

// Value of an expression made only of numbers and the %1 amount.
int64_t staticValue(const NpcBehaviourNode* node, int32_t count, bool& ok)
{
	if (!node) {
		ok = false;
		return 0;
	}

	switch (node->type) {
		case BEHAVIOUR_TYPE_NUMBER:
			return node->number;
		case BEHAVIOUR_TYPE_MESSAGE_COUNT:
			return count;
		case BEHAVIOUR_TYPE_OPERATION: {
			const int64_t left = staticValue(node->left, count, ok);
			const int64_t right = staticValue(node->right, count, ok);
			switch (node->number) {
				case BEHAVIOUR_OPERATOR_MULTIPLY: return left * right;
				case BEHAVIOUR_OPERATOR_SUM: return left + right;
				case BEHAVIOUR_OPERATOR_RES: return left - right;
				default: break;
			}
			ok = false;
			return 0;
		}
		default:
			ok = false;
			return 0;
	}
}

const NpcBehaviourAction* findAction(const NpcBehaviour* behaviour, NpcBehaviourType_t type)
{
	for (const NpcBehaviourAction* action : behaviour->actions) {
		if (action->type == type) {
			return action;
		}
	}
	return nullptr;
}

bool topicCondition(const NpcBehaviourCondition* condition, int32_t& topic)
{
	if (condition->type != BEHAVIOUR_TYPE_OPERATION || !condition->expression) {
		return false;
	}

	const NpcBehaviourNode* node = condition->expression;
	if (node->number != BEHAVIOUR_OPERATOR_EQUALS || !node->left || !node->right) {
		return false;
	}

	if (node->left->type != BEHAVIOUR_TYPE_TOPIC || node->right->type != BEHAVIOUR_TYPE_NUMBER) {
		return false;
	}

	topic = node->right->number;
	return true;
}

bool usesItemVariable(const NpcBehaviourAction* action)
{
	return action->expression && action->expression->type == BEHAVIOUR_TYPE_ITEM;
}

std::string cleanField(std::string text)
{
	for (char& c : text) {
		if (c == '\t' || c == '\n' || c == '\r') {
			c = ' ';
		}
	}
	return text;
}

void sendTradeMessage(Player& player, const std::string& text)
{
	if (text.size() > 16384) {
		return;
	}

	NetworkMessage message;
	message.addByte(0x32);
	message.addByte(NPC_TRADE_OPCODE);
	message.addString(text);
	player.sendNetworkMessage(message);
}

} // namespace

void NpcTrade::handleRequest(Player& player, const std::string& request)
{
	unsigned int npcId = 0;
	unsigned int index = 0;
	int count = 0;

	if (std::sscanf(request.c_str(), "trade\t%u\t%u\t%d", &npcId, &index, &count) == 3) {
		if (Npc* npc = g_game.getNpcByID(npcId)) {
			npc->handleTradeRequest(&player, index, count);
		}
	} else if (std::sscanf(request.c_str(), "close\t%u", &npcId) == 1) {
		if (Npc* npc = g_game.getNpcByID(npcId)) {
			npc->closeTradeRequest(&player);
		}
	}
}

void BehaviourDatabase::buildTradeOffers()
{
	tradeOffers.clear();
	tradeKeyword = false;

	// Which topics end in a plain purchase or a plain sale once the player says "yes".
	std::map<int32_t, int> topicKinds;
	for (const NpcBehaviour* behaviour : behaviourEntries) {
		if (behaviour->situation != SITUATION_NONE) {
			continue;
		}

		int32_t confirmTopic = 0;
		bool hasTopic = false;
		bool saysYes = false;
		for (const NpcBehaviourCondition* condition : behaviour->conditions) {
			if (topicCondition(condition, confirmTopic)) {
				hasTopic = true;
			} else if (condition->type == BEHAVIOUR_TYPE_STRING) {
				if (condition->string == "yes" || condition->string == "yes$") {
					saysYes = true;
				}
				if (searchWord(condition->string, "trade")) {
					tradeKeyword = true;
				}
			}
		}

		if (!hasTopic || !saysYes) {
			continue;
		}

		bool deletesMoney = false;
		bool createsMoney = false;
		bool createsItem = false;
		bool deletesItem = false;
		bool other = false;
		for (const NpcBehaviourAction* action : behaviour->actions) {
			switch (action->type) {
				case BEHAVIOUR_TYPE_STRING: break;
				case BEHAVIOUR_TYPE_DELETEMONEY: deletesMoney = true; break;
				case BEHAVIOUR_TYPE_CREATEMONEY: createsMoney = true; break;
				case BEHAVIOUR_TYPE_CREATE:
					if (usesItemVariable(action)) {
						createsItem = true;
					} else {
						other = true;
					}
					break;
				case BEHAVIOUR_TYPE_DELETE:
					if (usesItemVariable(action)) {
						deletesItem = true;
					} else {
						other = true;
					}
					break;
				default:
					other = true;
					break;
			}
		}

		int kind = 0;
		if (!other && deletesMoney && createsItem && !createsMoney && !deletesItem) {
			kind = TOPIC_BUY;
		} else if (!other && createsMoney && deletesItem && !deletesMoney && !createsItem) {
			kind = TOPIC_SELL;
		} else {
			continue;
		}

		auto it = topicKinds.find(confirmTopic);
		if (it == topicKinds.end()) {
			topicKinds[confirmTopic] = kind;
		} else if (it->second != kind) {
			it->second = TOPIC_CONFLICT;
		}
	}

	std::vector<NpcTradeOffer> countedOffers;
	for (const NpcBehaviour* behaviour : behaviourEntries) {
		if (behaviour->situation != SITUATION_NONE) {
			continue;
		}

		bool counted = false;
		bool dependsOnTopic = false;
		for (const NpcBehaviourCondition* condition : behaviour->conditions) {
			if (condition->type == BEHAVIOUR_TYPE_MESSAGE_COUNT) {
				counted = true;
			} else if (condition->type == BEHAVIOUR_TYPE_OPERATION && containsType(condition->expression, BEHAVIOUR_TYPE_TOPIC)) {
				dependsOnTopic = true;
			}
		}

		if (dependsOnTopic) {
			continue;
		}

		const NpcBehaviourAction* itemAction = findAction(behaviour, BEHAVIOUR_TYPE_ITEM);
		const NpcBehaviourAction* priceAction = findAction(behaviour, BEHAVIOUR_TYPE_PRICE);
		const NpcBehaviourAction* topicAction = findAction(behaviour, BEHAVIOUR_TYPE_TOPIC);
		if (!itemAction || !priceAction || !topicAction) {
			continue;
		}

		const NpcBehaviourAction* amountAction = findAction(behaviour, BEHAVIOUR_TYPE_AMOUNT);
		const NpcBehaviourAction* dataAction = findAction(behaviour, BEHAVIOUR_TYPE_DATA);

		const int32_t sample = counted ? 2 : 1;
		bool ok = true;
		const int64_t itemId = staticValue(itemAction->expression, sample, ok);
		const int64_t topicValue = staticValue(topicAction->expression, sample, ok);
		const int64_t priceValue = staticValue(priceAction->expression, sample, ok);
		const int64_t amountValue = amountAction ? staticValue(amountAction->expression, sample, ok) : 1;
		const int64_t dataValue = dataAction ? staticValue(dataAction->expression, sample, ok) : -1;
		if (!ok || itemId <= 0 || itemId > 0xFFFF || priceValue < 0 || amountValue < 1) {
			continue;
		}

		if (Item::items[static_cast<uint16_t>(itemId)].id == 0) {
			continue;
		}

		auto kind = topicKinds.find(static_cast<int32_t>(topicValue));
		if (kind == topicKinds.end() || kind->second == TOPIC_CONFLICT) {
			continue;
		}

		NpcTradeOffer offer;
		offer.itemId = static_cast<uint16_t>(itemId);
		offer.data = static_cast<int32_t>(dataValue);
		offer.topic = static_cast<int32_t>(topicValue);
		offer.sell = kind->second == TOPIC_SELL;
		if (counted) {
			offer.counted = behaviour;
			countedOffers.push_back(offer);
		} else {
			offer.unit = behaviour;
			offer.amount = static_cast<int32_t>(std::min<int64_t>(amountValue, 10000));
			offer.price = static_cast<int32_t>(std::min<int64_t>(priceValue, std::numeric_limits<int32_t>::max()));
			tradeOffers.push_back(offer);
		}
	}

	for (NpcTradeOffer& offer : tradeOffers) {
		for (const NpcTradeOffer& counted : countedOffers) {
			if (counted.itemId == offer.itemId && counted.data == offer.data && counted.sell == offer.sell && counted.topic == offer.topic) {
				offer.counted = counted.counted;
				break;
			}
		}
	}
}

bool BehaviourDatabase::tradeOfferAvailable(const NpcTradeOffer& offer, Player* player)
{
	// Vocation, premium, quest and similar requirements of the spoken offer still apply.
	for (const NpcBehaviourCondition* condition : offer.unit->conditions) {
		switch (condition->type) {
			case BEHAVIOUR_TYPE_NOP:
			case BEHAVIOUR_TYPE_STRING:
			case BEHAVIOUR_TYPE_MESSAGE_COUNT:
			case BEHAVIOUR_TYPE_FULL_DIGIT:
				break;
			case BEHAVIOUR_TYPE_OPERATION:
				if (containsType(condition->expression, BEHAVIOUR_TYPE_MESSAGE_COUNT)) {
					break;
				}
				if (!checkCondition(condition, player, "")) {
					return false;
				}
				break;
			default:
				if (!checkCondition(condition, player, "")) {
					return false;
				}
				break;
		}
	}
	return true;
}

bool BehaviourDatabase::sendTrade(Player* player)
{
	std::ostringstream ss;
	ss << "open\t" << npc->getID() << '\t' << cleanField(npc->getName()) << '\t' << player->getMoney() << '\n';

	std::set<std::tuple<uint16_t, int32_t, bool>> seen;
	for (size_t i = 0; i < tradeOffers.size(); i++) {
		const NpcTradeOffer& offer = tradeOffers[i];
		if (seen.count(std::make_tuple(offer.itemId, offer.data, offer.sell)) != 0) {
			continue;
		}

		if (!tradeOfferAvailable(offer, player)) {
			continue;
		}
		seen.emplace(offer.itemId, offer.data, offer.sell);

		const ItemType& it = Item::items[offer.itemId];
		const int32_t countData = (it.stackable || !it.hasSubType()) ? -1 : offer.data;
		const uint32_t have = player->getItemTypeCount(offer.itemId, countData, offer.sell);

		ss << (offer.sell ? 'S' : 'B') << '\t' << i << '\t' << offer.itemId << '\t' << offer.data << '\t'
			<< offer.amount << '\t' << offer.price << '\t' << it.weight << '\t'
			<< (offer.counted ? MAX_TRADE_COUNT : 1) << '\t' << have << '\t'
			<< cleanField(it.article) << '\t' << cleanField(it.name) << '\n';
	}

	if (seen.empty()) {
		return false;
	}

	tradePlayer = player->getID();
	sendTradeMessage(*player, ss.str());
	return true;
}

bool BehaviourDatabase::openTrade(Player* player)
{
	if (!player || tradeOffers.empty() || !sendTrade(player)) {
		return false;
	}

	if (!tradeKeyword) {
		npc->doSay("Of course, take a look at my offers.");
	}
	return true;
}

void BehaviourDatabase::closeTrade(bool notify)
{
	if (tradePlayer == 0) {
		return;
	}

	if (notify) {
		if (Player* player = g_game.getPlayerByID(tradePlayer)) {
			std::ostringstream ss;
			ss << "close\t" << npc->getID();
			sendTradeMessage(*player, ss.str());
		}
	}
	tradePlayer = 0;
}

void BehaviourDatabase::handleTrade(Player* player, size_t index, int32_t count)
{
	if (!player || index >= tradeOffers.size() || count < 1 || count > MAX_TRADE_COUNT) {
		return;
	}

	if (npc->focusCreature != player->getID() || tradePlayer != player->getID()) {
		std::ostringstream ss;
		ss << "close\t" << npc->getID();
		sendTradeMessage(*player, ss.str());
		return;
	}

	if (!Position::areInRange<3, 3>(player->getPosition(), npc->getPosition())) {
		return;
	}

	const int64_t now = OTSYS_TIME();
	if (now - lastTradeTime < TRADE_INTERVAL) {
		return;
	}
	lastTradeTime = now;

	const NpcTradeOffer& offer = tradeOffers[index];
	if (!tradeOfferAvailable(offer, player)) {
		return;
	}

	const NpcBehaviour* rule = offer.unit;
	if (count > 1) {
		if (!offer.counted) {
			return;
		}
		rule = offer.counted;
	}

	const NpcBehaviourAction* priceAction = findAction(rule, BEHAVIOUR_TYPE_PRICE);
	const NpcBehaviourAction* amountAction = findAction(rule, BEHAVIOUR_TYPE_AMOUNT);
	bool ok = priceAction != nullptr;
	const int64_t priceValue = ok ? staticValue(priceAction->expression, count, ok) : 0;
	const int64_t amountValue = amountAction ? staticValue(amountAction->expression, count, ok) : 1;
	if (!ok || priceValue < 0 || priceValue > std::numeric_limits<int32_t>::max() || amountValue < 1 || amountValue > 10000) {
		return;
	}

	// Same state the spoken offer would leave behind, then the NPC's own "yes" rule decides.
	type = offer.itemId;
	data = offer.data;
	amount = static_cast<int32_t>(amountValue);
	price = static_cast<int32_t>(priceValue);
	topic = offer.topic;

	npc->lastTalkCreature = player->getID();
	react(SITUATION_NONE, player, "yes");

	if (npc->focusCreature == player->getID() && tradePlayer == player->getID()) {
		sendTrade(player);
	}
}
