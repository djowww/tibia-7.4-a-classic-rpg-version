CharacterList = { }

-- private variables
local charactersWindow
local loadBox
local characterList
local errorBox
local waitingWindow
local autoReconnectButton
local updateWaitEvent
local resendWaitEvent
local loginEvent
local autoReconnectEvent
local lastLogout = 0
-- loading screen "Nightfall Passage" (defined below the character screen code)
local journey
local startJourney, stopJourney, canJourney

-- private functions
local function tryLogin(charInfo, tries)
  tries = tries or 1

  if tries > 50 then
    return
  end

  if g_game.isOnline() then
    if tries == 1 then
      g_game.safeLogout()
    end
    loginEvent = scheduleEvent(function() tryLogin(charInfo, tries+1) end, 100)
    return
  end

  g_game.loginWorld(G.account, G.password, charInfo.worldName, charInfo.worldHost, charInfo.worldPort, charInfo.characterName, G.authenticatorToken, G.sessionKey)
  -- g_logger.info("Login to " .. charInfo.worldHost .. ":" .. charInfo.worldPort)
  local function cancel()
    if g_game.isOnline() then return false end -- already in, the game is opening
    loadBox = nil
    g_game.cancelLogin()
    CharacterList.show()
  end
  if canJourney(charInfo) then
    -- loading screen on the character screen itself: the hero walks out of
    -- the temple while night falls, then teleports into the game
    loadBox = { destroy = function()
      if g_game.isOnline() then
        if not journey and charactersWindow then charactersWindow:hide() end
        -- the game interface tells us when the map is on screen
        scheduleEvent(function()
          if journey and not journey.ready and g_game.isOnline() then journey.ready = true end
        end, 2500)
      else
        stopJourney()
      end
    end }
    startJourney(charInfo, cancel)
  elseif Transition then
    -- loading screen instead of the small "Please wait" box: the character
    -- screen fades to black and the hero walks while the server connects
    local selected = characterList and characterList:getFocusedChild()
    local details = selected and selected.characterName == charInfo.characterName and selected.details
    loadBox = { destroy = function()
      if g_game.isOnline() then
        -- the game interface opens the curtain when the map is ready
        if charactersWindow then charactersWindow:hide() end
        scheduleEvent(function()
          if Transition and Transition.isHolding() and g_game.isOnline() then Transition.release() end
        end, 2500)
      elseif Transition then
        Transition.release()
      end
    end }
    Transition.hold({ name = charInfo.characterName, outfit = details and details.outfit,
                      status = tr('Entering the world'), onCancel = cancel,
                      whenBlack = function() if loadBox or g_game.isOnline() then CharacterList.hide() end end })
  else
    CharacterList.hide()
    loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to game server...'))
    connect(loadBox, { onCancel = cancel })
  end

  -- save last used character
  g_settings.set('last-used-character', charInfo.characterName)
  g_settings.set('last-used-world', charInfo.worldName)
end

local function updateWait(timeStart, timeEnd)
  if waitingWindow then
    local time = g_clock.seconds()
    if time <= timeEnd then
      local percent = ((time - timeStart) / (timeEnd - timeStart)) * 100
      local timeStr = string.format("%.0f", timeEnd - time)

      local progressBar = waitingWindow:getChildById('progressBar')
      progressBar:setPercent(percent)

      local label = waitingWindow:getChildById('timeLabel')
      label:setText(tr('Trying to reconnect in %s seconds.', timeStr))

      updateWaitEvent = scheduleEvent(function() updateWait(timeStart, timeEnd) end, 1000 * progressBar:getPercentPixels() / 100 * (timeEnd - timeStart))
      return true
    end
  end

  if updateWaitEvent then
    updateWaitEvent:cancel()
    updateWaitEvent = nil
  end
end

local function resendWait()
  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil

    if updateWaitEvent then
      updateWaitEvent:cancel()
      updateWaitEvent = nil
    end

    if charactersWindow then
      local selected = characterList:getFocusedChild()
      if selected then
        local charInfo = { worldHost = selected.worldHost,
                           worldPort = selected.worldPort,
                           worldName = selected.worldName,
                           characterName = selected.characterName }
        tryLogin(charInfo)
      end
    end
  end
end

local function onLoginWait(message, time)
  CharacterList.destroyLoadBox()

  waitingWindow = g_ui.displayUI('waitinglist')

  local label = waitingWindow:getChildById('infoLabel')
  label:setText(message)

  updateWaitEvent = scheduleEvent(function() updateWait(g_clock.seconds(), g_clock.seconds() + time) end, 0)
  resendWaitEvent = scheduleEvent(resendWait, time * 1000)
end

function onGameLoginError(message)
  CharacterList.destroyLoadBox()
  errorBox = displayErrorBox(tr("Login Error"), message)
  errorBox.onOk = function()
    errorBox = nil
    CharacterList.showAgain()
  end
  scheduleAutoReconnect()
end

function onGameLoginToken(unknown)
  CharacterList.destroyLoadBox()
  -- TODO: make it possible to enter a new token here / prompt token
  errorBox = displayErrorBox(tr("Two-Factor Authentification"), 'A new authentification token is required.\nPlease login again.')
  errorBox.onOk = function()
    errorBox = nil
    EnterGame.show()
  end
end

function onGameConnectionError(message, code)
  CharacterList.destroyLoadBox()
  if (not g_game.isOnline() or code ~= 2) and not errorBox then -- code 2 is normal disconnect, end of file
    local text = translateNetworkError(code, g_game.getProtocolGame() and g_game.getProtocolGame():isConnecting(), message)
    errorBox = displayErrorBox(tr("Connection Error"), text)
    errorBox.onOk = function()
      errorBox = nil
      CharacterList.showAgain()
    end
  end
  scheduleAutoReconnect()
end

function onGameUpdateNeeded(signature)
  CharacterList.destroyLoadBox()
  errorBox = displayErrorBox(tr("Update needed"), tr('Enter with your account again to update your client.'))
  errorBox.onOk = function()
    errorBox = nil
    CharacterList.showAgain()
  end  
end

function onGameEnd()
  stopJourney()
  scheduleAutoReconnect()
  if Transition and characterList and characterList:hasChildren() and not errorBox then
    Transition.reveal(500)
  end
  CharacterList.showAgain()
end

function onLogout()
  lastLogout = g_clock.millis()
end

function scheduleAutoReconnect()
  if lastLogout + 2000 > g_clock.millis() then
    return
  end
  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)    
  end
  autoReconnectEvent = scheduleEvent(executeAutoReconnect, 5000)
end

function executeAutoReconnect()  
  if not autoReconnectButton or not autoReconnectButton:isOn() or g_game.isOnline() then
    return
  end
  if errorBox then
    errorBox:destroy()
    errorBox = nil
  end
  CharacterList.doLogin()
end

-- public functions
function CharacterList.init()
  if USE_NEW_ENERGAME then return end
  connect(g_game, { onLoginError = onGameLoginError })
  connect(g_game, { onLoginToken = onGameLoginToken })
  connect(g_game, { onUpdateNeeded = onGameUpdateNeeded })
  connect(g_game, { onConnectionError = onGameConnectionError })
  connect(g_game, { onGameStart = CharacterList.destroyLoadBox })
  connect(g_game, { onLoginWait = onLoginWait })
  connect(g_game, { onGameEnd = onGameEnd })
  connect(g_game, { onLogout = onLogout })

  if G.characters then
    CharacterList.create(G.characters, G.characterAccount)
  end
end

function CharacterList.terminate()
 if USE_NEW_ENERGAME then return end
  disconnect(g_game, { onLoginError = onGameLoginError })
  disconnect(g_game, { onLoginToken = onGameLoginToken })
  disconnect(g_game, { onUpdateNeeded = onGameUpdateNeeded })
  disconnect(g_game, { onConnectionError = onGameConnectionError })
  disconnect(g_game, { onGameStart = CharacterList.destroyLoadBox })
  disconnect(g_game, { onLoginWait = onLoginWait })
  disconnect(g_game, { onGameEnd = onGameEnd })
  disconnect(g_game, { onLogout = onLogout })

  if charactersWindow then
    characterList = nil
    charactersWindow:destroy()
    charactersWindow = nil
  end

  if loadBox then
    g_game.cancelLogin()
    loadBox:destroy()
    loadBox = nil
  end

  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil
  end

  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  if resendWaitEvent then
    removeEvent(resendWaitEvent)
    resendWaitEvent = nil
  end

  if loginEvent then
    removeEvent(loginEvent)
    loginEvent = nil
  end

  CharacterList = nil
end

-- Character screen: the selected character stands in the temple of its home
-- town. Scenes are pictures built from the server map (tools/generate-charselect-scenes.py),
-- one per town, with the temple tile at SCENE_TILE of a 40x22 tile picture.
local SCENE_ZOOM = 3
local SCENE_TILE_X, SCENE_TILE_Y = 20, 11
local LIST_RIGHT = 0 -- the list is hidden; the arrow at the bottom right switches characters
local DEFAULT_SCENE = '/images/charselect/thais'
local heroDirection = 2

local function sceneFor(town)
  local slug = tostring(town or ''):lower():gsub('[^a-z]', '')
  if slug ~= '' and g_resources.fileExists('/images/charselect/' .. slug .. '.png') then
    return '/images/charselect/' .. slug
  end
  return DEFAULT_SCENE
end

local function characterInfoText(details, withTown)
  if not details then return '' end
  local vocation = details.vocation or ''
  if vocation == '' or vocation:lower() == 'none' then vocation = 'No vocation' end
  local text = 'Level ' .. details.level .. ' ' .. vocation
  if withTown and details.town and details.town ~= '' then
    text = text .. ', ' .. details.town
  end
  return text
end

local function clamp(x, a, b)
  return math.max(a or 0, math.min(b or 1, x))
end

local function ease(x)
  x = clamp(x)
  return x * x * (3 - 2 * x)
end

-- Places the scenery, the hero and the plate. While the game loads the hero
-- walks (journey.hx/hy in tiles from the temple) and the camera follows him
-- without showing the edge of the scenery.
local function relayout()
  if not charactersWindow then return end
  local tile = 32 * SCENE_ZOOM
  local W, H = charactersWindow:getWidth(), charactersWindow:getHeight()
  local px = math.floor(LIST_RIGHT + (W - LIST_RIGHT) / 2)
  local py = math.floor(H * 0.46)
  local hx, hy = 0, 0
  if journey then hx, hy = journey.hx, journey.hy end
  local sx = px - (SCENE_TILE_X + 0.5 + hx) * tile
  local sy = py - (SCENE_TILE_Y + 0.5 + hy) * tile
  if journey then
    if 40 * tile >= W then sx = clamp(sx, W - 40 * tile, 0) end
    if 22 * tile >= H then sy = clamp(sy, H - 22 * tile, 0) end
  end
  sx, sy = math.floor(sx), math.floor(sy)
  local scene = charactersWindow:getChildById('scene')
  scene:setMarginLeft(sx)
  scene:setMarginTop(sy)
  local cx = math.floor(sx + (SCENE_TILE_X + 0.5 + hx) * tile)
  local cy = math.floor(sy + (SCENE_TILE_Y + 0.5 + hy) * tile)
  local heroTile = charactersWindow:getChildById('heroTile')
  heroTile:setMarginLeft(cx - tile / 2)
  heroTile:setMarginTop(cy - tile / 2)

  local plate = charactersWindow:getChildById('plate')
  local plateTop = py + tile / 2 + 96
  local drop = 0
  if journey then
    drop = math.max(0, math.min(146, H - 40 - plateTop - plate:getHeight()) * journey.plateK)
  end
  plate:setMarginTop(math.floor(plateTop + drop))

  -- night (twice the window) and torch glow stay centred on the hero
  local night = charactersWindow:getChildById('night')
  night:setWidth(2 * W)
  night:setHeight(2 * H)
  night:setMarginLeft(cx - W)
  night:setMarginTop(cy - H)
  local glow = charactersWindow:getChildById('torchGlow')
  glow:setWidth(W)
  glow:setHeight(H)
  glow:setMarginLeft(cx - math.floor(W / 2))
  glow:setMarginTop(cy - math.floor(H / 2))
  if journey then journey.cx, journey.cy = cx, cy end
end

local function updateHero()
  if not charactersWindow or not characterList then return end
  local selected = characterList:getFocusedChild()
  local hero = charactersWindow:getChildById('hero')
  local details = selected and selected.details
  local hasHero = details ~= nil

  hero:setVisible(hasHero)
  charactersWindow:getChildById('heroName'):setVisible(hasHero)
  charactersWindow:getChildById('heroHealth'):setVisible(hasHero)
  charactersWindow:getChildById('rotateLeft'):setVisible(hasHero)
  charactersWindow:getChildById('rotateRight'):setVisible(hasHero)
  charactersWindow:getChildById('scene'):setImageSource(sceneFor(details and details.town))

  local plate = charactersWindow:getChildById('plate')
  plate:setVisible(selected ~= nil)
  if not selected then return end

  plate:getChildById('plateName'):setText(selected.characterName)
  plate:getChildById('plateInfo'):setText(hasHero and characterInfoText(details, true) or selected.worldName)
  if hasHero then
    charactersWindow:getChildById('heroName'):setText(selected.characterName)
    hero:setOutfit(details.outfit)
    hero:setDirection(heroDirection)
  end
end

local function updateSwitch()
  if not charactersWindow or not characterList then return end
  local count = characterList:getChildCount()
  local selected = characterList:getFocusedChild()
  local index = selected and characterList:getChildIndex(selected) or 0
  charactersWindow:getChildById('switchCharacter'):setVisible(count > 1)
  local label = charactersWindow:getChildById('switchCount')
  label:setVisible(count > 1)
  label:setText(index .. '/' .. count)
end

-- Loading screen "Nightfall Passage": after Enter Game the character screen
-- does not cut away. Its buttons fade, the plate slides down and grows a
-- progress bar, the hero walks out of the temple while night falls around a
-- torch glow, and when the game is ready he teleports: an iris closes on him
-- and opens on the player in the game.
-- WALK_PATHS comes from tools/generate-loading-images.py --paths (map walkable
-- tiles; run it again if the map around a temple changes).
local WALK_PATHS = {
  abdendriel = 'SSSSSEE',
  ankrahmun = 'EESSSEE',
  carlin = 'ESSSSS',
  darashia = 'NNEEEEN',
  edron = 'EESSSSS',
  isleofsolitude = 'NNNWWWW',
  kazordoon = 'EESSSSE',
  porthope = 'ESSSSES',
  rookgaard = 'EEESESS',
  thais = 'EEESEES',
  venore = 'EEESSSS',
}
local STEP_DIRS = { N = {0, -1, 0}, E = {1, 0, 1}, S = {0, 1, 2}, W = {-1, 0, 3} } -- x, y, direction
local STEP_MS = 520        -- one tile of walk
local MIN_LOADING = 1500   -- the walk and the dusk need a moment even on a fast login
local FX_FRAME = 70        -- teleport effect frame
local CHROME = { 'rotateLeft', 'rotateRight', 'buttonOk', 'autoReconnect', 'buttonCancel',
                 'switchCharacter', 'switchCount' }
local LOAD_PARTS = { 'loadTrack', 'loadFill', 'loadShine', 'loadSpark', 'loadStatus', 'loadPercent' }

local function townName(details)
  local town = details and details.town or ''
  return town ~= '' and town or 'Thais'
end

canJourney = function(charInfo)
  if not charactersWindow or not charactersWindow:isVisible() or not characterList then return false end
  local selected = characterList:getFocusedChild()
  return selected ~= nil and selected.details ~= nil and selected.characterName == charInfo.characterName
end

local function setOpacities(ids, value)
  for _, id in ipairs(ids) do
    local widget = charactersWindow:recursiveGetChildById(id)
    if widget then widget:setOpacity(value) end
  end
end

local function journeyArrival(e)
  local w = charactersWindow
  local fx = w:getChildById('teleportFx')
  local frame = math.floor(e / FX_FRAME)
  fx:setVisible(frame < 8)
  if frame < 8 then fx:setImageClip({ x = frame * 32, y = 0, width = 32, height = 32 }) end
  if e >= 3 * FX_FRAME then
    w:getChildById('hero'):hide()
    w:getChildById('heroName'):hide()
    w:getChildById('heroHealth'):hide()
  end
  if not Transition then
    if e >= 300 then journey.done = true end
    return
  end
  local CLOSE0, CLOSE1, OPEN0, OPEN1 = 90, 390, 460, 900
  if e >= CLOSE0 and e < CLOSE1 then
    local q = clamp((e - CLOSE0) / (CLOSE1 - CLOSE0))
    local full = Transition.irisFullSize(journey.cx, journey.cy)
    Transition.iris(journey.cx, journey.cy, full * (1 - q * q))
  elseif e >= CLOSE1 then
    if not journey.inGame then
      -- black: the game is already drawn underneath
      journey.inGame = true
      Transition.iris(journey.cx, journey.cy, 0)
      w:hide()
      local map = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
      local rect = map and map:getRect()
      if rect and rect.width > 0 then
        journey.gx, journey.gy = rect.x + rect.width / 2, rect.y + rect.height / 2
      else
        journey.gx, journey.gy = rootWidget:getWidth() / 2, rootWidget:getHeight() / 2
      end
    end
    local q = clamp((e - OPEN0) / (OPEN1 - OPEN0))
    Transition.iris(journey.gx, journey.gy, Transition.irisFullSize(journey.gx, journey.gy) * (1 - (1 - q) * (1 - q)))
    if e >= OPEN1 then journey.done = true end
  end
end

local function journeyTick()
  if not journey or not charactersWindow then return end
  local now = g_clock.millis()
  local u = now - journey.start
  local w = charactersWindow

  -- the buttons of the character screen fade away
  local chrome = 1 - clamp(u / 220)
  setOpacities(CHROME, chrome * 1)

  -- walk: stops where the path ends or when the teleport starts
  local walked = journey.arrive and (journey.arrive - journey.start) or u
  local path = journey.path
  local steps = math.floor(walked / STEP_MS)
  local part = (walked % STEP_MS) / STEP_MS
  local hx, hy, dir, moving = 0, 0, journey.dir, false
  for i = 1, math.min(steps, #path) do
    local d = STEP_DIRS[path:sub(i, i)]
    hx, hy, dir = hx + d[1], hy + d[2], d[3]
  end
  if steps < #path then
    local d = STEP_DIRS[path:sub(steps + 1, steps + 1)]
    dir = d[3]
    if not journey.arrive then
      hx, hy, moving = hx + d[1] * part, hy + d[2] * part, true
    end
  end
  journey.hx, journey.hy = hx, hy
  local hero = w:getChildById('hero')
  if journey.lastDir ~= dir then hero:setDirection(dir) journey.lastDir = dir end
  if journey.moving ~= moving then hero:setAnimate(moving) journey.moving = moving end

  -- the plate slides down and grows the progress bar
  journey.plateK = ease(u / 460)
  w:getChildById('plate'):setHeight(math.floor(56 + 40 * journey.plateK))
  local shown = clamp((u - 220) / 260)
  setOpacities(LOAD_PARTS, shown)
  w:getChildById('loadEsc'):setOpacity(journey.arrive and 0 or shown * 0.9)

  local progress = journey.ready and 1 or 0.94 * (1 - math.exp(-u / 900))
  local track = w:recursiveGetChildById('loadTrack')
  local fill = math.floor((track:getWidth() - 2) * progress)
  w:recursiveGetChildById('loadFill'):setWidth(fill)
  local spark = w:recursiveGetChildById('loadSpark')
  spark:setMarginLeft(math.max(0, fill - 1))
  spark:setOpacity(progress > 0 and progress < 1 and shown * (0.55 + 0.45 * math.sin(now / 90)) or 0)
  w:recursiveGetChildById('loadPercent'):setText(math.floor(progress * 100 + 0.5) .. '%')
  local status
  if progress >= 1 then status = tr('Entering %s', journey.town)
  elseif progress < 0.38 then status = tr('Connecting to Antigas 7.4')
  elseif progress < 0.8 then status = tr('Receiving the world map')
  else status = tr('Stepping into %s', journey.town) end
  w:recursiveGetChildById('loadStatus'):setText(status)

  -- dusk, then night closing in around the torch glow
  local nightK = ease(u / 1300)
  w:getChildById('dusk'):setOpacity(math.sin(math.pi * clamp(u / 1000)) * 0.13)
  w:getChildById('night'):setOpacity(nightK)
  w:getChildById('torchGlow'):setOpacity(nightK * (0.8 + 0.2 * math.sin(math.floor(now / 110) * 1.9)))

  relayout()

  if not journey.arrive and journey.ready and u >= MIN_LOADING then
    journey.arrive = now
  end
  if journey.arrive then
    journeyArrival(now - journey.arrive)
    if journey.done then
      stopJourney()
    end
  end
end

-- a broken frame must not leave the player stuck on the loading screen
local function safeJourneyTick()
  local ok, err = pcall(journeyTick)
  if not ok then
    g_logger.error('[CharacterList] loading screen: ' .. tostring(err))
    stopJourney()
    if g_game.isOnline() and charactersWindow then charactersWindow:hide() end
  end
end

startJourney = function(charInfo, cancel)
  stopJourney()
  local selected = characterList:getFocusedChild()
  local details = selected.details
  local slug = tostring(details.town or ''):lower():gsub('[^a-z]', '')
  journey = {
    start = g_clock.millis(), hx = 0, hy = 0, plateK = 0,
    path = WALK_PATHS[slug] or '', town = townName(details),
    dir = heroDirection, cancel = cancel,
  }
  charactersWindow:getChildById('teleportFx'):hide()
  charactersWindow:focus()
  journey.event = cycleEvent(safeJourneyTick, 16)
  safeJourneyTick()
end

-- Back to the plain character screen (login error, cancel, end of the teleport).
stopJourney = function()
  if not journey then return end
  removeEvent(journey.event)
  journey = nil
  if Transition then Transition.irisOff() end
  if not charactersWindow then return end
  setOpacities(CHROME, 1)
  charactersWindow:getChildById('switchCharacter'):setOpacity(0.75)
  setOpacities(LOAD_PARTS, 0)
  charactersWindow:getChildById('loadEsc'):setOpacity(0)
  charactersWindow:getChildById('plate'):setHeight(56)
  charactersWindow:getChildById('dusk'):setOpacity(0)
  charactersWindow:getChildById('night'):setOpacity(0)
  charactersWindow:getChildById('torchGlow'):setOpacity(0)
  charactersWindow:getChildById('teleportFx'):hide()
  charactersWindow:getChildById('hero'):setAnimate(false)
  updateHero()
  relayout()
end

-- game_interface calls this when the game is on screen
function CharacterList.onGameShown()
  if journey then journey.ready = true end
end

function CharacterList.isLoading()
  return journey ~= nil
end

function CharacterList.nextCharacter()
  if journey then return end
  if not characterList or characterList:getChildCount() < 2 then return end
  local selected = characterList:getFocusedChild()
  local index = selected and characterList:getChildIndex(selected) or 0
  local nextIndex = index % characterList:getChildCount() + 1
  characterList:focusChild(characterList:getChildByIndex(nextIndex), KeyboardFocusReason)
end

function CharacterList.rotateHero(step)
  if journey then return end
  heroDirection = (heroDirection + step) % 4
  if charactersWindow then
    charactersWindow:getChildById('hero'):setDirection(heroDirection)
  end
end

function CharacterList.create(characters, account, otui)
  otui = 'characterlist' -- UI resources are selected locally, never by the server.
  if charactersWindow then
    charactersWindow:destroy()
  end

  charactersWindow = g_ui.displayUI(otui)
  characterList = charactersWindow:recursiveGetChildById('characters')
  autoReconnectButton = charactersWindow:recursiveGetChildById('autoReconnect')
  charactersWindow.onGeometryChange = relayout
  heroDirection = 2

  -- characters
  G.characters = characters
  G.characterAccount = account

  characterList:destroyChildren()
  local accountStatusLabel = charactersWindow:recursiveGetChildById('accountStatusLabel')
  local focusLabel
  for i,characterInfo in ipairs(characters) do
    local widget = g_ui.createWidget('CharSelectRow', characterList)
    widget:getChildById('name'):setText(characterInfo.name)

    -- these are used by login
    widget.characterName = characterInfo.name
    widget.worldName = characterInfo.worldName
    widget.worldHost = characterInfo.worldIp
    widget.worldPort = characterInfo.worldPort

    -- level, vocation, outfit and town: only servers that support the
    -- detailed list send them; without them the row shows the world name.
    local details = characterInfo.details
    widget.details = details
    if details then
      widget:getChildById('info'):setText(characterInfoText(details, false))
      widget:getChildById('creature'):setOutfit(details.outfit)
    else
      widget:getChildById('info'):setText(characterInfo.worldName)
      widget:getChildById('creature'):hide()
    end

    connect(widget, { onDoubleClick = function () CharacterList.doLogin() return true end } )

    if i == 1 or (g_settings.get('last-used-character') == widget.characterName and g_settings.get('last-used-world') == widget.worldName) then
      focusLabel = widget
    end
  end

  if focusLabel then
    characterList:focusChild(focusLabel, KeyboardFocusReason)
    addEvent(function() if characterList then characterList:ensureChildVisible(focusLabel) end end)
  end

  characterList.onChildFocusChange = function(self, focusedChild)
    removeEvent(autoReconnectEvent)
    autoReconnectEvent = nil
    if focusedChild then
      characterList:ensureChildVisible(focusedChild)
    end
    heroDirection = 2
    updateHero()
    updateSwitch()
  end

  relayout()
  updateHero()
  updateSwitch()

  -- the scrollbar only shows when the rows do not fit
  local scrollBar = charactersWindow:recursiveGetChildById('characterListScrollBar')
  scrollBar:hide()
  addEvent(function()
    if characterList and scrollBar then
      scrollBar:setVisible(characterList:getChildCount() * 46 > characterList:getHeight())
    end
  end)

  -- account
  local status = ''
  if account.status == AccountStatus.Frozen then
    status = tr(' (Frozen)')
  elseif account.status == AccountStatus.Suspended then
    status = tr(' (Suspended)')
  end

  if account.subStatus == SubscriptionStatus.Free then
    accountStatusLabel:setText(('%s%s'):format(tr('Free Account'), status))
  elseif account.subStatus == SubscriptionStatus.Premium then
    if account.premDays == 0 or account.premDays == 65535 then
      accountStatusLabel:setText(('%s%s'):format(tr('Free Premium Account'), status))
    else
      accountStatusLabel:setText(('%s%s'):format(tr('Premium Account (%s) days left', account.premDays), status))
    end
  end

  if account.premDays > 0 and account.premDays <= 7 then
    accountStatusLabel:setOn(true)
  else
    accountStatusLabel:setOn(false)
  end

  autoReconnectButton.onClick = function(widget)
    local autoReconnect = not g_settings.getBoolean('autoReconnect', true)
    autoReconnectButton:setOn(autoReconnect)
    g_settings.set('autoReconnect', autoReconnect)
  end
end

function CharacterList.destroy()
  CharacterList.hide(true)

  if charactersWindow then
    characterList = nil
    charactersWindow:destroy()
    charactersWindow = nil
  end
end

function CharacterList.show()
  if loadBox or errorBox or not charactersWindow then return end
  charactersWindow:show()
  charactersWindow:raise()
  charactersWindow:focus()
  
  local autoReconnect = g_settings.getBoolean('autoReconnect', true)
  autoReconnectButton:setOn(autoReconnect)
end

function CharacterList.hide(showLogin)
  removeEvent(autoReconnectEvent)
  autoReconnectEvent = nil

  showLogin = showLogin or false
  charactersWindow:hide()

  if showLogin and EnterGame and not g_game.isOnline() then
    EnterGame.show()
  end
end

-- Logout button and Escape: fade back to the login window.
function CharacterList.logout()
  if journey then
    -- Esc while loading cancels the login, unless the game is already in
    if not g_game.isOnline() and not journey.arrive and journey.cancel then
      local cancel = journey.cancel
      stopJourney()
      cancel()
    end
    return
  end
  if Transition then
    Transition.fadeThrough(function() CharacterList.hide(true) end)
  else
    CharacterList.hide(true)
  end
end

function CharacterList.showAgain()
  if characterList and characterList:hasChildren() then
    CharacterList.show()
  end
end

function CharacterList.isVisible()
  if charactersWindow and charactersWindow:isVisible() then
    return true
  end
  return false
end

function CharacterList.doLogin()
  if journey then return end
  removeEvent(autoReconnectEvent)
  autoReconnectEvent = nil

  local selected = characterList:getFocusedChild()
  if selected then
    local charInfo = { worldHost = selected.worldHost,
                       worldPort = selected.worldPort,
                       worldName = selected.worldName,
                       characterName = selected.characterName }
    if not Transition then charactersWindow:hide() end
    if loginEvent then
      removeEvent(loginEvent)
      loginEvent = nil
    end
    tryLogin(charInfo)
  else
    displayErrorBox(tr('Error'), tr('You must select a character to login!'))
  end
end

function CharacterList.destroyLoadBox()
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
end

function CharacterList.cancelWait()
  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil
  end

  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  if resendWaitEvent then
    removeEvent(resendWaitEvent)
    resendWaitEvent = nil
  end

  CharacterList.destroyLoadBox()
  CharacterList.showAgain()
end
