-- Focused contract test for Flora's offline LOCAL SEASON weather mode.
-- Run from the mod root: luajit tests/seasonal_weather.lua

local checks = 0
local function check(value, label)
  checks = checks + 1
  if not value then error(label, 2) end
end
local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(
      label, tostring(expected), tostring(actual)), 2)
  end
end
local function between(value, lo, hi, label)
  checks = checks + 1
  if value < lo or value > hi then
    error(("%s: expected %s..%s, got %s"):format(
      label, tostring(lo), tostring(hi), tostring(value)), 2)
  end
end

-- Flora only needs these provider modules to exist while its pure weather
-- helpers are loaded; none of their rendering methods run in this test.
local modules = {
  Voxel3D = {}, TileShape = {}, Mat4 = {}, FirstPerson = {},
  DayNight = {}, ThirdPerson = {},
}
local V = {
  require = function(name)
    local module = modules[name]
    if module == nil then error("unexpected provider module " .. name) end
    return module
  end,
}

local Flora = assert(loadfile("lib/Flora.lua"))(V)
local profile = assert(Flora._seasonalWeatherProfile)
local roll = assert(Flora._seasonalWeatherRoll)
local seasonal = assert(Flora._seasonal)

local winter = profile({ year = 2026, month = 1, day = 15 })
local spring = profile({ year = 2026, month = 4, day = 15 })
local summer = profile({ year = 2026, month = 7, day = 15 })
local autumn = profile({ year = 2026, month = 10, day = 15 })
local december = profile({ year = 2026, month = 12, day = 15 })
eq(winter.season, "WINTER", "January profile")
eq(spring.season, "SPRING", "April profile")
eq(summer.season, "SUMMER", "July profile")
eq(autumn.season, "AUTUMN", "October profile")
eq(december.season, "WINTER", "December profile")
eq(summer.dateKey, "2026-07-15", "local date key")

check(winter.wetMin > summer.wetMin,
  "winter showers last longer than summer showers")
check(summer.dryMin > spring.dryMin,
  "summer dry spells are longer than spring dry spells")
check(spring.stormOdds > winter.stormOdds,
  "spring showers have higher storm odds than steady winter rain")

local sameDay = profile({ year = 2026, month = 7, day = 15 })
local nextDay = profile({ year = 2026, month = 7, day = 16 })
eq(sameDay.seed, summer.seed, "same local day keeps the same seed")
check(nextDay.seed ~= summer.seed, "next local day changes the seed")
eq(roll(summer.seed, 1), roll(sameDay.seed, 1),
  "same daily seed repeats the same first roll")
check(roll(summer.seed, 1) ~= roll(summer.seed, 2),
  "successive seasonal rolls differ")
between(roll(summer.seed, 7), 0, 0.999999999999,
  "seasonal roll remains in [0, 1)")

local fallback = profile(nil)
eq(fallback.season, "MILD", "missing calendar selects safe fallback")
eq(fallback.dateKey, "calendar-unavailable", "fallback date key")
eq(fallback.dryMin, 240, "fallback preserves Sometimes dry minimum")
eq(fallback.dryMax, 900, "fallback preserves Sometimes dry maximum")
eq(fallback.wetMin, 45, "fallback preserves Sometimes wet minimum")
eq(fallback.wetMax, 150, "fallback preserves Sometimes wet maximum")
eq(fallback.stormOdds, 0.14, "fallback preserves Sometimes storm odds")
eq(profile({ year = 2026, month = 99, day = 1 }).season, "MILD",
  "malformed calendar selects safe fallback")

-- The pure seams must not consume the global random stream used by legacy
-- SOMETIMES weather and the rest of Flora.
math.randomseed(314159)
local expectedRandom = math.random()
math.randomseed(314159)
profile({ year = 2026, month = 3, day = 8 })
roll(12345, 12)
eq(math.random(), expectedRandom, "seasonal helpers leave math.random untouched")

-- A fixed day produces a deterministic clock, bounded by that season's
-- ranges, and rolls into rain without touching the legacy rainUntil/dryUntil.
local originalCalendar = seasonal.deviceCalendar
seasonal.deviceCalendar = function()
  return { year = 2026, month = 7, day = 15 }
end
seasonal.clock = nil
local raining, storm, liveProfile = seasonal.update(0)
eq(raining, false, "seasonal clock starts dry")
eq(storm, false, "dry seasonal clock is not a storm")
eq(liveProfile.season, "SUMMER", "clock uses device calendar profile")
between(seasonal.clock.dryUntil, summer.dryMin, summer.dryMax,
  "initial dry spell follows summer bounds")
local firstDryUntil = seasonal.clock.dryUntil
local rainStart = firstDryUntil + 0.01
raining, storm = seasonal.update(rainStart)
eq(raining, true, "seasonal clock enters a shower")
check(type(storm) == "boolean", "storm result is boolean")
between(seasonal.clock.rainUntil - rainStart,
  summer.wetMin, summer.wetMax, "shower follows summer bounds")

seasonal.clock = nil
seasonal.update(0)
eq(seasonal.clock.dryUntil, firstDryUntil,
  "same date repeats the deterministic daily schedule")

-- Date refresh is cheap (once a minute) and rolls to a fresh daily clock.
seasonal.deviceCalendar = function()
  return { year = 2026, month = 7, day = 16 }
end
seasonal.update(61)
eq(seasonal.clock.dateKey, "2026-07-16", "midnight/date change refreshes profile")
check(seasonal.clock.dryUntil > 61, "new date starts with a dry interval")

-- Calendar APIs can be absent on restricted devices without disabling the
-- mode.  Exercise both an unavailable function and a throwing function.
seasonal.deviceCalendar = originalCalendar
local savedDate = os.date
os.date = nil
eq(seasonal.deviceCalendar(), nil, "missing os.date is tolerated")
os.date = function() error("calendar denied") end
eq(seasonal.deviceCalendar(), nil, "throwing os.date is tolerated")
os.date = savedDate
seasonal.clock = nil

print(("seasonal weather tests passed (%d checks)"):format(checks))
