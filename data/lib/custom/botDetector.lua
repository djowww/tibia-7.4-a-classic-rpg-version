-- Behaviour-based bot detection. It only alerts the staff: nobody is
-- kicked or banned automatically.
--
-- The C++ side (src/botdetector.cpp) times every action packet and the
-- reaction after each hit. This file turns those numbers into a score,
-- tracks long hunting sessions and runs the optional in-game check.

BotDetector = BotDetector or {}

BotDetector.config = {
	enabled = true,
	checkInterval = 60, -- seconds, must match globalevents.xml

	-- Rhythm: intervals between the same kind of action (300 ms to 15 s).
	rhythmMinSamples = 30,
	rhythmMaxCv = 0.05,      -- standard deviation / mean
	rhythmMinNear = 0.85,    -- share of intervals within 25 ms (or 3%) of the median
	rhythmCategories = { use = "usar item", usewith = "runa/poção", attack = "atacar", say = "magia/fala", autowalk = "clique no mapa" },

	-- Reaction: time from losing health to the next spell, rune or potion.
	reactionMinSamples = 15,
	reactionMaxSd = 50,      -- ms, humans vary by 100 ms or more
	reactionMaxMean = 600,
	reactionMaxMedian = 90,  -- faster than any human, whatever the variation

	-- Reaction minus the ping the client reports: what is left is the time
	-- the player took to notice the hit and press a key. People need 200 ms
	-- or more even when they are expecting it; a bot needs a few ms.
	thinkMinSamples = 12,
	thinkMaxMedian = 100,

	burstsLimit = 5,         -- seconds with more than 12 clicks/hotkeys

	-- Client signature: the official client (OTCv8) reports its ping and fps
	-- every few seconds, walks with the new walking packet and its modules
	-- talk over extended opcodes right after login. A headless bot does none.
	signatureAfter = 120,    -- seconds online before judging
	signatureMinSteps = 20,

	-- Long sessions.
	breakMinutes = 5,        -- no action for this long counts as a pause
	huntBreakMinutes = 10,   -- no experience for this long ends a hunt
	huntHours = 6,           -- hunting without pause in the same spot
	spotSize = 60,           -- sqm, width and height of "the same spot"
	activeHours = 10,        -- any activity without a single pause

	attentionScore = 2,
	suspectScore = 3,
	alertCooldown = 30 * 60,

	-- In-game check (captcha).
	autoCheck = false,       -- true sends the check to every new suspect
	checkTimeout = 180,      -- seconds to answer
	verifiedFor = 2 * 60 * 60, -- a passed check clears the score for this long

	logFile = "data/reports/botdetector.log",
}

BotDetector.players = BotDetector.players or {} -- by guid, survives /reload
BotDetector.history = BotDetector.history or {} -- last alerts, newest last

local function now()
	return os.time()
end

function BotDetector.log(text)
	local line = os.date("%Y-%m-%d %H:%M:%S") .. " " .. text
	print("[BotDetector] " .. text)
	local file = io.open(BotDetector.config.logFile, "a")
	if file then
		file:write(line .. "\n")
		file:close()
	end
end

-- The client draws Latin-1 and this file is UTF-8: convert what goes to it.
local function latin1(text)
	return (text:gsub("([\194\195])([\128-\191])", function(a, b)
		return string.char((a:byte() - 194) * 64 + b:byte())
	end))
end
BotDetector.latin1 = latin1

local function isStaff(player)
	return player:getGroup():getAccess() and player:getAccountType() >= ACCOUNT_TYPE_GAMEMASTER
end
BotDetector.isStaff = isStaff

function BotDetector.notifyStaff(text)
	for _, staff in ipairs(Game.getPlayers()) do
		if isStaff(staff) then
			staff:sendTextMessage(MESSAGE_STATUS_CONSOLE_RED, latin1("[Anti-bot] " .. text))
		end
	end
end

function BotDetector.getState(player)
	local guid = player:getGuid()
	local state = BotDetector.players[guid]
	if not state or state.cid ~= player:getId() then
		-- new login: keep only what must outlive the session
		local old = state or {}
		state = {
			cid = player:getId(),
			name = player:getName(),
			score = 0,
			level = 0,
			reasons = {},
			alertedAt = old.alertedAt or 0,
			alertedScore = old.alertedScore or 0,
			verifiedUntil = old.verifiedUntil or 0,
			checkFailed = old.checkFailed or 0,
			activeSince = now(),
			lastActive = now(),
			huntSince = nil,
			lastExpAt = nil,
			lastExp = player:getExperience(),
			spot = nil,
		}
		BotDetector.players[guid] = state
	end
	return state
end

local function fmt(value)
	return string.format("%d", math.floor((value or 0) + 0.5))
end

local function hours(seconds)
	return string.format("%.1f h", seconds / 3600)
end

-- Updates the session trackers once per check interval.
local function trackSession(player, state, stats)
	local cfg = BotDetector.config
	local t = now()

	-- any action at all
	local idle = stats and stats.idle or -1
	if idle >= 0 and idle < cfg.checkInterval * 1000 then
		if t - state.lastActive >= cfg.breakMinutes * 60 then
			state.activeSince = t
		end
		state.lastActive = t
	end

	-- hunting: experience going up, and where
	local exp = player:getExperience()
	if exp > state.lastExp then
		local pos = player:getPosition()
		if not state.huntSince or t - (state.lastExpAt or 0) >= cfg.huntBreakMinutes * 60 then
			state.huntSince = t
			state.spot = { minX = pos.x, maxX = pos.x, minY = pos.y, maxY = pos.y, z = pos.z, same = true }
		else
			local spot = state.spot
			spot.minX, spot.maxX = math.min(spot.minX, pos.x), math.max(spot.maxX, pos.x)
			spot.minY, spot.maxY = math.min(spot.minY, pos.y), math.max(spot.maxY, pos.y)
			if spot.maxX - spot.minX > cfg.spotSize or spot.maxY - spot.minY > cfg.spotSize then
				-- moved on: the spot restarts here, the hunt goes on
				state.huntSince = t
				state.spot = { minX = pos.x, maxX = pos.x, minY = pos.y, maxY = pos.y, z = pos.z, same = true }
			end
		end
		state.lastExpAt = t
	end
	state.lastExp = exp
end

-- Returns score, reasons (list of strings).
function BotDetector.evaluate(player, state, stats)
	local cfg = BotDetector.config
	local score, reasons = 0, {}
	local t = now()

	if stats then
		local rhythm = 0
		for key, label in pairs(cfg.rhythmCategories) do
			local ring = stats[key]
			if ring and ring.n >= cfg.rhythmMinSamples and ring.mean and ring.mean > 0 then
				local cv = ring.sd / ring.mean
				if cv <= cfg.rhythmMaxCv or ring.near >= cfg.rhythmMinNear then
					rhythm = rhythm + 1
					reasons[#reasons + 1] = string.format("ritmo perfeito em %s (%s ms ± %s, %d%% iguais, %d amostras)",
						label, fmt(ring.mean), fmt(ring.sd), math.floor(ring.near * 100), ring.n)
				end
			end
		end
		if rhythm > 0 then
			score = score + 2 + math.min(rhythm - 1, 1)
		end

		local reaction = stats.reaction
		local reactionFlagged = false
		if reaction and reaction.n >= cfg.reactionMinSamples then
			reactionFlagged = reaction.median <= cfg.reactionMaxMedian or
				(reaction.sd <= cfg.reactionMaxSd and reaction.mean <= cfg.reactionMaxMean)
			if reaction.median <= cfg.reactionMaxMedian then
				score = score + 3
				reasons[#reasons + 1] = string.format("cura rápida demais após dano (mediana %s ms, %d amostras)", fmt(reaction.median), reaction.n)
			elseif reaction.sd <= cfg.reactionMaxSd and reaction.mean <= cfg.reactionMaxMean then
				score = score + 3
				reasons[#reasons + 1] = string.format("cura sempre no mesmo tempo após dano (%s ms ± %s, %d amostras)", fmt(reaction.mean), fmt(reaction.sd), reaction.n)
			end
		end

		if reaction and reaction.n >= cfg.thinkMinSamples and stats.ping and stats.ping > 0 and not reactionFlagged then
			local think = reaction.median - stats.ping
			if think <= cfg.thinkMaxMedian then
				score = score + 3
				reasons[#reasons + 1] = string.format("reage ao dano em %s ms descontando o ping de %s ms (mediana, %d amostras)",
					fmt(math.max(think, 0)), fmt(stats.ping), reaction.n)
			end
		end

		if stats.tracked >= cfg.signatureAfter * 1000 then
			local missing = {}
			if (stats.newPings or 0) == 0 or (stats.fpsMax or 0) == 0 then
				missing[#missing + 1] = "não informa ping/FPS"
			end
			if (stats.extOpcodes or 0) == 0 then
				missing[#missing + 1] = "não carrega os módulos do cliente"
			end
			if (stats.oldSteps or 0) >= cfg.signatureMinSteps and (stats.newSteps or 0) == 0 then
				missing[#missing + 1] = "anda com pacotes antigos"
			end
			if #missing >= 2 then
				score = score + 3
				reasons[#reasons + 1] = "cliente não oficial: " .. table.concat(missing, ", ")
			elseif #missing == 1 then
				score = score + 1
				reasons[#reasons + 1] = "cliente diferente do oficial: " .. missing[1]
			end
		end

		if stats.bursts >= cfg.burstsLimit then
			score = score + 1
			reasons[#reasons + 1] = string.format("%d rajadas de mais de 12 cliques por segundo", stats.bursts)
		end
	end

	if state.huntSince and state.lastExpAt and t - state.lastExpAt < cfg.huntBreakMinutes * 60 then
		local hunting = t - state.huntSince
		if hunting >= cfg.huntHours * 3600 then
			score = score + 2
			local spot = state.spot
			reasons[#reasons + 1] = string.format("caçando há %s sem pausa no mesmo lugar (%d,%d,%d)", hours(hunting),
				math.floor((spot.minX + spot.maxX) / 2), math.floor((spot.minY + spot.maxY) / 2), spot.z)
		end
	end

	local active = t - state.activeSince
	if t - state.lastActive < cfg.breakMinutes * 60 and active >= cfg.activeHours * 3600 then
		score = score + 1
		reasons[#reasons + 1] = string.format("ativo há %s sem nenhuma pausa de %d min", hours(active), cfg.breakMinutes)
	end

	if Guardian then
		score = Guardian.evaluate(player, score, reasons)
	end

	if state.checkFailed > 0 then
		score = score + 3
		reasons[#reasons + 1] = string.format("não respondeu a verificação anti-bot (%dx)", state.checkFailed)
	end

	if state.verifiedUntil > t then
		score = 0
		reasons[#reasons + 1] = "verificado pela staff ou pela checagem, alerta pausado"
	end

	return score, reasons
end

function BotDetector.check(player)
	if isStaff(player) then
		return
	end
	local cfg = BotDetector.config
	local state = BotDetector.getState(player)
	local stats = getBotDetectorStats(player:getId())
	trackSession(player, state, stats)

	local score, reasons = BotDetector.evaluate(player, state, stats)
	state.score, state.reasons, state.checkedAt = score, reasons, now()
	if Guardian then
		Guardian.enforce(player)
	end
	state.level = score >= cfg.suspectScore and 2 or (score >= cfg.attentionScore and 1 or 0)

	if state.level == 2 then
		local t = now()
		if score > state.alertedScore or t - state.alertedAt >= cfg.alertCooldown then
			state.alertedAt, state.alertedScore = t, score
			local text = string.format("%s parece bot (%d pontos): %s", player:getName(), score, table.concat(reasons, "; "))
			BotDetector.log(text)
			BotDetector.notifyStaff(text .. ". Use /botinfo " .. player:getName() .. " ou /botcheck " .. player:getName() .. ".")
			table.insert(BotDetector.history, { time = t, name = player:getName(), score = score, reasons = reasons })
			while #BotDetector.history > 30 do
				table.remove(BotDetector.history, 1)
			end
			if cfg.autoCheck and not state.pendingCheck then
				BotDetector.sendCheck(player, nil)
			end
		end
	end
end

function BotDetector.checkAll()
	if not BotDetector.config.enabled then
		return
	end
	local online = {}
	for _, player in ipairs(Game.getPlayers()) do
		online[player:getGuid()] = true
		BotDetector.check(player)
	end
	-- forget sessions of players that left more than a day ago
	local t = now()
	for guid, state in pairs(BotDetector.players) do
		if not online[guid] and t - (state.checkedAt or t) > 24 * 3600 then
			BotDetector.players[guid] = nil
		end
	end
end

-- In-game check: a simple sum the player answers in the chat.
local function answerText(question)
	return string.format(
		"Anti-bot check: how much is %s? Answer by saying !human <number> within %d minutes.\n\n" ..
		"Verificação anti-bot: quanto é %s? Responda dizendo !humano <número> em até %d minutos.",
		question, math.ceil(BotDetector.config.checkTimeout / 60), question, math.ceil(BotDetector.config.checkTimeout / 60))
end

function BotDetector.sendCheck(player, staffName)
	local state = BotDetector.getState(player)
	local a, b = math.random(2, 9), math.random(2, 9)
	local token = math.random(1, 2^30)
	state.pendingCheck = { answer = a + b, token = token, sentAt = now(), by = staffName or "auto" }
	local question = string.format("%d + %d", a, b)
	player:popupFYI(latin1(answerText(question)))
	player:sendTextMessage(MESSAGE_STATUS_WARNING, latin1((answerText(question):gsub("\n\n", " "))))
	BotDetector.log(string.format("check sent to %s by %s", player:getName(), staffName or "auto"))

	local guid, cid = player:getGuid(), player:getId()
	addEvent(function()
		local st = BotDetector.players[guid]
		if not st or not st.pendingCheck or st.pendingCheck.token ~= token then
			return
		end
		local by = st.pendingCheck.by
		st.pendingCheck = nil
		local online = Player(cid)
		if not online then
			st.lastCheck = "logout"
			BotDetector.log(string.format("%s logged out before answering the check", st.name))
			return
		end
		st.checkFailed = st.checkFailed + 1
		st.lastCheck = "timeout"
		local text = string.format("%s NÃO respondeu a verificação anti-bot em %d s.", st.name, BotDetector.config.checkTimeout)
		BotDetector.log(text)
		BotDetector.notifyStaff(text)
		BotDetector.notifyChecker(online, by, text)
	end, BotDetector.config.checkTimeout * 1000)
end

function BotDetector.answer(player, param)
	local state = BotDetector.getState(player)
	local pending = state.pendingCheck
	if not pending then
		player:sendTextMessage(MESSAGE_INFO_DESCR, latin1("There is no pending check. / Não há verificação pendente."))
		return
	end
	local value = tonumber(param)
	if value ~= pending.answer then
		pending.wrong = (pending.wrong or 0) + 1
		player:sendTextMessage(MESSAGE_STATUS_WARNING, "Wrong answer, try again. / Resposta errada, tente de novo.")
		if pending.wrong >= 3 then
			state.pendingCheck = nil
			state.checkFailed = state.checkFailed + 1
			state.lastCheck = "wrong"
			local text = string.format("%s errou a verificação anti-bot 3 vezes.", player:getName())
			BotDetector.log(text)
			BotDetector.notifyStaff(text)
			BotDetector.notifyChecker(player, pending.by, text)
		end
		return
	end
	state.pendingCheck = nil
	state.checkFailed = 0
	state.verifiedUntil = now() + BotDetector.config.verifiedFor
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Thank you! / Obrigado!")
	local text = string.format("%s passou na verificação anti-bot em %d s.", player:getName(), now() - pending.sentAt)
	state.lastCheck = "passed"
	BotDetector.log(text)
	BotDetector.notifyStaff(text)
	BotDetector.notifyChecker(player, pending.by, text)
end

function BotDetector.clear(player, staffName)
	local state = BotDetector.getState(player)
	state.checkFailed = 0
	state.pendingCheck = nil
	state.verifiedUntil = now() + BotDetector.config.verifiedFor
	state.alertedScore = 0
	resetBotDetector(player:getId())
	BotDetector.log(string.format("%s cleared by %s", player:getName(), staffName))
end

local function ringLine(label, ring)
	if not ring or ring.n == 0 then
		return nil
	end
	if not ring.mean then
		return string.format("%s: %d", label, ring.n)
	end
	return string.format("%s: %d amostras, %s ms ± %s (mediana %s, %d%% iguais)", label, ring.n,
		fmt(ring.mean), fmt(ring.sd), fmt(ring.median), math.floor(ring.near * 100))
end

-- Detail lines shared by /botinfo and the client's Inspect bot window.
function BotDetector.detailLines(state, stats)
	local lines = {}
	if stats then
		local rings = {}
		for _, key in ipairs({ "use", "usewith", "attack", "say", "autowalk", "walk", "move" }) do
			rings[#rings + 1] = ringLine("  " .. key, stats[key])
		end
		if #rings > 0 then
			lines[#lines + 1] = "Intervalos entre ações iguais (300 ms a 15 s):"
			for _, line in ipairs(rings) do
				lines[#lines + 1] = line
			end
		end
		lines[#lines + 1] = ringLine("Reação após dano", stats.reaction) or "Reação após dano: sem amostras"
		if stats.ping and stats.ping >= 0 then
			lines[#lines + 1] = string.format("Ping informado pelo cliente: %s ms.", fmt(stats.ping))
		end
		lines[#lines + 1] = string.format("Rajadas: %d. Pacotes de ação: %d. Última ação há %s s.", stats.bursts, stats.packets, fmt(stats.idle / 1000))
		lines[#lines + 1] = string.format("Assinatura do cliente: %d pings do OTCv8, %d opcodes estendidos, %d passos antigos, %d passos novos.",
			stats.newPings or 0, stats.extOpcodes or 0, stats.oldSteps or 0, stats.newSteps or 0)
	else
		lines[#lines + 1] = "Sem dados do detector ainda."
	end
	local t = now()
	lines[#lines + 1] = string.format("Ativo sem pausa há %s.", hours(t - state.activeSince))
	if state.huntSince and state.lastExpAt and t - state.lastExpAt < BotDetector.config.huntBreakMinutes * 60 then
		lines[#lines + 1] = string.format("Caçando no mesmo lugar há %s.", hours(t - state.huntSince))
	end
	return lines
end

local function verdictOf(score)
	local cfg = BotDetector.config
	if score >= cfg.suspectScore then
		return "suspeito"
	elseif score >= cfg.attentionScore then
		return "atenção"
	end
	return "normal"
end

function BotDetector.describe(player)
	local state = BotDetector.getState(player)
	local stats = getBotDetectorStats(player:getId())
	local score, reasons = BotDetector.evaluate(player, state, stats)
	local lines = { string.format("%s: %d pontos, %d%% de chance de bot (%s)", player:getName(), score,
		BotDetector.percent(score, state, stats), verdictOf(score)) }
	for _, reason in ipairs(reasons) do
		lines[#lines + 1] = "- " .. reason
	end
	for _, line in ipairs(BotDetector.detailLines(state, stats)) do
		lines[#lines + 1] = line
	end
	if state.pendingCheck then
		lines[#lines + 1] = "Verificação pendente."
	end
	return table.concat(lines, "\n")
end

-- Score to an estimated chance. The steps follow the thresholds above: one
-- signal alone (2) is "attention", a proven bot signal (3+) is "suspect".
local PERCENT = { [0] = 3, 15, 40, 70, 85, 93, 97 }
function BotDetector.percent(score, state, stats)
	if state.verifiedUntil > now() then
		return 1
	end
	if score <= 0 and (not stats or stats.packets < 50) then
		return 0 -- not enough data to say anything
	end
	return PERCENT[math.min(score, 6)]
end

-- Inspect bot window (client module game_botinspect, opcode 135). Staff only.
BotDetector.OPCODE = 135

function BotDetector.report(player, note)
	local state = BotDetector.getState(player)
	local stats = getBotDetectorStats(player:getId())
	local score, reasons = BotDetector.evaluate(player, state, stats)
	local t = now()
	local check = { failed = state.checkFailed }
	if state.pendingCheck then
		check.state = "pending"
		check.left = math.max(0, BotDetector.config.checkTimeout - (t - state.pendingCheck.sentAt))
		check.by = state.pendingCheck.by
	elseif state.verifiedUntil > t then
		check.state = "verified"
		check.left = state.verifiedUntil - t
	else
		check.state = state.lastCheck or "none"
	end
	local enough = stats and stats.packets >= 50
	return {
		action = "report",
		name = player:getName(),
		level = player:getLevel(),
		score = score,
		percent = BotDetector.percent(score, state, stats),
		verdict = (score <= 0 and not enough) and "sem dados" or verdictOf(score),
		reasons = reasons,
		details = BotDetector.detailLines(state, stats),
		minutes = stats and math.floor(stats.tracked / 60000) or 0,
		actions = stats and stats.packets or 0,
		check = check,
		note = note,
	}
end

function BotDetector.sendReport(staff, target, note)
	staff:sendExtendedOpcode(BotDetector.OPCODE, json.encode(BotDetector.report(target, note)))
end

-- A check result goes back to the staff member who started it, if online.
function BotDetector.notifyChecker(target, staffName, text)
	if not staffName or staffName == "auto" then
		return
	end
	local staff = Player(staffName)
	if staff and isStaff(staff) then
		BotDetector.sendReport(staff, target, text)
	end
end

function BotDetector.handleInspect(staff, action, name)
	local target = Player(name)
	if not target then
		staff:sendExtendedOpcode(BotDetector.OPCODE, json.encode({ action = "offline", name = name }))
		return
	end
	if isStaff(target) then
		staff:sendExtendedOpcode(BotDetector.OPCODE, json.encode({ action = "offline", name = name, staff = true }))
		return
	end
	local note
	if action == "check" then
		local state = BotDetector.getState(target)
		if state.pendingCheck then
			note = "Já existe uma verificação pendente."
		else
			BotDetector.sendCheck(target, staff:getName())
			note = "Verificação enviada. O resultado aparece aqui e no chat."
		end
	elseif action == "clear" then
		BotDetector.clear(target, staff:getName())
		note = "Marcado como humano por 2 horas."
	end
	BotDetector.sendReport(staff, target, note)
end
