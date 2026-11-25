local lastSync = {}
local lastCleanup = 0

function onExtendedOpcode(player, opcode, buffer)
	if opcode ~= RegenStatus.OPCODE or type(buffer) ~= 'string' or #buffer > 64 then
		return false
	end
	local ok, request = pcall(json.decode, buffer)
	if not ok or type(request) ~= 'table' or request.action ~= 'sync' then
		return false
	end
	local now, guid = os.time(), player:getGuid()
	if lastSync[guid] and now - lastSync[guid] < RegenStatus.SYNC_INTERVAL then
		return true
	end
	lastSync[guid] = now
	if now - lastCleanup >= 60 then
		lastCleanup = now
		for id, time in pairs(lastSync) do
			if time < now - 120 then lastSync[id] = nil end
		end
	end
	RegenStatus.send(player)
	return true
end
