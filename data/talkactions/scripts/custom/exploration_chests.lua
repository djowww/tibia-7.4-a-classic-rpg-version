-- Staff only: where this boot placed each exploration chest, with a /gotopos
-- to a free tile next to it.
local function besideChest(chest)
	for dx = -1, 1 do
		for dy = -1, 1 do
			local position = Position(chest.x + dx, chest.y + dy, chest.z)
			local tile = Tile(position)
			if (dx ~= 0 or dy ~= 0) and tile and tile:getGround() and not tile:hasFlag(TILESTATE_BLOCKSOLID) then
				return position
			end
		end
	end
	return chest
end

function onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end

	local lines = {"Exploration chests:"}
	for index, region in ipairs(ExplorationChests.regions) do
		local chest = ExplorationChests.placed[index]
		if chest then
			local go = besideChest(chest)
			lines[#lines + 1] = string.format("%s: %d, %d, %d (/gotopos %d,%d,%d)", region.name, chest.x, chest.y, chest.z, go.x, go.y, go.z)
		else
			lines[#lines + 1] = string.format("%s: not placed", region.name)
		end
	end
	player:showTextDialog(2472, table.concat(lines, "\n"))
	return false
end
