-- Food and water time left, shown in the client's Skills window (opcode 131).
RegenStatus = {OPCODE = 131, WATER_SUBID = 17870, SYNC_INTERVAL = 5}

local function secondsLeft(condition)
	if not condition then
		return 0
	end
	return math.max(0, math.floor(condition:getTicks() / 1000))
end

function RegenStatus.send(player)
	if not player or not player:isPlayer() then
		return
	end
	local food = secondsLeft(player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT))
	local water = secondsLeft(player:getCondition(CONDITION_REGENERATION, CONDITIONID_COMBAT, RegenStatus.WATER_SUBID))
	player:sendExtendedOpcode(RegenStatus.OPCODE, json.encode({action = 'status', food = food, water = water}))
end
