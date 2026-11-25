-- Rendering policy only. The server acknowledges the actual map buffer before
-- the UI expands; visible dimensions are odd and leave a walking margin.
AntigasViewport = {classicWidth = 15, classicHeight = 11, maxWidth = 29, maxHeight = 15}

function AntigasViewport.calculate(width, height, mode)
  if mode ~= 2 or width <= 0 or height <= 0 then
    return {width = 15, height = 11, wide = false}
  end
  local ratio = width / height
  local rows = math.max(11, math.min(15, math.floor(height / 64)))
  if rows % 2 == 0 then rows = rows + 1 end
  local function columns(y)
    local x = math.max(3, math.floor(y * ratio))
    return x % 2 == 0 and x + 1 or x
  end
  while rows > 3 and columns(rows) > AntigasViewport.maxWidth do rows = rows - 2 end
  local cols = columns(rows)
  -- Extremely short/wide windows keep a bounded, proportionate view.
  return {width = math.min(cols, AntigasViewport.maxWidth), height = rows,
    wide = cols <= AntigasViewport.maxWidth}
end

function AntigasViewport.requestSize(dimension)
  -- +3 keeps 2 tiles of map beyond each edge, so walking 2 steps ahead
  -- of the server (prewalk) never shows unloaded black borders.
  return math.max(18, dimension.width + 3), math.max(14, dimension.height + 3)
end
