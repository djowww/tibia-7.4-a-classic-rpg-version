// Preco dinamico dos NPCs do Antigas 7.4.
// Cada unidade vendida a um NPC aumenta a "saturacao" daquele item no servidor
// todo. A cada 20 unidades o NPC paga 1% a menos, ate pagar so metade. A
// saturacao cai pela metade a cada 3 horas, entao o preco volta sozinho.
// Fica so na memoria: o restart diario zera o mercado.

#ifndef FS_NPCMARKET_H
#define FS_NPCMARKET_H

#include <cmath>
#include <cstdint>
#include <ctime>
#include <unordered_map>

namespace NpcMarket {

static constexpr double UNITS_PER_PERCENT = 20.0;
static constexpr int32_t MIN_PERCENT = 50;
static constexpr double HALF_LIFE_SECONDS = 3.0 * 60 * 60;

struct Entry {
	double pressure = 0.0;
	int64_t updated = 0;
};

inline std::unordered_map<uint16_t, Entry>& entries()
{
	static std::unordered_map<uint16_t, Entry> market;
	return market;
}

inline void decay(Entry& entry, int64_t now)
{
	if (entry.updated != 0 && now > entry.updated) {
		entry.pressure *= std::pow(0.5, static_cast<double>(now - entry.updated) / HALF_LIFE_SECONDS);
	}
	entry.updated = now;
}

inline int32_t percentFor(double pressure)
{
	int32_t percent = 100 - static_cast<int32_t>(pressure / UNITS_PER_PERCENT);
	return percent < MIN_PERCENT ? MIN_PERCENT : (percent > 100 ? 100 : percent);
}

// Quanto (em %) os NPCs pagam hoje por este item.
inline int32_t pricePercent(uint16_t itemId)
{
	auto it = entries().find(itemId);
	if (it == entries().end()) {
		return 100;
	}
	decay(it->second, static_cast<int64_t>(std::time(nullptr)));
	return percentFor(it->second.pressure);
}

inline void recordSale(uint16_t itemId, uint32_t units)
{
	Entry& entry = entries()[itemId];
	decay(entry, static_cast<int64_t>(std::time(nullptr)));
	entry.pressure += units;
}

inline int64_t applyPercent(int64_t price, int32_t percent)
{
	if (price <= 0 || percent >= 100) {
		return price;
	}
	// Arredonda para o mais proximo: com divisao inteira, -1% num item de 4 gold
	// ja pagava 3 (-25%).
	int64_t paid = (price * percent + 50) / 100;
	return paid < 1 ? 1 : paid;
}

} // namespace NpcMarket

#endif
