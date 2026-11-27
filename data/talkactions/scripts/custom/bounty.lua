-- !bounty mostra as maiores recompensas e a sua.
function onSay(player, words, param)
	local lines = {"Bounties (kill them to collect the gold):"}
	local list = getTopBounties(10)
	if #list == 0 then
		lines[#lines + 1] = "Nobody has a bounty right now."
	end
	for i, entry in ipairs(list) do
		lines[#lines + 1] = string.format("%d. %s (level %d): %d gold", i, entry.name, entry.level, entry.gold)
	end
	local mine = player:getBounty()
	if mine > 0 then
		lines[#lines + 1] = string.format("Your own bounty: %d gold.", mine)
	end
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, table.concat(lines, "\n"))
	return false
end
