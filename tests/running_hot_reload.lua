-- Four real API-2 entry loads in one Lua process. The voxel module tables are
-- deliberately shared, matching F5 where process-global renderer modules
-- survive while Scott's Tweaks receives a fresh mod/options generation.

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks root required")
local engineRoot = assert(argv[2], "Gen1Recomp source root required")
package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local function read(relative)
  local file = assert(io.open(sourceRoot .. "/" .. relative, "rb"),
    "missing " .. relative)
  local body = file:read("*a")
  file:close()
  return body
end

local baseCalls, observedWalk = 0, nil
local FreeMove = { WALK = 1, BIKE = 2 }
function FreeMove.tick(state)
  baseCalls = baseCalls + 1
  observedWalk = FreeMove.WALK
  state.player.px = (state.player.px or 0) + 2
  return "base", nil, "tail"
end
local FirstPerson = {}
function FirstPerson.frame(me) return me.lift or 0 end
local sharedVoxel = {
  FreeMove = FreeMove, FirstPerson = FirstPerson,
}
package.preload["tests.scotts_tweaks_shared_voxel"] = function()
  return sharedVoxel
end

local providerManifest = [[{
  "id":"POKEMON_FINAL","name":"Shared Voxel","version":"1.8.1",
  "api":2,"entry":"main.lua","profile":"content","priority":100,
  "dependencies":[],"optional_dependencies":[],"conflicts":[],
  "games":["gen1"],"permissions":[]
}]]
local providerEntry = [[return function(mod)
  local shared = require("tests.scotts_tweaks_shared_voxel")
  mod.exports.lib = { require = function(name) return shared[name] end }
end]]
local function delegateManifest(id)
  return string.format([[{
    "id":"%s","name":"Legacy Delegate","version":"1.0.0",
    "api":2,"entry":"main.lua","profile":"content","priority":100,
    "dependencies":[],"optional_dependencies":[],"conflicts":[],
    "games":["gen1"],"permissions":[]
  }]], id)
end
local delegateEntry = [[return function(mod) mod.exports.active = true end]]

local prefix = "mods/voxel_run_bridge/"
local files = {
  [prefix .. "manifest.json"] = read("manifest.json"),
  [prefix .. "main.lua"] = read("main.lua"),
  ["mods/POKEMON_FINAL/manifest.json"] = providerManifest,
  ["mods/POKEMON_FINAL/main.lua"] = providerEntry,
  ["mods/trainer_forfeit/manifest.json"] = delegateManifest("trainer_forfeit"),
  ["mods/trainer_forfeit/main.lua"] = delegateEntry,
  ["mods/oak_spare_starter/manifest.json"] = delegateManifest("oak_spare_starter"),
  ["mods/oak_spare_starter/main.lua"] = delegateEntry,
}
for _, relative in ipairs({
  "modules/settings.lua", "modules/migrations.lua",
  "modules/trainer_forfeit.lua", "modules/trainer_dialogue.lua",
  "modules/oak_spare_starter.lua", "modules/running.lua",
  "modules/option_screen.lua", "modules/tweaks_menu.lua",
  "modules/thor_dual_screen.lua",
  "modules/gen2_ui_assets.lua", "modules/gen2_ui.lua",
}) do
  local ok, body = pcall(read, relative)
  if ok then files[prefix .. relative] = body end
end

local function loadEntry()
  local run = T.sdk.loadMod("mods/voxel_run_bridge", {
    data = require("tests.modkit.fixtures").fresh(),
    fs = T.sdk.memfs(files), generation = 1,
  })
  T.eq(#run.errors, 0, "entry loads through the real API-2 Loader")
  return run
end

local run1 = loadEntry()
local tickRecord = rawget(FreeMove, "_scottsTweaksRunningBobTick")
local frameRecord = rawget(FirstPerson, "_scottsTweaksRunningBobFrame")
T.check(type(tickRecord) == "table", "first entry installs bob dispatcher")
T.eq(tickRecord and tickRecord.state, frameRecord and frameRecord.state,
  "tick and camera dispatchers share one persistent state")
local tickWrapper = tickRecord and tickRecord.wrapper
local frameWrapper = frameRecord and frameRecord.wrapper
local firstOptionCallback = tickRecord and tickRecord.state.option
local speedRecord = rawget(FreeMove, "_scottsTweaksVoxelRunBridge")
local speedWrapper = speedRecord and speedRecord.wrapper

local run2 = loadEntry()
local tickRecord2 = rawget(FreeMove, "_scottsTweaksRunningBobTick")
local frameRecord2 = rawget(FirstPerson, "_scottsTweaksRunningBobFrame")
T.eq(tickRecord2, tickRecord, "second entry reuses the tick record")
T.eq(frameRecord2, frameRecord, "second entry reuses the frame record")
T.eq(tickRecord2.wrapper, tickWrapper, "tick wrapper identity stays stable")
T.eq(frameRecord2.wrapper, frameWrapper, "camera wrapper identity stays stable")
T.check(tickRecord2.state.option ~= firstOptionCallback,
  "second entry refreshes the settings callback")
local speedRecord2 = rawget(FreeMove, "_scottsTweaksVoxelRunBridge")
T.eq(speedRecord2, speedRecord,
  "second entry reuses the movement.speed dispatcher record")
T.eq(speedRecord2 and speedRecord2.wrapper, speedWrapper,
  "second entry does not stack a voxel speed wrapper")
local running2 = run2.loader.exports.voxel_run_bridge.running
T.eq(running2 and running2.bob and running2.bob.reason,
  "dispatcher_refreshed", "second export reports dispatcher refresh")

local Game = require("src.core.Game")
Game.save = { onBike = false }
Game.input = { isDown = function(_, key) return key == "b" end }
local player = {
  px = 0, py = 0, stepFrames = 16, moving = false,
  inputLocked = false, surfing = false, lift = 7,
}
local a, middle, tail = FreeMove.tick({ player = player })
T.eq(baseCalls, 1, "two entries still reach the voxel tick exactly once")
T.check(math.abs((observedWalk or 0) - (16 / 11)) < 0.00001,
  "held B applies the 1.5X producer exactly once")
T.eq(FreeMove.WALK, 1, "dispatcher restores the voxel speed constant")
T.eq(a, "base", "dispatcher preserves the first return")
T.eq(middle, nil, "dispatcher preserves an interior nil")
T.eq(tail, "tail", "dispatcher preserves the final return")
local cameraLift = FirstPerson.frame(player)
T.check(cameraLift ~= 7, "refreshed entry applies distance-based bob")
T.eq(player.lift, 7, "camera bob never mutates player lift")

local shoesManifestPath = "mods/running_shoes/manifest.json"
local shoesEntryPath = "mods/running_shoes/main.lua"
files[shoesManifestPath] = delegateManifest("running_shoes")
files[shoesEntryPath] = delegateEntry
local run3 = loadEntry()
local running3 = run3.loader.exports.voxel_run_bridge.running
T.eq(running3 and running3.provider, "running_shoes",
  "enabling standalone Running Shoes delegates the feature")
T.eq(running3 and running3.priorDispatcherSuspended, true,
  "delegation suspends the retained camera dispatcher")
T.eq(tickRecord.state.active, false,
  "delegated entry leaves the shared bob state inactive")
local delegatedPlayer = {
  px = 0, py = 0, stepFrames = 16, moving = false,
  inputLocked = false, surfing = false, lift = 9,
}
local delegatedBaseBefore = baseCalls
FreeMove.tick({ player = delegatedPlayer })
T.eq(baseCalls, delegatedBaseBefore + 1,
  "delegated camera dispatcher reaches the voxel tick once")
T.eq(FirstPerson.frame(delegatedPlayer), 9,
  "delegated camera dispatcher adds no head bob")

files[shoesManifestPath] = nil
files[shoesEntryPath] = nil
local run4 = loadEntry()
local tickRecord4 = rawget(FreeMove, "_scottsTweaksRunningBobTick")
T.eq(tickRecord4, tickRecord,
  "removing standalone Running Shoes resumes the retained dispatcher")
T.eq(tickRecord4 and tickRecord4.state.active, true,
  "provider removal reactivates the shared bob state")
T.eq(tickRecord4 and tickRecord4.wrapper, tickWrapper,
  "provider transition never stacks the camera wrapper")
local priorLiveLoader = Game.mods
Game.mods = { exports = {} }
local removedPlayer = {
  px = 0, py = 0, stepFrames = 16, moving = false,
  inputLocked = false, surfing = false, lift = 11,
}
FreeMove.tick({ player = removedPlayer })
T.eq(FirstPerson.frame(removedPlayer), 11,
  "retained camera dispatcher is inert when Tweaks leaves the live Loader")
T.eq(tickRecord4.state.offset, 0,
  "an absent live generation clears retained camera offset")
Game.mods = priorLiveLoader

run4.release()
run3.release()
run2.release()
run1.release()
package.loaded["tests.scotts_tweaks_shared_voxel"] = nil
package.preload["tests.scotts_tweaks_shared_voxel"] = nil
T.finish("Scott's Tweaks running hot reload/provider transition")
