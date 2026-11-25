-- F1: staff command list for GM and GOD accounts. The server builds the list
-- from data/talkactions/talkactions.xml (opcode 134), so it never goes stale.
local OPCODE = 134

local window
local commands
local account

local function request()
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() and g_game.getFeature(GameExtendedOpcode) then
    protocol:sendExtendedOpcode(OPCODE, 'list')
  end
end

local function fill()
  local entries = window.entries
  entries:destroyChildren()
  if not commands then
    window.count:setText('Loading...')
    return
  end
  local query = window.search:getText():lower()
  local shown = 0
  for _, command in ipairs(commands) do
    local text = (command.usage .. ' ' .. command.help):lower()
    if query == '' or text:find(query, 1, true) then
      local entry = g_ui.createWidget('GmCommandEntry', entries)
      entry.usage:setText(command.usage)
      entry.level:setText(command.level)
      entry.help:setText(command.help ~= '' and command.help or 'No description.')
      entry:setTooltip(command.help)
      shown = shown + 1
    end
  end
  if shown == #commands then
    window.count:setText(shown .. ' commands')
  else
    window.count:setText(shown .. ' of ' .. #commands .. ' commands')
  end
end

function filter()
  if window and window:isVisible() then fill() end
end

function hide()
  if window then window:hide() end
end

function show()
  if not g_game.isOnline() or not g_game.isGM() then return end
  window.header.title:setText((account or 'Staff') .. ' commands')
  fill()
  window:show()
  window:raise()
  window:focus()
  window.search:focus()
  request()
end

function toggle()
  if window:isVisible() then hide() else show() end
end

local function onCommands(protocol, opcode, buffer)
  local ok, data = pcall(function() return json.decode(buffer) end)
  if not ok or type(data) ~= 'table' or data.action ~= 'list' or type(data.commands) ~= 'table' then return end
  commands = {}
  for _, command in ipairs(data.commands) do
    if type(command) == 'table' and type(command.words) == 'string' then
      table.insert(commands, {usage = tostring(command.usage or command.words), help = tostring(command.help or ''),
        level = tostring(command.level or '')})
    end
  end
  account = type(data.account) == 'string' and data.account or nil
  if window:isVisible() then
    window.header.title:setText((account or 'Staff') .. ' commands')
    fill()
  end
end

local function offline()
  commands, account = nil, nil
  hide()
end

function init()
  window = g_ui.displayUI('gmcommands')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onCommands, true)
  g_keyboard.bindKeyDown('F1', toggle)
  connect(g_game, {onGameEnd = offline})
end

function terminate()
  disconnect(g_game, {onGameEnd = offline})
  g_keyboard.unbindKeyDown('F1', toggle)
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then window:destroy() window = nil end
end
