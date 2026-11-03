-- Random layouts built like macOS builds them: each new display touches an
-- existing one. Set GAPJUMPER_SEED to reproduce a failure.

local G = require("gapjumper.geometry")
local config = G.config()

local SIZES = {
  { 1470, 956 }, { 1512, 982 }, { 1728, 1117 }, { 1280, 800 }, { 1920, 1080 },
  { 1080, 1920 }, { 2560, 1440 }, { 1440, 2560 }, { 3440, 1440 }, { 1366, 1024 },
  { 1707.5, 960.5 },
}

local seed = tonumber(os.getenv("GAPJUMPER_SEED")) or 42
math.randomseed(seed)

local function overlapsAny(frames, c)
  for _, f in ipairs(frames) do
    if c.x < f.x2 and f.x < c.x2 and c.y < f.y2 and f.y < c.y2 then return true end
  end
  return false
end

local function attach(frames, i)
  local size = SIZES[math.random(#SIZES)]
  local w, h = size[1], size[2]
  for _ = 1, 50 do
    local f = frames[math.random(#frames)]
    local x, y
    local side = math.random(4)
    if side <= 2 then
      x = side == 1 and f.x2 or f.x - w
      y = math.floor(f.y - h + math.random() * (f.y2 - f.y + h))
    else
      y = side == 3 and f.y2 or f.y - h
      x = math.floor(f.x - w + math.random() * (f.x2 - f.x + w))
    end
    local c = T.frame("display" .. i, x, y, w, h)
    if not overlapsAny(frames, c) then
      table.insert(frames, c)
      return
    end
  end
end

local function randomLayout()
  local first = SIZES[math.random(#SIZES)]
  local frames = { T.frame("display1", 0, 0, first[1], first[2]) }
  for i = 2, math.random(2, 6) do attach(frames, i) end
  return frames
end

local PUSHES = {
  right = { 5, 0 }, left = { -5, 0 }, down = { 0, 5 }, up = { 0, -5 },
}

for run = 1, 400 do
  local frames = randomLayout()
  local where = string.format("seed %d run %d", seed, run)

  local problems = G.validate(frames, config, 16)
  T.check("valid layout, " .. where, #problems == 0, table.concat(problems, "; "))

  for _, stretch in ipairs(G.map(frames, config, 16)) do
    local f, direction = stretch.screen, stretch.direction
    local d = G.DIRECTIONS[direction]
    local perp = (stretch.from + stretch.to) / 2
    local pos = {
      [d.perp] = perp,
      [d.axis] = d.sign > 0 and f[d.axis .. "2"] - 1 or f[d.axis],
    }
    local push = PUSHES[direction]
    local jumped, point = G.findJump(frames, f, pos, push[1], push[2], config)

    -- Judge this exact point: a stretch can be shorter than the sampling step.
    local _, target = G.target(frames, f, perp, direction, config)
    local blocked = target and not G.neighbor(frames, f, perp, direction)

    if not blocked then
      T.check("no jump where it must not, " .. where, jumped == nil)
    else
      T.check("jumps where it must, " .. where, jumped == direction)
      local landed = G.screenAt(frames, point.x, point.y)
      T.check("jump leaves the display, " .. where, landed ~= f)
      T.check("jump lands on a display, " .. where, landed ~= nil)
      local onEdge = false
      for _, side in pairs(G.DIRECTIONS) do
        local limit = side.sign > 0 and landed[side.axis .. "2"] or landed[side.axis]
        onEdge = onEdge or math.abs(limit - point[side.axis]) <= config.EDGE_TOLERANCE
      end
      T.check("landing is clear of every edge, " .. where, not onEdge)
    end
  end
end

-- Every edge is covered by its stretches, end to end, with no gaps or overlaps,
-- and every point on a jump stretch lands inside its target clear of the edges.
for run = 1, 100 do
  local frames = randomLayout()
  local where = string.format("seed %d map run %d", seed, run)
  local edges = {}
  for _, s in ipairs(G.map(frames, config, 8)) do
    local key = tostring(s.screen) .. s.direction
    local e = edges[key]
    if not e then
      e = { screen = s.screen, direction = s.direction, last = nil, first = s.from }
      edges[key] = e
    end
    T.check("stretches are contiguous, " .. where, e.last == nil or e.last == s.from)
    T.check("stretches are not empty, " .. where, s.to > s.from)
    T.check("native and jump stretches name a target, " .. where,
      (s.action == "none") == (s.target == nil))
    e.last = s.to
    if s.action == "jump" then
      local point, t = G.target(frames, s.screen, s.from, s.direction, config)
      T.check("landing is inside the target, " .. where,
        point.x >= t.x + config.ENTRY_MARGIN and point.x <= t.x2 - config.ENTRY_MARGIN
        and point.y >= t.y + config.ENTRY_MARGIN and point.y <= t.y2 - config.ENTRY_MARGIN)
    end
  end
  local count = 0
  for _, e in pairs(edges) do
    count = count + 1
    local d = G.DIRECTIONS[e.direction]
    T.check("stretches span the whole edge, " .. where,
      e.first == e.screen[d.perp] and e.last == e.screen[d.perp .. "2"])
  end
  T.check("every display has four edges, " .. where, count == #frames * 4)
end
