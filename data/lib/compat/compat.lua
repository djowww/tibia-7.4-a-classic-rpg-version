TRUE = true
FALSE = false

result.getDataInt = result.getNumber
result.getDataLong = result.getNumber
result.getDataString = result.getString
result.getDataStream = result.getStream

LUA_ERROR = false
LUA_NO_ERROR = true

STACKPOS_GROUND = 0
STACKPOS_FIRST_ITEM_ABOVE_GROUNDTILE = 1
STACKPOS_SECOND_ITEM_ABOVE_GROUNDTILE = 2
STACKPOS_THIRD_ITEM_ABOVE_GROUNDTILE = 3
STACKPOS_FOURTH_ITEM_ABOVE_GROUNDTILE = 4
STACKPOS_FIFTH_ITEM_ABOVE_GROUNDTILE = 5
STACKPOS_TOP_CREATURE = 253
STACKPOS_TOP_FIELD = 254
STACKPOS_TOP_MOVEABLE_ITEM_OR_CREATURE = 255

THING_TYPE_PLAYER = 1 + 1
THING_TYPE_MONSTER = 2 + 1
THING_TYPE_NPC = 3 + 1

COMBAT_POISONDAMAGE = COMBAT_EARTHDAMAGE
TALKTYPE_ORANGE_1 = TALKTYPE_MONSTER_SAY
TALKTYPE_ORANGE_2 = TALKTYPE_MONSTER_YELL

NORTH = DIRECTION_NORTH
EAST = DIRECTION_EAST
SOUTH = DIRECTION_SOUTH
WEST = DIRECTION_WEST
SOUTHWEST = DIRECTION_SOUTHWEST
SOUTHEAST = DIRECTION_SOUTHEAST
NORTHWEST = DIRECTION_NORTHWEST
NORTHEAST = DIRECTION_NORTHEAST

do
	local function CreatureIndex(self, key)
		local methods = getmetatable(self)
		if key == "uid" then
			return methods.getId(self)
		elseif key == "type" then
			local creatureType = 0
			if methods.isPlayer(self) then
				creatureType = THING_TYPE_PLAYER
			elseif methods.isMonster(self) then
				creatureType = THING_TYPE_MONSTER
			elseif methods.isNpc(self) then
				creatureType = THING_TYPE_NPC
			end
			return creatureType
		elseif key == "itemid" then
			return 1
		elseif key == "actionid" then
			return 0
		end
		return methods[key]
	end
	rawgetmetatable("Player").__index = CreatureIndex
	rawgetmetatable("Monster").__index = CreatureIndex
	rawgetmetatable("Npc").__index = CreatureIndex
end

do
	local function ItemIndex(self, key)
		local methods = getmetatable(self)
		if key == "itemid" then
			return methods.getId(self)
		elseif key == "actionid" then
			return methods.getActionId(self)
		elseif key == "uid" then
			return methods.getUniqueId(self)
		elseif key == "type" then
			return methods.getSubType(self)
		end
		return methods[key]
	end
	rawgetmetatable("Item").__index = ItemIndex
	rawgetmetatable("Container").__index = ItemIndex
	rawgetmetatable("Teleport").__index = ItemIndex
end

function pushThing(thing)
	local t = {uid = 0, itemid = 0, type = 0, actionid = 0}
	if thing ~= nil then
		if thing:isItem() then
			t.uid = thing:getUniqueId()
			t.itemid = thing:getId()
			if ItemType(t.itemid):hasSubType() then
				t.type = thing:getSubType()
			end
			t.actionid = thing:getActionId()
		elseif thing:isCreature() then
			t.uid = thing:getId()
			t.itemid = 1
			if thing:isPlayer() then
				t.type = THING_TYPE_PLAYER
			elseif thing:isMonster() then
				t.type = THING_TYPE_MONSTER
			else
				t.type = THING_TYPE_NPC
			end
		end
	end
	return t
end

createCombatObject = Combat
setCombatArea = Combat.setArea
setCombatCallback = Combat.setCallback
setCombatCondition = Combat.setCondition
setCombatFormula = Combat.setFormula
setCombatParam = Combat.setParameter

createConditionObject = Condition
setConditionParam = Condition.setParameter
setConditionFormula = Condition.setFormula
addDamageCondition = Condition.addDamage
addOutfitCondition = Condition.setOutfit

function doCombat(cid, combat, var) return combat:execute(cid, var) end

function isCreature(cid) return Creature(cid) ~= nil end
function isPlayer(cid) return Player(cid) ~= nil end
function isMonster(cid) return Monster(cid) ~= nil end
function isNpc(cid) return Npc(cid) ~= nil end
function isItem(uid) return Item(uid) ~= nil end
function isContainer(uid) return Container(uid) ~= nil end

function getCreaturePosition(cid) local c = Creature(cid) return c ~= nil and c:getPosition() or false end

getCreaturePos = getCreaturePosition

function doCreatureSetLookDir(cid, direction) local c = Creature(cid) return c ~= nil and c:setDirection(direction) or false end

doSetCreatureDirection = doCreatureSetLookDir

function getIPByPlayerName(name) local p = Player(name) return p ~= nil and p:getIp() or false end
function getPlayerBalance(cid) local p = Player(cid) return p ~= nil and p:getBankBalance() or false end
function getPlayerSkullType(cid) local p = Player(cid) return p ~= nil and p:getSkull() or false end
function isPremium(cid) local p = Player(cid) return p ~= nil and p:isPremium() or false end

getPlayerAccountBalance = getPlayerBalance
getIpByName = getIPByPlayerName

function doPlayerSendCancel(cid, text) local p = Player(cid) return p ~= nil and p:sendCancelMessage(text) or false end

doPlayerSendDefaultCancel = doPlayerSendCancel

function doRemoveItem(uid, ...) local i = Item(uid) return i ~= nil and i:remove(...) or false end

function isSightClear(fromPos, toPos, floorCheck) return Position(fromPos):isSightClear(toPos, floorCheck) end

function isItemMovable(itemId) return ItemType(itemId):isMovable() end
function isCorpse(uid) local i = Item(uid) return i ~= nil and ItemType(i:getId()):isCorpse() or false end

isItemMoveable = isItemMovable
isMoveable = isMovable

function hasProperty(uid, prop)
	local item = Item(uid)
	if item == nil then
		return false
	end

	local parent = item:getParent()
	if parent:isTile() and item == parent:getGround() then
		return parent:hasProperty(prop)
	else
		return item:hasProperty(prop)
	end
end

function getTopCreature(position)
	local t = Tile(position)
	if t == nil then
		return pushThing(nil)
	end
	return pushThing(t:getTopCreature())
end

function getThingfromPos(pos)
	local tile = Tile(pos)
	if tile == nil then
		return pushThing(nil)
	end

	local thing
	local stackpos = pos.stackpos or 0
	if stackpos == STACKPOS_TOP_MOVEABLE_ITEM_OR_CREATURE then
		thing = tile:getTopCreature()
		if thing == nil then
			local item = tile:getTopDownItem()
			if item ~= nil and item:getType():isMovable() then
				thing = item
			end
		end
	elseif stackpos == STACKPOS_TOP_FIELD then
		thing = tile:getFieldItem()
	elseif stackpos == STACKPOS_TOP_CREATURE then
		thing = tile:getTopCreature()
	else
		thing = tile:getThing(stackpos)
	end
	return pushThing(thing)
end

function doRelocate(fromPos, toPos)
	if fromPos == toPos then
		return false
	end

	local fromTile = Tile(fromPos)
	if fromTile == nil then
		return false
	end

	if Tile(toPos) == nil then
		return false
	end

	for i = fromTile:getThingCount() - 1, 0, -1 do
		local thing = fromTile:getThing(i)
		if thing ~= nil then
			if thing:isItem() then
				if ItemType(thing:getId()):isMovable() then
					thing:moveTo(toPos)
				elseif ItemType(thing:getId()):isMagicField() then
					thing:remove()
				elseif ItemType(thing:getId()):isSplash() then
					thing:remove()
				end
			elseif thing:isCreature() then
				thing:teleportTo(toPos)
			end
		end
	end
	return true
end

function getThing(uid)
	return uid >= 0x10000000 and pushThing(Creature(uid)) or pushThing(Item(uid))
end

saveData = saveServer

function getGlobalStorageValue(key)
	return Game.getStorageValue(key) or -1
end

function setGlobalStorageValue(key, value)
	Game.setStorageValue(key, value)
	return true
end

getWorldType = Game.getWorldType

numberToVariant = Variant
stringToVariant = Variant
positionToVariant = Variant

variantToNumber = Variant.getNumber
variantToString = Variant.getString
variantToPosition = Variant.getPosition

function getSpectators(centerPos, rangex, rangey, multifloor, onlyPlayers)
	local result = Game.getSpectators(centerPos, multifloor, onlyPlayers or false, rangex, rangex, rangey, rangey)
	if #result == 0 then
		return nil
	end

	for index, spectator in ipairs(result) do
		result[index] = spectator:getId()
	end
	return result
end

function broadcastMessage(message, messageType)
	Game.broadcastMessage(message, messageType)
	print("> Broadcasted message: \"" .. message .. "\".")
end
