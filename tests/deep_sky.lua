-- Focused ROM-free contract for Scott's fixed deep-sky photography.
-- Run from the Scott's Tweaks mod root:
--   lua tests/deep_sky.lua .
--   luajit tests/deep_sky.lua .

local argv = rawget(_G, "arg") or {}
local root = argv[1] or "."

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end
local function eq(actual, expected, message)
  check(actual == expected,
        message .. (" (got %s, wanted %s)"):format(
          tostring(actual), tostring(expected)))
end
local function near(actual, expected, epsilon, message)
  check(math.abs(actual - expected) <= epsilon,
        message .. (" (got %.10f, wanted %.10f)"):format(
          actual, expected))
end

local Astronomy = assert(loadfile(root .. "/lib/Astronomy.lua"))({})

local phase = "day"
local clockMode = "hour"
local celestialOverride = nil
local lunar = { source = "game", illuminated = 0, milkyWay = 1 }
local DayNight = {
  CYCLE = 1200,
  T = { dawn = 0, day = 300, dusk = 600, night = 900 },
  SUN_COLORS = {
    { 248, 240, 200 }, { 248, 208, 96 },
    { 248, 144, 80 }, { 216, 96, 64 },
  },
  MOON_COLORS = {
    { 240, 244, 248 }, { 224, 232, 240 },
    { 168, 184, 208 }, { 120, 136, 168 },
  },
}
DayNight.setting = { get = function() return clockMode end }
function DayNight.time() return DayNight.T.night end
function DayNight.mix()
  if phase == "day" then return { day = 1 } end
  return { night = 1 }
end
function DayNight.astronomy() return lunar end
function DayNight.celestialDay(t)
  if celestialOverride ~= nil then return celestialOverride end
  return (tonumber(t) or DayNight.T.night) / DayNight.CYCLE
end

local loads, operations = {}, {}
local currentColor = { 1, 1, 1, 1 }
local g = {}

function g.newImage(path)
  local image = {
    path = path,
    width = 192,
    height = 128,
    released = false,
  }
  function image:setFilter(min, mag) self.filter = { min, mag } end
  function image:setWrap(horizontal, vertical)
    self.wrap = { horizontal, vertical }
  end
  function image:getDimensions() return self.width, self.height end
  function image:release() self.released = true end
  loads[#loads + 1] = image
  return image
end
function g.getShader() return nil end
function g.setShader() end
function g.getBlendMode() return "alpha", "alphamultiply" end
function g.setBlendMode() end
function g.getDepthMode() return "lequal", true end
function g.setDepthMode() end
function g.getScissor() return nil end
function g.setScissor() end
function g.setColor(r, green, b, a)
  currentColor = { r, green, b, a }
end
function g.rectangle(mode, x, y, width, height)
  operations[#operations + 1] = {
    kind = "rectangle", mode = mode, x = x, y = y,
    width = width, height = height,
    color = { currentColor[1], currentColor[2],
              currentColor[3], currentColor[4] },
  }
end
function g.draw(image, x, y, rotation, sx, sy, ox, oy)
  operations[#operations + 1] = {
    kind = "deep-sky", image = image, x = x, y = y,
    rotation = rotation, sx = sx, sy = sy, ox = ox, oy = oy,
    color = { currentColor[1], currentColor[2],
              currentColor[3], currentColor[4] },
  }
end

local oldLove = rawget(_G, "love")
local oldConfig = rawget(_G, "__ds_ceiling_config")
local oldPaletteLoaded = package.loaded["src.render.PaletteFX"]
local oldPalettePreload = package.preload["src.render.PaletteFX"]

_G.love = { graphics = g }
package.loaded["src.render.PaletteFX"] = nil
package.preload["src.render.PaletteFX"] = function()
  return { effectiveColors = function() return nil end }
end

local V = {
  path = "C:/staged/scotts-tweaks",
  require = function(name)
    if name == "DayNight" then return DayNight end
    if name == "Astronomy" then return Astronomy end
    error("unexpected Sky dependency: " .. tostring(name))
  end,
}
local Sky = assert(loadfile(root .. "/lib/Sky.lua"))(V)

eq(#Sky.DEEP_SKY_CATALOG, 1,
  "catalog starts with Scott's one supplied deep-sky photograph")
eq(Sky.DEEP_SKY_CATALOG[1].id, "m42_orion_nebula",
  "catalog identifies Orion's M42")
eq(Sky.DEEP_SKY_CATALOG[1].path,
  "assets/sky/astrophotography/m42_orion_nebula.png",
  "catalog uses the packaged astrophotography path")

-- REAL CLOCK consumes one continuous Unix-day coordinate rather than mixing a
-- UTC date edge with the local day/night dial. One second therefore produces
-- one tiny forward turn, with no second daily reset. Fixed NIGHT keeps the
-- useful midnight presentation on the same reference date.
clockMode = "sync"
lunar = { source = "sync", illuminated = 0, milkyWay = 1 }
celestialOverride = Sky.CELESTIAL_SYNC_REFERENCE_DAY
local syncStart = Sky.siderealTurn(DayNight.T.night, lunar)
near(syncStart, Sky.DEEP_SKY_CATALOG[1].raHours / 24, 1e-12,
  "reference real-clock midnight places M42 on the meridian")
celestialOverride = celestialOverride + 1 / 86400
local syncNext = Sky.siderealTurn(DayNight.T.night, lunar)
near(Astronomy.wrap01(syncNext - syncStart),
  Astronomy.SIDEREAL_TURNS_PER_DAY / 86400, 1e-12,
  "real-clock sky advances smoothly by one sidereal second")
clockMode = "night"
celestialOverride = Sky.CELESTIAL_REFERENCE_UNIX_DAY + 0.5
near(Sky.siderealTurn(DayNight.T.night, lunar),
  Sky.DEEP_SKY_CATALOG[1].raHours / 24, 1e-12,
  "fixed NIGHT keeps the calibrated midnight sky")
clockMode, celestialOverride = "hour", nil
lunar = { source = "game", illuminated = 0, milkyWay = 1 }

-- Pure descriptor gates must not even ask the graphics layer for the image.
phase = "day"
_G.__ds_ceiling_config = function() return { stars = true } end
eq(Sky.deepSky(DayNight.T.day), nil,
  "daytime publishes no deep-sky descriptor")
eq(#loads, 0, "daytime performs no asset load")

phase = "night"
_G.__ds_ceiling_config = function() return { stars = false } end
eq(Sky.deepSky(DayNight.T.night), nil,
  "disabled NIGHT SKY publishes no deep-sky descriptor")
eq(#loads, 0, "disabled NIGHT SKY performs no asset load")

-- Moonlight washes the photograph out without ever exceeding its deliberately
-- faint catalog ceiling.
_G.__ds_ceiling_config = function() return { stars = true } end
lunar = { source = "game", illuminated = 0, milkyWay = 1 }
local newMoonObjects = Sky.deepSky(DayNight.T.night)
check(newMoonObjects and newMoonObjects[1],
  "new-moon night publishes Orion's descriptor")
local newMoonAlpha = newMoonObjects and newMoonObjects[1].alpha or 0
check(newMoonAlpha > 0 and newMoonAlpha <= 0.14,
  "new-moon Orion stays visible and at or below fourteen percent")
near(newMoonAlpha, Sky.DEEP_SKY_CATALOG[1].maxAlpha, 1e-12,
  "new moon reaches only the catalog's faint ceiling")

lunar = { source = "game", illuminated = 1, milkyWay = 0.16 }
local fullMoonObjects = Sky.deepSky(DayNight.T.night)
check(fullMoonObjects and fullMoonObjects[1],
  "full-moon night retains a faint Orion descriptor")
local fullMoonAlpha = fullMoonObjects and fullMoonObjects[1].alpha or 0
check(newMoonAlpha > fullMoonAlpha and fullMoonAlpha > 0,
  "Orion is dimmer under a full Moon but does not disappear")
check(fullMoonAlpha <= 0.14,
  "full-moon Orion remains beneath the same alpha ceiling")
eq(#loads, 0, "descriptor calculation remains free of asset I/O")

-- At game-day zero the release calibration places M42 on the meridian at the
-- NIGHT pin. Three game-hours either way retain it above the horizon and put
-- it on opposite sides of transit.
lunar = { source = "game", illuminated = 0, milkyWay = 1 }
local before = Sky.deepSky(750)
local beforeX = before and before[1] and before[1].direction.dx
local beforeY = before and before[1] and before[1].direction.dy
local transit = Sky.deepSky(DayNight.T.night)
local transitX = transit and transit[1] and transit[1].direction.dx
local transitY = transit and transit[1] and transit[1].direction.dy
local after = Sky.deepSky(1050)
local afterX = after and after[1] and after[1].direction.dx
local afterY = after and after[1] and after[1].direction.dy
check(beforeX and beforeX > 0 and beforeY > 0,
  "Orion is above the eastern sky before the NIGHT transit")
check(transitX and math.abs(transitX) < 0.000001 and transitY > 0.8,
  "Orion transits high on the meridian at reference-day NIGHT")
check(afterX and afterX < 0 and afterY > 0,
  "Orion remains above the western sky after the NIGHT transit")

-- Projection happens in Voxel3D; painting receives the already projected
-- descriptor. Keep this object separate from the shared catalog row so later
-- deepSky calls cannot mutate the fixture under the test.
local paintedObject = {
  id = Sky.DEEP_SKY_CATALOG[1].id,
  path = Sky.DEEP_SKY_CATALOG[1].path,
  widthFraction = Sky.DEEP_SKY_CATALOG[1].widthFraction,
  maxAlpha = Sky.DEEP_SKY_CATALOG[1].maxAlpha,
  alpha = newMoonAlpha,
  x = 120,
  y = 56,
  upX = 120,
  upY = 48,
}
local paintedSky = {
  0.2, 0.3, 0.5, 1,
  bands = {
    { 0.04, 0.05, 0.12 },
    { 0.12, 0.16, 0.30 },
  },
}
local moon = {
  x = 250,
  y = 48,
  moon = true,
  phase = 0.5,
  illuminated = 1,
}

operations = {}
check(Sky.paint(320, 180, paintedSky, 150, 4, moon, { paintedObject }),
  "Sky.paint accepts projected Orion and the pixel Moon together")
eq(#loads, 1, "first visible paint lazily loads M42 exactly once")
eq(loads[1].path,
  "C:/staged/scotts-tweaks/assets/sky/astrophotography/"
    .. "m42_orion_nebula.png",
  "lazy loader resolves M42 through V.path")
eq(loads[1].filter[1], "nearest", "M42 minification stays nearest-pixel")
eq(loads[1].filter[2], "nearest", "M42 magnification stays nearest-pixel")
eq(loads[1].wrap[1], "clamp", "M42 horizontal edge clamps")
eq(loads[1].wrap[2], "clamp", "M42 vertical edge clamps")

local deepAt, moonRectangleAfter
for i, operation in ipairs(operations) do
  if operation.kind == "deep-sky" then deepAt = deepAt or i end
  if deepAt and i > deepAt and operation.kind == "rectangle"
      and operation.width == 4 and operation.height == 4 then
    moonRectangleAfter = i
    break
  end
end
check(deepAt ~= nil, "Sky.paint issues one deep-sky image draw")
check(moonRectangleAfter and moonRectangleAfter > deepAt,
  "Orion paints after sky bands and before Moon cell rectangles")
check(operations[deepAt].color[4] <= 0.14,
  "paint path also clamps M42 to the faint alpha ceiling")

operations = {}
check(Sky.paint(320, 180, paintedSky, 150, 4, moon, { paintedObject }),
  "a second frame paints the cached M42 image")
eq(#loads, 1, "stable frames never reload the deep-sky texture")

Sky.invalidate()
check(loads[1].released, "invalidation releases the cached M42 texture")
operations = {}
check(Sky.paint(320, 180, paintedSky, 150, 4, moon, { paintedObject }),
  "deep sky paints again after invalidation")
eq(#loads, 2, "post-invalidation paint reloads M42 exactly once")
check(loads[2] ~= loads[1] and not loads[2].released,
  "reload creates a fresh live texture handle")
eq(loads[2].filter[1], "nearest",
  "reloaded M42 restores nearest filtering")
eq(loads[2].wrap[1], "clamp",
  "reloaded M42 restores clamped wrapping")

Sky.invalidate()
check(loads[2].released, "final invalidation releases the reloaded texture")

local skyLayerFile = assert(io.open(root .. "/lib/SkyLayer.lua", "rb"))
local skyLayerSource = skyLayerFile:read("*a")
skyLayerFile:close()
check(skyLayerSource:find("CelestialSky.siderealTurn", 1, true) ~= nil,
  "procedural stars read the same sidereal turn as catalog photography")
check(skyLayerSource:find("Mat4.rotateY(skyAngle)", 1, true) ~= nil,
  "star and Milky Way planes rotate on that shared sky turn")

_G.love = oldLove
_G.__ds_ceiling_config = oldConfig
package.loaded["src.render.PaletteFX"] = oldPaletteLoaded
package.preload["src.render.PaletteFX"] = oldPalettePreload

if failures > 0 then error(tostring(failures) .. " deep-sky checks failed") end
print(("Deep sky: %d checks passed"):format(checks))
