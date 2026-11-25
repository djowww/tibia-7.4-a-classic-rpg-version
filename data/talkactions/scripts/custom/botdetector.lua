-- Staff commands of the bot detector (data/lib/custom/botDetector.lua) and
-- the players' answer to the in-game check. Alerts only, no punishment.
local function findTarget(player, param)
	local name = param and param:match("^%s*(.-)%s*$") or ""
	if name == "" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Informe o nome do personagem.")
		return nil
	end
	local target = Player(name)
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Personagem " .. name .. " não está online.")
	end
	return target
end

local function suspects(player)
	local rows = {}
	for _, target in ipairs(Game.getPlayers()) do
		if not BotDetector.isStaff(target) then
			local state = BotDetector.players[target:getGuid()]
			if state and state.score and state.score > 0 then
				rows[#rows + 1] = state
			end
		end
	end
	table.sort(rows, function(a, b) return a.score > b.score end)

	local lines = { "Suspeitos online (pontos: 2 = atenção, 3+ = suspeito):" }
	for _, state in ipairs(rows) do
		lines[#lines + 1] = string.format("%s - %d: %s", state.name, state.score, table.concat(state.reasons, "; "))
	end
	if #rows == 0 then
		lines[#lines + 1] = "nenhum."
	end
	local history = BotDetector.history
	if #history > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Últimos alertas:"
		for i = #history, math.max(1, #history - 9), -1 do
			local alert = history[i]
			lines[#lines + 1] = string.format("%s %s (%d)", os.date("%d/%m %H:%M", alert.time), alert.name, alert.score)
		end
	end
	player:showTextDialog(1998, table.concat(lines, "\n"), false)
end

function onSay(player, words, param)
	if words == "!human" or words == "!humano" then
		BotDetector.answer(player, param)
		return false
	end

	if not player:getGroup():getAccess() or player:getAccountType() < ACCOUNT_TYPE_GAMEMASTER then
		return true
	end

	if words == "/suspects" then
		BotDetector.checkAll()
		suspects(player)
	elseif words == "/botinfo" then
		local target = findTarget(player, param)
		if target then
			player:showTextDialog(1998, BotDetector.describe(target), false)
		end
	elseif words == "/botcheck" then
		local target = findTarget(player, param)
		if target then
			BotDetector.sendCheck(target, player:getName())
			player:sendTextMessage(MESSAGE_INFO_DESCR, "Verificação enviada para " .. target:getName() .. ". Você será avisado do resultado.")
		end
	elseif words == "/botclear" then
		local target = findTarget(player, param)
		if target then
			BotDetector.clear(target, player:getName())
			player:sendTextMessage(MESSAGE_INFO_DESCR, target:getName() .. " marcado como verificado por 2 horas.")
		end
	end
	return false
end
