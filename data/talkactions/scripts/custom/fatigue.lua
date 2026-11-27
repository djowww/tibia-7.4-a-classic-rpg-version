-- !fatigue mostra de quais criaturas voce esta cansado e se e noite de caca.
function onSay(player, words, param)
	local lines = {}
	if isHuntNight() then
		lines[#lines + 1] = string.format("It is a hunting night: +%d%% experience and loot, but monsters hit harder.", HUNT_NIGHT_EXP_PERCENT)
	else
		lines[#lines + 1] = "Hunting nights run from 19:00 to 05:00 game time (!time)."
	end
	local list = player:getHuntFatigueList()
	if #list == 0 then
		lines[#lines + 1] = "You are not tired of any creature."
	else
		lines[#lines + 1] = "Tired of:"
		for _, entry in ipairs(list) do
			lines[#lines + 1] = string.format("- %s: -%d%% experience", entry.name, entry.percent)
		end
	end
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, table.concat(lines, "\n"))
	return false
end
