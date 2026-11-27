-- Token of the launcher session, sent by the client module game_guardian.
function onExtendedOpcode(player, opcode, buffer)
	return Guardian.onExtendedOpcode(player, opcode, buffer)
end
