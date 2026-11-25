-- The client asks for the staff command list when a GM or GOD presses F1.
function onExtendedOpcode(player, opcode, buffer)
	if opcode ~= GmCommands.OPCODE or buffer ~= 'list' then
		return false
	end
	GmCommands.send(player)
	return true
end
