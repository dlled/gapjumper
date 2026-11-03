-- Runs the real event handling against a fake Hammerspoon.

local function fakeWatcher(log, name)
  return {
    start = function() log[name] = true end,
    stop = function() log[name] = false end,
  }
end

local function load(screens, configFile, keepGlobal)
  package.loaded["gapjumper"] = nil
  if not keepGlobal then gapJumper = nil end

  local dir = os.tmpname()
  os.remove(dir)
  if configFile then
    os.execute("mkdir -p '" .. dir .. "'")
    local file = assert(io.open(dir .. "/gapjumper_config.lua", "w"))
    file:write(configFile)
    file:close()
  end

  local world = { now = 100, posted = {}, running = {}, alerts = {}, enabled = false, starts = 0 }

  local function screenObject(f)
    return {
      name = function() return f.name end,
      fullFrame = function() return f end,
    }
  end
  world.screens = screens

  hs = {
    configdir = dir,
    accessibilityState = function() return true end,
    autoLaunch = function() return true end,
    alert = { show = function(text) table.insert(world.alerts, text) end },
    timer = {
      secondsSinceEpoch = function() return world.now end,
      new = function(_, fn) world.guardian = fn; return fakeWatcher(world.running, "guardian") end,
    },
    screen = {
      allScreens = function()
        local objects = {}
        for _, f in ipairs(world.screens) do table.insert(objects, screenObject(f)) end
        return objects
      end,
      watcher = {
        new = function(fn) world.screensChanged = fn; return fakeWatcher(world.running, "screens") end,
      },
    },
    caffeinate = {
      watcher = {
        systemDidWake = "wake",
        screensDidWake = "screensWake",
        sessionDidBecomeActive = "session",
        systemWillSleep = "sleep",
        new = function(fn) world.power = fn; return fakeWatcher(world.running, "wake") end,
      },
    },
    eventtap = {
      new = function(types, fn)
        world.types, world.tapped = types, fn
        return {
          start = function() world.enabled = true; world.starts = world.starts + 1 end,
          stop = function() world.enabled = false end,
          isEnabled = function() return world.enabled end,
        }
      end,
      event = {
        properties = { mouseEventDeltaX = "dx", mouseEventDeltaY = "dy" },
        types = { mouseMoved = "moved", leftMouseDragged = "dragged" },
        newMouseEvent = function(kind, point)
          return { post = function() table.insert(world.posted, { kind = kind, point = point }) end }
        end,
      },
    },
  }

  local module = require("gapjumper")

  function world.move(x, y, dx, dy, kind)
    local event = {
      getProperty = function(_, name) return name == "dx" and dx or dy end,
      location = function() return { x = x, y = y } end,
      getType = function() return kind or "moved" end,
    }
    return world.tapped(event)
  end

  world.cleanup = function() os.execute("rm -rf '" .. dir .. "'") end
  return world, module
end

local r = T.frame
local laptop = r("laptop", 0, 0, 1000, 800)
local tall = r("tall", 1000, 0, 1000, 1600)
local pair = { laptop, tall }
local BLOCKED = { 1000, 1200 }  -- left edge of the tall display, past the laptop

local function push(world, times, kind)
  local last
  for _ = 1, times do
    world.now = world.now + 0.01
    last = world.move(BLOCKED[1], BLOCKED[2], -5, 0, kind)
  end
  return last
end

do
  local world = load(pair)
  T.check("alert on load", world.alerts[1] == "Gap Jumper active")
  T.check("listens to moves and drags", world.types[1] == "moved" and world.types[2] == "dragged")
  T.check("everything started", world.enabled and world.running.screens
    and world.running.guardian and world.running.wake)
  T.check("global survives garbage collection", gapJumper ~= nil)

  T.check("below the threshold passes through", push(world, 2) == false and #world.posted == 0)
  T.check("the threshold jump drops the event", push(world, 1) == true)
  T.check("jump posts one event", #world.posted == 1)
  local jump = world.posted[1]
  T.check("jump lands on the laptop", jump.point.x == 998 and jump.point.y == 798)
  T.check("jump keeps the event type", jump.kind == "moved")
  world.cleanup()
end

do
  local world = load(pair)
  push(world, 3, "dragged")
  T.check("a drag stays a drag", world.posted[1].kind == "dragged")

  world.posted = {}
  push(world, 3)
  T.check("cooldown blocks a second jump", #world.posted == 0)
  world.now = world.now + 1
  push(world, 3)
  T.check("jumps again after the cooldown", #world.posted == 1)
  world.cleanup()
end

do
  local world = load(pair)
  push(world, 2)
  world.now = world.now + 1
  push(world, 2)
  T.check("a pause resets the push", #world.posted == 0)

  world.move(1500, 500, 5, 0)
  push(world, 2)
  T.check("leaving the edge resets the push", #world.posted == 0)

  world.move(500, 400, 0, 0)
  T.check("no movement is ignored", #world.posted == 0)
  world.cleanup()
end

do
  local world = load(pair)
  for _ = 1, 10 do
    world.now = world.now + 0.01
    T.check("native edge is left alone", world.move(1000, 400, -5, 0) == false)
  end
  T.check("native edge never jumps", #world.posted == 0)
  world.cleanup()
end

do
  local world = load({ laptop })
  for _ = 1, 10 do
    world.now = world.now + 0.01
    T.check("single display passes events", world.move(999, 400, 5, 0) == false)
  end
  T.check("single display never jumps", #world.posted == 0)
  world.cleanup()
end

do
  local world, module = load({ laptop })
  world.screens = pair
  local starts = world.starts
  world.screensChanged()
  T.check("display change refreshes frames", #module.frames == 2)
  T.check("display change restarts the tap", world.starts == starts + 1 and world.enabled)
  push(world, 3)
  T.check("jumps on a display connected later", #world.posted == 1)

  world.screens = { laptop }
  world.screensChanged()
  T.check("disconnecting drops the display", #module.frames == 1)
  world.cleanup()
end

do
  local world, module = load(pair)
  world.enabled = false
  world.guardian()
  T.check("guardian restarts a disabled tap", world.enabled)

  world.enabled = false
  world.screens = { laptop }
  world.power("wake")
  T.check("wake restarts the tap and refreshes", world.enabled and #module.frames == 1)

  module.stop()
  T.check("stop halts everything", not world.enabled and not world.running.screens
    and not world.running.guardian and not world.running.wake)
  module.start()
  T.check("start resumes", world.enabled and world.running.screens)
  world.cleanup()
end

do
  local world, module = load(pair, "return { MIN_PUSH = 30 }")
  T.check("user config is applied", module.config.MIN_PUSH == 30)
  push(world, 3)
  T.check("user threshold is respected", #world.posted == 0)
  world.cleanup()
end

do
  local printed = _G.print
  _G.print = function() end
  local broken, brokenModule = load(pair, "this is not lua")
  local wrong, wrongModule = load(pair, "return { MIN_PUSH = 'lots', NOPE = 1 }")
  _G.print = printed
  T.check("broken config still loads", brokenModule.config.MIN_PUSH == 12)
  T.check("wrong config keeps defaults", wrongModule.config.MIN_PUSH == 12)
  T.check("broken config is reported", brokenModule.status():find("problem=", 1, true) ~= nil)
  T.check("wrong config is reported", wrongModule.status():find("NOPE", 1, true) ~= nil)
  broken.cleanup()
  wrong.cleanup()
end

do
  local world, module = load(pair)
  local status = module.status()
  T.check("status reports the tap", status:find("tap=true", 1, true) ~= nil)
  T.check("status reports displays", status:find("displays=2", 1, true) ~= nil)
  T.check("a good layout has no problems", status:find("problem=", 1, true) == nil)
  T.check("report names the displays", module.report():find("JUMPS to laptop", 1, true) ~= nil)
  world.cleanup()
end

do
  local world = load(pair)
  world.now = world.now + 0.01
  T.check("one push just below the threshold passes", world.move(1000, 1200, -11, 0) == false)
  world.now = world.now + 1
  T.check("one push at the threshold jumps at once", world.move(1000, 1200, -12, 0) == true)
  T.check("the big push posts one event", #world.posted == 1)

  world.now = world.now + 0.01
  T.check("events during the cooldown pass through", world.move(1000, 1200, -50, 0) == false)
  T.check("nothing posted during the cooldown", #world.posted == 1)
  world.cleanup()
end

do
  local world = load(pair)
  world.now = world.now + 0.01
  T.check("a cursor outside every display passes", world.move(-50, -50, -20, 0) == false)
  T.check("outside every display never jumps", #world.posted == 0)
  push(world, 2)
  world.move(1000, 1200, 0, 5)
  push(world, 1)
  T.check("moving along the edge resets the push", #world.posted == 0)
  world.cleanup()
end

do
  local world = load(pair)
  push(world, 3)
  T.check("first jump before the clock change", #world.posted == 1)
  world.now = world.now - 60
  push(world, 3)
  T.check("a clock moving backwards does not block jumps", #world.posted == 2)
  world.cleanup()
end

do
  local world = load(pair)
  push(world, 2)
  world.screensChanged()
  push(world, 1)
  T.check("a display change resets the push", #world.posted == 0)
  push(world, 2)
  T.check("pushing again after the change jumps", #world.posted == 1)
  world.cleanup()
end

do
  local world, module = load(pair)
  for _, event in ipairs({ "screensWake", "session" }) do
    world.enabled = false
    world.screens = event == "session" and pair or { laptop }
    world.power(event)
    T.check("power event " .. event .. " restarts the tap", world.enabled)
  end
  T.check("power events refresh the displays", #module.frames == 2)

  world.enabled = true
  world.screens = { laptop }
  world.power("sleep")
  T.check("going to sleep leaves the displays alone", #module.frames == 2)
  world.cleanup()
end

do
  local first = load(pair)
  local second, secondModule = load(pair, nil, true)
  T.check("loading again stops the previous tap", not first.enabled)
  T.check("loading again stops the previous watchers", not first.running.screens
    and not first.running.guardian and not first.running.wake)
  T.check("the new instance is running", second.enabled and gapJumper == secondModule)
  first.cleanup()
  second.cleanup()
end

do
  local world, module = load({})
  T.check("no displays loads", #module.frames == 0)
  local ok, status = pcall(module.status)
  T.check("status works with no displays", ok and status:find("displays=0", 1, true) ~= nil, status)
  T.check("report works with no displays", pcall(module.report))
  world.now = world.now + 0.01
  T.check("moves pass with no displays", world.move(10, 10, 20, 0) == false)
  world.cleanup()
end

do
  local world, module = load({ laptop, r("overlap", 500, 0, 1000, 800) })
  T.check("an overlapping layout is reported", module.status():find("overlaps", 1, true) ~= nil)
  world.cleanup()
end

do
  local world, module = load({ laptop, r("mirror", 0, 0, 1000, 800), tall })
  T.check("mirrored displays are not a problem", module.status():find("problem=", 1, true) == nil)
  push(world, 3)
  T.check("jumps with a mirrored display", #world.posted == 1)
  world.cleanup()
end

do
  local printed = _G.print
  local lines = {}
  _G.print = function(text) table.insert(lines, text) end
  local world, module = load(pair, "return 5")
  _G.print = printed
  T.check("a config that is not a table keeps defaults", module.config.MIN_PUSH == 12)
  T.check("a config that is not a table is reported",
    module.status():find("problem=ignored gapjumper_config.lua", 1, true) ~= nil)
  T.check("config problems are printed to the console", #lines > 0)
  world.cleanup()
end

do
  local world, module = load(pair, "return {}")
  T.check("an empty config has no problems", module.status():find("problem=", 1, true) == nil)
  world.cleanup()
end

hs = nil
gapJumper = nil
package.loaded["gapjumper"] = nil
