-- "Inspect bot" and "Start bot check" from the client's right-click menu
-- (module game_botinspect, opcode 135). Only GM and GOD accounts get an
-- answer; for anybody else the request is ignored.
local MIN_INTERVAL = 300 -- ms between requests of the same staff member
local lastRequest = {}

function onExtendedOpcode(player, opcode, buffer)
	if opcode ~= BotDetector.OPCODE then
		return false
	end
	if not BotDetector.isStaff(player) or type(buffer) ~= "string" or #buffer > 200 then
		return true
	end
	local now = os.mtime()
	local cid = player:getId()
	if lastRequest[cid] and now - lastRequest[cid] < MIN_INTERVAL then
		return true
	end
	lastRequest[cid] = now

	local ok, data = pcall(json.decode, buffer)
	if not ok or type(data) ~= "table" or type(data.name) ~= "string" or data.name == "" or #data.name > 40 then
		return true
	end
	local action = data.action
	if action ~= "inspect" and action ~= "check" and action ~= "clear" then
		return true
	end
	BotDetector.handleInspect(player, action, data.name)
	return true
end
