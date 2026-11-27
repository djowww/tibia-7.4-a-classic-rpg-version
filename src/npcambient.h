// Falas espontaneas dos NPCs (data/npc/ambient.txt).
// Cada NPC fala sozinho de tempos em tempos, so quando ha jogador por perto
// e ninguem esta conversando com ele. As falas sao mandadas como "monster say":
// aparecem em cima do NPC e nao entram no chat Default.

#ifndef FS_NPCAMBIENT_H
#define FS_NPCAMBIENT_H

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

struct NpcAmbientLines
{
	std::vector<std::string> any;
	std::vector<std::string> day;
	std::vector<std::string> night;
};

class NpcAmbient
{
	public:
		// Intervalo entre duas falas do mesmo NPC.
		static constexpr int64_t MIN_INTERVAL = 60 * 1000;
		static constexpr int64_t MAX_INTERVAL = 180 * 1000;
		// Primeira fala depois que um jogador chega perto.
		static constexpr int64_t FIRST_MIN = 8 * 1000;
		static constexpr int64_t FIRST_MAX = 45 * 1000;
		// Pausa depois de uma conversa com jogador.
		static constexpr int64_t AFTER_TALK = 30 * 1000;
		// Dois NPCs na mesma area (16x16 sqm, mesmo andar) nao falam com menos de 12 s.
		static constexpr int64_t AREA_GAP = 12 * 1000;

		static bool load(const std::string& filename = "data/npc/ambient.txt");

		// Chave = nome do arquivo .npc sem pasta e sem extensao ("aldee").
		static const NpcAmbientLines* get(const std::string& key);

		// Escolhe uma fala (evita repetir a anterior). Vazio se nao ha fala.
		static const std::string* pick(const NpcAmbientLines& lines, bool night, int32_t& lastIndex);

		// Reserva a vez da area; false se outro NPC da area falou ha pouco.
		static bool claimArea(uint16_t x, uint16_t y, uint8_t z, int64_t now);

		static size_t size() {
			return table.size();
		}

		// So para teste: parse de um texto.
		static bool parse(const std::string& text, std::unordered_map<std::string, NpcAmbientLines>& out);

	private:
		static std::unordered_map<std::string, NpcAmbientLines> table;
		static std::unordered_map<uint32_t, int64_t> areaLast;
};

#endif
