/**
 * Tibia GIMUD Server - a free and open-source MMORPG server emulator
 * Copyright (C) 2017  Alejandro Mujica <alejandrodemujica@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include "otpch.h"

#include "protocollogin.h"

#include "outputmessage.h"
#include "tasks.h"

#include "configmanager.h"
#include "iologindata.h"
#include "ban.h"
#include "game.h"
#include "scheduler.h"
#include "database.h"
#include "vocation.h"

extern ConfigManager g_config;
extern Game g_game;
extern Vocations g_vocations;

namespace {

struct CharacterDetails {
	uint16_t level = 1;
	uint16_t lookType = 136;
	uint8_t lookHead = 0;
	uint8_t lookBody = 0;
	uint8_t lookLegs = 0;
	uint8_t lookFeet = 0;
	std::string vocation;
	std::string town;
};

// Accounts with more characters than this get the plain list only, so the
// login reply always fits in one network message.
const size_t maxDetailedCharacters = 50;

uint8_t clampLookColor(int64_t value)
{
	return static_cast<uint8_t>(std::max<int64_t>(0, std::min<int64_t>(132, value)));
}

bool loadCharacterDetails(uint32_t accountId, std::map<std::string, CharacterDetails>& details)
{
	std::ostringstream query;
	query << "SELECT `name`, `level`, `vocation`, `looktype`, `lookhead`, `lookbody`, `looklegs`, `lookfeet`, `town_id` FROM `players` WHERE `account_id` = " << accountId;
	bool success = false;
	DBResult_ptr result = Database::getInstance()->storeQuery(query.str(), &success);
	if (!success || !result) {
		return false;
	}

	do {
		CharacterDetails row;
		row.level = static_cast<uint16_t>(std::max<int64_t>(1, std::min<int64_t>(std::numeric_limits<uint16_t>::max(), result->getNumber<int64_t>("level"))));
		row.lookType = static_cast<uint16_t>(std::max<int64_t>(0, std::min<int64_t>(std::numeric_limits<uint16_t>::max(), result->getNumber<int64_t>("looktype"))));
		row.lookHead = clampLookColor(result->getNumber<int64_t>("lookhead"));
		row.lookBody = clampLookColor(result->getNumber<int64_t>("lookbody"));
		row.lookLegs = clampLookColor(result->getNumber<int64_t>("looklegs"));
		row.lookFeet = clampLookColor(result->getNumber<int64_t>("lookfeet"));

		if (const Vocation* vocation = g_vocations.getVocation(result->getNumber<uint16_t>("vocation"))) {
			row.vocation = vocation->getVocName();
		}
		if (const Town* town = g_game.map.towns.getTown(result->getNumber<uint32_t>("town_id"))) {
			row.town = town->getName();
		}
		details[result->getString("name")] = std::move(row);
	} while (result->next());
	return true;
}

}

void ProtocolLogin::sendUpdateRequest()
{
	auto output = OutputMessagePool::getOutputMessage();

	output->addByte(0x1E);
	send(output);

	disconnect();
}

void ProtocolLogin::disconnectClient(const std::string& message)
{
	auto output = OutputMessagePool::getOutputMessage();

	output->addByte(0x0A);
	output->addString(message);
	send(output);

	disconnect();
}

void ProtocolLogin::getCharacterList(uint32_t accountNumber, const std::string& password)
{
	if (g_config.getBoolean(ConfigManager::BLOCK_LOGIN)) {
		disconnectClient(g_config.getString(ConfigManager::BLOCK_LOGIN_TEXT));
		return;
	}

	AuthenticationResult authentication = IOLoginData::loginserverAuthentication(accountNumber, password);
	const auto failureDelay = getAccountAuthenticationFailureLimiter().processResult(accountNumber, authentication.status);
	if (authentication.status != AuthenticationStatus::Success) {
		const std::string message = authenticationFailureMessage(authentication.status);
		if (failureDelay.count() > 0) {
			SchedulerTask* task = nullptr;
			try {
				const std::shared_ptr<ProtocolLogin> self = std::static_pointer_cast<ProtocolLogin>(shared_from_this());
				task = createSchedulerTask(static_cast<uint32_t>(failureDelay.count()), [self, message]() {
					if (!self->isConnectionExpired()) {
						self->disconnectClient(message);
					}
				});
				if (g_scheduler.addEvent(task) != 0) {
					return;
				}
				task = nullptr; // addEvent consumes the task when it returns zero
			} catch (...) {
				delete task;
			}
		}
		disconnectClient(message);
		return;
	}
	Account& account = authentication.account;

	auto output = OutputMessagePool::getOutputMessage();

	//Update premium days
	Game::updatePremium(account);

	const std::string& motd = g_config.getString(ConfigManager::MOTD);
	if (!motd.empty()) {
		//Add MOTD
		output->addByte(0x14);

		std::ostringstream ss;
		ss << g_game.getMotdNum() << "\n" << motd;
		output->addString(ss.str());
	}

	uint8_t size = std::min<size_t>(std::numeric_limits<uint8_t>::max(), account.characters.size());

	//Add character details (only for clients that asked; sent before the list so
	//the client has them when the list arrives)
	if (characterDetails && size > 0 && size <= maxDetailedCharacters) {
		std::map<std::string, CharacterDetails> details;
		if (loadCharacterDetails(account.id, details)) {
			output->addByte(0x66);
			output->addByte(size);
			for (uint8_t i = 0; i < size; i++) {
				auto it = details.find(account.characters[i]);
				if (it == details.end()) {
					output->addByte(0x00);
					continue;
				}

				const CharacterDetails& row = it->second;
				output->addByte(0x01);
				output->add<uint16_t>(row.level);
				output->addString(row.vocation);
				output->add<uint16_t>(row.lookType);
				output->addByte(row.lookHead);
				output->addByte(row.lookBody);
				output->addByte(row.lookLegs);
				output->addByte(row.lookFeet);
				output->addString(row.town);
			}
		}
	}

	//Add char list
	output->addByte(0x64);

	output->addByte(size);
	for (uint8_t i = 0; i < size; i++) {
		output->addString(account.characters[i]);
		output->addString(g_config.getString(ConfigManager::SERVER_NAME));
		output->add<uint32_t>(inet_addr(g_config.getString(ConfigManager::IP).c_str()));
		output->add<uint16_t>(g_config.getNumber(ConfigManager::GAME_PORT));
	}

	//Add premium days
	if (g_config.getBoolean(ConfigManager::FREE_PREMIUM)) {
		output->add<uint16_t>(0xFFFF);
	} else {
		output->add<uint16_t>(account.premiumDays);
	}

	send(output);

	disconnect();
}

void ProtocolLogin::onRecvFirstMessage(NetworkMessage& msg)
{
	if (g_game.getGameState() == GAME_STATE_SHUTDOWN) {
		disconnect();
		return;
	}

	msg.skipBytes(2); // client OS

	/*uint16_t version =*/ msg.get<uint16_t>();
	msg.skipBytes(12);

	/*
	 * Skipped bytes:
	 * 4 bytes: protocolVersion
	 * 12 bytes: dat, spr, pic signatures (4 bytes each)
	 */
	
	// Public version marker, not a secret or account authentication factor.
	// Check before RSA decoding so old clients receive a useful update notice.
	if (msg.getString() != "Antigas-26") {
		disconnectClient("Please download Antigas client v26 or newer at https://tibia74.tech");
		return;
	}
	
	if (!Protocol::RSA_decrypt(msg)) {
		disconnect();
		return;
	}

	uint32_t key[4];
	key[0] = msg.get<uint32_t>();
	key[1] = msg.get<uint32_t>();
	key[2] = msg.get<uint32_t>();
	key[3] = msg.get<uint32_t>();
	enableXTEAEncryption();
	setXTEAKey(key);

	/*if (version < CLIENT_VERSION_MIN || version > CLIENT_VERSION_MAX) {
		//sendUpdateRequest();
		disconnectClient("Use the Antigas 7.4 client to log in!");
		return;
	}*/

	if (g_game.getGameState() == GAME_STATE_STARTUP) {
		disconnectClient("Gameworld is starting up. Please wait.");
		return;
	}

	if (g_game.getGameState() == GAME_STATE_MAINTAIN) {
		disconnectClient("Gameworld is under maintenance.\nPlease re-connect in a while.");
		return;
	}
	
	const std::string customMessage = g_config.getString(ConfigManager::BLOCK_LOGIN_TEXT);
	if (g_config.getBoolean(ConfigManager::BLOCK_LOGIN)) {
		disconnectClient(customMessage);
		return;
	}

    uint32_t accountNumber = msg.get<uint32_t>();
	if (!accountNumber) {
		disconnectClient("Invalid account number.");
		return;
	}

	std::string password = msg.getString();
	if (password.empty()) {
		disconnectClient("Invalid password.");
		return;
	}
	
	// Optional client markers after the password. The random RSA padding of
	// clients that send neither does not match them.
	uint16_t markerLength = msg.get<uint16_t>();
	if (markerLength == 5 && msg.getString(5) == "OTCv8") {
		otclientV8 = msg.get<uint16_t>(); // 253, 260, 261, ...
	} else if (markerLength == 4 && msg.getString(4) == "ACL1") {
		characterDetails = true; // Antigas character list v1
	}
	// First packets retain their absolute end; the XTEA cursor helper uses a
	// different length convention and would allow four undeclared bytes here.
	if (msg.isOverrun() || msg.getBufferPosition() > msg.getLength()) {
		disconnect();
		return;
	}

	BanInfo banInfo;
	auto connection = getConnection();
	if (!connection) {
		return;
	}
	const auto ipBan = IOBan::lookupIpBan(connection->getIP(), banInfo);
	if (ipBan == BanLookupResult::Error) {
		disconnectClient("Login temporarily unavailable. Please try again later.");
		return;
	}
	if (ipBan == BanLookupResult::Banned) {
		if (banInfo.reason.empty()) {
			banInfo.reason = "(none)";
		}
		std::ostringstream ss;
		ss << "Your IP has been banned until " << formatDateShort(banInfo.expiresAt) << " by " << banInfo.bannedBy << ".\n\nReason specified:\n" << banInfo.reason;
		disconnectClient(ss.str());
		return;
	}

	auto thisPtr = std::static_pointer_cast<ProtocolLogin>(shared_from_this());
	g_dispatcher.addTask(createTask(std::bind(&ProtocolLogin::getCharacterList, thisPtr, accountNumber, password)));
}
