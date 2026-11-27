-- Focused shared rarity helper regression suite. Run with LuaJIT from repo root.
-- Native UI is unavailable offline, so userdata wrappers share native fields,
-- matching the lifetime boundary relevant to this helper.
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
assert(type(newproxy) == 'function', 'This lifetime suite requires LuaJIT newproxy userdata')

local SLOT, AURA, HALO = '/images/ui/item', '/images/ui/rarity_aura', '/images/ui/rarity_halo'
local FRAMES = {1, 1, 1, 16, 32}

local methods = {}
function methods.isDestroyed(native) return native.destroyed end
function methods.isVisible(native) return native.visible end
function methods.getItem(native) return native.item end
function methods.getWidth(native) return native.size.width end
function methods.getHeight(native) return native.size.height end
function methods.getText(native) return native.text end
function methods.getClassName(native) return native.className end
function methods.getChildById(native, id) return native.byId and native.byId[id] end
function methods.setColor(native, value)
  assert(not native.destroyed, 'setColor after native widget destruction')
  native.color = value
end
function methods.setImageSource(native, value)
  assert(not native.destroyed, 'image write after native widget destruction')
  native.image, native.imageWrites = value, native.imageWrites + 1
end
function methods.setImageClip(native, value)
  assert(not native.destroyed, 'clip write after native widget destruction')
  native.clip, native.clipWrites = value, native.clipWrites + 1
end
function methods.setImageColor(native, value) native.imageColor = value end
function methods.setPhantom(native, value) native.phantom = value end
function methods.setFocusable(native, value) native.focusable = value end
function methods.setSize(native, value) native.size = value end
function methods.resize(native, width, height) native.size = {width = width, height = height} end
function methods.setMarginLeft(native, value) native.marginLeft = value end
function methods.setMarginTop(native, value) native.marginTop = value end
function methods.setBackgroundColor(native, value) native.backgroundColor = value end
function methods.setBorderWidth(native, value) native.borderWidth, native.borderWidthTop = value, value end
function methods.setBorderColor(native, value) native.borderColor, native.borderColorTop = value, value end
function methods.setBorderWidthTop(native, value) native.borderWidthTop = value end
function methods.setBorderColorTop(native, value) native.borderColorTop = value end
function methods.setTextAlign(native, value) native.textAlign = value end
function methods.setTextOffset(native, value) native.textOffset = value end
function methods.setColoredText(native, parts)
  check(#parts % 2 == 0, 'Colored text comes in text/color pairs')
  local text = ''
  for index = 1, #parts, 2 do text = text .. parts[index] end
  native.text, native.colored = text, parts
end
function methods.setOpacity(native, value)
  check(value >= 0 and value <= 1, 'Opacity stays in the native alpha range')
  native.opacity = value
end

local function nativeWidget(className)
  return {
    fields = {}, className = className or 'UIItem', destroyed = false, visible = true,
    size = {width = 34, height = 34}, item = {}, color = '#FFFFFF',
    image = SLOT, clip = {x = 0, y = 0, width = 34, height = 34}, imageWrites = 0, clipWrites = 0,
    borderWidth = 1, borderColor = '#ff0000'
  }
end

local wrapperNatives = setmetatable({}, {__mode = 'k'})
local function wrap(native, tracker)
  tracker = tracker or {finalized = 0}
  local wrapper, finalized = newproxy(true), false
  local mt = getmetatable(wrapper)
  mt.__index = function(_, key)
    assert(not finalized, 'access to a finalized Lua native wrapper')
    if methods[key] then
      return function(_, ...)
        assert(not finalized, 'method call on a finalized Lua native wrapper')
        return methods[key](native, ...)
      end
    end
    return native.fields[key]
  end
  mt.__newindex = function(_, key, value)
    assert(not finalized, 'field write on a finalized Lua native wrapper')
    native.fields[key] = value
  end
  mt.__gc = function()
    finalized = true
    tracker.finalized = tracker.finalized + 1
  end
  wrapperNatives[wrapper] = native
  return wrapper
end

local function sandbox()
  local env = {AlignLeft = 1, AlignCenter = 2, modules = {}}
  local timers, now, created, clockReads = {}, 0, 0, 0
  local connections, pressed = {}, false
  env.g_clock = {millis = function() clockReads = clockReads + 1; return now end}
  env.scheduleEvent = function(callback, delay)
    check(type(delay) == 'number' and delay >= 100, 'Animation timer is capped below 10 ticks/second')
    local token = {}
    timers[token] = callback
    return token
  end
  env.removeEvent = function(token) timers[token] = nil end
  env.g_ui = {createWidget = function(style, parent)
    check(style == 'UIWidget' and parent == nil, 'Only the parentless ground halo creates a widget')
    created = created + 1
    return wrap(nativeWidget('UIWidget'))
  end, getRootWidget = function() return env.rootWidget end}
  env.g_game = {isOnline = function() return false end}
  env.g_mouse = {isPressed = function() return pressed end}
  env.UIWidget = {}
  env.connect = function(object, handlers) connections[object] = handlers end
  env.disconnect = function(object) connections[object] = nil end
  local tooltipNative = nativeWidget('UILabel')
  tooltipNative.backgroundColor, tooltipNative.color = '#c0c0c0', '#3f3f3f'
  tooltipNative.borderColor, tooltipNative.textAlign = 'black', env.AlignCenter
  local rootNative = nativeWidget('UIWidget')
  rootNative.byId = {toolTip = wrap(tooltipNative)}
  env.rootWidget = wrap(rootNative)
  setmetatable(env, {__index = _G})
  local chunk = assert(loadfile(arg[1] or 'client/modules/game_rarityvisuals/rarityvisuals.lua'))
  setfenv(chunk, env)
  chunk()
  local control = {tooltip = tooltipNative}
  function control.timerCount() local count = 0; for _ in pairs(timers) do count = count + 1 end; return count end
  function control.created() return created end
  function control.setTime(value) now = value end
  function control.setPressed(value) pressed = value end
  function control.tick(value)
    now = value
    local token, callback = next(timers)
    check(callback ~= nil, 'Animated tiers keep an animation timer')
    timers[token] = nil
    local readsBefore = clockReads
    callback()
    check(clockReads == readsBefore + 1, 'One clock read animates every slot in a frame')
  end
  -- corelib fills and sizes the shared label before later hover handlers run.
  function control.hover(widget)
    local text = widget.tooltip
    tooltipNative.text, tooltipNative.colored = text, nil
    tooltipNative.size = {width = 100, height = 40}
    connections[env.UIWidget].onHoverChange(widget, true)
  end
  function control.connections() return connections end
  return env, control
end

local function collect() collectgarbage('collect'); collectgarbage('collect') end
local function plain(native)
  return native.image == SLOT and native.clip.x == 0 and native.clip.y == 0
    and native.clip.width == 34 and native.clip.height == 34 and native.color == '#FFFFFF'
end
local function frameOf(native, tier)
  check(native.image == AURA, 'Rare slot uses the aura sheet as its own background')
  check(native.clip.y == (tier - 1) * 34 and native.clip.width == 34 and native.clip.height == 34, 'Aura clip stays on the row of tier ' .. tier)
  check(native.clip.x % 34 == 0, 'Aura clip is aligned to a whole frame')
  return native.clip.x / 34
end

-- Catches registry keyed by transient userdata and weak keys losing live slots.
do
  local visual, clock = sandbox()
  local native, tracker = nativeWidget(), {finalized = 0}
  local widget = wrap(native, tracker)
  local weakWrapper = setmetatable({widget}, {__mode = 'v'})
  visual.applySlot(widget, 5, false)
  widget = nil
  collect()
  check(tracker.finalized == 0 and weakWrapper[1] ~= nil, 'Live registry keeps the native wrapper strong across GC')
  local entry = native.fields.antigasRarityVisualEntry
  local freshWrapper = wrap(native)
  visual.applySlot(freshWrapper, 5, false)
  check(native.fields.antigasRarityVisualEntry == entry, 'A second wrapper reuses the same slot entry')
  check(clock.timerCount() == 1, 'Repeated apply keeps one shared timer')
  check(clock.created() == 0, 'The aura needs no child widget at all')
  visual.clearSlot(freshWrapper)
  check(plain(native), 'Fresh-wrapper clear restores the plain slot background')
  check(native.fields.antigasRarityVisualEntry == nil, 'Fresh-wrapper clear removes native registry token')
  check(clock.timerCount() == 0, 'Clearing the last animated slot stops the timer immediately')
  collect()
  check(tracker.finalized == 1 and weakWrapper[1] == nil, 'Cleared registry releases its original wrapper for GC')
end

-- Catches stale auras when common, missing, or invalid tiers replace rarity.
do
  local visual, clock = sandbox()
  local native, widget = nativeWidget()
  widget = wrap(native)
  visual.applySlot(widget, 0, false)
  check(plain(native) and native.imageWrites == 0, 'Common items leave the slot untouched')
  check(clock.timerCount() == 0, 'Common items create no animation timer')
  for _, replacement in ipairs({0, -1, 6, 2.5, 'rare'}) do
    visual.applySlot(widget, 4, false)
    check(frameOf(native, 4) >= 0, 'Legendary slot shows its aura')
    visual.applySlot(widget, replacement, false)
    check(plain(native), 'Non-rarity tier restores the plain slot: ' .. tostring(replacement))
    check(clock.timerCount() == 0, 'Non-rarity tier releases animation: ' .. tostring(replacement))
  end
  visual.applySlot(widget, 2, false)
  native.item = nil
  visual.applySlot(wrap(native), 2, false)
  check(plain(native), 'Empty slot restores the plain background')
  visual.applySlot(wrap(native), 3, false)
  check(plain(native), 'Empty slot never receives an aura')
end

-- Catches writes to destroyed natives and timer retention after destruction.
do
  local visual, clock = sandbox()
  local native = nativeWidget()
  visual.applySlot(wrap(native), 5, false)
  native.destroyed = true
  visual.clearSlot(wrap(native))
  check(clock.timerCount() == 0, 'Parent destroy callback clears the final timer')
  local other = nativeWidget()
  visual.applySlot(wrap(other), 4, false)
  other.destroyed = true
  clock.tick(200)
  check(clock.timerCount() == 0, 'Animation drops a native widget destroyed before its callback')
  collect()
end

-- Catches per-slot timers, timers for static tiers, lost borders, and reset leaks.
do
  local visual, clock = sandbox()
  local natives = {}
  for tier = 1, 3 do
    natives[tier] = nativeWidget()
    visual.applySlot(wrap(natives[tier]), tier, false)
    check(frameOf(natives[tier], tier) == 0, 'Static tier ' .. tier .. ' shows its single frame')
  end
  check(clock.timerCount() == 0, 'Static tiers need no timer')
  for tier = 4, 5 do
    natives[tier] = nativeWidget()
    visual.applySlot(wrap(natives[tier]), tier, false)
  end
  check(clock.timerCount() == 1, 'Animated tiers share one timer')
  local staticWrites = natives[1].clipWrites + natives[2].clipWrites + natives[3].clipWrites
  local seen = {[4] = {}, [5] = {}}
  natives[4].visible = false
  local hiddenWrites = natives[4].clipWrites
  for frame = 1, 8 do clock.tick(frame * 200) end
  check(natives[4].clipWrites == hiddenWrites, 'Hidden slots do not repaint')
  natives[4].visible = true
  for frame = 9, 80 do
    clock.tick(frame * 200)
    for tier = 4, 5 do
      local index = frameOf(natives[tier], tier)
      check(index >= 0 and index < FRAMES[tier], 'Frame stays inside the sheet for tier ' .. tier)
      seen[tier][index] = true
    end
  end
  for tier = 4, 5 do
    local count = 0
    for _ in pairs(seen[tier]) do count = count + 1 end
    check(count == FRAMES[tier], 'Tier ' .. tier .. ' plays every frame of its loop')
  end
  check(natives[1].clipWrites + natives[2].clipWrites + natives[3].clipWrites == staticWrites, 'Static tiers are never repainted by the timer')
  check(clock.timerCount() == 1 and clock.created() == 0, 'Animation neither duplicates timers nor allocates widgets')
  for tier, native in ipairs(natives) do
    check(native.borderWidth == 1 and native.borderColor == '#ff0000', 'Aura leaves the existing boundary intact for tier ' .. tier)
  end
  visual.applySlot(wrap(natives[5]), 5, true)
  check(frameOf(natives[5], 5) == 0, 'Locked slot rests on the first frame')
  clock.tick(81 * 200); clock.tick(82 * 200)
  check(frameOf(natives[5], 5) == 0, 'Locked slot does not animate')
  visual.clearSlot(wrap(natives[4]))
  visual.clearSlot(wrap(natives[5]))
  check(clock.timerCount() == 0, 'Timer stops when only static tiers remain')
  visual.applySlot(wrap(natives[5]), 5, false)
  visual.resetSlots()
  for tier, native in ipairs(natives) do
    check(plain(native), 'Reset restores the plain slot for tier ' .. tier)
    check(native.fields.antigasRarityVisualEntry == nil, 'Reset removes each native slot token')
  end
  check(clock.timerCount() == 0, 'Reset stops the shared timer')
  collect()
end

-- Catches a halo that blocks clicks, loses its tier color, or leaves alpha range.
do
  local visual, clock = sandbox()
  local halo = visual.createGroundHalo()
  local native = wrapperNatives[halo]
  check(native.phantom == true and native.focusable == false, 'Ground halo cannot intercept pointer or focus input')
  check(native.image == HALO and native.opacity == 0, 'Ground halo starts invisible with its own image')
  local colors = {}
  for tier = 1, 5 do
    visual.paintGroundHalo(halo, tier, 0.6)
    check(native.opacity == 0.6 and not colors[native.imageColor], 'Each tier tints the halo with its own color')
    colors[native.imageColor] = true
  end
  visual.paintGroundHalo(halo, 5, 7)
  check(native.opacity == 1, 'Halo opacity is clamped')
  native.destroyed = true
  visual.paintGroundHalo(halo, 2, 0.5)
  check(native.opacity == 1, 'Destroyed halo is never painted')
  check(clock.timerCount() == 0, 'Ground halo adds no timer of its own')
  -- Catches a halo that ignores the map zoom and drifts off its tile.
  local plain = wrapperNatives[visual.createGroundHalo()]
  check(plain.size.width == 44 and plain.size.height == 22 and plain.marginLeft == -16 and plain.marginTop == -9, 'Unscaled map centers the halo low on the tile')
  local panel = {getVisibleDimension = function() return {width = 15, height = 11} end,
    getWidth = function() return 960 end, getHeight = function() return 704 end}
  visual.modules = {game_interface = {getMapPanel = function() return panel end}}
  local zoomed = visual.createGroundHalo()
  local zoomedNative = wrapperNatives[zoomed]
  check(zoomedNative.size.width == 88 and zoomedNative.size.height == 44, 'Halo grows with a 2x map')
  check(zoomedNative.marginLeft == 0 and zoomedNative.marginTop == 14, 'Halo offset follows a 2x map')
  panel.getHeight = function() return 352 end
  visual.paintGroundHalo(zoomed, 1, 0.5)
  check(zoomedNative.size.width == 44 and zoomedNative.marginLeft == -16, 'Halo follows a resized map on the next paint')
end

-- Catches a tooltip that keeps the rare look, colors the wrong line, or styles while dragging.
do
  local visual, clock = sandbox()
  visual.init()
  local tip = clock.tooltip
  local function item(tier, text)
    local native = nativeWidget()
    native.fields.rarityTier, native.fields.rarityTooltip, native.fields.tooltip = tier, tier and true or nil, text
    return wrap(native)
  end
  clock.hover(item(3, 'Epic\n+3 attack\n+3% maximum health'))
  check(tip.backgroundColor == '#111111' and tip.textAlign == 1, 'Rare tooltip switches to the dark left-aligned box')
  check(tip.colored[3] == 'Epic' and tip.colored[1] == '' and tip.colored[5] == '\n+3 attack\n+3% maximum health', 'Tier name is the colored segment')
  check(tip.colored[4] ~= tip.colored[6] and tip.borderColorTop ~= 'black' and tip.borderWidthTop == 2, 'Tier color marks the name and the top strip')
  check(tip.text == 'Epic\n+3 attack\n+3% maximum health', 'Coloring keeps the tooltip text unchanged')
  check(tip.size.width == 108 and tip.size.height == 44, 'Rare tooltip gains room for its padding')
  clock.hover(item(2, 'You see a sword.\nRare\n+2 attack'))
  check(tip.colored[1] == 'You see a sword.\n' and tip.colored[3] == 'Rare', 'Tier name is found after a native item line')
  clock.hover(item(1, 'Uncommon'))
  check(tip.colored[3] == 'Uncommon' and tip.colored[5] == '', 'A tier without details still colors its name')
  clock.hover(item(nil, 'Close'))
  check(tip.backgroundColor == '#c0c0c0' and tip.color == '#3f3f3f' and tip.textAlign == 2 and tip.borderWidthTop == 1 and tip.borderColorTop == 'black', 'Ordinary tooltip gets the classic look back')
  check(tip.colored == nil, 'Ordinary tooltip text is not recolored')
  clock.hover(item(4, 'Rare sword of legends'))
  check(tip.backgroundColor == '#c0c0c0', 'Text without the tier line keeps the classic look')
  clock.setPressed(true)
  clock.hover(item(5, 'Mythic\n+5 attack'))
  check(tip.backgroundColor == '#c0c0c0' and tip.colored == nil, 'No restyle while a mouse button is held')
  clock.setPressed(false)
  clock.hover(item(5, 'Mythic\n+5 attack'))
  check(tip.backgroundColor == '#111111', 'Mythic tooltip is styled')
  visual.terminate()
  check(tip.backgroundColor == '#c0c0c0' and next(clock.connections()) == nil, 'Terminate restores the tooltip and disconnects')
end

-- Catches losing colored loot text or world drops, or tinting commons white.
do
  local visual = sandbox()
  local seen = {}
  for tier = 1, 5 do
    check(not seen[visual.getTextColor(tier)], 'Each rarity tier has a distinct text color')
    seen[visual.getTextColor(tier)] = true
  end
  for tier = 0, 5 do
    for _, surface in ipairs({'ground', 'corpse'}) do
      check(visual.getWorldTint(tier, 0, 0, surface) ~= '#FFFFFF', 'World ' .. surface .. ' keeps hue at cycle start, tier ' .. tier)
      check(visual.getWorldTint(tier, 2100, 0, surface) ~= '#FFFFFF', 'World ' .. surface .. ' keeps hue at cycle peak, tier ' .. tier)
    end
  end
end

print('PASS rarity visuals/native-wrapper lifecycle: ' .. checks .. ' assertions')
