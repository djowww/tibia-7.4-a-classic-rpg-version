-- A small speech balloon is shown beside every NPC. Clicking it greets the NPC.
-- The balloon uses the skull slot of the client (NPCs never have a skull),
-- which is drawn together with the names: on top of the map, never hidden by
-- walls or items, unscaled and following the NPC while it walks. The image has
-- transparent padding on the left so the balloon sits to the right of the
-- head, below the name line.
local ICON_PATH = '/modules/game_npcballoon/balloon'
-- Visible balloon in screen pixels, relative to the point where the client
-- draws the creature information (centre of the sprite, just above it).
local ICON = {x = 17, y = 5, width = 16, height = 12}
local MARGIN = 4
local SPRITE = 32
-- Creature sprites are drawn 8 pixels up and to the left of their tile.
local DISPLACEMENT = 8
local PROBE = 96
local TALK_RANGE = 3
local GREETING = 'hi'
-- Skull id without a stock image, so only the balloon texture is drawn.
local BALLOON_SKULL = 7

local STEP = {
  [North] = {x = 0, y = -1}, [East] = {x = 1, y = 0}, [South] = {x = 0, y = 1}, [West] = {x = -1, y = 0},
  [NorthEast] = {x = 1, y = -1}, [SouthEast] = {x = 1, y = 1}, [SouthWest] = {x = -1, y = 1}, [NorthWest] = {x = -1, y = -1}
}

local balloons = {}
local scanEvent = nil

local function isNpc(creature)
  return creature and creature.isNpc and creature:isNpc()
end

local function addBalloon(creature)
  if not isNpc(creature) then return end
  if creature:getSkull() ~= BALLOON_SKULL then
    creature:setSkull(BALLOON_SKULL)
  end
  local id = creature:getId()
  if balloons[id] ~= creature then
    creature:setSkullTexture(ICON_PATH)
    balloons[id] = creature
  end
end

-- The server may describe a known NPC again, which resets its skull.
local function onSkullChange(creature, skull)
  if skull ~= BALLOON_SKULL and isNpc(creature) then
    balloons[creature:getId()] = nil
    addBalloon(creature)
  end
end

local function clear()
  balloons = {}
end

local function scan()
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  local seen = {}
  for _, creature in ipairs(g_map.getSpectators(pos, true)) do
    if isNpc(creature) then
      addBalloon(creature)
      seen[creature:getId()] = true
    end
  end
  for id in pairs(balloons) do
    if not seen[id] then balloons[id] = nil end
  end
end

-- onAppear alone misses NPCs already known at login or re-sent by the server,
-- so the creatures in view are also checked twice a second.
function init()
  connect(Creature, {onAppear = addBalloon, onSkullChange = onSkullChange})
  connect(g_game, {onGameStart = scan, onGameEnd = clear})
  scanEvent = cycleEvent(function() if g_game.isOnline() then scan() end end, 500)
  if g_game.isOnline() then scan() end
end

function terminate()
  removeEvent(scanEvent)
  scanEvent = nil
  disconnect(Creature, {onAppear = addBalloon, onSkullChange = onSkullChange})
  disconnect(g_game, {onGameStart = scan, onGameEnd = clear})
  for _, creature in pairs(balloons) do
    pcall(function() creature:setSkull(SkullNone) end)
  end
  clear()
end

-- Map pixel (32 per tile) under a screen point, or nil outside the map.
local function mapPixel(map, point)
  local pos = map:getPosition(point)
  if not pos then return nil end
  local offset = map:getPositionOffset(point)
  if not offset then return nil end
  return {x = pos.x * SPRITE + offset.x, y = pos.y * SPRITE + offset.y}
end

-- Screen pixels per map pixel around the mouse, measured with a second point.
local function mapScale(map, mousePos, origin)
  local scale = {}
  for _, axis in ipairs({'x', 'y'}) do
    for _, delta in ipairs({PROBE, -PROBE}) do
      local point = {x = mousePos.x, y = mousePos.y}
      point[axis] = point[axis] + delta
      local other = mapPixel(map, point)
      local span = other and math.abs(other[axis] - origin[axis]) or 0
      if span > 0 then
        scale[axis] = PROBE / span
        break
      end
    end
  end
  if not scale.x and not scale.y then return nil end
  return {x = scale.x or scale.y, y = scale.y or scale.x}
end

-- While walking the NPC already stands on the destination tile and is drawn
-- sliding towards it.
local function walkOffset(creature)
  if not creature:isWalking() then return 0, 0 end
  local step = STEP[creature:getDirection()]
  if not step then return 0, 0 end
  local duration = creature:getStepDuration()
  if not duration or duration <= 0 then return 0, 0 end
  local left = (1 - math.max(0, math.min(1, creature:getWalkTicksElapsed() / duration))) * SPRITE
  return -step.x * left, -step.y * left
end

-- Called by UIGameMap on a left click. Returns true when the click hit a balloon.
function onMapClick(map, mousePos)
  if not g_game.isOnline() or not next(balloons) then return false end
  local player = g_game.getLocalPlayer()
  local playerPos = player and player:getPosition()
  if not playerPos then return false end
  local mouse = mapPixel(map, mousePos)
  if not mouse then return false end
  local scale = mapScale(map, mousePos, mouse)
  if not scale then return false end

  for _, creature in pairs(balloons) do
    local npcPos = creature:getPosition()
    if npcPos and npcPos.z == playerPos.z then
      local walkX, walkY = walkOffset(creature)
      local pointX = npcPos.x * SPRITE + SPRITE / 2 - DISPLACEMENT + walkX
      local pointY = npcPos.y * SPRITE - DISPLACEMENT - 2 + walkY
      local x = (mouse.x - pointX) * scale.x - ICON.x
      local y = (mouse.y - pointY) * scale.y - ICON.y
      if x >= -MARGIN and x <= ICON.width + MARGIN and y >= -MARGIN and y <= ICON.height + MARGIN then
        greet(creature)
        return true
      end
    end
  end
  return false
end

-- Says the greeting to an NPC. Returns false when the creature is not an NPC,
-- so callers can fall back to their normal action (attack, follow...).
function greet(creature)
  if not isNpc(creature) then return false end
  local player = g_game.getLocalPlayer()
  local npcPos, playerPos = creature:getPosition(), player and player:getPosition()
  if not npcPos or not playerPos then return true end
  if npcPos.z ~= playerPos.z then
    modules.game_textmessage.displayFailureMessage(tr('You are too far away.'))
    return true
  end
  local distance = math.max(math.abs(npcPos.x - playerPos.x), math.abs(npcPos.y - playerPos.y))
  if distance > TALK_RANGE then
    modules.game_textmessage.displayFailureMessage(tr('You are too far away.'))
    return true
  end
  g_game.talk(GREETING)
  return true
end
