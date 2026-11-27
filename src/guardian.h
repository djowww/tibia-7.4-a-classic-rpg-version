// Launcher sessions ("Guardian"). The official launcher asks for a session
// token before it starts the client and reports what it found on the
// computer: whether the client files match the signed release and whether a
// known bot tool is running. The client sends the token after login and the
// bot detector (data/lib/custom/guardian.lua) reads the session from here.
//
// Nothing here kicks or bans. Everything a launcher says can be faked by
// someone who rewrites it, so the reports only add to the staff alert.

#ifndef FS_GUARDIAN_H_5C0D7E0B9A4F4B0F8E7C2D61A3B4C5D6
#define FS_GUARDIAN_H_5C0D7E0B9A4F4B0F8E7C2D61A3B4C5D6

#include <cstdint>
#include <deque>
#include <string>
#include <unordered_map>

struct lua_State;

class Guardian
{
	public:
		enum Flag : uint8_t {
			FLAG_FILES_OK = 1 << 0,       // every client file matches the signed list
			FLAG_FILES_MODIFIED = 1 << 1, // a file differs or an unexpected script was added
			FLAG_BOT_TOOL = 1 << 2,       // a known bot is running
			FLAG_MACRO_TOOL = 1 << 3,     // a generic macro tool is running
			FLAG_INJECTED = 1 << 4,       // a known bot library is loaded inside the client
			FLAG_NO_MANIFEST = 1 << 5,    // the install has no signed file list
		};

		static constexpr size_t TOKEN_LENGTH = 32;
		static constexpr size_t MAX_DETAIL = 300;
		static constexpr uint16_t HEARTBEAT_SECONDS = 60;
		static constexpr int64_t SESSION_IDLE_MS = 10 * 60 * 1000; // dropped after this long without a heartbeat
		static constexpr size_t MAX_SESSIONS_PER_IP = 8;
		static constexpr size_t MAX_ISSUES_PER_MINUTE = 6; // per IP
		static constexpr size_t MAX_SESSIONS = 20000;

		struct Session {
			uint32_t ip = 0;
			int64_t createdAt = 0;
			int64_t lastBeatAt = 0;
			uint16_t launcherVersion = 0;
			uint16_t clientVersion = 0;
			uint8_t flags = 0;  // latest report
			uint8_t worst = 0;  // every problem flag ever reported in this session
			std::string detail; // latest non-empty explanation from the launcher
			uint32_t playerId = 0;
			uint32_t beats = 0;
		};

		static Guardian& instance();

		// All of these run on the dispatcher thread.
		// Returns the new token, or an empty string when the IP asks too often.
		std::string issue(uint32_t ip, uint16_t launcherVersion, uint16_t clientVersion, uint8_t flags, const std::string& detail, int64_t now);
		bool heartbeat(const std::string& token, uint32_t ip, uint8_t flags, const std::string& detail, int64_t now);

		static void registerLua(lua_State* L);

	private:
		Guardian() = default;
		void prune(int64_t now);
		Session* findByPlayer(uint32_t playerId);
		static std::string cleanDetail(const std::string& detail);

		static int luaBind(lua_State* L);
		static int luaGetSession(lua_State* L);
		static int luaForget(lua_State* L);

		std::unordered_map<std::string, Session> sessions;
		std::unordered_map<uint32_t, std::deque<int64_t>> issuesByIp;
		int64_t prunedAt = 0;
};

#endif
