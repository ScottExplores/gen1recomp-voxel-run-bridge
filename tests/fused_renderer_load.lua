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
  "free_fly_cockpit", "gapped_land", "bag_pockets", "gen2_menus",
  "experience_mode", "trainer_forfeit_enabled", "trainer_rematches",
  "trainer_adaptive_dialogue", "trainer_growth", "oak_spare_starter",
  "running_enabled", "running_speed", "running_view_bob",
  "running_bob_intensity", "dual_screen",
}
for _, key in ipairs(ownKeys) do
  T.eq(schemaCount[key], 1, "own canonical option appears once: " .. key)
end
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
local game = {
  data = run.data,
  save = { options = { modOptions = {} }, party = {} },
  mods = run.loader,
  stack = stack,
  input = { wasPressed = function() return false end,
            isDown = function() return false end },
  writeOptions = function() writes = writes + 1 end,
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
local function mapIds(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    if row.id then out[row.id] = row end
  end
  return out
end

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

run.loader.modOptions.voxel_run_bridge =
  run.loader.modOptions.voxel_run_bridge or {}
run.loader.modOptions.voxel_run_bridge.simple_menu = true
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

run.loader.modOptions.voxel_run_bridge.simple_menu = false
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
T.check(movement["voxel_run_bridge:running_view_bob"] ~= nil,
  "run head bob lives in Movement")
T.eq(graphics["voxel_run_bridge:running_view_bob"], nil,
  "run head bob is not mixed into View & Camera")
T.check(world["voxel_run_bridge:gapped_land"] ~= nil,
  "Gapped Land lives in World & Weather")
T.check(system["voxel_run_bridge:dual_screen"] ~= nil,
  "Thor second-screen control lives in Menus & Device")
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
  if row.label == "TRAINER ART SOURCE" then
    trainerSourceCount = trainerSourceCount + 1
  elseif row.label == "TRAINER ART SET" then
    trainerSetCount = trainerSetCount + 1
  end
end
T.eq(playerViewCount, 1, "player battle view is not duplicated")
T.eq(frontFlipCount, 1, "player flip is not duplicated")
T.eq(trainerSourceCount, 1, "trainer art source is unambiguous")
T.eq(trainerSetCount, 1, "trainer art set is separately named")
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

-- The synthetic Wild row writes through VendorHost: all three values persist,
-- both host/vendor events fire, and a customized hidden mode is made explicit.
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
T.eq(hostEvents, 3, "Encounter Mode emits three host option events")
T.eq(vendorEvents, 3, "Encounter Mode emits three live vendor events")
T.eq(writes, beforeWrites + 3,
  "Encounter Mode persists each underlying vendor option")
host:writeOption(game, "overworld_wild_spawns", "enable_hidden", true)
T.eq(encounter.value(), "CUSTOM",
  "hidden encounters are reported explicitly as CUSTOM")
T.eq(encounter.step(game, 1), true,
  "stepping CUSTOM returns to a safe visible mode")
T.eq(host:readOption("overworld_wild_spawns", "enable_hidden"), false,
  "safe visible mode disables sprite-less encounters")
T.eq(host:readOption("overworld_wild_spawns", "random_encounters"), false,
  "safe visible mode disables classic random encounters")
T.eq(host:readOption("overworld_wild_spawns", "enabled"), true,
  "safe visible mode retains visible Pokemon")

-- Party FOLLOW/DISMISS both call this same exported follower-count path.
-- It must update the unified key immediately; no standalone-style Wilds
-- bucket may be created behind MOD SETTINGS' back.
local wildRuntime = host.loaded.overworld_wild_spawns
local wildExports = wildRuntime and wildRuntime.exports
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

-- Upgrade migrations read one early fused build's stray vendor bucket only as
-- a fallback, then normalize into the canonical host bucket and Loader mirror.
local wildV = wildExports and wildExports.lib
local WildConfig = wildV and wildV.require("config")
local wildMod = wildV and wildV.mod
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
