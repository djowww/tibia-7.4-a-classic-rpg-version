function onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end

	if player:getAccountType() < ACCOUNT_TYPE_GAMEMASTER then
		return false
	end

	local position = player:getPosition()
	local isGhost = not player:isInGhostMode()

	player:setGhostMode(isGhost)
	-- avisa o cliente para deixar o GOD andar por paredes e agua (game_walking)
	player:sendExtendedOpcode(133, isGhost and "1" or "0")
	if isGhost then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You are now invisible.")
		position:sendMagicEffect(CONST_ME_POFF)
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You are visible again.")
		position:sendMagicEffect(CONST_ME_TELEPORT)
	end
	return false
end
