-- Postes e lampioes que nao tinham script proprio: liga/desliga como antes,
-- mas a noite as luzes da cidade nao apagam.
function onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if CityLights.blocksUse(player, item) then
		player:sendCancelMessage("The city lights stay lit until dawn.")
		return true
	end

	local transformId = CITY_LIGHT_PAIRS[item:getId()] or CITY_LIGHT_UNLIT[item:getId()]
	if not transformId then
		return false
	end
	item:transform(transformId)
	return true
end
