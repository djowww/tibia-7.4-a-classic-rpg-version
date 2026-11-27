-- Avisa todo mundo quando comeca e quando acaba a noite de caca (19:00-05:00 do jogo).
local wasNight = nil

function onThink(interval)
	local night = isHuntNight()
	if wasNight ~= nil and night ~= wasNight then
		if night then
			Game.broadcastMessage(string.format("The hunting night has begun. Until dawn monsters give %d%% more experience and loot, return faster and hit harder.", HUNT_NIGHT_EXP_PERCENT), MESSAGE_EVENT_ADVANCE)
		else
			Game.broadcastMessage("The sun is rising. The hunting night is over.", MESSAGE_EVENT_ADVANCE)
		end
	end
	wasNight = night
	return true
end
