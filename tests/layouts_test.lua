-- Common Mac and monitor combinations. Sizes are the points macOS reports.

local G = require("gapjumper.geometry")
local config = G.config()
local r = T.frame

local AIR_13 = { 1470, 956 }
local PRO_14 = { 1512, 982 }
local PRO_16 = { 1728, 1117 }
local FHD = { 1920, 1080 }
local QHD = { 2560, 1440 }
local UHD_SCALED = { 3008, 1692 }
local ULTRAWIDE = { 3440, 1440 }
local IPAD = { 1366, 1024 }

local function at(name, size, x, y) return r(name, x, y, size[1], size[2]) end

local LAYOUTS = {
  ["single laptop"] = { at("laptop", PRO_14, 0, 0) },
  ["desktop Mac, single monitor"] = { at("monitor", QHD, 0, 0) },

  ["Air 13 below centered FHD"] = {
    at("laptop", AIR_13, 0, 0), at("monitor", FHD, -225, -1080),
  },
  ["Pro 14 below centered QHD"] = {
    at("laptop", PRO_14, 0, 0), at("monitor", QHD, -524, -1440),
  },
  ["Pro 16 below ultrawide"] = {
    at("laptop", PRO_16, 0, 0), at("monitor", ULTRAWIDE, -856, -1440),
  },
  ["laptop right of monitor, bottom aligned"] = {
    at("laptop", PRO_14, 0, 0), at("monitor", QHD, -2560, -458),
  },
  ["laptop left of monitor, top aligned"] = {
    at("laptop", AIR_13, 0, 0), at("monitor", UHD_SCALED, 1470, 0),
  },

  ["desktop Mac, different sizes top aligned"] = {
    at("main", QHD, 0, 0), at("side", FHD, 2560, 0),
  },
  ["desktop Mac, different sizes bottom aligned"] = {
    at("main", QHD, 0, 0), at("side", FHD, 2560, 360),
  },
  ["desktop Mac, three in a row of mixed sizes"] = {
    at("main", QHD, 0, 0), at("left", FHD, -1920, 180), at("right", UHD_SCALED, 2560, -126),
  },

  ["four displays, portrait sides beside the laptop"] = {
    at("laptop", PRO_14, 0, 0), at("top", FHD, -213, -1080),
    r("left", -1080, 0, 1080, 1920), r("right", 1512, 0, 1080, 1920),
  },
  ["four displays, portrait sides raised"] = {
    at("laptop", PRO_14, 0, 0), at("top", FHD, -182, -1080),
    r("left", -1262, -1080, 1080, 1920), r("right", 1738, -1046, 1080, 1920),
  },

  ["three stacked"] = {
    at("laptop", PRO_14, 0, 0), at("middle", FHD, -204, -1080), at("high", QHD, -524, -2520),
  },
  ["L shape"] = {
    at("main", QHD, 0, 0), at("right", FHD, 2560, 0), at("below", FHD, 0, 1440),
  },
  ["touching only by a corner"] = {
    at("laptop", PRO_14, 0, 0), at("monitor", FHD, 1512, -1080),
  },
  ["primary display in the middle"] = {
    at("primary", FHD, 0, 0), at("west", FHD, -1920, 0), at("east", FHD, 1920, 0),
    at("north", FHD, 0, -1080),
  },
  ["iPad as a display"] = {
    at("laptop", PRO_14, 0, 0), at("ipad", IPAD, 1512, 0),
  },
  ["scaled display with fractional size"] = {
    r("laptop", 0, 0, 1707.5, 960.5), at("monitor", FHD, 1707.5, 0),
  },
  ["mirrored displays"] = {
    at("laptop", PRO_14, 0, 0), at("mirror", PRO_14, 0, 0), at("monitor", QHD, 1512, 0),
  },
}

for name, frames in pairs(LAYOUTS) do
  local problems = G.validate(frames, config, 4)
  T.check("layout: " .. name, #problems == 0, table.concat(problems, "; "))
  T.check("report: " .. name, #G.report(frames, config) > 0)
end

-- What each kind of Mac should do on the edges people use most
local laptop = at("laptop", AIR_13, 0, 0)
local monitor = at("monitor", UHD_SCALED, 1470, 0)
local _, t = G.target({ laptop, monitor }, monitor, 2000, "down", config)
T.check("no display below means no jump", t == nil)
local nextDoor = { laptop, monitor }
T.check("short display's side is native at the top",
  G.neighbor(nextDoor, monitor, 500, "left") == laptop)
_, t = G.target(nextDoor, monitor, 1500, "left", config)
T.check("taller display jumps to the short one below its edge", t == laptop)

local singleProblems = G.validate({ at("only", FHD, 0, 0) }, config, 4)
T.check("a single display has nowhere to jump", #singleProblems == 0)
for _, stretch in ipairs(G.map({ at("only", FHD, 0, 0) }, config, 8)) do
  T.check("a single display never jumps", stretch.action == "none")
end
