-- Run from the mod root with either:
--   luajit tests/main.lua
--   lovec tests

local checks = 0

local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(
      label, tostring(expected), tostring(actual)), 2)
  end
end

local speedResponder
local speedCalls = 0

local Runtime = {}
function Runtime.wantsHook(name)
  return name == "movement.speed" and speedResponder ~= nil
end
function Runtime.call(name, vanilla, frames, ctx)
  eq(name, "movement.speed", "hook name")
  speedCalls = speedCalls + 1
  if speedResponder then return speedResponder(frames, ctx) end
  return vanilla(frames, ctx)
end

local Game = {
  save = { onBike = false },
  input = { isDown = function() return true end },
}

package.preload["src.mods.Runtime"] = function() return Runtime end
package.preload["src.core.Game"] = function() return Game end

local entry = assert(loadfile("main.lua"))()

local function fixture(opts)
  opts = opts or {}
  local seen = {}
  local FreeMove = { WALK = 1, BIKE = 2 }
  local originalTick
  originalTick = function(state)
    seen.walk, seen.bike = FreeMove.WALK, FreeMove.BIKE
    if opts.throwTick then error("tick exploded") end
    return "tick-result", 42
  end
  FreeMove.tick = originalTick

  local lib = {
    _runningShoesHook = opts.runningShoesHook,
    _voxelRunBridgeHook = opts.bridgeHook,
    require = function(name)
      eq(name, "FreeMove", "requested voxel module")
      if opts.requireError then error("provider loader failed") end
      return FreeMove
    end,
  }
  local exportedLib = opts.malformedLib and 42 or lib
  local voxel = { exports = { lib = exportedLib } }
  local logs = {}
  local mod = {
    id = "voxel_run_bridge",
    exports = {},
    log = {
      info = function(_, message) logs[#logs + 1] = message end,
      warn = function(_, message) logs[#logs + 1] = message end,
    },
    find = function(id)
      if not opts.noVoxel and id == (opts.voxelId or "DRAMATIC_SHAPE") then
        return voxel
      end
    end,
  }

  entry(mod)
  return {
    mod = mod,
    lib = lib,
    FreeMove = FreeMove,
    originalTick = originalTick,
    seen = seen,
    logs = logs,
  }
end

local function player(fields)
  local p = {
    stepFrames = 16,
    bikeStepFrames = 8,
    surfing = false,
    moving = false,
    inputLocked = false,
  }
  for key, value in pairs(fields or {}) do p[key] = value end
  return p
end

-- Foot speed: 16 frames -> 8 frames is a 2x FreeMove walk.
speedResponder = function(frames, ctx)
  eq(frames, 16, "foot base frames")
  eq(ctx.onBike, false, "foot context")
  eq(ctx.freeMove, true, "free-move context")
  eq(ctx.continuous, true, "continuous context")
  return 8
end
speedCalls = 0
Game.save = { onBike = false }
local foot = fixture()
local a, b = foot.FreeMove.tick({ player = player() })
eq(a, "tick-result", "first tick return")
eq(b, 42, "second tick return")
eq(foot.seen.walk, 2, "foot multiplier visible inside tick")
eq(foot.seen.bike, 2, "bike speed untouched on foot")
eq(foot.FreeMove.WALK, 1, "walk speed restored")
eq(foot.FreeMove.BIKE, 2, "bike speed restored after foot tick")
eq(speedCalls, 1, "foot hook call count")

-- Bike speed uses the bike frame baseline and scales only BIKE.
speedResponder = function(frames, ctx)
  eq(frames, 8, "bike base frames")
  eq(ctx.onBike, true, "bike context")
  return 4
end
Game.save = { onBike = true }
local bike = fixture({ voxelId = "potato_voxel" })
bike.FreeMove.tick({ player = player() })
eq(bike.seen.walk, 1, "walk speed untouched on bike")
eq(bike.seen.bike, 4, "bike multiplier visible inside tick")
eq(bike.FreeMove.BIKE, 2, "bike speed restored")

-- Invalid hook output degrades to the voxel defaults.
speedResponder = function() return "not-a-speed" end
Game.save = { onBike = false }
local invalid = fixture({ voxelId = "DRAMALESS_SHAPE" })
invalid.FreeMove.tick({ player = player() })
eq(invalid.seen.walk, 1, "invalid speed falls back")

-- Numeric zero/negative output follows the engine's >=1 frame clamp.
speedResponder = function() return 0 end
local clamped = fixture({ voxelId = "BATTLE_ART_VOXEL_FORK" })
clamped.FreeMove.tick({ player = player() })
eq(clamped.seen.walk, 16, "zero speed result clamps to one frame")
eq(clamped.FreeMove.WALK, 1, "clamped walk speed restored")

-- Slower hooks are translated too; this is not hard-coded as a run boost.
speedResponder = function() return 32 end
local slowed = fixture()
slowed.FreeMove.tick({ player = player() })
eq(slowed.seen.walk, 0.5, "slower hook halves free movement")
eq(slowed.FreeMove.WALK, 1, "slower walk speed restored")

-- The bridge is dormant until another mod registers movement.speed.
speedResponder = nil
speedCalls = 0
local noProducer = fixture()
local passA, passB = noProducer.FreeMove.tick({ player = player() })
eq(passA, "tick-result", "no-producer first return")
eq(passB, 42, "no-producer second return")
eq(noProducer.seen.walk, 1, "no producer keeps voxel default")
eq(speedCalls, 0, "no producer hook calls")

-- A broken speed producer fails closed and warns only once per session.
speedResponder = function() error("speed hook exploded") end
speedCalls = 0
local brokenSpeed = fixture()
brokenSpeed.FreeMove.tick({ player = player() })
brokenSpeed.FreeMove.tick({ player = player() })
eq(brokenSpeed.seen.walk, 1, "broken speed hook keeps voxel default")
eq(brokenSpeed.FreeMove.WALK, 1, "broken speed hook leaves walk restored")
eq(speedCalls, 2, "broken speed hook was sampled")
eq(#brokenSpeed.logs, 2, "broken speed hook warns once after install log")

-- Scripted and input-locked movement never consults the hook.
speedResponder = function() return 1 end
speedCalls = 0
local scripted = fixture()
scripted.FreeMove.tick({ player = player({ moving = true }) })
scripted.FreeMove.tick({ player = player({ inputLocked = true }) })
eq(speedCalls, 0, "scripted movement hook calls")
eq(scripted.seen.walk, 1, "scripted movement keeps default")

-- Temporary constants are restored even if the voxel tick errors.
speedResponder = function() return 8 end
local broken = fixture({ throwTick = true })
local ok, err = pcall(broken.FreeMove.tick, { player = player() })
eq(ok, false, "tick error propagates")
eq(type(err), "string", "tick error has traceback text")
eq(broken.FreeMove.WALK, 1, "walk restored after error")
eq(broken.FreeMove.BIKE, 2, "bike restored after error")

-- Native Running Shoes integration remains the only wrapper when present.
local delegated = fixture({ runningShoesHook = true })
eq(delegated.FreeMove.tick, delegated.originalTick, "native integration not wrapped")
eq(delegated.mod.exports.status.reason,
  "running_shoes_has_native_voxel_support", "delegation reason")

-- A previous bridge marker prevents nested wrappers on a reload.
local already = fixture({ bridgeHook = { owner = "previous" } })
eq(already.FreeMove.tick, already.originalTick, "bridge is not installed twice")
eq(already.mod.exports.status.reason, "already_installed",
  "existing bridge reason")

-- Malformed companion exports and throwing module loaders fail closed.
local malformed = fixture({ malformedLib = true })
eq(malformed.mod.exports.status.reason, "no_supported_voxel_mod",
  "malformed export reason")
local loaderError = fixture({ requireError = true })
eq(loaderError.FreeMove.tick, loaderError.originalTick,
  "throwing provider loader is not wrapped")
eq(loaderError.mod.exports.status.reason, "voxel_freemove_unavailable",
  "throwing provider loader reason")

-- Installing without a supported voxel mod is a clean no-op.
local absent = fixture({ noVoxel = true })
eq(absent.mod.exports.status.active, false, "no-voxel status")
eq(absent.mod.exports.status.reason, "no_supported_voxel_mod",
  "no-voxel reason")

print(("voxel_run_bridge: %d checks passed"):format(checks))
if love and love.event then love.event.quit(0) end
