function onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL then
		ExplorationChests.apply(player)
	end
	return true
end

function onExtendedOpcode(player, opcode, buffer)
	return ExplorationChests.onExtendedOpcode(player, opcode, buffer)
end
