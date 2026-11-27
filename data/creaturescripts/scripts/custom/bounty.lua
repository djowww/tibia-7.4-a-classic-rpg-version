-- Recompensa pela cabeca do PK (ver data/lib/custom/bounty.lua).
function onDeath(player, corpse, killer, mostDamageKiller, unjustified, mostDamageUnjustified)
	local hunter = bountyPlayerOf(killer) or bountyPlayerOf(mostDamageKiller)

	-- 1) Quem morreu tinha recompensa: paga o cacador.
	local bounty = player:getBounty()
	if bounty > 0 and hunter and hunter ~= player then
		player:setBounty(0)
		hunter:setBankBalance(hunter:getBankBalance() + bounty)
		-- Salva na hora: quem morreu ja e salvo com a recompensa zerada, e uma
		-- queda do servidor antes do save automatico faria o ouro sumir.
		hunter:save()
		hunter:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You collected the bounty of %d gold on %s. It was sent to your bank account.", bounty, player:getName()))
		Game.broadcastMessage(string.format("%s collected the bounty of %d gold on the head of %s.", hunter:getName(), bounty, player:getName()), MESSAGE_STATUS_WARNING)
	end

	-- 2) Morte injusta: o assassino paga a propria recompensa.
	local function charge(murderer)
		if not murderer or murderer == player then
			return
		end
		local wanted = murderer:getLevel() * BOUNTY_GOLD_PER_LEVEL
		local paid = murderer:chargeBounty(wanted)
		if paid <= 0 then
			return
		end
		murderer:setBounty(murderer:getBounty() + paid)
		murderer:sendTextMessage(MESSAGE_STATUS_WARNING, string.format("You murdered %s. %d gold of your money is now a bounty on your head (total %d gold).", player:getName(), paid, murderer:getBounty()))
	end

	local lastHitPlayer = bountyPlayerOf(killer)
	local mostDamagePlayer = bountyPlayerOf(mostDamageKiller)
	if unjustified then
		charge(lastHitPlayer)
	end
	if mostDamageUnjustified and mostDamagePlayer ~= lastHitPlayer then
		charge(mostDamagePlayer)
	end
	return true
end
