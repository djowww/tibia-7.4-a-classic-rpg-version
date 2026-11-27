#include "otpch.h"

#include "guardian.h"
#include "tools.h"

#include <random>

#include <lua.hpp>

namespace {

constexpr uint8_t PROBLEM_FLAGS = Guardian::FLAG_FILES_MODIFIED | Guardian::FLAG_BOT_TOOL |
	Guardian::FLAG_MACRO_TOOL | Guardian::FLAG_INJECTED | Guardian::FLAG_NO_MANIFEST;

std::string randomToken()
{
	static std::random_device device;
	static const char digits[] = "0123456789abcdef";
	std::string token;
	token.reserve(Guardian::TOKEN_LENGTH);
	while (token.size() < Guardian::TOKEN_LENGTH) {
		uint32_t value = device();
		for (int i = 0; i < 8 && token.size() < Guardian::TOKEN_LENGTH; ++i) {
			token.push_back(digits[value & 0xF]);
			value >>= 4;
		}
	}
	return token;
}

void setField(lua_State* L, const char* key, double value)
{
	lua_pushnumber(L, value);
	lua_setfield(L, -2, key);
}

}

Guardian& Guardian::instance()
{
	static Guardian guardian;
	return guardian;
}

std::string Guardian::cleanDetail(const std::string& detail)
{
	// The text ends up in the staff log: keep printable ASCII only.
	std::string clean;
	clean.reserve(std::min(detail.size(), MAX_DETAIL));
	for (char c : detail) {
		if (clean.size() >= MAX_DETAIL) {
			break;
		}
		clean.push_back(c >= 0x20 && c < 0x7F ? c : '?');
	}
	return clean;
}

void Guardian::prune(int64_t now)
{
	if (now - prunedAt < 60 * 1000) {
		return;
	}
	prunedAt = now;
	for (auto it = sessions.begin(); it != sessions.end();) {
		if (now - it->second.lastBeatAt > SESSION_IDLE_MS) {
			it = sessions.erase(it);
		} else {
			++it;
		}
	}
	for (auto it = issuesByIp.begin(); it != issuesByIp.end();) {
		if (it->second.empty() || now - it->second.back() > 60 * 1000) {
			it = issuesByIp.erase(it);
		} else {
			++it;
		}
	}
}

std::string Guardian::issue(uint32_t ip, uint16_t launcherVersion, uint16_t clientVersion, uint8_t flags, const std::string& detail, int64_t now)
{
	prune(now);

	auto& recent = issuesByIp[ip];
	while (!recent.empty() && now - recent.front() > 60 * 1000) {
		recent.pop_front();
	}
	if (recent.size() >= MAX_ISSUES_PER_MINUTE || sessions.size() >= MAX_SESSIONS) {
		return std::string();
	}

	// One computer rarely needs more than a few launchers: reuse the oldest slot.
	size_t sameIp = 0;
	auto oldest = sessions.end();
	for (auto it = sessions.begin(); it != sessions.end(); ++it) {
		if (it->second.ip != ip) {
			continue;
		}
		++sameIp;
		if (oldest == sessions.end() || it->second.lastBeatAt < oldest->second.lastBeatAt) {
			oldest = it;
		}
	}
	if (sameIp >= MAX_SESSIONS_PER_IP && oldest != sessions.end()) {
		sessions.erase(oldest);
	}

	std::string token = randomToken();
	while (sessions.find(token) != sessions.end()) {
		token = randomToken();
	}

	Session session;
	session.ip = ip;
	session.createdAt = now;
	session.lastBeatAt = now;
	session.launcherVersion = launcherVersion;
	session.clientVersion = clientVersion;
	session.flags = flags;
	session.worst = flags & PROBLEM_FLAGS;
	session.detail = cleanDetail(detail);
	sessions.emplace(token, std::move(session));
	recent.push_back(now);
	return token;
}

bool Guardian::heartbeat(const std::string& token, uint32_t ip, uint8_t flags, const std::string& detail, int64_t now)
{
	auto it = sessions.find(token);
	if (it == sessions.end() || it->second.ip != ip) {
		return false;
	}
	Session& session = it->second;
	session.lastBeatAt = now;
	session.flags = flags;
	session.worst |= flags & PROBLEM_FLAGS;
	if (!detail.empty()) {
		session.detail = cleanDetail(detail);
	}
	++session.beats;
	prune(now);
	return true;
}

Guardian::Session* Guardian::findByPlayer(uint32_t playerId)
{
	if (playerId == 0) {
		return nullptr;
	}
	for (auto& entry : sessions) {
		if (entry.second.playerId == playerId) {
			return &entry.second;
		}
	}
	return nullptr;
}

int Guardian::luaBind(lua_State* L)
{
	// guardianBind(playerId, ip, token) -> "ok" | "unknown" | "ip"
	const uint32_t playerId = static_cast<uint32_t>(lua_tonumber(L, 1));
	const uint32_t ip = static_cast<uint32_t>(lua_tonumber(L, 2));
	size_t length = 0;
	const char* raw = lua_tolstring(L, 3, &length);
	Guardian& guardian = instance();

	if (!raw || length != TOKEN_LENGTH) {
		lua_pushliteral(L, "unknown");
		return 1;
	}
	auto it = guardian.sessions.find(std::string(raw, length));
	if (it == guardian.sessions.end()) {
		lua_pushliteral(L, "unknown");
		return 1;
	}
	if (it->second.ip != ip) {
		lua_pushliteral(L, "ip");
		return 1;
	}
	if (Session* previous = guardian.findByPlayer(playerId)) {
		previous->playerId = 0;
	}
	it->second.playerId = playerId;
	lua_pushliteral(L, "ok");
	return 1;
}

int Guardian::luaGetSession(lua_State* L)
{
	// getGuardianSession(playerId) -> table or nil
	const Session* session = instance().findByPlayer(static_cast<uint32_t>(lua_tonumber(L, 1)));
	if (!session) {
		lua_pushnil(L);
		return 1;
	}
	const int64_t now = OTSYS_TIME();
	lua_createtable(L, 0, 8);
	setField(L, "age", static_cast<double>(now - session->createdAt));
	setField(L, "beatAge", static_cast<double>(now - session->lastBeatAt));
	setField(L, "beats", session->beats);
	setField(L, "flags", session->flags);
	setField(L, "worst", session->worst);
	setField(L, "launcherVersion", session->launcherVersion);
	setField(L, "clientVersion", session->clientVersion);
	lua_pushlstring(L, session->detail.data(), session->detail.size());
	lua_setfield(L, -2, "detail");
	return 1;
}

int Guardian::luaForget(lua_State* L)
{
	// guardianUnbind(playerId): the session stays valid for the next login.
	if (Session* session = instance().findByPlayer(static_cast<uint32_t>(lua_tonumber(L, 1)))) {
		session->playerId = 0;
	}
	return 0;
}

void Guardian::registerLua(lua_State* L)
{
	lua_register(L, "guardianBind", Guardian::luaBind);
	lua_register(L, "getGuardianSession", Guardian::luaGetSession);
	lua_register(L, "guardianUnbind", Guardian::luaForget);
}
