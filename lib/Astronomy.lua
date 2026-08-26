-- Small, deterministic astronomy helpers for Scott's pixel sky.
--
-- This is deliberately not a planetarium.  The renderer only needs four
-- stable answers: where the Moon is in its cycle, how much of it is lit, how
-- strongly it can light the world, and how much dark-sky detail survives.
-- Keeping those answers here makes the real-clock and accelerated game-clock
-- paths use exactly the same phase math without adding a network, GPS or
-- per-frame allocation to the Thor build.

local Astronomy = {}

local PI2 = math.pi * 2
local DAY_SECONDS = 86400

-- 2000-01-06 18:14 UTC, a commonly used known-new-moon epoch.  A lunar phase
-- does not need the player's location; location changes rise/set geometry,
-- while the illuminated fraction is effectively the same everywhere.
Astronomy.NEW_MOON_EPOCH = 947182440
Astronomy.SYNODIC_MONTH_DAYS = 29.530588853
Astronomy.DEFAULT_GAME_CYCLE_DAYS = 8

local function wrap01(value)
  value = tonumber(value) or 0
  return value - math.floor(value)
end

Astronomy.wrap01 = wrap01

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

function Astronomy.snapshot(source, value, cycleDays)
  source = source == "game" and "game" or "sync"
  local phase = source == "game"
    and Astronomy.gamePhase(value, cycleDays)
    or Astronomy.realPhase(value)
  local lit = Astronomy.illumination(phase)
  return {
    source = source,
    phase = phase,
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
