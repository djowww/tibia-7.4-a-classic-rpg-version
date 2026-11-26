local requestTimes = {}
local MAX_REQUEST_BYTES = 8192
local MAX_REQUEST_MONSTERS = 200
local REQUEST_INTERVAL = 2
local lastRequestCleanup = 0

local function sendBonusMessage(player, completed, action)
	local bonus = completed * 0.2
	local message
	if action == "synchronized" then
		message = string.format("Bestiary XP bonus synchronized: +%.1f%% permanent bonus from %d completed bestiaries.", bonus, completed)
	else
		message = string.format("Bestiary complete! Each completed bestiary grants +0.2%% permanent XP. Your bonus is now +%.1f%%.", bonus)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, message)
end

-- Normalized name and storage key of each monster killed so far. Only names of
-- real monsters reach this cache, so it stays as small as the monster roster.
local killKeys = {}

local function killKey(name)
	local entry = killKeys[name]
	if entry == nil then
		local storageKey = AntigasBestiary.storageKey(name)
		entry = storageKey and {storageKey = storageKey, monster = AntigasBestiary.normalizeName(name)} or false
		killKeys[name] = entry
	end
	return entry
end

function onKill(killer, target)
	if not killer or not killer:isPlayer() or not target or not target:isMonster() then
		return true
	end
	local targetMaster = target:getMaster()
	if targetMaster and targetMaster:isPlayer() then
		return true
	end

	local entry = killKey(target:getName())
	if not entry then
		return true
	end
	local storageKey = entry.storageKey

	local kills = math.max(0, math.min(AntigasBestiary.MAX_KILLS, killer:getStorageValue(storageKey)))
	if kills < AntigasBestiary.MAX_KILLS then
		kills = kills + 1
		killer:setStorageValue(storageKey, kills)
		local update = {
			action = "update",
			monster = entry.monster,
			kills = kills
		}
		if kills == AntigasBestiary.MAX_KILLS then
			local completed = AntigasBestiary.addCompletion(killer)
			if completed then
				update.completed = completed
				sendBonusMessage(killer, completed, "completed")
			end
		end
		killer:sendExtendedOpcode(AntigasBestiary.OPCODE, json.encode(update))
	end
	return true
end

function onExtendedOpcode(player, opcode, buffer)
	if opcode ~= AntigasBestiary.OPCODE then
		return false
	end
	if type(buffer) ~= "string" or #buffer > MAX_REQUEST_BYTES then
		return false
	end

	-- Rate limit before decoding, so a flood of large requests costs nothing.
	local guid = player:getGuid()
	local now = os.time()
	local lastRequest = requestTimes[guid]
	if lastRequest and now - lastRequest < REQUEST_INTERVAL then
		return true
	end
	requestTimes[guid] = now

	local decoded, request = pcall(function() return json.decode(buffer) end)
	if not decoded or type(request) ~= "table" or request.action ~= "getProgress" or type(request.monsters) ~= "table" then
		return false
	end
	if now - lastRequestCleanup >= 60 then
		lastRequestCleanup = now
		for playerGuid, timestamp in pairs(requestTimes) do
			if timestamp < now - 120 then
				requestTimes[playerGuid] = nil
			end
		end
	end

	local counts, seen = {}, {}
	local monsterCount = #request.monsters
	if monsterCount > MAX_REQUEST_MONSTERS then
		return false
	end
	local validMonsterCount, completedInCatalog = 0, 0
	for index = 1, monsterCount do
		local requestedName = request.monsters[index]
		local normalized = AntigasBestiary.normalizeName(requestedName)
		if normalized and not seen[normalized] and MonsterType(normalized) then
			seen[normalized] = true
			validMonsterCount = validMonsterCount + 1
			local storageKey = AntigasBestiary.storageKey(normalized)
			local kills = math.max(0, math.min(AntigasBestiary.MAX_KILLS, player:getStorageValue(storageKey)))
			counts[requestedName] = kills
			if kills >= AntigasBestiary.MAX_KILLS then
				completedInCatalog = completedInCatalog + 1
			end
		end
	end

	local completed = AntigasBestiary.getCompletedCount(player)
	if monsterCount == AntigasBestiary.CATALOG_SIZE and validMonsterCount == AntigasBestiary.CATALOG_SIZE then
		local previous = completed
		completed = AntigasBestiary.reconcileCompletedCount(player, completedInCatalog)
		if completed > previous then
			sendBonusMessage(player, completed, "synchronized")
		end
	end

	player:sendExtendedOpcode(AntigasBestiary.OPCODE, json.encode({
		action = "progress",
		data = counts,
		completed = completed
	}))
	return true
end
