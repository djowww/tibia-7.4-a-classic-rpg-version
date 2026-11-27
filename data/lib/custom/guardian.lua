-- Guardian: what the official launcher reports about the computer.
--
-- The launcher asks the server for a session token before it starts the
-- client (src/guardian.cpp, answered on the status port), the client sends
-- that token right after login (module game_guardian, opcode 136) and the
-- launcher keeps the session alive with a heartbeat every 60 seconds.
--
-- Like the rest of the bot detector this only adds to the staff alert. A
-- launcher runs on the player's computer and can be faked, so the server
-- never trusts it alone. Set requireLauncher to true to refuse players that
-- did not come through the launcher.

Guardian = Guardian or {}

Guardian.OPCODE = 136

Guardian.config = {
	enabled = true,
	graceSeconds = 45,       -- time the client has to present its token after login
	staleSeconds = 150,      -- heartbeats come every 60 s
	requireLauncher = false, -- true: players without a valid session are disconnected after the grace time

	scoreMissing = 2,        -- no token, unknown token or token from another IP
	scoreStale = 2,          -- launcher closed while playing
	scoreBotTool = 3,        -- a known bot is running
	scoreInjected = 3,       -- a known bot library inside the client
	scoreModified = 3,       -- client files changed or scripts added
	scoreMacro = 1,          -- generic macro tool (AutoHotkey and similar)
	scoreNoManifest = 1,     -- install without the signed file list
}

local FLAG_FILES_MODIFIED = 2
local FLAG_BOT_TOOL = 4
local FLAG_MACRO_TOOL = 8
local FLAG_INJECTED = 16
local FLAG_NO_MANIFEST = 32

Guardian.logins = Guardian.logins or {} -- by player id: { at = os.time(), status = result of guardianBind }

local function has(flags, flag)
	return math.floor(flags / flag) % 2 == 1
end

function Guardian.onLogin(player)
	Guardian.logins[player:getId()] = { at = os.time() }
end

function Guardian.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= Guardian.OPCODE then
		return false
	end
	local cid = player:getId()
	local login = Guardian.logins[cid]
	if not login then
		login = { at = os.time() }
		Guardian.logins[cid] = login
	end
	if type(buffer) ~= "string" or #buffer ~= 32 or buffer:find("[^0-9a-f]") then
		login.status = "unknown"
	else
		login.status = guardianBind(cid, player:getIp(), buffer)
	end
	-- The client writes the answer to its log, which helps support.
	player:sendExtendedOpcode(Guardian.OPCODE, login.status)
	return true
end

-- Returns the launcher session of the player, or nil and the reason.
function Guardian.session(player)
	local cid = player:getId()
	local login = Guardian.logins[cid]
	if not login then
		return nil, "untracked"
	end
	if login.status == "ok" then
		local session = getGuardianSession(cid)
		if session then
			return session
		end
		return nil, "expired"
	end
	if os.time() - login.at < Guardian.config.graceSeconds then
		return nil, "waiting"
	end
	return nil, login.status or "missing"
end

local MISSING_TEXT = {
	missing = "entrou sem o launcher oficial (cliente não mandou o token do Guardian)",
	unknown = "token do Guardian inválido ou vencido",
	expired = "sessão do Guardian vencida (launcher fechado há mais de 10 min)",
	ip = "token do Guardian pedido de outro IP",
}

-- Called by BotDetector.evaluate. Adds to reasons and returns the new score.
function Guardian.evaluate(player, score, reasons)
	local cfg = Guardian.config
	if not cfg.enabled then
		return score
	end
	local session, why = Guardian.session(player)
	if not session then
		if MISSING_TEXT[why] then
			score = score + cfg.scoreMissing
			reasons[#reasons + 1] = MISSING_TEXT[why]
		end
		return score
	end

	if session.beatAge > cfg.staleSeconds * 1000 then
		score = score + cfg.scoreStale
		reasons[#reasons + 1] = string.format("launcher fechado ou sem resposta há %d s", math.floor(session.beatAge / 1000))
	end

	local found = {}
	if has(session.worst, FLAG_BOT_TOOL) then
		score = score + cfg.scoreBotTool
		found[#found + 1] = "bot conhecido aberto no PC"
	end
	if has(session.worst, FLAG_INJECTED) then
		score = score + cfg.scoreInjected
		found[#found + 1] = "biblioteca de bot dentro do cliente"
	end
	if has(session.worst, FLAG_FILES_MODIFIED) then
		score = score + cfg.scoreModified
		found[#found + 1] = "arquivos do cliente alterados"
	end
	if has(session.worst, FLAG_MACRO_TOOL) then
		score = score + cfg.scoreMacro
		found[#found + 1] = "programa de macro aberto"
	end
	if has(session.worst, FLAG_NO_MANIFEST) then
		score = score + cfg.scoreNoManifest
		found[#found + 1] = "instalação sem a lista assinada de arquivos"
	end
	if #found > 0 then
		local text = "Guardian: " .. table.concat(found, ", ")
		if session.detail ~= "" then
			text = text .. " (" .. session.detail .. ")"
		end
		reasons[#reasons + 1] = text
	end
	return score
end

-- Called by BotDetector.check for every player that is not staff.
function Guardian.enforce(player)
	local cfg = Guardian.config
	if not cfg.enabled or not cfg.requireLauncher then
		return
	end
	local session, why = Guardian.session(player)
	if not session and MISSING_TEXT[why] then
		player:sendTextMessage(MESSAGE_STATUS_WARNING, "Please start the game with the official launcher.")
		local cid = player:getId()
		addEvent(function()
			local target = Player(cid)
			if target then
				target:remove()
			end
		end, 3000)
	end
end
