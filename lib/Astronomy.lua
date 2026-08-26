-- Small, deterministic astronomy helpers for Scott's pixel sky.
--
-- This is deliberately not a planetarium. The renderer needs stable lunar
-- phase/light answers plus one small equatorial-to-world coordinate seam for
-- fixed sky art. Keeping those answers here makes the real-clock and
-- accelerated game-clock paths use exactly the same math without adding a
-- network, GPS or per-frame OS query to the Thor build.

local Astronomy = {}

local PI2 = math.pi * 2
local DAY_SECONDS = 86400

-- 2000-01-06 18:14 UTC, a commonly used known-new-moon epoch.  A lunar phase
-- does not need the player's location; location changes rise/set geometry,
-- while the illuminated fraction is effectively the same everywhere.
Astronomy.NEW_MOON_EPOCH = 947182440
Astronomy.SYNODIC_MONTH_DAYS = 29.530588853
Astronomy.DEFAULT_GAME_CYCLE_DAYS = 8
Astronomy.SIDEREAL_TURNS_PER_DAY = 1.002737909

local function wrap01(value)
  value = tonumber(value) or 0
  return value - math.floor(value)
end

Astronomy.wrap01 = wrap01

-- Local sidereal rotation in turns. `dayCount` may be an absolute Unix-day
-- count or the accelerated game's continuous day count; day zero is a
-- deliberately neutral reference so a catalog renderer can choose one clear
-- calibration without burying an asset-specific offset in this pure helper.
-- Longitude is optional and east-positive, also in turns.
function Astronomy.siderealTurns(dayCount, longitudeTurns)
  return wrap01((tonumber(dayCount) or 0)
                * Astronomy.SIDEREAL_TURNS_PER_DAY
                + (tonumber(longitudeTurns) or 0))
end

-- Convert an equatorial catalog coordinate into Scott's world axes:
-- +X east, +Y up, +Z south. RA is in hours, declination and latitude are in
-- degrees, and `siderealTurns` is the local meridian's right ascension in
-- turns. The result is normalized defensively so callers can use it directly
-- as a sky direction without carrying coordinate-system details into drawing.
function Astronomy.equatorialDirection(raHours, decDegrees, siderealTurns,
                                        latitudeDegrees)
  local ra = (tonumber(raHours) or 0) / 24 * PI2
  local dec = math.max(-90, math.min(90, tonumber(decDegrees) or 0))
              * math.pi / 180
  local latitude = math.max(-90, math.min(90,
                          tonumber(latitudeDegrees) or 0)) * math.pi / 180
  local hourAngle = ((tonumber(siderealTurns) or 0) * PI2) - ra
  local cosDec, sinDec = math.cos(dec), math.sin(dec)
  local cosLat, sinLat = math.cos(latitude), math.sin(latitude)
  local cosHour, sinHour = math.cos(hourAngle), math.sin(hourAngle)
  local dx = -cosDec * sinHour
  local dy = sinLat * sinDec + cosLat * cosDec * cosHour
  local dz = sinLat * cosDec * cosHour - cosLat * sinDec
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  if length <= 0 then return { dx = 0, dy = 1, dz = 0 } end
  return { dx = dx / length, dy = dy / length, dz = dz / length }
end

function Astronomy.realPhase(timestamp)
  timestamp = tonumber(timestamp) or Astronomy.NEW_MOON_EPOCH
  local month = Astronomy.SYNODIC_MONTH_DAYS * DAY_SECONDS
  return wrap01((timestamp - Astronomy.NEW_MOON_EPOCH) / month)
end

function Astronomy.gamePhase(gameDay, cycleDays)
  cycleDays = tonumber(cycleDays) or Astronomy.DEFAULT_GAME_CYCLE_DAYS
  if cycleDays <= 0 then cycleDays = Astronomy.DEFAULT_GAME_CYCLE_DAYS end
  return wrap01((tonumber(gameDay) or 0) / cycleDays)
end

-- Phase zero is new, one half is full.  The cosine form is both the physical
-- illuminated fraction and a smooth value that can drive the pixel palette.
function Astronomy.illumination(phase)
  return (1 - math.cos(PI2 * wrap01(phase))) * 0.5
end

function Astronomy.phaseName(phase)
  local index = math.floor(wrap01(phase) * 8 + 0.5) % 8
  return ({
    "NEW", "WAXING CRESCENT", "FIRST QUARTER", "WAXING GIBBOUS",
    "FULL", "WANING GIBBOUS", "LAST QUARTER", "WANING CRESCENT",
  })[index + 1]
end

-- A small, location-free lunar clock. Fractions are measured from local
-- sunrise around one civil day: a new Moon rises with the sun (0), first
-- quarter near noon (0.25), full Moon near sunset (0.5), and last quarter
-- near midnight (0.75). This is intentionally the same simple astronomical
-- model as the phase art -- enough to make the pixel Moon drift later each
-- day without asking the handheld for GPS or building an ephemeris.
function Astronomy.moonrise(phase)
  return wrap01(phase)
end

-- Where the Moon is in its daily path: zero at moonrise, 0.25 at transit,
-- 0.5 at moonset and 0.75 on the far side of the world. Keeping this helper
-- in fractions lets both the 24-hour clock and accelerated game clocks use
-- exactly the same orbit.
function Astronomy.moonDayPosition(dayFraction, phase)
  return wrap01(wrap01(dayFraction) - Astronomy.moonrise(phase))
end

-- How much later moonrise occurs from one day to the next for a cycle of the
-- requested length. The real synodic month yields about 48.8 minutes; the
-- existing eight-day game cycle deliberately advances three game-hours.
function Astronomy.moonriseDelay(cycleDays)
  cycleDays = tonumber(cycleDays) or Astronomy.SYNODIC_MONTH_DAYS
  if cycleDays <= 0 then cycleDays = Astronomy.SYNODIC_MONTH_DAYS end
  return 1 / cycleDays
end

function Astronomy.snapshotPhase(source, phase)
  source = source or "fixed"
  phase = wrap01(phase)
  local lit = Astronomy.illumination(phase)
  return {
    source = source,
    phase = phase,
    moonrise = Astronomy.moonrise(phase),
    illuminated = lit,
    -- Cast-light strength follows the illuminated fraction directly.  The
    -- ambient night palette remains, so a new moon is dark rather than black.
    moonlight = lit,
    -- The Milky Way never snaps completely away, but full moonlight washes
    -- most of it out.  The curve reserves its strongest jump for dark moons.
    milkyWay = 0.16 + 0.84 * ((1 - lit) ^ 1.35),
    waxing = phase > 0 and phase < 0.5,
    name = Astronomy.phaseName(phase),
  }
end

function Astronomy.snapshot(source, value, cycleDays)
  source = source == "game" and "game" or "sync"
  local phase = source == "game"
    and Astronomy.gamePhase(value, cycleDays)
    or Astronomy.realPhase(value)
  return Astronomy.snapshotPhase(source, phase)
end

-- Light at a point on the visible lunar sphere. nx/ny are disc-local values
-- from -1 to 1. Positive means sunlit. This gives the renderer a real curved
-- terminator while still letting it paint the result as whole square cells.
function Astronomy.surfaceLight(nx, ny, phase)
  nx, ny = tonumber(nx) or 0, tonumber(ny) or 0
  local rr = nx * nx + ny * ny
  if rr > 1 then return -1 end
  local nz = math.sqrt(math.max(0, 1 - rr))
  local a = PI2 * wrap01(phase)
  return nx * math.sin(a) - nz * math.cos(a)
end

return Astronomy
