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

  CharacterList.hide()
  
  g_game.loginWorld(G.account, G.password, charInfo.worldName, charInfo.worldHost, charInfo.worldPort, charInfo.characterName, G.authenticatorToken, G.sessionKey)
  -- g_logger.info("Login to " .. charInfo.worldHost .. ":" .. charInfo.worldPort)
  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to game server...'))
  connect(loadBox, { onCancel = function()
                                  loadBox = nil
                                  g_game.cancelLogin()
                                  CharacterList.show()
                                end })

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
  scheduleAutoReconnect()
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

local function relayout()
  if not charactersWindow then return end
  local tile = 32 * SCENE_ZOOM
  local px = math.floor(LIST_RIGHT + (charactersWindow:getWidth() - LIST_RIGHT) / 2)
  local py = math.floor(charactersWindow:getHeight() * 0.46)
  local heroTile = charactersWindow:getChildById('heroTile')
  heroTile:setMarginLeft(px - tile / 2)
  heroTile:setMarginTop(py - tile / 2)
  local scene = charactersWindow:getChildById('scene')
  scene:setMarginLeft(px - (SCENE_TILE_X + 0.5) * tile)
  scene:setMarginTop(py - (SCENE_TILE_Y + 0.5) * tile)
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

function CharacterList.nextCharacter()
  if not characterList or characterList:getChildCount() < 2 then return end
  local selected = characterList:getFocusedChild()
  local index = selected and characterList:getChildIndex(selected) or 0
  local nextIndex = index % characterList:getChildCount() + 1
  characterList:focusChild(characterList:getChildByIndex(nextIndex), KeyboardFocusReason)
end

function CharacterList.rotateHero(step)
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
  removeEvent(autoReconnectEvent)
  autoReconnectEvent = nil

  local selected = characterList:getFocusedChild()
  if selected then
    local charInfo = { worldHost = selected.worldHost,
                       worldPort = selected.worldPort,
                       worldName = selected.worldName,
                       characterName = selected.characterName }
    charactersWindow:hide()
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
