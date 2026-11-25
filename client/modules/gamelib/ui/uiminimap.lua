-- Guide marks: stairs, holes, shops, banks, temples and quests that every
-- player sees from the start. They come from /data/minimap-markers.txt, built
-- by tools/generate-minimap-markers.py, one "x,y,z,icon,description" per line.
-- They are never written to the player's settings, so the marks a player
-- creates keep working as before. Only the marks near the camera get a widget,
-- since the file has thousands of stairs.
local GUIDE_FILE = '/data/minimap-markers.txt'
local GUIDE_SETTING = 'minimapGuideMarks'
local GUIDE_CELL = 64
local GUIDE_MAX_WIDGETS = 400
local GUIDE_STAIRS_MIN_SCALE = 1    -- arrows only when zoomed in enough to tell them apart
local GUIDE_PLACES_MIN_SCALE = 0.25
local GUIDE_STAIR_ICONS = { [14] = true, [15] = true }
local guideMarks

local function loadGuideMarks()
  if guideMarks then return guideMarks end
  guideMarks = { places = {}, stairs = {} }
  if not g_resources.fileExists(GUIDE_FILE) then return guideMarks end
  local ok, content = pcall(function() return g_resources.readFileContents(GUIDE_FILE) end)
  if not ok or type(content) ~= 'string' then return guideMarks end
  for line in content:gmatch('[^\r\n]+') do
    local x, y, z, icon, description = line:match('^(%d+),(%d+),(%d+),(%d+),(.*)$')
    if x then
      local mark = { pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }, icon = tonumber(icon), description = description }
      local z = mark.pos.z
      if GUIDE_STAIR_ICONS[mark.icon] then
        local floor = guideMarks.stairs[z]
        if not floor then floor = {} guideMarks.stairs[z] = floor end
        local key = math.floor(mark.pos.x / GUIDE_CELL) .. ',' .. math.floor(mark.pos.y / GUIDE_CELL)
        local cell = floor[key]
        if not cell then cell = {} floor[key] = cell end
        table.insert(cell, mark)
      else
        local floor = guideMarks.places[z]
        if not floor then floor = {} guideMarks.places[z] = floor end
        table.insert(floor, mark)
      end
    end
  end
  return guideMarks
end

function UIMinimap:onCreate()
  self.autowalk = true
end

function UIMinimap:onSetup()
  self.flagWindow = nil
  self.flags = {}
  self.guideFlags = {}
  self.alternatives = {}
  self.onAddAutomapFlag = function(pos, icon, description) self:addFlag(pos, icon, description) end
  self.onRemoveAutomapFlag = function(pos, icon, description) self:removeFlag(pos, icon, description) end
  connect(g_game, {
    onAddAutomapFlag = self.onAddAutomapFlag,
    onRemoveAutomapFlag = self.onRemoveAutomapFlag,
  })
end

function UIMinimap:onDestroy()
  for _,widget in pairs(self.alternatives) do
    widget:destroy()
  end
  self.alternatives = {}
  disconnect(g_game, {
    onAddAutomapFlag = self.onAddAutomapFlag,
    onRemoveAutomapFlag = self.onRemoveAutomapFlag,
  })
  self:destroyFlagWindow()
  self.flags = {}
  if self.guideEvent then
    removeEvent(self.guideEvent)
    self.guideEvent = nil
  end
  self.guideFlags = {}
end

function UIMinimap:onVisibilityChange()
  if not self:isVisible() then
    self:destroyFlagWindow()
  end
end

function UIMinimap:onCameraPositionChange(cameraPos)
  if self.cross then
    self:setCrossPosition(self.cross.pos)
  end
  self:scheduleGuideFlags()
end

function UIMinimap:scheduleGuideFlags()
  if self.guideEvent then return end
  self.guideEvent = scheduleEvent(function()
    self.guideEvent = nil
    self:updateGuideFlags()
  end, 100)
end

function UIMinimap:areGuideFlagsEnabled()
  return g_settings.getBoolean(GUIDE_SETTING, true)
end

function UIMinimap:setGuideFlagsEnabled(enabled)
  g_settings.set(GUIDE_SETTING, enabled)
  self:updateGuideFlags()
end

-- Creates the widgets of the guide marks around the camera and drops the rest.
function UIMinimap:updateGuideFlags()
  if not self.guideFlags then return end
  local wanted, count = {}, 0
  local camera = self:getCameraPosition()
  local scale = self:getScale()
  if camera and scale and scale > 0 and self:areGuideFlagsEnabled() then
    local marks = loadGuideMarks()
    local halfWidth = math.ceil(self:getWidth() / scale / 2) + 2
    local halfHeight = math.ceil(self:getHeight() / scale / 2) + 2
    local minX, maxX = camera.x - halfWidth, camera.x + halfWidth
    local minY, maxY = camera.y - halfHeight, camera.y + halfHeight
    local function want(mark)
      local pos = mark.pos
      if count < GUIDE_MAX_WIDGETS and pos.x >= minX and pos.x <= maxX and pos.y >= minY and pos.y <= maxY then
        wanted[mark] = true
        count = count + 1
      end
    end
    if scale >= GUIDE_PLACES_MIN_SCALE then
      for _,mark in ipairs(marks.places[camera.z] or {}) do
        want(mark)
      end
    end
    local floor = marks.stairs[camera.z]
    if floor and scale >= GUIDE_STAIRS_MIN_SCALE then
      for cellX = math.floor(minX / GUIDE_CELL), math.floor(maxX / GUIDE_CELL) do
        for cellY = math.floor(minY / GUIDE_CELL), math.floor(maxY / GUIDE_CELL) do
          for _,mark in ipairs(floor[cellX .. ',' .. cellY] or {}) do
            want(mark)
          end
        end
      end
    end
  end

  for mark,flag in pairs(self.guideFlags) do
    if not wanted[mark] then
      self.guideFlags[mark] = nil
      flag:destroy()
    end
  end
  for mark in pairs(wanted) do
    if not self.guideFlags[mark] then
      local flag = g_ui.createWidget('MinimapFlag')
      self:insertChild(1, flag)
      flag.pos = mark.pos
      flag.description = mark.description
      flag.icon = mark.icon
      flag.temporary = true
      flag:setIcon('/images/game/minimap/flag' .. mark.icon)
      flag:setTooltip(mark.description)
      self.guideFlags[mark] = flag
      self:centerInPosition(flag, mark.pos)
    end
  end
end

function UIMinimap:hideFloor()
  self.floorUpWidget:hide()
  self.floorDownWidget:hide()
end

function UIMinimap:hideZoom()
  self.zoomInWidget:hide()
  self.zoomOutWidget:hide()
end

function UIMinimap:disableAutoWalk()
  self.autowalk = false
end

function UIMinimap:load()
  local settings = g_settings.getNode('Minimap')
  if settings then
    if settings.flags then
      for _,flag in pairs(settings.flags) do
        self:addFlag(flag.position, flag.icon, flag.description)
      end
    end
    self:setZoom(settings.zoom)
  end
  self:updateGuideFlags()
end

function UIMinimap:save()
  local settings = { flags={} }
  for _,flag in pairs(self.flags) do
    if not flag.temporary then
      table.insert(settings.flags, {
        position = flag.pos,
        icon = flag.icon,
        description = flag.description,
      })
    end
  end
  settings.zoom = self:getZoom()
  g_settings.setNode('Minimap', settings)
end

local function onFlagMouseRelease(widget, pos, button)
  if button == MouseRightButton then
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    menu:addOption(tr('Delete mark'), function() widget:destroy() end)
    menu:display(pos)
    return true
  end
  return false
end

function UIMinimap:setCrossPosition(pos)
  local cross = self.cross
  if not self.cross then
    cross = g_ui.createWidget('MinimapCross', self)
    cross:setIcon('/images/game/minimap/cross')
    self.cross = cross
  end

  pos.z = self:getCameraPosition().z
  cross.pos = pos
  if pos then
    self:centerInPosition(cross, pos)
  else
    cross:breakAnchors()
  end
end

function UIMinimap:addFlag(pos, icon, description, temporary)
  if not pos or not icon then return end
  local flag = self:getFlag(pos, icon, description)
  if flag or not icon then
    return
  end
  temporary = temporary or false

  flag = g_ui.createWidget('MinimapFlag')
  self:insertChild(1, flag)
  flag.pos = pos
  flag.description = description
  flag.icon = icon
  flag.temporary = temporary
  if type(tonumber(icon)) == 'number' then
    flag:setIcon('/images/game/minimap/flag' .. icon)
  else
    flag:setIcon(resolvepath(icon, 1))
  end
  flag:setTooltip(description)
  flag.onMouseRelease = onFlagMouseRelease
  flag.onDestroy = function() table.removevalue(self.flags, flag) end
  table.insert(self.flags, flag)
  self:centerInPosition(flag, pos)
end

function UIMinimap:addAlternativeWidget(widget, pos, maxZoom)
  widget.pos = pos
  widget.maxZoom = maxZoom or 0
  widget.minZoom = minZoom
  table.insert(self.alternatives, widget)
end

function UIMinimap:setAlternativeWidgetsVisible(show)
  local layout = self:getLayout()
  layout:disableUpdates()
  for _,widget in pairs(self.alternatives) do
    if show then
      self:insertChild(1, widget)
      self:centerInPosition(widget, widget.pos)
    else
      self:removeChild(widget)
    end
  end
  layout:enableUpdates()
  layout:update()
end

function UIMinimap:onZoomChange(zoom)
  self:scheduleGuideFlags()
  for _,widget in pairs(self.alternatives) do
    if (not widget.minZoom or widget.minZoom >= zoom) and widget.maxZoom <= zoom then
      widget:show()
    else
      widget:hide()
    end
  end
end

function UIMinimap:getFlag(pos)
  for _,flag in pairs(self.flags) do
    if flag.pos.x == pos.x and flag.pos.y == pos.y and flag.pos.z == pos.z then
      return flag
    end
  end
  return nil
end

function UIMinimap:removeFlag(pos, icon, description)
  local flag = self:getFlag(pos)
  if flag then
    flag:destroy()
  end
end

function UIMinimap:reset()
  self:setZoom(0)
  if self.cross then
    self:setCameraPosition(self.cross.pos)
  end
end

function UIMinimap:move(x, y)
  local cameraPos = self:getCameraPosition()
  local scale = self:getScale()
  if scale > 1 then scale = 1 end
  local dx = x/scale
  local dy = y/scale
  local pos = {x = cameraPos.x - dx, y = cameraPos.y - dy, z = cameraPos.z}
  self:setCameraPosition(pos)
end

function UIMinimap:onMouseWheel(mousePos, direction)
  local keyboardModifiers = g_keyboard.getModifiers()
  if direction == MouseWheelUp and keyboardModifiers == KeyboardNoModifier then
    self:zoomIn()
  elseif direction == MouseWheelDown and keyboardModifiers == KeyboardNoModifier then
    self:zoomOut()
  elseif direction == MouseWheelDown and keyboardModifiers == KeyboardCtrlModifier then
    self:floorUp(1)
  elseif direction == MouseWheelUp and keyboardModifiers == KeyboardCtrlModifier then
    self:floorDown(1)
  end
end

function UIMinimap:onMousePress(pos, button)
  if not self:isDragging() then
    self.allowNextRelease = true
  end
end

function UIMinimap:onMouseRelease(pos, button)
  if not self.allowNextRelease then return true end
  self.allowNextRelease = false

  local mapPos = self:getTilePosition(pos)
  if not mapPos then return end

  if button == MouseLeftButton then
    local player = g_game.getLocalPlayer()
    if self.autowalk then
      player:autoWalk(mapPos)
    end
    return true
  elseif button == MouseRightButton then
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    menu:addOption(tr('Create mark'), function() self:createFlagWindow(mapPos) end)
    if self:areGuideFlagsEnabled() then
      menu:addOption(tr('Hide guide marks'), function() self:setGuideFlagsEnabled(false) end)
    else
      menu:addOption(tr('Show guide marks'), function() self:setGuideFlagsEnabled(true) end)
    end
    menu:display(pos)
    return true
  end
  return false
end

function UIMinimap:onDragEnter(pos)
  self.dragReference = pos
  self.dragCameraReference = self:getCameraPosition()
  return true
end

function UIMinimap:onDragMove(pos, moved)
  local scale = self:getScale()
  local dx = (self.dragReference.x - pos.x)/scale
  local dy = (self.dragReference.y - pos.y)/scale
  local pos = {x = self.dragCameraReference.x + dx, y = self.dragCameraReference.y + dy, z = self.dragCameraReference.z}
  self:setCameraPosition(pos)
  return true
end

function UIMinimap:onDragLeave(widget, pos)
  return true
end

function UIMinimap:onStyleApply(styleName, styleNode)
  for name,value in pairs(styleNode) do
    if name == 'autowalk' then
      self.autowalk = value
    end
  end
end

function UIMinimap:createFlagWindow(pos)
  if self.flagWindow then return end
  if not pos then return end

  self.flagWindow = g_ui.createWidget('MinimapFlagWindow', rootWidget)

  local positionLabel = self.flagWindow:getChildById('position')
  local description = self.flagWindow:getChildById('description')
  local okButton = self.flagWindow:getChildById('okButton')
  local cancelButton = self.flagWindow:getChildById('cancelButton')

  if positionLabel then
	positionLabel:setText(string.format('%i, %i, %i', pos.x, pos.y, pos.z))
  end
  
  local flagRadioGroup = UIRadioGroup.create()
  for i=0,19 do
    local checkbox = self.flagWindow:getChildById('flag' .. i)
    checkbox.icon = i
    flagRadioGroup:addWidget(checkbox)
  end

  flagRadioGroup:selectWidget(flagRadioGroup:getFirstWidget())

  local successFunc = function()
    self:addFlag(pos, flagRadioGroup:getSelectedWidget().icon, description:getText())
    self:destroyFlagWindow()
  end

  local cancelFunc = function()
    self:destroyFlagWindow()
  end

  okButton.onClick = successFunc
  cancelButton.onClick = cancelFunc

  self.flagWindow.onEnter = successFunc
  self.flagWindow.onEscape = cancelFunc

  self.flagWindow.onDestroy = function() flagRadioGroup:destroy() end
end

function UIMinimap:destroyFlagWindow()
  if self.flagWindow then
    self.flagWindow:destroy()
    self.flagWindow = nil
  end
end
