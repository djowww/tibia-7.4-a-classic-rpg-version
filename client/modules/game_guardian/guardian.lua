-- Guardian: the launcher writes its session token to guardian.session before
-- it starts the client. After login the token goes to the server (opcode 136,
-- data/lib/custom/guardian.lua), which links this character to the launcher
-- session. Without the file nothing is sent and the server notes that the
-- client was opened without the launcher.
local OPCODE = 136
local TOKEN_FILE = '/guardian.session'

local sendEvent

local function readToken()
  if not g_resources.fileExists(TOKEN_FILE) then return nil end
  local ok, content = pcall(g_resources.readFileContents, TOKEN_FILE)
  if not ok or type(content) ~= 'string' then return nil end
  local token = content:match('^%s*(%x+)%s*$')
  if token and #token == 32 then return token:lower() end
  return nil
end

local function send()
  sendEvent = nil
  local protocol = g_game.getProtocolGame()
  if not protocol or not g_game.isOnline() or not g_game.getFeature(GameExtendedOpcode) then return end
  local token = readToken()
  if token then protocol:sendExtendedOpcode(OPCODE, token) end
end

local function onGameStart()
  removeEvent(sendEvent)
  sendEvent = scheduleEvent(send, 1000)
end

-- The server answers "ok" when it linked this character to the launcher session.
local function onAnswer(protocol, opcode, buffer)
  g_logger.info('Guardian session: ' .. tostring(buffer))
end

function init()
  ProtocolGame.registerExtendedOpcode(OPCODE, onAnswer, true)
  connect(g_game, { onGameStart = onGameStart })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  removeEvent(sendEvent)
  sendEvent = nil
end
