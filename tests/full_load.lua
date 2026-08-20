-- ROM-free production-loader smoke.
-- Run from a Gen1Recomp checkout:
--   luajit <mod>/tests/full_load.lua <mod-root> [fixture-root]

local argv = rawget(_G, "arg") or {}
local sourceRoot = argv[1] or os.getenv("SCOTTS_TWEAKS_MOD_ROOT")
local fixtureRoot = argv[2] or os.getenv("SCOTTS_TWEAKS_FIXTURE_ROOT") or "."
local expectedTradeAdapter = argv[3]
  or os.getenv("SCOTTS_TWEAKS_EXPECT_TRADE_ADAPTER")
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
  "version": "1.6.2",
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
  local flying = false
  local cockpitDraws = 0
  mod.exports.isFlying = function() return flying end
  mod.exports.testSetFlying = function(value) flying = value == true end
  mod.exports.testCockpitDraws = function() return cockpitDraws end
  mod.exports.testBadgeChecks = badgeChecksEnabled
  mod.exports.testStartFlight = startFlight
  mod.hooks:wrap("render.hud", function(nextFn, game, viewport)
    local out = nextFn(game, viewport)
    local provider = mod.find("POKEMON_FINAL")
    local lib = provider and provider.exports and provider.exports.lib
    local FirstPerson = lib and lib.require("FirstPerson")
    if flying and FirstPerson and FirstPerson.hidePlayer() then
      cockpitDraws = cockpitDraws + 1
    end
    return out
  end)
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
  local FirstPerson = { hidden = true }
  function FirstPerson.hidePlayer() return FirstPerson.hidden end
  local DayNight = { isCanopy = function() return false end }
  local Mat4 = { translate = function(x, y, z) return { x, y, z } end }
  local modules = {
    FreeMove = FreeMove,
    VoxelScene = VoxelScene,
    Voxel3D = Voxel3D,
    VoxelState = VoxelState,
    FirstPerson = FirstPerson,
    DayNight = DayNight,
    Mat4 = Mat4,
  }
  mod.exports.lib = {
    require = function(name) return modules[name] end
  }
  mod.exports.testFreeMove = FreeMove
  mod.exports.testVoxelScene = VoxelScene
  mod.exports.testVoxel3D = Voxel3D
  mod.exports.testFirstPerson = FirstPerson
end]]
local modFiles = {
  [prefix .. "manifest.json"] = read("manifest.json"),
  [prefix .. "main.lua"] = read("main.lua"),
  [freeFlyPrefix .. "manifest.json"] = freeFlyManifest,
  [freeFlyPrefix .. "main.lua"] = freeFlyEntry,
  [pokemonFinalPrefix .. "manifest.json"] = pokemonFinalManifest,
  [pokemonFinalPrefix .. "main.lua"] = pokemonFinalEntry,
}
for _, relative in ipairs({
  -- The fused renderer's asset transform is validated by the loader before

  -- the entry runs, so the fixture must carry it even when the vendored lib/

  -- tree is absent and installBattleArt stands down.

  "transform_birds.lua",

  "modules/settings.lua",
  "modules/migrations.lua",
  "modules/trainer_forfeit.lua",
  "modules/trainer_dialogue.lua",
  "modules/oak_spare_starter.lua",
  "modules/running.lua",
  "modules/option_screen.lua",
  "modules/tweaks_menu.lua",
  "modules/thor_dual_screen.lua",
  "modules/gen2_ui.lua",
}) do
  local ok, body = pcall(read, relative)
  if ok then modFiles[prefix .. relative] = body end
end

local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs(modFiles),
  generation = 1,
})

T.eq(#run.errors, 0, "Scott's Tweaks loads through the API-2 loader")
T.check(run.mod ~= nil, "loader selected Scott's Tweaks")
T.eq(run.mod and run.mod.manifest.id, "voxel_run_bridge",
  "stable updater identity is retained")
T.eq(run.mod and run.mod.manifest.name, "Scott's Tweaks",
  "new display name is loaded")
T.eq(run.mod and run.mod.manifest.version, "0.12.1",
  "loader selected version 0.12.1")
-- The consolidated build bundles All Pokemon Catchable 151 and Dynamic Scaling, which repatch
-- encounter tables and pokemon records. The loader warns when a mod writes to
-- pokemon while claiming otherwise, and a link partner must know, so the flag
-- is now honestly true.
T.eq(run.mod and run.mod.manifest.affects_link, true,
  "bundled encounter and stat changes are declared to link partners")
local thorApi = run.loader.exports.voxel_run_bridge.thorDualScreen
T.check(type(thorApi) == "table",
  "main orchestrator installs the physical-Thor presenter")
for _, name in ipairs({
  "getEnabled", "getMode", "secondDisplayAttached", "getStatus",
}) do
  T.check(type(thorApi and thorApi[name]) == "function",
    "Thor export publishes " .. name)
end
T.eq(thorApi and thorApi.getMode(), "off",
  "central dual_screen default reaches the Thor presenter")

local schema = run.loader.optionSchemas.voxel_run_bridge or {}
local schemaByKey = {}
for _, row in ipairs(schema) do schemaByKey[row.key] = row end
for key, expected in pairs({
  simple_menu = true,
  trainer_forfeit_enabled = true,
  trainer_rematches = true,
  trainer_adaptive_dialogue = true,
  trainer_growth = "gentle",
  oak_spare_starter = true,
  running_enabled = true,
  running_speed = 1.5,
  running_view_bob = true,
  running_bob_intensity = 0.125,
  dual_screen = false,
}) do
  T.check(type(schemaByKey[key]) == "table", key .. " is in central schema")
  T.eq(schemaByKey[key] and schemaByKey[key].default, expected,
    key .. " has the release default")
end
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

local bagPocketsOption
local experienceOption
local cockpitOption
for _, row in ipairs(schema) do
  if row.key == "bag_pockets" then bagPocketsOption = row end
  if row.key == "experience_mode" then experienceOption = row end
  if row.key == "free_fly_cockpit" then cockpitOption = row end
end
T.eq(bagPocketsOption and bagPocketsOption.type, "toggle",
  "Bag Pockets uses a toggle")
T.eq(bagPocketsOption and bagPocketsOption.label, "CLASSIC POCKETS",
  "schema distinguishes classic pockets from PACK navigation")
T.eq(bagPocketsOption and bagPocketsOption.default, true,
  "Bag Pockets defaults on")
T.check(type(bagPocketsOption and bagPocketsOption.help) == "string"
    and bagPocketsOption.help:find("PACK + POK", 1, true) ~= nil,
  "schema explains that PACK + Pokegear keeps its pocket projection")
T.eq(experienceOption and experienceOption.type, "choice",
  "EXP mode uses a choice")
T.eq(experienceOption and experienceOption.default, "vanilla",
  "EXP mode defaults to vanilla")
T.eq(experienceOption and #(experienceOption.choices or {}), 4,
  "EXP mode exposes all four choices")
T.eq(cockpitOption and cockpitOption.type, "toggle",
  "Free Fly cockpit control uses a toggle")
T.eq(cockpitOption and cockpitOption.default, false,
  "Free Fly cockpit defaults to a clear first-person view")

local shareItem = run.data.items.SCOTTS_EXP_SHARE
local tradeStone = run.data.items.SCOTTS_TRADE_STONE
local tradeEffect = run.data.item_effects.SCOTTS_TRADE_STONE_EFFECT
T.eq(shareItem and shareItem.name, "EXP.SHARE",
  "EXP.SHARE key item is registered")
T.eq(shareItem and shareItem.keyItem, true,
  "EXP.SHARE is protected as a key item")
T.eq(tradeStone and tradeStone.price, 500,
  "Trade Stone costs 500")
T.eq(tradeStone and tradeStone.effect, "SCOTTS_TRADE_STONE_EFFECT",
  "Trade Stone references its registered effect")
T.eq(type(tradeEffect and tradeEffect.use), "function",
  "Trade Stone effect is registered")
T.eq(type(run.data.screens and run.data.screens.BagMenu), "table",
  "BagMenu decorator is registered")
T.eq(type(run.data.screens and run.data.screens.ShopMenu), "table",
  "ShopMenu decorator is registered")

run.data.pokemon.ALAKAZAM = run.data.pokemon.ALAKAZAM or { name = "ALAKAZAM" }
local into = select(3, tradeEffect.use({
  data = run.data,
  target = { species = "KADABRA" },
}))
T.eq(into and into.evolveTo, "ALAKAZAM",
  "Trade Stone maps Kadabra to Alakazam")

local ItemEffects = require("src.inventory.ItemEffects")
local tradeStatus = run.loader.exports.voxel_run_bridge.tradeStone
if expectedTradeAdapter == "compat" then
  T.eq(tradeStatus and tradeStatus.adapter, "v0.1.75_compatibility",
    "v0.1.75 receives the narrow Trade Stone dispatcher")
  T.eq(type(rawget(ItemEffects, "_scottsTweaksTradeStoneHook")), "table",
    "v0.1.75 compatibility wrapper is ownership-marked")
elseif expectedTradeAdapter == "native" then
  T.eq(tradeStatus and tradeStatus.adapter, "native_item_effects",
    "newer engine keeps native registered-item dispatch")
  T.eq(rawget(ItemEffects, "_scottsTweaksTradeStoneHook"), nil,
    "newer engine receives no process-global item wrapper")
else
  local mode = tradeStatus and tradeStatus.adapter
  T.check(mode == "native_item_effects" or mode == "v0.1.75_compatibility",
    "engine selects native or compatibility Trade Stone dispatch")
  T.eq(rawget(ItemEffects, "_scottsTweaksTradeStoneHook") ~= nil,
    mode == "v0.1.75_compatibility",
    "Trade Stone wrapper presence matches the selected dispatcher")
end
T.eq(ItemEffects.needsTarget("SCOTTS_TRADE_STONE", tradeStone, run.data), true,
  "live engine ItemEffects targets the Trade Stone")
local effectSave = { inventory = {}, player = { name = "RED" } }
local stoneResult, _, stoneExtra = ItemEffects.use(run.data,
  effectSave, "SCOTTS_TRADE_STONE", { species = "KADABRA" })
T.eq(stoneResult, "consumed",
  "live engine ItemEffects accepts a valid Trade Stone target")
T.eq(stoneExtra and stoneExtra.evolveTo, "ALAKAZAM",
  "live engine ItemEffects returns the native evolution target")
local battleResult = ItemEffects.use(run.data, effectSave,
  "SCOTTS_TRADE_STONE", { species = "KADABRA" }, {})
T.eq(battleResult, "failed", "Trade Stone is refused in battle")

local Screens = require("src.ui.Screens")
Screens.invalidate()
local pressed
local stack = { values = {} }
function stack:push(value) self.values[#self.values + 1] = value end
function stack:pop() return table.remove(self.values) end
function stack:top() return self.values[#self.values] end
local screenGame = {
  data = run.data,
  save = {
    inventory = { SCOTTS_TRADE_STONE = 2, SCOTTS_EXP_SHARE = 1 },
    bagOrder = { "SCOTTS_TRADE_STONE", "SCOTTS_EXP_SHARE" },
    party = {}, money = 5000,
  },
  input = {
    wasPressed = function(_, key) return key == pressed end,
    isDown = function() return false end,
  },
  stack = stack,
}
local function buildScreen(id, ...)
  if type(Screens.build) == "function" then
    return Screens.build(screenGame, id, ...)
  end
  return Screens.get(screenGame, id).new(screenGame, ...)
end
local menuApi = run.loader.exports.voxel_run_bridge.tweaksMenu
local tweaksMain = buildScreen(menuApi.screenIds.main)
T.eq(#(tweaksMain.rows or {}), 8,
  "MOD SETTINGS opens as seven categories plus one visibility control")
local expectedCategories = {
  "VIEW & CAMERA", "WORLD & WEATHER", "POKEMON ART", "BATTLES",
  "WILD & FOLLOWERS", "MOVEMENT", "MENUS & DEVICE",
}
for i, label in ipairs(expectedCategories) do
  T.eq(tweaksMain.rows[i] and tweaksMain.rows[i].label, label,
    "unified category " .. i .. " is concise and stable")
end
local optionsShown = tweaksMain.rows[8]
T.eq(optionsShown and optionsShown.label, "OPTIONS SHOWN",
  "the single visibility control is named plainly")
T.eq(optionsShown and optionsShown.value(), "BASIC",
  "new installs show the BASIC settings set")
T.check(type(tweaksMain.footer) == "string"
    and tweaksMain.footer:find("MOD SETTINGS", 1, true) ~= nil,
  "screen footer keeps the current menu title visible")

-- Inspect ALL so coverage includes advanced settings without changing any of
-- their values. The root visibility row itself is part of the canonical
-- schema and is collected from the root below.
run.loader.modOptions.voxel_run_bridge =
  run.loader.modOptions.voxel_run_bridge or {}
run.loader.modOptions.voxel_run_bridge.simple_menu = false
local organized = {}
for _, row in ipairs(tweaksMain.rows or {}) do
  local key = type(row.id) == "string"
    and row.id:match("^voxel_run_bridge:(.+)$") or nil
  if key then organized[key] = row end
end
for _, id in ipairs({
  menuApi.screenIds.graphics, menuApi.screenIds.world,
  menuApi.screenIds.sprites, menuApi.screenIds.battles,
  menuApi.screenIds.wilds, menuApi.screenIds.movement,
  menuApi.screenIds.system,
}) do
  local child = buildScreen(id)
  for _, row in ipairs(child.rows or {}) do
    local key = type(row.id) == "string"
      and row.id:match("^voxel_run_bridge:(.+)$") or nil
    if key then organized[key] = row end
  end
end
local organizedCount = 0
for key in pairs(organized) do
  organizedCount = organizedCount + 1
  T.check(schemaByKey[key] ~= nil,
    key .. " organized row is backed by the central schema")
end
T.eq(organizedCount, #schema,
  "categorized screens retain every Mod Manager setting")
run.loader.modOptions.voxel_run_bridge.simple_menu = true
T.eq(organized.gen2_menus.value(), "OFF",
  "built-in PACK + Pokegear needs no external import")
run.loader.modOptions.voxel_run_bridge =
  run.loader.modOptions.voxel_run_bridge or {}
run.loader.modOptions.voxel_run_bridge.gen2_menus = true
local bagCallback = function() return "native-red-bag" end
local packRows = run.loader.hooks:call("ui.start_menu.items",
  function(_, rows) return rows end, screenGame, {
    { id = "vanilla.item", label = "ITEM", onSelect = bagCallback },
    { id = "vanilla.mods", label = "MODS" },
  })
T.eq(packRows[1].label, "PACK",
  "enabled built-in feature presents Red ITEM as PACK")
T.eq(packRows[1].onSelect, bagCallback,
  "PACK preserves the exact Red bag callback")
T.eq(packRows[2].id, "scotts_tweaks.pokegear",
  "POKeGEAR is inserted immediately after PACK")
T.eq(packRows[2].label, "POKéGEAR",
  "POKeGEAR uses its requested Start label")
local gen2Api = run.loader.exports.voxel_run_bridge.gen2Ui
T.eq(gen2Api.getStatus().romImport, false,
  "built-in Pokegear has no ROM-import dependency")
local pokegearScreen = buildScreen(gen2Api.screenIds.pokegear)
T.check(type(pokegearScreen.items) == "table"
    and #pokegearScreen.items == 2,
  "real Pokegear screen exposes Clock and Kanto Map")
T.check(type(pokegearScreen.items[1].label) == "string"
    and pokegearScreen.items[1].label:match("^CLOCK ") ~= nil,
  "real Pokegear screen renders a live clock row")
T.eq(pokegearScreen.items[2].label, "KANTO MAP",
  "real Pokegear screen routes to Red's Kanto Map")
local goldInventoryMenu = buildScreen(menuApi.screenIds.inventory)
local goldInventoryRows = {}
for _, row in ipairs(goldInventoryMenu.rows or {}) do
  local key = type(row.id) == "string"
    and row.id:match("^voxel_run_bridge:(.+)$") or nil
  if key then goldInventoryRows[key] = row end
end
T.check(type(goldInventoryRows.bag_pockets) == "table",
  "organized menu keeps the saved Classic Pockets preference reachable while PACK is enabled")
T.check(type(goldInventoryRows.experience_mode) == "table",
  "organized PACK inventory menu retains EXP mode")
run.loader.modOptions.voxel_run_bridge.gen2_menus = false

local writes = 0
screenGame.mods = run.loader
require("src.core.Game").mods = run.loader
screenGame.save.options = { modOptions = {} }
screenGame.writeOptions = function() writes = writes + 1 end
T.eq(organized.running_enabled.value(screenGame), "ON",
  "organized running row reads the central default")
organized.running_enabled.step(screenGame, 1)
T.eq(organized.running_enabled.value(screenGame), "OFF",
  "organized running row changes live")
T.eq(screenGame.save.options.modOptions.voxel_run_bridge.running_enabled,
  false, "organized row persists to save options")
T.eq(run.loader.modOptions.voxel_run_bridge.running_enabled, false,
  "organized row mirrors into Loader options")
T.eq(writes, 1, "organized row performs one option write")
organized.running_enabled.step(screenGame, -1)

T.eq(organized.free_fly_without_badges.value(screenGame), "ON",
  "organized Free Fly row reads the central default")
local writesBeforeFreeFly = writes
organized.free_fly_without_badges.step(screenGame, 1)
T.eq(organized.free_fly_without_badges.value(screenGame), "OFF",
  "organized Free Fly row changes the shared value")
T.eq(run.loader.exports.free_fly.testBadgeChecks(), true,
  "organized row emits the live event that restores Free Fly's preference")
T.eq(writes, writesBeforeFreeFly + 1,
  "organized Free Fly row performs one option write")
organized.free_fly_without_badges.step(screenGame, -1)
T.eq(run.loader.exports.free_fly.testBadgeChecks(), false,
  "turning organized Free Fly row back on reapplies the live override")

T.eq(organized.dual_screen.value(screenGame), "OFF",
  "Thor row shows the central OFF value without a legacy provider")
local liveThorApi = run.loader.exports.voxel_run_bridge.thorDualScreen
run.loader.exports.voxel_run_bridge.thorDualScreen = {
  getStatus = function() return {
    delegated = true, delegateId = "gen1recomp_ds",
    blockedReason = "delegated_to_gen1recomp_ds",
  } end,
}
local writesBeforeDelegated = writes
T.eq(organized.dual_screen.value(screenGame), "OTHER MOD",
  "legacy Dual Screen makes the organized Thor row non-authoritative")
T.eq(organized.dual_screen.step(screenGame, 1), false,
  "delegated Thor row refuses edits")
T.eq(writes, writesBeforeDelegated,
  "delegated Thor row performs no option write")
run.loader.exports.voxel_run_bridge.thorDualScreen = liveThorApi
T.eq(organized.dual_screen.value(screenGame), "OFF",
  "after legacy removal the Thor row returns to ON/OFF authority")
local writesBeforeThor = writes
organized.dual_screen.step(screenGame, 1)
T.eq(organized.dual_screen.value(screenGame), "ON",
  "organized Thor row changes the shared live value")
T.eq(liveThorApi.getMode(), "on",
  "organized Thor row notifies the installed presenter")
T.eq(screenGame.save.options.modOptions.voxel_run_bridge.dual_screen, true,
  "organized Thor row persists the central value")
T.eq(writes, writesBeforeThor + 1,
  "organized Thor row performs one option write")
organized.dual_screen.step(screenGame, -1)

local startRows = run.loader.hooks:call("ui.start_menu.items",
  function(_, rows) return rows end, screenGame, {
    { id = "vanilla.party", label = "POKEMON" },
    { id = "vanilla.mods", label = "MODS" },
  })
local startCount, battleArtCount = 0, 0
for _, row in ipairs(startRows) do
  if row.id == "scotts_tweaks.open" and row.label == "MOD SETTINGS" then
    startCount = startCount + 1
  end
  if row.label == "BATTLE ART" then battleArtCount = battleArtCount + 1 end
end
T.eq(startCount, 1, "Start exposes exactly one MOD SETTINGS entry")
T.eq(battleArtCount, 0, "Start exposes no competing Battle Art entry")

local bagScreen = buildScreen("BagMenu", {})
T.eq(bagScreen.title, "< ITEMS >",
  "real BagMenu opens in the Items pocket")
T.eq(bagScreen.items[1] and bagScreen.items[1].value,
  "SCOTTS_TRADE_STONE", "real BagMenu shows Trade Stone in Items")
pressed = "right"
bagScreen:update(0)
pressed = nil
T.eq(bagScreen.title, "< BALLS >",
  "real BagMenu follows Gold order from Items to Balls")
pressed = "right"
bagScreen:update(0)
pressed = nil
T.eq(bagScreen.title, "< KEY ITEMS >",
  "real BagMenu follows Gold order from Balls to Key Items")
T.eq(bagScreen.items[1] and bagScreen.items[1].value,
  "SCOTTS_EXP_SHARE", "real BagMenu shows EXP.SHARE in Key Items")
pressed = "right"
bagScreen:update(0)
pressed = nil
T.eq(bagScreen.title, "< TM/HM >",
  "real BagMenu follows Gold order from Key Items to TM/HM")
pressed = "right"
bagScreen:update(0)
pressed = nil
T.eq(bagScreen.title, "< ITEMS >",
  "real BagMenu wraps from TM/HM to Items")

local shopScreen = buildScreen("ShopMenu", {}, function() end)
stack:push(shopScreen)
pressed = "a"
shopScreen:update(0)
pressed = nil
local buyScreen = stack:top()
T.eq(buyScreen and buyScreen.title, "BUY", "real ShopMenu opens BUY")
T.eq(buyScreen and buyScreen.items[1] and buyScreen.items[1].value,
  "SCOTTS_TRADE_STONE", "real ShopMenu appends one Trade Stone")
T.eq(type(buyScreen and buyScreen._scottsTweaksOwnedCount), "table",
  "real BUY list receives the live bag-count decorator")

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
local providerExports = run.loader.exports.POKEMON_FINAL
local FirstPerson = providerExports and providerExports.testFirstPerson
local originalHidePlayer = FirstPerson and FirstPerson.hidePlayer
local cockpitControl = run.loader.exports.voxel_run_bridge.freeFlyCockpitControl
T.eq(cockpitControl and cockpitControl.active, true,
  "exact Free Fly 1.6.2 cockpit control activates through the loader")
freeFlyExports.testSetFlying(true)
hooks:call("render.hud", function() return "base-hud" end, {}, {})
T.eq(freeFlyExports.testCockpitDraws(), 0,
  "default-off cockpit suppresses Free Fly's first-person HUD picture")
T.eq(FirstPerson and FirstPerson.hidePlayer, originalHidePlayer,
  "loader HUD chain restores the provider's visibility function")
T.eq(FirstPerson and FirstPerson.hidePlayer(), true,
  "loader HUD chain leaves the world player-card rule unchanged")

run.loader.modOptions.voxel_run_bridge =
  run.loader.modOptions.voxel_run_bridge or {}
run.loader.modOptions.voxel_run_bridge.free_fly_cockpit = true
hooks:call("render.hud", function() return "base-hud" end, {}, {})
T.eq(freeFlyExports.testCockpitDraws(), 1,
  "FLY COCKPIT on restores Free Fly's original HUD picture")

run.loader.modOptions.voxel_run_bridge.free_fly_cockpit = false
FirstPerson.hidden = false
hooks:call("render.hud", function() return "base-hud" end, {}, {})
T.eq(freeFlyExports.testCockpitDraws(), 1,
  "third-person flight never gains a separate cockpit picture")
T.eq(FirstPerson.hidePlayer, originalHidePlayer,
  "third-person HUD leaves provider visibility ownership untouched")
FirstPerson.hidden = true

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
T.eq(exported.moduleErrors, nil,
  "all required consolidated modules install without a contained error")
T.eq(exported.trainerForfeit and exported.trainerForfeit.installed, true,
  "integrated trainer forfeit/rematches install")
T.eq(exported.trainerForfeit and exported.trainerForfeit.sourceVersion,
  "0.3.0", "trainer feature records its incorporated source version")
T.eq(exported.oakSpareStarter and exported.oakSpareStarter.installed, true,
  "integrated Oak spare starter installs")
T.eq(exported.oakSpareStarter and exported.oakSpareStarter.sourceVersion,
  "0.1.1", "Oak feature records its incorporated source version")
T.eq(exported.running and exported.running.installed, true,
  "integrated B-button running producer installs")
T.eq(exported.running and exported.running.alwaysAvailable, true,
  "running does not require a story unlock")
T.eq(exported.migrations and exported.migrations.installed, true,
  "legacy migration adapter installs")
T.eq(exported.tweaksMenu and exported.tweaksMenu.installed, true,
  "categorized Scott's Tweaks menu installs")
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
T.eq(pokemonFinalExports.lib._voxelRunBridgeHook.version, "0.12.1",
  "Pokemon Final bridge marker carries the update version")
T.eq(type(exported.hmWithoutBadges), "function",
  "live HM option accessor is published")
T.eq(exported.hmWithoutBadges(), true, "live HM option reports enabled")
T.eq(exported.bagPockets and exported.bagPockets.active, true,
  "Bag Pockets status is published")
T.eq(exported.shopTweaks and exported.shopTweaks.price, 500,
  "shop status publishes the Trade Stone price")
T.eq(exported.tradeStone and exported.tradeStone.id, "SCOTTS_TRADE_STONE",
  "Trade Stone status is published")
T.eq(exported.experience and exported.experience.mode, "vanilla",
  "EXP status starts in the safe vanilla mode")

run.release()
T.finish("Scott's Tweaks full load")
