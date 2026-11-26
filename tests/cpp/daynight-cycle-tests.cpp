#include "daynight.h"

#include <iostream>

namespace {

int failures = 0;

void expect(bool condition, const char* message)
{
	if (!condition) {
		std::cerr << "FAIL: " << message << '\n';
		++failures;
	}
}

} // namespace

int main()
{
	using namespace DayNight;

	// 4 horas reais = 1 dia do jogo; 2 horas reais = 12 horas do jogo.
	expect(worldMinute(0) == 0, "inicio do ciclo e meia-noite");
	expect(worldMinute(2 * 60 * 60) == 720, "2 h reais depois e meio-dia");
	expect(worldMinute(4 * 60 * 60) == 0, "4 h reais fecham o dia");
	expect(worldMinute(10) == 1, "10 s reais = 1 minuto do jogo");
	expect(worldMinute(0, 360) == 360, "ajuste de hora funciona");
	expect(worldMinute(0, -60) == 1380, "ajuste negativo volta para 23:00");

	// Dia de 12 h do jogo (06:00-18:00) dura 2 h reais.
	int dayTicks = 0;
	for (int64_t s = 0; s < CYCLE_SECONDS; s += 10) {
		int32_t m = worldMinute(s);
		if (m >= SUNRISE && m < SUNSET) {
			++dayTicks;
		}
	}
	expect(dayTicks * 10 == 2 * 60 * 60, "metade clara dura 2 h reais");

	expect(lightLevelAt(0) == LIGHT_NIGHT, "meia-noite escura");
	expect(lightLevelAt(720) == LIGHT_DAY, "meio-dia claro");
	expect(lightLevelAt(SUNRISE - TWILIGHT) == LIGHT_NIGHT, "amanhecer comeca escuro");
	expect(lightLevelAt(SUNRISE) == (LIGHT_DAY + LIGHT_NIGHT) / 2, "06:00 a meio caminho");
	expect(lightLevelAt(SUNSET) == (LIGHT_DAY + LIGHT_NIGHT) / 2, "18:00 a meio caminho");
	expect(lightLevelAt(SUNRISE + TWILIGHT) == LIGHT_DAY, "07:00 ja e dia");
	expect(lightLevelAt(SUNSET + TWILIGHT) == LIGHT_NIGHT, "19:00 ja e noite");

	// Transicao suave: de um minuto para o outro a luz muda no maximo 2 niveis.
	for (int32_t m = 1; m < MINUTES_PER_DAY; ++m) {
		int32_t diff = lightLevelAt(m) - lightLevelAt(m - 1);
		if (diff > 2 || diff < -2) {
			std::cerr << "salto de luz em " << m << ": " << diff << '\n';
			++failures;
			break;
		}
		int32_t level = lightLevelAt(m);
		expect(level >= LIGHT_NIGHT && level <= LIGHT_DAY, "luz dentro dos limites");
	}

	if (failures != 0) {
		return 1;
	}
	std::cout << "daynight-cycle: ok\n";
	return 0;
}
