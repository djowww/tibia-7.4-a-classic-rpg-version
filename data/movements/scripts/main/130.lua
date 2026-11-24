function onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if player and player:getStorageValue(260) == 1 then
		doRelocate(item:getPosition(),{x = 33095, y = 32590, z = 15})
		item:getPosition():sendMagicEffect(11)
		Game.sendMagicEffect({x = 33095, y = 32590, z = 15}, 11)
		player:setStorageValue(260, 0)
	else
		doRelocate(item:getPosition(),{x = 33073, y = 32604, z = 15})
		item:getPosition():sendMagicEffect(11)
		Game.sendMagicEffect({x = 33073, y = 32604, z = 15}, 11)
	end
end

function onAddItem(item, tileitem, position)
	doRelocate(item:getPosition(),{x = 33073, y = 32604, z = 15})
	item:getPosition():sendMagicEffect(11)
	Game.sendMagicEffect({x = 33073, y = 32604, z = 15}, 11)
end
