-- Staff command list for the client's F1 window (opcode 134). It is read from
-- data/talkactions/talkactions.xml on each request, so new commands show up by
-- themselves; the "usage" and "help" attributes are only for this window.
GmCommands = {OPCODE = 134, FILE = 'data/talkactions/talkactions.xml', MIN_INTERVAL = 2}

local ACCOUNT_TYPES = {
	normal = ACCOUNT_TYPE_NORMAL, tutor = ACCOUNT_TYPE_TUTOR, ['senior-tutor'] = ACCOUNT_TYPE_SENIORTUTOR,
	gamemaster = ACCOUNT_TYPE_GAMEMASTER, god = ACCOUNT_TYPE_GOD,
}
local ACCOUNT_NAMES = {
	[ACCOUNT_TYPE_TUTOR] = 'Tutor', [ACCOUNT_TYPE_SENIORTUTOR] = 'Senior Tutor',
	[ACCOUNT_TYPE_GAMEMASTER] = 'GM', [ACCOUNT_TYPE_GOD] = 'GOD',
}

local function unescape(value)
	return (value:gsub('&quot;', '"'):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&apos;', "'"):gsub('&amp;', '&'))
end

function GmCommands.parse(text)
	text = text:gsub('<!%-%-.-%-%->', '')
	local list = {}
	for tag in text:gmatch('<talkaction%s(.-)/?>') do
		local attributes = {}
		for key, value in tag:gmatch('([%w_%-]+)%s*=%s*"(.-)"') do
			attributes[key] = unescape(value)
		end
		if attributes.words then
			list[#list + 1] = attributes
		end
	end
	return list
end

-- Same rule as TalkActionAuthorization::allows (src/talkactionpolicy.h).
local function allowed(player, command)
	local permission = command.permission
	if permission == 'public' then
		return command.help ~= nil -- public commands only when they have a staff use (/pos)
	end
	local minimum = command.minaccounttype and ACCOUNT_TYPES[command.minaccounttype]
	if command.minaccounttype and not minimum then
		return false
	end
	if permission == 'access' then
		local group = player:getGroup()
		if not group or not group:getAccess() then return false end
	elseif permission == 'broadcast' then
		if not player:hasFlag(PlayerFlag_CanBroadcast) then return false end
	elseif permission ~= 'account' then
		return false
	end
	return not minimum or player:getAccountType() >= minimum
end

function GmCommands.listFor(player)
	local file = io.open(GmCommands.FILE, 'r')
	if not file then
		return {}
	end
	local text = file:read('*a')
	file:close()

	local result = {}
	for _, command in ipairs(GmCommands.parse(text)) do
		if allowed(player, command) then
			local minimum = command.minaccounttype and ACCOUNT_TYPES[command.minaccounttype]
			result[#result + 1] = {
				words = command.words,
				usage = command.usage or command.words,
				help = command.help or '',
				level = minimum and ACCOUNT_NAMES[minimum] or (command.permission == 'public' and 'All' or 'Staff'),
			}
		end
	end
	return result
end

local lastSent = {}

function GmCommands.send(player)
	if player:getAccountType() < ACCOUNT_TYPE_GAMEMASTER then
		return
	end
	local now, guid = os.time(), player:getGuid()
	if lastSent[guid] and now - lastSent[guid] < GmCommands.MIN_INTERVAL then
		return
	end
	lastSent[guid] = now
	local accountName = ACCOUNT_NAMES[player:getAccountType()] or 'Staff'
	player:sendExtendedOpcode(GmCommands.OPCODE, json.encode({action = 'list', account = accountName,
		commands = GmCommands.listFor(player)}))
end
