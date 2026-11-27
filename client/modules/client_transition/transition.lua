-- Screen transitions: a black curtain that fades in and out between the
-- client screens, and a loading screen while the game server connects.
--   Transition.fadeThrough(fn)  fade to black, run fn, fade back in
--   Transition.reveal()         start black and fade into the new screen
--   Transition.hold(info)       fade to black and keep a loading screen
--   Transition.release()        fade the curtain (and loading screen) out
Transition = {}

local FADE_TO_BLACK = 220
local FADE_FROM_BLACK = 420
local HOLD_TIMEOUT = 20000

local overlay
local loading
local animEvent
local progressEvent
local dotsEvent
local timeoutEvent
local progress = 0
local holding = false
local onCancel

-- the black is a child widget: the opacity of a child shows at once,
-- while the overlay's own background lagged behind when it was shown
-- and darkened in the same frames
local curtain = 0
local function setCurtain(alpha)
  curtain = math.max(0, math.min(1, alpha))
  overlay:getChildById('curtain'):setOpacity(curtain)
end

local function smooth(t)
  return t * t * (3 - 2 * t)
end

local function stopLoading()
  removeEvent(progressEvent)
  removeEvent(dotsEvent)
  removeEvent(timeoutEvent)
  progressEvent, dotsEvent, timeoutEvent = nil, nil, nil
end

local function setProgress(value)
  progress = math.max(0, math.min(1, value))
  local bar = loading:getChildById('bar')
  bar:getChildById('fill'):setWidth(math.floor((bar:getWidth() - 2) * progress))
end

-- children do not inherit the parent's opacity, so the loading screen
-- follows the curtain by hand
local function setLoadingAlpha(alpha)
  if not loading:isVisible() then return end
  for _, child in ipairs(loading:recursiveGetChildren()) do
    child:setOpacity(alpha)
  end
end

local fontsReady = false
local function applyFonts()
  if fontsReady then return end
  fontsReady = true
  loading:getChildById('name'):setFont('sans-bold-16px')
  loading:getChildById('status'):setFont('verdana-11px-antialised')
  loading:getChildById('hint'):setFont('verdana-11px-antialised')
end

local function animate(target, duration, done)
  removeEvent(animEvent)
  animEvent = nil
  overlay:show()
  overlay:raise()
  local from = curtain
  local started = g_clock.millis()
  local function step()
    animEvent = nil
    local t = duration > 0 and math.min((g_clock.millis() - started) / duration, 1) or 1
    local value = from + (target - from) * smooth(t)
    setCurtain(value)
    setLoadingAlpha(value)
    if t < 1 then
      animEvent = scheduleEvent(step, 16)
      return
    end
    if target <= 0 then
      overlay:hide()
      loading:hide()
    end
    if done then done() end
  end
  step()
end

function Transition.init()
  g_ui.importStyle('transition')
  overlay = g_ui.createWidget('TransitionOverlay', rootWidget)
  overlay:setId('screenTransition')
  overlay:setOpacity(1)
  loading = overlay:getChildById('loading')
  overlay.onKeyDown = function(widget, keyCode)
    if keyCode == KeyEscape and holding and onCancel then
      -- the callback returns false when it is too late to cancel
      if onCancel() ~= false then Transition.release() end
      return true
    end
    return holding
  end
  -- opening the client: start black and fade into the login screen once
  -- the first heavy frames (loading sprites, resizing the window) are over
  setCurtain(1)
  overlay:show()
  local last = g_clock.millis()
  local calm = 0
  local waited = 0
  local function waitCalm()
    animEvent = nil
    if not overlay or holding then return end
    overlay:raise()
    local now = g_clock.millis()
    local gap = now - last
    last = now
    waited = waited + gap
    calm = gap < 80 and calm + 1 or 0
    if calm >= 4 or waited > 6000 then
      return animate(0, 800)
    end
    animEvent = scheduleEvent(waitCalm, 50)
  end
  animEvent = scheduleEvent(waitCalm, 50)
end

function Transition.terminate()
  removeEvent(animEvent)
  animEvent = nil
  stopLoading()
  if overlay then
    overlay:destroy()
    overlay = nil
  end
  loading = nil
  Transition = nil
end

function Transition.isBusy()
  return overlay ~= nil and overlay:isVisible()
end

function Transition.fadeThrough(fn, outTime)
  if not overlay then
    if fn then fn() end
    return
  end
  animate(1, FADE_TO_BLACK, function()
    if fn then
      local ok, err = pcall(fn)
      if not ok then g_logger.error('[Transition] ' .. tostring(err)) end
    end
    -- one frame in black so the new screen lays out before it shows
    scheduleEvent(function()
      if overlay and not holding then animate(0, outTime or FADE_FROM_BLACK) end
    end, 30)
  end)
end

function Transition.reveal(outTime)
  if not overlay or holding then return end
  removeEvent(animEvent)
  animEvent = nil
  setCurtain(1)
  overlay:show()
  overlay:raise()
  scheduleEvent(function()
    if overlay and not holding then animate(0, outTime or FADE_FROM_BLACK) end
  end, 30)
end

-- info: { name = 'Character', outfit = {...}, status = 'Entering the world',
--         onCancel = function() end, whenBlack = function() end }
function Transition.hold(info)
  info = info or {}
  if not overlay then
    if info.whenBlack then info.whenBlack() end
    return
  end
  stopLoading()
  applyFonts()
  holding = true
  onCancel = info.onCancel

  local hero = loading:getChildById('hero')
  if info.outfit then
    hero:setOutfit(info.outfit)
    hero:setDirection(2) -- walking towards the player
    hero:show()
  else
    hero:hide()
  end
  loading:getChildById('name'):setText(info.name or '')
  loading:getChildById('hint'):setVisible(onCancel ~= nil)
  local statusLabel = loading:getChildById('status')
  local status = info.status or 'Entering the world'
  local dots = 0
  statusLabel:setText(status)
  dotsEvent = cycleEvent(function()
    dots = (dots + 1) % 4
    statusLabel:setText(status .. string.rep('.', dots))
  end, 400)

  -- the bar creeps towards 90% until the game is really on screen
  setProgress(0)
  progressEvent = cycleEvent(function()
    setProgress(progress + (0.9 - progress) * 0.05)
  end, 40)
  timeoutEvent = scheduleEvent(function() Transition.release() end, HOLD_TIMEOUT)

  local wasVisible = loading:isVisible()
  loading:show()
  if not wasVisible then setLoadingAlpha(overlay:isVisible() and curtain or 0) end
  overlay:focus()
  animate(1, FADE_TO_BLACK, function()
    if info.whenBlack then
      local ok, err = pcall(info.whenBlack)
      if not ok then g_logger.error('[Transition] ' .. tostring(err)) end
    end
  end)
end

-- Iris: a black screen with a round hole of diameter d centred on (cx, cy),
-- made of the hole picture and four black rectangles around it.
local IRIS_PARTS = { 'irisHole', 'irisTop', 'irisBottom', 'irisLeft', 'irisRight' }

local function place(widget, x, y, w, h)
  widget:setMarginLeft(x)
  widget:setMarginTop(y)
  widget:setWidth(math.max(0, w))
  widget:setHeight(math.max(0, h))
end

function Transition.iris(cx, cy, d)
  if not overlay then return end
  local W, H = rootWidget:getWidth(), rootWidget:getHeight()
  d = math.max(0, math.floor(d))
  local l, t = math.floor(cx - d / 2), math.floor(cy - d / 2)
  if not overlay:isVisible() or not overlay.irisOn then
    removeEvent(animEvent)
    animEvent = nil
    setCurtain(0)
    loading:hide()
    overlay:show()
    overlay:raise()
    for _, id in ipairs(IRIS_PARTS) do overlay:getChildById(id):show() end
    overlay.irisOn = true
  end
  place(overlay:getChildById('irisHole'), l, t, d, d)
  place(overlay:getChildById('irisTop'), 0, 0, W, t)
  place(overlay:getChildById('irisBottom'), 0, t + d, W, H - t - d)
  place(overlay:getChildById('irisLeft'), 0, t, l, d)
  place(overlay:getChildById('irisRight'), l + d, t, W - l - d, d)
end

-- diameter of the hole that just uncovers the whole window from (cx, cy)
function Transition.irisFullSize(cx, cy)
  local W, H = rootWidget:getWidth(), rootWidget:getHeight()
  local far = 0
  for _, corner in ipairs({ {0, 0}, {W, 0}, {0, H}, {W, H} }) do
    far = math.max(far, math.sqrt((corner[1] - cx) ^ 2 + (corner[2] - cy) ^ 2))
  end
  return 2 * far / 0.8 + 8 -- the picture is clear up to 80% of its radius
end

function Transition.irisOff()
  if not overlay or not overlay.irisOn then return end
  overlay.irisOn = false
  for _, id in ipairs(IRIS_PARTS) do overlay:getChildById(id):hide() end
  if not holding and curtain <= 0 then overlay:hide() end
end

function Transition.isHolding()
  return holding
end

function Transition.release(outTime)
  if not overlay then return end
  local wasHolding = holding
  holding = false
  onCancel = nil
  if not overlay:isVisible() then
    stopLoading()
    return
  end
  if wasHolding then
    stopLoading()
    setProgress(1)
    -- let the full bar show for a moment before the curtain opens
    removeEvent(animEvent)
    animEvent = scheduleEvent(function()
      animEvent = nil
      if overlay and not holding then animate(0, outTime or 500) end
    end, 120)
    return
  end
  animate(0, outTime or FADE_FROM_BLACK)
end
