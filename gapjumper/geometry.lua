-- Display geometry for Gap Jumper. Pure Lua with no Hammerspoon dependency, so
-- every layout can be tested without the hardware.
--
-- Frames use Hammerspoon's global coordinates: { name, x, y, x2, y2 }, with the
-- origin at the top left of the primary display and y growing downwards.

local G = {}

G.DEFAULTS = {
  MIN_PUSH = 12,          -- px of accumulated push before jumping
  PUSH_TIMEOUT = 0.35,    -- s without pushing that reset the accumulated push
  COOLDOWN = 0.15,        -- s without jumping after a jump, prevents bouncing
  ENTRY_MARGIN = 2,       -- px inside the target display
  EDGE_TOLERANCE = 1.5,   -- px within which the cursor counts as being on the edge
  SIDE_PENALTY = 300,     -- px of extra cost when the target is not straight ahead
}

G.DIRECTIONS = {
  right = { axis = "x", perp = "y", sign = 1 },
  left  = { axis = "x", perp = "y", sign = -1 },
  down  = { axis = "y", perp = "x", sign = 1 },
  up    = { axis = "y", perp = "x", sign = -1 },
}

local SIDES = { "up", "down", "left", "right" }

-- Merges user settings over the defaults. Returns the config and a list of
-- problems; a rejected setting keeps its default.
function G.config(overrides)
  local config, problems = {}, {}
  for key, value in pairs(G.DEFAULTS) do config[key] = value end
  for key, value in pairs(overrides or {}) do
    if G.DEFAULTS[key] == nil then
      table.insert(problems, "unknown setting " .. tostring(key))
    -- `value ~= value` rejects NaN, which slips through every comparison;
    -- math.huge would silently turn jumping (or the cooldown) off for good.
    elseif type(value) ~= "number" or value ~= value or value < 0 or value == math.huge
      or (key == "MIN_PUSH" and value == 0) then
      table.insert(problems, "invalid value for " .. tostring(key) .. ": " .. tostring(value))
    else
      config[key] = value
    end
  end
  return config, problems
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function edge(f, d)
  return d.sign > 0 and f[d.axis .. "2"] or f[d.axis]
end

function G.screenAt(frames, x, y)
  for _, f in ipairs(frames) do
    if x >= f.x and x < f.x2 and y >= f.y and y < f.y2 then return f end
  end
end

-- The display macOS crosses into on its own, if one sits right past the edge.
function G.neighbor(frames, f, perp, direction)
  local d = G.DIRECTIONS[direction]
  local probe = { [d.perp] = perp, [d.axis] = edge(f, d) + (d.sign > 0 and 1 or -1) }
  return G.screenAt(frames, probe.x, probe.y)
end

-- Landing point from the `direction` edge of `f`, and the target display.
-- Only displays whose center lies past that edge count: this keeps a tall
-- display next to the laptop from capturing a push towards the Dock.
function G.target(frames, f, perp, direction, config)
  local d = G.DIRECTIONS[direction]
  local axis2, perp2 = d.axis .. "2", d.perp .. "2"
  local limit = edge(f, d)
  local best, bestCost

  for _, t in ipairs(frames) do
    local center = (t[d.axis] + t[axis2]) / 2
    if t ~= f and (center - limit) * d.sign > 0 then
      local gap = d.sign > 0 and t[d.axis] - limit or limit - t[axis2]
      local side = math.max(t[d.perp] - perp, perp - t[perp2], 0)
      local cost = math.max(gap, 0) + side + (side > 0 and config.SIDE_PENALTY or 0)
      if not bestCost or cost < bestCost then
        best, bestCost = t, cost
      end
    end
  end
  if not best then return nil end

  local m = config.ENTRY_MARGIN
  local entry = d.sign > 0 and math.max(limit, best[d.axis]) + m
    or math.min(limit, best[axis2]) - m
  return {
    [d.axis] = clamp(entry, best[d.axis] + m, best[axis2] - m),
    [d.perp] = clamp(perp, best[d.perp] + m, best[perp2] - m),
  }, best
end

-- Returns the direction, landing point and event push, if a jump is possible.
-- Tries the dominant axis first so corners behave well.
function G.findJump(frames, f, pos, dx, dy, config)
  local h = dx > 0 and "right" or dx < 0 and "left" or nil
  local v = dy > 0 and "down" or dy < 0 and "up" or nil
  local order = math.abs(dx) >= math.abs(dy) and { h, v } or { v, h }

  for i = 1, 2 do
    local direction = order[i]
    local d = G.DIRECTIONS[direction]
    if d and math.abs(edge(f, d) - pos[d.axis]) <= config.EDGE_TOLERANCE
      and not G.neighbor(frames, f, pos[d.perp], direction) then
      local point = G.target(frames, f, pos[d.perp], direction, config)
      if point then
        return direction, point, d.axis == "x" and math.abs(dx) or math.abs(dy)
      end
    end
  end
end

local function behavior(frames, f, perp, direction, config)
  local neighbor = G.neighbor(frames, f, perp, direction)
  if neighbor then return "native", neighbor end
  local _, target = G.target(frames, f, perp, direction, config)
  if target then return "jump", target end
  return "none"
end

-- Walks every display edge and groups it into stretches with the same behavior.
function G.map(frames, config, step)
  step = step or 1
  local stretches = {}
  for _, f in ipairs(frames) do
    for _, direction in ipairs(SIDES) do
      local d = G.DIRECTIONS[direction]
      local first, last = f[d.perp], f[d.perp .. "2"]
      local from = first
      local action, target = behavior(frames, f, first, direction, config)

      local function flush(to)
        table.insert(stretches, {
          screen = f, direction = direction, axis = d.perp,
          from = from, to = to, action = action, target = target,
        })
      end

      local p = first + step
      while p < last do
        local nextAction, nextTarget = behavior(frames, f, p, direction, config)
        if nextAction ~= action or nextTarget ~= target then
          flush(p)
          from, action, target = p, nextAction, nextTarget
        end
        p = p + step
      end
      flush(last)
    end
  end
  return stretches
end

local function sameFrame(a, b)
  return a.x == b.x and a.y == b.y and a.x2 == b.x2 and a.y2 == b.y2
end

local function overlaps(a, b)
  return a.x < b.x2 and b.x < a.x2 and a.y < b.y2 and b.y < a.y2
end

-- Mirrored displays report the same frame and behave as a single one.
local function unique(frames)
  local result = {}
  for _, f in ipairs(frames) do
    local seen = false
    for _, other in ipairs(result) do seen = seen or sameFrame(f, other) end
    if not seen then table.insert(result, f) end
  end
  return result
end

-- Checks that a layout behaves: every jump lands on its target and every
-- display can be reached from the others. Returns a list of problems.
function G.validate(frames, config, step)
  local problems = {}
  local screens = unique(frames)
  -- macOS can briefly report no displays while they reconfigure or sleep.
  if #screens == 0 then return problems end

  for i, a in ipairs(screens) do
    for j = i + 1, #screens do
      if overlaps(a, screens[j]) then
        table.insert(problems, a.name .. " overlaps " .. screens[j].name)
      end
    end
  end

  local links = {}
  for _, s in ipairs(G.map(screens, config, step)) do
    if s.target then
      links[s.screen] = links[s.screen] or {}
      links[s.screen][s.target] = true
    end
    if s.action == "jump" then
      for _, p in ipairs({ s.from, (s.from + s.to) / 2 }) do
        local point, t = G.target(screens, s.screen, p, s.direction, config)
        if not t or G.screenAt(screens, point.x, point.y) ~= t then
          table.insert(problems, string.format("%s %s at %g does not land on its target",
            s.screen.name, s.direction, p))
        end
      end
    end
  end

  local reached, pending, count = { [screens[1]] = true }, { screens[1] }, 1
  while #pending > 0 do
    local current = table.remove(pending)
    for t in pairs(links[current] or {}) do
      if not reached[t] then
        reached[t] = true
        count = count + 1
        table.insert(pending, t)
      end
    end
  end
  if count < #screens then
    table.insert(problems, string.format("only %d of %d displays can be reached", count, #screens))
  end

  return problems
end

function G.report(frames, config)
  local lines = {}
  local function label(f) return string.format("%s (x=%g)", f.name, f.x) end
  local current
  for _, s in ipairs(G.map(frames, config)) do
    if s.screen ~= current then
      current = s.screen
      table.insert(lines, string.format("%s  x=%g..%g  y=%g..%g",
        current.name, current.x, current.x2, current.y, current.y2))
    end
    local what = s.action == "native" and "native"
      or s.action == "jump" and "JUMPS to " .. label(s.target)
      or "no exit"
    table.insert(lines, string.format("  %-5s %s=%g..%g  %s", s.direction, s.axis, s.from, s.to, what))
  end
  return table.concat(lines, "\n")
end

return G
