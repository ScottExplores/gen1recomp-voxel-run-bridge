-- Runs the split scaler through a real Gen1Recomp BattleState/Pokemon/Stats
-- stack. Invoke once per supported engine fixture with Lua and LuaJIT:
--   lua tests/dynamic_scaling_engine_compat.lua <engine-root>

local argv = rawget(_G, "arg") or {}
local engineRoot = assert(argv[1], "Gen1Recomp engine root required")
package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

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

local Fixtures = require("tests.modkit.fixtures")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local data = Fixtures.fresh()

-- The ROM-free fixture has one ordinary trainer. Reuse the same valid party
-- definition under boss IDs so classification, not fixture data, is tested.
data.trainers.OPP_BROCK = data.trainers.OPP_FIX_YOUNGSTER
data.trainers.OPP_RIVAL3 = data.trainers.OPP_FIX_YOUNGSTER

local save = SaveData.newGame()
save.party = {
  Pokemon.new(data, "FIXMON_A", 20),
  Pokemon.new(data, "FIXMON_C", 24),
}
save.inventory.BOULDERBADGE = 1
local game = {
  data = data, save = save,
  mods = { modOptions = {} },
  writeOptions = function() return true end,
}

local values = {
  randomize = "off",
  trainer_difficulty = "normal",
  boss_difficulty = "hard",
  wild_difficulty = "normal",
}
local schema, listeners = nil, {}
local options = {}
function options:define(rows) schema = rows; return rows end
function options:get(key)
  if values[key] ~= nil then return values[key] end
  for _, row in ipairs(schema or {}) do
    if row.key == key then return row.default end
  end
end
local events = {}
function events:on(name, callback)
  listeners[name] = listeners[name] or {}
  listeners[name][#listeners[name] + 1] = callback
end
function events:emit(name, payload)
  for _, callback in ipairs(listeners[name] or {}) do callback(payload) end
end
local mod = {
  id = "Dynamic_Scaling", exports = {}, options = options, events = events,
  hooks = { wrap = function() end },
  log = { info = function() end, warn = function() end },
}

_G.__DYNAMIC_SCALING = nil
BattleState.__dynamic_scaling_wrapped = nil
BattleState.__scottsDynamicScalingPatch = nil
local rawTrainer, rawWild = BattleState.newTrainer, BattleState.newWild
local install = assert(loadfile("vendor/dynamic_scaling/main.lua"))()
install(mod)
local api = assert(mod.exports.dynamicScaling)

check(BattleState.newTrainer ~= rawTrainer,
  "real trainer constructor is wrapped")
check(BattleState.newWild ~= rawWild,
  "real wild constructor is wrapped")
check(api.isBoss(game, "OPP_BROCK"), "real Gym ID selects BOSSES")
check(api.isBoss(game, "OPP_RIVAL3"), "real Champion ID selects BOSSES")
eq(api.isBoss(game, "OPP_FIX_YOUNGSTER"), false,
  "ordinary real trainer selects TRAINERS")

local trainer = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
eq(#trainer.enemyParty, 2, "NORMAL real trainer keeps party size")
eq(trainer.enemyParty[1].level, 24,
  "NORMAL real trainer reaches player average +2")
eq(trainer.enemy.level, trainer.enemyParty[1].level,
  "real trainer cache follows the scaled lead")

local boss = BattleState.newTrainer(game, "OPP_BROCK", 1)
eq(#boss.enemyParty, 6, "HARD real boss expands to six Pokemon")
eq(boss.enemyParty[1].level, 32,
  "HARD real boss reaches player average +10")
eq(boss.enemyAIMods[1], 1, "HARD real boss receives boss AI")
eq(boss.enemyParty[1].statExp.attack, 65535,
  "HARD real boss receives maximum stat experience")

local wild = BattleState.newWild(game, "FIXMON_C", 3)
eq(wild.enemy.mon.species, "FIXMON_C",
  "real wild scaling preserves encounter species")
eq(wild.enemy.mon.level, 24,
  "NORMAL real wild reaches player average +2")
eq(wild.enemy.level, wild.enemy.mon.level,
  "real wild level cache follows the replacement")
eq(wild.enemy.maxHP, wild.enemy.mon.stats.hp,
  "real wild HP cache follows the replacement")

events:emit("mod.options_changed", {
  mod = mod.id, key = "wild_difficulty", value = "off",
})
local vanillaWild = BattleState.newWild(game, "FIXMON_C", 3)
eq(vanillaWild.enemy.mon.level, 3,
  "OFF delegates the real wild level unchanged")

if failures > 0 then error(tostring(failures) .. " engine checks failed") end
print(("Dynamic scaling engine compatibility: %d checks passed"):format(checks))
