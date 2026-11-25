-- Runs the client's minimap widget code against the generated guide marks,
-- with the client API mocked: luajit tests/lua/minimap-guide-marks-tests.lua
local created, destroyed, settings, pending = 0, 0, {}, {}

g_resources = {
  fileExists = function(path) return io.open('client' .. path, 'rb') ~= nil end,
  readFileContents = function(path)
    local file = assert(io.open('client' .. path, 'rb'))
    local content = file:read('*a')
    file:close()
    return content
  end,
}
g_settings = {
  getBoolean = function(key, default) if settings[key] == nil then return default end return settings[key] end,
  set = function(key, value) settings[key] = value end,
  getNode = function() return { zoom = 0, flags = { { position = { x = 32369, y = 32241, z = 7 }, icon = 3, description = 'minha marca' } } } end,
  setNode = function(key, value) settings[key] = value end,
}
g_ui = { createWidget = function()
  created = created + 1
  local widget = {}
  function widget:setIcon(icon) self.iconPath = icon end
  function widget:setTooltip(text) self.tooltip = text end
  function widget:destroy() destroyed = destroyed + 1 if self.onDestroy then self.onDestroy() end end
  return widget
end }
g_game = {}
function connect() end
function disconnect() end
function scheduleEvent(callback) table.insert(pending, callback) return callback end
function removeEvent() end
function table.removevalue(list, value)
  for index, item in ipairs(list) do if item == value then table.remove(list, index) return end end
end
local function runEvents()
  local events = pending
  pending = {}
  for _, callback in ipairs(events) do callback() end
end

UIMinimap = {}
dofile('client/modules/gamelib/ui/uiminimap.lua')

local map = setmetatable({ camera = { x = 32369, y = 32241, z = 7 }, scale = 1, zoom = 0 }, { __index = UIMinimap })
function map:getCameraPosition() return self.camera end
function map:getScale() return self.scale end
function map:getZoom() return self.zoom end
function map:setZoom(zoom) self.zoom = zoom self:onZoomChange(zoom) end
function map:getWidth() return 176 end
function map:getHeight() return 176 end
function map:insertChild() end
function map:centerInPosition() end
function map:destroyFlagWindow() end

local function count(icon)
  local total = 0
  for mark in pairs(map.guideFlags) do
    if not icon or mark.icon == icon then total = total + 1 end
  end
  return total
end

map:onSetup()
map:load()
runEvents()
assert(#map.flags == 1, 'the mark saved by the player is loaded')
assert(count(5) == 1, 'Thais temple has its cross')
assert(count(14) + count(15) > 0, 'stairs around the temple are marked')
for mark, flag in pairs(map.guideFlags) do
  assert(flag.temporary and flag.tooltip == mark.description)
  assert(math.abs(mark.pos.x - map.camera.x) <= 90 and math.abs(mark.pos.y - map.camera.y) <= 90 and mark.pos.z == 7)
end
print('Thais, zoom normal: ' .. count() .. ' marks (' .. count(14) .. ' up, ' .. count(15) .. ' down)')

-- Saving keeps only what the player created.
map:save()
assert(#settings.Minimap.flags == 1 and settings.Minimap.flags[1].description == 'minha marca')

-- Zoomed out: shops, banks and temples stay, the arrows go away.
map.scale = 0.25
map:onZoomChange(-2)
runEvents()
assert(count(14) + count(15) == 0 and count(5) >= 1 and count(13) == 1)
print('Thais, zoom afastado: ' .. count() .. ' marks')

-- Walking away replaces the widgets instead of piling them up.
map.scale = 1
map.camera = { x = 32957, y = 32076, z = 7 }
map:onCameraPositionChange(map.camera)
runEvents()
assert(count(5) == 1 and created - destroyed == count() + 1)
assert(count() <= 400)

-- Another floor shows that floor only.
map.camera = { x = 32369, y = 32241, z = 8 }
map:onCameraPositionChange(map.camera)
runEvents()
for mark in pairs(map.guideFlags) do assert(mark.pos.z == 8) end

-- The player can turn the guide marks off; their own marks stay.
map:setGuideFlagsEnabled(false)
assert(count() == 0 and #map.flags == 1)
map:setGuideFlagsEnabled(true)
assert(count() > 0)
print('minimap guide marks tests passed')
