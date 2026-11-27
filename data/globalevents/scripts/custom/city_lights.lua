-- Acende as luzes das cidades no fim da tarde e volta ao normal quando amanhece (ver data/lib/custom/cityLights.lua).
function onStartup()
	local count = CityLights.scan()
	print(string.format(">> City lights: %d fixed lights found in towns.", count))
	CityLights.update()
	return true
end

function onThink(interval)
	CityLights.update()
	return true
end
