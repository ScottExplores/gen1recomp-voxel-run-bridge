-- Production-loader check that the vendored Scott's Battle Art Kanto renderer
-- actually initialises inside Scott's Tweaks.
--
-- The memfs fixtures elsewhere deliberately carry only the Tweaks modules, so
-- installBattleArt stands down there and the renderer is never exercised. This
-- one feeds the loader the real vendored lib/ and data/ tree and asserts the
-- fused renderer reports itself installed.
--
--   luajit tests/fused_renderer_load.lua <mod-root> <engine-root> <file-list>

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local listPath = assert(argv[3], "file list required")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.modkit")

local prefix = "mods/voxel_run_bridge/"

local function slurp(path)
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local modFiles = {}
local count = 0
for relative in io.lines(listPath) do
  if relative ~= "" then
    modFiles[prefix .. relative] = slurp(sourceRoot .. "/" .. relative)
    count = count + 1
  end
end
T.check(count > 80, "vendored code tree was staged (" .. count .. " files)")
T.check(modFiles[prefix .. "battle_art_main.lua"] ~= nil, "renderer entry staged")

local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs(modFiles),
  generation = 1,
})

-- All Pokemon Catchable 151 repatches real Kanto encounter tables, and the
-- modkit fixture only defines synthetic species (FIXMON_A/B/C) and maps, so
-- every one of its species references reads as dangling here. That is a gap in
-- the harness, not in the mod: assert the shape of the errors rather than
-- hiding them, so any other class of load failure still fails this test.
local dexGap, other = 0, {}
for _, e in ipairs(run.errors) do
  local text = type(e) == "table" and (e.message or e.text or "") or tostring(e)
  if text:find("unresolved reference to pokemon", 1, true)
     or text:find("unresolved reference to maps", 1, true) then
    dexGap = dexGap + 1
  else
    other[#other + 1] = text
  end
end
T.eq(#other, 0, "no load errors beyond the fixture dex gap: " .. table.concat(other, " | "):sub(1, 300))
T.check(dexGap > 0, "fixture dex gap accounted for (" .. dexGap .. " references)")
T.check(run.mod ~= nil, "loader selected the fused mod")
T.eq(run.mod and run.mod.manifest.id, "voxel_run_bridge", "updater identity retained")

-- Never declare a conflict with a mod this one bundles. Loader:_enforceConflicts
-- fails the DECLARING mod, so a player who still has the standalone copy
-- installed loses Scott's Tweaks entirely rather than the duplicate. Coexistence
-- is handled at runtime instead: the fused renderer stands down and the vendor
-- host skips any mod with a standalone copy.
for _, spec in ipairs((run.mod and run.mod.manifest.conflictSpecs) or {}) do
  T.check(spec.id ~= "BATTLE_ART_VOXEL_FORK",
    "no self-defeating conflict with the bundled renderer")
end
T.eq(#((run.mod and run.mod.manifest.conflictSpecs) or {}), 0,
  "no manifest conflicts: coexistence is resolved at runtime")

local exports = run.loader.exports.voxel_run_bridge
T.check(type(exports) == "table", "fused mod publishes exports")
T.check(type(exports.fusedRenderer) == "table", "fused renderer reported its state")
T.eq(exports.fusedRenderer and exports.fusedRenderer.installed, true,
  "vendored Battle Art renderer installed")
T.check(type(exports.lib) == "table", "renderer published its module table")
T.check(type(exports.lib and exports.lib.require) == "function",
  "renderer module loader is available to companion adapters")
T.eq(exports.version, "1.9.3", "vendored renderer reports its own version")

-- Settings layout: SIMPLE is the everyday set, ALL adds the renderer tuning
-- pages back, and no setting is dropped by either.
local sm = exports.settingsMenu
T.check(type(sm) == "table", "settings menu exported")

-- The renderer must see the bundled sprite pack. It asks the engine for
-- companions by id, and the engine cannot see a bundled mod, so without the
-- hosted handle it concluded Crystal was absent while Crystal was running and
-- already owned sprite drawing -- which left no Pokemon drawn anywhere.
local SpriteMenu = exports.lib.require("SpriteMenu")
local spriteMenu = SpriteMenu.new()
T.check(spriteMenu:crystalHandle() ~= nil,
  "the renderer can see the bundled Crystal sprite pack")
T.check(spriteMenu:crystalReady(), "bundled Crystal reports ready")
T.eq(sm.activePack and sm.activePack(), "crystal", "Crystal is the active sprite pack")
local cats = {}
for _, c in ipairs(sm and sm.categories or {}) do cats[c.id] = c end
for _, id in ipairs({ "quick", "world", "player", "sprites", "battles" }) do
  T.check(cats[id] ~= nil and not cats[id].advancedOnly,
    "everyday category present in SIMPLE: " .. id)
end
for _, id in ipairs({ "views", "advanced" }) do
  T.check(cats[id] ~= nil and cats[id].advancedOnly == true,
    "tuning category is hidden under SIMPLE: " .. id)
end
T.eq(cats.world and cats.world.label, "OPEN WORLD", "world screen is named plainly")
T.check(sm and sm.screenIds and sm.screenIds.player ~= nil, "player screen registered")

local cov = sm and sm.coverage and sm.coverage()
T.check(type(cov) == "table", "settings coverage readable")
T.eq(cov and cov.duplicates, 0, "no setting appears in two categories")
local playerKeys = {}
for _, k in ipairs(cov and cov.categories and cov.categories.player or {}) do
  playerKeys[k] = true
end
for _, k in ipairs({ "playerView", "frontFlip", "backPlacement" }) do
  T.check(playerKeys[k], "front/back player control lives on the player screen: " .. k)
end

-- Day/night: the dial is unchanged, only the rate, so 1 HOUR is three times
-- the 20 MIN period rather than a second set of timings.
local DayNight = exports.lib.require("DayNight")
T.eq(DayNight.PERIOD and DayNight.PERIOD.hour, 3600, "1 HOUR is a real hour")
T.eq(DayNight.PERIOD and DayNight.PERIOD.cycle, 1200, "20 MIN period unchanged")
T.eq(DayNight.CYCLE, 1200, "dial width unchanged")

local vend = exports.vendored
T.check(type(vend) == "table", "vendor host reported status")
local loadedSet = {}
for _, id in ipairs(vend and vend.loaded or {}) do loadedSet[id] = true end
for _, id in ipairs({
  "overworld_wild_spawns", "free_fly", "choose_lead",
  "all_pokemon_catchable_151_mod", "unique_menu_icons", "Dynamic_Scaling",
  "crystal_animated_sprites_with_shiny_visuals",
}) do
  T.check(loadedSet[id], "bundled mod loaded: " .. id
    .. (vend and vend.failed and vend.failed[id] and (" -- " .. tostring(vend.failed[id])) or ""))
end
T.eq(exports.freeFlyCockpitControl
    and exports.freeFlyCockpitControl.active, true,
  "bundled Free Fly 1.8.0 receives the cockpit presentation control")
T.eq(exports.freeFlyCockpitControl
    and exports.freeFlyCockpitControl.version, "1.8.0",
  "cockpit presentation control reports the bundled Free Fly version")

-- API-2 Loader publishes only the consolidated id. Hosted capability lookups
-- must still connect Wilds and Free Fly to the real fused providers, without
-- manufacturing historical export aliases.
T.eq(run.loader.exports.overworld_wild_spawns, nil,
  "fused Loader has no historical Wilds export alias")
T.eq(run.loader.exports.free_fly, nil,
  "fused Loader has no historical Free Fly export alias")
do
  local fusedHost = exports.vendorHost
  local bundledWildHandle = fusedHost and fusedHost.loaded
    and fusedHost.loaded.overworld_wild_spawns
  local bundledWildExports = bundledWildHandle and bundledWildHandle.exports
  local bundledWildV = bundledWildExports and bundledWildExports.lib
  local bundledWildMod = bundledWildV and bundledWildV.mod
  local ownRendererHandle = bundledWildMod and bundledWildMod.find
    and bundledWildMod.find(bundledWildMod, "BATTLE_ART_VOXEL_FORK")
  T.eq(ownRendererHandle and ownRendererHandle.exports, exports,
    "bundled Wilds resolves the installed fused renderer root")
  local VariableSize = bundledWildV and bundledWildV.require("variable_size")
  if VariableSize and VariableSize.clearCaches then VariableSize.clearCaches() end
  local selectedVoxel, selectedVoxelId
  if VariableSize then
    selectedVoxel, selectedVoxelId = VariableSize.findVoxelRenderer(bundledWildMod)
  end
  T.eq(selectedVoxel and selectedVoxel.exports, ownRendererHandle.exports,
    "Wilds VariableSize selects the fused renderer capability")
  T.eq(selectedVoxelId, "BATTLE_ART_VOXEL_FORK",
    "Wilds VariableSize reports the fused renderer id")
  local ownVoxelScene = exports.lib.require("VoxelScene")
  local liveVoxelAdapter = bundledWildExports and bundledWildExports.logic
    and bundledWildExports.logic.voxel
  T.check(liveVoxelAdapter and liveVoxelAdapter:refreshPresence({ force = true }),
    "Wilds VoxelAdapter detects the fused renderer")
  T.eq(liveVoxelAdapter and liveVoxelAdapter.present, true,
    "Wilds VoxelAdapter records fused renderer presence")
  T.eq(ownVoxelScene and ownVoxelScene._owwildRenderWrapped, true,
    "Wilds hooks the actual fused VoxelScene")

  local skyChunk = assert(loadstring(modFiles[
    prefix .. "vendor/free_fly/lib/shared/skylib.lua"],
    "@fused_free_fly_skylib.lua"))
  local FusedSky = skyChunk()
  local EngineGame = require("src.core.Game")
  EngineGame.mods = run.loader
  local skyWildsExports, skyWildsSource = FusedSky.spriteSourceExports(
    EngineGame, "overworld_wild_spawns")
  T.eq(skyWildsExports, bundledWildExports,
    "bundled Free Fly selects Wilds' real render exports")
  T.eq(skyWildsExports and skyWildsExports.render,
    bundledWildExports and bundledWildExports.render,
    "bundled Free Fly receives the Wilds sprite pipeline")
  T.eq(skyWildsSource, "vendor_host",
    "Free Fly resolves Wilds through VendorHost without an export alias")
end

-- Real fused ownership: Loader publishes only voxel_run_bridge, never the
-- renderer's historical standalone id. Crystal must still resolve the root
-- Battle Art capability, register its authored-alpha predicate with
-- BattlePics, and recognise the staged battle through that same module lib.
T.eq(run.loader.exports.BATTLE_ART_VOXEL_FORK, nil,
  "fused Loader has no historical Battle Art export alias")
local crystalHandle = exports.vendorHost and exports.vendorHost.loaded
  and exports.vendorHost.loaded.crystal_animated_sprites_with_shiny_visuals
local crystalExports = crystalHandle and crystalHandle.exports
T.check(type(crystalExports) == "table", "hosted Crystal exports are available")
T.check(type(crystalExports and crystalExports.voxelContext) == "function",
  "hosted Crystal publishes its renderer-context probe")
T.check(type(crystalExports and crystalExports.refreshVoxelPaper) == "function",
  "hosted Crystal publishes its transparency-registration refresh")
local crystalGame = require("src.core.Game")
crystalGame.mods = run.loader
local crystalLoader = crystalGame.mods
local BattlePics = exports.lib.require("BattlePics")
local crystalImage = {
  getFilename = function()
    return "mods/voxel_run_bridge/vendor/crystal/assets/front/normal/1/001.png"
  end,
}
T.check(crystalExports and crystalExports.isCrystalImage(crystalImage),
  "hosted Crystal recognises its rooted fused asset path")
BattlePics.unregisterTransparentProvider(
  "crystal_animated_sprites_with_shiny_visuals")
T.eq(BattlePics.preservesAuthoredTransparency(crystalImage), false,
  "fused transparency proof begins without a retained provider")
T.check(crystalExports.refreshVoxelPaper(),
  "Crystal resolves voxel_run_bridge and refreshes its provider")
T.check(BattlePics.preservesAuthoredTransparency(crystalImage),
  "fused Crystal registers authored transparency without a standalone alias")
local OverworldBattle = exports.lib.require("OverworldBattle")
local originalBattleProbe = OverworldBattle.battle
local activeCrystalBattle = {}
OverworldBattle.battle = function() return activeCrystalBattle end
local okCrystalContext, inCrystalContext = pcall(
  crystalExports.voxelContext, activeCrystalBattle)
OverworldBattle.battle = originalBattleProbe
T.check(okCrystalContext and inCrystalContext == true,
  "hosted Crystal resolves the fused root OverworldBattle capability")
T.eq(activeCrystalBattle.__crystalVoxel, true,
  "successful fused renderer context is cached on the active battle")
local priorStandaloneRenderer = crystalLoader and crystalLoader.exports
  and crystalLoader.exports.DRAMATIC_SHAPE
local standaloneBattle, standaloneRequireCalls = {}, 0
crystalLoader.exports.DRAMATIC_SHAPE = { lib = {
  require = function(name)
    standaloneRequireCalls = standaloneRequireCalls + 1
    if name == "OverworldBattle" then
      return { battle = function() return standaloneBattle end }
    end
    error("unexpected standalone renderer module: " .. tostring(name))
  end,
} }
local okStandaloneContext, inStandaloneContext = pcall(
  crystalExports.voxelContext, standaloneBattle)
crystalLoader.exports.DRAMATIC_SHAPE = priorStandaloneRenderer
T.check(okStandaloneContext and inStandaloneContext == true,
  "standalone Crystal still prefers a historical standalone renderer")
T.check(standaloneRequireCalls > 0,
  "historical renderer capability is consulted before the fused fallback")

-- One canonical schema: Scott's own settings, every Battle Art setting, and
-- every namespaced bundled setting survive the one final define().
local host = exports.vendorHost
local schema = run.loader.optionSchemas.voxel_run_bridge or {}
local schemaCount, schemaByKey, schemaDuplicates = {}, {}, 0
for _, row in ipairs(schema) do
  schemaCount[row.key] = (schemaCount[row.key] or 0) + 1
  schemaByKey[row.key] = row
  if schemaCount[row.key] > 1 then schemaDuplicates = schemaDuplicates + 1 end
end
T.eq(schemaDuplicates, 0, "canonical schema has no duplicate keys")
T.eq(#schema, #(exports.optionSchema or {}),
  "exported canonical schema matches the Loader schema")
local ownKeys = {
  "simple_menu", "hm_without_badges", "free_fly_without_badges",
  "free_fly_cockpit", "gapped_land", "gen2_menus",
  "experience_mode", "trainer_forfeit_enabled", "trainer_rematches",
  "trainer_adaptive_dialogue", "trainer_growth", "oak_spare_starter",
  "running_enabled", "running_speed", "running_view_bob",
  "running_bob_intensity", "dual_screen",
}
for _, key in ipairs(ownKeys) do
  T.eq(schemaCount[key], 1, "own canonical option appears once: " .. key)
end
T.eq(schemaCount.bag_pockets, nil,
  "obsolete legacy Bag switch is absent while Modern Bag owns presentation")
for _, row in ipairs(exports.battleArtOptionSchema or {}) do
  T.eq(schemaCount[row.key], 1,
    "Battle Art canonical option appears once: " .. tostring(row.key))
end
local vendorSchema = host and host:mergedSchema() or {}
for _, row in ipairs(vendorSchema) do
  T.eq(schemaCount[row.key], 1,
    "namespaced vendor option appears once: " .. tostring(row.key))
end
T.eq(#schema, #ownKeys + #(exports.battleArtOptionSchema or {}) + #vendorSchema,
  "canonical schema contains every source exactly once")
T.eq(schemaByKey.simple_menu and schemaByKey.simple_menu.default, true,
  "BASIC is the single default visibility mode")
T.eq(schemaByKey.simple_menu and schemaByKey.simple_menu.label,
  "OPTIONS SHOWN", "canonical visibility flag uses the unified UI name")
local wildPrefix = "overworld_wild_spawns:"
T.eq(schemaByKey[wildPrefix .. "enabled"]
    and schemaByKey[wildPrefix .. "enabled"].default, true,
  "visible overworld Pokemon remain enabled on new installs")
T.eq(schemaByKey[wildPrefix .. "random_encounters"]
    and schemaByKey[wildPrefix .. "random_encounters"].default, false,
  "classic random encounters default off on new installs")
T.eq(schemaByKey[wildPrefix .. "enable_hidden"]
    and schemaByKey[wildPrefix .. "enable_hidden"].default, false,
  "sprite-less hidden encounters default off on new installs")

-- Exercise the real registered screens. This proves the root, category
-- placement, footers, and Mod Manager route rather than just their exports.
local Screens = require("src.ui.Screens")
Screens.invalidate()
local stack = { values = {} }
function stack:push(value) self.values[#self.values + 1] = value end
function stack:pop() return table.remove(self.values) end
function stack:top() return self.values[#self.values] end
local writes = 0
local pressed
local onOptionsPersist
local function copyModOptions(rootOptions)
  local out = {}
  for modId, bucket in pairs(rootOptions or {}) do
    if type(bucket) == "table" then
      out[modId] = {}
      for key, value in pairs(bucket) do out[modId][key] = value end
    end
  end
  return out
end
local game = {
  data = run.data,
  save = { options = { modOptions = {} }, party = {} },
  mods = run.loader,
  stack = stack,
  input = { wasPressed = function(_, key) return key == pressed end,
            isDown = function() return false end },
  writeOptions = function(self)
    writes = writes + 1
    if onOptionsPersist then onOptionsPersist(self.save.options.modOptions) end
  end,
}
require("src.core.Game").mods = run.loader
local function buildScreen(id)
  if type(Screens.build) == "function" then return Screens.build(game, id) end
  return Screens.get(game, id).new(game)
end
local function findLabel(rows, label)
  for _, row in ipairs(rows or {}) do
    if row.label == label then return row end
  end
end
local function findIndex(rows, label)
  for index, row in ipairs(rows or {}) do
    if row.label == label then return index end
  end
end
local function press(screen, key)
  pressed = key
  screen:update(0)
  pressed = nil
end
local function mapIds(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    if row.id then out[row.id] = row end
  end
  return out
end

-- A real Game installs the merged pipeline registry before opening options.
-- Do the same here so VIEW is exercised as a live selector rather than the
-- intentionally defensive UNAVAILABLE fallback used before Game startup.
require("src.render.Pipelines").install(game.data)

local unified = exports.tweaksMenu
T.check(type(unified) == "table" and unified.unified == true,
  "fused build publishes one unified settings menu")
local root = buildScreen(unified.screenIds.main)
local categoryLabels = {
  "VIEW & CAMERA", "WORLD & WEATHER", "POKEMON ART", "BATTLES",
  "WILD & FOLLOWERS", "MOVEMENT", "MENUS & DEVICE",
}
for _, label in ipairs(categoryLabels) do
  T.check(findLabel(root.rows, label) ~= nil,
    "root contains unified category: " .. label)
end
local shown = findLabel(root.rows, "OPTIONS SHOWN")
T.eq(shown and shown.value(), "BASIC", "root calls the default view BASIC")
T.eq(root.title, "MOD SETTINGS", "unified root has a visible title")
T.check(type(root.footer) == "string"
    and root.footer:find("MOD SETTINGS", 1, true) ~= nil,
  "unified root footer preserves its title")

local wildBasic = buildScreen(unified.screenIds.wilds)
local encounter = findLabel(wildBasic.rows, "ENCOUNTER MODE")
T.eq(encounter and encounter.value(), "VISIBLE",
  "Wild BASIC mode clearly starts with visible-only encounters")
for _, label in ipairs({
  "SPRITE STYLE", "GRASS VIEW", "OVERWORLD CATCH",
}) do
  T.check(findLabel(wildBasic.rows, label) ~= nil,
    "Wild BASIC exposes " .. label)
end
T.eq(findLabel(wildBasic.rows, "HIDDEN MONS"), nil,
  "advanced hidden encounters stay out of BASIC")

local spritesBasic = buildScreen(unified.screenIds.sprites)
T.check(findLabel(spritesBasic.rows, "PLAYER VIEW") ~= nil,
  "Pokemon BASIC keeps the everyday player orientation control")
T.check(findLabel(spritesBasic.rows, "TRAINER SOURCE") ~= nil,
  "Pokemon BASIC keeps one combined trainer-source shortcut")
T.eq(findLabel(spritesBasic.rows, "MY POKEMON FLIP"), nil,
  "Pokemon BASIC stays concise by hiding the advanced front flip")
T.eq(findLabel(spritesBasic.rows, "CRYSTAL OPTIONS"), nil,
  "Pokemon BASIC keeps provider-specific tuning out of the short list")

-- Exercise the real OptionScreen input path. The root visibility row has both
-- an A action and a left/right step; a generic activate-first dispatch used to
-- swallow the arrows, leaving users permanently in BASIC.
local pokemonIndex = findIndex(root.rows, "POKEMON ART")
root.index = pokemonIndex
press(root, "a")
local openedPokemon = stack:top()
T.eq(openedPokemon and openedPokemon.title, "POKEMON ART",
  "A opens the canonical Pokemon category through the registered route")
stack:pop()

run.loader.modOptions.voxel_run_bridge =
  run.loader.modOptions.voxel_run_bridge or {}
game.save.options.modOptions.voxel_run_bridge =
  game.save.options.modOptions.voxel_run_bridge or {}
run.loader.modOptions.voxel_run_bridge.frontFlip = true
game.save.options.modOptions.voxel_run_bridge.frontFlip = true
local rememberedFlip = run.loader.modOptions.voxel_run_bridge.frontFlip
root.index = findIndex(root.rows, "OPTIONS SHOWN")
press(root, "right")
T.eq(shown.value(), "ALL",
  "right arrow changes OPTIONS SHOWN from BASIC to ALL")
T.eq(run.loader.modOptions.voxel_run_bridge.frontFlip, rememberedFlip,
  "changing visibility does not alter a hidden Pokemon setting")
T.eq(game.save.options.modOptions.voxel_run_bridge.frontFlip, rememberedFlip,
  "changing visibility preserves the saved hidden Pokemon setting")

local categoryScreens = {
  graphics = buildScreen(unified.screenIds.graphics),
  world = buildScreen(unified.screenIds.world),
  sprites = buildScreen(unified.screenIds.sprites),
  battles = buildScreen(unified.screenIds.battles),
  wilds = buildScreen(unified.screenIds.wilds),
  movement = buildScreen(unified.screenIds.movement),
  system = buildScreen(unified.screenIds.system),
}
for name, child in pairs(categoryScreens) do
  T.check(type(child.footer) == "string"
      and child.footer:find("BACK:", 1, true) == 1,
    name .. " category has a visible titled footer")
end
local graphics = mapIds(categoryScreens.graphics.rows)
local world = mapIds(categoryScreens.world.rows)
local sprites = mapIds(categoryScreens.sprites.rows)
local movement = mapIds(categoryScreens.movement.rows)
local system = mapIds(categoryScreens.system.rows)
;(function()
local viewPipelines = require("src.render.Pipelines")
local view = graphics["pipeline:voxel"]
local priorView = viewPipelines.level("voxel")
viewPipelines.setLevel("voxel", 0)
viewPipelines.syncOptions(game.save.options)
T.eq(view and view.value(), "OFF",
  "VIEW uses the installed pipeline selector instead of a fallback row")
categoryScreens.graphics.index = findIndex(categoryScreens.graphics.rows, "VIEW")
for _ = 1, 6 do press(categoryScreens.graphics, "right") end
T.eq(view.value(), "1ST", "VIEW reaches first person through real input")
T.eq(game.save.options.pipelines.voxel, 6,
  "first-person VIEW is retained in the save options")
press(categoryScreens.graphics, "right")
T.eq(view.value(), "3RD EXPERIMENTAL",
  "VIEW reaches the compact third-person label through real input")
T.eq(game.save.options.pipelines.voxel, 7,
  "third-person VIEW is retained in the save options")
viewPipelines.setLevel("voxel", priorView)
viewPipelines.syncOptions(game.save.options)
end)()
T.check(movement["voxel_run_bridge:running_view_bob"] ~= nil,
  "run head bob lives in Movement")
T.eq(graphics["voxel_run_bridge:running_view_bob"], nil,
  "run head bob is not mixed into View & Camera")
T.check(world["voxel_run_bridge:gapped_land"] ~= nil,
  "Gapped Land lives in World & Weather")
T.check(system["voxel_run_bridge:dual_screen"] ~= nil,
  "Thor second-screen control lives in Menus & Device")
;(function()
local bagLook = system["modern_bag_ui:skin"]
local packMenus = system["voxel_run_bridge:gen2_menus"]
T.check(bagLook ~= nil and packMenus ~= nil,
  "Menus & Device exposes BAG LOOK and PACK controls")
T.eq(bagLook.label, "BAG LOOK",
  "the single Bag presentation label fits the handheld row")
T.eq(bagLook.value(), "POCKET",
  "the requested Pocket backpack is the bundled default")
T.eq(packMenus.value(), "ON", "PACK + Pokegear uses its new-install default")
local systemWithPack = mapIds(buildScreen(unified.screenIds.system).rows)
local savedBagLook = systemWithPack["modern_bag_ui:skin"]
T.check(savedBagLook ~= nil,
  "PACK does not hide the independent Bag presentation choice")
T.eq(savedBagLook.step(game, 1), true,
  "BAG LOOK remains editable while PACK is on")
T.eq(savedBagLook.value(), "MODERN",
  "BAG LOOK switches to the responsive Modern skin")
T.eq(packMenus.value(), "ON",
  "editing BAG LOOK leaves PACK enabled")
T.eq(packMenus.step(game, -1), true, "PACK + Pokegear can be disabled")
local systemAfterPack = mapIds(buildScreen(unified.screenIds.system).rows)
T.eq(systemAfterPack["modern_bag_ui:skin"].value(), "MODERN",
  "disabling PACK preserves the independent Bag skin")
T.eq(systemAfterPack["modern_bag_ui:skin"].step(game, -1), true,
  "Pocket Bag can be restored for later tests")
end)()
;(function()
local catchCycle = mapIds(categoryScreens.wilds.rows)[
  "overworld_wild_spawns:catch_cycle_combo"]
T.eq(catchCycle and catchCycle.label, "BALL SWITCH COMBO",
  "advanced Wilds ball-switch control has a clear label")
T.eq(catchCycle and catchCycle.value(), "B + D-PAD",
  "ball-switch default uses a compact handheld value")
T.eq(catchCycle and catchCycle.step(game, 1), true,
  "ball-switch combo can select the alternate controller binding")
T.eq(catchCycle.value(), "SELECT + D-PAD",
  "alternate ball-switch value fits the handheld row")
T.eq(catchCycle.step(game, -1), true,
  "ball-switch combo can restore its default binding")
end)()
for _, key in ipairs({ "fpfov", "dof", "grid", "curve", "third" }) do
  T.check(graphics["voxel_run_bridge:" .. key] ~= nil,
    "ALL restores first-person/camera control: " .. key)
end
T.eq(sprites["voxel_run_bridge:playerView"] ~= nil, true,
  "player battle view has one integrated control")
T.eq(sprites["voxel_run_bridge:frontFlip"] ~= nil, true,
  "player flip has one integrated control")
local playerViewCount, frontFlipCount = 0, 0
local trainerSourceCount, trainerSetCount = 0, 0
for _, row in ipairs(categoryScreens.sprites.rows or {}) do
  if row.id == "voxel_run_bridge:playerView" then
    playerViewCount = playerViewCount + 1
  elseif row.id == "voxel_run_bridge:frontFlip" then
    frontFlipCount = frontFlipCount + 1
  end
  if row.label == "TRAINER SOURCE" then
    trainerSourceCount = trainerSourceCount + 1
  elseif row.label == "TRAINER ART SET" then
    trainerSetCount = trainerSetCount + 1
  end
end
T.eq(playerViewCount, 1, "player battle view is not duplicated")
T.eq(frontFlipCount, 1, "player flip is not duplicated")
T.eq(trainerSourceCount, 0,
  "ALL replaces the combined trainer shortcut with per-side controls")
T.eq(trainerSetCount, 1, "trainer art set is separately named")
for _, key in ipairs({
  "battleArt", "duplicateFix", "opponentTrainerSource",
  "playerTrainerSource", "trainerArtSet", "frontAnimatedSet",
  "backAnimatedSet", "playerArtSet", "playerAnimatedSet", "opponentFlip",
  "backFlip", "backPlacement",
}) do
  T.check(sprites["voxel_run_bridge:" .. key] ~= nil,
    "ALL restores Battle Art sprite-source control: " .. key)
end
T.eq(sprites["voxel_run_bridge:duplicateFix"].label, "POKEMON SOURCE",
  "legacy duplicate ownership has a clear compact label")
T.eq(sprites["voxel_run_bridge:playerTrainerSource"].label,
  "MY TRAINER SOURCE", "player trainer source fits the handheld row")
T.eq(sprites["voxel_run_bridge:opponentTrainerSource"].label,
  "OPP TRAINER SRC", "opponent trainer source fits the handheld row")
T.eq(system["voxel_run_bridge:dual_screen"].label, "THOR 2ND SCREEN",
  "Thor display control fits the handheld row")

local crystalIndex = findIndex(categoryScreens.sprites.rows, "CRYSTAL OPTIONS")
categoryScreens.sprites.index = crystalIndex
press(categoryScreens.sprites, "a")
local crystal = stack:top()
T.eq(crystal and crystal.title, "CRYSTAL SPRITES",
  "ALL opens the active sprite provider's orientation screen")
for _, label in ipairs({
  "FRONT SPRITES", "REPLACE SPRITES", "PLAYER SPRITE", "BATTLE PIC",
  "ANIMATIONS",
}) do
  T.check(crystal and findLabel(crystal.rows, label) ~= nil,
    "Crystal orientation screen exposes " .. label)
end
;(function()
local crystalAnimations = crystal and findLabel(crystal.rows, "ANIMATIONS")
T.eq(crystalAnimations and crystalAnimations.value(game), "LOOP",
  "Crystal animations default to continuous looping")
local originalCrystalApply = crystalExports.applyOption
local animationApplies = {}
crystalExports.applyOption = function(key, value)
  if key == "crystalAnimations" then
    animationApplies[#animationApplies + 1] = value
  end
  return originalCrystalApply(key, value)
end
local animationWrites = writes
T.eq(crystalAnimations and crystalAnimations.step(game, 1), true,
  "Crystal animations can switch to play once")
T.eq(writes, animationWrites + 1,
  "Crystal animation mode persists exactly once")
T.eq(game.save.options.crystalAnimations, "once",
  "Crystal animation mode saves PLAY ONCE")
T.eq(crystalAnimations.value(game), "PLAY ONCE",
  "Crystal animation row reports PLAY ONCE")
T.eq(animationApplies[#animationApplies], "once",
  "Crystal animation mode applies live after persistence")
local animationWriter = game.writeOptions
local animationApplyCount = #animationApplies
game.writeOptions = function() return false, "animation storage rejected" end
T.eq(crystalAnimations.step(game, -1), false,
  "Crystal animation mode reports a persistence failure")
T.eq(game.save.options.crystalAnimations, "once",
  "failed Crystal animation write restores the saved mode")
T.eq(crystalAnimations.value(game), "PLAY ONCE",
  "failed Crystal animation write leaves the displayed mode coherent")
T.eq(#animationApplies, animationApplyCount,
  "failed Crystal animation write invokes no live provider callback")
game.writeOptions = animationWriter
T.eq(crystalAnimations.step(game, -1), true,
  "Crystal animations can return to LOOP")
T.eq(game.save.options.crystalAnimations, "loop",
  "Crystal LOOP mode is durably restored")
T.eq(animationApplies[#animationApplies], "loop",
  "Crystal LOOP mode applies live")
crystalExports.applyOption = originalCrystalApply
end)()
stack:pop()

local bob = movement["voxel_run_bridge:running_bob_intensity"]
run.loader.modOptions.voxel_run_bridge.running_bob_intensity = 0.25
T.eq(bob and bob.value(), "1X",
  "the historical 0.25 head-bob effect is labeled 1X")
run.loader.modOptions.voxel_run_bridge.running_bob_intensity = 0.125
T.eq(bob and bob.value(), "0.5X",
  "the lower new-install head-bob effect is labeled 0.5X")

local freeFlyNow = movement[
  "voxel_run_bridge:free_fly_without_badges"]
T.eq(freeFlyNow and freeFlyNow.value(), "ON",
  "FREE FLY NOW reports its enabled bypass")
T.eq(host:readOption("free_fly", "badges"), false,
  "FREE FLY NOW=ON reaches bundled mod.options:get('badges') as false")
T.eq(run.loader.modOptions.free_fly, nil,
  "bundled Free Fly creates no historical Loader option bucket")
T.eq(freeFlyNow and freeFlyNow.step(game, 1), true,
  "FREE FLY NOW can disable the bundled bypass")
T.eq(freeFlyNow and freeFlyNow.value(), "OFF",
  "FREE FLY NOW reports the disabled bypass")
T.eq(host:readOption("free_fly", "badges"), true,
  "FREE FLY NOW=OFF restores bundled badge checks")
T.eq(freeFlyNow and freeFlyNow.step(game, -1), true,
  "FREE FLY NOW can re-enable the bundled bypass")
T.eq(host:readOption("free_fly", "badges"), false,
  "re-enabled bundled bypass again reaches mod.options:get")

-- Both writers used by the unified surface are transactional: Scott-owned
-- rows go through modules/settings.lua, while imported Battle Art rows go
-- through lib/SettingsMenu.lua. A rejected device write must restore the
-- exact bucket objects and emit no live event for either path.
local failedUnifiedEvents = 0
run.loader.events:on("mod.options_changed", function(payload)
  if payload and payload.mod == "voxel_run_bridge"
      and (payload.key == "dual_screen" or payload.key == "opponentFlip") then
    failedUnifiedEvents = failedUnifiedEvents + 1
  end
end)
local unifiedWriter = game.writeOptions
local unifiedSavedBucket = game.save.options.modOptions.voxel_run_bridge
local unifiedLiveBucket = run.loader.modOptions.voxel_run_bridge
unifiedSavedBucket.dual_screen = false
unifiedLiveBucket.dual_screen = false
local dualRow = system["voxel_run_bridge:dual_screen"]
game.writeOptions = function() error("simulated unified storage failure") end
local eventsBeforeOwnFailure = failedUnifiedEvents
T.eq(dualRow and dualRow.step(game, 1), false,
  "Scott-owned unified row reports a thrown persistence failure")
T.eq(game.save.options.modOptions.voxel_run_bridge, unifiedSavedBucket,
  "Scott-owned failure preserves the save bucket identity")
T.eq(run.loader.modOptions.voxel_run_bridge, unifiedLiveBucket,
  "Scott-owned failure preserves the live bucket identity")
T.eq(unifiedSavedBucket.dual_screen, false,
  "Scott-owned failure restores the saved value")
T.eq(unifiedLiveBucket.dual_screen, false,
  "Scott-owned failure restores the live value")
T.eq(failedUnifiedEvents, eventsBeforeOwnFailure,
  "Scott-owned failure emits no misleading live event")

unifiedSavedBucket.opponentFlip = "authored"
unifiedLiveBucket.opponentFlip = "authored"
local opponentFlipRow = sprites["voxel_run_bridge:opponentFlip"]
game.writeOptions = function()
  return false, "simulated imported-row storage failure"
end
local eventsBeforeArtFailure = failedUnifiedEvents
T.eq(opponentFlipRow and opponentFlipRow.step(game, 1), false,
  "imported Battle Art row honors an explicit false persistence result")
T.eq(game.save.options.modOptions.voxel_run_bridge, unifiedSavedBucket,
  "Battle Art failure preserves the save bucket identity")
T.eq(run.loader.modOptions.voxel_run_bridge, unifiedLiveBucket,
  "Battle Art failure preserves the live bucket identity")
T.eq(unifiedSavedBucket.opponentFlip, "authored",
  "Battle Art failure restores the saved orientation")
T.eq(unifiedLiveBucket.opponentFlip, "authored",
  "Battle Art failure restores the live orientation")
T.eq(failedUnifiedEvents, eventsBeforeArtFailure,
  "Battle Art failure emits no misleading live event")
game.writeOptions = unifiedWriter

root.index = findIndex(root.rows, "OPTIONS SHOWN")
press(root, "left")
T.eq(shown.value(), "BASIC",
  "left arrow changes OPTIONS SHOWN from ALL back to BASIC")
local graphicsBasic = mapIds(buildScreen(unified.screenIds.graphics).rows)
T.eq(graphicsBasic["voxel_run_bridge:fpfov"], nil,
  "BASIC hides advanced first-person tuning after a live switch")
press(root, "a")
T.eq(shown.value(), "ALL",
  "A also changes OPTIONS SHOWN from BASIC to ALL")
T.eq(run.loader.modOptions.voxel_run_bridge.frontFlip, rememberedFlip,
  "BASIC/ALL round trip keeps the stored Pokemon flip")
local iconRow = sprites["unique_menu_icons:icon_color_mode"]
T.eq(iconRow and iconRow.value(), "ORIGINAL",
  "unified menu uses a short icon value label")
for _, label in ipairs({ "WILDS MENU", "FOLLOWERS MENU" }) do
  T.eq(findLabel(categoryScreens.wilds.rows, label), nil,
    "broken legacy submenu link is absent: " .. label)
end

-- Each persisted schema key has one logical home in the seven categories.
-- Synthetic controls declare the raw keys they intentionally replace.
local covered = {}
local function cover(key)
  if schemaByKey[key] then covered[key] = (covered[key] or 0) + 1 end
end
cover("simple_menu")
for _, child in pairs(categoryScreens) do
  for _, row in ipairs(child.rows or {}) do
    if type(row.id) == "string" then
      local key = row.id:match("^voxel_run_bridge:(.+)$") or row.id
      cover(key)
    end
    for _, key in ipairs(row.schemaKeys or {}) do cover(key) end
  end
end
for key in pairs(schemaByKey) do
  T.eq(covered[key], 1, "unified categories cover canonical key once: " .. key)
end

-- The synthetic Wild row commits one three-key transaction and invokes the
-- Wilds runtime once. Per-key engine events would replay partially-updated
-- modes and cause three map rebuilds, so the direct runtime callback owns it.
local wildRuntime = host.loaded.overworld_wild_spawns
local wildExports = wildRuntime and wildRuntime.exports
local wildLogic = wildExports and wildExports.logic
local wildV = wildExports and wildExports.lib
local WildConfig = wildV and wildV.require("config")
local wildMod = wildV and wildV.mod
local originalWildOptionsChanged = wildLogic and wildLogic.onOptionsChanged
local modeCallbacks, modePayload = 0, nil
if originalWildOptionsChanged then
  wildLogic.onOptionsChanged = function(self, payload)
    if payload and payload.key == "encounter_mode" then
      modeCallbacks = modeCallbacks + 1
      modePayload = payload
    end
    return originalWildOptionsChanged(self, payload)
  end
end

-- Reproduce an upgraded Android save: old standalone-style values disagree
-- with the canonical fused defaults. The transaction must delete only these
-- superseded aliases before its single disk write.
run.loader.modOptions.voxel_run_bridge =
  run.loader.modOptions.voxel_run_bridge or {}
run.loader.modOptions.voxel_run_bridge[wildPrefix .. "enabled"] = true
run.loader.modOptions.voxel_run_bridge[wildPrefix .. "random_encounters"] = false
run.loader.modOptions.voxel_run_bridge[wildPrefix .. "enable_hidden"] = false
game.save.options.modOptions.overworld_wild_spawns = {
  enabled = false, random_encounters = true, enable_hidden = true,
  grass_encounters = "both", unrelated = "keep",
}
run.loader.modOptions.overworld_wild_spawns = {
  enabled = false, random_encounters = true, enable_hidden = true,
  grass_encounters = "both", unrelated = "keep",
}
T.eq(encounter.value(), "VISIBLE",
  "canonical fused values outrank stale legacy save values")
local hostEvents, vendorEvents = 0, 0
run.loader.events:on("mod.options_changed", function(payload)
  if payload and payload.mod == "voxel_run_bridge"
      and type(payload.key) == "string"
      and payload.key:find(wildPrefix, 1, true) == 1 then
    hostEvents = hostEvents + 1
  elseif payload and payload.mod == "overworld_wild_spawns" then
    vendorEvents = vendorEvents + 1
  end
end)
local beforeWrites = writes
T.eq(encounter.step(game, 1), true,
  "Encounter Mode changes VISIBLE to BOTH")
local saved = game.save.options.modOptions.voxel_run_bridge or {}
T.eq(saved[wildPrefix .. "enable_hidden"], false,
  "Encounter Mode clears hidden encounters")
T.eq(saved[wildPrefix .. "random_encounters"], true,
  "BOTH enables classic random encounters")
T.eq(saved[wildPrefix .. "enabled"], true,
  "BOTH keeps visible overworld Pokemon enabled")
T.eq(hostEvents, 0, "Encounter Mode suppresses partial host option events")
T.eq(vendorEvents, 0, "Encounter Mode suppresses partial vendor option events")
T.eq(writes, beforeWrites + 1,
  "Encounter Mode persists its complete snapshot once")
T.eq(modeCallbacks, 1, "Encounter Mode invokes one live Wilds refresh")
T.eq(modePayload and modePayload.mode, "both",
  "live Wilds refresh receives the committed mode")
T.eq(modePayload and modePayload.enabled, true,
  "live Wilds refresh receives visible enabled")
T.eq(modePayload and modePayload.random_encounters, true,
  "live Wilds refresh receives classic encounters enabled")
for _, bucket in ipairs({
  game.save.options.modOptions.overworld_wild_spawns,
  run.loader.modOptions.overworld_wild_spawns,
}) do
  T.eq(bucket.enabled, nil, "Encounter Mode removes legacy enabled alias")
  T.eq(bucket.random_encounters, nil,
    "Encounter Mode removes legacy random alias")
  T.eq(bucket.enable_hidden, nil,
    "Encounter Mode removes legacy hidden alias")
  T.eq(bucket.grass_encounters, nil,
    "Encounter Mode removes legacy grass alias")
  T.eq(bucket.unrelated, "keep",
    "Encounter Mode preserves unrelated legacy data")
end
if originalWildOptionsChanged then
  wildLogic.onOptionsChanged = originalWildOptionsChanged
end
host:writeOption(game, "overworld_wild_spawns", "enable_hidden", true)
T.eq(encounter.value(), "CUSTOM",
  "hidden encounters are reported explicitly as CUSTOM")
local safeVisibleWrites = writes
local persistedVisibleOptions
onOptionsPersist = function(rootOptions)
  persistedVisibleOptions = copyModOptions(rootOptions)
end
T.eq(encounter.step(game, 1), true,
  "stepping CUSTOM returns to a safe visible mode")
onOptionsPersist = nil
T.eq(writes, safeVisibleWrites + 1,
  "safe VISIBLE is also one persisted transaction")
T.eq(host:readOption("overworld_wild_spawns", "enable_hidden"), false,
  "safe visible mode disables sprite-less encounters")
T.eq(host:readOption("overworld_wild_spawns", "random_encounters"), false,
  "safe visible mode disables classic random encounters")
T.eq(host:readOption("overworld_wild_spawns", "enabled"), true,
  "safe visible mode retains visible Pokemon")

-- Storage failure is not a mode change. The transaction must restore both
-- canonical mirrors and every legacy alias, leave the last durable VISIBLE
-- snapshot untouched, and skip the live map callback and confirmation.
local failedLegacySave = {
  enabled = false, random_encounters = true, enable_hidden = true,
  grass_encounters = "both", unrelated = "failure_keep",
}
local failedLegacyLive = {
  enabled = false, random_encounters = true, enable_hidden = true,
  grass_encounters = "both", unrelated = "failure_keep",
}
game.save.options.modOptions.overworld_wild_spawns = failedLegacySave
run.loader.modOptions.overworld_wild_spawns = failedLegacyLive
local failedRuntimeCallbacks = 0
local beforeFailedHandler = wildLogic.onOptionsChanged
wildLogic.onOptionsChanged = function(self, payload)
  if payload and payload.key == "encounter_mode" then
    failedRuntimeCallbacks = failedRuntimeCallbacks + 1
  end
  return beforeFailedHandler(self, payload)
end
local durableEnabled = persistedVisibleOptions.voxel_run_bridge[
  wildPrefix .. "enabled"]
local durableRandom = persistedVisibleOptions.voxel_run_bridge[
  wildPrefix .. "random_encounters"]
local durableHidden = persistedVisibleOptions.voxel_run_bridge[
  wildPrefix .. "enable_hidden"]
local beforeFailureStack = #stack.values
local beforeFailureWrites = writes
local failedPersistAttempts = 0
local successfulWriter = game.writeOptions
game.writeOptions = function()
  failedPersistAttempts = failedPersistAttempts + 1
  error("simulated Thor storage failure")
end
local failureOk, failureMessage = wildExports.setEncounterMode(
  "off", "failure_runtime_test", { game = game })
game.writeOptions = successfulWriter
wildLogic.onOptionsChanged = beforeFailedHandler
T.eq(failureOk, false, "Encounter Mode reports a failed disk write")
T.check(type(failureMessage) == "string"
    and failureMessage:find("simulated Thor storage failure", 1, true) ~= nil,
  "Encounter Mode propagates the disk error")
T.eq(failedPersistAttempts, 1,
  "failed Encounter Mode attempts one transaction")
T.eq(writes, beforeFailureWrites,
  "failed Encounter Mode records no successful persisted write")
T.eq(failedRuntimeCallbacks, 0,
  "failed Encounter Mode invokes no runtime refresh")
T.eq(#stack.values, beforeFailureStack,
  "failed Encounter Mode shows no success confirmation")
for _, bucket in ipairs({
  game.save.options.modOptions.voxel_run_bridge,
  run.loader.modOptions.voxel_run_bridge,
}) do
  T.eq(bucket[wildPrefix .. "enabled"], true,
    "failed mode restores canonical visible ON")
  T.eq(bucket[wildPrefix .. "random_encounters"], false,
    "failed mode restores canonical random OFF")
  T.eq(bucket[wildPrefix .. "enable_hidden"], false,
    "failed mode restores canonical hidden OFF")
end
for _, bucket in ipairs({ failedLegacySave, failedLegacyLive }) do
  T.eq(bucket.enabled, false, "failed mode retains legacy enabled")
  T.eq(bucket.random_encounters, true,
    "failed mode retains legacy random encounters")
  T.eq(bucket.enable_hidden, true,
    "failed mode retains legacy hidden encounters")
  T.eq(bucket.grass_encounters, "both",
    "failed mode retains legacy grass choice")
  T.eq(bucket.unrelated, "failure_keep",
    "failed mode retains unrelated legacy data")
end
T.eq(persistedVisibleOptions.voxel_run_bridge[wildPrefix .. "enabled"],
  durableEnabled, "failed mode retains durable visible state")
T.eq(persistedVisibleOptions.voxel_run_bridge[
    wildPrefix .. "random_encounters"], durableRandom,
  "failed mode retains durable random state")
T.eq(persistedVisibleOptions.voxel_run_bridge[
    wildPrefix .. "enable_hidden"], durableHidden,
  "failed mode retains durable hidden state")
T.eq(wildExports.encounterMode(), "visible",
  "failed mode leaves the live runtime on VISIBLE")

-- Model a cold Android reload from the exact tree observed inside
-- game:writeOptions, with no live
-- Loader mirrors. Canonical values must survive and no legacy bucket may be
-- available to reassert hidden/classic behavior.
T.check(type(persistedVisibleOptions) == "table",
  "VISIBLE captured one persisted post-migration tree")
local reloadGame = {
  save = { options = { modOptions = persistedVisibleOptions } },
  mods = { modOptions = {} },
}
local preReloadWorld = wildMod.world
wildMod.world = { game = reloadGame }
for key, expected in pairs({
  enabled = true, random_encounters = false, enable_hidden = false,
}) do
  local raw, present = WildConfig.peekSavedOption(wildMod, key)
  T.eq(present, true, "cold reload finds canonical " .. key)
  T.eq(raw, expected, "cold reload retains VISIBLE " .. key)
end
local reloadedLegacy =
  reloadGame.save.options.modOptions.overworld_wild_spawns or {}
for _, key in ipairs({
  "enabled", "random_encounters", "enable_hidden", "grass_encounters",
}) do
  T.eq(reloadedLegacy[key], nil,
    "cold reload has no legacy " .. key .. " to override VISIBLE")
end
T.eq(reloadedLegacy.unrelated, "keep",
  "cold reload retains unrelated standalone data")
wildMod.world = preReloadWorld
-- Leave the later standalone-bucket migration fixture independent from this
-- conflict fixture (its unrelated sentinel was deliberately retained above).
game.save.options.modOptions.overworld_wild_spawns = nil
run.loader.modOptions.overworld_wild_spawns = nil

-- Party FOLLOW/DISMISS both call this same exported follower-count path.
-- It must update the unified key immediately; no standalone-style Wilds
-- bucket may be created behind MOD SETTINGS' back.
T.eq(wildExports and wildExports.setFollowerCount(game, 0), 0,
  "party DISMISS backing path accepts zero followers")
T.eq(game.save.options.modOptions.voxel_run_bridge[
    wildPrefix .. "follower_count"], 0,
  "party DISMISS persists the canonical host save key")
T.eq(run.loader.modOptions.voxel_run_bridge[
    wildPrefix .. "follower_count"], 0,
  "party DISMISS updates MOD SETTINGS' live Loader value")
T.eq(host:readOption("overworld_wild_spawns", "follower_count"), 0,
  "MOD SETTINGS reads the DISMISS value immediately")
T.eq(game.save.options.modOptions.overworld_wild_spawns, nil,
  "party DISMISS creates no stray vendor save bucket")
T.eq(wildExports and wildExports.setFollowerCount(game, 1), 1,
  "party FOLLOW backing path restores one follower")
T.eq(host:readOption("overworld_wild_spawns", "follower_count"), 1,
  "MOD SETTINGS reads the FOLLOW value immediately")

-- Every public Wilds setter must treat persistence as the commit point. A
-- Thor storage error cannot refresh art, apply encounter logic, mutate the
-- follower save/cache mirrors, show a success box, or report success.
do
  local saveBucket = game.save.options.modOptions.voxel_run_bridge
  local liveBucket = run.loader.modOptions.voxel_run_bridge
  saveBucket[wildPrefix .. "sprite_style"] = "followers"
  liveBucket[wildPrefix .. "sprite_style"] = "followers"
  saveBucket[wildPrefix .. "random_encounters"] = false
  liveBucket[wildPrefix .. "random_encounters"] = false
  saveBucket[wildPrefix .. "grass_encounters"] = "both"
  liveBucket[wildPrefix .. "grass_encounters"] = "both"
  saveBucket[wildPrefix .. "follower_count"] = 1
  liveBucket[wildPrefix .. "follower_count"] = 1
  game.save.pokepcFollowerCount = 1

  local control = wildExports and wildExports.follower
    and wildExports.follower.control
  if control and control._optCache then control._optCache.follower_count = 1 end
  local artCalls = 0
  local renderProbe = {
    invalidateAssetCache = function() artCalls = artCalls + 1 end,
    refreshAllEntitySprites = function() artCalls = artCalls + 1 return 9 end,
  }
  local randomCalls = 0
  local logicProbe = {
    applyRandomEncounters = function() randomCalls = randomCalls + 1 end,
  }
  local successBoxes = #stack.values
  local failAttempts = 0
  local goodWriter = game.writeOptions
  game.writeOptions = function()
    failAttempts = failAttempts + 1
    error("public setter storage failure")
  end

  local spriteOk, spriteError = WildConfig.setSpriteStyle(
    wildMod, "pokemmo", "failure_sprite_test", {
      game = game, logic = {}, render = renderProbe,
    })
  T.eq(spriteOk, false, "sprite style reports persistence failure")
  T.check(type(spriteError) == "string"
      and spriteError:find("public setter storage failure", 1, true) ~= nil,
    "sprite style propagates the storage error")
  T.eq(failAttempts, 1, "sprite style attempts exactly one persisted write")
  T.eq(artCalls, 0, "failed sprite style does not refresh live art")
  T.eq(#stack.values, successBoxes,
    "failed sprite style shows no success confirmation")

  local followerResult, followerError = wildExports.setFollowerCount(game, 0)
  T.eq(followerResult, nil, "follower count reports persistence failure")
  T.check(type(followerError) == "string"
      and followerError:find("public setter storage failure", 1, true) ~= nil,
    "follower count propagates the storage error")
  T.eq(failAttempts, 2, "follower count attempts exactly one persisted write")
  T.eq(game.save.pokepcFollowerCount, 1,
    "failed follower count retains its save mirror")
  T.eq(control and control._optCache and control._optCache.follower_count, 1,
    "failed follower count retains its runtime cache")

  local randomOk, randomError = WildConfig.setRandomEncounters(
    wildMod, true, "failure_random_test", {
      game = game, logic = logicProbe,
    })
  game.writeOptions = goodWriter
  T.eq(randomOk, false, "random encounter setter reports persistence failure")
  T.check(type(randomError) == "string"
      and randomError:find("public setter storage failure", 1, true) ~= nil,
    "random encounter setter propagates the storage error")
  T.eq(failAttempts, 3,
    "random encounter multi-key change attempts one persisted write")
  T.eq(randomCalls, 0,
    "failed random encounter change invokes no live logic")
  T.eq(#stack.values, successBoxes,
    "failed public setters show no success confirmations")
  for _, bucket in ipairs({ saveBucket, liveBucket }) do
    T.eq(bucket[wildPrefix .. "sprite_style"], "followers",
      "failed sprite style rolls back every canonical mirror")
    T.eq(bucket[wildPrefix .. "follower_count"], 1,
      "failed follower count rolls back every canonical mirror")
    T.eq(bucket[wildPrefix .. "random_encounters"], false,
      "failed random toggle rolls back every canonical mirror")
    T.eq(bucket[wildPrefix .. "grass_encounters"], "both",
      "failed random toggle retains the legacy choice atomically")
  end
end

-- Control mode is derived from follow_control + trainer_trail + follower_count.
-- Exercise all four public modes through the real hosted export and prove each
-- user action is one durable transaction with an exact effective readback.
do
  local control = wildExports and wildExports.follower
    and wildExports.follower.control
  local function expectMode(mode, expectedUi, expectedTrail, expectedCount)
    local before = writes
    local ok, applied, count = wildExports.setControlMode(game, mode)
    T.eq(ok, true, "control mode persists: " .. mode)
    T.eq(applied, mode, "control mode reports applied value: " .. mode)
    T.eq(writes, before + 1,
      "control mode is one persisted transaction: " .. mode)
    T.eq(host:readOption("overworld_wild_spawns", "follow_control"),
      expectedUi, "control mode writes follow_control: " .. mode)
    T.eq(host:readOption("overworld_wild_spawns", "trainer_trail"),
      expectedTrail, "control mode writes trainer_trail: " .. mode)
    T.eq(host:readOption("overworld_wild_spawns", "follower_count"),
      expectedCount, "control mode writes/preserves follower count: " .. mode)
    T.eq(game.save.pokepcControlMode, mode,
      "control mode updates save mirror after commit: " .. mode)
    T.eq(game.save.pokepcFollowerCount, expectedCount,
      "control mode keeps follower mirror consistent: " .. mode)
    T.eq(wildExports.controlMode(game), mode,
      "control mode effective readback matches request: " .. mode)
    if mode == "pokemon" or mode == "pack" then
      T.eq(count, expectedCount,
        "count-dependent control mode reports committed count: " .. mode)
    end
  end

  if control and control._optCache then
    control._optCache.follow_control = "stale"
    control._optCache.trainer_trail = "stale"
    control._optCache.follower_count = 99
  end
  expectMode("pack", "pokemon", false, 1)
  T.eq(control and control._optCache and control._optCache.follow_control, nil,
    "successful control mode invalidates runtime option cache")
  expectMode("pokemon", "pokemon", false, 0)
  expectMode("lead_trainer", "pokemon", true, 0)
  expectMode("follow", "trainer", false, 0)
  expectMode("pack", "pokemon", false, 1)
  expectMode("follow", "trainer", false, 1)

  local saveBucket = game.save.options.modOptions.voxel_run_bridge
  local liveBucket = run.loader.modOptions.voxel_run_bridge
  control._optCache.control_mode = "cached-follow"
  control._optCache.follow_control = "cached-trainer"
  control._optCache.trainer_trail = "cached-trail"
  control._optCache.follower_count = 77
  local goodWriter = game.writeOptions
  local failedAttempts = 0
  game.writeOptions = function()
    failedAttempts = failedAttempts + 1
    error("control mode storage failure")
  end
  local throwOk, throwError = wildExports.setControlMode(game, "pokemon")
  T.eq(throwOk, false, "control mode propagates thrown persistence failure")
  T.check(type(throwError) == "string"
      and throwError:find("control mode storage failure", 1, true) ~= nil,
    "control mode returns thrown storage error")
  T.eq(failedAttempts, 1,
    "failed count-dependent control mode attempts one transaction")

  game.writeOptions = function()
    failedAttempts = failedAttempts + 1
    return false, "control mode false failure"
  end
  local falseOk, falseError = wildExports.setControlMode(game, "lead_trainer")
  game.writeOptions = goodWriter
  T.eq(falseOk, false, "control mode propagates false persistence result")
  T.check(type(falseError) == "string"
      and falseError:find("control mode false failure", 1, true) ~= nil,
    "control mode returns false-result storage error")
  T.eq(failedAttempts, 2,
    "failed two-key control mode attempts one transaction")
  T.eq(game.save.pokepcControlMode, "follow",
    "failed control modes retain control save mirror")
  T.eq(game.save.pokepcFollowerCount, 1,
    "failed control modes retain follower-count save mirror")
  T.eq(wildExports.controlMode(game), "follow",
    "failed control modes retain effective runtime mode")
  for _, bucket in ipairs({ saveBucket, liveBucket }) do
    T.eq(bucket[wildPrefix .. "follow_control"], "trainer",
      "failed control mode rolls back follow_control mirror")
    T.eq(bucket[wildPrefix .. "trainer_trail"], false,
      "failed control mode rolls back trainer_trail mirror")
    T.eq(bucket[wildPrefix .. "follower_count"], 1,
      "failed control mode rolls back follower_count mirror")
  end
  T.eq(control._optCache.control_mode, "cached-follow",
    "failed control mode retains control cache")
  T.eq(control._optCache.follow_control, "cached-trainer",
    "failed control mode retains follow-control cache")
  T.eq(control._optCache.trainer_trail, "cached-trail",
    "failed control mode retains trainer-trail cache")
  T.eq(control._optCache.follower_count, 77,
    "failed control mode retains follower-count cache")
  control._optCache = {}
end

-- Upgrade migrations read one early fused build's stray vendor bucket only as
-- a fallback, then normalize into the canonical host bucket and Loader mirror.
T.check(type(WildConfig) == "table" and type(wildMod) == "table",
  "bundled Wilds exposes its migration helpers to the fused fixture")
local oldWildWorld = wildMod.world
wildMod.world = { game = game }
local saveHost = game.save.options.modOptions.voxel_run_bridge
local liveHost = run.loader.modOptions.voxel_run_bridge
for _, key in ipairs({
  "sprite_style", "random_encounters", "water_spawns", "cave_spawns",
  "enable_water_spawns", "dev_overlay", "sprite_fade", "sprite_opacity",
  "sprite_color",
}) do
  saveHost[wildPrefix .. key] = nil
  liveHost[wildPrefix .. key] = nil
end
game.save.options.modOptions.overworld_wild_spawns = {
  sprite_style = "gold",
  grass_encounters = "both",
  enable_water_spawns = false,
  cave_spawns = "obsolete",
  dev_mode = true,
  sprite_opacity = 0.5,
  sprite_color = "classic",
}
WildConfig.migrateSpriteStyleOption(wildMod)
WildConfig.migrateRandomEncountersOption(wildMod)
WildConfig.migrateWaterDisplayMode(wildMod)
WildConfig.migrateCaveSpawnMode(wildMod)
WildConfig.migrateDevOverlayOption(wildMod)
WildConfig.migrateSpriteFadeOption(wildMod)
WildConfig.migrateSpriteColorOption(wildMod)
local migrated = {
  sprite_style = "pokemmo",
  random_encounters = true,
  water_spawns = "classic_encounters",
  enable_water_spawns = false,
  cave_spawns = "reachable",
  dev_overlay = true,
  sprite_fade = "faded",
  sprite_opacity = 0.72,
  sprite_color = "colored",
}
for key, expected in pairs(migrated) do
  T.eq(saveHost[wildPrefix .. key], expected,
    "Wilds migration writes canonical save key: " .. key)
  T.eq(liveHost[wildPrefix .. key], expected,
    "Wilds migration mirrors canonical Loader key: " .. key)
end
T.eq(run.loader.modOptions.overworld_wild_spawns, nil,
  "Wilds migrations create no stray live vendor bucket")
T.eq(host:readOption("overworld_wild_spawns", "sprite_style"), "pokemmo",
  "MOD SETTINGS immediately reads a migrated canonical value")
wildMod.world = oldWildWorld

local standaloneGame = {
  save = { options = {} }, mods = {}, writeOptions = function() end,
}
local standaloneWild = {
  id = "overworld_wild_spawns",
  options = { get = function() return nil end },
  world = { game = standaloneGame },
}
T.eq(WildConfig._writeOptionBucket(standaloneWild, standaloneGame,
    "follower_count", 4), true,
  "standalone Wilds retains its ordinary option writer")
T.eq(standaloneGame.save.options.modOptions.overworld_wild_spawns.follower_count,
  4, "standalone Wilds retains its unprefixed save bucket")
T.eq(standaloneGame.save.options.modOptions.voxel_run_bridge, nil,
  "standalone Wilds never creates a Scott's Tweaks bucket")
local standaloneBucket =
  standaloneGame.save.options.modOptions.overworld_wild_spawns
standaloneBucket.enabled = false
standaloneBucket.random_encounters = true
standaloneBucket.enable_hidden = true
local standaloneCallbacks = 0
standaloneGame.writeOptions = function()
  error("standalone persistence failure")
end
local standaloneModeOk, standaloneModeError = WildConfig.setEncounterMode(
  standaloneWild, "visible", "standalone_failure_test", {
    game = standaloneGame,
    confirm = false,
    onChanged = function() standaloneCallbacks = standaloneCallbacks + 1 end,
  })
T.eq(standaloneModeOk, false,
  "standalone Encounter Mode propagates persistence failure")
T.check(type(standaloneModeError) == "string"
    and standaloneModeError:find("standalone persistence failure", 1, true)
      ~= nil,
  "standalone Encounter Mode returns the storage error")
T.eq(standaloneBucket.enabled, false,
  "standalone failure restores visible enabled")
T.eq(standaloneBucket.random_encounters, true,
  "standalone failure restores random encounters")
T.eq(standaloneBucket.enable_hidden, true,
  "standalone failure restores hidden encounters")
T.eq(standaloneCallbacks, 0,
  "standalone failure invokes no live callback")
do
  local ok, detail = WildConfig._writeOptionBucket(
    standaloneWild, standaloneGame, "follower_count", 5)
  T.eq(ok, false, "standalone single-key writer reports persistence failure")
  T.check(type(detail) == "string"
      and detail:find("standalone persistence failure", 1, true) ~= nil,
    "standalone single-key writer propagates the storage error")
  T.eq(standaloneBucket.follower_count, 4,
    "standalone single-key writer restores the prior bucket value")
end

-- Developer F5 keeps the engine Pipelines singleton but reloads Wilds module
-- locals. Two generations must share one persistent rows dispatcher, refresh
-- its generation-local callback, protect the new owner from old cleanup, and
-- restore the original rows function when the live owner releases it.
local pipelineModuleName = "src.render.Pipelines"
local realPipelineModule = package.loaded[pipelineModuleName]
local baseRowsCalls = 0
local function basePipelineRows()
  baseRowsCalls = baseRowsCalls + 1
  return {
    { id = "pipeline:owwild_behavior_tick", label = "WILDS AI" },
    { id = "pipeline:fixture", label = "FIXTURE" },
  }
end
local fakePipelines = { rows = basePipelineRows }
package.loaded[pipelineModuleName] = fakePipelines
local behaviorTickSource = modFiles[
  prefix .. "vendor/wilds/lib/behavior_tick.lua"]
local function loadBehaviorTickGeneration(label)
  local chunk = assert(loadstring(behaviorTickSource,
    "@behavior_tick_" .. tostring(label) .. ".lua"))
  return chunk(wildV)
end
local BehaviorTickOne = loadBehaviorTickGeneration("generation_one")
local generationOne = setmetatable({
  mod = { id = "wilds_hot_reload_fixture" },
}, BehaviorTickOne)
generationOne:hideFromEngineOptions()
local stableRowsDispatcher = fakePipelines.rows
local dispatcherRegistry = fakePipelines._wildsOptionsRowDispatchers
local dispatcherKey = "wilds_hot_reload_fixture:owwild_behavior_tick"
local dispatcherRecord = dispatcherRegistry and dispatcherRegistry[dispatcherKey]
local generationOneCallback = dispatcherRecord and dispatcherRecord.callback
local firstRows = fakePipelines.rows({})
T.eq(#firstRows, 1, "first Wilds generation hides one engine pipeline row")
T.eq(firstRows[1] and firstRows[1].id, "pipeline:fixture",
  "first Wilds generation preserves unrelated pipeline rows")
T.eq(baseRowsCalls, 1,
  "first Wilds generation delegates to the engine rows function once")

local BehaviorTickTwo = loadBehaviorTickGeneration("generation_two")
local generationTwo = setmetatable({
  mod = { id = "wilds_hot_reload_fixture" },
}, BehaviorTickTwo)
generationTwo:hideFromEngineOptions()
T.eq(fakePipelines.rows, stableRowsDispatcher,
  "second Wilds generation reuses exactly one rows dispatcher")
T.eq(dispatcherRegistry[dispatcherKey], dispatcherRecord,
  "second Wilds generation reuses the persistent owner record")
T.check(dispatcherRecord.callback ~= generationOneCallback,
  "second Wilds generation refreshes the row-filter callback")
T.eq(dispatcherRecord.owner, generationTwo,
  "second Wilds generation owns the persistent dispatcher")
local secondRows = fakePipelines.rows({})
T.eq(#secondRows, 1, "refreshed dispatcher still hides WILDS AI once")
T.eq(baseRowsCalls, 2,
  "refreshed dispatcher still delegates to engine rows exactly once")

generationOne:restoreEngineOptionsRow()
T.eq(fakePipelines.rows, stableRowsDispatcher,
  "old generation cleanup cannot remove the refreshed dispatcher")
T.eq(dispatcherRecord.owner, generationTwo,
  "old generation cleanup cannot revoke the new owner")
generationTwo:restoreEngineOptionsRow()
T.eq(fakePipelines.rows, basePipelineRows,
  "live generation cleanup restores the original rows function")
T.eq(dispatcherRegistry[dispatcherKey], nil,
  "live generation cleanup removes its persistent owner record")
local restoredRows = fakePipelines.rows({})
T.eq(#restoredRows, 2,
  "reversible cleanup restores the WILDS AI engine row")
package.loaded[pipelineModuleName] = realPipelineModule

-- Physical-runtime regression: selecting VISIBLE on an already-live grass map
-- must rebuild that map, suppress classic rolls, and advance each fresh
-- logical-only spawn into the exact Gen1 draw list. Pipelines.applyOptions can
-- wipe this hidden AI pipeline to OFF, so exercise the recovery too.
local liveMap = {
  id = "VISIBLE_RUNTIME_TEST",
  widthCells = 8, heightCells = 6,
  inBounds = function(_, x, y)
    return x >= 0 and y >= 0 and x < 8 and y < 6
  end,
  isGrassCell = function(_, x, y)
    return x >= 2 and x <= 5 and y >= 2 and y <= 4
  end,
  isWalkableCell = function(_, x, y)
    return not (x == 2 and y == 2)
  end,
  warpAtCell = function(_, x, y)
    return x == 5 and y == 4
  end,
}
local livePlayer = { cellX = 0, cellY = 0 }
local liveOw = {
  map = liveMap, player = livePlayer, entities = { livePlayer },
  runner = { isRunning = function() return false end,
    run = function() end },
}
local liveEncounter = {
  grass = {
    rate = 25,
    slots = {
      { species = "FIXMON_A", level = 3 },
      { species = "FIXMON_B", level = 4 },
    },
    buckets = { 128, 256 },
  },
}
local oldVisibleWorld = wildMod.world
local oldVisibleEncounter = game.data.encounters.VISIBLE_RUNTIME_TEST
local liveBattleQueues = 0
game.data.encounters.VISIBLE_RUNTIME_TEST = liveEncounter
wildMod.world = {
  game = game,
  overworld = function() return liveOw end,
  queueScript = function()
    liveBattleQueues = liveBattleQueues + 1
    return true
  end,
}
local visibleWrites = writes
local visibleOk, visibleMode = wildExports.setEncounterMode(
  "visible", "visible_runtime_test", { game = game, confirm = false })
T.eq(visibleOk, true, "VISIBLE live transaction succeeds")
T.eq(visibleMode, "visible", "VISIBLE live transaction reports its mode")
T.eq(writes, visibleWrites + 1,
  "VISIBLE live transaction persists once")
T.check(wildExports.logic:countOnMap(liveMap.id) > 0,
  "VISIBLE immediately respawns the current grass map")
T.check(wildExports.canSuppressVanilla(),
  "VISIBLE marks the spawn system ready to suppress classic rolls")
local Runtime = require("src.mods.Runtime")
local classicRollCalls = 0
local suppressedRoll = Runtime.call("encounter.roll", function()
  classicRollCalls = classicRollCalls + 1
  return { species = "FIXMON_A", level = 3 }
end, liveEncounter, { mapId = liveMap.id, terrain = "grass" })
T.eq(suppressedRoll, nil, "VISIBLE suppresses a real classic grass roll")
T.eq(classicRollCalls, 0,
  "VISIBLE suppression stops the underlying random encounter function")

local spawnedEntity
for _, entity in pairs(wildExports.logic.entities or {}) do
  spawnedEntity = entity
  break
end
T.check(spawnedEntity ~= nil, "VISIBLE created a concrete overworld entity")
T.check(spawnedEntity and spawnedEntity.hiddenEncounter ~= true,
  "VISIBLE creates no sprite-less hidden encounter")
T.check(spawnedEntity and spawnedEntity.spawnFx ~= nil
    and spawnedEntity.hiddenBody == true,
  "fresh grass spawn begins logical-only during its pop animation")
local GameCompat = wildV.require("game_compat")
T.eq(GameCompat.entityInDrawList(liveOw, spawnedEntity, game), false,
  "unrevealed spawn is not prematurely inserted in the draw list")

local Pipelines = require("src.render.Pipelines")
local pipelineId = "owwild_behavior_tick"
-- The headless loader merges content but does not construct Game, whose load
-- normally installs the merged render-pipeline registry.
Pipelines.install(game.data)
T.check(Pipelines.get(pipelineId) ~= nil,
  "real merged content contains the Wilds behavior pipeline")
Pipelines.setLevel(pipelineId, 0)
T.eq(Pipelines.level(pipelineId), 0,
  "fixture reproduces settings wiping the hidden Wilds pipeline")
local oldGetTime = love.timer.getTime
local testNow = 1
love.timer.getTime = function() return testNow end

-- SpawnFx's wall-clock fail-safe can complete without emitting its usual
-- reveal event. A contact on that exact frame must repair draw membership and
-- defer the battle; otherwise a logical collision can launch an encounter
-- against a Pokemon the physical display never drew.
wildExports.logic:onStepped({
  mapId = liveMap.id,
  x = spawnedEntity.cellX,
  y = spawnedEntity.cellY,
})
T.eq(liveBattleQueues, 0,
  "stalled logical-only spawn cannot start an invisible contact battle")
T.eq(wildExports.logic.pendingBattle, nil,
  "invisible contact does not leave a pending battle")
T.eq(GameCompat.entityInDrawList(liveOw, spawnedEntity, game), true,
  "contact readiness repairs the completed spawn's draw-list membership")
wildExports.logic:_detachFromWorld(spawnedEntity)
T.eq(GameCompat.entityInDrawList(liveOw, spawnedEntity, game), false,
  "fixture detaches the completed spawn before pipeline reconciliation")

wildExports.behaviorTick._lastT = 0
wildExports.behaviorTick:stepFromWorld({ mapId = liveMap.id })
T.eq(Pipelines.level(pipelineId), 1,
  "the next world step restores the Wilds behavior pipeline")
T.eq(GameCompat.entityInDrawList(liveOw, spawnedEntity, game), true,
  "spawn reveal attaches the Pokemon to the real Gen1 draw list")
T.eq(spawnedEntity.registeredInWorld, true,
  "spawn attachment records successful world registration")

-- Even inside the cadence guard, recovery is unconditional: a settings wipe
-- must not wait for another full AI interval.
Pipelines.setLevel(pipelineId, 0)
wildExports.behaviorTick._lastT = testNow
wildExports.behaviorTick:stepFromWorld({ mapId = liveMap.id })
T.eq(Pipelines.level(pipelineId), 1,
  "pipeline recovery runs before the double-tick cadence guard")

-- OFF is distinct from CLASSIC even when an older Water Mons preference says
-- classic encounters. OFF retains only the encounter-roll hook and blocks
-- every terrain; CLASSIC removes it and delegates every terrain to vanilla.
host:writeOption(game, "overworld_wild_spawns",
  "water_spawns", "classic_encounters")
T.eq(WildConfig.waterDisplayMode(wildMod), "classic_encounters",
  "OFF regression starts with the overriding water-classic preference")
local offOk, offMode = wildExports.setEncounterMode(
  "off", "off_runtime_test", { game = game, confirm = false })
T.eq(offOk, true, "OFF live transaction succeeds")
T.eq(offMode, "off", "OFF live transaction reports its mode")
T.eq(wildExports.logic:countOnMap(liveMap.id), 0,
  "OFF clears visible entities from the current map")
local offHooks = wildExports.encounterHookState()
T.eq(offHooks.encounter, true,
  "OFF retains the classic-encounter suppression hook")
T.eq(offHooks.collision, false,
  "OFF removes the visible-wild collision hook")
T.check(wildExports.canSuppressVanilla(),
  "OFF reports classic encounter suppression while visible spawns are disabled")
local offBaseCalls = 0
local function offBaseRoll()
  offBaseCalls = offBaseCalls + 1
  return { species = "FIXMON_A", level = 3 }
end
for _, terrain in ipairs({ "grass", "water" }) do
  local result = Runtime.call("encounter.roll", offBaseRoll, liveEncounter, {
    mapId = liveMap.id, terrain = terrain,
  })
  T.eq(result, nil, "OFF suppresses real " .. terrain .. " encounter.roll")
end
T.eq(offBaseCalls, 0,
  "OFF never delegates grass or water rolls to vanilla")

-- Model the release/rebind boundary used by a loader refresh. The committed
-- OFF snapshot must reconstruct exactly the suppression-only ownership, and
-- repeated synchronization must remain idempotent.
wildExports.removeHooks()
local releasedHooks = wildExports.encounterHookState()
T.eq(releasedHooks.encounter, false,
  "release removes the OFF encounter hook")
T.eq(releasedHooks.collision, false,
  "release leaves no collision hook")
wildExports.syncEncounterHooks()
wildExports.syncEncounterHooks()
local reboundHooks = wildExports.encounterHookState()
T.eq(reboundHooks.encounter, true,
  "reload synchronization restores OFF suppression")
T.eq(reboundHooks.collision, false,
  "reload synchronization does not restore visible collisions in OFF")
local reboundBaseCalls = 0
local reboundRoll = Runtime.call("encounter.roll", function()
  reboundBaseCalls = reboundBaseCalls + 1
  return { species = "FIXMON_B", level = 4 }
end, liveEncounter, { mapId = liveMap.id, terrain = "grass" })
T.eq(reboundRoll, nil, "rebound OFF hook suppresses a real roll")
T.eq(reboundBaseCalls, 0,
  "rebound OFF hook remains singular and never delegates")

local classicOk, classicMode = wildExports.setEncounterMode(
  "classic", "classic_runtime_test", { game = game, confirm = false })
T.eq(classicOk, true, "CLASSIC live transaction succeeds")
T.eq(classicMode, "classic", "CLASSIC live transaction reports its mode")
local classicHooks = wildExports.encounterHookState()
T.eq(classicHooks.encounter, false,
  "CLASSIC removes the encounter suppression hook")
T.eq(classicHooks.collision, false,
  "CLASSIC keeps visible-wild collision disabled")
local classicBaseCalls = 0
for _, terrain in ipairs({ "grass", "water" }) do
  local result = Runtime.call("encounter.roll", function()
    classicBaseCalls = classicBaseCalls + 1
    return { species = "FIXMON_A", level = 3 }
  end, liveEncounter, { mapId = liveMap.id, terrain = terrain })
  T.check(result ~= nil,
    "CLASSIC delegates real " .. terrain .. " encounter.roll")
end
T.eq(classicBaseCalls, 2,
  "CLASSIC delegates grass and water exactly once each")

wildExports.setEncounterMode(
  "visible", "restore_visible_test", { game = game, confirm = false })
love.timer.getTime = oldGetTime
wildExports.logic:clearAll()
wildMod.world = oldVisibleWorld
game.data.encounters.VISIBLE_RUNTIME_TEST = oldVisibleEncounter

local startRows = run.loader.hooks:call("ui.start_menu.items",
  function(_, rows) return rows end, game, {
    { id = "vanilla.party", label = "POKEMON" },
    { id = "vanilla.mods", label = "MODS" },
  })
local modSettingsCount, battleArtCount = 0, 0
for _, row in ipairs(startRows) do
  if row.id == "scotts_tweaks.open" and row.label == "MOD SETTINGS" then
    modSettingsCount = modSettingsCount + 1
  end
  if row.label == "BATTLE ART" then battleArtCount = battleArtCount + 1 end
end
T.eq(modSettingsCount, 1, "Start contains one MOD SETTINGS entry")
T.eq(battleArtCount, 0, "Start contains no competing Battle Art entry")

stack.values = {}
local ManagerState = require("src.mods.ManagerState")
ManagerState.openOptions({ game = game }, { id = "voxel_run_bridge" })
T.eq(stack:top() and stack:top().title, "MOD SETTINGS",
  "Mod Manager routes the fused mod to the unified screen")

run.release()
T.finish("fused renderer load")
