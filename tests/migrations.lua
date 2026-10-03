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
      voxel_run_bridge = { running_speed = 2, experience_mode = "party" },
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
  mods = { modOptions = { voxel_run_bridge = {
    running_speed = 2, experience_mode = "party",
  } } },
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
for _, feature in ipairs({
    "experience_modes_v3", "trainer", "oak", "running", "dual",
  }) do
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
eq(options.experience_mode, "all",
  "legacy PARTY ALL value canonicalizes to ALL in the save")
eq(game.mods.modOptions.voxel_run_bridge.experience_mode, "all",
  "legacy PARTY ALL value canonicalizes in the live Loader")
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
      voxel_run_bridge = { dual_screen = false, experience_mode = "lead" },
    } },
    modData = { gen1recomp_ds = { enabled = true } },
  },
  mods = { modOptions = { voxel_run_bridge = {
    dual_screen = false, experience_mode = "lead",
  } } },
  writeOptions = function() writes = writes + 1 end,
}
api.run(game2)
eq(game2.save.options.modOptions.voxel_run_bridge.dual_screen, false,
  "an explicit Tweaks dual-screen choice wins over legacy state")
eq(game2.save.options.modOptions.voxel_run_bridge.experience_mode, "buddy",
  "legacy LEAD ONLY value canonicalizes to BUDDY")
eq(game2.mods.modOptions.voxel_run_bridge.experience_mode, "buddy",
  "legacy LEAD ONLY canonicalization reaches the stock Mod Manager cache")
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

-- A failed device write must not leave the menu/live Loader ahead of disk or
-- announce a change that will disappear on restart.
local savedBucket4 = game4.save.options.modOptions.voxel_run_bridge
local liveBucket4 = newLoader.modOptions.voxel_run_bridge
local eventsBeforeFailure = #emitted4
game4.writeOptions = function() error("simulated Android storage failure") end
local wroteFailed, writeFailure = settings4:set(game4, "dual_screen", true)
eq(wroteFailed, false, "organized-menu write reports a thrown storage failure")
check(tostring(writeFailure):find("simulated Android storage failure", 1, true)
    ~= nil, "organized-menu write returns the storage error")
eq(game4.save.options.modOptions.voxel_run_bridge, savedBucket4,
  "failed write preserves the save bucket identity")
eq(newLoader.modOptions.voxel_run_bridge, liveBucket4,
  "failed write preserves the live bucket identity")
eq(savedBucket4.dual_screen, false,
  "failed write restores the durable option mirror")
eq(liveBucket4.dual_screen, false,
  "failed write restores the live Loader option")
eq(#emitted4, eventsBeforeFailure,
  "failed write emits no live option event")

game4.writeOptions = function() return false, "read-only storage" end
local explicitFailed, explicitError = settings4:set(
  game4, "dual_screen", true)
eq(explicitFailed, false,
  "organized-menu write honors an explicit false persistence result")
check(tostring(explicitError):find("read-only storage", 1, true) ~= nil,
  "explicit failure detail reaches the caller")
eq(savedBucket4.dual_screen, false,
  "explicit failure restores the durable option mirror")
eq(liveBucket4.dual_screen, false,
  "explicit failure restores the live Loader option")
eq(#emitted4, eventsBeforeFailure,
  "explicit persistence failure emits no live option event")

-- Batched legacy imports must have the same transactional persistence
-- behavior as an organized-menu edit. In particular, a failed first attempt
-- must not mark a feature complete and prevent game.ready from retrying it.
for _, failureMode in ipairs({ "throw", "false" }) do
  local listeners5, attempts5, warnings5, events5 = {}, 0, {}, {}
  local completed5 = { trainer = true }
  local imported5 = { "trainer_memory" }
  local own5 = {
    legacy_import_v2 = completed5, legacy_imported_keys = imported5,
    preserved = "existing save data",
  }
  local saved5 = { experience_mode = "party", running_speed = 2 }
  local live5 = { experience_mode = "lead", running_speed = 1.5 }
  local allSaved5 = { voxel_run_bridge = saved5 }
  local allLive5 = { voxel_run_bridge = live5 }
  local oldOak5 = { claimed = true }
  local oldShoes5 = { enabled = false, viewBob = false, speed = 1.25 }
  local modData5 = {
    voxel_run_bridge = own5, oak_spare_starter = oldOak5,
    running_shoes = oldShoes5,
  }
  local options5 = { modOptions = allSaved5 }
  local game5 = {
    save = { options = options5, modData = modData5 },
    mods = {
      modOptions = allLive5,
      events = { emit = function(_, name, payload)
        events5[#events5 + 1] = { name = name, payload = payload }
      end },
    },
    writeOptions = function()
      attempts5 = attempts5 + 1
      if failureMode == "throw" then error("migration storage failure") end
      return false, "migration storage is read-only"
    end,
  }
  local mod5 = {
    id = mod.id, exports = {}, options = mod.options,
    events = { on = function(_, name, callback)
      listeners5[name] = callback
      return function() end
    end },
    log = { warn = function(_, _, detail)
      warnings5[#warnings5 + 1] = detail
    end },
  }
  package.loaded["src.core.Game"] = game5
  local settings5 = Settings.new(mod5, {})
  local api5 = install(mod5, { settings = settings5 })
  local label = "migration " .. failureMode .. " failure: "
  eq(attempts5, 1, label .. "the batch attempts one write")
  eq(api5.imported, false, label .. "API does not report an import")
  eq(#api5.importedKeys, 0, label .. "API exposes no committed keys")
  check(type(api5.lastError) == "string",
    label .. "API retains a useful persistence error")
  eq(#warnings5, 1, label .. "the persistence failure is logged")
  eq(game5.save.options, options5, label .. "options root identity survives")
  eq(options5.modOptions, allSaved5,
    label .. "saved modOptions identity survives")
  eq(allSaved5.voxel_run_bridge, saved5,
    label .. "saved bucket identity survives")
  eq(game5.mods.modOptions, allLive5,
    label .. "live modOptions identity survives")
  eq(allLive5.voxel_run_bridge, live5,
    label .. "live bucket identity survives")
  eq(saved5.experience_mode, "party", label .. "saved EXP import rolls back")
  eq(live5.experience_mode, "lead", label .. "live EXP import rolls back")
  eq(saved5.running_enabled, nil,
    label .. "new saved running preference rolls back")
  eq(live5.running_enabled, nil,
    label .. "new live running preference rolls back")
  eq(saved5.running_speed, 2,
    label .. "existing saved preference survives")
  eq(live5.running_speed, 1.5,
    label .. "failure does not reconcile a divergent Loader preference")
  eq(game5.save.modData, modData5, label .. "modData identity survives")
  eq(modData5.voxel_run_bridge, own5, label .. "own namespace identity survives")
  eq(own5.legacy_import_v2, completed5,
    label .. "migration marker identity survives")
  eq(completed5.trainer, true, label .. "previous completion survives")
  eq(completed5.experience_modes_v3, nil,
    label .. "EXP canonicalization remains pending")
  eq(completed5.oak, nil, label .. "Oak claim import remains pending")
  eq(completed5.running, nil, label .. "running import remains pending")
  eq(own5.legacy_imported_keys, imported5,
    label .. "imported-key list identity survives")
  eq(#imported5, 1, label .. "new imported keys roll back")
  eq(own5.oak_spare_starter_claimed, nil,
    label .. "new claim data rolls back with the options")
  eq(own5.preserved, "existing save data", label .. "unrelated own data survives")
  eq(modData5.oak_spare_starter, oldOak5,
    label .. "legacy Oak namespace is untouched")
  eq(modData5.running_shoes, oldShoes5,
    label .. "legacy running namespace is untouched")
  eq(#events5, 0, label .. "no option-change event announces failed imports")

  game5.writeOptions = function() attempts5 = attempts5 + 1 end
  eq(listeners5["game.ready"]({ game = game5 }), true,
    label .. "game.ready retries when storage recovers")
  eq(attempts5, 2, label .. "the successful retry writes once")
  eq(saved5.experience_mode, "all", label .. "retry canonicalizes saved EXP")
  eq(live5.experience_mode, "all", label .. "retry canonicalizes live EXP")
  eq(saved5.running_enabled, false, label .. "retry imports saved running choice")
  eq(live5.running_enabled, false, label .. "retry imports live running choice")
  eq(completed5.experience_modes_v3, true,
    label .. "retry commits the EXP completion marker")
  eq(completed5.oak, true, label .. "retry commits the Oak completion marker")
  eq(completed5.running, true,
    label .. "retry commits the running completion marker")
  eq(own5.oak_spare_starter_claimed, true,
    label .. "retry preserves the legitimate one-time claim")
  eq(own5.legacy_import_v2, completed5,
    label .. "successful retry also keeps marker identity")
  eq(own5.legacy_imported_keys, imported5,
    label .. "successful retry also keeps list identity")
  eq(api5.lastError, nil, label .. "successful retry clears the failure detail")
  eq(api5.imported, true, label .. "API reports the committed imports")
  eq(api5.run(game5), false, label .. "successful retry stays idempotent")
  eq(attempts5, 2, label .. "later lifecycle calls do not write again")
end

-- First-install failures must also undo tables that Settings/the migration
-- created. Neither a placeholder namespace nor an empty live bucket should
-- make a later boot look as if it already migrated.
local listeners6 = {}
local legacy6 = { gen1recomp_ds = { enabled = true } }
local game6 = {
  save = { modData = legacy6 }, mods = {},
  writeOptions = function() return false end,
}
local mod6 = {
  id = mod.id, exports = {}, options = mod.options, log = mod.log,
  events = { on = function(_, name, callback)
    listeners6[name] = callback
    return function() end
  end },
}
package.loaded["src.core.Game"] = game6
local settings6 = Settings.new(mod6, {})
local api6 = install(mod6, { settings = settings6 })
eq(game6.save.options, nil, "first-install failure removes a newly created options root")
eq(game6.mods.modOptions, nil, "first-install failure removes newly created live modOptions")
eq(game6.save.modData, legacy6, "first-install failure preserves the legacy modData root")
eq(legacy6.voxel_run_bridge, nil, "first-install failure removes a new migration namespace")
check(api6.lastError:find("game.writeOptions returned false", 1, true) ~= nil,
  "false-without-detail failure has a useful fallback message")
game6.writeOptions = function() return true end
eq(listeners6["game.ready"]({ game = game6 }), true,
  "first-install failure retries successfully on game.ready")
eq(game6.save.options.modOptions.voxel_run_bridge.dual_screen, true,
  "first-install retry commits the saved legacy preference")
eq(game6.mods.modOptions.voxel_run_bridge.dual_screen, true,
  "first-install retry commits the live legacy preference")

package.loaded["src.core.Game"] = nil
package.preload["src.core.Game"] = nil
if failures > 0 then error(tostring(failures) .. " migration checks failed") end
print("Scott's Tweaks migrations: " .. checks .. " checks passed")
