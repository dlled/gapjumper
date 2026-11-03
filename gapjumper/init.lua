-- Gap Jumper: when you push the mouse against an edge with no adjacent display,
-- the cursor jumps to the nearest display in that direction.

local G = require("gapjumper.geometry")

local M = {}

-- Settings live outside the module so reinstalling does not overwrite them.
local function loadSettings()
  local path = hs.configdir .. "/gapjumper_config.lua"
  local file = io.open(path, "r")
  if not file then return {}, {} end
  file:close()
  local ok, settings = pcall(dofile, path)
  if ok and type(settings) == "table" then return settings, {} end
  local reason = ok and "it must return a table, got " .. type(settings) or tostring(settings)
  return {}, { "ignored gapjumper_config.lua: " .. reason }
end

local props = hs.eventtap.event.properties

local function onMove(event)
  local dx = event:getProperty(props.mouseEventDeltaX)
  local dy = event:getProperty(props.mouseEventDeltaY)
  local now = hs.timer.secondsSinceEpoch()
  -- The wall clock can jump backwards (NTP, manual change); without this a
  -- stale cooldown could keep jumps blocked until the clock catches up.
  if M.blockedUntil - now > M.config.COOLDOWN then M.blockedUntil = 0 end
  if (dx == 0 and dy == 0) or now < M.blockedUntil then return false end

  local pos = event:location()
  local f = G.screenAt(M.frames, pos.x, pos.y)
  local direction, point, push
  if f then direction, point, push = G.findJump(M.frames, f, pos, dx, dy, M.config) end
  if not direction then
    M.push, M.direction = 0, nil
    return false
  end

  if direction ~= M.direction or now - M.lastPush > M.config.PUSH_TIMEOUT then
    M.push = 0
  end
  M.direction, M.lastPush = direction, now
  M.push = M.push + push

  if M.push >= M.config.MIN_PUSH then
    M.push, M.direction = 0, nil
    M.blockedUntil = now + M.config.COOLDOWN
    -- hs.mouse.absolutePosition uses CGWarpMouseCursorPosition, which ignores
    -- the physical mouse for ~0.25 s. A posted event has no such pause.
    hs.eventtap.event.newMouseEvent(event:getType(), point):post()
    return true
  end
  return false
end

local function refreshScreens()
  -- A push accumulated against the old layout must not carry over.
  M.push, M.direction = 0, nil
  M.frames = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    table.insert(M.frames, { name = screen:name(), x = f.x, y = f.y, x2 = f.x2, y2 = f.y2 })
  end
end

function M.stop()
  M.wakeWatcher:stop()
  M.guardian:stop()
  M.screenWatcher:stop()
  M.tap:stop()
end

function M.start()
  refreshScreens()
  M.tap:start()
  M.screenWatcher:start()
  M.guardian:start()
  M.wakeWatcher:start()
end

function M.report()
  return G.report(M.frames, M.config)
end

-- Machine-readable state for doctor.sh, one key=value per line.
function M.status()
  local problems = G.validate(M.frames, M.config)
  for _, problem in ipairs(M.settingsProblems) do table.insert(problems, problem) end
  local lines = {
    "tap=" .. tostring(M.tap:isEnabled()),
    "accessibility=" .. tostring(hs.accessibilityState(false)),
    "displays=" .. #M.frames,
    "autostart=" .. tostring(hs.autoLaunch()),
  }
  for _, problem in ipairs(problems) do table.insert(lines, "problem=" .. problem) end
  return table.concat(lines, "\n")
end

local settings, settingsProblems = loadSettings()
local config, configProblems = G.config(settings)
for _, problem in ipairs(configProblems) do table.insert(settingsProblems, problem) end
M.config, M.settingsProblems = config, settingsProblems
for _, problem in ipairs(settingsProblems) do print("gapjumper: " .. problem) end

-- If the module is loaded again in the same Lua state (without hs.reload), stop
-- the previous instance so two taps never handle the same events.
if type(gapJumper) == "table" and type(gapJumper.stop) == "function" then
  pcall(gapJumper.stop)
end

-- Restarting (not just starting) also revives a tap macOS left enabled but deaf.
local function restartTap()
  M.tap:stop()
  M.tap:start()
end

M.push, M.lastPush, M.blockedUntil = 0, 0, 0
M.onMove = onMove
M.tap = hs.eventtap.new(
  { hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.leftMouseDragged },
  function(event) return M.onMove(event) end
)
M.screenWatcher = hs.screen.watcher.new(function()
  refreshScreens()
  restartTap()
end)
-- macOS disables event taps after sleep or when a callback runs late
-- (kCGEventTapDisabledByTimeout). continueOnError keeps the timer alive.
M.guardian = hs.timer.new(5, function()
  if not M.tap:isEnabled() then M.tap:start() end
end, true)
local watcher = hs.caffeinate.watcher
M.wakeWatcher = watcher.new(function(event)
  if event == watcher.systemDidWake or event == watcher.screensDidWake
    or event == watcher.sessionDidBecomeActive then
    refreshScreens()
    restartTap()
  end
end)

-- Global so the garbage collector does not stop the event tap or the watchers.
gapJumper = M

M.start()
hs.alert.show("Gap Jumper active")

return M
