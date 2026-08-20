-- Allocation and behavior regression for Wilds' present-pipeline tick.
--
-- The real loop runs once per rendered frame. With twelve visible Pokemon it
-- must not allocate per-entity option tables or helper closures, or a handheld
-- spends several megabytes per minute on avoidable garbage collection.
--
--   luajit tests/wilds_behavior_tick_alloc.lua <mod-root>
--   lua    tests/wilds_behavior_tick_alloc.lua <mod-root>

local argv = rawget(_G, "arg") or {}
local root = argv[1] or "."

if rawget(_G, "jit") and type(jit.off) == "function" then
  -- Interpreter mode makes the allocation ceiling deterministic and also
  -- exercises the same bytecode path as stock Lua 5.1.
  jit.off()
end

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL " .. tostring(message) .. "\n")
  end
end
local function eq(got, wanted, message)
  check(got == wanted, string.format("%s (got %s, want %s)",
    message, tostring(got), tostring(wanted)))
end

local clock = 100
_G.love = {
  timer = {
    getTime = function() return clock end,
  },
}

local counters = {
  voxel = 0,
  spawnFx = 0,
  behavior = 0,
  animation = 0,
  alerts = 0,
  battles = 0,
  waterRefreshes = 0,
  fxCtxChanges = 0,
  behaviorCtxChanges = 0,
  aiTicks = 0,
  voxelFallbacks = 0,
}
local firstFxCtx
local firstBehaviorCtx
local emitEvents = false

local Config = {
  STATE = { AVAILABLE = "available" },
  DEFAULTS = {
    aggressive_sight_range = 5,
    aggressive_reaction_delay = 0.2,
    aggressive_step_seconds = 0.25,
    water_aggressive_sight_range = 4,
    land_water_chase_player_max = 6,
  },
}
function Config.isEnabled() return true end
function Config.get(_, key)
  if key == "wilds_ai" then return true end
  return nil
end
function Config.waterMons() return false end

local Behavior = {
  STATE = {
    ALERT = "alert",
    PLAYER_DETECTED = "player_detected",
    PLAYER_NOTICED = "player_noticed",
    CHASING = "chasing",
    CHASE_START = "chase_start",
    FLEEING = "fleeing",
    FLEE_START = "flee_start",
  },
}
function Behavior.isSafariFlee() return false end
function Behavior.isSafari() return false end
function Behavior.clearSafariFlee() end
function Behavior.tick(entity, ctx)
  counters.behavior = counters.behavior + 1
  if firstBehaviorCtx == nil then
    firstBehaviorCtx = ctx
  elseif firstBehaviorCtx ~= ctx then
    counters.behaviorCtxChanges = counters.behaviorCtxChanges + 1
  end
  if emitEvents and not entity._allocationEventEmitted then
    entity._allocationEventEmitted = true
    return entity.fixtureEvent
  end
end

local Movement = {}
function Movement.healBusy() return false end
function Movement.isBusy() return false end
function Movement.update() error("idle fixture must not interpolate movement") end
function Movement.refreshGrassFlag() end

local VoxelAdapter = {}
function VoxelAdapter.new()
  return {
    present = true,
    voxelActive = false,
    refreshPresence = function(self) self.present = true end,
    _probeVoxelActive = function() return false end,
    updateEntity = function(_, entity)
      counters.voxel = counters.voxel + 1
      entity.voxelUpdates = (entity.voxelUpdates or 0) + 1
    end,
    markFallback = function(_, entity, detail)
      counters.voxelFallbacks = counters.voxelFallbacks + 1
      entity.voxelFallbackDetail = detail
    end,
  }
end

local SpawnFx = {}
function SpawnFx.ensureProgress(entity)
  if entity.canTriggerBattle == nil then entity.canTriggerBattle = true end
end
function SpawnFx.updateEntity(_, _, ctx)
  counters.spawnFx = counters.spawnFx + 1
  if firstFxCtx == nil then
    firstFxCtx = ctx
  elseif firstFxCtx ~= ctx then
    counters.fxCtxChanges = counters.fxCtxChanges + 1
  end
end
function SpawnFx.canAct() return true end
function SpawnFx.canBattle(entity) return entity.canTriggerBattle ~= false end

local Surface = { WATER = "water" }
local WaterSpawn = {}
function WaterSpawn.distanceAt() return 2 end
function WaterSpawn.zoneForDistance() return "near_shore" end

local SafariCompat = {
  SIGHT_RANGE = 4,
  STATUS = { ACTIVE = "active", INACTIVE = "inactive" },
}
function SafariCompat.isActive() return false end
function SafariCompat.status() return SafariCompat.STATUS.INACTIVE end

local Grass = {}
local PaletteWatch = {}
function PaletteWatch.new()
  return { tick = function() end }
end

local GameCompat = {}
function GameCompat.liveOverworld(mod) return mod.world._ow end
function GameCompat.pollWildAlertEmote() end
function GameCompat.isGen2() return false end

local PerfStats = {}
function PerfStats.new()
  return {
    enabled = false,
    beginFrame = function() return nil end,
    endFrame = function() end,
    addMs = function() end,
    sampleCounts = function() end,
    count = function(_, key, value)
      if key == "aiTicks" then counters.aiTicks = counters.aiTicks + value end
    end,
  }
end

local modules = {
  config = Config,
  behavior = Behavior,
  movement = Movement,
  voxel_adapter = VoxelAdapter,
  debug_log = { info = function() end, warn = function() end },
  spawn_fx = SpawnFx,
  surface = Surface,
  water_spawn = WaterSpawn,
  safari_compat = SafariCompat,
  grass = Grass,
  palette_watch = PaletteWatch,
  game_compat = GameCompat,
  perf_stats = PerfStats,
}
local V = {
  require = function(name)
    return assert(modules[name], "unexpected Wilds dependency: " .. tostring(name))
  end,
}

local BehaviorTick = assert(loadfile(
  root .. "/vendor/wilds/lib/behavior_tick.lua"))(V)

local entities, spawns = {}, {}
for id = 1, 12 do
  local entity = {
    id = id,
    species = "FIXMON_" .. tostring(id),
    behavior = "wander",
    behaviorState = { state = "idle", behavior = "wander" },
    cellX = id,
    cellY = id + 1,
    canTriggerBattle = true,
  }
  entities[id] = entity
  spawns[id] = {
    state = Config.STATE.AVAILABLE,
    species = entity.species,
    behavior = entity.behavior,
  }
end
entities[1].fixtureEvent = "alert"
entities[2].fixtureEvent = "contact"
entities[3].fixtureEvent = "entered_water"
entities[4].fixtureEvent = "flee_start"

local player = { cellX = 1, cellY = 1 }
local ow = {
  map = { id = "ALLOC_FIXTURE" },
  player = player,
  entities = { player },
}
local logic = {
  state = { initialized = true },
  entities = entities,
  spawns = spawns,
  spawnFx = { update = function() end },
  render = {
    syncEntityAnimation = function(_, entity)
      counters.animation = counters.animation + 1
      entity.animationUpdates = (entity.animationUpdates or 0) + 1
    end,
  },
  shoreDistance = {},
}
function logic:_entityHasCompatibleWaterSprite() return true end
function logic:_onAggressiveAlert()
  counters.alerts = counters.alerts + 1
end
function logic:_startBattle()
  counters.battles = counters.battles + 1
end
function logic:refreshEntitySprite(entity, opts)
  counters.waterRefreshes = counters.waterRefreshes + 1
  entity.surface = opts.surface
  entity.spriteState = opts.spriteState
  entity._wildsPresSpriteState = opts.spriteState
  entity.spriteKind = "swimming"
end

local game = {}
local mod = {
  id = "wilds_allocation_fixture",
  world = { game = game, _ow = ow },
  exports = {},
}
local tick = BehaviorTick.new(mod, logic)

local function advance(frames)
  for _ = 1, frames do
    clock = clock + (1 / 60)
    tick:step({ mapId = ow.map.id })
  end
end

-- Populate one-time caches before taking the stopped-GC measurement.
advance(30)
for key in pairs(counters) do counters[key] = 0 end
firstFxCtx = nil
firstBehaviorCtx = nil
emitEvents = true
for id = 1, 12 do entities[id]._allocationEventEmitted = nil end

collectgarbage("collect")
local beforeKiB = collectgarbage("count")
collectgarbage("stop")
advance(600)
local afterKiB = collectgarbage("count")
collectgarbage("restart")
local allocatedKiB = afterKiB - beforeKiB

-- One small fixed table and instance-owned callbacks are fine. The ceiling is
-- intentionally far below the former multi-megabyte ten-second growth, while
-- leaving headroom for the two supported Lua 5.1 allocators.
local ALLOCATION_BUDGET_KIB = 384
check(allocatedKiB <= ALLOCATION_BUDGET_KIB,
  string.format("600-frame Wilds loop allocated %.1f KiB (budget %d KiB)",
    allocatedKiB, ALLOCATION_BUDGET_KIB))
eq(counters.fxCtxChanges, 0,
  "all visible Pokemon share one stable SpawnFx context table")
eq(firstFxCtx and firstFxCtx.map, ow.map,
  "reused SpawnFx context still carries the live map")
eq(firstFxCtx and firstFxCtx.spawnFx, logic.spawnFx,
  "reused SpawnFx context still carries the live FX manager")
eq(counters.behaviorCtxChanges, 0,
  "all behavior calls share the existing reusable behavior context")
eq(counters.voxel, 600 * 12,
  "voxel presentation still updates every entity every rendered frame")
eq(counters.spawnFx, 600 * 12,
  "spawn presentation still updates every entity every rendered frame")
eq(counters.animation, 600 * 12,
  "sprite animation still updates every entity every rendered frame")
eq(counters.behavior, counters.aiTicks * 12,
  "behavior decisions retain the fixed-rate AI cadence")
check(counters.aiTicks >= 299 and counters.aiTicks <= 301,
  "600 frames at 60 Hz produce approximately 300 fixed AI ticks")
eq(counters.alerts, 1, "alert event dispatch is preserved")
eq(counters.battles, 1, "contact event dispatch is preserved")
eq(counters.waterRefreshes, 1, "water-entry presentation dispatch is preserved")
eq(spawns[3].surface, Surface.WATER,
  "water-entry event still updates the persistent spawn record")
eq(spawns[4].behavior, entities[4].behavior,
  "flee event still updates the persistent behavior record")
eq(spawns[12].x, entities[12].cellX,
  "frame tick still mirrors entity coordinates into its spawn record")

-- The allocation-free protected call must retain the old fault boundary: a
-- bad adapter marks each entity for fallback instead of aborting the frame.
tick.voxel.updateEntity = function() error("fixture voxel failure", 0) end
advance(1)
eq(counters.voxelFallbacks, 12,
  "allocation-free voxel dispatch still protects every entity update")
check(type(entities[1].voxelFallbackDetail) == "string"
    and entities[1].voxelFallbackDetail:find(
      "fixture voxel failure", 1, true) ~= nil,
  "protected voxel dispatch preserves its diagnostic error")

io.write(string.format(
  "wilds behavior allocation: %.1f KiB / 600 frames; %d checks\n",
  allocatedKiB, checks))
if failures > 0 then os.exit(1) end
