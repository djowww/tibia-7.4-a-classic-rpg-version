-- Rules live in data/movements/lib/map_tiles.lua, keyed by movement id.
function onStepIn(creature, item, position, fromPosition)
	MapTiles.teleportOnStepIn(creature, item)
end

function onAddItem(item, tileitem, position)
	MapTiles.teleportOnAddItem(tileitem)
end
