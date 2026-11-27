-- Recompensa pela cabeca de quem mata sem justificativa.
-- Cada morte injusta cobra do assassino (banco primeiro, depois a mochila)
-- 100 gold por level dele e poe esse ouro na cabeca dele. Quem matar o
-- assassino leva tudo direto no banco. O ouro so troca de mao: nao nasce ouro novo.

BOUNTY_STORAGE = 17890
BOUNTY_GOLD_PER_LEVEL = 100

function Player:getBounty()
	return math.max(0, self:getStorageValue(BOUNTY_STORAGE))
end

function Player:setBounty(value)
	self:setStorageValue(BOUNTY_STORAGE, math.max(0, math.min(2000000000, value)))
end

-- Tira o valor do banco e, se faltar, do dinheiro carregado. Devolve quanto tirou.
function Player:chargeBounty(amount)
	local bank = self:getBankBalance()
	local fromBank = math.min(bank, amount)
	if fromBank > 0 then
		self:setBankBalance(bank - fromBank)
	end
	local missing = amount - fromBank
	local fromBag = math.min(self:getMoney(), missing)
	if fromBag > 0 and not self:removeMoney(fromBag) then
		fromBag = 0
	end
	return fromBank + fromBag
end

-- Dono real de um ataque (jogador ou dono do summon).
function bountyPlayerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

-- Maiores recompensas, inclusive de quem esta offline.
function getTopBounties(limit)
	local list = {}
	local resultId = db.storeQuery("SELECT `p`.`name`, `p`.`level`, `s`.`value` FROM `player_storage` `s` JOIN `players` `p` ON `p`.`id` = `s`.`player_id` WHERE `s`.`key` = " .. BOUNTY_STORAGE .. " AND `s`.`value` > 0 ORDER BY `s`.`value` DESC LIMIT " .. limit)
	if resultId then
		repeat
			list[#list + 1] = {
				name = result.getDataString(resultId, "name"),
				level = result.getDataInt(resultId, "level"),
				gold = result.getDataInt(resultId, "value")
			}
		until not result.next(resultId)
		result.free(resultId)
	end
	-- Online, o valor da memoria e o mais novo.
	for _, entry in ipairs(list) do
		local online = Player(entry.name)
		if online then
			entry.gold = online:getBounty()
		end
	end
	for _, online in ipairs(Game.getPlayers()) do
		local gold = online:getBounty()
		if gold > 0 then
			local found = false
			for _, entry in ipairs(list) do
				if entry.name == online:getName() then
					found = true
					break
				end
			end
			if not found then
				list[#list + 1] = {name = online:getName(), level = online:getLevel(), gold = gold}
			end
		end
	end
	table.sort(list, function(a, b) return a.gold > b.gold end)
	while #list > limit do
		table.remove(list)
	end
	return list
end
