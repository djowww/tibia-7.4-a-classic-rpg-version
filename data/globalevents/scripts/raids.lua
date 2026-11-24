local raids = {
	-- Weekly
	--Segunda-Feira
	['Monday'] = {
		['06:00'] = {raidName = 'thaiscaverats'},
		['18:00'] = {raidName = 'horses'},
		['21:00'] = {raidName = 'darashiawaspplague'}
	},

	--Terça-Feira
	['Tuesday'] = {
		['16:00'] = {raidName = 'panther'},
		['18:00'] = {raidName = 'horses'}
	},

	--Quarta-Feira
	['Wednesday'] = {
		['12:00'] = {raidName = 'orcbp'},
		['18:00'] = {raidName = 'horses'}
	},

	--Quinta-Feira
	['Thursday'] = {
		['22:00'] = {raidName = 'kazordoonhornedfox'},
		['18:00'] = {raidName = 'horses'},
		['21:00'] = {raidName = 'darashiawaspplague'}
	},

	--Sexta-feira
	['Friday'] = {
		['06:00'] = {raidName = 'foldayetis'},
		['18:00'] = {raidName = 'horses'},
		['20:00'] = {raidName = 'cavesgrorlam0'}
	},

	--Sábado
	['Saturday'] = {
		['20:00'] = {raidName = 'pohdemodras'},
		['18:00'] = {raidName = 'horses'},
		['14:00'] = {raidName = 'mintwalinminogeneral'},
		['02:00'] = {raidName = 'drefianecromancer'}
	},

	--Domingo
	['Sunday'] = {
		['23:00'] = {raidName = 'panther'},
		['18:00'] = {raidName = 'horses'}
	},

	-- By date (Day/Month)
	['31/10'] = {
		['16:00'] = {raidName = 'halloweenhare'}
	}
}

-- A raid may start up to RETRY_MINUTES after its time. The globalevent can skip a
-- minute, and Game.startRaid refuses while another raid is still running.
local RETRY_MINUTES = 30

local schedule = {}
for key, entries in pairs(raids) do
	local list = {}
	for clock, settings in pairs(entries) do
		local hour, minute = clock:match('^(%d%d):(%d%d)$')
		if hour then
			settings.minute = tonumber(hour) * 60 + tonumber(minute)
			list[#list + 1] = settings
		else
			print('[Warning - raids.lua] Invalid raid time ' .. tostring(clock) .. ' for ' .. tostring(key))
		end
	end
	schedule[key] = list
end

local function startDue(list, today, minuteOfDay)
	if not list then
		return
	end
	for i = 1, #list do
		local settings = list[i]
		local late = minuteOfDay - settings.minute
		if late >= 0 and late <= RETRY_MINUTES and settings.lastExecutedDate ~= today then
			if Game.startRaid(settings.raidName) then
				settings.lastExecutedDate = today
			end
		end
	end
end

function onThink(interval, lastExecution, thinkInterval)
	local now = os.date('*t')
	local today = string.format('%04d-%02d-%02d', now.year, now.month, now.day)
	local minuteOfDay = now.hour * 60 + now.min
	startDue(schedule[os.date('%A')], today, minuteOfDay)
	startDue(schedule[string.format('%02d/%02d', now.day, now.month)], today, minuteOfDay)
	return true
end
