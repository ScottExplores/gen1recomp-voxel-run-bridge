-- Focused regression for Wilds' Pokemon Tower scripted Marowak cell guard.
--
--   luajit tests/wilds_special_spawn_safety.lua <mod-root>
--   lua    tests/wilds_special_spawn_safety.lua <mod-root>

local argv = rawget(_G, "arg") or {}
local root = argv[1] or "."

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

local function loadWild(name, V)
  return assert(loadfile(root .. "/vendor/wilds/lib/" .. name .. ".lua"))(V)
end

local MAP = "POKEMON_TOWER_6F"
local TX, TY = 10, 16
local game = { save = { flags = {} } }
local SpecialSpawnSafety = loadWild("special_spawn_safety", {})

local reserved, reason = SpecialSpawnSafety.isReserved(game, MAP, TX, TY)
check(reserved == true, "Marowak trigger is reserved before the story battle")
eq(reason, "scripted ghost Marowak trigger", "reservation explains its owner")
check(SpecialSpawnSafety.isReserved(game, MAP, TX, TY - 1) == false,
  "adjacent Tower cell remains available")
check(SpecialSpawnSafety.isReserved(game, "POKEMON_TOWER_5F", TX, TY) == false,
  "same coordinates on another floor remain available")
check(SpecialSpawnSafety.isReserved(game, MAP, tostring(TX), tostring(TY)) == true,
  "numeric engine coordinates are normalized")

local active = SpecialSpawnSafety.activeCells(game, MAP)
eq(#active, 1, "only the proven Tower trigger is reserved")
eq(active[1].x, TX, "active reservation keeps the engine x coordinate")
eq(active[1].y, TY, "active reservation keeps the engine y coordinate")

game.save.flags.EVENT_BEAT_GHOST_MAROWAK = true
check(SpecialSpawnSafety.isReserved(game, MAP, TX, TY) == false,
  "trigger returns to normal after Marowak is beaten")
eq(#SpecialSpawnSafety.activeCells(game, MAP), 0,
  "no Tower reservation remains after the event flag")
game.save.flags.EVENT_BEAT_GHOST_MAROWAK = nil

-- Candidate selection must skip the trigger rather than merely detecting it
-- after an entity has already been created.
local Grass = loadWild("grass", {})
local map = {
  id = MAP,
  widthCells = 20,
  heightCells = 20,
  isWalkableCell = function() return true end,
  warpAtCell = function() return nil end,
}
local rejected = {}
local x, y = Grass.pickFree(
  map, {}, { cellX = 0, cellY = 0 }, 0,
  function() return 1 end,
  { { x = TX, y = TY }, { x = TX + 2, y = TY } }, 99,
  function(why) rejected[#rejected + 1] = why end,
  {
    mode = "walkable",
    isBlocked = function(cx, cy)
      return SpecialSpawnSafety.isReserved(game, MAP, cx, cy)
    end,
  })
eq(x, TX + 2, "spawn picker skips the scripted trigger")
eq(y, TY, "spawn picker keeps the eligible neighbor")
local sawStoryReject = false
for _, why in ipairs(rejected) do
  if why == "rejected: story trigger reserved" then
    sawStoryReject = true
    break
  end
end
check(sawStoryReject, "spawn diagnostics report the story reservation")

-- Exercise the real behavior state machine. The only walkable destination is
-- the Marowak trigger: wander must stay put until the event is complete.
local movementTarget
local Config = {
  STATE = {
    AVAILABLE = "available",
    REMOVED = "removed",
    ENCOUNTER_STARTING = "encounter_starting",
    IN_BATTLE = "in_battle",
  },
  DEFAULTS = { wild_step_seconds = 0.28 },
}
local Surface = { GRASS = "grass", WATER = "water", CAVE = "cave" }
local Movement = {
  STATE = { IDLE = "idle", ALERT = "alert", BATTLE_PENDING = "battle_pending" },
  isBusy = function() return false end,
  beginStep = function(_, nx, ny)
    movementTarget = { x = nx, y = ny }
    return true
  end,
  setFacing = function() end,
  refreshGrassFlag = function() end,
  stop = function() end,
}
local SafariCompat = {
  LAND_WEIGHTS = { SAFARI_IDLE = 1, SAFARI_WANDER = 1, SAFARI_FLEE = 1 },
  WATER_WEIGHTS = { WATER_IDLE = 1, WATER_WANDER = 1 },
  fleeAffinity = function() return 1 end,
}
local behaviorDeps = {
  config = Config,
  surface = Surface,
  spawn_regions = {
    contains = function() return true end,
    regionForCell = function() return nil end,
  },
  movement = Movement,
  cell_occupancy = { isFollowerEntity = function() return false end },
  safari_compat = SafariCompat,
  special_spawn_safety = SpecialSpawnSafety,
}
local Behavior = loadWild("behavior", {
  require = function(name)
    return assert(behaviorDeps[name], "unexpected Behavior dependency: " .. name)
  end,
})

local behaviorMap = {
  id = MAP,
  widthCells = 20,
  heightCells = 20,
  warpAtCell = function() return nil end,
  isGrassCell = function(_, cx, cy) return cx == TX and cy == TY end,
  isWalkableCell = function(_, cx, cy) return cx == TX and cy == TY end,
}
local entity = {
  cellX = TX,
  cellY = TY - 1,
  surface = Surface.GRASS,
  state = Config.STATE.AVAILABLE,
  behavior = Behavior.GRASS_WANDER,
  behaviorState = {
    behavior = Behavior.GRASS_WANDER,
    state = Behavior.STATE.PAUSED,
    nextActionAt = 0,
  },
}
local behaviorCtx = {
  map = behaviorMap,
  mapId = MAP,
  entities = {},
  player = { cellX = 0, cellY = 0 },
  game = game,
  rng = function(limit)
    if limit then return limit end
    return 1
  end,
}
Behavior.tick(entity, behaviorCtx)
check(movementTarget == nil,
  "wandering Pokemon cannot step onto the active Marowak trigger")

game.save.flags.EVENT_BEAT_GHOST_MAROWAK = true
entity.behaviorState.nextActionAt = 0
Behavior.tick(entity, behaviorCtx)
check(movementTarget ~= nil, "wander resumes after the scripted battle")
eq(movementTarget and movementTarget.x, TX, "released movement reaches trigger x")
eq(movementTarget and movementTarget.y, TY, "released movement reaches trigger y")
game.save.flags.EVENT_BEAT_GHOST_MAROWAK = nil

-- The shared hot-path context must carry the current map id into Behavior.
local tickDeps = {
  config = {}, behavior = {}, movement = {}, voxel_adapter = {}, debug_log = {},
  spawn_fx = {}, surface = {}, water_spawn = {},
  safari_compat = { SIGHT_RANGE = 4 }, grass = {}, palette_watch = {},
  game_compat = {}, perf_stats = {},
}
local BehaviorTick = loadWild("behavior_tick", {
  require = function(name)
    return assert(tickDeps[name], "unexpected BehaviorTick dependency: " .. name)
  end,
})
local tick = setmetatable({}, { __index = BehaviorTick })
local filled = tick:_fillBehaviorCtx(
  {}, { map = behaviorMap, entities = {}, player = behaviorCtx.player },
  game, {}, nil,
  {
    sight = 5, react = 0.2, chaseStep = 0.25, waterSight = 4,
    waterMons = false, landWaterMax = 5,
  }, false, entity, 0)
eq(filled.mapId, MAP, "behavior hot path forwards the current map id")

-- Exercise the actual SpawnLogic helper and final battle safety net with
-- narrow dependency stubs; neither path creates, moves, or battles anything.
local spawnDeps = { config = Config, grass = Grass,
  special_spawn_safety = SpecialSpawnSafety }
local SpawnLogic = loadWild("spawn_logic", {
  require = function(name)
    return spawnDeps[name] or {}
  end,
})
local removed = {}
local logic = setmetatable({
  mod = { world = {}, _testGame = game },
  activeMapId = MAP,
  pendingBattle = nil,
  entities = {
    blocked = {
      overworldWildSpawn = true,
      cellX = TX,
      cellY = TY,
      mapId = MAP,
    },
    neighbor = {
      overworldWildSpawn = true,
      cellX = TX + 1,
      cellY = TY,
      mapId = MAP,
    },
    inbound = {
      overworldWildSpawn = true,
      cellX = TX,
      cellY = TY - 1,
      targetX = TX,
      targetY = TY,
      mapId = MAP,
    },
  },
}, { __index = SpawnLogic })
function logic:_despawn(id)
  removed[id] = true
  self.entities[id] = nil
end
function logic:_ow()
  return { map = { id = MAP } }
end

eq(logic:purgeStoryReservedEntities(game, MAP), 2,
  "map initialization purges stale and inbound trigger occupants")
check(removed.blocked == true, "purge removes the conflicting Wilds entity")
check(removed.inbound == true,
  "purge removes an entity already moving into the trigger")
check(logic.entities.neighbor ~= nil, "purge preserves neighboring Wilds entities")

logic.entities.battle = {
  overworldWildSpawn = true,
  cellX = TX,
  cellY = TY,
  mapId = MAP,
}
local started = logic:_startBattle({
  id = "battle",
  state = Config.STATE.AVAILABLE,
  mapId = MAP,
  x = TX,
  y = TY,
})
check(started == false, "battle safety net refuses a Wilds encounter on the trigger")
check(removed.battle == true, "battle safety net despawns the conflicting entity")

logic.entities.inflightBattle = {
  overworldWildSpawn = true,
  cellX = TX,
  cellY = TY - 1,
  targetX = TX,
  targetY = TY,
  mapId = MAP,
}
started = logic:_startBattle({
  id = "inflightBattle",
  state = Config.STATE.AVAILABLE,
  mapId = MAP,
  x = TX,
  y = TY - 1,
})
check(started == false,
  "battle safety net checks an in-flight destination after hot reload")
check(removed.inflightBattle == true,
  "battle safety net despawns the inbound conflicting entity")

io.write(string.format("wilds special spawn safety: %d checks, %d failures\n",
  checks, failures))
if failures > 0 then os.exit(1) end
