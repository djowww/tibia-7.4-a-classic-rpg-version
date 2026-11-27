local drunk = Condition(CONDITION_DRUNK)
drunk:setParameter(CONDITION_PARAM_TICKS, 60000)

local poison = Condition(CONDITION_POISON)
poison:addDamage(1, 4000, -0)
poison:addDamage(1, 4000, -10)
poison:addDamage(2, 4000, -9)
poison:addDamage(2, 4000, -8)
poison:addDamage(3, 4000, -7)
poison:addDamage(3, 4000, -6)
poison:addDamage(4, 4000, -5)
poison:addDamage(4, 4000, -4)
poison:addDamage(6, 4000, -3)
poison:addDamage(10, 4000, -2)
poison:addDamage(10, 4000, -1)
poison:addDamage(10, 4000, -1)
poison:addDamage(10, 4000, -1)
poison:addDamage(8, 3950, -1)
poison:addDamage(1, 3940, -1)

local messages = {
	[FLUID_WATER] = "Gulp.",
	[FLUID_WINE] = "Aah...",
	[FLUID_BEER] = "Aah...",
	[FLUID_MUD] = "Gulp.",
	[FLUID_BLOOD] = "Gulp.",
	[FLUID_SLIME] = "Urgh!",
	[FLUID_OIL] = "Gulp.",
	[FLUID_URINE] = "Urgh!",
	[FLUID_MILK] = "Mmmh.",
	[FLUID_MANAFLUID] = "Aaaah...",
	[FLUID_LIFEFLUID] = "Aaaah...",
	[FLUID_LEMONADE] = "Mmmh."
}

function onUse(player, item, fromPosition, target, toPosition)
	if not target then
		return false
	end

	-- Using a fluid on a creature: its id is not an item id.
	local targetItemType = not target:isCreature() and ItemType(target:getId())
	if targetItemType and targetItemType:isFluidContainer() then
		if target:getFluidType() == 0 and item:getFluidType() ~= 0 then
			target:transform(target:getId(), item:getFluidType())
			item:transform(item:getId(), 0)
			return true
		elseif target:getFluidType() ~= 0 and item:getFluidType() == 0 then
			local fluid = target:getFluidType()
			target:transform(target:getId(), 0)
			item:transform(item:getId(), fluid)
			return true
		end
	end
	
	if target == player then
		if item:getFluidType() == FLUID_NONE then
			player:sendCancelMessage("It is empty.")
		else
            local restorative = item:getFluidType() == FLUID_MANAFLUID or item:getFluidType() == FLUID_LIFEFLUID
            if restorative then
                if player:getCondition(CONDITION_EXHAUST) then
                    player:sendCancelMessage(RETURNVALUE_YOUAREEXHAUSTED)
                    return true
                end
                local exhaustion = Condition(CONDITION_EXHAUST)
                exhaustion:setParameter(CONDITION_PARAM_TICKS, 1000)
                player:addCondition(exhaustion)
            end
			local fluid = item:getFluidType()
			if fluid == FLUID_BEER or fluid == FLUID_WINE then
				player:addCondition(drunk)
			elseif fluid == FLUID_SLIME then
				player:addCondition(poison)
			elseif fluid == FLUID_MANAFLUID then
				player:addMana(math.random(50, 150))
				player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
			elseif fluid == FLUID_LIFEFLUID then
				if player:getHealth() > 0 then
					player:addHealth(math.random(25, 75))
					player:removeCondition(CONDITION_PARALYZE)
				end
				player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
			end

			player:say(messages[fluid] or "Gulp.", TALKTYPE_SAY)
			item:transform(item:getId(), FLUID_NONE)
		end
	else
		if toPosition.x == CONTAINER_POSITION then
			toPosition = player:getPosition()
		end
		
		local tile = Tile(toPosition)
		if not tile then
			return false
		end
		
		if item:getFluidType() ~= FLUID_NONE and tile:hasFlag(TILESTATE_IMMOVABLEBLOCKSOLID) then
			return false
		end
		
		local fluidSource = targetItemType and targetItemType:getFluidSource() or FLUID_NONE
		if fluidSource ~= FLUID_NONE then
			item:transform(item:getId(), fluidSource)
		elseif item:getFluidType() == FLUID_NONE then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, "It is empty.")
		else

			Game.createItem(2886, item:getFluidType(), toPosition):decay()
			item:transform(item:getId(), FLUID_NONE)
		end
	end
	return true
end