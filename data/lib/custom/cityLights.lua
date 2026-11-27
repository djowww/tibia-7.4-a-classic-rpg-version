-- Luzes das cidades: postes, lampioes de parede e tochas fixas das cidades acendem
-- sozinhos no fim da tarde e ficam acesos ate o dia clarear. Nesse periodo ninguem
-- consegue apagar. De dia voltam ao estado original do mapa e podem ser usados normalmente.
-- So entram itens da superficie (andar 7 para cima) perto do templo de cada cidade,
-- fora das casas. As posicoes sao procuradas uma vez no startup (Game.findItemsInArea).

CITY_LIGHTS_ON = 17 * 60 + 30 -- 17:30, o entardecer ja escureceu um pouco
CITY_LIGHTS_OFF = 7 * 60 -- 07:00, dia claro
CITY_LIGHTS_RADIUS = 80
CITY_LIGHTS_RADIUS_BY_TOWN = {["Venore"] = 100}
CITY_LIGHTS_BATCH = 150 -- itens por lote
CITY_LIGHTS_BATCH_DELAY = 1000 -- ms entre lotes

-- apagado -> aceso
CITY_LIGHT_PAIRS = {
	[2108] = 2109, -- street lamp
	[2116] = 2117, -- bamboo lamp
	[2907] = 2908, [2909] = 2910, [2936] = 2937, [2938] = 2939, -- wall lamps
	[2944] = 2945, [2946] = 2947,
	[2928] = 2929, [2930] = 2931, [2940] = 2941, [2942] = 2943, -- torch bearers
	[2934] = 2935, -- tablelamp
}
CITY_LIGHT_UNLIT = {}
for off, on in pairs(CITY_LIGHT_PAIRS) do
	CITY_LIGHT_UNLIT[on] = off
end

CityLights = CityLights or {list = {}, index = {}, lit = nil, scanned = false, generation = 0}

local function key(x, y, z)
	return x * 0x100000 + y * 16 + z
end

function CityLights.isNightTime(minute)
	minute = minute or getWorldTime()
	return minute >= CITY_LIGHTS_ON or minute < CITY_LIGHTS_OFF
end

function CityLights.scan()
	local ids = {}
	for off, on in pairs(CITY_LIGHT_PAIRS) do
		ids[#ids + 1] = off
		ids[#ids + 1] = on
	end

	local list, index = {}, {}
	for _, town in ipairs(Game.getTowns()) do
		local temple = town:getTemplePosition()
		local radius = CITY_LIGHTS_RADIUS_BY_TOWN[town:getName()] or CITY_LIGHTS_RADIUS
		local found = Game.findItemsInArea(
			Position(math.max(0, temple.x - radius), math.max(0, temple.y - radius), 0),
			Position(temple.x + radius, temple.y + radius, 7), ids, true) or {}
		for _, entry in ipairs(found) do
			local k = key(entry.x, entry.y, entry.z)
			if not index[k] then
				local off = CITY_LIGHT_UNLIT[entry.id] or entry.id
				local light = {x = entry.x, y = entry.y, z = entry.z, off = off, on = CITY_LIGHT_PAIRS[off], original = entry.id}
				list[#list + 1] = light
				index[k] = light
			end
		end
	end

	CityLights.list, CityLights.index, CityLights.scanned = list, index, true
	return #list
end

function CityLights.get(position)
	return CityLights.index[key(position.x, position.y, position.z)]
end

-- Apagar uma luz da cidade fica bloqueado enquanto elas estao acesas (a noite).
function CityLights.blocksUse(player, item)
	if not CityLights.lit or not CITY_LIGHT_UNLIT[item:getId()] then
		return false
	end
	if not CityLights.get(item:getPosition()) then
		return false
	end
	return not (player and player:getGroup():getAccess())
end

local function switchLight(light, lit)
	local tile = Tile(Position(light.x, light.y, light.z))
	if not tile then
		return
	end
	local from, to
	if lit then
		from, to = light.off, light.on
	else
		-- de dia volta ao estado original do mapa
		from = light.original == light.off and light.on or light.off
		to = light.original
	end
	if from == to then
		return
	end
	local item = tile:getItemById(from)
	if item then
		item:transform(to)
	end
end

local function runBatch(generation, lit, first)
	if generation ~= CityLights.generation then
		return
	end
	local list = CityLights.list
	local last = math.min(#list, first + CITY_LIGHTS_BATCH - 1)
	for i = first, last do
		switchLight(list[i], lit)
	end
	if last < #list then
		addEvent(runBatch, CITY_LIGHTS_BATCH_DELAY, generation, lit, last + 1)
	end
end

function CityLights.set(lit)
	if not CityLights.scanned then
		CityLights.scan()
	end
	CityLights.lit = lit
	CityLights.generation = CityLights.generation + 1
	if #CityLights.list > 0 then
		runBatch(CityLights.generation, lit, 1)
	end
end

function CityLights.update()
	local night = CityLights.isNightTime()
	if night ~= CityLights.lit then
		-- no primeiro ciclo de dia nao precisa mexer: o mapa ja esta no estado original
		if CityLights.lit == nil and not night then
			CityLights.lit = false
			return
		end
		CityLights.set(night)
	end
end
