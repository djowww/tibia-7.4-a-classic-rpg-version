-- Food time left, plus where health and mana regeneration come from,
-- shown in the client's Skills window (opcode 131).
RegenStatus = {OPCODE = 131, SYNC_INTERVAL = 5}

local function secondsLeft(condition)
	if not condition then
		return 0
	end
	return math.max(0, math.floor(condition:getTicks() / 1000))
end

-- Same vocation the food condition uses (src/condition.cpp): a promoted
-- vocation without premium regenerates like the one it came from.
local function regenVocation(player)
	local vocation = player:getVocation()
	if vocation and not player:isPremium() then
		local demotion = vocation:getDemotion()
		if demotion and demotion:getId() ~= vocation:getId() then
			return demotion
		end
	end
	return vocation
end

-- Each source is {amount, seconds}; the client adds them up for display.
function RegenStatus.sources(player)
	local status = {
		food = {hp = {0, 0}, mana = {0, 0}},
		chests = {hp = {0, 0}, mana = {0, 0}},
	}
	local vocation = regenVocation(player)
	if vocation then
		status.food.hp = {vocation:getHealthGainAmount(), vocation:getHealthGainTicks()}
		status.food.mana = {vocation:getManaGainAmount(), vocation:getManaGainTicks()}
	end
	local chests = ExplorationChests
	if chests and chests.counts then
		local _, mana, life = chests.counts(player)
		-- One chest: 0.3 health every 10 s and 0.2 mana every 11 s.
		if life > 0 then status.chests.hp = {life * chests.LIFE_PER_MILLE / 10, 10} end
		if mana > 0 then status.chests.mana = {mana * chests.MANA_PER_MILLE / 10, 11} end
	end
	return status
end

function RegenStatus.send(player)
	if not player or not player:isPlayer() then
		return
	end
	local food = secondsLeft(player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT))
	player:sendExtendedOpcode(RegenStatus.OPCODE, json.encode({action = 'status', food = food,
		regen = RegenStatus.sources(player)}))
end
