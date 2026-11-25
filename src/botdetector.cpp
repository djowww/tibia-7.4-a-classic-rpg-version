#include "otpch.h"

#include "botdetector.h"
#include "tools.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include <lua.hpp>

BotDetector& BotDetector::instance()
{
	static BotDetector detector;
	return detector;
}

BotDetector::Category BotDetector::categorize(uint8_t recvbyte)
{
	switch (recvbyte) {
		case 0x65: case 0x66: case 0x67: case 0x68:
		case 0x6A: case 0x6B: case 0x6C: case 0x6D:
		case 0x45: // OTCv8 new walking
			return CAT_WALK;
		case 0x64:
			return CAT_AUTOWALK;
		case 0x6F: case 0x70: case 0x71: case 0x72:
			return CAT_TURN;
		case 0x82:
			return CAT_USE;
		case 0x83: case 0x84:
			return CAT_USEWITH;
		case 0xA1:
			return CAT_ATTACK;
		case 0x96:
			return CAT_SAY;
		case 0x78:
			return CAT_MOVE;
		default:
			return CAT_NONE;
	}
}

void BotDetector::onPacket(uint32_t playerId, uint8_t recvbyte)
{
	const Category category = categorize(recvbyte);
	if (category == CAT_NONE) {
		return;
	}

	const int64_t now = OTSYS_TIME();
	std::lock_guard<std::mutex> guard(lock);
	if (++sincePrune >= 20000) {
		pruneLocked(now);
	}

	Record& record = records[playerId];
	if (record.firstSeenAt == 0) {
		record.firstSeenAt = now;
	}
	++record.packets;
	record.lastActionAt = now;

	int64_t& last = record.lastAt[category];
	if (last != 0) {
		const int64_t interval = now - last;
		if (interval >= MIN_INTERVAL && interval <= MAX_INTERVAL) {
			record.intervals[category].push(static_cast<int32_t>(interval));
		}
	}
	last = now;

	// Walking and turning are paced by the client itself; bursts only count
	// clicks and hotkeys.
	if (category != CAT_WALK && category != CAT_TURN && category != CAT_AUTOWALK) {
		if (now - record.burstWindowAt >= 1000) {
			record.burstWindowAt = now;
			record.burstWindowCount = 0;
		}
		if (++record.burstWindowCount == BURST_LIMIT + 1) {
			++record.bursts;
		}
	}

	// Healing in 7.4 is a spell (say), a rune or a fluid (use with / use).
	if (record.damagedAt != 0 && (category == CAT_SAY || category == CAT_USE || category == CAT_USEWITH)) {
		const int64_t reaction = now - record.damagedAt;
		if (reaction <= MAX_REACTION) {
			record.reactions.push(static_cast<int32_t>(reaction));
		}
		record.damagedAt = 0;
	}
}

void BotDetector::onStats(uint32_t playerId, int32_t health)
{
	const int64_t now = OTSYS_TIME();
	std::lock_guard<std::mutex> guard(lock);
	auto it = records.find(playerId);
	if (it == records.end()) {
		Record& record = records[playerId];
		record.firstSeenAt = now;
		record.lastHealth = health;
		return;
	}

	Record& record = it->second;
	if (record.lastHealth >= 0 && health < record.lastHealth) {
		// Several hits in a row: measure from the first unanswered one.
		if (record.damagedAt == 0 || now - record.damagedAt > MAX_REACTION) {
			// A player who was already spamming heals (holding a hotkey) is
			// not reacting to this hit: only measure from a quiet moment.
			const int64_t lastHeal = std::max({record.lastAt[CAT_SAY], record.lastAt[CAT_USE], record.lastAt[CAT_USEWITH]});
			record.damagedAt = (now - lastHeal >= QUIET_BEFORE_HIT) ? now : 0;
		}
	}
	record.lastHealth = health;
}

void BotDetector::forget(uint32_t playerId)
{
	std::lock_guard<std::mutex> guard(lock);
	records.erase(playerId);
}

void BotDetector::pruneLocked(int64_t now)
{
	sincePrune = 0;
	for (auto it = records.begin(); it != records.end();) {
		const int64_t seen = std::max(it->second.lastActionAt, it->second.firstSeenAt);
		if (now - seen > 2 * 60 * 60 * 1000) {
			it = records.erase(it);
		} else {
			++it;
		}
	}
}

namespace {

void setField(lua_State* L, const char* key, double value)
{
	lua_pushnumber(L, value);
	lua_setfield(L, -2, key);
}

// Pushes {n, mean, sd, median, near} for the ring. "near" is the share of
// samples within max(25 ms, 3%) of the median: a timer-driven bot keeps it
// close to 1 even when it adds an occasional pause.
void pushRing(lua_State* L, const BotDetector::Ring& ring)
{
	std::vector<double> values(ring.values.begin(), ring.values.begin() + ring.size());
	lua_createtable(L, 0, 5);
	setField(L, "n", static_cast<double>(values.size()));
	setField(L, "total", ring.count);
	if (values.empty()) {
		return;
	}

	double sum = 0;
	for (double v : values) {
		sum += v;
	}
	const double mean = sum / values.size();
	double variance = 0;
	for (double v : values) {
		variance += (v - mean) * (v - mean);
	}
	variance /= values.size();

	std::vector<double> sorted = values;
	std::sort(sorted.begin(), sorted.end());
	const double median = sorted[sorted.size() / 2];
	const double tolerance = std::max(25.0, median * 0.03);
	size_t near = 0;
	for (double v : values) {
		if (std::abs(v - median) <= tolerance) {
			++near;
		}
	}

	setField(L, "mean", mean);
	setField(L, "sd", std::sqrt(variance));
	setField(L, "median", median);
	setField(L, "near", static_cast<double>(near) / values.size());
}

const char* const categoryNames[BotDetector::CAT_COUNT] = {
	"walk", "autowalk", "turn", "use", "usewith", "attack", "say", "move",
};

}

int BotDetector::luaGetStats(lua_State* L)
{
	// getBotDetectorStats(playerId)
	const uint32_t playerId = static_cast<uint32_t>(lua_tonumber(L, 1));
	BotDetector& detector = instance();
	const int64_t now = OTSYS_TIME();

	std::lock_guard<std::mutex> guard(detector.lock);
	auto it = detector.records.find(playerId);
	if (it == detector.records.end()) {
		lua_pushnil(L);
		return 1;
	}

	const Record& record = it->second;
	lua_createtable(L, 0, CAT_COUNT + 6);
	for (size_t i = 0; i < CAT_COUNT; ++i) {
		pushRing(L, record.intervals[i]);
		lua_setfield(L, -2, categoryNames[i]);
	}
	pushRing(L, record.reactions);
	lua_setfield(L, -2, "reaction");
	setField(L, "packets", static_cast<double>(record.packets));
	setField(L, "bursts", record.bursts);
	setField(L, "idle", record.lastActionAt == 0 ? -1 : static_cast<double>(now - record.lastActionAt));
	setField(L, "tracked", static_cast<double>(now - record.firstSeenAt));
	return 1;
}

int BotDetector::luaForget(lua_State* L)
{
	// resetBotDetector(playerId)
	instance().forget(static_cast<uint32_t>(lua_tonumber(L, 1)));
	return 0;
}

void BotDetector::registerLua(lua_State* L)
{
	lua_register(L, "getBotDetectorStats", BotDetector::luaGetStats);
	lua_register(L, "resetBotDetector", BotDetector::luaForget);
}
