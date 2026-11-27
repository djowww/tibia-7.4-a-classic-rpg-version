-- Rarity is shown as light behind the sprite: the slot swaps its own background
-- image for a pre-rendered aura frame, so nothing is ever drawn over the item.
local families = {
  [0] = { {151, 125, 88}, {189, 161, 112}, {210, 190, 149} },
  [1] = { {93, 139, 110}, {129, 173, 137}, {167, 195, 151} },
  [2] = { {99, 137, 169}, {130, 169, 193}, {169, 195, 207} },
  [3] = { {143, 111, 164}, {172, 143, 184}, {202, 174, 197} },
  [4] = { {178, 139, 78}, {207, 174, 111}, {225, 204, 156} },
  [5] = { {177, 107, 103}, {204, 142, 126}, {225, 177, 151} }
}
-- A native widget can have several Lua userdata wrappers. Weak userdata keys
-- may remain visible after their native pointer was finalized by LuaJIT.
-- Keep a strong wrapper in a plain Lua entry and share its token via the
-- widget's native fields, so callbacks with another wrapper find the same slot.
local slots = {}
local animated = 0
local animationEvent
local ANIMATION_MS = 200
local CYCLE_MS = 4200
local TWO_PI = math.pi * 2
local SLOT_IMAGE = '/images/ui/item'
local SLOT_SIZE = 34
-- rarity_aura.png: one row per tier, one 34x34 column per 200 ms frame.
-- Each frame is the slot background with the light, the thin border and the
-- bottom notches (one per tier) already painted, so the sprite stays on top.
local AURA_IMAGE = '/images/ui/rarity_aura'
local AURA_FRAMES = {1, 1, 1, 16, 32}
local HALO_IMAGE = '/images/ui/rarity_halo'
local AURA_COLORS = {'#5FAE78', '#5F8FCA', '#A074C8', '#D6A842', '#D2545A'}
local NAME_COLORS = {'#7DC18D', '#7DA7DA', '#B78FD7', '#E4BF6B', '#E27677'}
local TIER_NAMES = {'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic'}
local tooltipStyled = false

local function tierNumber(tier)
  return type(tier) == 'number' and tier == math.floor(tier)
    and tier >= 0 and tier <= 5 and tier or 0
end

local function phaseSeed(seed)
  if type(seed) == 'number' then return seed % CYCLE_MS end
  local value = tostring(seed or '')
  local hash = 0
  for i = 1, math.min(#value, 96) do
    hash = (hash * 31 + value:byte(i)) % CYCLE_MS
  end
  return hash
end

local function mix(a, b, amount)
  return {
    a[1] + (b[1] - a[1]) * amount,
    a[2] + (b[2] - a[2]) * amount,
    a[3] + (b[3] - a[3]) * amount
  }
end

local function hex(rgb)
  return string.format('#%02X%02X%02X',
    math.floor(rgb[1] + 0.5), math.floor(rgb[2] + 0.5), math.floor(rgb[3] + 0.5))
end

local function colorAt(tier, now, seed)
  local family = families[tierNumber(tier)]
  local phase = ((now or g_clock.millis()) + phaseSeed(seed)) / CYCLE_MS * TWO_PI
  local tone = (1 - math.cos(phase)) * 0.5
  if tone < 0.5 then return mix(family[1], family[2], tone * 2) end
  return mix(family[2], family[3], (tone - 0.5) * 2)
end

function getTextColor(tier)
  return hex(families[tierNumber(tier)][2])
end

function getWorldTint(tier, now, seed, surface)
  tier = tierNumber(tier)
  now = now or g_clock.millis()
  local phase = (now + phaseSeed(seed)) / CYCLE_MS * TWO_PI
  -- Neither end of the cycle turns white; the hue and intensity move together.
  local wave = (1 - math.cos(phase)) * 0.5
  local strength
  if surface == 'corpse' then
    strength = 0.13 + wave * 0.09
  else
    strength = 0.24 + tier * 0.015 + wave * 0.08
  end
  return hex(mix({255, 255, 255}, colorAt(tier, now, seed), strength))
end

local function alive(widget)
  return widget and not widget:isDestroyed()
end

local function frameClip(tier, frame)
  return {x = frame * SLOT_SIZE, y = (tier - 1) * SLOT_SIZE, width = SLOT_SIZE, height = SLOT_SIZE}
end

local function restoreBackground(widget)
  widget:setImageSource(SLOT_IMAGE)
  widget:setImageClip({x = 0, y = 0, width = SLOT_SIZE, height = SLOT_SIZE})
  widget:setColor('#FFFFFF')
end

-- The map is stretched to the window, but a tile widget is not: its size and
-- margins stay in screen pixels. Follow the zoom so the halo keeps its place.
local function groundScale()
  local interface = modules.game_interface
  local panel = interface and interface.getMapPanel and interface.getMapPanel()
  if not panel or not panel.getVisibleDimension then return 1 end
  local dimension = panel:getVisibleDimension()
  if not dimension or dimension.width < 1 or dimension.height < 1 then return 1 end
  local scale = math.min(panel:getWidth() / (dimension.width * 32), panel:getHeight() / (dimension.height * 32))
  if scale ~= scale or scale < 0.25 then return 1 end
  return math.min(scale, 4)
end

local function placeGroundHalo(widget, scale)
  if widget.antigasRarityHaloScale == scale then return end
  widget.antigasRarityHaloScale = scale
  local tile = 32 * scale
  widget:setSize({width = math.floor(44 * scale + 0.5), height = math.floor(22 * scale + 0.5)})
  -- Tile centers its widget 32 screen pixels right and below the tile origin;
  -- bring it to the middle of the tile, under the item's feet.
  widget:setMarginLeft(math.floor(tile * 0.5 - 32 + 0.5))
  widget:setMarginTop(math.floor(tile * 0.72 - 32 + 0.5))
end

-- The ground controller owns this parentless widget. Tile draws and projects it,
-- so it never needs a screen-space overlay or an extra animation event.
function createGroundHalo()
  local widget = g_ui.createWidget('UIWidget')
  widget:setPhantom(true)
  widget:setFocusable(false)
  widget:setImageSource(HALO_IMAGE)
  placeGroundHalo(widget, groundScale())
  widget:setOpacity(0)
  return widget
end

function paintGroundHalo(widget, tier, opacity)
  if not alive(widget) then return end
  placeGroundHalo(widget, groundScale())
  local color = AURA_COLORS[tierNumber(tier)] or AURA_COLORS[1]
  if widget.antigasRarityHaloColor ~= color then
    widget:setImageColor(color)
    widget.antigasRarityHaloColor = color
  end
  widget:setOpacity(math.max(0, math.min(1, opacity)))
end

local function paintSlot(widget, entry, now)
  local frames = AURA_FRAMES[entry.tier]
  local frame = 0
  if frames > 1 and not entry.locked then
    frame = math.floor((now + entry.seed) / ANIMATION_MS) % frames
  end
  if entry.frame ~= frame then
    widget:setImageClip(frameClip(entry.tier, frame))
    entry.frame = frame
  end
end

local function forget(entry)
  if not slots[entry] then return end
  slots[entry] = nil
  if AURA_FRAMES[entry.tier] > 1 then animated = animated - 1 end
  entry.widget = nil
end

local function animateSlots()
  animationEvent = nil
  local now = g_clock.millis()
  for entry in pairs(slots) do
    local widget = entry.widget
    if not alive(widget) then
      forget(entry)
    elseif AURA_FRAMES[entry.tier] > 1 and widget:isVisible() then
      paintSlot(widget, entry, now)
    end
  end
  if animated > 0 then animationEvent = scheduleEvent(animateSlots, ANIMATION_MS) end
end

local function stopIdleTimer()
  if animated <= 0 and animationEvent then
    removeEvent(animationEvent)
    animationEvent = nil
  end
end

function clearSlot(widget)
  if not widget then return end
  local entry = widget.antigasRarityVisualEntry
  if not entry then return end
  widget.antigasRarityVisualEntry = nil
  if alive(widget) then restoreBackground(widget) end
  forget(entry)
  stopIdleTimer()
end

function applySlot(widget, tier, locked)
  tier = tierNumber(tier)
  if tier == 0 or not alive(widget) or not widget:getItem() then
    clearSlot(widget)
    return
  end
  local entry = widget.antigasRarityVisualEntry
  if entry and entry.tier ~= tier then clearSlot(widget); entry = nil end
  if not entry then
    entry = {widget = widget, tier = tier, seed = phaseSeed(tostring(widget))}
    slots[entry] = true
    if AURA_FRAMES[tier] > 1 then animated = animated + 1 end
    widget.antigasRarityVisualEntry = entry
  end
  entry.locked = locked == true
  -- A style refresh may have put the plain slot image back; claim it again.
  widget:setImageSource(AURA_IMAGE)
  entry.frame = nil
  paintSlot(widget, entry, g_clock.millis())
  if animated > 0 and not animationEvent then
    animationEvent = scheduleEvent(animateSlots, ANIMATION_MS)
  end
end

function resetSlots()
  if animationEvent then removeEvent(animationEvent); animationEvent = nil end
  for entry in pairs(slots) do
    local widget = entry.widget
    if alive(widget) then
      widget.antigasRarityVisualEntry = nil
      restoreBackground(widget)
    end
    forget(entry)
  end
  animated = 0
end

-- The shared tooltip is one label owned by corelib. A rare item restyles it
-- (dark box, tier strip on top, tier name in its color) right after corelib
-- fills it; the next ordinary tooltip gets the classic look back.
local function tooltipLabel()
  return rootWidget and rootWidget:getChildById('toolTip')
end

local function restoreTooltip()
  if not tooltipStyled then return end
  tooltipStyled = false
  local label = tooltipLabel()
  if not alive(label) then return end
  label:setBackgroundColor('#c0c0c0')
  label:setColor('#3f3f3f')
  label:setBorderWidth(1)
  label:setBorderColor('black')
  label:setTextAlign(AlignCenter)
  label:setTextOffset({x = 0, y = 0})
end

function tooltipParts(text, tier)
  tier = tierNumber(tier)
  local name = TIER_NAMES[tier]
  if not name or type(text) ~= 'string' then return nil end
  local first
  if text:sub(1, #name) == name and (#text == #name or text:sub(#name + 1, #name + 1) == '\n') then
    first = 1
  else
    local found = text:find('\n' .. name .. '\n', 1, true)
    if found then
      first = found + 1
    elseif #text > #name and text:sub(-#name - 1) == '\n' .. name then
      first = #text - #name + 1
    end
  end
  if not first then return nil end
  local plain = '#D8D8D8'
  return {text:sub(1, first - 1), plain, name, NAME_COLORS[tier], text:sub(first + #name), plain}
end

local function onHoverChange(widget, hovered)
  if not hovered then return end
  local tier = widget.rarityTooltip and tierNumber(widget.rarityTier) or 0
  local parts = tier > 0 and not g_mouse.isPressed() and tooltipParts(widget.tooltip, tier)
  if not parts then
    restoreTooltip()
    return
  end
  local label = tooltipLabel()
  if not alive(label) or label:getText() ~= widget.tooltip then return end
  label:setColoredText(parts)
  label:setBackgroundColor('#111111')
  label:setColor('#D8D8D8')
  label:setBorderWidth(1)
  label:setBorderColor('black')
  label:setBorderWidthTop(2)
  label:setBorderColorTop(AURA_COLORS[tier])
  label:setTextAlign(AlignLeft)
  label:setTextOffset({x = 5, y = 1})
  label:resize(label:getWidth() + 8, label:getHeight() + 4)
  tooltipStyled = true
end

function init()
  connect(g_game, {onGameEnd = resetSlots})
  connect(UIWidget, {onHoverChange = onHoverChange})
  if g_game.isOnline() then
    -- Restore existing authoritative slot metadata after reloading this module.
    for _, widget in ipairs(g_ui.getRootWidget():recursiveGetChildren()) do
      if alive(widget) and widget:getClassName() == 'UIItem' and widget.rarityTier then
        applySlot(widget, widget.rarityTier, widget.rarityLocked)
      end
    end
  end
end

function terminate()
  disconnect(g_game, {onGameEnd = resetSlots})
  disconnect(UIWidget, {onHoverChange = onHoverChange})
  restoreTooltip()
  resetSlots()
end
