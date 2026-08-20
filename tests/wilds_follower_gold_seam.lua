-- Focused Gold .88/.96 follower seam regression.
-- Run: luajit tests/wilds_follower_gold_seam.lua <mod-root> <engine-root>

local argv = rawget(_G, "arg") or {}
local modRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. package.path

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

local function slurp(path)
  local file = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = file:read("*a")
  file:close()
  return body
end

-- Lock the test to the exact public engine shapes that caused the failure.
local worldSource = slurp(engineRoot .. "/src/world/gen2/World.lua")
check(worldSource:find(
    "{ id = n.id, ox = n.ox, oy = n.oy, image = img }", 1, true) ~= nil,
  "Gold neighbor rows expose id/offset/image without nb.map")
check(worldSource:find(
    "npc.mapId == nil or npc.mapId == self.map.id", 1, true) ~= nil,
  "Gold rebuildPeople retains only current-map guests")

local modules = {}
local guestCompat = {
  isGen2 = function() return true end,
  attachGuestEntity = function(ow, entity)
    ow.entities = ow.entities or {}
    ow.npcs = ow.npcs or {}
    ow.entities[#ow.entities + 1] = entity
    ow.npcs[#ow.npcs + 1] = entity
    -- Exact old seam: attachGuestEntity fills only nil mapId. The control
    -- engine therefore has to rebind a preserved source-map guest first.
    if entity.mapId == nil and ow.map and ow.map.id then
      entity.mapId = ow.map.id
    end
    return "npcs+entities"
  end,
  liveOverworld = function(_, game) return game and game.world end,
}
modules["follower/constants"] = {}
modules.wilds_fs = {}
modules.debug_log = { info = function() end, warn = function() end }
modules.config = {
  DEFAULTS = { sprite_style = "pokemmo", follower_count = 1 },
  get = function(_, key) return modules.config.DEFAULTS[key] end,
  spriteStyle = function() return "pokemmo" end,
  debug = function() return false end,
}
modules.tile = { CELL = 16 }
modules.cell_occupancy = {
  isFollowerEntity = function(entity)
    return entity and entity.pokepcTrailer == true
  end,
}
modules.surface = { WATER = "WATER" }
modules.game_compat = guestCompat

local mod = {
  id = "overworld_wild_spawns",
  path = modRoot .. "/vendor/wilds",
  exports = {},
  options = { get = function() return nil end },
  log = { info = function() end, warn = function() end },
  find = function() return nil end,
}
local V = { mod = mod, path = mod.path }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile(modRoot .. "/vendor/wilds/lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local GoldMap = require("src.world.gen2.Map")
local ControlEngine = V.require("follower/control_engine")
local game = { generation = 2 }
local engine = ControlEngine.new(mod, { game = game })

local tileset = { collision = { [2] = { 0, 0, 0, 0 } } }
local function mapDef(id)
  return {
    id = id, tileset = "TEST", environment = "ROUTE",
    width = 2, height = 2, blocks = { 1, 1, 1, 1 },
  }
end
local oldDef, newDef = mapDef("OLD_ROUTE"), mapDef("NEW_ROUTE")
local oldMap = GoldMap.new(oldDef, tileset)
local newMap = GoldMap.new(newDef, tileset)
local ow = {
  map = newMap,
  maps = { OLD_ROUTE = oldDef, NEW_ROUTE = newDef },
  tilesets = { TEST = tileset },
  -- Real Gold neighbor shape. x=-1 translates through ox=-32 to old x=1.
  neighbors = { { id = "OLD_ROUTE", ox = -32, oy = 0, image = {} } },
  _wildsFollowerSeamActive = true,
}
game.world = ow
mod.world = { game = game }

local seamSnapshot = { map = oldMap, playerX = 0, playerY = 1 }
check(engine:_isWalkingSeam(game, ow,
    { via = "connection", map = newMap }, seamSnapshot),
  "explicit connection is the only soft follower handoff")
for _, via in ipairs({ "boot", "reload", "checkpoint", "continue" }) do
  check(not engine:_isWalkingSeam(game, ow,
      { via = via, map = newMap }, seamSnapshot),
    via .. " lifecycle entry fails closed even at a map edge")
end
check(not engine:_isWalkingSeam(game, ow, { map = newMap }, seamSnapshot),
  "missing entry cause fails closed")

local resolved, rx, ry = engine:_followerMapCell(ow, -1, 1)
check(resolved ~= nil and getmetatable(resolved) == GoldMap,
  "id-only Gold neighbor resolves through the real gen2.Map API")
eq(resolved and resolved.id, "OLD_ROUTE",
  "resolved follower cell belongs to the source neighbor")
eq(rx, 1, "negative destination x translates to neighbor-local x")
eq(ry, 1, "neighbor-local y is retained")
check(engine:isFollowerCellAllowed(game, ow,
    { pokepcTrailer = true, wildsFollowerRole = "party_trailer" }, -1, 1,
    { surface = "land", role = "party_trailer" }),
  "translated old-side follower cell stays walkable")
local cached = select(1, engine:_followerMapCell(ow, -1, 1))
eq(cached, resolved, "Gold neighbor runtime map is cached by world/definition")

-- Preserve the Gen1 row contract alongside the new Gold resolver.
local gen1Neighbor = {
  id = "GEN1_NEIGHBOR",
  inBounds = function(_, x, y) return x == 1 and y == 1 end,
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
}
ow.neighbors = { { map = gen1Neighbor, ox = -32, oy = 0 } }
local legacyResolved = select(1, engine:_followerMapCell(ow, -1, 1))
eq(legacyResolved, gen1Neighbor, "Gen1 nb.map neighbor resolution is preserved")

-- A preserved native Gold NPC carries its source mapId. The destination
-- attach must rebind it before Gold's next rebuildPeople guest filter.
local trailer = {
  id = "wilds_trailer_1", mapId = "OLD_ROUTE",
  pokepcTrailer = true, wildsFollower = true,
  cellX = 0, cellY = 1, px = 0, py = 16,
  targetX = 1, targetY = 1, goalX = 1, goalY = 1,
  _wildsGoalX = 2, _wildsGoalY = 1,
  facing = "right", moving = true, progress = 0.25,
}
ow.player = { cellX = 1, cellY = 1 }
ow.npcs, ow.entities = {}, { ow.player }
engine._pendingConnectionHandoff = {
  playerX = 0, playerY = 1,
  trailers = { trailer },
  trailCells = { { x = 0, y = 1 } },
  trailHead = { x = 0, y = 1 },
  trailHistory = {},
}
check(engine:_applyConnectionHandoff(ow),
  "Gold destination applies the preserved follower handoff")
eq(trailer.mapId, "NEW_ROUTE",
  "destination attach rebinds the preserved Gold guest mapId")
eq(trailer.cellX, 1, "handoff translates a moving trailer body")
eq(trailer.targetX, 2, "handoff translates a moving trailer target")
eq(trailer._wildsGoalX, 3,
  "handoff translates the authoritative live movement goal")
eq(ow.npcs[1], trailer, "translated guest attaches to Gold NPC list")
eq(ow.entities[2], trailer, "translated guest attaches to Gold draw list")
check(trailer.mapId == nil or trailer.mapId == ow.map.id,
  "translated guest survives Gold rebuildPeople's exact retention filter")

if failures > 0 then
  io.stderr:write(string.format("%d/%d checks passed, %d FAILURES\n",
    checks - failures, checks, failures))
  os.exit(1)
end
print(string.format("wilds follower Gold seam: %d checks passed", checks))
