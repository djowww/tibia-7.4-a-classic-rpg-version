-- Rules live in data/movements/lib/map_tiles.lua, keyed by movement id.
function onStepIn(creature, item, position, fromPosition)
	MapTiles.storageFlagOnStepIn(creature, item)
end
