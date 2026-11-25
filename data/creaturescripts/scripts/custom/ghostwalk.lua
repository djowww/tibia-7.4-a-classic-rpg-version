-- O cliente pergunta (opcode 133 "?") se o /ghost esta ligado, para liberar andar por paredes.
-- Cobre a reconexao, quando o onLogin nao roda de novo.
function onExtendedOpcode(player, opcode, buffer)
	if opcode ~= 133 or buffer ~= "?" then
		return false
	end
	if player:getGroup():getAccess() then
		player:sendExtendedOpcode(133, player:isInGhostMode() and "1" or "0")
	end
	return true
end
