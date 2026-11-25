-- Run from the server root with LuaJIT or Lua 5.2. No server is needed.
-- Covers data/movements/lib/custom/map_tiles.lua and its movements.xml registrations.
local relocations, effects = {}, {}
doRelocate = function(from, to) relocations[#relocations + 1] = {from = from, to = to} end
Game = {sendMagicEffect = function(pos, effect) effects[#effects + 1] = {pos = pos, effect = effect} end}
dofile('data/movements/lib/custom/map_tiles.lua')

local function check(name, fn)
	local ok, err = pcall(fn)
	if not ok then error(name .. ': ' .. tostring(err)) end
	print('PASS: ' .. name)
end
local function reset() relocations, effects = {}, {} end
local function same(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
local TILE = {x = 100, y = 200, z = 7}
local function tile(id)
	return {getMovementId = function() return id end, getPosition = function() return TILE end}
end
local function creature(isPlayer, storage)
	local self = {storage = storage or {}}
	function self:isPlayer() return isPlayer end
	function self:getPlayer() return isPlayer and self or nil end
	function self:getStorageValue(key) return self.storage[key] or -1 end
	function self:setStorageValue(key, value) self.storage[key] = value end
	return self
end

check('movements.xml registers every rule and only existing scripts', function()
	local file = assert(io.open('data/movements/movements.xml', 'rb'))
	local xml = file:read('*a')
	file:close()
	local registered = {teleport = {}, storage_flag = {}}
	for attributes in xml:gmatch('<movevent ([^>]-)/>') do
		local folder, script = attributes:match('script="(%a+)/([%w_]+)%.lua"')
		if folder == 'main' or folder == 'custom' then
			local id = tonumber(attributes:match('movementid="(%d+)"'))
			local event = attributes:match('event="(%a+)"')
			local handle = assert(io.open('data/movements/scripts/' .. folder .. '/' .. script .. '.lua', 'rb'),
				'missing script ' .. folder .. '/' .. script .. '.lua')
			handle:close()
			if registered[script] then
				registered[script][id] = registered[script][id] or {}
				registered[script][id][event] = true
			end
		end
	end
	for id, rule in pairs(MapTiles.teleports) do
		local events = assert(registered.teleport[id], 'teleport rule without registration: ' .. id)
		assert(events.StepIn, 'teleport rule must be registered for StepIn: ' .. id)
		assert((rule.addItem ~= nil) == (events.AddItem == true), 'AddItem registration mismatch: ' .. id)
	end
	for id in pairs(registered.teleport) do
		assert(MapTiles.teleports[id], 'teleport registration without rule: ' .. id)
	end
	for id in pairs(MapTiles.storageFlags) do
		assert(registered.storage_flag[id] and registered.storage_flag[id].StepIn,
			'storage flag rule without StepIn registration: ' .. id)
	end
	for id in pairs(registered.storage_flag) do
		assert(MapTiles.storageFlags[id], 'storage flag registration without rule: ' .. id)
	end
end)

check('every rule is well formed', function()
	local function position(pos) return type(pos) == 'table' and pos.x and pos.y and pos.z end
	local function teleport(rule, id)
		assert(position(rule.to), 'teleport without destination: ' .. id)
		assert(rule.from == nil or position(rule.from), 'bad source: ' .. id)
		for _, entry in ipairs(rule.effects or {}) do
			assert(type(entry.effect) == 'number' and (entry.pos == nil or position(entry.pos)), 'bad effect: ' .. id)
		end
	end
	for id, rule in pairs(MapTiles.teleports) do
		teleport(rule, id)
		if type(rule.addItem) == 'table' then teleport(rule.addItem, id) end
	end
	for id, rule in pairs(MapTiles.storageFlags) do
		assert(type(rule.storage) == 'number' and type(rule.value) == 'number' and type(rule.effect) == 'number',
			'bad storage flag: ' .. id)
	end
end)

check('teleport relocates the tile and shows effects on the tile and the destination', function()
	-- Former main/132.lua.
	local rule = MapTiles.teleports[132]
	reset()
	MapTiles.teleportOnStepIn(creature(false), tile(132))
	assert(#relocations == 1 and relocations[1].from == TILE and same(relocations[1].to, rule.to))
	assert(#effects == 2 and effects[1].pos == TILE and same(effects[2].pos, rule.to))
	reset()
	MapTiles.teleportOnAddItem(tile(132))
	assert(#relocations == 1 and #effects == 2, 'dropped items follow the same rule')
end)

check('playerOnly filters stepping monsters but not dropped items', function()
	-- Former main/2011.lua: effect 13 when stepping, 14 for dropped items.
	reset()
	MapTiles.teleportOnStepIn(creature(false), tile(2011))
	assert(#relocations == 0 and #effects == 0)
	MapTiles.teleportOnStepIn(creature(true), tile(2011))
	assert(#relocations == 1 and effects[1].effect == 13)
	reset()
	MapTiles.teleportOnAddItem(tile(2011))
	assert(#relocations == 1 and effects[1].effect == 14)
end)

check('fixed source tiles and step-only teleports keep their behaviour', function()
	-- Former main/185.lua: relocates another tile, only when stepped on.
	reset()
	MapTiles.teleportOnStepIn(creature(false), tile(185))
	assert(same(relocations[1].from, {x = 32176, y = 31864, z = 15}) and same(relocations[1].to, {x = 32176, y = 31870, z = 15}))
	reset()
	MapTiles.teleportOnAddItem(tile(185))
	assert(#relocations == 0, 'tile without addItem must ignore dropped items')
	MapTiles.teleportOnStepIn(creature(true), tile(999999))
	assert(#relocations == 0, 'unknown movement id must be ignored')
end)

check('storage flags are set once and only for players', function()
	-- Former main/48.lua: storage 41 below 1 -> 1, effect 7 on a fixed tile.
	reset()
	MapTiles.storageFlagOnStepIn(creature(false), tile(48))
	assert(#effects == 0)
	local player = creature(true)
	MapTiles.storageFlagOnStepIn(player, tile(48))
	assert(player.storage[41] == 1 and #effects == 1 and effects[1].effect == 7 and same(effects[1].pos, {x = 32477, y = 31900, z = 1}))
	MapTiles.storageFlagOnStepIn(player, tile(48))
	assert(#effects == 1, 'an already set flag must not replay the effect')
	-- Former main/138.lua: unconditional flag, effect on the tile itself.
	reset()
	player = creature(true, {[277] = 1})
	MapTiles.storageFlagOnStepIn(player, tile(138))
	assert(player.storage[277] == 1 and #effects == 1 and effects[1].pos == TILE and effects[1].effect == 13)
end)
print('Map tile tests passed')
