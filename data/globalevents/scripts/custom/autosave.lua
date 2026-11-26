-- Periodic world save (players, houses and house items). Without it the
-- world was saved only at the daily 06:00 restart, so a hard crash (OOM,
-- kill, VPS reboot) rolled back everyone still online and could duplicate
-- items that had already been handed to a player who logged out.
--
-- Saving everyone at once froze the server for about 3.5 ms per player
-- (1.9 s with 471 online in the 500-bot test). So this runs every 10 s
-- (interval in globalevents.xml) and saves one slice of the players each
-- time: every player is still saved once per 5 minutes, houses too.
local SLICES = 30 -- 30 ticks x 10 s = 5 minutes
local tick = 0

function onThink(interval)
	if Game.getGameState() ~= GAME_STATE_NORMAL then
		return true
	end

	local slice = tick % SLICES
	tick = tick + 1

	local start = os.mtime()
	local saved = 0
	for _, player in ipairs(Game.getPlayers()) do
		if player:getGuid() % SLICES == slice then
			player:save()
			saved = saved + 1
		end
	end
	if slice == 0 then
		saveHouses()
	end

	local elapsed = os.mtime() - start
	if elapsed >= 200 then
		print(string.format("[AutoSave] slice %d: %d players saved in %d ms (%d online)", slice, saved, elapsed, Game.getPlayerCount()))
	end
	return true
end
