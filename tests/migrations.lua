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

local listeners = {}
local mod = {
  id = "voxel_run_bridge", exports = {},
  options = { get = function() return nil end },
  events = { on = function(_, name, callback)
    listeners[name] = callback
    return function() end
  end },
  log = { warn = function() end },
}
local Settings = assert(loadfile("modules/settings.lua"))()
local settings = Settings.new(mod, {})

local writes = 0
local legacyMemory = {
  format = 1, sequence = 4,
  trainers = { route3 = { wins = 2 } }, recentWins = {},
}
local trainerBucket = { memory = legacyMemory }
local oakBucket = { claimed = true }
local shoesBucket = {
  enabled = false, speed = 1.25, viewBob = false, bobIntensity = 0.75,
}
local dualBucket = { enabled = true, sideBySide = true }
local game = {
  save = {
    options = { modOptions = {
      voxel_run_bridge = { running_speed = 2 },
      trainer_forfeit = {
        rematches = false, adaptive_dialogue = false,
        trainer_growth = "off",
      },
      scott_mod = { run_enabled = true, run_speed = 1.5 },
    } },
    modData = {
      trainer_forfeit = trainerBucket,
      oak_spare_starter = oakBucket,
      running_shoes = shoesBucket,
      gen1recomp_ds = dualBucket,
    },
  },
  mods = { modOptions = { voxel_run_bridge = { running_speed = 2 } } },
  writeOptions = function() writes = writes + 1 end,
}
package.loaded["src.core.Game"] = nil
package.preload["src.core.Game"] = function() return game end

local install = assert(loadfile("modules/migrations.lua"))()
local api = install(mod, { settings = settings })
local own = game.save.modData.voxel_run_bridge
local options = game.save.options.modOptions.voxel_run_bridge

check(type(own.legacy_import_v2) == "table",
  "migration records a per-save feature marker")
for _, feature in ipairs({ "trainer", "oak", "running", "dual" }) do
  eq(own.legacy_import_v2[feature], true,
    feature .. " migration records completion")
end
check(own.trainer_memory ~= legacyMemory,
  "trainer memory is copied rather than aliased")
eq(own.trainer_memory.trainers.route3.wins, 2,
  "trainer journey memory is preserved")
eq(options.trainer_rematches, false, "rematch preference imports")
eq(options.trainer_adaptive_dialogue, false,
  "dialogue preference imports")
eq(options.trainer_growth, "off", "growth preference imports")
eq(own.oak_spare_starter_claimed, true,
  "Oak's one-time claim imports")
eq(options.running_enabled, false, "0.x running enabled value imports")
eq(options.running_speed, 2,
  "an explicit Tweaks run speed is never overwritten")
eq(options.running_view_bob, false, "0.x view-bob value imports")
eq(options.running_bob_intensity, 0.75,
  "0.x bob intensity imports")
eq(options.dual_screen, true, "legacy dual enabled value imports")
eq(game.mods.modOptions.voxel_run_bridge.dual_screen, true,
  "imports mirror into the live Loader cache")
eq(writes, 1, "all imported options persist in one write")
eq(game.save.modData.trainer_forfeit, trainerBucket,
  "trainer legacy namespace remains untouched")
eq(game.save.modData.oak_spare_starter, oakBucket,
  "Oak legacy namespace remains untouched")
eq(game.save.modData.running_shoes, shoesBucket,
  "running legacy namespace remains untouched")
eq(game.save.modData.gen1recomp_ds, dualBucket,
  "dual legacy namespace remains untouched")
eq(api.run(game), false, "the migration is idempotent")
eq(writes, 1, "a repeated migration performs no write")

local game2 = {
  save = {
    options = { modOptions = {
      voxel_run_bridge = { dual_screen = false },
    } },
    modData = { gen1recomp_ds = { enabled = true } },
  },
  mods = { modOptions = { voxel_run_bridge = { dual_screen = false } } },
  writeOptions = function() writes = writes + 1 end,
}
api.run(game2)
eq(game2.save.options.modOptions.voxel_run_bridge.dual_screen, false,
  "an explicit Tweaks dual-screen choice wins over legacy state")
eq(game2.save.modData.gen1recomp_ds.enabled, true,
  "explicit-choice migration still preserves the old dual bucket")

-- Exact transition: providers remain active for one boot and write newer
-- legacy state after Tweaks loads. Their feature markers must stay pending,
-- then import the latest state only after those providers are removed.
local active = {
  trainer_forfeit = true, oak_spare_starter = true,
  running_shoes = true, gen1recomp_ds = true,
}
local lateMemory = { format = 1, sequence = 1, trainers = {
  late = { wins = 1 },
}, recentWins = {} }
local lateTrainer = { memory = lateMemory }
local lateOak = { claimed = false }
local lateShoes = {
  enabled = true, speed = 1.25, viewBob = true, bobIntensity = 0.5,
}
local lateDual = { enabled = false }
local game3 = {
  save = {
    options = { modOptions = {
      trainer_forfeit = { rematches = true },
    } },
    modData = {
      trainer_forfeit = lateTrainer, oak_spare_starter = lateOak,
      running_shoes = lateShoes, gen1recomp_ds = lateDual,
    },
  },
  mods = { modOptions = {} }, writeOptions = function() end,
}
local mod3 = {
  id = mod.id, exports = {}, options = mod.options, events = mod.events,
  log = mod.log,
}
local settings3 = Settings.new(mod3, {})
package.loaded["src.core.Game"] = game3
local api3 = install(mod3, {
  settings = settings3,
  findMod = function(id) return active[id] and { id = id } or nil end,
})
local own3 = game3.save.modData.voxel_run_bridge
eq(own3.legacy_import_v2.trainer, nil,
  "active trainer provider defers trainer completion")
eq(own3.legacy_import_v2.oak, nil,
  "active Oak provider defers Oak completion")
eq(own3.legacy_import_v2.running, nil,
  "active running provider defers running completion")
eq(own3.legacy_import_v2.dual, nil,
  "active dual provider defers dual completion")

lateMemory.trainers.late.wins = 9
lateTrainer.memory.sequence = 8
lateOak.claimed = true
lateShoes.enabled = false
lateShoes.bobIntensity = 0.25
lateDual.enabled = true
game3.save.options.modOptions.trainer_forfeit.rematches = false
for id in pairs(active) do active[id] = false end
eq(api3.run(game3), true,
  "removing legacy providers completes deferred imports")
eq(own3.trainer_memory.trainers.late.wins, 9,
  "deferred trainer import uses the latest written history")
eq(game3.save.options.modOptions.voxel_run_bridge.trainer_rematches,
  false, "deferred trainer import uses the latest setting")
eq(own3.oak_spare_starter_claimed, true,
  "deferred Oak import prevents a duplicate starter")
eq(game3.save.options.modOptions.voxel_run_bridge.running_enabled, false,
  "deferred running import uses the latest enabled value")
eq(game3.save.options.modOptions.voxel_run_bridge.running_bob_intensity,
  0.25, "deferred running import uses the latest bob value")
eq(game3.save.options.modOptions.voxel_run_bridge.dual_screen, true,
  "deferred dual import uses the latest enabled value")
eq(game3.save.modData.trainer_forfeit, lateTrainer,
  "deferred import preserves the trainer namespace identity")
eq(game3.save.modData.oak_spare_starter, lateOak,
  "deferred import preserves the Oak namespace identity")
eq(game3.save.modData.running_shoes, lateShoes,
  "deferred import preserves the running namespace identity")
eq(game3.save.modData.gen1recomp_ds, lateDual,
  "deferred import preserves the dual namespace identity")

-- F5 builds the fresh Loader before assigning it to Game.mods. The immediate
-- migration may therefore update the save and retiring Loader first; the
-- subsequent game.ready must reconcile that save into the live generation.
local listeners4, emitted4, writes4 = {}, {}, 0
local mod4 = {
  id = mod.id, exports = {}, options = mod.options,
  events = { on = function(_, name, callback)
    listeners4[name] = callback
    return function() end
  end },
  log = mod.log,
}
local oldLoader = { modOptions = {} }
local game4 = {
  save = {
    options = { modOptions = {} },
    modData = { gen1recomp_ds = { enabled = true } },
  },
  mods = oldLoader,
  writeOptions = function() writes4 = writes4 + 1 end,
}
package.loaded["src.core.Game"] = game4
local settings4 = Settings.new(mod4, {})
install(mod4, { settings = settings4, findMod = function() return nil end })
eq(game4.save.options.modOptions.voxel_run_bridge.dual_screen, true,
  "F5 entry migration first records the imported value in the save")
eq(oldLoader.modOptions.voxel_run_bridge.dual_screen, true,
  "F5 entry may safely mirror into the retiring Loader")
local newLoader = {
  modOptions = {},
  events = { emit = function(_, name, payload)
    emitted4[#emitted4 + 1] = { name = name, payload = payload }
  end },
}
game4.mods = newLoader
listeners4["game.ready"]({ game = game4 })
eq(newLoader.modOptions.voxel_run_bridge.dual_screen, true,
  "game.ready reconciles imported options into the fresh Loader")
eq(emitted4[#emitted4].name, "mod.options_changed",
  "fresh-Loader reconciliation emits the standard option event")
eq(emitted4[#emitted4].payload.key, "dual_screen",
  "fresh-Loader event identifies the imported option")
local writesBeforeMenu = writes4
eq(settings4:set(game4, "dual_screen", false), true,
  "organized-menu setting writes through the shared helper")
eq(newLoader.modOptions.voxel_run_bridge.dual_screen, false,
  "organized-menu edit changes the fresh live Loader")
eq(emitted4[#emitted4].payload.value, false,
  "organized-menu edit emits its new live value")
eq(writes4, writesBeforeMenu + 1,
  "organized-menu edit persists exactly once")

package.loaded["src.core.Game"] = nil
package.preload["src.core.Game"] = nil
if failures > 0 then error(tostring(failures) .. " migration checks failed") end
print("Scott's Tweaks migrations: " .. checks .. " checks passed")
