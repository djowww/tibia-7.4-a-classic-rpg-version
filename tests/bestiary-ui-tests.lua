-- Offline integration fixture of the Game Wiki. Run ONLY in an isolated client copy, after loadModules().
-- Uses the existing inbound callback; never connects or writes character data.
local function report(message)
  local file = assert(io.open(BESTIARY_QA_REPORT, 'a'))
  file:write(message .. '\n')
  file:close()
end
local function run()
  report('START Game Wiki UI tests')
  assert(not g_game.isOnline(), 'Offline test only')
  g_window.setTitle('Antigas - Game Wiki UI QA (offline)')
  g_window.resize({width = 1000, height = 700})
  g_game.setClientVersion(772)
  local m = modules.game_wiki
  local root = g_ui.getRootWidget()
  local catalog = dofile('/modules/game_wiki/data/monsters.lua')
  local items = dofile('/modules/game_wiki/data/items.lua')
  local function window() return root:recursiveGetChildById('wikiWindow') end
  local function child(id) return window():recursiveGetChildById(id) end
  local function rows(id) return child(id):getChildren() end
  local function packet(payload) ProtocolGame.onExtendedOpcode(nil, 124, json.encode(payload)) end
  local first, second, third = catalog.monsters[1].name, catalog.monsters[2].name, catalog.monsters[3].name

  m.show()
  assert(window():isVisible() and window():getText() == 'Game Wiki', 'Open')
  assert(#rows('bestiaryList') == #catalog.monsters, 'Full catalog')
  packet({action = 'progress', completed = 4, data = {[first] = 347, [second] = 1000, [third] = 99}})
  assert(child('xpBonus'):getText() == 'XP +0.8%', 'Permanent Bestiary XP bonus is displayed')
  assert(rows('bestiaryList')[1].info:getText() == '347/1000', 'Kill count on the list')
  assert(rows('bestiaryList')[2].info:getText() == 'Complete', 'Completed entry on the list')
  m.setProgressFilter('progress')
  assert(#rows('bestiaryList') == 2, 'In progress excludes zero/completed')
  m.setProgressFilter('completed')
  assert(#rows('bestiaryList') == 1, 'Completed only')
  child('bestiarySearch'):setText(first:upper())
  assert(#rows('bestiaryList') == 0 and child('bestiaryEmpty'):isVisible(), 'Search combines with filter')
  m.setProgressFilter('all')
  assert(#rows('bestiaryList') >= 1, 'Case insensitive search')
  child('bestiarySearch'):setText('[')
  assert(#rows('bestiaryList') == 0, 'Search is literal, not a Lua pattern')
  child('bestiarySearch'):setText('')

  m.openMonsterByName(first)
  assert(child('monsterName'):getText() == first, 'Details of the selected creature')
  assert(child('killLine').value:getText() == '347 / 1,000', 'Kill count on the details')
  assert(child('killProgressBar'):getPercent() == 34.7, 'Proportional bar')
  packet({action = 'update', monster = first, kills = 1000, completed = 5})
  assert(child('killLine').value:getText() == '1,000 / 1,000', 'Live details update')
  assert(child('xpBonus'):getText() == 'XP +1.0%', 'Completing an entry updates the XP bonus')

  for index, monster in ipairs(catalog.monsters) do
    m.openMonster(index)
    assert(#rows('spots') == #monster.spots and #monster.spots > 0, 'Places of ' .. monster.name)
    assert(#rows('loot') == #monster.loot, 'Loot of ' .. monster.name)
    assert(child('lootEmpty'):isVisible() == (#monster.loot == 0), 'Empty loot note of ' .. monster.name)
  end
  report('PASS: ' .. #catalog.monsters .. ' creatures with places and loot')

  for index, item in ipairs(items) do
    m.openItem(index)
    assert(child('itemName'):getText() == item.name, 'Item ' .. item.name)
    assert(#rows('drops') == #item.drops and #rows('trades') == #item.npc, 'Sources of ' .. item.name)
  end
  report('PASS: ' .. #items .. ' items with drops and NPC trades')

  m.openMonsterByName('Dragon')
  local lootRow = rows('loot')[1]
  signalcall(lootRow.onClick, lootRow)
  assert(child('itempediaPanel'):isVisible(), 'Loot opens the Itempedia')
  local dropRow = rows('drops')[1]
  signalcall(dropRow.onClick, dropRow)
  assert(child('bestiaryPanel'):isVisible(), 'A creature that drops the item opens the Bestiary')

  m.setTab('hunting')
  m.setHuntVocation('K')
  m.setHuntMode('solo')
  child('huntLevel'):setValue(40)
  assert(child('levelLine').value:getText() == '40' and #rows('huntList') > 0, 'Hunts for a level 40 knight')
  child('huntLevel'):setValue(3)
  for _, card in ipairs(rows('huntList')) do
    local recommended = card.tag:getText():find('Recommended', 1, true)
    assert(not recommended or card.title:getText():find('Rookgaard', 1, true), 'Only Rookgaard is recommended below level 8')
  end
  m.setHuntMode('party')
  child('huntLevel'):setValue(70)
  assert(#rows('huntList') > 0, 'Party hunts')
  m.setTab('bosstiary')
  assert(#rows('bossList') == #catalog.bosses, 'Bosses listed')

  m.hide()
  packet({action = 'update', monster = second, kills = 1000})
  assert(not window():isVisible(), 'Incoming progress cannot reopen a closed window')
  m.toggle()
  assert(window():isVisible(), 'Toggle open')
  m.toggle()
  assert(not window():isVisible(), 'Toggle closed')
  signalcall(g_game.onGameEnd)
  assert(child('xpBonus'):getText() == 'XP +0.0%', 'Logout clears the previous character bonus')
  m.terminate()
  assert(not root:recursiveGetChildById('wikiWindow'), 'Terminate destroys window')
  m.init()
  m.show()
  packet({action = 'progress', data = {[first] = 347}})
  assert(rows('bestiaryList')[1].info:getText() == '347/1000', 'Opcode re-registers after module reload')
  m.hide()
  report('PASS: tabs, filters, search, links, hunting guide, live progress and open/close')
end
scheduleEvent(function()
  local ok, err = pcall(run)
  if not ok then report('FAIL: ' .. tostring(err)) end
  report('END')
end, 500)
