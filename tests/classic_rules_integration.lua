-- Production-loader regression for the non-destructive original-rules profile.
-- Run CLASSIC and CUSTOM in separate processes because the engine owns globals:
--   luajit tests/classic_rules_integration.lua <mod-root> <engine-root> <file-list> classic
--   luajit tests/classic_rules_integration.lua <mod-root> <engine-root> <file-list> custom
--   luajit tests/classic_rules_integration.lua <mod-root> <engine-root> <file-list> classic_early
local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local listPath = assert(argv[3], "file list required")
local mode = argv[4] or "classic"
assert(mode == "classic" or mode == "custom" or mode == "classic_early",
  "mode must be classic, custom, or classic_early")
local classic = mode ~= "custom"
local early = mode == "classic_early"

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.modkit")
local Serializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local EngineGame = require("src.core.Game")
local Runtime = require("src.mods.Runtime")
local prefix = "mods/voxel_run_bridge/"
local files = {}
local count = 0
for relative in io.lines(listPath) do
  if relative ~= "" then
    local handle = assert(io.open(sourceRoot .. "/" .. relative, "rb"))
    files[prefix .. relative] = handle:read("*a")
    handle:close()
    count = count + 1
  end
end
T.check(count > 80, "real fused source tree is staged")
T.check(files[prefix .. "modules/classic_rules.lua"] ~= nil,
  "classic profile source is staged")

-- Deliberately contradictory old custom choices: effective rules must win
-- without rewriting these preferences or any already-earned save rewards.
local requested = {
  classic_rules = classic,
  early_flight = early,
  hm_without_badges = true,
  free_fly_without_badges = true,
  experience_mode = "all",
  trainer_forfeit_enabled = true,
  trainer_rematches = true,
  trainer_growth = "gentle",
  oak_spare_starter = true,
  running_enabled = true,
  running_speed = 1.5,
  ["free_fly:quickstart"] = true,
  ["free_fly:badges"] = false,
  ["free_fly:gates"] = false,
  ["overworld_wild_spawns:enabled"] = true,
  ["overworld_wild_spawns:random_encounters"] = false,
  ["overworld_wild_spawns:enable_hidden"] = true,
  ["Dynamic_Scaling:randomize"] = "chaos",
  ["Dynamic_Scaling:trainer_difficulty"] = "hard",
  ["Dynamic_Scaling:boss_difficulty"] = "medium",
  ["Dynamic_Scaling:wild_difficulty"] = "normal",
}
files["options.lua"] = Serializer.encode({
  mods = { voxel_run_bridge = true },
  modOptions = { voxel_run_bridge = requested },
})
local fs = T.sdk.memfs(files)
local data = require("tests.modkit.fixtures").fresh()
EngineGame.data = data
EngineGame.save = SaveData.newGame()
EngineGame.save.options = SaveData.loadOptions(fs)
EngineGame.mods = nil
EngineGame.overworld = nil
EngineGame.input = {
  isDown = function() return false end,
  wasPressed = function() return false end,
}
EngineGame.stack = { states = {} }
function EngineGame.stack:top() return self.states[#self.states] end
function EngineGame.stack:pop() return table.remove(self.states) end
function EngineGame.stack:push(value) self.states[#self.states + 1] = value end
local writes = 0
function EngineGame:writeOptions() writes = writes + 1 return true end

local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = data, fs = fs, generation = 1,
})
local unexpected, dexGap = {}, 0
for _, e in ipairs(run.errors) do
  local message = type(e) == "table" and (e.message or e.text or "") or tostring(e)
  if not classic and (message:find("unresolved reference to pokemon", 1, true)
      or message:find("unresolved reference to maps", 1, true)) then
    dexGap = dexGap + 1
  else
    unexpected[#unexpected + 1] = message
  end
end
T.eq(#unexpected, 0, "no unexpected production-loader errors: "
  .. table.concat(unexpected, " | "):sub(1, 300))
if classic then
  T.eq(#run.errors, 0, "classic skips fixture-incompatible catchable content completely")
else
  T.check(dexGap > 0, "custom retains known catchable fixture reference gap")
end
EngineGame.data, EngineGame.mods = run.data, run.loader
local exports = assert(run.loader.exports.voxel_run_bridge)
local profile = assert(exports.classicRules)
local host = assert(exports.vendorHost)
T.eq(profile:enabled(), classic, "boot snapshot reflects requested profile")
T.eq(profile:status().restartRequired, false, "new boot is a coherent rules profile")
T.eq(exports.fusedRenderer.installed, true, "fused renderer remains installed")
T.check(type(exports.lib.require("FirstPerson")) == "table",
  "first-person renderer remains available")
T.eq(exports.freeFlyCockpitControl.active, true, "first-person flight presentation remains attached")
T.eq(host.loaded.all_pokemon_catchable_151_mod ~= nil, not classic,
  "catchable encounter/evolution patches follow the boot rules")
T.eq(host:readOption("free_fly", "quickstart"), not classic,
  "classic stops new free gift Pokemon without changing the custom preference")
T.eq(host:readOption("free_fly", "badges"), classic,
  "classic restores the Free Fly badge check")
T.eq(host:readOption("free_fly", "gates"), classic,
  "classic restores story gates even over a saved OFF preference")
T.eq(host:readOption("free_fly", "scotts_early_fly"), early,
  "earned early flight stays an explicit independent travel preference")
T.eq(exports.settings.get("early_flight"), early, "effective early-flight preference stays independent")
T.eq(exports.settings.get("hm_without_badges"), not classic, "HM gameplay rules use the profile")
T.eq(exports.settings.get("experience_mode"), classic and "vanilla" or "all",
  "EXP gameplay rules use the profile")
T.eq(exports.settings.get("oak_spare_starter"), not classic, "Oak gift rules use the profile")
T.eq(exports.settings.get("trainer_forfeit_enabled"), not classic,
  "trainer forfeit rules use the profile")
T.eq(exports.settings.get("trainer_rematches"), not classic, "rematch rules use the profile")
T.eq(exports.settings.get("trainer_growth"), classic and "off" or "gentle",
  "trainer growth rules use the profile")
T.eq(exports.settings.get("running_enabled"), true, "running remains an independent convenience")
T.eq(exports.settings.get("running_speed"), 1.5, "running preference is preserved")

-- Attach the real service owner and actual saved options to exercise the
-- vendors' raw-save readers and their cached lifecycle state, not just getters.
run.loader.events:emit("game.ready", { game = EngineGame })
local wildHandle = assert(host.loaded.overworld_wild_spawns)
local wildExports = wildHandle.exports
local wildV = wildExports.lib
local wildMod = wildV.mod
local WildConfig = wildV.require("config")
T.eq(WildConfig.isEnabled(wildMod), not classic, "cached Wilds enable state uses the profile")
T.eq(WildConfig.randomEncountersEnabled(wildMod), classic,
  "classic random encounters override explicit saved FALSE")
T.eq(WildConfig.get(wildMod, "enable_hidden"), not classic,
  "classic never leaves sprite-less hidden encounters enabled")
T.eq(wildExports.encounterMode(), classic and "classic" or "custom",
  "Wilds reports the effective encounter rules")
local scaling = assert(host.loaded.Dynamic_Scaling.exports.dynamicScaling)
local C = assert(scaling.config)
T.eq(C.randomize, classic and "off" or "chaos", "cached trainer randomizer uses effective rules")
T.eq(C.trainerDifficulty, classic and "off" or "hard", "cached trainer tier uses effective rules")
T.eq(C.bossDifficulty, classic and "off" or "medium", "cached boss tier uses effective rules")
T.eq(C.wildDifficulty, classic and "off" or "normal", "cached wild tier uses effective rules")
if classic then
  run.loader.events:emit("mod.options_changed", {
    mod = "Dynamic_Scaling", key = "trainer_difficulty", value = "hard",
  })
  T.eq(C.trainerDifficulty, "off", "stale options event cannot bypass classic trainer rules")
  run.loader.events:emit("mod.options_changed", {
    mod = "Dynamic_Scaling", key = "randomize", value = "chaos",
  })
  T.eq(C.randomize, "off", "stale options event cannot bypass classic trainer teams")
end
local saved = EngineGame.save.options.modOptions.voxel_run_bridge
for key, value in pairs(requested) do
  T.eq(saved[key], value, "saved custom preference is untouched: " .. key)
end
T.eq(saved["free_fly:quickstart"], true, "disabling gifts never erases saved custom choice")
T.eq(saved["overworld_wild_spawns:random_encounters"], false,
  "random encounter overlay never rewrites the custom choice")
local schema = {}
for _, definition in ipairs(run.loader.optionSchemas.voxel_run_bridge or {}) do
  schema[definition.key] = definition
end
T.eq(schema.classic_rules and schema.classic_rules.default, false,
  "new profile does not silently change existing default behavior")
T.eq(schema.early_flight and schema.early_flight.default, false,
  "earned early flight requires an explicit player choice")

local stoneTarget = { species = "FIXMON_A" }
run.data.pokemon.FIXMON_A.evolutions = {
  { method = "TRADE", species = "FIXMON_B" },
}
EngineGame.save.inventory.SCOTTS_TRADE_STONE = 1
local stoneEffect = assert(run.data.item_effects.SCOTTS_TRADE_STONE_EFFECT)
local stoneResult, _, stoneEffectArgs = stoneEffect.use({
  data = run.data, save = EngineGame.save, target = stoneTarget,
})
T.eq(stoneResult, classic and "failed" or "consumed",
  "classic blocks Trade Stone while custom use remains intact")
if classic then
  T.eq(stoneEffectArgs, nil, "classic cannot queue a trade-stone evolution")
else
  T.eq(stoneEffectArgs and stoneEffectArgs.evolveTo, "FIXMON_B",
    "custom trade-stone evolution remains intact")
end
T.eq(EngineGame.save.inventory.SCOTTS_TRADE_STONE, 1,
  "profile never confiscates a previously-owned Trade Stone")
T.eq(stoneTarget.species, "FIXMON_A", "profile never rewrites an owned species")

-- A pre-existing gifted bird must earn the ordinary flight badge in classic
-- mode; do not remove its marker, FLY move, Pokemon, or any reward to do so.
local mon = { species = "FIXMON_A", hp = 20, moves = {
  { id = "FLY", pp = 15 }, { id = "CUT", pp = 30 },
}, freeFlyGift = true }
EngineGame.save.party = { mon }
EngineGame.save.inventory.THUNDERBADGE = nil
local ow = { isOverworld = true, map = {
  id = "FIX_ROUTE", def = { tileset = "OVERWORLD", index = 0 },
}, player = { onBike = false } }
EngineGame.overworld = ow
local function freeFlyRow()
  local rows = run.loader.hooks:call("ui.party.submenu",
    function(_, items) return items end,
    EngineGame, {}, mon, { overworld = ow })
  for _, row in ipairs(rows or {}) do
    if row.label == "FREEFLY" then return row end
  end
end
T.eq(freeFlyRow() ~= nil, not classic, "gift does not bypass classic flight badge")
EngineGame.save.inventory.THUNDERBADGE = 1
T.check(freeFlyRow() ~= nil, "ordinary earned flight remains available")
T.eq(mon.freeFlyGift, true, "flight rules never erase the gift marker")
T.eq(mon.moves[1].id, "FLY", "flight rules never erase an owned move")
T.eq(EngineGame.save.party[1], mon, "flight rules never replace the owned Pokemon")
EngineGame.save.inventory.THUNDERBADGE = nil
local eligible = Runtime.call("fieldmove.eligibility", function() return nil end,
  "CUT", { save = EngineGame.save })
local expectedEligible
if not classic then expectedEligible = mon end
T.eq(eligible, expectedEligible, "real HM hook preserves classic badge refusal")
local baseAwards, shareAwards = 0, 0
Runtime.call("battle.exp_award", function() baseAwards = baseAwards + 1 end, {
  battle = { game = EngineGame, player = { mon = mon }, party = { mon } },
  applyShare = function() shareAwards = shareAwards + 1 end,
})
T.eq(baseAwards, classic and 1 or 0, "classic delegates real EXP awards to the original engine")
T.eq(shareAwards, classic and 0 or 1, "custom sharing remains available outside classic")

if early then
  -- This is the explicit movement exception to classic story/battle rules:
  -- an earned first badge and a caught compatible party member, with no FLY
  -- move or HM ownership. The same real menu hook must enforce all three.
  mon.freeFlyGift = nil
  mon.moves = { { id = "CUT", pp = 30 } }
  local beforeMoves = mon.moves
  run.data.pokemon.FIXMON_A.tmhm = { "FLY" }
  T.eq(freeFlyRow(), nil, "earned early flight is unavailable before the first badge")
  EngineGame.save.inventory.BOULDERBADGE = 1
  T.check(freeFlyRow() ~= nil, "classic plus explicit early flight accepts an earned compatible partner")
  mon.hp = 0
  T.eq(freeFlyRow(), nil, "fainted party member cannot provide earned early flight")
  mon.hp = 20
  EngineGame.save.party = {}
  T.eq(freeFlyRow(), nil, "preview or PC descriptor cannot provide earned early flight")
  EngineGame.save.party = { mon }
  T.eq(mon.moves, beforeMoves, "early flight never changes the move table")
  T.eq(#mon.moves, 1, "early flight never teaches a move")
  T.eq(EngineGame.save.inventory.HM02, nil, "early flight never grants an HM")
  T.eq(EngineGame.save.inventory.THUNDERBADGE, nil, "early flight never grants a later badge")
  T.eq(host:readOption("free_fly", "badges"), true, "early flight retains ordinary water badge protection")
  T.eq(host:readOption("free_fly", "gates"), true, "early flight retains story gates")
end

-- The ordinary unified menu persists ONLY the requested profile. Its restart
-- notice must be honest: loaded content and cached gameplay stay coherent.
local Screens = require("src.ui.Screens")
Screens.invalidate()
if not classic then
  -- User-selected difficulty and visible-wild customizations remain ordinary
  -- editable features. Cycling a control never modifies a different tier,
  -- and returning to the initial choice restores its saved preference.
  saved.simple_menu = false
  run.loader.modOptions.voxel_run_bridge.simple_menu = false
  local battles = Screens.build(EngineGame, exports.tweaksMenu.screenIds.battles)
  local wilds = Screens.build(EngineGame, exports.tweaksMenu.screenIds.wilds)
  local function rowById(rows, id)
    for _, candidate in ipairs(rows or {}) do
      if candidate.id == id then return candidate end
    end
  end
  local difficultyOrder = { "off", "normal", "medium", "hard" }
  local function selectableDifficulty(rows, key, field, initial)
    local option = assert(rowById(rows, "Dynamic_Scaling:" .. key))
    T.check(option.value() ~= "CLASSIC", "Custom unlocks " .. key)
    local currentIndex
    for index, value in ipairs(difficultyOrder) do
      if value == initial then currentIndex = index end
    end
    for offset = 1, 4 do
      local wanted = difficultyOrder[((currentIndex - 1 + offset) % 4) + 1]
      T.eq(option.step(EngineGame, 1), true, "Custom can select " .. key .. ":" .. wanted)
      T.eq(host:readOption("Dynamic_Scaling", key), wanted,
        "Custom stores selected " .. key .. ":" .. wanted)
      T.eq(C[field], wanted, "Custom applies selected " .. key .. ":" .. wanted .. " live")
    end
    T.eq(saved["Dynamic_Scaling:" .. key], initial, "cycling preserves initial " .. key)
  end
  selectableDifficulty(battles.rows, "trainer_difficulty", "trainerDifficulty", "hard")
  T.eq(C.bossDifficulty, "medium", "trainer edits leave selected boss tier intact")
  T.eq(C.wildDifficulty, "normal", "trainer edits leave selected wild tier intact")
  selectableDifficulty(battles.rows, "boss_difficulty", "bossDifficulty", "medium")
  T.eq(C.trainerDifficulty, "hard", "boss edits leave selected trainer tier intact")
  selectableDifficulty(wilds.rows, "wild_difficulty", "wildDifficulty", "normal")
  T.eq(C.bossDifficulty, "medium", "wild edits leave selected boss tier intact")
  local teamRow = assert(rowById(battles.rows, "Dynamic_Scaling:randomize"))
  for _, wanted in ipairs({ "themed", "off", "chaos" }) do
    T.eq(teamRow.step(EngineGame, 1), true, "Custom can select trainer teams " .. wanted)
    T.eq(C.randomize, wanted, "Custom applies trainer teams " .. wanted .. " live")
  end
  T.eq(saved["Dynamic_Scaling:randomize"], "chaos", "cycling restores selected trainer teams")
  local encounterRow = assert(rowById(wilds.rows, "overworld_wild_spawns:encounter_mode"))
  for _, wanted in ipairs({ "visible", "both", "classic", "off" }) do
    T.eq(encounterRow.step(EngineGame, 1), true, "Custom can select encounter mode " .. wanted)
    T.eq(wildExports.encounterMode(), wanted, "Custom applies encounter mode " .. wanted .. " live")
  end
  T.eq(host:writeOptions(EngineGame, "overworld_wild_spawns", {
    { key = "enabled", value = true },
    { key = "random_encounters", value = false },
    { key = "enable_hidden", value = true },
  }), true, "Custom can restore its prior independent wild preferences")
  T.eq(wildExports.encounterMode(), "custom", "prior custom encounter combination remains supported")
  local densityRow = assert(rowById(wilds.rows, "overworld_wild_spawns:spawn_density"))
  local density = host:readOption("overworld_wild_spawns", "spawn_density")
  T.eq(densityRow.step(EngineGame, 1), true, "Custom spawn amount stays selectable")
  T.check(host:readOption("overworld_wild_spawns", "spawn_density") ~= density,
    "Custom spawn amount edit changes its actual setting")
  T.eq(densityRow.step(EngineGame, -1), true, "Custom spawn amount can restore its prior choice")
  T.eq(host:readOption("overworld_wild_spawns", "spawn_density"), density,
    "Custom spawn amount restored without affecting encounter mode")
  T.eq(wildExports.encounterMode(), "custom", "spawn amount leaves custom encounter choice intact")

  -- Already-open rows must react to the optional travel mode, not capture its
  -- value at screen construction and let competing switches fight.
  saved.simple_menu = false
  run.loader.modOptions.voxel_run_bridge.simple_menu = false
  local movement = Screens.build(EngineGame, exports.tweaksMenu.screenIds.movement)
  local flyNow, earlyRow, giftRow
  for _, candidate in ipairs(movement.rows or {}) do
    if candidate.label == "FREE FLY NOW" then flyNow = candidate end
    if candidate.label == "EARLY FLY (BROCK)" then earlyRow = candidate end
    if candidate.id == "free_fly:quickstart" then giftRow = candidate end
  end
  T.check(flyNow and earlyRow and giftRow, "movement rows expose earned-flight controls")
  T.eq(earlyRow.step(EngineGame), true, "earned flight can be enabled from the open menu")
  T.eq(flyNow.value(), "EARLY MODE", "global bypass clearly yields to earned flight")
  T.eq(giftRow.value(), "EARLY MODE", "already-open gift row yields to earned flight")
  T.eq(flyNow.step(EngineGame), false, "global bypass cannot fight earned flight")
  T.eq(giftRow.step(EngineGame), false, "gift shortcut cannot fight earned flight")
  T.eq(host:readOption("free_fly", "badges"), true, "earned mode forces normal water badge checks")
  T.eq(host:readOption("free_fly", "quickstart"), false, "earned mode cannot grant a gift")
  T.eq(earlyRow.step(EngineGame), true, "earned flight can be disabled from the same menu")
  T.eq(flyNow.value(), "ON", "custom bypass preference returns without rewriting it")
  T.check(giftRow.value() ~= "EARLY MODE", "same open gift row unlocks when early mode ends")
end
local screen = Screens.build(EngineGame, exports.tweaksMenu.screenIds.main)
local row
for _, candidate in ipairs(screen.rows or {}) do
  if candidate.label == "CLASSIC RULES" then row = candidate break end
end
T.check(row ~= nil, "profile is reachable in the simple unified menu")
T.eq(row and row.value(), classic and "ON" or "OFF", "menu reports active boot profile")
local writesBefore = writes
T.eq(row and row.step(EngineGame), true, "menu profile selection persists successfully")
T.eq(writes, writesBefore + 1, "profile selection writes exactly once")
T.eq(profile:requested(), not classic, "profile selection records the next requested boot")
T.eq(profile:enabled(), classic, "profile selection leaves current runtime coherent")
T.eq(row.value(), "RESTART", "profile selection clearly announces restart")
T.eq(host.loaded.all_pokemon_catchable_151_mod ~= nil, not classic,
  "pending selection never claims boot content was rolled back live")
T.eq(WildConfig.randomEncountersEnabled(wildMod), classic,
  "pending selection never produces hybrid encounter rules")
T.eq(exports.settings.get("experience_mode"), classic and "vanilla" or "all",
  "pending selection never produces hybrid EXP rules")
T.eq(saved.experience_mode, "all", "pending selection preserves prior EXP preference")
T.eq(saved.oak_spare_starter, true, "pending selection preserves prior Oak preference")

run.release()
T.finish("Scott's Tweaks classic rules integration " .. mode)
