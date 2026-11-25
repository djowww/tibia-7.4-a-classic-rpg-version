-- Exploration chests: one hidden chest per region, placed at startup on one of
-- that region's hiding spots. Each character opens each chest once and picks a
-- permanent reward in the client window (opcode 132).
ExplorationChests = {
	OPCODE = 132,
	CHEST_ITEM = 2479, -- unmovable "a chest", shown by the client as 2472
	ACTION_BASE = 47100, -- region n uses action id ACTION_BASE + n
	STORAGE_BASE = 17700, -- storage STORAGE_BASE + n = reward picked in region n
	ATTRIBUTES_SUBID = 17880,
	REGEN_SUBID = 17881,
	GOLD_PER_MILLE = 4, -- 0.4% of total experience
	MANA_PER_MILLE = 2, -- +0.2% max mana per mana chest
	LIFE_PER_MILLE = 3, -- +0.3% max health per health chest
	MANA_TICK_MS = 55000, -- 0.2 mana every 11 s = 1 mana every 55 s per chest
	LIFE_TICK_MS = 33333, -- 0.3 health every 10 s = 1 health every 33.3 s per chest
	REACH = 1,
	GLOW_EFFECT = CONST_ME_YELLOW_RINGS, -- golden sparkle over each chest
	GLOW_INTERVAL_MS = 2500,
	CHOICES = {gold = 1, mana = 2, life = 3},
	regions = {
		{name = "Rookgaard", spots = {Position(32108, 32133, 7), Position(32125, 32189, 7), Position(32052, 32186, 7), Position(32120, 32163, 7)}},
		{name = "Thais", spots = {Position(32325, 32150, 7), Position(32358, 32391, 7), Position(32345, 32300, 7), Position(32462, 32334, 7)}},
		{name = "Carlin", spots = {Position(32351, 31658, 7), Position(32403, 31664, 7), Position(32379, 31710, 7), Position(32316, 31686, 7)}},
		{name = "Kazordoon", spots = {Position(32636, 31967, 7), Position(32544, 31962, 7), Position(32564, 31886, 7), Position(32763, 32029, 7)}},
		{name = "Ab'Dendriel", spots = {Position(32693, 31708, 7), Position(32654, 31630, 7), Position(32842, 31735, 7), Position(32587, 31684, 7)}},
		{name = "Venore", spots = {Position(32861, 32180, 7), Position(32827, 32128, 7), Position(32816, 32097, 7), Position(32878, 32154, 7)}},
		{name = "Edron", spots = {Position(33145, 31813, 7), Position(33216, 31883, 7), Position(33188, 31902, 7), Position(33303, 31742, 7)}},
		{name = "Darashia", spots = {Position(33101, 32347, 7), Position(33201, 32308, 7), Position(33310, 32341, 7), Position(33138, 32516, 7)}},
		{name = "Ankrahmun", spots = {Position(33058, 32851, 7), Position(33256, 32808, 7), Position(33234, 32789, 7)}},
		{name = "Port Hope", spots = {Position(32623, 32902, 7), Position(32627, 32625, 7), Position(32629, 32868, 7), Position(32560, 32679, 7)}},
	},
	placed = {}, -- region index -> position of this boot's chest
	pending = {}, -- player guid -> region index of the window last opened
}

local E = ExplorationChests

function E.getChoice(player, region)
	return math.max(0, player:getStorageValue(E.STORAGE_BASE + region))
end

function E.counts(player)
	local explored, mana, life = 0, 0, 0
	for index = 1, #E.regions do
		local choice = E.getChoice(player, index)
		if choice > 0 then
			explored = explored + 1
			if choice == E.CHOICES.mana then mana = mana + 1 end
			if choice == E.CHOICES.life then life = life + 1 end
		end
	end
	return explored, mana, life
end

function E.goldFor(player)
	return math.floor(player:getExperience() * E.GOLD_PER_MILLE / 1000)
end

-- Rebuilds the bonus conditions from the stored choices. Max health/mana are
-- a share of the character's own maximum, so it runs again on level up.
function E.apply(player)
	player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, E.ATTRIBUTES_SUBID)
	player:removeCondition(CONDITION_REGENERATION, CONDITIONID_COMBAT, E.REGEN_SUBID)
	local _, mana, life = E.counts(player)
	if mana == 0 and life == 0 then
		return
	end

	local extraHealth = math.floor(player:getMaxHealth() * life * E.LIFE_PER_MILLE / 1000 + 0.5)
	local extraMana = math.floor(player:getMaxMana() * mana * E.MANA_PER_MILLE / 1000 + 0.5)
	if extraHealth > 0 or extraMana > 0 then
		local attributes = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
		attributes:setParameter(CONDITION_PARAM_SUBID, E.ATTRIBUTES_SUBID)
		attributes:setParameter(CONDITION_PARAM_TICKS, -1)
		if extraHealth > 0 then attributes:setParameter(CONDITION_PARAM_STAT_MAXHITPOINTS, extraHealth) end
		if extraMana > 0 then attributes:setParameter(CONDITION_PARAM_STAT_MAXMANAPOINTS, extraMana) end
		player:addCondition(attributes)
	end

	local regen = Condition(CONDITION_REGENERATION, CONDITIONID_COMBAT)
	regen:setParameter(CONDITION_PARAM_SUBID, E.REGEN_SUBID)
	regen:setParameter(CONDITION_PARAM_TICKS, -1)
	regen:setParameter(CONDITION_PARAM_HEALTHGAIN, life > 0 and 1 or 0)
	regen:setParameter(CONDITION_PARAM_HEALTHTICKS, life > 0 and math.max(1000, math.floor(E.LIFE_TICK_MS / life)) or 86400000)
	regen:setParameter(CONDITION_PARAM_MANAGAIN, mana > 0 and 1 or 0)
	regen:setParameter(CONDITION_PARAM_MANATICKS, mana > 0 and math.max(1000, math.floor(E.MANA_TICK_MS / mana)) or 86400000)
	player:addCondition(regen)
end

function E.glow()
	for _, position in pairs(E.placed) do
		position:sendMagicEffect(E.GLOW_EFFECT)
	end
	addEvent(E.glow, E.GLOW_INTERVAL_MS)
end

function E.placeAll()
	-- Startup events may run before ServerStartup seeds the generator.
	math.randomseed(os.mtime and os.mtime() or os.time())
	local placed = 0
	for index, region in ipairs(E.regions) do
		local first = math.random(#region.spots)
		for attempt = 0, #region.spots - 1 do
			local position = region.spots[(first + attempt - 1) % #region.spots + 1]
			local tile = Tile(position)
			if tile and tile:getGround() and not tile:getTopCreature() then
				local chest = Game.createItem(E.CHEST_ITEM, 1, position)
				if chest then
					chest:setActionId(E.ACTION_BASE + index)
					E.placed[index] = Position(position.x, position.y, position.z)
					placed = placed + 1
					break
				end
			end
		end
		if not E.placed[index] then
			print(string.format('[ExplorationChests] no free spot for %s', region.name))
		end
	end
	print(string.format('>> Exploration chests placed: %d of %d', placed, #E.regions))
	if placed > 0 then
		addEvent(E.glow, E.GLOW_INTERVAL_MS)
	end
end

local function near(player, position)
	local from = player:getPosition()
	return position and from.z == position.z
		and math.abs(from.x - position.x) <= E.REACH and math.abs(from.y - position.y) <= E.REACH
end

local function send(player, data)
	player:sendExtendedOpcode(E.OPCODE, json.encode(data))
end

function E.onUse(player, item)
	local index = item:getActionId() - E.ACTION_BASE
	local region = E.regions[index]
	if not region then
		return false
	end
	local explored = E.counts(player)
	local choice = E.getChoice(player, index)
	if choice > 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
			"You have already claimed the treasure of %s. Regions explored: %d of %d.", region.name, explored, #E.regions))
		return true
	end

	local maxMana, maxHealth = player:getMaxMana(), player:getMaxHealth()
	E.pending[player:getGuid()] = index
	send(player, {
		action = 'open',
		region = index,
		name = region.name,
		experience = player:getExperience(),
		gold = E.goldFor(player),
		mana = math.floor(maxMana * E.MANA_PER_MILLE / 1000 + 0.5),
		health = math.floor(maxHealth * E.LIFE_PER_MILLE / 1000 + 0.5),
		explored = explored,
		total = #E.regions,
	})
	item:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true
end

function E.claim(player, index, choiceName)
	local region = E.regions[index]
	local choice = E.CHOICES[choiceName]
	local guid = player:getGuid()
	if not region or not choice or E.pending[guid] ~= index then
		return
	end
	if E.getChoice(player, index) > 0 then
		E.pending[guid] = nil
		send(player, {action = 'close'})
		return
	end
	if not near(player, E.placed[index]) then
		player:sendCancelMessage("You are too far away from the chest.")
		return
	end

	E.pending[guid] = nil
	player:setStorageValue(E.STORAGE_BASE + index, choice)
	local message
	if choice == E.CHOICES.gold then
		local gold = E.goldFor(player)
		if gold > 0 then player:addMoney(gold) end
		message = string.format("You found the treasure of %s: %d gold coins.", region.name, gold)
	elseif choice == E.CHOICES.mana then
		message = string.format("You found the treasure of %s: +0.2%% max mana and +0.2 mana every 11 seconds, forever.", region.name)
	else
		message = string.format("You found the treasure of %s: +0.3%% max health and +0.3 health every 10 seconds, forever.", region.name)
	end
	E.apply(player)
	if RegenStatus and RegenStatus.send then RegenStatus.send(player) end
	local explored = E.counts(player)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s Regions explored: %d of %d.", message, explored, #E.regions))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	send(player, {action = 'close'})
end

function E.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= E.OPCODE or type(buffer) ~= 'string' or #buffer > 128 then
		return false
	end
	local ok, request = pcall(json.decode, buffer)
	if not ok or type(request) ~= 'table' then
		return false
	end
	if request.action == 'claim' then
		E.claim(player, tonumber(request.region), request.choice)
	elseif request.action == 'close' then
		E.pending[player:getGuid()] = nil
	else
		return false
	end
	return true
end
