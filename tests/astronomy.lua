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
near(Astronomy.siderealTurns(0), 0, 1e-12,
     "sidereal seam has a neutral day-zero reference")
near(Astronomy.siderealTurns(1), 0.002737909, 1e-12,
     "one solar day advances the stars by the sidereal excess")
near(Astronomy.siderealTurns(0, 0.25), 0.25, 1e-12,
     "east longitude advances local sidereal rotation")
near(Astronomy.siderealTurns(-1), 1 - 0.002737909, 1e-12,
     "sidereal rotation wraps negative day counts")

local function directionLength(d)
  return math.sqrt(d.dx * d.dx + d.dy * d.dy + d.dz * d.dz)
end
local overhead = Astronomy.equatorialDirection(0, 0, 0, 0)
near(overhead.dx, 0, 1e-12, "equatorial transit has no east component")
near(overhead.dy, 1, 1e-12, "equatorial transit is overhead at equator")
near(overhead.dz, 0, 1e-12, "equatorial transit has no south component")
near(directionLength(overhead), 1, 1e-12,
     "equatorial direction is normalized")
local risingEast = Astronomy.equatorialDirection(6, 0, 0, 0)
near(risingEast.dx, 1, 1e-12, "object six RA-hours ahead rises east")
near(risingEast.dy, 0, 1e-12, "rising equatorial object is on horizon")
local settingWest = Astronomy.equatorialDirection(18, 0, 0, 0)
near(settingWest.dx, -1, 1e-12, "object six RA-hours behind sets west")
local northPole = Astronomy.equatorialDirection(0, 90, 0, 45)
near(northPole.dy, math.sqrt(0.5), 1e-12,
     "north celestial pole altitude equals northern latitude")
near(northPole.dz, -math.sqrt(0.5), 1e-12,
     "north celestial pole points along world north")
near(directionLength(northPole), 1, 1e-12,
     "polar equatorial direction is normalized")

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
near(Astronomy.moonrise(0), 0, 1e-9,
     "new moon rises near sunrise")
near(Astronomy.moonrise(0.25), 0.25, 1e-9,
     "first-quarter moon rises near noon")
near(Astronomy.moonrise(0.5), 0.5, 1e-9,
     "full moon rises near sunset")
near(Astronomy.moonrise(0.75), 0.75, 1e-9,
     "last-quarter moon rises near midnight")
near(Astronomy.moonriseDelay(Astronomy.SYNODIC_MONTH_DAYS) * 24 * 60,
     48.763, 0.002,
     "real moonrise drifts roughly 49 minutes later each day")
near(Astronomy.moonriseDelay(Astronomy.DEFAULT_GAME_CYCLE_DAYS) * 24,
     3, 1e-9,
     "eight-day game Moon drifts three game-hours later each day")
near(Astronomy.snapshot("sync", Astronomy.NEW_MOON_EPOCH + 86400).moonrise,
     Astronomy.moonriseDelay(Astronomy.SYNODIC_MONTH_DAYS), 1e-9,
     "real-clock snapshot carries one day's moonrise delay")
near(Astronomy.snapshot("game", 1).moonrise, 0.125, 1e-9,
     "accelerated snapshot carries one game's moonrise delay")
near(Astronomy.moonDayPosition(0.5, 0.5), 0, 1e-9,
     "full Moon starts its daily path at sunset")
near(Astronomy.moonDayPosition(0.75, 0.5), 0.25, 1e-9,
     "full Moon transits around midnight")
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
near(DayNight.celestialDay(), 0, 1e-12,
     "accelerated celestial day begins with the saved game day")
near(DayNight.celestialDay(DayNight.T.day), 0.25, 1e-12,
     "accelerated celestial day includes an explicit dial fraction")
near(DayNight.celestialDay(DayNight.CYCLE * 2), 2, 1e-12,
     "explicit celestial dial values retain complete day turns")
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
near(DayNight.celestialDay(), 4, 1e-12,
     "accelerated celestial day advances across complete game days")
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
near(DayNight.celestialDay(), Astronomy.NEW_MOON_EPOCH / 86400, 1e-12,
     "real-clock celestial day is the cached Unix-day value")
check(timestampReads == 1,
      "celestial coordinates reuse the lunar timestamp cache")
option = "night"
near(DayNight.celestialDay(), Astronomy.NEW_MOON_EPOCH / 86400, 1e-12,
     "pinned views retain the current real celestial day")
check(timestampReads == 1,
      "pinned celestial coordinates reuse the same timestamp cache")
option = "sync"
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

-- The daily Moon arc follows the same simple astronomical rise schedule as
-- the phase snapshot. These calls provide the exact phase so the geometry
-- remains independent of the running clock's deliberately continuous phase.
local function moonElevation(t, phase)
  local _, elevation, isMoon = DayNight.moonAt(t, { phase = phase })
  check(isMoon, "lunar arc identifies itself as the Moon")
  return elevation
end
near(moonElevation(DayNight.T.dawn, 0), 0, 1e-9,
     "new Moon meets the horizon at sunrise")
near(moonElevation(DayNight.T.day, 0.25), 0, 1e-9,
     "first-quarter Moon meets the horizon at noon")
near(moonElevation(DayNight.T.dusk, 0.5), 0, 1e-9,
     "full Moon meets the horizon at sunset")
near(moonElevation(DayNight.T.night, 0.75), 0, 1e-9,
     "last-quarter Moon meets the horizon at midnight")
check(moonElevation(DayNight.T.night, 0.5) > 39.9,
      "full Moon reaches the top of its arc around midnight")
check(moonElevation(DayNight.T.night, 0.25) < 0.01,
      "first-quarter Moon has set around midnight")

-- Exercise the live bodyAt -> astronomy cache -> orbit path as well: at the
-- same midnight, tomorrow's later-rising Moon must be lower in the east.
DayNight.astronomyDay = 3.25
DayNight.resetAstronomyCache()
local _, midnightFullElevation, midnightIsMoon =
  DayNight.bodyAt(DayNight.T.night)
DayNight.astronomyDay = 4.25
DayNight.resetAstronomyCache()
local _, nextMidnightElevation, nextMidnightIsMoon =
  DayNight.bodyAt(DayNight.T.night)
check(midnightIsMoon and nextMidnightIsMoon,
      "night body remains the Moon while its rise time drifts")
check(midnightFullElevation > nextMidnightElevation
      and nextMidnightElevation > 0,
      "next day's later-rising Moon is lower at the same game time")

-- The primary body changes from sun to Moon at dusk and back at dawn. A
-- quarter Moon is already high at either seam, so its presentation and shadow
-- weights must ease instead of appearing for one frame at full strength.
near(DayNight.moonHandoff(DayNight.T.dusk), 0, 1e-12,
     "Moon presentation is absent at the dusk handoff")
near(DayNight.moonHandoff(DayNight.T.dusk + DayNight.BLEND / 2),
     0.5, 1e-12, "Moon presentation eases smoothly after dusk")
near(DayNight.moonHandoff(DayNight.T.dusk + DayNight.BLEND),
     1, 1e-12, "Moon presentation completes its dusk fade")
near(DayNight.moonHandoff(DayNight.T.night), 1, 1e-12,
     "Moon presentation stays complete through the night")
near(DayNight.moonHandoff(DayNight.CYCLE - DayNight.BLEND / 2),
     0.5, 1e-12, "Moon presentation eases smoothly before dawn")
near(DayNight.moonHandoff(DayNight.CYCLE), 0, 1e-12,
     "Moon presentation is absent at the dawn handoff")

local seamEpsilon = 0.001
check(math.abs(DayNight.moonHandoff(DayNight.T.dusk - seamEpsilon)
               - DayNight.moonHandoff(DayNight.T.dusk + seamEpsilon))
      < 1e-8, "dusk Moon handoff is continuous")
check(math.abs(DayNight.moonHandoff(DayNight.CYCLE - seamEpsilon)
               - DayNight.moonHandoff(DayNight.CYCLE + seamEpsilon))
      < 1e-8, "dawn Moon handoff is continuous")

DayNight.astronomyDay = 1.5 -- first quarter is high immediately after dusk
DayNight.resetAstronomyCache()
local duskMoon = DayNight.body(DayNight.T.dusk + 1)
check(duskMoon and duskMoon.moon and duskMoon.dy > 0.3,
      "elevated first-quarter Moon exists immediately after dusk")
check(duskMoon and duskMoon.alpha > 0 and duskMoon.alpha < 0.001,
      "elevated dusk Moon begins nearly transparent")
near(DayNight.strengthAt(DayNight.T.dusk + DayNight.BLEND / 2),
     DayNight.moonHandoff(DayNight.T.dusk + DayNight.BLEND / 2),
     1e-12, "lunar shadow follows the dusk presentation fade")

DayNight.astronomyDay = 5 -- last quarter is high immediately before dawn
DayNight.resetAstronomyCache()
local dawnMoon = DayNight.body(DayNight.CYCLE - 1)
check(dawnMoon and dawnMoon.moon and dawnMoon.dy > 0.3,
      "elevated last-quarter Moon exists immediately before dawn")
check(dawnMoon and dawnMoon.alpha > 0 and dawnMoon.alpha < 0.001,
      "elevated dawn Moon finishes nearly transparent")
near(DayNight.strengthAt(DayNight.CYCLE - DayNight.BLEND / 2),
     DayNight.moonHandoff(DayNight.CYCLE - DayNight.BLEND / 2),
     1e-12, "lunar shadow follows the dawn presentation fade")
local dawnSun = DayNight.body(DayNight.T.dawn)
check(dawnSun and not dawnSun.moon and dawnSun.alpha == 1,
      "sun body retains full presentation alpha")

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
