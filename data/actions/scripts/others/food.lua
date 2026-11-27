local MAX_FOOD_SECONDS = 60 * 60 -- food stacks up to 60 minutes

function onUse(player, item, fromPosition, target, toPosition)
	local itemType = ItemType(item:getId())
	local condition = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if condition and math.floor(condition:getTicks() / 1000 + (itemType:getNutrition() * 12)) > MAX_FOOD_SECONDS then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "You are full.")
	else
		player:feed(itemType:getNutrition() * 12)
		item:remove(1)
		RegenStatus.send(player)
	end
	
	return true
end
