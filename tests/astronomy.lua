-- Focused moon/sun tests. Run from the Scott's Tweaks mod root with Lua 5.1.

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end
local function near(actual, expected, epsilon, message)
  check(math.abs(actual - expected) <= epsilon,
        message .. (" (got %.8f, wanted %.8f)"):format(actual, expected))
end

local Astronomy = assert(loadfile("lib/Astronomy.lua"))({})
near(Astronomy.realPhase(Astronomy.NEW_MOON_EPOCH), 0, 1e-9,
     "known epoch is a new moon")
near(Astronomy.realPhase(Astronomy.NEW_MOON_EPOCH
     + Astronomy.SYNODIC_MONTH_DAYS * 86400 / 2), 0.5, 1e-9,
     "half a synodic month is full moon")
near(Astronomy.gamePhase(2), 0.25, 1e-9,
     "default accelerated cycle reaches first quarter on day two")
near(Astronomy.gamePhase(4), 0.5, 1e-9,
     "default accelerated cycle reaches full moon on day four")
near(Astronomy.gamePhase(8), 0, 1e-9,
     "default accelerated phase repeats after eight game days")
near(Astronomy.illumination(0), 0, 1e-9, "new moon is unlit")
near(Astronomy.illumination(0.5), 1, 1e-9, "full moon is fully lit")
check(Astronomy.snapshot("game", 0).milkyWay
      > Astronomy.snapshot("game", 4).milkyWay,
      "Milky Way is strongest near new moon")
check(Astronomy.surfaceLight(0.7, 0, 0.25) > 0
      and Astronomy.surfaceLight(-0.7, 0, 0.25) < 0,
      "waxing quarter lights the right side of the pixel Moon")

local option = "hour"
local saved = {}
local settingStub = {}
function settingStub.new()
  return {
    get = function() return option end,
    setIndex = function() end,
  }
end
local dayV = {
  mod = { save = {
    get = function(_, key) return saved[key] end,
    set = function(_, key, value) saved[key] = value end,
  } },
}
dayV.require = function(name)
  if name == "ModSetting" then return settingStub end
  if name == "Astronomy" then return Astronomy end
  error("unexpected dependency: " .. tostring(name))
end
package.loaded["src.render.PaletteFX"] = nil
package.preload["src.render.PaletteFX"] = function()
  return { effectiveColors = function() return nil end }
end

local DayNight = assert(loadfile("lib/DayNight.lua"))(dayV)
DayNight.clock, DayNight.astronomyDay = 0, 0
local newMoon = DayNight.astronomy()
near(newMoon.phase, 0, 1e-9, "accelerated sky begins at new moon")
check(DayNight.astronomy() == newMoon,
      "same-frame astronomy reads reuse one snapshot on handhelds")
DayNight.update(DayNight.PERIOD.hour * 4)
local fullMoon = DayNight.astronomy()
near(fullMoon.phase, 0.5, 1e-9,
     "four accelerated game days reach full moon")
check(DayNight.astronomyDay == 4,
      "large update counts every completed accelerated day")
DayNight.store()
DayNight.clock, DayNight.astronomyDay = 123, 0
DayNight.restore()
check(DayNight.astronomyDay == 4,
      "accelerated lunar day persists with the save slot")
option = "sync"
local timestampReads = 0
DayNight.timestamp = function()
  timestampReads = timestampReads + 1
  return Astronomy.NEW_MOON_EPOCH
end
DayNight.resetAstronomyCache()
local syncedMoon = DayNight.astronomy()
near(syncedMoon.phase, 0, 1e-9,
     "real-clock mode uses the real lunar epoch rather than game days")
check(timestampReads == 1,
      "real-clock astronomy reads the device clock once")
for _ = 1, 20 do DayNight.astronomy() end
DayNight.update(59)
DayNight.astronomy()
check(timestampReads == 1,
      "same-minute sky consumers reuse the device timestamp")
DayNight.update(1)
DayNight.astronomy()
check(timestampReads == 2,
      "device timestamp refreshes after one minute")
option = "hour"

DayNight.astronomyDay = 7
DayNight.resetAstronomyCache()
local darkPalette = DayNight.palette(DayNight.T.night)
local darkTint = DayNight.tint(true, DayNight.T.night)
DayNight.astronomyDay = 3
DayNight.resetAstronomyCache()
local fullPalette = DayNight.palette(DayNight.T.night)
local fullTint = DayNight.tint(true, DayNight.T.night)
check(fullPalette[1][1] + fullPalette[1][2] + fullPalette[1][3]
      > darkPalette[1][1] + darkPalette[1][2] + darkPalette[1][3],
      "full moon lifts the pixel night-sky palette")
check(fullTint[1] + fullTint[2] + fullTint[3]
      > darkTint[1] + darkTint[2] + darkTint[3],
      "full moon contributes more outdoor light than new moon")

-- The displayed arc must now visibly climb rather than spend all day on the
-- horizon. Noon is over twenty degrees high after the presentation factor.
local noon = DayNight.body(DayNight.T.day)
check(noon.dy > math.sin(math.rad(20)),
      "displayed noon sun follows an elevated arc")

-- Load the cell-art sky headlessly and verify its phase mask. No graphics
-- methods are called until paint(), so the pure mask remains testable here.
local skyV = { require = function(name)
  if name == "DayNight" then return DayNight end
  if name == "Astronomy" then return Astronomy end
  error("unexpected sky dependency: " .. tostring(name))
end }
local Sky = assert(loadfile("lib/Sky.lua"))(skyV)
local full = { moon = true, phase = 0.5, illuminated = 1 }
local new = { moon = true, phase = 0, illuminated = 0 }
local quarter = { moon = true, phase = 0.25, illuminated = 0.5 }
check(Sky._moonCellVisible(full, -3, 0, 4)
      and Sky._moonCellVisible(full, 3, 0, 4),
      "full pixel Moon lights both sides")
check(not Sky._moonCellVisible(new, 0, 0, 4),
      "new pixel Moon leaves the dark sky unobstructed")
check(Sky._moonCellVisible(quarter, 3, 0, 4)
      and not Sky._moonCellVisible(quarter, -3, 0, 4),
      "quarter pixel Moon paints the correct half")

package.loaded["src.render.PaletteFX"] = nil
package.preload["src.render.PaletteFX"] = nil

if failures > 0 then error(tostring(failures) .. " astronomy checks failed") end
print(("Astronomy: %d checks passed"):format(checks))
