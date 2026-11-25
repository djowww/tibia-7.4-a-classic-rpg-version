-- Scores every online player once a minute; see data/lib/custom/botDetector.lua.
function onThink(interval)
	BotDetector.checkAll()
	return true
end
