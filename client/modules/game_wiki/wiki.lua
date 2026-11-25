-- Game Wiki: Bestiary (with kill progress), Itempedia, Hunting Guide and Bosstiary.
-- The data files are generated from the server files by tools/generate-game-wiki.py.
local catalog = dofile('/modules/game_wiki/data/monsters.lua')
local monsters, bosses = catalog.monsters, catalog.bosses
local items = dofile('/modules/game_wiki/data/items.lua')
local hunts = dofile('/modules/game_wiki/data/hunts.lua')

local BESTIARY_OPCODE = 124
local BESTIARY_MAX_KILLS = 1000
local MAX_ITEM_ROWS = 120
local HUNT_PAGE = 6       -- hunts shown at first, and added by "Show more"
local HUNT_MIN_CREATURES = 4
local MAP_FLAG_ICON = 9
local TABS = {'bestiary', 'itempedia', 'hunting', 'bosstiary'}
local RARITY = {'Very rare', 'Rare', 'Uncommon', 'Common'}
local RARITY_COLOR = {'#F0C040', '#B070E0', '#5AA0E6', '#6E6E6E'}
local VOCATION_NAME = {K = 'knight', P = 'paladin', S = 'sorcerer', D = 'druid'}
local GROUND_FLOOR = 7
local VOCATIONS = {'K', 'P', 'S', 'D'}

local wikiWindow
local activeTab = 'bestiary'
local activeFilter = 'all'
local selectedMonster = 1
local selectedItem = 1
local itemCategory = 'All'
local huntVocation, huntLevel, huntMode = 'K', 20, 'solo'
local huntFromCharacter = false
local huntShown, huntStatus = HUNT_PAGE, ''
local bestiaryProgress = {}
local bestiaryCompletedCount = 0
local monsterRows = {}
local mapDots = {}
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
	return kills >= BESTIARY_MAX_KILLS and 'complete' or (kills .. ' / ' .. BESTIARY_MAX_KILLS .. ' kills')
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
		text = #items .. ' items in the Itempedia. Click a creature to open it in the Bestiary.'
	elseif activeTab == 'hunting' then
		text = huntStatus
	else
		text = #bosses .. ' bosses known so far.'
	end
	child('status'):setText(text)
end

local function updateMonsterDetail()
	local monster = monsters[selectedMonster]
	if not wikiWindow or not built or not monster then return end
	local kills = getKillCount(monster.name)
	local complete = kills >= BESTIARY_MAX_KILLS
	child('killText'):setText(formatNumber(kills) .. ' / ' .. formatNumber(BESTIARY_MAX_KILLS))
	child('killProgressBar'):setPercent(kills * 100 / BESTIARY_MAX_KILLS)
	child('killProgressBar'):setVisible(kills > 0)
	child('killBonus'):setColor(complete and '#45D145' or '#F0C040')
	local note = complete and 'Entry complete. +0.2% permanent experience earned.'
		or 'Kill 1,000 to complete this entry and earn +0.2% permanent experience.'
	child('killTrack'):setTooltip(note)
	child('killBonus'):setTooltip(note)
end

-- The places of a creature become dots on a small map: the surface of the
-- region that holds them all. A click sends the place to the real minimap.
local function showSpots(monster)
	local map = child('spotMap')
	for _, dot in ipairs(mapDots) do dot:destroy() end
	mapDots = {}
	local spots = monster.spots
	local heading = 'WHERE'
	if monster.places > #spots then
		heading = string.format('WHERE (%d largest of %d places)', #spots, monster.places)
	end
	child('spotsHeading'):setText(heading)
	if #spots == 0 then return end

	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, spot in ipairs(spots) do
		minX, maxX = math.min(minX, spot.x), math.max(maxX, spot.x)
		minY, maxY = math.min(minY, spot.y), math.max(maxY, spot.y)
	end
	local width, height = map:getWidth(), map:getHeight()
	if width < 50 or height < 50 then width, height = 420, 150 end -- not laid out yet
	local fit = math.min(width / (maxX - minX + 80), height / (maxY - minY + 80))
	local zoom = math.max(-5, math.min(0, math.floor(math.log(fit) / math.log(2))))
	map:setZoom(zoom)
	map:setCameraPosition({x = math.floor((minX + maxX) / 2), y = math.floor((minY + maxY) / 2), z = GROUND_FLOOR})

	for index = #spots, 1, -1 do -- the largest place stays on top
		local spot = spots[index]
		local dot = g_ui.createWidget('WikiMapDot', map)
		dot:setTooltip(string.format('%s (%d here). Click to see it on the minimap.', spot.area, spot.n))
		dot.onClick = function() showOnMap(spot.x, spot.y, spot.z, monster.name) end
		map:centerInPosition(dot, {x = spot.x, y = spot.y, z = GROUND_FLOOR})
		mapDots[#mapDots + 1] = dot
	end
end

local function showMonster(index)
	local monster = monsters[index]
	if not wikiWindow or not monster then return end
	selectedMonster = index
	for _, row in ipairs(monsterRows) do row:setOn(row.monsterId == index) end

	setCreaturePreview(child('preview'), monster.look, 64)
	child('monsterName'):setText(monster.name)
	child('healthStat').value:setText(formatNumber(monster.health))
	child('expStat').value:setText(formatNumber(monster.experience))
	local summon = child('summonStat')
	summon:setVisible(monster.manacost > 0)
	if monster.manacost > 0 then
		local ways = {}
		if monster.summon then ways[#ways + 1] = 'summon' end
		if monster.convince then ways[#ways + 1] = 'convince' end
		summon.value:setText(formatNumber(monster.manacost))
		summon:setTooltip('Mana needed to ' .. table.concat(ways, ' or ') .. ' it.')
	end
	updateMonsterDetail()
	showSpots(monster)

	local loot = child('loot')
	loot:destroyChildren()
	for _, entry in ipairs(monster.loot) do
		local cell = g_ui.createWidget('WikiLootCell', loot)
		cell.item:setItemId(entry.id)
		cell:setBorderColor(RARITY_COLOR[entry.r] or RARITY_COLOR[4])
		local name = entry.max > 1 and (entry.name .. ' (up to ' .. entry.max .. ')') or entry.name
		cell:setTooltip(name .. '\n' .. (RARITY[entry.r] or ''))
		local target = itemById[entry.id]
		if target then cell.onClick = function() openItem(target) end end
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
			local row = g_ui.createWidget('WikiMonsterCell', list)
			row.monsterId = index
			setCreaturePreview(row.creature, monster.look, 32)
			row.onClick = function() showMonster(index) end
			monsterRows[#monsterRows + 1] = row
		end
	end
	for _, row in ipairs(monsterRows) do
		local name = monsters[row.monsterId].name
		local kills = getKillCount(name)
		local complete = kills >= BESTIARY_MAX_KILLS
		row.track.bar:setWidth(math.floor(38 * kills / BESTIARY_MAX_KILLS))
		row.track.bar:setBackgroundColor(complete and '#45D145' or '#2FA32F')
		row:setBackgroundColor(complete and '#1F3A1F' or '#262626')
		row:setTooltip(name .. '\n' .. killText(kills))
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
			child('bestiaryScroll'):setValue(math.max(0, (math.floor((position - 1) / 5) - 2) * (row:getHeight() + 2)))
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

local RISK = {
	{text = 'Safe', color = '#45D145'},
	{text = 'Careful', color = '#F0C040'},
	{text = 'Dangerous', color = '#E06060'},
}
local PIP_ON, PIP_OFF = '#F0C040', '#4A4A4A'

local function huntBand(hunt)
	if huntMode == 'party' then return hunt.party end
	return hunt[huntVocation]
end

-- 1 safe, 2 careful, 3 dangerous: stronger neighbours count, and so does
-- being at the very start of the level range.
local function huntRisk(hunt, band)
	local risk, names = 1, {}
	local level = huntMode == 'party' and huntLevel * 1.3 or huntLevel
	for _, entry in ipairs(hunt.danger or {}) do
		names[#names + 1] = entry[1]
		risk = math.max(risk, entry[2] > level and 3 or 2)
	end
	if risk == 1 and huntLevel - band[1] < (band[2] - band[1]) * 0.15 then risk = 2 end
	return risk, names
end

local function setPips(widget, amount)
	for index = 1, 3 do
		widget['p' .. index]:setBackgroundColor(index <= amount and PIP_ON or PIP_OFF)
	end
end

local function huntPlace(hunt)
	local area, floor = hunt.area:match('^(.-), floor ([+-])%d+$')
	if not area then return hunt.area end
	return area .. (floor == '-' and ', underground' or ', upstairs')
end

local function refreshHunts()
	if not wikiWindow or not built then return end
	for _, vocation in ipairs(VOCATIONS) do child('voc_' .. vocation):setOn(huntVocation == vocation) end
	child('mode_solo'):setOn(huntMode == 'solo')
	child('mode_party'):setOn(huntMode == 'party')
	child('levelLabel'):setText('Level ' .. huntLevel)

	-- One place per creature: the one where most of them live.
	local best, order = {}, {}
	for _, hunt in ipairs(hunts) do
		local band = huntBand(hunt)
		-- Rookgaard is for those who have not left it yet.
		if band and huntLevel >= band[1] and huntLevel <= band[2] and not (hunt.rook and huntLevel >= 8) then
			local current = best[hunt.name]
			if not current then order[#order + 1] = hunt.name end
			if not current or (hunt.n or 0) > (current.n or 0) then best[hunt.name] = hunt end
		end
	end
	local ideal = ((huntLevel + 2) / 1.65) ^ 2 -- experience of the strongest creature this level takes on
	local fit, golds = {}, {}
	for _, name in ipairs(order) do
		local hunt = best[name]
		local risk, names = huntRisk(hunt, huntBand(hunt))
		local score = hunt.exp * (risk == 3 and 0.5 or (risk == 2 and 0.85 or 1))
		if (hunt.n or 0) < HUNT_MIN_CREATURES then score = score * 0.4 end
		fit[#fit + 1] = {hunt = hunt, risk = risk, danger = names, score = score}
		golds[#golds + 1] = hunt.gp or 0
	end
	table.sort(fit, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.hunt.name < b.hunt.name end)
	table.sort(golds)
	local lowGold, highGold = golds[math.ceil(#golds / 3)] or 0, golds[math.ceil(#golds * 2 / 3)] or 0

	local list = child('huntList')
	list:destroyChildren()
	local shown = math.min(#fit, huntShown)
	for position = 1, shown do
		local entry = fit[position]
		local hunt, band = entry.hunt, huntBand(entry.hunt)
		local card = g_ui.createWidget('WikiHuntCard', list)
		local target = monsterByName[hunt.name]
		if target then setCreaturePreview(card.frame.creature, monsters[target].look, 32) end
		card.title:setText(hunt.name)
		card.level:setText('Lv ' .. band[1] .. '-' .. band[2])
		card.place:setText(huntPlace(hunt))
		local ratio = hunt.exp / ideal
		setPips(card.xp, ratio >= 0.5 and 3 or (ratio >= 0.2 and 2 or 1))
		local gold = hunt.gp or 0
		setPips(card.loot, gold > highGold and 3 or (gold > lowGold and 2 or 1))
		local risk = RISK[entry.risk]
		card.riskDot:setBackgroundColor(risk.color)
		card.risk:setText(risk.text)
		card.risk:setColor(risk.color)

		local names = {}
		for _, creature in ipairs(hunt.mon) do names[#names + 1] = creature[2] .. ' ' .. creature[1] end
		local tooltip = 'Lives here: ' .. table.concat(names, ', ')
			.. string.format('\n%s xp and about %d gp per kill', formatNumber(hunt.exp), gold)
		if #entry.danger > 0 then tooltip = tooltip .. '\nBeware: ' .. table.concat(entry.danger, ', ') end
		if target then tooltip = tooltip .. '\nClick to open ' .. hunt.name .. ' in the Bestiary.' end
		card:setTooltip(tooltip)
		if target then card.onClick = function() openMonster(target) end end
		card.map.onClick = function() showOnMap(hunt.x, hunt.y, hunt.z, hunt.name .. ' hunt') end
	end
	child('huntEmpty'):setVisible(shown == 0)
	child('huntMore'):setEnabled(shown < #fit)
	huntStatus = shown == 0 and 'No hunt for this choice.'
		or string.format('Best %d of %d hunts for a level %d %s.', shown, #fit, huntLevel,
			huntMode == 'party' and 'party' or VOCATION_NAME[huntVocation])
	if activeTab == 'hunting' then updateStatus() end
end

local function resetHunts()
	huntShown = HUNT_PAGE
	refreshHunts()
	if wikiWindow and built then child('huntScroll'):setValue(0) end
end

function showMoreHunts()
	huntShown = huntShown + HUNT_PAGE
	refreshHunts()
end

function setHuntVocation(vocation)
	huntVocation = vocation
	resetHunts()
end

function setHuntMode(mode)
	huntMode = mode
	resetHunts()
end

function setHuntLevel(level)
	level = math.max(1, math.min(150, math.floor(tonumber(level) or huntLevel)))
	if level == huntLevel then return end
	huntLevel = level
	resetHunts()
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
		resetHunts()
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
	huntShown = HUNT_PAGE
	mapFlag = nil
	hide()
	updateVisibleProgress()
end

function resizeWiki()
	if not wikiWindow then return end
	local rootSize = rootWidget:getSize()
	wikiWindow:setSize({width = math.min(740, rootSize.width - 16), height = math.min(530, rootSize.height - 16)})
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

	for index, id in ipairs({'healthStat', 'summonStat', 'expStat'}) do
		child(id).icon:setImageClip({x = 0, y = (index - 1) * 12, width = 12, height = 12})
	end
	-- The small map of the Bestiary only shows places: no walking, no marks of its own.
	local map = child('spotMap')
	map.autowalk = false
	map.guideFlags = nil
	map.onMouseRelease = function() return true end
	if map.onAddAutomapFlag then
		disconnect(g_game, {onAddAutomapFlag = map.onAddAutomapFlag, onRemoveAutomapFlag = map.onRemoveAutomapFlag})
	end

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
	wikiWindow, monsterRows, itemRows, mapDots, mapFlag, built = nil, {}, {}, {}, nil, false
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
