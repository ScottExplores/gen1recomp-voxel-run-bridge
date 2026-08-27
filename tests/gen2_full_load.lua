-- ROM-free production-loader smoke for the unified Gen 2 profile.
--
-- Run from any directory with the current Gen1Recomp checkout available:
--   luajit tests/gen2_full_load.lua <mod-root> <engine-root> [file-list]
-- Before the release manifest is bumped, append `force-gen2-manifest` to test
-- the production source with only the staged in-memory manifest broadened.

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local listPath
local forceManifest = false
local gameVersion = "gold"
for index = 3, #argv do
  local value = argv[index]
  if value == "force-gen2-manifest" then
    forceManifest = true
  elseif value == "gold" or value == "silver" or value == "crystal" then
    gameVersion = value
  elseif value and value ~= "" then
    listPath = value
  end
end

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local prefix = "mods/voxel_run_bridge/"

local function slurp(path)
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local relativeFiles = {}
if listPath then
  for relative in io.lines(listPath) do relativeFiles[#relativeFiles + 1] = relative end
else
  local command = 'git -C "' .. sourceRoot:gsub('"', '\\"')
    .. '" ls-files --cached --others --exclude-standard'
  local pipe = assert(io.popen(command, "r"), "cannot enumerate mod files")
  for relative in pipe:lines() do relativeFiles[#relativeFiles + 1] = relative end
  local closed = pipe:close()
  assert(closed ~= nil, "git could not enumerate mod files")
end

local modFiles, count = {}, 0
for _, relative in ipairs(relativeFiles) do
  relative = relative:gsub("\\", "/")
  if relative ~= "" then
    local body = slurp(sourceRoot .. "/" .. relative)
    if forceManifest and relative == "manifest.json" then
      body = body:gsub('"games"%s*:%s*%[%s*"gen1"%s*%]',
        '"games": ["gen1", "gen2"]')
    end
    modFiles[prefix .. relative] = body
    count = count + 1
  end
end
T.check(count > 80, "complete unified package was staged")

local priorVersion = GameVersion.get()
GameVersion.set(gameVersion)
local okLoad, runOrError = pcall(function()
  return T.sdk.loadMod("mods/voxel_run_bridge", {
    data = require("tests.modkit.fixtures").fresh(),
    fs = T.sdk.memfs(modFiles),
    generation = 2,
  })
end)
GameVersion.set(priorVersion)
T.check(okLoad, "Gen 2 loader did not raise: " .. tostring(runOrError))
if not okLoad then T.finish("Scott's Tweaks Gen 2 full load") return end

local run = runOrError
T.check(run.mod ~= nil, "Gen 2 loader selected Scott's Tweaks")
T.eq(GameVersion.get(), priorVersion,
  "test restored the process game version after " .. gameVersion .. " load")
T.eq(run.mod and run.mod.state, "loaded", "Scott's Tweaks reaches loaded state")
T.eq(#run.errors, 0, "Gen 2 load has no loader errors")

local exports = run.loader.exports.voxel_run_bridge or {}
T.eq(exports.runtime and exports.runtime.generation, 2,
  "entry routed to the Gen 2 profile")
T.eq(exports.runtime and exports.runtime.onePackage, true,
  "Gen 2 profile reports the single-package design")
T.eq(exports.status and exports.status.mode, "native_gen2_profile",
  "Gen 2 status names the native profile")

local loaded = {}
for _, id in ipairs((exports.vendored and exports.vendored.loaded) or {}) do
  loaded[id] = true
end
for _, id in ipairs({
  "overworld_wild_spawns",
  "free_fly",
  "choose_lead",
  "unique_menu_icons",
  "crystal_animated_sprites_with_shiny_visuals",
}) do
  T.eq(loaded[id], true, "safe Gen 2 vendor is active: " .. id)
end
for _, id in ipairs({
  "modern_bag_ui", "all_pokemon_catchable_151_mod", "Dynamic_Scaling",
}) do
  T.eq(loaded[id], nil, "Kanto-only vendor stayed dormant: " .. id)
end

T.check(type(exports.running) == "table" and exports.running.installed == true,
  "renderer-neutral B-button running installed")
T.eq(exports.experience and exports.experience.generation, 2,
  "EXP modes use the Gen 2 battle path")
T.eq(exports.experience and exports.experience.item, "EXP_SHARE",
  "EXP modes recognize Gen 2's native item identity")
T.check(type(exports.thorDualScreen) == "table"
    and exports.thorDualScreen.controllerOnly == true
    and type(exports.thorDualScreen.getStatus) == "function",
  "generation-aware Thor presenter installed for native Gen 2 menus")

-- The Kanto emulations and story/content mutations must not merely be
-- disabled; their installers must never have run on this branch.
for _, key in ipairs({
  "gen2Ui", "tweaksMenu", "trainerForfeit", "oakSpareStarter",
  "tradeStone", "gappedLand", "hmWithoutBadges",
}) do
  T.eq(exports[key], nil, "Gen 1 installer stayed dormant: " .. key)
end
T.eq(exports.fusedRenderer and exports.fusedRenderer.provider,
  "SCOTTS_GEN2_VOXEL",
  "companion alias points at the Gen 2 terrain provider, not Battle Art")
T.eq(exports.fusedRenderer and exports.fusedRenderer.terrainOnly, true,
  "companion alias excludes Stadium models and battles")
T.eq(run.data.items and run.data.items.SCOTTS_EXP_SHARE, nil,
  "synthetic Gen 1 EXP.SHARE was not registered in Gen 2")
T.eq(run.data.items and run.data.items.SCOTTS_TRADE_STONE, nil,
  "Trade Stone was not registered in Gen 2")

local schemaByKey = {}
for _, row in ipairs(run.loader.optionSchemas.voxel_run_bridge or {}) do
  schemaByKey[row.key] = row
end
for _, key in ipairs({
  "free_fly_without_badges", "free_fly_cockpit", "experience_mode",
  "running_enabled", "running_speed", "running_view_bob",
  "running_bob_intensity", "dual_screen", "daytime", "moonPhase",
  "ledgeDepth",
}) do
  T.check(type(schemaByKey[key]) == "table",
    "Gen 2 schema contains " .. key)
end
for _, key in ipairs({
  "bag_pockets", "gen2_menus", "hm_without_badges", "gapped_land",
  "trainer_forfeit_enabled", "trainer_rematches", "oak_spare_starter",
}) do
  T.eq(schemaByKey[key], nil, "Gen 2 schema omits Kanto-only " .. key)
end

run.release()
T.finish("Scott's Tweaks Gen 2 full load")
