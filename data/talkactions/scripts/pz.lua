function onSay(player, words, param)
	local condition = player:isPzLocked() and player:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
	if not condition then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "You don't have Pz")
		return false
	end

	local seconds = math.max(0, math.floor(condition:getEndTime() / 1000) - os.time())
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "You have to wait " .. seconds .. " second" .. (seconds == 1 and "" or "s") .. " for pz.")
	return false
end
