-- Regras de caca do Antigas 7.4.
-- Noite de caca: das 19:00 as 05:00 do jogo os monstros dao 25% a mais de XP
-- (loot, dano e respawn da noite ficam no C++, ver src/daynight.h).
-- Cansaco: matar a mesma criatura sem parar tira 1% da XP a cada 20 mortes
-- acumuladas, ate -40%. O cansaco cai 100 mortes por hora (zera em ate 8 horas).
-- Fica na memoria do servidor: sobrevive a relog, mas o restart diario zera.

HUNT_NIGHT_START = 19 * 60
HUNT_NIGHT_END = 5 * 60
HUNT_NIGHT_EXP_PERCENT = 25

HUNT_FATIGUE_KILLS_PER_PERCENT = 20
HUNT_FATIGUE_MAX_PERCENT = 40
HUNT_FATIGUE_RECOVERY_PER_HOUR = 100

HuntFatigue = HuntFatigue or {}

function isHuntNight()
	local minute = getWorldTime()
	return minute >= HUNT_NIGHT_START or minute < HUNT_NIGHT_END
end

local function fatigueEntry(player, name, now)
	local guid = player:getGuid()
	local list = HuntFatigue[guid]
	if not list then
		list = {}
		HuntFatigue[guid] = list
	end
	local entry = list[name]
	if not entry then
		entry = {points = 0, time = now}
		list[name] = entry
	end
	local recovered = (now - entry.time) * HUNT_FATIGUE_RECOVERY_PER_HOUR / 3600
	entry.points = math.max(0, entry.points - recovered)
	entry.time = now
	return entry
end

local function fatiguePercent(points)
	return math.min(HUNT_FATIGUE_MAX_PERCENT, math.floor(points / HUNT_FATIGUE_KILLS_PER_PERCENT))
end

-- Conta uma morte e devolve quanto (%) da XP o cansaco tira.
function Player:addHuntFatigue(monsterName)
	local now = os.time()
	local name = monsterName:lower()
	local entry = fatigueEntry(self, name, now)
	local before = fatiguePercent(entry.points)
	entry.points = math.min(entry.points + 1, HUNT_FATIGUE_MAX_PERCENT * HUNT_FATIGUE_KILLS_PER_PERCENT)
	local after = fatiguePercent(entry.points)
	if after > before and after % 5 == 0 then
		self:sendTextMessage(MESSAGE_STATUS_DEFAULT, string.format("You are getting tired of hunting %s: -%d%% experience from them. Hunt something else to recover.", name, after))
	end
	return before
end

-- Lista das criaturas que estao cansando o jogador (para !fatigue).
function Player:getHuntFatigueList()
	local list = HuntFatigue[self:getGuid()]
	local out = {}
	if not list then
		return out
	end
	local now = os.time()
	for name in pairs(list) do
		local percent = fatiguePercent(fatigueEntry(self, name, now).points)
		if percent > 0 then
			out[#out + 1] = {name = name, percent = percent}
		end
	end
	table.sort(out, function(a, b) return a.percent > b.percent end)
	return out
end

-- Aplica noite e cansaco na XP de um monstro (antes dos bonus online e bestiary).
function Player:applyHuntRules(exp, monster)
	local percent = 100
	if isHuntNight() then
		percent = percent + HUNT_NIGHT_EXP_PERCENT
	end
	percent = percent - self:addHuntFatigue(monster:getName())
	-- Arredonda para o mais proximo: com floor, -1% numa criatura de 5 XP (rat)
	-- virava 4 XP, ou seja -20%.
	return math.floor(exp * percent / 100 + 0.5)
end
