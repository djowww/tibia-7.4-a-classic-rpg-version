function Game.sendMagicEffect(position, effect)
	local pos = Position(position)
	pos:sendMagicEffect(effect)
end

function Game.removeItemsOnMap(position)
	local tile = Tile(position)
	if not tile then
		return
	end
	local tileCount = tile:getThingCount()
	local i = 0
	while i < tileCount do
		local tileItem = tile:getThing(i)
		if tileItem and not tileItem:isCreature() and ItemType(tileItem:getId()):isMovable() then
			tileItem:remove()
		else
			i = i + 1
		end
	end
end

function Game.transformItemOnMap(position, itemId, toItemId, subtype)
	if not subtype then
		subtype = -1
	end

	local tile = Tile(position)
	local item = tile and tile:getItemById(itemId)
	if item then
		item:transform(toItemId, subtype)
		item:decay()
	end
	return item
end

function Game.removeItemOnMap(position, itemId, subtype)
	if not subtype then
		subtype = -1
	end
	
	local tile = Tile(position)
	local item = tile and tile:getItemById(itemId, subtype)
	if item then
		item:remove()
	end
	return item ~= nil
end

function Game.isItemThere(position, itemId)
	local tile = Tile(position)
	return tile ~= nil and tile:getItemById(itemId) ~= nil
end

function Game.isPlayerThere(position)
	local tile = Tile(position)
	local creatures = tile and tile:getCreatures() or {}
	for _, creature in ipairs(creatures) do
		if creature:isPlayer() then
			return true
		end
	end
	return false
end

function Game.broadcastMessage(message, messageType)
	if messageType == nil then
		messageType = MESSAGE_STATUS_WARNING
	end

	for _, player in ipairs(Game.getPlayers()) do
		player:sendTextMessage(messageType, message)
	end
end

function Game.convertIpToString(ip)
	local band = bit.band
	local rshift = bit.rshift
	return string.format("%d.%d.%d.%d",
		band(ip, 0xFF),
		band(rshift(ip, 8), 0xFF),
		band(rshift(ip, 16), 0xFF),
		rshift(ip, 24)
	)
end

if not globalStorageTable then
	globalStorageTable = {}
end

function Game.getStorageValue(key)
	return globalStorageTable[key]
end

function Game.setStorageValue(key, value)
	globalStorageTable[key] = value
end

-- Slow-script diagnostics are scoped to protected invocations in the C++ core.
