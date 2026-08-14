-- ROM-free production-loader smoke.
-- Run from a Gen1Recomp checkout:
--   luajit <mod>/tests/full_load.lua <mod-root> [fixture-root]

local argv = rawget(_G, "arg") or {}
local sourceRoot = argv[1] or os.getenv("SCOTTS_TWEAKS_MOD_ROOT")
local fixtureRoot = argv[2] or os.getenv("SCOTTS_TWEAKS_FIXTURE_ROOT") or "."
local engineRoot = os.getenv("SCOTTS_TWEAKS_ENGINE_ROOT") or fixtureRoot
assert(sourceRoot, "pass the Scott's Tweaks source root")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. fixtureRoot .. "/?.lua;" .. fixtureRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

local function read(relative)
  local path = sourceRoot .. "/" .. relative
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local prefix = "mods/voxel_run_bridge/"
local freeFlyPrefix = "mods/free_fly/"
local pokemonFinalPrefix = "mods/POKEMON_FINAL/"
local freeFlyManifest = [[{
  "id": "free_fly",
  "name": "Free Fly Test Double",
  "version": "1.5.0",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "priority": 100,
  "dependencies": [],
  "optional_dependencies": [],
  "conflicts": [],
  "games": ["gen1"],
  "permissions": []
}]]
local freeFlyEntry = [[return function(mod)
  mod.options:define({
    { key = "badges", type = "toggle", default = true },
    { key = "gates", type = "toggle", default = true }
  })
  local function option(key, default)
    local value = mod.options:get(key)
    if value == nil then return default end
    return value
  end
  local function badgeChecksEnabled() return option("badges", true) == true end
  local function startFlight(save)
    if not save.knowsFly then
      return false, "FLY REQUIRED"
    end
    if option("gates", true) == true and save.storyBlocked then
      return false, "STORY BLOCKED"
    end
    if badgeChecksEnabled() and not (save.inventory or {}).THUNDERBADGE then
      return false, "THUNDERBADGE REQUIRED"
    end
    return true, "TAKEOFF"
  end
  mod.exports.isFlying = function() return false end
  mod.exports.testBadgeChecks = badgeChecksEnabled
  mod.exports.testStartFlight = startFlight
end]]
local pokemonFinalManifest = [[{
  "id": "POKEMON_FINAL",
  "name": "Pokemon Final Test Double",
  "version": "1.8.1-scott.4",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "priority": 100,
  "dependencies": [],
  "optional_dependencies": [],
  "conflicts": [],
  "games": ["gen1"],
  "permissions": []
}]]
local pokemonFinalEntry = [[return function(mod)
  local FreeMove = { WALK = 1, BIKE = 2 }
  FreeMove.tick = function(state) return state end
  local VoxelScene = { render = function(state) return state end }
  local Voxel3D = {
    beginScene = function() return true end,
    newMesh = function() return { release = function() end } end,
    draw = function() end,
    invalidate = function() end,
    seams = function() end,
    glass = function() end,
  }
  local VoxelState = { isFreeCam = function() return true end }
  local DayNight = { isCanopy = function() return false end }
  local Mat4 = { translate = function(x, y, z) return { x, y, z } end }
  local modules = {
    FreeMove = FreeMove,
    VoxelScene = VoxelScene,
    Voxel3D = Voxel3D,
    VoxelState = VoxelState,
    DayNight = DayNight,
    Mat4 = Mat4,
  }
  mod.exports.lib = {
    require = function(name) return modules[name] end
  }
  mod.exports.testFreeMove = FreeMove
  mod.exports.testVoxelScene = VoxelScene
  mod.exports.testVoxel3D = Voxel3D
end]]
local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs({
    [prefix .. "manifest.json"] = read("manifest.json"),
    [prefix .. "main.lua"] = read("main.lua"),
    [freeFlyPrefix .. "manifest.json"] = freeFlyManifest,
    [freeFlyPrefix .. "main.lua"] = freeFlyEntry,
    [pokemonFinalPrefix .. "manifest.json"] = pokemonFinalManifest,
    [pokemonFinalPrefix .. "main.lua"] = pokemonFinalEntry,
  }),
  generation = 1,
})

T.eq(#run.errors, 0, "Scott's Tweaks loads through the API-2 loader")
T.check(run.mod ~= nil, "loader selected Scott's Tweaks")
T.eq(run.mod and run.mod.manifest.id, "voxel_run_bridge",
  "stable updater identity is retained")
T.eq(run.mod and run.mod.manifest.name, "Scott's Tweaks",
  "new display name is loaded")
T.eq(run.mod and run.mod.manifest.version, "0.3.0",
  "loader selected version 0.3.0")

local schema = run.loader.optionSchemas.voxel_run_bridge or {}
local gappedLandOption
for _, row in ipairs(schema) do
  if row.key == "gapped_land" then gappedLandOption = row break end
end
T.check(type(gappedLandOption) == "table", "Gapped Land option is registered")
T.eq(gappedLandOption and gappedLandOption.type, "toggle",
  "Gapped Land uses a toggle")
T.eq(gappedLandOption and gappedLandOption.label, "GAPPED LAND",
  "Gapped Land uses its player-facing label")
T.eq(gappedLandOption and gappedLandOption.default, true,
  "Gapped Land defaults on")

local hmOption
for _, row in ipairs(schema) do
  if row.key == "hm_without_badges" then hmOption = row break end
end
T.check(type(hmOption) == "table", "HM option is registered")
T.eq(hmOption and hmOption.default, true, "HM bypass defaults on")

local freeFlyOption
for _, row in ipairs(schema) do
  if row.key == "free_fly_without_badges" then freeFlyOption = row break end
end
T.check(type(freeFlyOption) == "table", "Free Fly option is registered")
T.eq(freeFlyOption and freeFlyOption.default, true,
  "Free Fly bypass defaults on")

local freeFlyOptions = run.loader.modOptions.free_fly
T.check(type(freeFlyOptions) == "table", "Free Fly live option bucket exists")
T.eq(freeFlyOptions and freeFlyOptions.badges, false,
  "production loader applies Free Fly's own badge override")
local freeFlyExports = run.loader.exports.free_fly
T.check(type(freeFlyExports) == "table", "Free Fly exports are feature-detected")
T.eq(freeFlyExports.testBadgeChecks(), false,
  "Free Fly reads the live badge override")
local flightSave = { inventory = {}, knowsFly = true }
local flew, reason = freeFlyExports.testStartFlight(flightSave)
T.eq(flew, true, "Free Fly private gate passes without badge")
T.eq(reason, "TAKEOFF", "Free Fly does not return THUNDERBADGE error")
T.eq(next(flightSave.inventory), nil, "Free Fly adapter never grants a badge")
local noMove, moveReason = freeFlyExports.testStartFlight({
  inventory = {}, knowsFly = false,
})
T.eq(noMove, false, "Free Fly still requires an eligible FLY user")
T.eq(moveReason, "FLY REQUIRED", "Free Fly move rule remains on")
local crossedGate, gateReason = freeFlyExports.testStartFlight({
  inventory = {}, knowsFly = true, storyBlocked = true,
})
T.eq(crossedGate, false, "Free Fly story gate remains on")
T.eq(gateReason, "STORY BLOCKED", "Free Fly story rule is unchanged")

local hooks = run.loader.hooks
local pidgeot = { species = "PIDGEOT", moves = { { id = "FLY" } } }
local save = { inventory = {}, party = { pidgeot } }
local user = hooks:call("fieldmove.eligibility", function() return nil end,
  "FLY", { save = save, data = run.data })
T.eq(user, pidgeot, "production hook returns the real FLY user")
T.eq(next(save.inventory), nil, "production hook does not grant a badge")

local items = {
  { label = "STATS", action = "stats" },
  { label = "SWITCH", action = "switch" },
}
local cutter = { species = "BULBASAUR", moves = { { id = "CUT" } } }
local menu = hooks:call("ui.party.submenu", function(_, list) return list end,
  { data = run.data }, items, cutter,
  { battle = false, overworld = { dark = false, map = { def = {} } } })
T.eq(menu[1] and menu[1].action, "cut",
  "production party hook exposes known CUT before STATS")
T.eq(menu[2] and menu[2].action, "stats", "STATS remains after field moves")

local exported = run.loader.exports.voxel_run_bridge
T.check(type(exported) == "table", "exports are published")
T.eq(exported.status and exported.status.active, true,
  "voxel bridge activates through the production loader")
T.eq(exported.status and exported.status.voxel, "POKEMON_FINAL",
  "production loader selects Pokemon Final by manifest id")
T.check(type(exported.gappedLand) == "table",
  "Gapped Land compatibility status is published")
T.eq(exported.gappedLand and exported.gappedLand.active, true,
  "Gapped Land attaches through exported renderer capabilities")
T.eq(exported.gappedLand and exported.gappedLand.reason, "attached",
  "Gapped Land reports its active attachment state")
T.eq(exported.gappedLand and exported.gappedLand.mode, "visual_apron",
  "Gapped Land identifies its presentation-only mode")
T.eq(exported.gappedLand and exported.gappedLand.voxel, "POKEMON_FINAL",
  "Gapped Land reports the selected renderer provider")
T.eq(exported.gappedLand and exported.gappedLand.providerVersion,
  "1.8.1-scott.4", "Gapped Land exposes the provider version diagnostically")
T.eq(type(exported.gappedLand and exported.gappedLand.restore), "function",
  "Gapped Land publishes an ownership-safe restore function")
local pokemonFinalExports = run.loader.exports.POKEMON_FINAL
T.check(type(pokemonFinalExports) == "table",
  "Pokemon Final test-double exports are published")
T.eq(pokemonFinalExports.lib._voxelRunBridgeHook.owner, "voxel_run_bridge",
  "Pokemon Final FreeMove receives Scott's bridge marker")
T.eq(pokemonFinalExports.lib._voxelRunBridgeHook.version, "0.3.0",
  "Pokemon Final bridge marker carries the update version")
T.eq(type(exported.hmWithoutBadges), "function",
  "live HM option accessor is published")
T.eq(exported.hmWithoutBadges(), true, "live HM option reports enabled")

run.release()
T.finish("Scott's Tweaks full load")
