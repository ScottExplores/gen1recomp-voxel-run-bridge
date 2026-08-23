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
local VoxelState = { level = 6, FP_LEVEL = 6, TP_LEVEL = 7 }
function VoxelState.isFirstPerson(level)
  return (level or VoxelState.level) == VoxelState.FP_LEVEL
end
-- Load the shipped camera module so the trainer-focus assertions exercise its
-- real attitude helper. Its renderer-only dependencies remain cold here, and
-- frame() is replaced with the tiny numeric fixture the bob dispatcher needs.
local firstPersonDeps = {
  Mat4 = {}, VoxelState = VoxelState,
  Voxel3D = { available = function() return true end },
  Jump = {}, WorldCurve = {}, ThirdPerson = {},
}
local FirstPerson = assert(loadfile(sourceRoot .. "/lib/FirstPerson.lua"))({
  require = function(name) return firstPersonDeps[name] end,
})
function FirstPerson.frame(me) return me.lift or 0 end
local sharedVoxel = {
  FreeMove = FreeMove, FirstPerson = FirstPerson, VoxelState = VoxelState,
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
  -- The fused renderer's asset transform is validated by the loader before

  -- the entry runs, so the fixture must carry it even when the vendored lib/

  -- tree is absent and installBattleArt stands down.

  "transform_birds.lua",

  "modules/settings.lua", "modules/migrations.lua",
  "modules/trainer_forfeit.lua", "modules/trainer_dialogue.lua",
  "modules/oak_spare_starter.lua", "modules/running.lua",
  "modules/option_screen.lua", "modules/tweaks_menu.lua",
  "modules/thor_dual_screen.lua",
  "modules/gen2_ui.lua",
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

-- The saved raw value is deliberately retained for compatibility, but the
-- player-facing scale makes that historical 0.25 effect the 1X reference and
-- offers several genuinely gentler steps below it.
local runningSchema = run1.loader.optionSchemas.voxel_run_bridge
local bobSchema
for _, row in ipairs(runningSchema or {}) do
  if row.key == "running_bob_intensity" then bobSchema = row break end
end
T.check(type(bobSchema) == "table", "head-bob intensity stays in the schema")
T.eq(bobSchema and bobSchema.default, 0.125,
  "new installs default to a gentle 0.5X head bob")
T.eq(bobSchema and bobSchema.choices[1][1], "0.25X",
  "head bob offers a quarter-strength setting")
T.eq(bobSchema and bobSchema.choices[1][2], 0.0625,
  "quarter strength is meaningfully below the historical raw 0.25")
T.eq(bobSchema and bobSchema.choices[6][1], "1X",
  "the historical strength has the simple 1X label")
T.eq(bobSchema and bobSchema.choices[6][2], 0.25,
  "1X preserves existing saves at raw 0.25")

-- A sight trainer owns the approach, but not the player's first-person head.
-- The event fires before dialogue is pushed, so the camera and the staged-
-- battle seed must both turn now without changing either actor's facing.
local RuntimeFocus = require("src.mods.Runtime")
local GameFocus = require("src.core.Game")
local focusPlayer = {
  px = 16, py = 32, cellX = 1, cellY = 2, facing = "up",
}
local focusNpc = {
  id = "TRAINER_FOCUS", px = 48, py = 32, cellX = 3, cellY = 2,
  facing = "left",
}
GameFocus.overworld = { engaging = true, player = focusPlayer }
FirstPerson.yaw, FirstPerson.pitch = -0.75, 0.6
FirstPerson.lastYaw, FirstPerson.lastPitch = nil, nil
RuntimeFocus.emit("world.trainer_engaged", { npc = focusNpc })
local focusStatus = run1.loader.exports.voxel_run_bridge.running.trainerFocus
T.eq(focusStatus and focusStatus.active, true,
  "trainer camera focus installs beside the first-person renderer")
T.eq(focusStatus and focusStatus.reason, "first_person_sight_focus",
  "trainer focus reports its narrow sight-path ownership")
T.check(math.abs(FirstPerson.yaw - math.pi / 2) < 0.00001,
  "first-person sight rotates east toward the approaching trainer")
T.eq(FirstPerson.pitch, FirstPerson.PITCH_DEFAULT,
  "trainer focus restores a readable neutral pitch")
T.eq(FirstPerson.lastYaw, FirstPerson.yaw,
  "trainer focus seeds the staged battle with the corrected yaw")
T.eq(FirstPerson.lastPitch, FirstPerson.pitch,
  "trainer focus seeds the staged battle with the corrected pitch")
T.eq(focusPlayer.facing, "up",
  "trainer focus does not turn the player body or script state")
T.eq(focusNpc.facing, "left",
  "trainer focus does not disturb the trainer approach facing")
T.eq(focusStatus and focusStatus.focusCount, 1,
  "one trainer engagement focuses exactly once in one live generation")

VoxelState.level = VoxelState.TP_LEVEL
FirstPerson.yaw = -0.4
RuntimeFocus.emit("world.trainer_engaged", { npc = focusNpc })
T.eq(FirstPerson.yaw, -0.4,
  "third-person view preserves its player-controlled camera")
T.eq(focusStatus and focusStatus.focusCount, 1,
  "third-person engagements do not count as first-person focus")

VoxelState.level = VoxelState.FP_LEVEL
GameFocus.overworld.engaging = false
FirstPerson.yaw = 0.35
RuntimeFocus.emit("world.trainer_engaged", { npc = focusNpc })
T.eq(FirstPerson.yaw, 0.35,
  "A-button and scripted trainer dialogue preserve their camera choreography")
T.eq(focusStatus and focusStatus.focusCount, 1,
  "non-sight trainer paths do not trigger the focus adapter")

-- Gen 2 sends the sight direction before the walk-up rather than exposing
-- Gen 1's OverworldState.engaging flag. It supplies NPC px/py/cell fields but
-- no world/player reference, so the exact trainer->player direction is the
-- authoritative bearing (reversed here to player->trainer).
GameFocus.overworld = nil
FirstPerson.yaw = 0.2
RuntimeFocus.emit("world.trainer_engaged", {
  npc = focusNpc, sight = { distance = 3, dir = "down" },
})
T.check(math.abs(math.abs(FirstPerson.yaw) - math.pi) < 0.00001,
  "Gen 2 sight payload turns the first-person camera back toward its trainer")
T.eq(focusStatus and focusStatus.focusCount, 2,
  "Gen 2's explicit sight path triggers one camera focus")
T.eq(focusPlayer.facing, "up",
  "Gen 2 sight direction never mutates a player facing")
GameFocus.overworld = nil

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

-- Exercise the engine's real grid path. Player:tryMove sets moving=true
-- before movement.speed is called, which is the ordering that used to make
-- every 2D/orbital-view step reject the held B button.
local Runtime = require("src.mods.Runtime")
local Data = T.fixtures.fresh()
local Collision = require("src.world.Collision")
local Player = require("src.world.Player")
Collision.load(Data)
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }
local openMap = {
  def = { tileset = "FIX_OUT" },
  inBounds = function(_, x, y)
    return x >= 0 and y >= 0 and x < 20 and y < 20
  end,
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
  cellTile = function() return 0 end,
}
local gridPlayer = Player.new(Data, 5, 5, "down")
T.eq(gridPlayer:tryMove("down", openMap, {}), "moved",
  "held B starts a real grid step")
T.eq(gridPlayer.stepFramesCur, 11,
  "held B shortens a 2D grid step from 16 to 11 frames")
local manualTicks = 0
while gridPlayer.moving and manualTicks < 30 do
  manualTicks = manualTicks + 1
  gridPlayer:update()
end
T.eq(manualTicks, 11, "the real running step lands in 11 updates")

-- ScriptRunner emits this before it queues/resumes its movement. The handler
-- must restore Scott's retained duration so direct scripted moves stay in
-- lockstep with their 16-frame NPC escorts.
Runtime.emit("script.started", {
  ctx = { game = Game, overworld = { player = gridPlayer } },
})
T.eq(gridPlayer.stepFramesCur, 16,
  "script start restores Scott's completed run to vanilla duration")
gridPlayer.targetX, gridPlayer.targetY = gridPlayer.cellX, gridPlayer.cellY + 1
gridPlayer.moving = true
gridPlayer.progress = 0
local scriptedTicks = 0
while gridPlayer.moving and scriptedTicks < 30 do
  scriptedTicks = scriptedTicks + 1
  gridPlayer:update()
end
T.eq(scriptedTicks, 16,
  "a scripted step after running still takes the vanilla 16 updates")

-- The ordinary idle boundary provides the same restoration even when no
-- script begins immediately after the run.
T.eq(gridPlayer:tryMove("down", openMap, {}), "moved",
  "a second held-B grid step starts")
while gridPlayer.moving do gridPlayer:update() end
Runtime.call("input.step", function() end,
  { overworld = { player = gridPlayer } }, 1 / 60)
T.eq(gridPlayer.stepFramesCur, 16,
  "the next idle input boundary restores the vanilla duration")

local shoesManifestPath = "mods/running_shoes/manifest.json"
local shoesEntryPath = "mods/running_shoes/main.lua"
files[shoesManifestPath] = delegateManifest("running_shoes")
files[shoesEntryPath] = delegateEntry
local run3 = loadEntry()
local running3 = run3.loader.exports.voxel_run_bridge.running
-- Running Shoes takes the run multiplier so it is never applied twice, but it
-- ships no camera bob, so the bob stays live. Bundling Running Shoes used to
-- take the bob down with the speed hook and left first-person running flat.
T.eq(running3 and running3.speedProvider, "running_shoes",
  "enabling standalone Running Shoes delegates run speed")
T.eq(running3 and running3.speedDelegated, true,
  "run speed is delegated")
T.eq(running3 and running3.installed, true,
  "the camera bob stays installed")
T.eq(tickRecord.state.active, true,
  "the shared bob state stays active alongside Running Shoes")
local delegatedPlayer = {
  px = 0, py = 0, stepFrames = 16, moving = false,
  inputLocked = false, surfing = false, lift = 9,
}
local delegatedBaseBefore = baseCalls
FreeMove.tick({ player = delegatedPlayer })
T.eq(baseCalls, delegatedBaseBefore + 1,
  "delegated camera dispatcher reaches the voxel tick once")
T.check(FirstPerson.frame(delegatedPlayer) ~= 9,
  "camera dispatcher still applies the head bob under Running Shoes")

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
