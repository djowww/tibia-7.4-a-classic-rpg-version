-- Game Wiki: Bestiary (with kill progress), Itempedia, Hunting Guide and Bosstiary.
-- The data files are generated from the server files by tools/generate-game-wiki.py.
local catalog = dofile('/modules/game_wiki/data/monsters.lua')
local monsters, bosses = catalog.monsters, catalog.bosses
local items = dofile('/modules/game_wiki/data/items.lua')
local hunts = dofile('/modules/game_wiki/data/hunts.lua')

local BESTIARY_OPCODE = 124
local BESTIARY_MAX_KILLS = 1000
local MAX_ITEM_ROWS = 120
local MAX_HUNTS = 40
local HUNT_SOON_LEVELS = 10
local MAP_FLAG_ICON = 9
local TABS = {'bestiary', 'itempedia', 'hunting', 'bosstiary'}
local RARITY = {'Very rare', 'Rare', 'Uncommon', 'Common'}
local VOCATIONS = {'K', 'P', 'S', 'D'}

local wikiWindow
local activeTab = 'bestiary'
local activeFilter = 'all'
local selectedMonster = 1
local selectedItem = 1
local itemCategory = 'All'
local huntVocation, huntLevel, huntMode = 'K', 20, 'solo'
local huntFromCharacter = false
local bestiaryProgress = {}
local bestiaryCompletedCount = 0
local monsterRows = {}
local mapFlag
local built = false -- the lists need the sprites, which load with the first login

local monsterByName, itemByName, itemById = {}, {}, {}
for index, monster in ipairs(monsters) do monsterByName[monster.name] = index end
for index, item in ipairs(items) do
	itemByName[item.name] = index
	if not item.fluid and not itemById[item.id] then itemById[item.id] = index end
end

local function formatNumber(value)
	local formatted = tostring(math.floor(value)):reverse():gsub('(%d%d%d)', '%1,'):reverse()
	return formatted:sub(1, 1) == ',' and formatted:sub(2) or formatted
end

local function normalizedName(name)
	return tostring(name or ''):lower():gsub('%s+', ' ')
end

local function getKillCount(name)
	return math.max(0, math.min(BESTIARY_MAX_KILLS, tonumber(bestiaryProgress[normalizedName(name)]) or 0))
end

local function matchesProgress(kills)
	return activeFilter == 'all' or (activeFilter == 'progress' and kills > 0 and kills < BESTIARY_MAX_KILLS)
		or (activeFilter == 'completed' and kills >= BESTIARY_MAX_KILLS)
end

local function child(id)
	return wikiWindow:recursiveGetChildById(id)
end

local function setCreaturePreview(widget, outfit, limit)
	widget:setOutfit(outfit)
	-- Keep the pixel scale of the south-facing frame, up to the size of the slot.
	local thing = g_things.getThingType(outfit.type, ThingCategoryCreature)
	local pixels = thing and thing:getExactSize(0, 2, 0, 0, 0) or 32
	pixels = math.max(1, math.min(limit, pixels))
	widget:setSize({width = pixels, height = pixels})
end

local function setItemIcon(widget, item)
	widget:setItemId(item.id)
	if item.fluid then widget:setItemSubType(item.fluid) end
end

local function setLine(line, label, value)
	line.label:setText(label)
	line.value:setText(value)
end

local function killText(kills)
	return kills >= BESTIARY_MAX_KILLS and 'Complete' or (kills .. '/' .. BESTIARY_MAX_KILLS)
end

-- Minimap ---------------------------------------------------------------

function showOnMap(x, y, z, description)
	local minimap = modules.game_minimap and modules.game_minimap.minimapWidget
	if not minimap then return end
	local pos = {x = x, y = y, z = z}
	if mapFlag and not mapFlag:isDestroyed() then mapFlag:destroy() end
	minimap:setCameraPosition(pos)
	minimap:addFlag(pos, MAP_FLAG_ICON, description, true)
	mapFlag = minimap:getFlag(pos)
	if wikiWindow then
		child('status'):setText('Shown on the minimap: ' .. description .. '. Use Centre on the minimap to go back.')
	end
end

-- Bestiary --------------------------------------------------------------

local function updateStatus()
	if not wikiWindow then return end
	child('xpBonus'):setText(string.format('XP +%.1f%%', bestiaryCompletedCount * 0.2))
	local text = ''
	if activeTab == 'bestiary' then
		text = string.format('Completed %d / %d creatures. Each one grants +0.2%% permanent XP.', bestiaryCompletedCount, #monsters)
	elseif activeTab == 'itempedia' then
		text = #items .. ' items listed. Click a creature to open it in the Bestiary.'
	elseif activeTab == 'hunting' then
		text = #hunts .. ' hunting places on the map.'
	else
		text = #bosses .. ' bosses known so far.'
	end
	child('status'):setText(text)
end

local function updateMonsterDetail()
	local monster = monsters[selectedMonster]
	if not wikiWindow or not built or not monster then return end
	local kills = getKillCount(monster.name)
	setLine(child('killLine'), 'Kills', formatNumber(kills) .. ' / ' .. formatNumber(BESTIARY_MAX_KILLS))
	child('killProgressBar'):setPercent(kills * 100 / BESTIARY_MAX_KILLS)
	child('killProgressBar'):setVisible(kills > 0)
	child('killNote'):setText(kills >= BESTIARY_MAX_KILLS and 'Entry complete. +0.2% permanent experience earned.'
		or 'Complete this entry for +0.2% permanent experience.')
end

local function showMonster(index)
	local monster = monsters[index]
	if not wikiWindow or not monster then return end
	selectedMonster = index
	for _, row in ipairs(monsterRows) do row:setOn(row.monsterId == index) end

	setCreaturePreview(child('preview'), monster.look, 64)
	child('monsterName'):setText(monster.name)
	setLine(child('healthLine'), 'Health', formatNumber(monster.health))
	setLine(child('expLine'), 'Experience', formatNumber(monster.experience))
	local summon = 'Not possible'
	child('summonLine'):setTooltip('')
	if monster.manacost > 0 then
		local ways = {}
		if monster.summon then ways[#ways + 1] = 'summon' end
		if monster.convince then ways[#ways + 1] = 'convince' end
		summon = monster.manacost .. ' mana'
		child('summonLine'):setTooltip('Mana needed to ' .. table.concat(ways, ' or ') .. ' it.')
	end
	setLine(child('summonLine'), 'Summon', summon)
	updateMonsterDetail()

	local heading = 'WHERE TO FIND'
	if monster.places > #monster.spots then
		heading = string.format('WHERE TO FIND (%d largest of %d places)', #monster.spots, monster.places)
	end
	child('spotsHeading'):setText(heading)
	local spots = child('spots')
	spots:destroyChildren()
	for _, spot in ipairs(monster.spots) do
		local row = g_ui.createWidget('WikiSpotRow', spots)
		row.area:setText(spot.area)
		row.coords:setText(string.format('%d, %d, %d', spot.x, spot.y, spot.z))
		row:setTooltip(string.format('%d %s here', spot.n, monster.name))
		row.map.onClick = function() showOnMap(spot.x, spot.y, spot.z, monster.name) end
	end

	local loot = child('loot')
	loot:destroyChildren()
	for _, entry in ipairs(monster.loot) do
		local row = g_ui.createWidget('WikiItemRow', loot)
		row.item:setItemId(entry.id)
		row.name:setText(entry.max > 1 and (entry.name .. ' (up to ' .. entry.max .. ')') or entry.name)
		row.info:setText(RARITY[entry.r] or '')
		local target = itemById[entry.id]
		if target then
			row:setTooltip('Open ' .. entry.name .. ' in the Itempedia.')
			row.onClick = function() openItem(target) end
		end
	end
	child('lootEmpty'):setVisible(#monster.loot == 0)
end

local function refreshMonsterList(resetScroll)
	if not wikiWindow or not built then return end
	local list, scrollbar = child('bestiaryList'), child('bestiaryScroll')
	local text = child('bestiarySearch'):getText():lower()
	local visible = {}
	for index, monster in ipairs(monsters) do
		if matchesProgress(getKillCount(monster.name)) and (text == '' or monster.name:lower():find(text, 1, true)) then
			visible[#visible + 1] = index
		end
	end
	local rebuild = #monsterRows ~= #visible
	for position, index in ipairs(visible) do
		if rebuild or monsterRows[position].monsterId ~= index then rebuild = true break end
	end
	local oldScroll = scrollbar:getValue()
	if rebuild then
		list:destroyChildren()
		monsterRows = {}
		for _, index in ipairs(visible) do
			local monster = monsters[index]
			local row = g_ui.createWidget('WikiMonsterRow', list)
			row.monsterId = index
			setCreaturePreview(row.creature, monster.look, 32)
			row.name:setText(monster.name)
			row.onClick = function() showMonster(index) end
			monsterRows[#monsterRows + 1] = row
		end
	end
	for _, row in ipairs(monsterRows) do
		local kills = getKillCount(monsters[row.monsterId].name)
		row.info:setText(killText(kills))
		row.info:setColor(kills >= BESTIARY_MAX_KILLS and '#45D145' or '#929292')
		row:setOn(row.monsterId == selectedMonster)
	end
	child('bestiaryEmpty'):setVisible(#visible == 0)
	for _, filter in ipairs({'all', 'progress', 'completed'}) do
		child('filter_' .. filter):setOn(activeFilter == filter)
	end
	if resetScroll then scrollbar:setValue(0) elseif rebuild then scrollbar:setValue(oldScroll) end
end

function setProgressFilter(value)
	if value ~= 'all' and value ~= 'progress' and value ~= 'completed' then return end
	activeFilter = value
	refreshMonsterList(true)
end

function openMonster(index)
	if not monsters[index] then return end
	activeFilter = 'all'
	child('bestiarySearch'):setText('')
	setTab('bestiary')
	refreshMonsterList(false)
	showMonster(index)
	for position, row in ipairs(monsterRows) do
		if row.monsterId == index then
			child('bestiaryScroll'):setValue(math.max(0, (position - 4) * row:getHeight()))
			break
		end
	end
end

function openMonsterByName(name)
	if monsterByName[name] then openMonster(monsterByName[name]) end
end

-- Itempedia -------------------------------------------------------------

local itemRows = {}

local function showItem(index)
	local item = items[index]
	if not wikiWindow or not item then return end
	selectedItem = index
	for _, row in ipairs(itemRows) do row:setOn(row.itemIndex == index) end

	setItemIcon(child('itemIcon'), item)
	child('itemName'):setText(item.name)
	child('itemKind'):setText(item.cat)
	child('itemDescription'):setText(item.desc or '')

	local lines = child('itemLines')
	lines:destroyChildren()
	for _, pair in ipairs(item.lines) do
		setLine(g_ui.createWidget('WikiLine', lines), pair[1], pair[2])
	end
	lines:setHeight(math.max(1, #item.lines * 16))

	local drops = child('drops')
	drops:destroyChildren()
	for _, drop in ipairs(item.drops) do
		local target = monsterByName[drop[1]]
		local row = g_ui.createWidget('WikiMonsterRow', drops)
		if target then
			setCreaturePreview(row.creature, monsters[target].look, 32)
			row:setTooltip('Open ' .. drop[1] .. ' in the Bestiary.')
			row.onClick = function() openMonster(target) end
		end
		row.name:setText(drop[1])
		row.info:setText(RARITY[drop[2]] or '')
	end
	child('dropsEmpty'):setVisible(#item.drops == 0)

	local trades = child('trades')
	trades:destroyChildren()
	for _, trade in ipairs(item.npc) do
		local row = g_ui.createWidget('WikiTradeRow', trades)
		local amount = trade[5] > 1 and (' x' .. trade[5]) or ''
		row.text:setText(string.format('%s %s, %s%s', trade[1] == 'sells' and 'Buy from' or 'Sell to', trade[2], trade[3], amount))
		row.text:setColor(trade[1] == 'sells' and '#CFCFCF' or '#8FE08F')
		row.price:setText(formatNumber(trade[4]) .. ' gp')
	end
	child('tradeEmpty'):setVisible(#item.npc == 0)
end

local function refreshItemList(resetScroll)
	if not wikiWindow or not built then return end
	local list = child('itemList')
	local text = child('itemSearch'):getText():lower()
	local total = 0
	list:destroyChildren()
	itemRows = {}
	for index, item in ipairs(items) do
		if (itemCategory == 'All' or item.cat == itemCategory) and (text == '' or item.name:lower():find(text, 1, true)) then
			total = total + 1
			if #itemRows < MAX_ITEM_ROWS then
				local row = g_ui.createWidget('WikiItemRow', list)
				row.itemIndex = index
				setItemIcon(row.item, item)
				row.name:setText(item.name)
				row.info:setText(item.cat)
				row:setOn(index == selectedItem)
				row.onClick = function() showItem(index) end
				itemRows[#itemRows + 1] = row
			end
		end
	end
	local empty = child('itemEmpty')
	empty:setVisible(total == 0)
	if total > MAX_ITEM_ROWS and activeTab == 'itempedia' then
		child('status'):setText(string.format('Showing %d of %d items. Type a name to narrow the list.', MAX_ITEM_ROWS, total))
	elseif activeTab == 'itempedia' then
		updateStatus()
	end
	if resetScroll then child('itemScroll'):setValue(0) end
end

function openItem(index)
	local item = items[index]
	if not item then return end
	itemCategory = 'All'
	child('itemCategory'):setCurrentOption('All')
	child('itemSearch'):setText(item.name)
	setTab('itempedia')
	refreshItemList(true)
	showItem(index)
end

function openItemByName(name)
	if itemByName[name] then openItem(itemByName[name]) end
end

-- Hunting Guide ---------------------------------------------------------

local function huntBand(hunt)
	if huntMode == 'party' then return hunt.party end
	return hunt[huntVocation]
end

local function refreshHunts()
	if not wikiWindow or not built then return end
	for _, vocation in ipairs(VOCATIONS) do child('voc_' .. vocation):setOn(huntVocation == vocation) end
	child('mode_solo'):setOn(huntMode == 'solo')
	child('mode_party'):setOn(huntMode == 'party')
	setLine(child('levelLine'), 'LEVEL', tostring(huntLevel))

	local fit, soon = {}, {}
	for _, hunt in ipairs(hunts) do
		local band = huntBand(hunt)
		if band then
			if huntLevel >= band[1] and huntLevel <= band[2] then
				fit[#fit + 1] = hunt
			elseif huntLevel < band[1] and band[1] - huntLevel <= HUNT_SOON_LEVELS then
				soon[#soon + 1] = hunt
			end
		end
	end
	-- Best experience first among the places that fit; the next ones by how soon they open.
	table.sort(fit, function(a, b) if a.exp ~= b.exp then return a.exp > b.exp end return a.area < b.area end)
	table.sort(soon, function(a, b)
		local first, second = huntBand(a)[1], huntBand(b)[1]
		if first ~= second then return first < second end
		return a.area < b.area
	end)

	local list = child('huntList')
	list:destroyChildren()
	local shown = 0
	local function add(hunt, recommended)
		if shown >= MAX_HUNTS then return end
		shown = shown + 1
		local band = huntBand(hunt)
		local card = g_ui.createWidget('WikiHuntCard', list)
		card.title:setText(hunt.name .. ' - ' .. hunt.area)
		card.level:setText('Lv ' .. band[1] .. '-' .. band[2])
		card.tag:setText((recommended and 'Recommended' or ('From level ' .. band[1]))
			.. string.format('   %d, %d, %d', hunt.x, hunt.y, hunt.z))
		card.tag:setColor(recommended and '#45D145' or '#929292')
		local names = {}
		for _, entry in ipairs(hunt.mon) do names[#names + 1] = entry[2] .. ' ' .. entry[1] end
		card.creatures:setText(table.concat(names, ', '))
		card.danger:setText(hunt.danger and ('Beware: ' .. table.concat(hunt.danger, ', ')) or '')
		card:setHeight(hunt.danger and 82 or 64)
		card.map.onClick = function() showOnMap(hunt.x, hunt.y, hunt.z, hunt.name .. ' hunt') end
	end
	-- Two places per creature first, so the list shows different hunts.
	local perCreature, later = {}, {}
	for _, hunt in ipairs(fit) do
		perCreature[hunt.name] = (perCreature[hunt.name] or 0) + 1
		if perCreature[hunt.name] <= 2 then add(hunt, true) else later[#later + 1] = hunt end
	end
	for _, hunt in ipairs(later) do add(hunt, true) end
	for _, hunt in ipairs(soon) do add(hunt, false) end
	child('huntEmpty'):setVisible(shown == 0)
	child('huntScroll'):setValue(0)
end

function setHuntVocation(vocation)
	huntVocation = vocation
	refreshHunts()
end

function setHuntMode(mode)
	huntMode = mode
	refreshHunts()
end

function setHuntLevel(level)
	level = math.max(1, math.min(150, math.floor(tonumber(level) or huntLevel)))
	if level == huntLevel then return end
	huntLevel = level
	refreshHunts()
end

function useMyCharacter()
	local player = g_game.getLocalPlayer()
	if player then
		local ok, vocation = pcall(function() return player:getVocation() end)
		vocation = ok and VOCATIONS[(tonumber(vocation) or 0) % 10] or nil
		if vocation then huntVocation = vocation end
		local level = tonumber(player:getLevel()) or 0
		if level > 0 then huntLevel = math.min(150, level) end
	end
	if wikiWindow then
		child('huntLevel'):setValue(huntLevel)
		refreshHunts()
	end
end

-- Bosstiary -------------------------------------------------------------

local function buildBosses()
	local list = child('bossList')
	list:destroyChildren()
	for _, boss in ipairs(bosses) do
		local cell = g_ui.createWidget('WikiBossCell', list)
		setCreaturePreview(cell.frame.creature, boss.look, 64)
		cell.name:setText(boss.name)
		cell.info:setText('HP ' .. formatNumber(boss.health) .. '   XP ' .. formatNumber(boss.experience))
	end
end

-- Window ----------------------------------------------------------------

function setTab(tab)
	if not wikiWindow or not table.contains(TABS, tab) then return end
	activeTab = tab
	for _, name in ipairs(TABS) do
		child('tab_' .. name):setOn(name == tab)
		child(name .. 'Panel'):setVisible(name == tab)
	end
	if tab == 'hunting' and not huntFromCharacter then
		huntFromCharacter = true
		useMyCharacter()
	end
	updateStatus()
end

local function updateVisibleProgress()
	if not wikiWindow then return end
	refreshMonsterList(false)
	updateMonsterDetail()
	updateStatus()
end

local function requestProgress()
	if not g_game.isOnline() or not g_game.getFeature(GameExtendedOpcode) then return end
	local protocol = g_game.getProtocolGame()
	if not protocol then return end
	local names = {}
	for _, monster in ipairs(monsters) do names[#names + 1] = monster.name end
	protocol:sendExtendedOpcode(BESTIARY_OPCODE, json.encode({action = 'getProgress', monsters = names}))
end

local function onBestiaryOpcode(protocol, opcode, buffer)
	if opcode ~= BESTIARY_OPCODE or type(buffer) ~= 'string' or #buffer > 16384 then return end
	local decoded, payload = pcall(function() return json.decode(buffer) end)
	if not decoded or type(payload) ~= 'table' then return end

	if payload.action == 'progress' then
		if type(payload.data) ~= 'table' then return end
		bestiaryProgress = {}
		bestiaryCompletedCount = math.max(0, math.min(#monsters, tonumber(payload.completed) or 0))
		for name, kills in pairs(payload.data) do
			if type(name) == 'string' then
				bestiaryProgress[normalizedName(name)] = math.max(0, math.min(BESTIARY_MAX_KILLS, tonumber(kills) or 0))
			end
		end
	elseif payload.action == 'update' and type(payload.monster) == 'string' then
		bestiaryProgress[normalizedName(payload.monster)] = math.max(0, math.min(BESTIARY_MAX_KILLS, tonumber(payload.kills) or 0))
		if payload.completed ~= nil then
			bestiaryCompletedCount = math.max(0, math.min(#monsters, tonumber(payload.completed) or bestiaryCompletedCount))
		end
	else
		return
	end
	updateVisibleProgress()
end

-- The button of the inventory panel was made for the old Bestiary window.
local function renameInventoryButton()
	local inventory = modules.game_inventory
	local button = inventory and inventory.inventoryWindow and inventory.inventoryWindow:recursiveGetChildById('logoutButton')
	if button then
		button:setText('Wiki')
		button:setTooltip('Open the Game Wiki: bestiary, items, hunting places and bosses.')
	end
end

local function onGameStart()
	renameInventoryButton()
end

local function onGameEnd()
	bestiaryProgress = {}
	bestiaryCompletedCount = 0
	activeFilter = 'all'
	huntFromCharacter = false
	mapFlag = nil
	hide()
	updateVisibleProgress()
end

function resizeWiki()
	if not wikiWindow then return end
	local rootSize = rootWidget:getSize()
	wikiWindow:setSize({width = math.min(740, rootSize.width - 16), height = math.min(500, rootSize.height - 16)})
end

function init()
	wikiWindow = g_ui.displayUI('wiki')

	local category = child('itemCategory')
	local seen = {}
	category:addOption('All')
	for _, item in ipairs(items) do
		if not seen[item.cat] then
			seen[item.cat] = true
			category:addOption(item.cat)
		end
	end
	category.onOptionChange = function(_, text)
		itemCategory = text
		refreshItemList(true)
	end
	child('bestiarySearch').onTextChange = function() refreshMonsterList(true) end
	child('itemSearch').onTextChange = function() refreshItemList(true) end
	child('huntLevel').onValueChange = function(_, value) setHuntLevel(value) end
	child('huntLevel'):setValue(huntLevel)

	connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
	connect(rootWidget, {onGeometryChange = resizeWiki})
	ProtocolGame.registerExtendedOpcode(BESTIARY_OPCODE, onBestiaryOpcode, true)

	setTab(activeTab)
	renameInventoryButton()
end

local function build()
	if built or not g_things.isDatLoaded() then return end
	built = true
	buildBosses()
	refreshMonsterList(true)
	showMonster(selectedMonster)
	refreshItemList(true)
	showItem(selectedItem)
	refreshHunts()
end

function terminate()
	disconnect(rootWidget, {onGeometryChange = resizeWiki})
	disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
	ProtocolGame.unregisterExtendedOpcode(BESTIARY_OPCODE)
	if wikiWindow then wikiWindow:destroy() end
	wikiWindow, monsterRows, itemRows, mapFlag, built = nil, {}, {}, nil, false
end

function show()
	if not wikiWindow then return end
	resizeWiki()
	renameInventoryButton()
	build()
	refreshMonsterList(false)
	updateStatus()
	wikiWindow:show()
	wikiWindow:raise()
	wikiWindow:focus()
	requestProgress()
end

function hide()
	if wikiWindow then wikiWindow:hide() end
end

function toggle()
	if wikiWindow and wikiWindow:isVisible() then
		hide()
	else
		show()
	end
end
