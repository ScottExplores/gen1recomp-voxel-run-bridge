-- Focused checks for the split Dynamic Scaling controls and the one-real-hour
-- game clock.  The battle constructors model the cache fields shared by
-- Gen1Recomp 0.1.75 through 0.1.96, so the test runs without a ROM.

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end
local function eq(actual, expected, message)
  check(actual == expected, message .. " (expected " .. tostring(expected)
    .. ", got " .. tostring(actual) .. ")")
end

local function newMon(_, species, level)
  return {
    species = species, level = level,
    moves = { { id = "TACKLE", pp = 35 } },
    dvs = { attack = 7, defense = 7, speed = 7, special = 7, hp = 7 },
    statExp = { attack = 0, defense = 0, speed = 0, special = 0, hp = 0 },
    stats = { hp = level * 2 }, hp = level * 2,
  }
end

local Pokemon = { new = newMon }
local Stats = {
  calc = function(_, level, dvs, statExp)
    local bonus = (dvs and dvs.attack == 15) and 10 or 0
    if statExp and statExp.attack == 65535 then bonus = bonus + 10 end
    return { hp = level * 2 + bonus, attack = level + bonus }
  end,
}

local function battler(mon)
  return {
    mon = mon, species = mon.species, name = mon.species,
    level = mon.level, curTypes = { "NORMAL" }, curMoves = mon.moves,
    stats = mon.stats, curStats = mon.stats,
    hp = mon.hp, maxHP = mon.stats.hp, shownHP = mon.hp,
  }
end

local rawTrainerCalls, rawWildCalls = 0, 0
local BattleState = {}
function BattleState.newTrainer(game, trainerId, partyIndex)
  rawTrainerCalls = rawTrainerCalls + 1
  local one = newMon(game.data, "RATTATA", 10)
  local two = newMon(game.data, "RATICATE", 12)
  return {
    kind = "trainer", oppClass = trainerId, partyIndex = partyIndex,
    enemyParty = { one, two }, enemy = battler(one), enemyAIMods = { 9 },
  }
end
function BattleState.newWild(game, species, level)
  rawWildCalls = rawWildCalls + 1
  local mon = newMon(game.data, species, level)
  return { kind = "wild", enemy = battler(mon) }
end

local listeners, schema = {}, nil
local writes, writeManyCalls = 0, 0
local hostId, vendorId = "voxel_run_bridge", "Dynamic_Scaling"
local prefix = vendorId .. ":"
local Game = {
  data = {
    pokemon = {
      RATTATA = { dex = 19, name = "RATTATA", types = { "NORMAL" },
        evolutions = { { method = "LEVEL", level = 20, species = "RATICATE" } } },
      RATICATE = { dex = 20, name = "RATICATE", types = { "NORMAL" } },
      PIDGEY = { dex = 16, name = "PIDGEY", types = { "NORMAL", "FLYING" } },
    },
    moves = { TACKLE = { pp = 35 } },
    trainers = {
      OPP_LASS = { name = "LASS" },
      OPP_BROCK = { name = "BROCK" },
      FUTURE_BOSS = { name = "TEST", boss = true },
    },
  },
  save = {
    party = { { level = 20 }, { level = 24 } },
    inventory = { BOULDERBADGE = 1 },
    options = { modOptions = {
      [hostId] = { [prefix .. "difficulty"] = "medium" },
    } },
  },
  mods = { modOptions = {
    [hostId] = { [prefix .. "difficulty"] = "medium" },
  } },
}
function Game:writeOptions() writes = writes + 1; return true end

local options = {
  hosted = { hostId = hostId, vendorId = vendorId, prefix = prefix },
}
function options:define(rows) schema = rows; return rows end
function options:get(key)
  local bucket = Game.mods.modOptions[hostId] or {}
  local stored = bucket[prefix .. key]
  if stored ~= nil then return stored end
  for _, row in ipairs(schema or {}) do
    if row.key == key then return row.default end
  end
end
local function writeRoot(game, holder, changes)
  if type(holder) ~= "table" then return end
  holder.modOptions = holder.modOptions or {}
  holder.modOptions[hostId] = holder.modOptions[hostId] or {}
  for _, change in ipairs(changes) do
    holder.modOptions[hostId][prefix .. change.key] = change.value
  end
end
function options:writeMany(game, changes)
  writeManyCalls = writeManyCalls + 1
  writeRoot(game, game.save and game.save.options, changes)
  writeRoot(game, game.mods, changes)
  game:writeOptions()
  return true
end

local events = {}
function events:on(name, callback)
  listeners[name] = listeners[name] or {}
  listeners[name][#listeners[name] + 1] = callback
end
function events:emit(name, payload)
  for _, callback in ipairs(listeners[name] or {}) do callback(payload) end
end

local rowsHook
local mod = {
  id = vendorId, exports = {}, options = options, events = events,
  hooks = { wrap = function(_, name, callback)
    if name == "ui.options.rows" then rowsHook = callback end
  end },
  log = { info = function() end, warn = function() end },
}

package.loaded["src.battle.BattleState"] = nil
package.loaded["src.pokemon.Pokemon"] = nil
package.loaded["src.pokemon.Stats"] = nil
package.loaded["src.core.Game"] = nil
package.preload["src.battle.BattleState"] = function() return BattleState end
package.preload["src.pokemon.Pokemon"] = function() return Pokemon end
package.preload["src.pokemon.Stats"] = function() return Stats end
package.preload["src.core.Game"] = function() return Game end
_G.__DYNAMIC_SCALING = nil

local install = assert(loadfile("vendor/dynamic_scaling/main.lua"))()
install(mod)
local api = assert(mod.exports.dynamicScaling)

local schemaByKey, duplicates = {}, 0
for _, row in ipairs(schema or {}) do
  if schemaByKey[row.key] then duplicates = duplicates + 1 end
  schemaByKey[row.key] = row
end
eq(duplicates, 0, "difficulty schema has no duplicate keys")
eq(schemaByKey.difficulty, nil, "legacy one-size difficulty row is retired")
for _, key in ipairs({
  "trainer_difficulty", "boss_difficulty", "wild_difficulty",
}) do
  check(type(schemaByKey[key]) == "table", key .. " is defined")
  eq(schemaByKey[key] and schemaByKey[key].default, "off",
    key .. " defaults OFF on a new install")
  eq(#(schemaByKey[key] and schemaByKey[key].choices or {}), 4,
    key .. " keeps all four existing tiers")
end

-- The immediate hot-load reconciliation sees the old fused key and persists
-- all three replacements in a single transaction without deleting it.
eq(writeManyCalls, 1, "legacy split migration is one transaction")
eq(writes, 1, "legacy split migration is one durable write")
local migrated = Game.save.options.modOptions[hostId]
for _, key in ipairs({
  "trainer_difficulty", "boss_difficulty", "wild_difficulty",
}) do
  eq(migrated[prefix .. key], "medium",
    "legacy MEDIUM seeds " .. key)
end
eq(migrated[prefix .. "difficulty"], "medium",
  "legacy value remains available to an older release")
eq(api.config.trainerDifficulty, "medium", "trainer runtime adopts migration")
eq(api.config.bossDifficulty, "medium", "boss runtime adopts migration")
eq(api.config.wildDifficulty, "medium", "wild runtime adopts migration")

check(api.isBoss(Game, "OPP_BROCK"), "Gym Leader class is a boss")
check(api.isBoss(Game, "OPP_LORELEI"), "Elite Four class is a boss")
check(api.isBoss(Game, "OPP_RIVAL3"), "Champion rival class is a boss")
check(api.isBoss(Game, "FUTURE_BOSS"), "future explicit boss metadata is honored")
eq(api.isBoss(Game, "OPP_LASS"), false, "ordinary trainer is not a boss")

events:emit("mod.options_changed", {
  mod = vendorId, key = "trainer_difficulty", value = "normal",
})
events:emit("mod.options_changed", {
  mod = vendorId, key = "boss_difficulty", value = "hard",
})
events:emit("mod.options_changed", {
  mod = vendorId, key = "wild_difficulty", value = "normal",
})

local trainer = BattleState.newTrainer(Game, "OPP_LASS", 1)
eq(#trainer.enemyParty, 2, "NORMAL trainer keeps the vanilla party size")
eq(trainer.enemyParty[1].level, 22,
  "NORMAL trainer retains the original curve at player average +2")
eq(trainer.enemyParty[2].level, 24,
  "NORMAL trainer retains relative party level spacing")
eq(trainer.enemyAIMods[1], 9, "NORMAL trainer keeps vanilla AI")

local boss = BattleState.newTrainer(Game, "OPP_BROCK", 1)
eq(#boss.enemyParty, 6, "HARD boss retains the six-Pokemon rule")
eq(boss.enemyParty[1].level, 30,
  "HARD boss retains the original curve at player average +10")
eq(boss.enemyParty[2].level, 32,
  "HARD boss retains relative party level spacing")
eq(boss.enemyAIMods[1], 1, "HARD boss receives boss AI")
eq(boss.enemyParty[1].statExp.attack, 65535,
  "HARD boss retains maximum stat experience")
eq(boss.enemy.level, boss.enemyParty[1].level,
  "trainer HUD cache follows the rebuilt lead")

local wild = BattleState.newWild(Game, "PIDGEY", 4)
eq(wild.enemy.mon.species, "PIDGEY", "wild scaling preserves species")
eq(wild.enemy.mon.level, 24,
  "NORMAL wild Pokemon uses player average +2")
eq(wild.enemy.level, 24, "wild HUD cache follows the scaled monster")
eq(wild.enemy.maxHP, wild.enemy.mon.stats.hp,
  "wild HP cache follows the scaled monster")

events:emit("mod.options_changed", {
  mod = vendorId, key = "wild_difficulty", value = "hard",
})
local hardWild = BattleState.newWild(Game, "PIDGEY", 4)
eq(hardWild.enemy.mon.level, 32, "HARD wild Pokemon keeps the +10 tier")
eq(hardWild.enemy.mon.statExp.attack, 65535,
  "HARD wild Pokemon receives maximum stat experience")

events:emit("mod.options_changed", {
  mod = vendorId, key = "wild_difficulty", value = "off",
})
local vanillaWild = BattleState.newWild(Game, "PIDGEY", 4)
eq(vanillaWild.enemy.mon.level, 4, "OFF leaves a wild level untouched")

-- A partially migrated save keeps its explicit trainer choice and seeds only
-- the missing boss/wild choices from the old value.
local partial = {
  data = Game.data,
  save = { party = Game.save.party, inventory = Game.save.inventory,
    options = { modOptions = { [hostId] = {
      [prefix .. "difficulty"] = "hard",
      [prefix .. "trainer_difficulty"] = "normal",
    } } } },
  mods = { modOptions = { [hostId] = {
    [prefix .. "difficulty"] = "hard",
    [prefix .. "trainer_difficulty"] = "normal",
  } } },
  writeOptions = Game.writeOptions,
}
local beforePartial = writeManyCalls
api.refreshOptions(partial, true)
eq(writeManyCalls, beforePartial + 1,
  "partial migration writes its missing controls once")
local partialSaved = partial.save.options.modOptions[hostId]
eq(partialSaved[prefix .. "trainer_difficulty"], "normal",
  "partial migration preserves an explicit trainer choice")
eq(partialSaved[prefix .. "boss_difficulty"], "hard",
  "partial migration seeds the boss choice")
eq(partialSaved[prefix .. "wild_difficulty"], "hard",
  "partial migration seeds the wild choice")

-- Reloading the module refreshes callbacks but never stacks constructors.
local stableTrainer, stableWild = BattleState.newTrainer, BattleState.newWild
install(mod)
eq(BattleState.newTrainer, stableTrainer, "hot reload keeps one trainer wrapper")
eq(BattleState.newWild, stableWild, "hot reload keeps one wild wrapper")
check(rawTrainerCalls >= 2 and rawWildCalls >= 3,
  "every wrapped constructor delegates to the engine constructor")

-- The standalone row surface mirrors the three controls. The fused host
-- suppresses this hook and uses the categorized Scott's Tweaks rows instead.
local rows = rowsHook(function(_, current) return current end, Game, {})
local rowLabels = {}
for _, row in ipairs(rows) do rowLabels[row.label] = true end
for _, label in ipairs({
  "TRAINER DIFFICULTY", "BOSS DIFFICULTY", "WILD DIFFICULTY",
}) do
  check(rowLabels[label], "standalone options include " .. label)
end

-- Day/night keeps its saved `hour` token but gives the two running clocks
-- unambiguous game-time labels.
local dayValue = "hour"
local dayV = {
  mod = { id = "voxel_run_bridge", options = {
    get = function(_, key) return key == "daytime" and dayValue or nil end,
  } },
}
package.loaded["src.render.PaletteFX"] = nil
package.preload["src.render.PaletteFX"] = function() return {} end
dayV.require = function(name)
  if name == "ModSetting" then
    local chunk = assert(loadfile("lib/ModSetting.lua"))
    return chunk(dayV)
  end
  if name == "Astronomy" then
    return assert(loadfile("lib/Astronomy.lua"))(dayV)
  end
  error("unexpected DayNight dependency: " .. tostring(name))
end
local DayNight = assert(loadfile("lib/DayNight.lua"))(dayV)
eq(DayNight.setting:get(), "hour", "saved one-hour token survives reload")
eq(DayNight.setting.labels[1], "REAL CLOCK", "wall clock label is explicit")
eq(DayNight.setting.labels[6], "GAME 20 MIN",
  "short game cycle label is explicit")
eq(DayNight.setting.labels[7], "GAME 1 HOUR",
  "one-hour game cycle label is explicit")
eq(DayNight.PERIOD.hour, 3600, "one game day is exactly one real hour")
DayNight.clock = 0
DayNight.update(900)
eq(DayNight.clock, 300, "fifteen real minutes advances one quarter-day")
DayNight.update(2700)
eq(DayNight.clock, 0, "one real hour returns to the same game time")
dayValue = "sync"
DayNight.setting:sync("sync")
DayNight.hours = function() return 12 end
eq(DayNight.time(), DayNight.T.day,
  "REAL CLOCK remains the original local-time synchronization")

for _, name in ipairs({
  "src.battle.BattleState", "src.pokemon.Pokemon", "src.pokemon.Stats",
  "src.core.Game", "src.render.PaletteFX",
}) do
  package.loaded[name] = nil
  package.preload[name] = nil
end
_G.__DYNAMIC_SCALING = nil

if failures > 0 then error(tostring(failures) .. " focused checks failed") end
print(("Dynamic scaling + day/night: %d checks passed"):format(checks))
