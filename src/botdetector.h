/**
 * Behaviour-based bot detector.
 *
 * Records the arrival time of every action packet a player sends and how
 * fast the player reacts after losing health. It never punishes anybody:
 * Lua (data/lib/custom/botDetector.lua) reads the statistics, scores them
 * and alerts the staff.
 */

#ifndef FS_BOTDETECTOR_H
#define FS_BOTDETECTOR_H

#include <array>
#include <cstdint>
#include <mutex>
#include <unordered_map>

struct lua_State;

class BotDetector
{
	public:
		enum Category : uint8_t {
			CAT_WALK,
			CAT_AUTOWALK,
			CAT_TURN,
			CAT_USE,
			CAT_USEWITH,
			CAT_ATTACK,
			CAT_SAY,
			CAT_MOVE,
			CAT_COUNT,
			CAT_NONE = 0xFF,
		};

		static constexpr size_t RING_SIZE = 48;
		// Intervals outside this window are not "rhythm": shorter ones come
		// from held keys (client hotkey repeat is 100-200 ms), longer ones
		// are simply pauses.
		static constexpr int64_t MIN_INTERVAL = 300;
		static constexpr int64_t MAX_INTERVAL = 15000;
		// Only the first heal-like action this long after a hit counts.
		static constexpr int64_t MAX_REACTION = 2000;
		// Reactions only count when no heal-like action came this soon before the hit.
		static constexpr int64_t QUIET_BEFORE_HIT = 1000;

		struct Ring {
			std::array<int32_t, RING_SIZE> values {};
			uint32_t count = 0; // total ever pushed
			void push(int32_t v) { values[count % RING_SIZE] = v; ++count; }
			size_t size() const { return count < RING_SIZE ? count : RING_SIZE; }
		};

		struct Record {
			std::array<int64_t, CAT_COUNT> lastAt {};
			std::array<Ring, CAT_COUNT> intervals;
			Ring reactions;
			int64_t damagedAt = 0;   // last health loss not yet answered
			int32_t lastHealth = -1;
			int64_t lastActionAt = 0;
			int64_t firstSeenAt = 0;
			uint64_t packets = 0;
			// burst = more than BURST_LIMIT action packets inside one second
			int64_t burstWindowAt = 0;
			uint32_t burstWindowCount = 0;
			uint32_t bursts = 0;
			// Client signature: what the official client (OTCv8) always sends
			// and a headless bot usually does not.
			uint32_t newPings = 0;   // 0x40, OTCv8 extended ping with ping and fps
			uint32_t fpsMax = 0;
			Ring localPings;         // ping the client reports, in ms
			uint32_t extOpcodes = 0; // 0x32, custom client modules
			uint32_t oldSteps = 0;   // 0x65-0x6D, one packet per step
			uint32_t newSteps = 0;   // 0x45, OTCv8 new walking
		};

		static constexpr uint32_t BURST_LIMIT = 12;

		static BotDetector& instance();

		static Category categorize(uint8_t recvbyte);

		// network thread
		void onPacket(uint32_t playerId, uint8_t recvbyte);
		void onNewPing(uint32_t playerId, uint16_t localPing, uint16_t fps);
		// dispatcher thread
		void onStats(uint32_t playerId, int32_t health);
		void forget(uint32_t playerId);

		static void registerLua(lua_State* L);

	private:
		BotDetector() = default;
		void pruneLocked(int64_t now);
		static int luaGetStats(lua_State* L);
		static int luaForget(lua_State* L);

		std::mutex lock;
		std::unordered_map<uint32_t, Record> records;
		uint32_t sincePrune = 0;
};

#endif
