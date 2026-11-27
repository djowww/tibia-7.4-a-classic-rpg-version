-- Noite de caca, cansaco por criatura e recompensa do PK.
MESSAGE_STATUS_DEFAULT = 17
MESSAGE_STATUS_WARNING = 18
MESSAGE_EVENT_ADVANCE = 19
Player = {}
local worldMinute = 12 * 60
function getWorldTime() return worldMinute end
local clock = 1000000
os.time = function() return clock end

dofile("data/lib/custom/huntRules.lua")
dofile("data/lib/custom/bounty.lua")

local function makePlayer(guid, level)
	local p = {guid = guid, level = level or 50, storage = {}, bank = 0, money = 0, messages = {}}
	return setmetatable(p, {__index = function(t, k)
		local own = {
			getGuid = function(self) return self.guid end,
			getLevel = function(self) return self.level end,
			getName = function(self) return "P" .. self.guid end,
			isPlayer = function() return true end,
			getMaster = function() return nil end,
			sendTextMessage = function(self, _, text) self.messages[#self.messages + 1] = text end,
			getStorageValue = function(self, key) return self.storage[key] or -1 end,
			setStorageValue = function(self, key, value) self.storage[key] = value end,
			getBankBalance = function(self) return self.bank end,
			setBankBalance = function(self, value) self.bank = value end,
			getMoney = function(self) return self.money end,
			removeMoney = function(self, n) self.money = self.money - n return true end,
			save = function(self) self.saved = (self.saved or 0) + 1 return true end,
		}
		return own[k] or Player[k]
	end})
end

local rat = {getName = function() return "Rat" end}

-- Dia: XP normal. Noite: +25%.
local p = makePlayer(1)
assert(p:applyHuntRules(100, rat) == 100, "day XP must be unchanged")
worldMinute = 20 * 60
assert(isHuntNight(), "20:00 is a hunting night")
assert(p:applyHuntRules(100, rat) == 125, "night XP must be +25%")
worldMinute = 4 * 60 + 59
assert(isHuntNight(), "04:59 is still night")
worldMinute = 5 * 60
assert(not isHuntNight(), "05:00 ends the night")

-- Cansaco: depois de 20 mortes, -1%; teto de -40%.
local q = makePlayer(2)
for _ = 1, 20 do q:applyHuntRules(100, rat) end
assert(q:applyHuntRules(1000, rat) == 990, "21st kill must give -1%")
assert(q:applyHuntRules(5, rat) == 5, "-1% on a 5 XP rat must round to 5, not 4")
for _ = 1, 2000 do q:applyHuntRules(100, rat) end
assert(q:applyHuntRules(1000, rat) == 600, "fatigue caps at -40%")
assert(#q.messages > 0, "player must be warned about fatigue")
-- Outra criatura nao e afetada.
assert(q:applyHuntRules(1000, {getName = function() return "Troll" end}) == 1000, "fatigue is per creature")
-- Recupera 100 mortes por hora: em 8 horas zera.
clock = clock + 8 * 3600
assert(q:applyHuntRules(1000, rat) == 1000, "fatigue must recover in 8 hours")
clock = clock + 3600
assert(#q:getHuntFatigueList() == 0, "recovered fatigue is not listed")

-- Recompensa: cobra do banco e depois da mochila.
local killer = makePlayer(3, 40)
killer.bank, killer.money = 3000, 5000
assert(killer:chargeBounty(40 * BOUNTY_GOLD_PER_LEVEL) == 4000, "charges the full bounty")
assert(killer.bank == 0 and killer.money == 4000, "bank first, then carried gold")
local poor = makePlayer(4, 40)
assert(poor:chargeBounty(4000) == 0, "nothing to charge from a broke player")

-- Fluxo completo do onDeath.
Game = {broadcastMessage = function() end}
dofile("data/creaturescripts/scripts/custom/bounty.lua")
local victim = makePlayer(5, 30)
onDeath(victim, nil, killer, killer, true, true)
assert(killer:getBounty() == 4000, "unjustified kill puts the murderer's gold on his head")
local hunter = makePlayer(6, 60)
onDeath(killer, nil, hunter, hunter, false, false)
assert(hunter.bank == 4000 and killer:getBounty() == 0, "hunter collects the bounty in the bank")
assert((hunter.saved or 0) >= 1, "hunter is saved right after collecting the bounty")

print("hunt-rules-tests: ok")
