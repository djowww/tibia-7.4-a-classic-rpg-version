function onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if player then
		player:setStorageValue(260, 1)
	end
	return true
end
