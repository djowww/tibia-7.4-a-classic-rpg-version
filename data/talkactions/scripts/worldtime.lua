-- !time mostra a hora do jogo; /worldtime HH:MM (GM) muda a hora para testar o dia e a noite.
-- Um dia do jogo dura 4 horas reais: 2 h de dia (06:00-18:00) e 2 h de noite.
local function describe(minutes)
	if minutes >= 300 and minutes < 420 then
		return "dawn"
	elseif minutes >= 420 and minutes < 1020 then
		return "day"
	elseif minutes >= 1020 and minutes < 1140 then
		return "dusk"
	end
	return "night"
end

function onSay(player, words, param)
	if words == "/worldtime" and param ~= "" then
		local hours, minutes = param:match("^%s*(%d+):(%d+)%s*$")
		hours, minutes = tonumber(hours), tonumber(minutes)
		if not hours or hours > 23 or minutes > 59 then
			player:sendCancelMessage("Usage: /worldtime HH:MM")
			return false
		end
		setWorldTime(hours * 60 + minutes)
	end

	local worldTime = getWorldTime()
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "The time is " .. getFormattedWorldTime() .. " (" .. describe(worldTime) .. ").")
	return false
end
