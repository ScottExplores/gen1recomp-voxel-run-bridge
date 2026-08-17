-- ROM-free production-loader integration for Pokemon Final voxel running.
-- Run with:
--   luajit tests/voxel_full_load.lua <mod-root> <engine-root>

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local freeFlyRoot = argv[3]

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
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

local function readFrom(root, relative)
  local path = root .. "/" .. relative
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local function readOptional(root, relative)
  local path = root .. "/" .. relative
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

local scottPrefix = "mods/voxel_run_bridge/"
local pokemonPrefix = "mods/POKEMON_FINAL/"
local shoesPrefix = "mods/running_shoes/"

local pokemonManifest = [[{
  "id": "POKEMON_FINAL",
  "name": "Pokemon Final Test Double",
  "version": "1.8.1-scott.3",
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

local pokemonEntry = [[return function(mod)
  local FreeMove = { WALK = 1, BIKE = 2 }
  FreeMove.tick = function()
    mod.exports.seenWalk = FreeMove.WALK
    mod.exports.seenBike = FreeMove.BIKE
    return "provider-tick", 42
  end
  local lib = {
    require = function(name)
      if name == "FreeMove" then return FreeMove end
      error("unknown Pokemon Final module: " .. tostring(name))
    end,
  }
  mod.exports.lib = lib
  mod.exports.testFreeMove = FreeMove
end]]

local shoesManifest = [[{
  "id": "running_shoes",
  "name": "Running Shoes Test Double",
  "version": "1.4.1",
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

local shoesEntry = [[return function(mod)
  mod.exports.calls = 0
  mod.hooks:wrap("movement.speed", function(nextFn, frames, ctx)
    mod.exports.calls = mod.exports.calls + 1
    mod.exports.lastContext = ctx
    local base = tonumber(nextFn(frames, ctx)) or tonumber(frames) or 16
    local input = ctx and ctx.input
    if input and input.isDown and input:isDown("b") then
      return math.max(1, math.floor(base / 2))
    end
    return base
  end)
end]]

local files = {
  [scottPrefix .. "manifest.json"] = read("manifest.json"),
  [scottPrefix .. "main.lua"] = read("main.lua"),
  [pokemonPrefix .. "manifest.json"] = pokemonManifest,
  [pokemonPrefix .. "main.lua"] = pokemonEntry,
  [shoesPrefix .. "manifest.json"] = shoesManifest,
  [shoesPrefix .. "main.lua"] = shoesEntry,
}
for _, relative in ipairs({
  "modules/settings.lua", "modules/migrations.lua",
  "modules/trainer_forfeit.lua", "modules/trainer_dialogue.lua",
  "modules/oak_spare_starter.lua", "modules/running.lua",
  "modules/option_screen.lua", "modules/tweaks_menu.lua",
  "modules/thor_dual_screen.lua",
  "modules/gen2_ui.lua",
}) do
  files[scottPrefix .. relative] = read(relative)
end

local expectedFreeFlyVersion
if freeFlyRoot then
  local freeFlyPrefix = "mods/free_fly/"
  expectedFreeFlyVersion = readFrom(freeFlyRoot, "manifest.json")
    :match('"version"%s*:%s*"([^"]+)"')
  for _, relative in ipairs({
    "manifest.json",
    "main.lua",
    "lib/shared/skylib.lua",
  }) do
    files[freeFlyPrefix .. relative] = readFrom(freeFlyRoot, relative)
  end
  -- Free Fly 1.6+ split compatibility helpers out of main.lua. Older 1.5
  -- packages do not carry these files, so include each one only when present.
  for _, relative in ipairs({
    "lib/FlightInput.lua",
    "lib/FollowerLanding.lua",
    "lib/VoxelProvider.lua",
  }) do
    local body = readOptional(freeFlyRoot, relative)
    if body then files[freeFlyPrefix .. relative] = body end
  end
end

local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs(files),
  generation = 1,
})

T.eq(#run.errors, 0, "integration fixture loads through the API-2 loader")

local orderAt = {}
for index, id in ipairs(run.loader.order or {}) do orderAt[id] = index end
T.check(orderAt.POKEMON_FINAL ~= nil, "Pokemon Final appears in load order")
T.check(orderAt.running_shoes ~= nil, "Running Shoes appears in load order")
T.check(orderAt.voxel_run_bridge ~= nil, "Scott's Tweaks appears in load order")
T.check(orderAt.POKEMON_FINAL < orderAt.voxel_run_bridge,
  "Pokemon Final loads before its optional bridge consumer")
T.check(orderAt.running_shoes < orderAt.voxel_run_bridge,
  "movement.speed producer loads before its optional bridge consumer")

local scott = run.loader.exports.voxel_run_bridge
local pokemon = run.loader.exports.POKEMON_FINAL
local shoes = run.loader.exports.running_shoes
T.eq(scott.status and scott.status.active, true,
  "Scott's voxel bridge activates")
T.eq(scott.status and scott.status.voxel, "POKEMON_FINAL",
  "Scott's bridge selects Pokemon Final")
T.check(type(pokemon and pokemon.testFreeMove) == "table",
  "Pokemon Final exports its FreeMove table")
T.check(type(shoes) == "table", "movement.speed producer exports are live")

if freeFlyRoot then
  local freeFly = run.loader.exports.free_fly
  T.check(type(freeFly and freeFly.isFlying) == "function",
    "real Free Fly package publishes isFlying")
  local badgesOption
  for _, row in ipairs(run.loader.optionSchemas.free_fly or {}) do
    if row.key == "badges" then badgesOption = row break end
  end
  T.check(type(badgesOption) == "table" and badgesOption.type == "toggle",
    "real Free Fly package registers the badges toggle")
  T.eq(run.loader.modOptions.free_fly.badges, false,
    "Scott's Tweaks disables the real Free Fly badge gate live")
  local active, reason, version = scott.freeFlyBadgeBypass()
  T.eq(active, true, "real Free Fly adapter reports active")
  T.eq(reason, "badges_runtime_override",
    "real Free Fly adapter reports its live override")
  T.eq(version, expectedFreeFlyVersion,
    "real Free Fly adapter reports detected version")
end

local Game = require("src.core.Game")
Game.save = { onBike = false }
Game.input = {
  held = true,
  isDown = function(self, key) return key == "b" and self.held end,
}

local player = {
  stepFrames = 16,
  bikeStepFrames = 8,
  surfing = false,
  moving = false,
  inputLocked = false,
}
local first, second = pokemon.testFreeMove.tick({ player = player })
T.eq(first, "provider-tick", "wrapped FreeMove preserves first return value")
T.eq(second, 42, "wrapped FreeMove preserves second return value")
T.eq(pokemon.seenWalk, 2,
  "held B applies the Running Shoes 2x multiplier inside FreeMove")
T.eq(pokemon.seenBike, 2, "foot running leaves bike speed untouched")
T.eq(pokemon.testFreeMove.WALK, 1,
  "FreeMove walk constant is restored after the tick")
T.eq(pokemon.testFreeMove.BIKE, 2,
  "FreeMove bike constant is restored after the tick")
T.eq(shoes.calls, 1, "movement.speed producer is sampled once")
T.eq(shoes.lastContext and shoes.lastContext.freeMove, true,
  "producer receives free-movement context")
T.eq(shoes.lastContext and shoes.lastContext.continuous, true,
  "producer receives continuous-movement context")

Game.input.held = false
pokemon.testFreeMove.tick({ player = player })
T.eq(pokemon.seenWalk, 1, "released B keeps Pokemon Final at walking speed")
T.eq(pokemon.testFreeMove.WALK, 1,
  "unboosted FreeMove tick also leaves its constant unchanged")
T.eq(shoes.calls, 2, "producer is sampled once per eligible FreeMove tick")

run.release()
T.finish("Scott's Tweaks Pokemon Final voxel full load")
