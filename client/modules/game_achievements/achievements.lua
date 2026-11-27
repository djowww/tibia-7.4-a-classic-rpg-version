local OPCODE = 126
local window, refreshEvent, timeoutEvent, startupEvent, requestEvent
local current, incoming, latestSnapshot, lastRequest
local readyCount = 0
local ranks = {
  {name='Novice', numeral='I', fraction=0},
  {name='Adventurer', numeral='II', fraction=0.10},
  {name='Veteran', numeral='III', fraction=0.25},
  {name='Elite', numeral='IV', fraction=0.50},
  {name='Master', numeral='V', fraction=0.75},
  {name='Legend', numeral='VI', fraction=1}
}
local rankTrophies = {'Deer trophy', 'Wolf trophy', 'Orc trophy', 'Cyclops trophy', 'Dragon lord trophy', 'Demon trophy'}

-- The trophy hall. Every number here mirrors tools/generate-achievement-hall.py,
-- which draws the pictures: tile (0, 0) of the room sits at pixel (40, 48) of
-- the 600 x 320 picture and the pedestals stand on the columns and rows below.
local HALL_WIDTH, HALL_HEIGHT, ORIGIN_X, ORIGIN_Y = 600, 320, 40, 48
local PEDESTAL_COLUMNS, PEDESTAL_ROWS = {2, 4, 6, 10, 12, 14}, {2, 5}
local RANK_COLUMNS = {3, 5, 7, 9, 11, 13}
local IMAGES = '/images/achievements/'

local function commas(value)
  local text = tostring(math.floor(value))
  while true do
    local replaced, count = text:gsub('^(%d+)(%d%d%d)', '%1,%2')
    text = replaced
    if count == 0 then return text end
  end
end

local function short(value)
  if value >= 1000000 then return (value / 1000000) .. 'M' end
  if value >= 10000 then return (value / 1000) .. 'k' end
  return commas(value)
end

local function reach(what) return function(target) return 'Reach ' .. what .. ' ' .. target end end

-- One pedestal per track, in the order of the rows of hall_items.png. `prefix`
-- is the id the server gives the five objectives of the track.
local tracks = {
  {prefix='steps_', name='Steps walked', short='Steps', title=function(target) return 'Walk ' .. commas(target) .. ' steps' end,
    items={'Leather boots', 'Soft boots', 'Steel boots', 'Boots of haste', 'Golden boots'}},
  {prefix='level_', name='Character level', short='Level', title=reach('level'),
    items={'Gold coin', 'Platinum coin', 'Crystal coin', 'Golden helmet', 'Crown'}},
  {prefix='monsterKills_', name='Monsters defeated', short='Monsters', title=function(target) return 'Defeat ' .. commas(target) .. ' monsters' end,
    items={'Wolf trophy', 'Orc trophy', 'Cyclops trophy', 'Dragon lord trophy', 'Demon trophy'}},
  {prefix='pvpKills_', name='PvP kills', short='PvP', title=function(target) return target == 1 and 'Win your first PvP fight' or 'Reach ' .. commas(target) .. ' PvP kills' end,
    items={'Leather helmet', 'Soldier helmet', 'Warrior helmet', 'Crusader helmet', 'Demon helmet'}},
  {prefix='deaths_', name='Deaths', short='Deaths', title=function(target) return target == 1 and 'Die for the first time' or 'Die ' .. commas(target) .. ' times' end,
    items={'Bone', 'Big bone', 'Skull', 'Skull of Ratha', 'Burning skull'}},
  {prefix='skill_7_', name='Magic level', short='Magic', title=reach('magic level'),
    items={'Spell rune', 'Spellbook', 'Crystal ball', 'Orb', 'Spellbook'}},
  {prefix='skill_0_', name='Fist fighting', short='Fist', title=reach('fist fighting'),
    items={'Power ring', 'Power ring', 'Power ring', 'Power ring', 'Power ring'}},
  {prefix='skill_1_', name='Club fighting', short='Club', title=reach('club fighting'),
    items={'Club', 'Mace', 'Morning star', 'War hammer', 'Thunder hammer'}},
  {prefix='skill_2_', name='Sword fighting', short='Sword', title=reach('sword fighting'),
    items={'Sword', 'Longsword', 'Two handed sword', 'Giant sword', 'Magic sword'}},
  {prefix='skill_3_', name='Axe fighting', short='Axe', title=reach('axe fighting'),
    items={'Axe', 'Battle axe', 'Double axe', 'Knight axe', 'Great axe'}},
  {prefix='skill_4_', name='Distance fighting', short='Distance', title=reach('distance fighting'),
    items={'Spear', 'Bow', 'Crossbow', 'Burst arrow', 'Power bolt'}},
  {prefix='skill_5_', name='Shielding', short='Shielding', title=reach('shielding'),
    items={'Wooden shield', 'Steel shield', 'Dragon shield', 'Demon shield', 'Mastermind shield'}}
}

local hall = {scale=0, lights={}, glows={}, items={}, frames={}, dots={}, spots={}, trophies={}}
local selected, userSelected = nil, false

local function cancel(event) if event then removeEvent(event) end end

local function syncPlayerBarSelection()
  local playerBars = modules.game_playerbars
  if playerBars and playerBars.setActionSelected then
    playerBars.setActionSelected('achievements', window and window:isVisible())
  end
end

local function send(action)
  if not g_game.isOnline() or not g_game.getFeature(GameExtendedOpcode) then return false end
  local protocol = g_game.getProtocolGame()
  if not protocol then return false end
  protocol:sendExtendedOpcode(OPCODE, json.encode({action = action}))
  return true
end

local function updateUnread(count)
  if modules.game_playerbars and modules.game_playerbars.setAchievementsUnread then
    modules.game_playerbars.setAchievementsUnread(math.max(0, tonumber(count) or 0) + readyCount)
  end
end

local function updateClaimButton()
  if window then
    window.claimButton:setVisible(readyCount > 0)
    window.claimButton:setEnabled(readyCount > 0 and not timeoutEvent and not requestEvent
      and g_game.isOnline() and g_game.getFeature(GameExtendedOpcode))
  end
end

local function place(widget, x, y, width, height)
  widget:setMarginLeft(x)
  widget:setMarginTop(y)
  widget:setSize({width=width, height=height})
  return widget
end

local function picture(class, parent, image, x, y, width, height)
  local widget = place(g_ui.createWidget(class, parent), x, y, width, height)
  if image then widget:setImageSource(IMAGES .. image) end
  return widget
end

-- Cell of hall_items.png: one row per track, five lit items then their silhouettes.
local function itemClip(track, tier, lit)
  return {x=((lit and 0 or 5) + tier - 1) * 32, y=(track - 1) * 32, width=32, height=32}
end

function selectPedestal(index)
  if not tracks[index] then return end
  selected, userSelected = index, true
  render()
end

-- Lays the room out once for a zoom of 1 or 2; render() only repaints it.
local function buildHall(scale)
  if hall.scale == scale then return end
  local panel = window.hall
  panel:destroyChildren()
  hall = {scale=scale, lights={}, glows={}, items={}, frames={}, dots={}, spots={}, trophies={}}
  place(panel, 0, 0, HALL_WIDTH * scale, HALL_HEIGHT * scale)
  local function p(value) return value * scale end
  local position = {}
  for _, row in ipairs(PEDESTAL_ROWS) do
    for _, column in ipairs(PEDESTAL_COLUMNS) do
      position[#position + 1] = {x=ORIGIN_X + column * 32, y=ORIGIN_Y + row * 32}
    end
  end
  hall.statue = picture('HallImage', panel, 'hall_statue', p(HALL_WIDTH / 2 - 4 - 80), p(84 - 80), p(160), p(160))
  for index, tile in ipairs(position) do
    hall.lights[index] = picture('HallImage', panel, 'hall_light', p(tile.x + 8 - 64), p(tile.y + 10 - 64), p(128), p(128))
  end
  for index, column in ipairs(RANK_COLUMNS) do
    hall.trophies[index] = picture('HallSpot', panel, 'hall_ranks', p(ORIGIN_X + column * 32 - 32), p(ORIGIN_Y), p(64), p(32))
  end
  for index, tile in ipairs(position) do
    hall.glows[index] = picture('HallImage', panel, 'hall_glow', p(tile.x - 20), p(tile.y - 20), p(56), p(56))
    hall.items[index] = picture('HallImage', panel, 'hall_items', p(tile.x - 8), p(tile.y - 8), p(32), p(32))
    hall.frames[index] = picture('HallFrame', panel, nil, p(tile.x - 9), p(tile.y - 9), p(35), p(39))
    hall.frames[index]:setBorderWidth(scale)
    hall.dots[index] = {}
    for tier = 1, 5 do
      hall.dots[index][tier] = picture('HallImage', panel, nil, p(tile.x - 2 + (tier - 1) * 5), p(tile.y + 32), p(3), p(3))
    end
    local spot = picture('HallSpot', panel, nil, p(tile.x - 10), p(tile.y - 12), p(40), p(50))
    spot.onClick = function() selectPedestal(index) end
    hall.spots[index] = spot
  end

  -- At zoom 2 the two plaques lie over the lower wall; at zoom 1 they go below the room.
  local big = scale == 2
  local plaqueTop = big and p(HALL_HEIGHT) - 114 or HALL_HEIGHT + 6
  place(window.plaque, big and 14 or 0, plaqueTop, big and 496 or 297, 104)
  place(window.tiers, big and p(HALL_WIDTH) - 466 or 303, plaqueTop, big and 452 or 297, 104)
  local frame = window.plaque.bigFrame
  frame:setSize({width=big and 68 or 34, height=big and 68 or 34})
  frame.bigItem:setSize({width=big and 64 or 32, height=big and 64 or 32})
  for tier = 1, 5 do window.tiers.tierRow['tier' .. tier]:setWidth(big and 83 or 50) end
  for column, id in ipairs({'speed', 'attack', 'pvp', 'death'}) do
    window.bonuses[id].icon:setImageClip({x=(column - 1) * 32, y=0, width=32, height=32})
  end
  window:setSize({width=p(HALL_WIDTH) + 14, height=(big and p(HALL_HEIGHT) or HALL_HEIGHT + 110) + 35})
end

-- Groups the flat catalog of the server into the twelve tracks of the hall.
local function trackStates()
  local byId, states = {}, {}
  for _, entry in ipairs(current and current.entries or {}) do byId[entry.id] = entry end
  for index, track in ipairs(tracks) do
    local state = {track=track, tiers={}, done=0, known=true}
    for tier = 1, 5 do
      local entry = byId[track.prefix .. tier]
      if not entry then state.known = false; break end
      state.tiers[tier] = entry
      -- Tiers are earned in order, so the first open one is the next goal.
      if entry.completed and state.done == tier - 1 then state.done = tier end
    end
    if not state.known then state.tiers, state.done = {}, 0 end
    state.next = state.tiers[state.done + 1]
    state.ratio = state.next and state.next.progress / state.next.target or (state.known and 1 or 0)
    states[index] = state
  end
  return states
end

local function rankOf(completed, total)
  local rankIndex, thresholds = 1, {}
  for index, rank in ipairs(ranks) do
    thresholds[index] = math.ceil(total * rank.fraction)
    if total > 0 and completed >= thresholds[index] then rankIndex = index end
  end
  return rankIndex, thresholds
end

local function updateRank(completed, total)
  local rankIndex, thresholds = rankOf(completed, total)
  local rank = ranks[rankIndex]
  local goal = thresholds[math.min(#ranks, rankIndex + 1)]
  window.rankName:setText(rank.name)
  window.rankIcon:setImageClip({x=(rankIndex - 1) * 64, y=total > 0 and 0 or 32, width=64, height=32})
  window.rankBar:setText(total > 0 and completed .. ' / ' .. goal or '')
  window.rankBar:setPercent(total > 0 and math.min(100, 100 * completed / goal) or 0)
  if total == 0 then
    window.rankBar:setTooltip('')
  elseif rankIndex == #ranks then
    window.rankBar:setTooltip('Every achievement completed')
  else
    window.rankBar:setTooltip(string.format('%d more to reach %s', goal - completed, ranks[rankIndex + 1].name))
  end
  if hall.statue then hall.statue:setImageClip({x=(rankIndex - 1) * 160, y=0, width=160, height=160}) end
  for index, trophy in ipairs(hall.trophies) do
    local earned = total > 0 and index <= rankIndex
    trophy:setImageClip({x=(index - 1) * 64, y=earned and 0 or 32, width=64, height=32})
    trophy:setTooltip(string.format('%s\n%s', ranks[index].name,
      earned and 'Earned' or (total > 0 and thresholds[index] .. ' / ' .. total or 'Not earned yet')))
  end
end

local function rewardText(entry)
  -- Servers from before the trophy hall still name the retired item reward.
  return entry.reward == 'Item reward retired' and 'Rank progress' or entry.reward
end

local function renderPlaque(index, state)
  local track, plaque, tiers = state.track, window.plaque, window.tiers
  local shown = math.max(1, state.done)
  plaque.bigFrame.bigItem:setImageClip(itemClip(index, shown, state.done > 0))
  plaque.bigFrame:setTooltip(state.done > 0 and track.items[state.done] or '')
  plaque.trackName:setText(track.name)
  local goal = state.next
  if not state.known then
    plaque.bar:setText(''); plaque.reward:setText(''); plaque.bar:setPercent(0)
  elseif goal then
    -- The reward only shows when it is more than the step toward the next rank.
    local reward = rewardText(goal)
    plaque.bar:setText(commas(goal.progress) .. ' / ' .. commas(goal.target))
    plaque.reward:setText(reward ~= 'Rank progress' and reward or '')
    plaque.bar:setPercent(math.min(100, 100 * goal.progress / goal.target))
  else
    plaque.bar:setText(commas(state.tiers[5].target)); plaque.reward:setText(''); plaque.bar:setPercent(100)
  end
  plaque.bar:setBackgroundColor(state.known and not goal and '#c9a45c' or '#8E805E')
  for tier = 1, 5 do
    local box, entry = tiers.tierRow['tier' .. tier], state.tiers[tier]
    local status = tier <= state.done and 'Completed' or 'Locked'
    box.slot.item:setImageClip(itemClip(index, tier, tier <= state.done))
    box.caption:setText(entry and short(entry.target) or '-')
    box.caption:setColor(tier <= state.done and '#8fbf7a' or (tier == state.done + 1 and '#DDD8C6' or '#8f8e84'))
    if entry and tier == state.done + 1 then status = commas(entry.target - entry.progress) .. ' to go' end
    box:setTooltip(entry and string.format('%s\n%s\n%s\n%s', track.title(entry.target), track.items[tier], rewardText(entry), status)
      or track.items[tier])
  end
end

function render()
  if not window then return end
  local states = trackStates()
  local completed, total = 0, current and #current.entries or 0
  readyCount = 0
  for _, entry in ipairs(current and current.entries or {}) do
    if entry.completed then completed = completed + 1
    elseif entry.ready then readyCount = readyCount + 1 end
  end
  -- Until the player picks a pedestal, the plaque follows the closest goal.
  if not userSelected or not selected then
    selected = 1
    local best = -1
    for index, state in ipairs(states) do
      if state.next and state.ratio > best then selected, best = index, state.ratio end
    end
  end
  updateRank(completed, total)
  for index, state in ipairs(states) do
    local done = state.done
    if hall.items[index] then
      hall.lights[index]:setVisible(done > 0)
      if done > 0 then hall.lights[index]:setImageClip({x=(done - 1) * 128, y=(index - 1) * 128, width=128, height=128}) end
      hall.glows[index]:setVisible(done == 5)
      hall.items[index]:setImageClip(itemClip(index, math.max(1, done), done > 0))
      hall.frames[index]:setVisible(index == selected)
      for tier = 1, 5 do hall.dots[index][tier]:setBackgroundColor(tier <= done and '#e6b84a' or '#0c0c0c') end
      hall.spots[index]:setTooltip(state.next and string.format('%s\n%s / %s', state.track.name,
        commas(state.next.progress), commas(state.next.target)) or state.track.name)
    end
  end
  renderPlaque(selected, states[selected])
  local b = current and current.bonuses
  if b then
    window.bonuses.speed.value:setText('+' .. (tonumber(b.speed) or 0))
    window.bonuses.attack.value:setText('+' .. (tonumber(b.attack) or 0) .. '%')
    window.bonuses.pvp.value:setText('+' .. (tonumber(b.pvp) or 0) .. '%')
    window.bonuses.death.value:setText('-' .. (tonumber(b.deathReduction) or 0) .. '%')
  end
  window.bonuses:setVisible(b ~= nil)
  if current then
    window.message:setText(readyCount > 0 and 'Make room in your inventory, then use Claim rewards.' or '')
  end
  updateClaimButton()
end

local function validEntry(entry)
  if type(entry) ~= 'table' then return false end
  for _, key in ipairs({'id', 'title', 'category', 'reward'}) do
    if type(entry[key]) ~= 'string' or #entry[key] > 200 then return false end
  end
  return type(entry.completed) == 'boolean' and (entry.ready == nil or type(entry.ready) == 'boolean') and type(entry.progress) == 'number'
    and type(entry.target) == 'number' and entry.target > 0 and entry.target <= 2147483647
    and entry.progress >= 0 and entry.progress <= entry.target
    and entry.progress == math.floor(entry.progress) and entry.target == math.floor(entry.target)
end

local function acceptProgress(payload)
  if type(payload.entries) ~= 'table' or #payload.entries > 60 then return end
  for _, entry in ipairs(payload.entries) do if not validEntry(entry) then return end end
  local id, page, pages = payload.snapshotId, payload.page, payload.pages
  if type(id) ~= 'number' or id < 1 or id > 2147483647 or id ~= math.floor(id)
    or type(page) ~= 'number' or type(pages) ~= 'number' or pages < 1 or pages > 20
    or page < 1 or page > pages or page ~= math.floor(page) or pages ~= math.floor(pages) then return end
  if latestSnapshot and id < latestSnapshot then return end
  if not incoming or incoming.id ~= id then
    if latestSnapshot == id then return end
    latestSnapshot = id
    incoming = {id=id, total=pages, parts={}, received=0}
  end
  if incoming.total ~= pages or incoming.parts[page] then return end
  incoming.parts[page] = payload.entries
  incoming.received = incoming.received + 1
  if incoming.received < pages then return end

  local entries, ids = {}, {}
  for index = 1, pages do
    for _, entry in ipairs(incoming.parts[index]) do
      if ids[entry.id] or #entries >= 60 then incoming=nil; return end
      ids[entry.id] = true
      entries[#entries + 1] = entry
    end
  end
  current = {entries=entries, bonuses=payload.bonuses}
  incoming = nil
  cancel(timeoutEvent); timeoutEvent=nil
  render()
  if window:isVisible() then send('markSeen'); updateUnread(0)
  else updateUnread(tonumber(payload.unread) or 0) end
end

local function onOpcode(protocol, opcode, buffer)
  if not window or opcode ~= OPCODE or type(buffer) ~= 'string' or #buffer > 8192 then return end
  local ok, payload = pcall(json.decode, buffer)
  if not ok or type(payload) ~= 'table' then return end
  if payload.action == 'progress' then acceptProgress(payload)
  elseif payload.action == 'seen' then updateUnread(0) end
end

local function request(action)
  if not window or timeoutEvent or requestEvent then return end
  if action == 'claimRewards' and readyCount == 0 then return end
  local now = g_clock.millis()
  if lastRequest and now - lastRequest < 2100 then
    requestEvent = scheduleEvent(function() requestEvent=nil; request(action); updateClaimButton() end, 2100 - (now-lastRequest))
    updateClaimButton()
    return
  end
  if not send(action) then
    window.message:setText('Connect to the game to view your achievement progress.')
    return
  end
  lastRequest = now
  window.message:setText(action == 'claimRewards' and 'Claiming achievement rewards...' or 'Updating achievement progress...')
  timeoutEvent = scheduleEvent(function()
    timeoutEvent=nil; incoming=nil
    if window then
      window.message:setText(action == 'claimRewards' and 'Reward claim could not be confirmed. Please try Refresh.' or 'Progress could not be updated. Please try Refresh.')
      updateClaimButton()
    end
  end, 8000)
  updateClaimButton()
end

function refresh() request('getProgress') end

function claimRewards() request('claimRewards') end

function show()
  if not window then return end
  local size = g_ui.getRootWidget():getSize()
  buildHall((size.width >= 1230 and size.height >= 700) and 2 or 1)
  window:show(); window:raise(); window:focus()
  render()
  if current then send('markSeen'); updateUnread(0) end
  refresh()
  cancel(refreshEvent)
  local function poll()
    refreshEvent=nil
    if window and window:isVisible() and g_game.isOnline() then
      refresh()
      refreshEvent=scheduleEvent(poll, 10000)
    end
  end
  refreshEvent=scheduleEvent(poll, 10000)
end

function hide()
  cancel(refreshEvent); refreshEvent=nil
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

local function onGameStart()
  cancel(startupEvent)
  -- onGameStart precedes the server's extended-opcode handshake.
  startupEvent=scheduleEvent(function() startupEvent=nil; refresh() end, 1000)
end

local function onGameEnd()
  hide()
  cancel(timeoutEvent); cancel(startupEvent); cancel(requestEvent)
  timeoutEvent,startupEvent,requestEvent=nil,nil,nil
  current,incoming,latestSnapshot,lastRequest=nil,nil,nil,nil
  readyCount=0
  selected,userSelected=nil,false
  if window then
    render()
    window.message:setText('Connect to the game to view your achievement progress.')
  end
  updateUnread(0)
end

function init()
  window=g_ui.displayUI('achievements'); window:hide()
  buildHall(1)
  render()
  connect(window, {onVisibilityChange=syncPlayerBarSelection})
  syncPlayerBarSelection()
  connect(g_game,{onGameStart=onGameStart,onGameEnd=onGameEnd})
  ProtocolGame.registerExtendedOpcode(OPCODE,onOpcode,true)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  onGameEnd()
  disconnect(g_game,{onGameStart=onGameStart,onGameEnd=onGameEnd})
  if window then disconnect(window, {onVisibilityChange=syncPlayerBarSelection}) end
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then window:destroy() end
  window=nil
  hall={scale=0, lights={}, glows={}, items={}, frames={}, dots={}, spots={}, trophies={}}
end
