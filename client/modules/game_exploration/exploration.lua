local OPCODE = 132
local GOLD_COIN, VIAL, CHEST = 3031, 2874, 2472
local MANA_COLOR, LIFE_COLOR = 7, 2

local window
local region
local choice

local function formatNumber(value)
  local text = tostring(math.floor(value))
  local formatted = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if formatted:sub(1, 1) == ',' then formatted = formatted:sub(2) end
  return formatted
end

local function send(data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode(data))
  end
end

local function refreshChoice()
  for _, id in ipairs({'gold', 'mana', 'life'}) do
    local option = window[id]
    option:setOn(choice == id)
    option.dot:setBackgroundColor(choice == id and '#F0C860' or '#555555')
  end
  window.claimButton:setEnabled(choice ~= nil)
end

local function hide()
  if window then window:hide() end
  region, choice = nil, nil
end

-- Item ids are set on open: at module load the client has no item data yet.
local function setIcons()
  window.header.chest:setItemId(CHEST)
  window.gold.icon:setItemId(GOLD_COIN)
  window.gold.icon:setItemCount(100)
  window.gold.icon:setShowCount(false)
  window.mana.icon:setItemId(VIAL)
  window.mana.icon:setItemSubType(MANA_COLOR)
  window.life.icon:setItemId(VIAL)
  window.life.icon:setItemSubType(LIFE_COLOR)
end

local function open(data)
  setIcons()
  region, choice = tonumber(data.region), nil
  window.header.regionName:setText('The hidden chest of ' .. tostring(data.name or '?'))

  local gold = window.gold
  gold.title:setText(formatNumber(data.gold or 0) .. ' gold coins')
  gold.title:setColor('#F0C860')
  gold.detail:setText('0.4% of your total experience (' .. formatNumber(data.experience or 0) .. ')')

  local mana = window.mana
  mana.title:setText('+0.2% max mana (+' .. tostring(data.mana or 0) .. ')')
  mana.title:setColor('#8FA9FF')
  mana.detail:setText('and +0.2 mana every 11 seconds')

  local life = window.life
  life.title:setText('+0.3% max health (+' .. tostring(data.health or 0) .. ')')
  life.title:setColor('#FF8A90')
  life.detail:setText('and +0.3 health every 10 seconds')

  local explored, total = tonumber(data.explored) or 0, tonumber(data.total) or 1
  window.exploredValue:setText(explored .. ' / ' .. total)
  window.exploredBar:setPercent(math.floor(explored * 100 / math.max(1, total)))

  refreshChoice()
  window:show()
  window:raise()
  window:focus()
end

function pick(id)
  if not region then return end
  choice = id
  refreshChoice()
end

function claim()
  if not region or not choice then return end
  send({action = 'claim', region = region, choice = choice})
end

function close()
  if region then send({action = 'close'}) end
  hide()
end

local function onOpcode(protocol, opcode, buffer)
  if not window or type(buffer) ~= 'string' then return end
  local ok, data = pcall(json.decode, buffer)
  if not ok or type(data) ~= 'table' then return end
  if data.action == 'open' then
    open(data)
  elseif data.action == 'close' then
    hide()
  end
end

function init()
  window = g_ui.displayUI('exploration')
  window:hide()
  connect(g_game, {onGameEnd = hide})
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode, true)
end

function terminate()
  disconnect(g_game, {onGameEnd = hide})
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then window:destroy() end
  window = nil
end
