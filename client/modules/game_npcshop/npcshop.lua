local OPCODE = 130
local MAX_AMOUNT = 100

local window
local npcId, npcName
local money = 0
local freeSlots -- empty hands + container slots, sent by the server (nil on old servers)
local offers = {buy = {}, sell = {}}
local mode = 'buy'
local selected
local amount = 1
local cells = {}

local function split(text, separator)
  local fields = {}
  for field in (text .. separator):gmatch('(.-)' .. separator) do
    fields[#fields + 1] = field
  end
  return fields
end

local function formatNumber(value)
  local text = tostring(math.floor(value))
  local formatted = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if formatted:sub(1, 1) == ',' then formatted = formatted:sub(2) end
  return formatted
end

local function formatWeight(weight)
  return string.format('%.2f oz', weight / 100)
end

local SMALL_WORDS = {['of'] = true, ['the'] = true, ['a'] = true, ['an'] = true}

local function title(name)
  local first = true
  return (name:gsub('(%a)([%w\']*)', function(letter, rest)
    local word = letter .. rest
    if not first and SMALL_WORDS[word:lower()] then return word end
    first = false
    return letter:upper() .. rest
  end))
end

-- Fluid containers (vials) share one item id: the subtype picks the fluid color.
local function setOfferItem(widget, offer, count)
  widget:setItemId(offer.itemId)
  if offer.subType > 0 then
    widget:setItemSubType(offer.subType)
  elseif count and count > 1 then
    widget:setItemCount(count)
  end
end

local function sellAllSummary()
  local units, total = 0, 0
  for _, offer in ipairs(offers.sell) do
    local lots = math.floor(offer.sellable / offer.amount)
    units = units + lots * offer.amount
    total = total + lots * offer.price
  end
  return units, total
end

local function freeCapacity()
  local player = g_game.getLocalPlayer()
  if player and player.getFreeCapacity then
    -- This protocol reports capacity in hundreds of oz (same * 100 as Skills and Inventory).
    return player:getFreeCapacity() * 100
  end
  return nil
end

local function isStackable(itemId)
  local ok, thing = pcall(function() return g_things.getThingType(itemId, ThingCategoryItem) end)
  return ok and thing and thing:isStackable() or false
end

local function maxAmount(offer)
  local limit = math.min(MAX_AMOUNT, offer.max)
  if mode == 'buy' then
    if offer.price > 0 then
      limit = math.min(limit, math.floor(money / offer.price))
    end
  else
    limit = math.min(limit, math.floor(offer.have / offer.amount))
  end
  return math.max(1, limit)
end

local function canTrade(offer, count)
  if mode == 'buy' then
    return money >= offer.price * count
  end
  return offer.have >= offer.amount * count
end

local function updateDetail()
  if not window then return end
  local detail = window.detail
  local offer = selected
  window.money:setText(formatNumber(money) .. ' gp')
  local capacity = freeCapacity()
  window.capacity:setText(capacity and string.format('Cap: %.2f oz', capacity) or '')

  if not offer then
    detail:hide()
    window.note:setText('')
    return
  end
  detail:show()

  amount = math.max(1, math.min(amount, maxAmount(offer)))
  local total = offer.price * amount
  local name = title(offer.name)
  local article = offer.article ~= '' and (offer.article .. ' ') or ''

  setOfferItem(detail.icon, offer)
  detail.name:setText(name)
  detail.description:setText('You see ' .. article .. offer.name .. '. It weighs ' .. formatWeight(offer.weight) .. '.')
  detail.priceValue:setText(formatNumber(offer.price) .. ' gp')
  detail.weightValue:setText(formatWeight(offer.weight))
  detail.haveValue:setText(tostring(offer.have))
  detail.amount:setText(tostring(amount))
  detail.totalValue:setText(formatNumber(total) .. ' gp')

  local single = offer.max <= 1
  detail.minus:setEnabled(not single)
  detail.plus:setEnabled(not single)
  detail.ten:setEnabled(not single)
  detail.max:setEnabled(not single)

  local ok = canTrade(offer, amount)
  local units = amount * offer.amount
  detail.action:setText((mode == 'buy' and 'Buy ' or 'Sell ') .. units .. 'x ' .. name)
  detail.action:setEnabled(ok)

  local note = ''
  if not ok then
    note = mode == 'buy' and 'You do not have enough gold.' or 'You have none of this item.'
  elseif mode == 'buy' and capacity and offer.weight * units / 100 > capacity then
    note = 'Too heavy: it would drop on the floor.'
  elseif mode == 'buy' and freeSlots then
    local needed = isStackable(offer.itemId) and math.ceil(units / 100) or units
    if freeSlots < needed then
      if freeSlots == 0 then
        note = 'Backpack full: it drops on the floor.'
      elseif needed == units then
        note = 'Only ' .. freeSlots .. ' fit: the rest drops on the floor.'
      else
        note = 'Backpack full: it may drop on the floor.'
      end
    elseif freeSlots == needed and total > 0 then
      -- Change coins need a slot too when no coin stack can take them.
      note = 'No room left: change may drop on the floor.'
    end
  end
  window.note:setText(note)
end

local function select(offer)
  selected = offer
  amount = 1
  for _, cell in ipairs(cells) do
    cell:setOn(cell.offer == offer)
  end
  updateDetail()
end

local function refresh()
  if not window then return end
  local list = offers[mode]
  window.buyTab:setOn(mode == 'buy')
  window.sellTab:setOn(mode == 'sell')
  window.buyTab:setEnabled(#offers.buy > 0)
  window.sellTab:setEnabled(#offers.sell > 0)
  window.buyTab:setText('Buy from ' .. (npcName or 'NPC'))
  window.sellTab:setText('Sell to ' .. (npcName or 'NPC'))

  window.grid:destroyChildren()
  cells = {}
  for _, offer in ipairs(list) do
    local cell = g_ui.createWidget('NpcTradeCell', window.grid)
    cell.offer = offer
    setOfferItem(cell.item, offer, offer.amount)
    cell.name:setText(title(offer.name))
    cell.price:setText(formatNumber(offer.price) .. ' gp')
    cell:setTooltip(title(offer.name) .. '\n' .. formatNumber(offer.price) .. ' gp, ' .. formatWeight(offer.weight))
    if mode == 'sell' then
      cell.have:setText('x' .. offer.have)
      if offer.have < offer.amount then cell:setOpacity(0.45) end
    else
      cell.have:setText('')
    end
    cell.onClick = function() select(offer) end
    cells[#cells + 1] = cell
  end
  local units, total = sellAllSummary()
  window.sellAll:setVisible(mode == 'sell')
  window.note:removeAnchor(AnchorRight)
  window.note:addAnchor(AnchorRight, mode == 'sell' and 'sellAll' or 'close', AnchorLeft)
  window.sellAll:setEnabled(units > 0)
  window.sellAll:setTooltip(units > 0 and ('Sell ' .. units .. ' items for ' .. formatNumber(total) .. ' gp.\nEquipped items are kept.') or 'Nothing to sell (equipped items are kept).')

  window.emptyState:setText(#list == 0 and (mode == 'buy' and 'This NPC has nothing to sell.' or 'This NPC does not buy anything.') or '')

  -- Keep the same item selected after the server refreshes the list.
  local keep
  if selected then
    for _, offer in ipairs(list) do
      if offer.index == selected.index then keep = offer break end
    end
  end
  local previousAmount = amount
  select(keep or list[1])
  if keep then
    amount = previousAmount
    updateDetail()
  end
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, text)
  end
end

function setMode(newMode)
  if newMode == mode or #offers[newMode] == 0 then
    if window then
      window.buyTab:setOn(mode == 'buy')
      window.sellTab:setOn(mode == 'sell')
    end
    return
  end
  mode = newMode
  selected = nil
  refresh()
end

function setAmount(value)
  if not selected then return end
  amount = math.max(1, math.min(value, maxAmount(selected)))
  updateDetail()
end

function changeAmount(delta)
  setAmount(amount + delta)
end

function trade()
  if not selected or not npcId or not canTrade(selected, amount) then return end
  send(string.format('trade\t%d\t%d\t%d', npcId, selected.index, amount))
end

local sellAllBox

function sellAll()
  if not npcId or sellAllBox then return end
  local units, total = sellAllSummary()
  if units == 0 then return end
  local id = npcId
  local function close()
    if sellAllBox then sellAllBox:destroy() end
    sellAllBox = nil
  end
  local function accept()
    close()
    if npcId == id then send(string.format('sellall\t%d', id)) end
  end
  sellAllBox = displayGeneralBox('Sell all',
    'Sell ' .. units .. (units == 1 and ' item' or ' items') .. ' to ' .. (npcName or 'the NPC') .. ' for ' .. formatNumber(total) .. ' gp?\nEquipped items and rare items are kept.',
    {{text = 'Sell all', callback = accept}, {text = 'Cancel', callback = close}}, accept, close)
end

function hide(fromServer)
  if sellAllBox then sellAllBox:destroy() sellAllBox = nil end
  if window and window:isVisible() then
    window:hide()
    if not fromServer and npcId then
      send(string.format('close\t%d', npcId))
    end
  end
end

local function open(lines)
  local header = split(lines[1], '\t')
  local id = tonumber(header[2])
  if not id then return end

  local sameNpc = npcId == id and window:isVisible()
  npcId = id
  npcName = header[3] or 'NPC'
  money = tonumber(header[4]) or 0
  freeSlots = tonumber(header[5])
  offers = {buy = {}, sell = {}}

  for i = 2, #lines do
    local f = split(lines[i], '\t')
    if #f >= 11 and (f[1] == 'B' or f[1] == 'S') then
      local offer = {
        index = tonumber(f[2]) or 0,
        itemId = tonumber(f[3]) or 0,
        data = tonumber(f[4]) or -1,
        amount = math.max(1, tonumber(f[5]) or 1),
        price = tonumber(f[6]) or 0,
        weight = tonumber(f[7]) or 0,
        max = tonumber(f[8]) or 1,
        have = tonumber(f[9]) or 0,
        article = f[10],
        name = f[11],
        subType = tonumber(f[12]) or 0,
        sellable = tonumber(f[13]) or 0
      }
      local list = f[1] == 'B' and offers.buy or offers.sell
      list[#list + 1] = offer
    end
  end

  table.sort(offers.buy, function(a, b) return a.name < b.name end)
  table.sort(offers.sell, function(a, b) return a.name < b.name end)

  if not sameNpc then
    mode = #offers.buy > 0 and 'buy' or 'sell'
    selected = nil
    amount = 1
  elseif #offers[mode] == 0 then
    mode = mode == 'buy' and 'sell' or 'buy'
    selected = nil
  end

  window:setText('Trade with ' .. npcName)
  refresh()
  if not window:isVisible() then
    window:show()
    window:raise()
    window:focus()
  end
end

local function onOpcode(protocol, opcode, buffer)
  if not window or type(buffer) ~= 'string' then return end
  local lines = split(buffer, '\n')
  local header = split(lines[1] or '', '\t')
  if header[1] == 'open' then
    open(lines)
  elseif header[1] == 'close' then
    if tonumber(header[2]) == npcId then hide(true) end
  end
end

local function onGameEnd()
  if sellAllBox then sellAllBox:destroy() sellAllBox = nil end
  if window then window:hide() end
  npcId, npcName, selected = nil, nil, nil
  offers = {buy = {}, sell = {}}
  money, amount, mode = 0, 1, 'buy'
end

function init()
  window = g_ui.displayUI('npcshop')
  window:hide()
  window.moneyIcon:setItemId(3031) -- gold coin, drawn as a small pile
  window.moneyIcon:setItemCount(10)
  window.moneyIcon:setShowCount(false)
  connect(g_game, {onGameEnd = onGameEnd})
  connect(LocalPlayer, {onFreeCapacityChange = updateDetail})
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode, true)
end

function terminate()
  disconnect(g_game, {onGameEnd = onGameEnd})
  disconnect(LocalPlayer, {onFreeCapacityChange = updateDetail})
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then window:destroy() end
  window = nil
end
