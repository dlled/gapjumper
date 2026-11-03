-- Exact landing points on layouts with known geometry.

local G = require("gapjumper.geometry")
local config = G.config()
local r = T.frame

local function jump(name, frames, f, perp, direction, target, x, y)
  local point, t = G.target(frames, f, perp, direction, config)
  local ok = t == target and (not target or (point.x == x and point.y == y))
  T.check(name, ok, string.format("%s (%s, %s)", t and t.name or "nil",
    point and point.x or "-", point and point.y or "-"))
end

local function native(name, frames, f, perp, direction, expected)
  T.check(name, (G.neighbor(frames, f, perp, direction) ~= nil) == expected)
end

local laptop = r("laptop", 0, 0, 1512, 982)
local top = r("top", -213, -1080, 1920, 1080)

-- Portrait monitors beside the laptop
local left = r("left", -1080, 0, 1080, 1920)
local right = r("right", 1512, 0, 1080, 1920)
local beside = { laptop, top, left, right }

jump("portrait up to top monitor", beside, right, 2000, "up", top, 1705, -2)
jump("other portrait up to top monitor", beside, left, -600, "up", top, -211, -2)
jump("portrait to laptop below its edge", beside, right, 1500, "left", laptop, 1510, 980)
jump("other portrait to laptop below its edge", beside, left, 1500, "right", laptop, 2, 980)
jump("top monitor to portrait", beside, top, -500, "right", right, 1709, 2)
jump("top monitor to other portrait", beside, top, -500, "left", left, -215, 2)
jump("laptop Dock does not jump", beside, laptop, 700, "down", nil)
jump("outer edge does not jump", beside, right, 500, "right", nil)
jump("top of top monitor does not jump", beside, top, 500, "up", nil)

native("portrait to laptop is native", beside, right, 500, "left", true)
native("portrait below laptop is not", beside, right, 1500, "left", false)
native("portrait and top monitor overlap is native", beside, right, 1600, "up", true)
native("portrait past top monitor is not", beside, right, 2000, "up", false)
native("laptop to top monitor is native", beside, laptop, 700, "up", true)

-- Portrait monitors raised beside the top monitor
local raisedLeft = r("left", -1293, -950, 1080, 1920)
local raisedRight = r("right", 1707, -950, 1080, 1920)
local raised = { laptop, top, raisedLeft, raisedRight }

jump("laptop to portrait across the gap", raised, laptop, 500, "left", raisedLeft, -215, 500)
jump("laptop to other portrait across the gap", raised, laptop, 500, "right", raisedRight, 1709, 500)
jump("portrait to laptop straight ahead", raised, raisedLeft, 100, "right", laptop, 2, 100)
jump("other portrait to laptop straight ahead", raised, raisedRight, 100, "left", laptop, 1510, 100)
jump("portrait low on the laptop", raised, raisedRight, 950, "left", laptop, 1510, 950)
jump("Dock does not jump here either", raised, laptop, 700, "down", nil)

native("portrait upper half reaches top monitor", raised, raisedLeft, -500, "right", true)
native("other portrait upper half reaches top monitor", raised, raisedRight, -500, "left", true)

-- Dominant axis and edge detection
local function find(name, pos, dx, dy, direction)
  local got = G.findJump(beside, right, pos, dx, dy, config)
  T.check(name, got == direction, got)
end

find("cursor one pixel inside the edge", { x = 2000, y = 0 }, 0, -5, "up")
find("fractional cursor on the far edge", { x = 1512.5, y = 1500 }, -5, 0, "left")
find("away from the edge does nothing", { x = 2000, y = 40 }, 0, -5, nil)
find("moving along the edge does nothing", { x = 2000, y = 0 }, 5, 0, nil)
find("moving away from the edge does nothing", { x = 2000, y = 0 }, 0, 5, nil)
find("corner uses the blocked axis", { x = 2000, y = 0 }, 2, -9, "up")

-- Settings
local custom, problems = G.config({ MIN_PUSH = 30 })
T.check("setting is applied", custom.MIN_PUSH == 30 and #problems == 0)
for name, overrides in pairs({
  unknown = { NOPE = 1 },
  ["wrong type"] = { MIN_PUSH = "12" },
  negative = { COOLDOWN = -1 },
  ["zero push"] = { MIN_PUSH = 0 },
}) do
  local result, found = G.config(overrides)
  T.check("rejects " .. name, #found == 1 and result.MIN_PUSH == G.DEFAULTS.MIN_PUSH)
end

-- Validation reports what it should
local overlapping = { r("a", 0, 0, 1000, 800), r("b", 500, 0, 1000, 800) }
T.check("overlapping displays are reported", #G.validate(overlapping, config, 8) > 0)
local tiny = { r("a", 0, 0, 1000, 800), r("b", 1000, 0, 1, 1) }
T.check("impossible landing is reported", #G.validate(tiny, config, 1) > 0)

-- Display lookup uses half-open frames: the far edges belong to the neighbor
local pairOfTwo = { r("a", 0, 0, 1000, 800), r("b", 1000, 0, 1000, 800) }
T.check("left edge belongs to the display", G.screenAt(pairOfTwo, 0, 0) == pairOfTwo[1])
T.check("shared edge belongs to the right display", G.screenAt(pairOfTwo, 1000, 400) == pairOfTwo[2])
T.check("just before the shared edge", G.screenAt(pairOfTwo, 999.9, 400) == pairOfTwo[1])
T.check("bottom edge is outside", G.screenAt(pairOfTwo, 500, 800) == nil)
T.check("outside every display", G.screenAt(pairOfTwo, -1, 400) == nil)
T.check("no displays", G.screenAt({}, 0, 0) == nil)

-- findJump details
local function findFull(pos, dx, dy)
  return G.findJump(beside, right, pos, dx, dy, config)
end
T.check("no movement never jumps", findFull({ x = 2000, y = 0 }, 0, 0) == nil)
local direction, point, push = findFull({ x = 2591, y = 0 }, 9, -2)
T.check("corner falls back to the other axis when the dominant one is an outer edge",
  direction == "up", direction)
T.check("fallback push uses that axis's delta", push == 2, push)
T.check("fallback lands on the top monitor",
  point and G.screenAt(beside, point.x, point.y) == top)
direction, _, push = findFull({ x = 1512, y = 1500 }, -7, 1)
T.check("push is the delta along the jump axis", direction == "left" and push == 7, push)
T.check("edge tolerance is respected",
  findFull({ x = 1512 + config.EDGE_TOLERANCE + 0.1, y = 1500 }, -5, 0) == nil)
T.check("a native edge never jumps", findFull({ x = 1512, y = 500 }, -5, 0) == nil)

-- Landing respects the entry margin even with a huge perpendicular offset
local far, farTarget = G.target(beside, right, 1e6, "left", config)
T.check("perpendicular position is clamped into the target",
  farTarget == laptop and far.y == laptop.y2 - config.ENTRY_MARGIN, far and far.y)
local wide = G.config({ ENTRY_MARGIN = 10 })
far = G.target(beside, right, 1500, "left", wide)
T.check("a custom entry margin is used", far.x == laptop.x2 - 10 and far.y == laptop.y2 - 10,
  far and (far.x .. "," .. far.y))

-- A straight-ahead display wins over a nearer one off to the side
local center = r("center", 0, 0, 1000, 1000)
local ahead = r("ahead", 1500, 0, 1000, 1000)
local aside = r("aside", 1100, 1200, 300, 300)
local _, chosen = G.target({ center, ahead, aside }, center, 500, "right", config)
T.check("straight ahead beats off to the side", chosen == ahead, chosen and chosen.name)

-- Settings edge cases
local defaults, none = G.config(nil)
T.check("no settings means defaults", #none == 0 and defaults.COOLDOWN == G.DEFAULTS.COOLDOWN)
T.check("defaults are copied, not shared", defaults ~= G.DEFAULTS)
local zeroCooldown, zeroProblems = G.config({ COOLDOWN = 0, ENTRY_MARGIN = 0 })
T.check("zero is fine except for MIN_PUSH", #zeroProblems == 0 and zeroCooldown.COOLDOWN == 0)
local _, nanProblems = G.config({ MIN_PUSH = 0 / 0 })
T.check("rejects NaN", #nanProblems == 1)
local infConfig, infProblems = G.config({ MIN_PUSH = math.huge, COOLDOWN = math.huge })
T.check("rejects infinity", #infProblems == 2 and infConfig.MIN_PUSH == G.DEFAULTS.MIN_PUSH)
local _, manyProblems = G.config({ MIN_PUSH = true, NOPE = 1, COOLDOWN = {} })
T.check("every bad setting is reported", #manyProblems == 3, #manyProblems)

-- Validation and report edge cases
T.check("no displays validate without errors", #G.validate({}, config, 8) == 0)
T.check("no displays report without errors", G.report({}, config) == "")
local mirrors = { r("a", 0, 0, 1000, 800), r("b", 0, 0, 1000, 800) }
T.check("mirrored displays are not an overlap", #G.validate(mirrors, config, 8) == 0)
local text = G.report(beside, config)
T.check("report lists native edges", text:find("native", 1, true) ~= nil)
T.check("report lists jumps", text:find("JUMPS to laptop", 1, true) ~= nil)
T.check("report lists edges with no exit", text:find("no exit", 1, true) ~= nil)
