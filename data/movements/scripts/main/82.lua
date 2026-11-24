function onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if player and player:getStorageValue(271) > 0 and player:getStorageValue(272) > 0 and player:getStorageValue(273) > 0 and player:getStorageValue(274) > 0 and player:getStorageValue(275) > 0 and player:getStorageValue(276) > 0 and player:getStorageValue(277) > 0 then
		doRelocate(item:getPosition(),{x = 33164, y = 32694, z = 14})
		item:getPosition():sendMagicEffect(11)
		Game.sendMagicEffect({x = 33164, y = 32694, z = 14}, 11)
		player:setStorageValue(271,0)
		player:setStorageValue(272,0)
		player:setStorageValue(273,0)
		player:setStorageValue(274,0)
		player:setStorageValue(275,0)
		player:setStorageValue(276,0)
		player:setStorageValue(277,0)
	else
		doRelocate(item:getPosition(),{x = 33259, y = 32707, z = 13})
		Game.sendMagicEffect({x = 33259, y = 32707, z = 13}, 11)
	end
end

function onAddItem(item, tileitem, position)
	doRelocate(tileitem:getPosition(),{x = 33259, y = 32707, z = 13})
	Game.sendMagicEffect({x = 33259, y = 32707, z = 13}, 11)
end
