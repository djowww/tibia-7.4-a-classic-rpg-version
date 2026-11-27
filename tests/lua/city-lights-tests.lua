-- Luzes das cidades: acendem no fim da tarde, ninguem apaga a noite, de dia voltam ao original.
local worldTime = 12 * 60
getWorldTime = function() return worldTime end

local pending = {}
addEvent = function(fn, delay, ...)
	pending[#pending + 1] = {fn = fn, args = {...}}
end
local function runEvents()
	while #pending > 0 do
		local event = table.remove(pending, 1)
		event.fn(unpack(event.args))
	end
end

Position = function(x, y, z) return {x = x, y = y, z = z} end

local tiles = {}
local function tileKey(x, y, z) return x .. ':' .. y .. ':' .. z end
local function newItem(id, x, y, z)
	local item = {id = id}
	function item:getId() return self.id end
	function item:transform(newId) self.id = newId end
	function item:getPosition() return Position(x, y, z) end
	tiles[tileKey(x, y, z)] = item
	return item
end
Tile = function(pos)
	local item = tiles[tileKey(pos.x, pos.y, pos.z)]
	if not item then return nil end
	return {getItemById = function(_, id) return item.id == id and item or nil end}
end

-- Thais com 400 postes apagados, um lampiao ja aceso e um poste longe (fora da cidade).
local lamps = {}
for i = 1, 400 do
	lamps[i] = newItem(2108, 32300 + (i % 100), 32200 + math.floor(i / 100), 7)
end
local litLamp = newItem(2908, 32369, 32240, 7)
local farLamp = newItem(2108, 31000, 31000, 7)

local searched
Game = {
	getTowns = function()
		return {{getName = function() return "Thais" end, getTemplePosition = function() return Position(32369, 32241, 7) end}}
	end,
	findItemsInArea = function(from, to, ids, skipHouses)
		searched = {from = from, to = to, skipHouses = skipHouses}
		local wanted = {}
		for _, id in ipairs(ids) do wanted[id] = true end
		local found = {}
		for _, item in pairs(tiles) do
			local p = item:getPosition()
			if wanted[item.id] and p.x >= from.x and p.x <= to.x and p.y >= from.y and p.y <= to.y and p.z >= from.z and p.z <= to.z then
				found[#found + 1] = {x = p.x, y = p.y, z = p.z, id = item.id}
			end
		end
		return found
	end,
}

dofile('data/lib/custom/cityLights.lua')

local player = {getGroup = function() return {getAccess = function() return false end} end}
local gm = {getGroup = function() return {getAccess = function() return true end} end}

assert(CityLights.scan() == 401, "only lights near the temple")
assert(searched.skipHouses == true and searched.to.z == 7 and searched.from.z == 0)

-- meio-dia: nada muda
CityLights.update()
runEvents()
assert(lamps[1].id == 2108 and litLamp.id == 2908)
assert(not CityLights.blocksUse(player, litLamp), "day lights work as usual")

-- 17:29 ainda apagado, 17:30 acende tudo em lotes
worldTime = 17 * 60 + 29
CityLights.update()
assert(CityLights.lit == false)
worldTime = 17 * 60 + 30
CityLights.update()
local litNow = 0
for i = 1, 400 do if lamps[i].id == 2109 then litNow = litNow + 1 end end
-- o lampiao ja aceso pode cair no primeiro lote (149 ou 150 trocados)
assert(litNow >= CITY_LIGHTS_BATCH - 1 and litNow <= CITY_LIGHTS_BATCH, "first batch only")
runEvents()
for i = 1, 400 do assert(lamps[i].id == 2109) end
assert(litLamp.id == 2908 and farLamp.id == 2108)

-- a noite: ninguem apaga (GM pode), acender um apagado continua livre
assert(CityLights.blocksUse(player, lamps[5]))
assert(not CityLights.blocksUse(gm, lamps[5]))
assert(not CityLights.blocksUse(player, farLamp))
lamps[7]:transform(2108)
assert(not CityLights.blocksUse(player, lamps[7]))

-- 07:00 volta ao estado do mapa
worldTime = 7 * 60
CityLights.update()
runEvents()
for i = 1, 400 do assert(lamps[i].id == 2108) end
assert(litLamp.id == 2908, "lamps lit on the map stay lit by day")
assert(not CityLights.blocksUse(player, litLamp))

-- reinicio no meio da noite: acende no startup
CityLights.lit = nil
worldTime = 23 * 60
CityLights.update()
runEvents()
assert(lamps[1].id == 2109)

print("city-lights-tests: ok")
