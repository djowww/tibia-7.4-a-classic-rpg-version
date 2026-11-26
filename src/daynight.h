// Ciclo de dia e noite do Antigas 7.4.
// O dia do jogo tem 1440 minutos: o dia (06:00-18:00) e a noite (18:00-06:00)
// duram 2 horas reais cada, entao um dia completo leva 4 horas reais.
// Amanhecer (05:00-07:00) e entardecer (17:00-19:00) clareiam e escurecem aos poucos.

#ifndef FS_DAYNIGHT_H
#define FS_DAYNIGHT_H

#include <cstdint>

namespace DayNight {

static constexpr int32_t MINUTES_PER_DAY = 1440;
static constexpr int64_t CYCLE_SECONDS = 4 * 60 * 60;
static constexpr int32_t SUNRISE = 6 * 60;
static constexpr int32_t SUNSET = 18 * 60;
static constexpr int32_t TWILIGHT = 60;
static constexpr int32_t LIGHT_DAY = 250;
static constexpr int32_t LIGHT_NIGHT = 40;

enum class Phase { Day, Night, Sunrise, Sunset };

// Minuto do dia do jogo (0-1439) para um instante real em segundos, mais um ajuste em minutos do jogo.
inline int32_t worldMinute(int64_t unixSeconds, int32_t offsetMinutes = 0)
{
	int64_t inCycle = unixSeconds % CYCLE_SECONDS;
	if (inCycle < 0) {
		inCycle += CYCLE_SECONDS;
	}
	int64_t minute = inCycle * MINUTES_PER_DAY / CYCLE_SECONDS + offsetMinutes;
	minute %= MINUTES_PER_DAY;
	if (minute < 0) {
		minute += MINUTES_PER_DAY;
	}
	return static_cast<int32_t>(minute);
}

inline Phase phaseAt(int32_t minute)
{
	if (minute >= SUNRISE - TWILIGHT && minute < SUNRISE + TWILIGHT) {
		return Phase::Sunrise;
	}
	if (minute >= SUNSET - TWILIGHT && minute < SUNSET + TWILIGHT) {
		return Phase::Sunset;
	}
	if (minute >= SUNRISE + TWILIGHT && minute < SUNSET - TWILIGHT) {
		return Phase::Day;
	}
	return Phase::Night;
}

inline int32_t lightLevelAt(int32_t minute)
{
	switch (phaseAt(minute)) {
		case Phase::Day:
			return LIGHT_DAY;
		case Phase::Night:
			return LIGHT_NIGHT;
		case Phase::Sunrise:
			return LIGHT_NIGHT + (LIGHT_DAY - LIGHT_NIGHT) * (minute - (SUNRISE - TWILIGHT)) / (2 * TWILIGHT);
		case Phase::Sunset:
		default:
			return LIGHT_DAY - (LIGHT_DAY - LIGHT_NIGHT) * (minute - (SUNSET - TWILIGHT)) / (2 * TWILIGHT);
	}
}

} // namespace DayNight

#endif
