-- Inspect bot: GM and GOD only. The right-click menu on a player calls
-- inspect() or startCheck(); the server (data/creaturescripts/scripts/custom/
-- botinspect.lua, opcode 135) checks the account again and answers with the
-- bot detector report, which is shown here and refreshed while open.
local OPCODE = 135
local REFRESH = 5000

local window
local target
local refreshEvent
local report

local function w(id)
  return window:recursiveGetChildById(id)
end

-- The server writes UTF-8; the client fonts are Latin-1.
local function latin1(text)
  return (tostring(text):gsub('([\194\195])([\128-\191])', function(a, b)
    return string.char((a:byte() - 194) * 64 + b:byte())
  end))
end

local VERDICT_COLORS = {
  ['suspeito'] = '#FF5A4A', ['atenção'] = '#F0C860', ['normal'] = '#7FCF6A', ['sem dados'] = '#B4B4B4',
}

local function send(action, name)
  local protocol = g_game.getProtocolGame()
  if not protocol or not g_game.isOnline() or not g_game.getFeature(GameExtendedOpcode) then return end
  protocol:sendExtendedOpcode(OPCODE, json.encode({action = action, name = name}))
end

function canUse(creature)
  return g_game.isOnline() and g_game.isGM() and creature and creature:isPlayer() and not creature:isLocalPlayer()
end

local function scheduleRefresh()
  removeEvent(refreshEvent)
  refreshEvent = scheduleEvent(function()
    refreshEvent = nil
    if window and window:isVisible() and target then
      send('inspect', target)
      scheduleRefresh()
    end
  end, REFRESH)
end

local function open(name)
  target = name
  report = nil
  w('title'):setText(name)
  w('percent'):setText('...')
  w('percent'):setColor('#B4B4B4')
  w('bar'):setPercent(0)
  w('verdict'):setText('Loading...')
  w('data'):setText('')
  w('checkState'):setText('')
  w('note'):setText('')
  w('reasons'):setText('')
  w('details'):setText('')
  window:show()
  window:raise()
  window:focus()
  scheduleRefresh()
end

function inspect(creature)
  if not canUse(creature) then return end
  open(creature:getName())
  send('inspect', creature:getName())
end

function startCheck(creature)
  if not canUse(creature) then return end
  open(creature:getName())
  send('check', creature:getName())
end

function check()
  if target then send('check', target) end
end

function clear()
  if target then send('clear', target) end
end

function refresh()
  if target then send('inspect', target) end
end

function hide()
  removeEvent(refreshEvent)
  refreshEvent = nil
  if window then window:hide() end
end

local function checkText(check)
  if type(check) ~= 'table' then return '' end
  local failed = tonumber(check.failed) or 0
  local text
  if check.state == 'pending' then
    text = string.format('Bot check pending: %d s left (sent by %s).', tonumber(check.left) or 0, tostring(check.by or '?'))
  elseif check.state == 'verified' then
    text = string.format('Verified as human: %d min left.', math.ceil((tonumber(check.left) or 0) / 60))
  elseif check.state == 'passed' then
    text = 'Last bot check: passed.'
  elseif check.state == 'timeout' then
    text = 'Last bot check: no answer.'
  elseif check.state == 'wrong' then
    text = 'Last bot check: 3 wrong answers.'
  elseif check.state == 'logout' then
    text = 'Last bot check: logged out before answering.'
  else
    text = 'No bot check sent yet.'
  end
  if failed > 0 then text = text .. string.format(' Failed checks: %d.', failed) end
  return text
end

local function show(data)
  report = data
  local percent = math.max(0, math.min(100, tonumber(data.percent) or 0))
  local verdict = tostring(data.verdict or '')
  local color = VERDICT_COLORS[verdict] or '#C8C8C8'
  w('title'):setText(string.format('%s (level %d)', tostring(data.name), tonumber(data.level) or 0))
  w('percent'):setText(verdict == 'sem dados' and '--' or (percent .. '%'))
  w('percent'):setColor(color)
  w('bar'):setPercent(percent)
  w('bar'):setBackgroundColor(color)
  w('verdict'):setText(latin1(string.format('Bot chance - %s (%d points)', verdict, tonumber(data.score) or 0)))
  w('verdict'):setColor(color)
  w('data'):setText(string.format('Watched for %d min, %d actions.', tonumber(data.minutes) or 0, tonumber(data.actions) or 0))
  w('checkState'):setText(checkText(data.check))
  w('note'):setText(type(data.note) == 'string' and latin1(data.note) or '')

  local reasons = {}
  if type(data.reasons) == 'table' then
    for _, reason in ipairs(data.reasons) do reasons[#reasons + 1] = '- ' .. latin1(reason) end
  end
  if #reasons == 0 then reasons[1] = 'No bot signal so far.' end
  w('reasons'):setText(table.concat(reasons, '\n'))

  local details = {}
  if type(data.details) == 'table' then
    for _, line in ipairs(data.details) do details[#details + 1] = latin1(line) end
  end
  w('details'):setText(table.concat(details, '\n'))

  local pending = type(data.check) == 'table' and data.check.state == 'pending'
  w('checkButton'):setEnabled(not pending)
end

local function onOpcode(protocol, opcode, buffer)
  if not window or type(buffer) ~= 'string' or #buffer > 16384 then return end
  local ok, data = pcall(function() return json.decode(buffer) end)
  if not ok or type(data) ~= 'table' then return end
  if data.action == 'offline' then
    if target and data.name == target then
      w('verdict'):setText(data.staff and 'Staff members are not inspected.' or 'Player is not online.')
      w('verdict'):setColor('#B4B4B4')
      w('percent'):setText('--')
      removeEvent(refreshEvent)
      refreshEvent = nil
    end
    return
  end
  if data.action ~= 'report' or type(data.name) ~= 'string' then return end
  -- a check result can arrive for a player whose window was closed
  if not window:isVisible() or (target and data.name:lower() ~= target:lower()) then
    if type(data.note) == 'string' and data.note ~= '' then
      if modules.game_textmessage then modules.game_textmessage.displayStatusMessage(latin1('[Anti-bot] ' .. data.note)) end
    end
    return
  end
  target = data.name
  show(data)
end

local function offline()
  target, report = nil, nil
  hide()
end

function init()
  window = g_ui.displayUI('botinspect')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode, true)
  connect(g_game, {onGameEnd = offline})
end

function terminate()
  disconnect(g_game, {onGameEnd = offline})
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  removeEvent(refreshEvent)
  if window then window:destroy() window = nil end
end
