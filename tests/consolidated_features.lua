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

-- Trainer paid-forfeit/rematch integration under the consolidated namespace.
local listeners, hookRows = {}, {}
local function emit(name, payload)
  for _, callback in ipairs(listeners[name] or {}) do callback(payload) end
end
local pushed = {}
local Game = {
  save = { money = 500, party = { { hp = 10 } }, flags = {}, inventory = {} },
  data = {
    text = {
      AFTER = "Ready for another battle?",
      _PewterGymBrockPostBattleAdviceText = "Brock is ready.",
    },
    trainerHeader = function() return { after = "AFTER" } end,
  },
  stack = { push = function(_, value) pushed[#pushed + 1] = value end },
}
local vanillaTalks = 0
local Overworld = {}
function Overworld.talkTo(_, npc) vanillaTalks = vanillaTalks + 1; npc.frozen = true end
local TextBox = {}
function TextBox.new(game, text, onDone, opts)
  return { game = game, text = text, onDone = onDone, opts = opts }
end
local builtBattle
local BattleState = {}
function BattleState.newTrainer(game, class, party)
  local partyDef = { { species = "GEODUDE", level = 12 } }
  if hookRows["trainer.party"] then
    partyDef = hookRows["trainer.party"](
      function(_, _, value) return value end, class, party, partyDef)
  end
  builtBattle = {
    game = game, kind = "trainer", oppClass = class,
    partyIndex = party, tryRun = function() return "vanilla" end,
    sayChoice = function() end, say = function() end, builtParty = partyDef,
  }
  return builtBattle
end
package.loaded["src.core.Game"] = nil
package.loaded["src.world.OverworldController"] = nil
package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.OverworldController"] = function() return Overworld end
package.preload["data.scripts.init"] = function()
  return { talkScript = function(_, text)
    return text == "TEXT_PEWTERGYM_BROCK"
  end }
end
package.preload["data.scripts.victories"] = function()
  return {
    ["OPP_BROCK#1"] = {
      badge = "BOULDERBADGE", flag = "EVENT_BEAT_BROCK",
      gotFlag = "EVENT_GOT_TM34", item = "TM_BIDE",
    },
  }
end
package.preload["src.render.TextBox"] = function() return TextBox end
package.preload["src.battle.BattleState"] = function() return BattleState end

local optionValues = {
  trainer_forfeit_enabled = true, trainer_rematches = true,
  trainer_adaptive_dialogue = true, trainer_growth = "gentle",
}
local recordCalls, boostCalls = 0, 0
local mod = {
  id = "voxel_run_bridge", exports = {},
  options = { get = function(_, key) return optionValues[key] end },
  events = { on = function(_, name, callback)
    listeners[name] = listeners[name] or {}
    listeners[name][#listeners[name] + 1] = callback
    return function() end
  end },
  hooks = { wrap = function(_, name, callback)
    hookRows[name] = callback
    return function() end
  end },
  log = { info = function() end, warn = function() end },
}
local context = {
  settings = { get = function(_, key, fallback)
    local value = optionValues[key]
    return value == nil and fallback or value
  end },
  findMod = function() return nil end,
  loadOwn = function(path)
    if path ~= "modules/trainer_dialogue.lua" then return nil end
    return function()
      return {
        context = function() return { text = "Journey line" } end,
        beforeRematch = function() end,
        recordBattle = function() recordCalls = recordCalls + 1 end,
        rematchBoost = function()
          boostCalls = boostCalls + 1
          return { levelBonus = 1 }
        end,
        cleanup = function() end,
      }
    end
  end,
}
local trainerInstall = assert(loadfile("modules/trainer_forfeit.lua"))()
local trainer = trainerInstall(mod, context)
eq(mod.exports.trainerForfeit, trainer,
  "trainer feature uses its namespaced export")
eq(mod.exports.status, nil, "trainer feature does not overwrite bridge status")
eq(trainer.sourceVersion, "0.3.0", "incorporated trainer source is identified")

local npc = {
  id = "ROUTE_3_obj_1", facing = "left", cellX = 5, cellY = 6,
  def = { index = 1, name = "YOUNGSTER", text = "TEXT_YOUNGSTER",
    trainerClass = "OPP_YOUNGSTER", trainerParty = 1 },
  facePlayer = function(self) self.faced = true end,
}
local overworld = setmetatable({
  map = { id = "ROUTE_3", def = { label = "Route3" } },
  player = {}, trainerDefeated = function() return true end,
  pushBattle = function(_, battle) pushed[#pushed + 1] = battle end,
  afterBattle = function() end,
}, { __index = Overworld })
Game.overworld = overworld

local rawRunCalls, choice
local battle = {
  kind = "trainer", oppClass = "OPP_YOUNGSTER", partyIndex = 1,
  game = Game,
  tryRun = function() rawRunCalls = (rawRunCalls or 0) + 1; return "raw" end,
  sayChoice = function(_, _, callback) choice = callback end,
  say = function() end,
}
emit("world.trainer_engaged", {
  npc = npc, trainerClass = "OPP_YOUNGSTER", partyIndex = 1,
})
emit("battle.started", { battle = battle, kind = "trainer" })
battle:tryRun()
check(type(choice) == "function", "ordinary trainer RUN becomes a paid choice")
choice(true)
eq(Game.save.money, 300, "paid forfeit deducts exactly ¥200")
eq(battle.result, "run", "paid forfeit ends with the run result")

optionValues.trainer_forfeit_enabled = false
eq(battle:tryRun(), "raw", "live OFF delegates an already wrapped battle")
eq(rawRunCalls, 1, "live OFF calls the original RUN once")

local battle2RawCalls = 0
local function battle2Raw() battle2RawCalls = battle2RawCalls + 1; return "raw2" end
local battle2 = {
  kind = "trainer", oppClass = "OPP_YOUNGSTER", partyIndex = 1,
  game = Game, tryRun = battle2Raw,
  sayChoice = function() error("paid choice must stay off") end,
  say = function() end,
}
emit("world.trainer_engaged", {
  npc = npc, trainerClass = "OPP_YOUNGSTER", partyIndex = 1,
})
emit("battle.started", { battle = battle2, kind = "trainer" })
eq(battle2.tryRun, battle2Raw,
  "PAID FORFEIT OFF installs no RUN wrapper on a new battle")
emit("battle.ended", { battle = battle2, result = "win" })
eq(recordCalls, 1,
  "REMATCHES ON still records journey history while paid RUN is off")

local beforeFlags = next(Game.save.flags)
Overworld.talkTo(overworld, npc)
local prompt = pushed[#pushed]
check(prompt and prompt.opts and type(prompt.opts.choice) == "function",
  "defeated ordinary trainer offers a rematch")
prompt.opts.choice(true)
eq(builtBattle and builtBattle.trainerForfeitRematch, true,
  "rematch battle is explicitly reward-safe tagged")
eq(builtBattle and builtBattle.checkpointOrigin.trainerForfeitRematch, true,
  "rematch checkpoint carries the safe continuation marker")
eq(next(Game.save.flags), beforeFlags, "starting a rematch changes no story flag")
check(boostCalls > 0,
  "gentle rematch growth remains active while paid RUN is off")
local rematchRaw = builtBattle.tryRun
emit("battle.started", { battle = builtBattle, kind = "trainer" })
eq(builtBattle.tryRun, rematchRaw,
  "paid RUN remains absent inside a rematch when its toggle is off")

Game.save.flags.EVENT_BEAT_BROCK = true
Game.save.flags.EVENT_GOT_TM34 = true
Game.save.inventory.BOULDERBADGE = 1
local gym = setmetatable({
  map = { id = "PEWTER_GYM", def = { label = "PewterGym" } },
  player = {}, trainerDefeated = function() return true end,
  pushBattle = overworld.pushBattle, afterBattle = function() end,
}, { __index = Overworld })
local brock = {
  id = "PEWTER_GYM_obj_1",
  def = { index = 1, name = "PEWTERGYM_BROCK",
    text = "TEXT_PEWTERGYM_BROCK", trainerClass = "OPP_BROCK",
    trainerParty = 1 },
  facePlayer = function(self) self.faced = true end,
}
Game.overworld = gym
Overworld.talkTo(gym, brock)
local gymPrompt = pushed[#pushed]
check(gymPrompt and gymPrompt.opts and type(gymPrompt.opts.choice) == "function",
  "Gym Leader rematch remains available while paid RUN is off")

local stableTalkWrapper = Overworld.talkTo
local reloadedTrainer = trainerInstall(mod, context)
eq(Overworld.talkTo, stableTalkWrapper,
  "trainer hot reload retains one stable raw talk dispatcher")
eq(reloadedTrainer.hotReload, "dispatcher_refreshed",
  "trainer hot reload reports a refreshed dispatcher")
trainer.cleanup()
eq(Overworld.talkTo, stableTalkWrapper,
  "old trainer cleanup cannot tear down the refreshed dispatcher")
optionValues.trainer_rematches = false
local vanillaBeforeReloadCheck = vanillaTalks
Overworld.talkTo(overworld, npc)
eq(vanillaTalks, vanillaBeforeReloadCheck + 1,
  "refreshed dispatcher reads the latest live OFF setting")
optionValues.trainer_rematches = true
local pushedBeforeReloadCheck = #pushed
Overworld.talkTo(overworld, npc)
eq(#pushed, pushedBeforeReloadCheck + 1,
  "refreshed dispatcher serves rematches after live ON")
Game.mods = { exports = {} }
local vanillaBeforeRemovedCheck = vanillaTalks
Overworld.talkTo(overworld, npc)
eq(vanillaTalks, vanillaBeforeRemovedCheck + 1,
  "retained dispatcher becomes inert when Tweaks is absent from the live Loader")
Game.mods = nil
local delegatedMod = { id = mod.id, exports = {}, log = mod.log }
local delegated = trainerInstall(delegatedMod, {
  findMod = function(id) return id == "trainer_forfeit" and {} or nil end,
})
eq(delegated.delegated, true, "standalone trainer mod receives ownership")
eq(delegated.provider, "trainer_forfeit",
  "trainer delegation identifies the provider")
check(Overworld.talkTo ~= stableTalkWrapper,
  "enabling the standalone provider suspends Tweaks' raw dispatcher")
local suspendedPatch = rawget(Overworld, "_scottsTweaksTrainerRematchV2")
eq(suspendedPatch and suspendedPatch.active, false,
  "delegation keeps one inactive dispatcher record for safe transition")

local resumedTrainer = trainerInstall(mod, context)
eq(Overworld.talkTo, stableTalkWrapper,
  "removing the standalone provider resumes the same dispatcher")
eq(resumedTrainer.hotReload, "dispatcher_refreshed",
  "provider removal refreshes the retained dispatcher")
reloadedTrainer.cleanup()
eq(Overworld.talkTo, stableTalkWrapper,
  "pre-delegation cleanup cannot tear down the resumed generation")
resumedTrainer.cleanup()
check(Overworld.talkTo ~= stableTalkWrapper,
  "current trainer cleanup restores the raw Overworld method")

-- Oak's spare starter keeps one private claim key and yields only its feature
-- when Random Starters or the old standalone mod owns Oak's Lab.
local contribution, baseCalls = nil, 0
package.loaded["src.script.MapScripts"] = nil
package.loaded["src.script.Commands"] = nil
package.loaded["src.pokemon.Party"] = nil
package.loaded["src.core.GameVersion"] = nil
package.preload["src.script.MapScripts"] = function()
  return {
    baseTalk = function() return function(_, _, _, done)
      baseCalls = baseCalls + 1; done()
    end end,
    namedScript = function() return {} end,
    namedSource = function() return {} end,
  }
end
package.preload["src.script.Commands"] = function()
  return { hide_object = function() end }
end
package.preload["src.pokemon.Party"] = function() return { MAX = 6 } end
package.preload["src.core.GameVersion"] = function()
  return { isYellow = function() return false end }
end

local oakEnabled = true
local oakMod = {
  id = mod.id, exports = {},
  content = { map_scripts = { register = function(_, _, value)
    contribution = value
  end } },
}
local oakContext = {
  findMod = function() return nil end,
  settings = { get = function(_, key, fallback)
    if key == "oak_spare_starter" then return oakEnabled end
    return fallback
  end },
}
local oakInstall = assert(loadfile("modules/oak_spare_starter.lua"))()
local oak = oakInstall(oakMod, oakContext)
eq(oakMod.exports.oakSpareStarter, oak,
  "Oak feature uses its namespaced export")
eq(oak.sourceVersion, "0.1.1", "incorporated Oak source is identified")
check(type(contribution) == "table", "Oak's Lab contribution registers")
local claim = contribution.scripts.oak_spare_starter_claim_charmander
local claimField
for _, row in ipairs(claim) do
  if row[1] == "set_field" then claimField = row[2] end
end
eq(claimField, "mod:oak_spare_starter_claimed",
  "Oak claim state is namespaced inside Scott's Tweaks")

oakEnabled = false
local done = 0
contribution.talk.TEXT_OAKSLAB_CHARMANDER_POKE_BALL({
  save = {
    flags = { EVENT_GOT_STARTER = true,
      EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true, EVENT_CHOSE_SQUIRTLE = true },
    party = {}, objectToggles = {}, modData = {},
  },
}, { runner = { run = function() end } }, {}, function() done = done + 1 end)
eq(baseCalls, 1, "Oak OFF delegates to the exact base talk handler")
eq(done, 1, "Oak OFF completes base interaction normally")

local randomRegistered = false
local randomMod = {
  id = mod.id, exports = {},
  content = { map_scripts = { register = function() randomRegistered = true end } },
}
local randomResult = oakInstall(randomMod, {
  findMod = function(id) return id == "random_starters" and {} or nil end,
})
eq(randomResult.provider, "random_starters",
  "Random Starters receives only Oak's Lab ownership")
eq(randomRegistered, false, "delegated Oak feature registers no competing script")

local standaloneRegistered = false
local standaloneOak = oakInstall({
  id = mod.id, exports = {},
  content = { map_scripts = { register = function()
    standaloneRegistered = true
  end } },
}, {
  findMod = function(id) return id == "oak_spare_starter" and {} or nil end,
})
eq(standaloneOak.provider, "oak_spare_starter",
  "standalone Oak mod receives Oak's Lab ownership")
eq(standaloneRegistered, false,
  "standalone Oak delegation installs no competing script")

package.loaded["src.mods.Runtime"] = nil
package.preload["src.mods.Runtime"] = function() return {} end
local runningHooks = 0
local runningMod = {
  id = mod.id, exports = {},
  hooks = { wrap = function() runningHooks = runningHooks + 1 end },
}
local runningInstall = assert(loadfile("modules/running.lua"))()
local runningDelegated = runningInstall(runningMod, {
  findMod = function(id) return id == "running_shoes" and {} or nil end,
})
eq(runningDelegated.provider, "running_shoes",
  "standalone Running Shoes receives running ownership")
eq(runningHooks, 0,
  "running delegation installs neither producer nor camera wrapper")

for _, name in ipairs({
  "src.core.Game", "src.world.OverworldController", "data.scripts.init",
  "data.scripts.victories", "src.render.TextBox", "src.battle.BattleState",
  "src.script.MapScripts", "src.script.Commands", "src.pokemon.Party",
  "src.core.GameVersion",
  "src.mods.Runtime",
}) do
  package.loaded[name] = nil
  package.preload[name] = nil
end

if failures > 0 then error(tostring(failures) .. " feature checks failed") end
print("Scott's Tweaks consolidated features: " .. checks .. " checks passed")
