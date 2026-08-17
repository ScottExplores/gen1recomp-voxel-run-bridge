-- Trainer Forfeit & Rematches
-- Incorporated from Trainer Forfeit 0.3.0 (MIT) and adapted to the Scott's
-- Tweaks namespace. See THIRD_PARTY_NOTICES.md.
--
-- RUN may be bought for ¥200 in ordinary trainer encounters.  After an
-- ordinary map trainer or Gym Leader has been safely completed, talking to
-- that NPC offers a rematch without clearing story flags or replaying
-- one-time rewards.

local COST = 200
local PATCH_KEY = "_scottsTweaksTrainerPaidRun"
local WORLD_PATCH = "_scottsTweaksTrainerRematchV2"
local DEFAULT_OPTIONS = {
  trainer_forfeit_enabled = true,
  trainer_rematches = true,
  trainer_adaptive_dialogue = true,
  trainer_growth = "gentle",
}

local OPPOSITE = {
  up = "down", down = "up", left = "right", right = "left",
}

local SPECIAL_CLASSES = {
  OPP_RIVAL1 = true, OPP_RIVAL2 = true, OPP_RIVAL3 = true,
  OPP_PROF_OAK = true, OPP_BROCK = true, OPP_MISTY = true,
  OPP_LT_SURGE = true, OPP_ERIKA = true, OPP_KOGA = true,
  OPP_SABRINA = true, OPP_BLAINE = true, OPP_GIOVANNI = true,
  OPP_LORELEI = true, OPP_BRUNO = true, OPP_AGATHA = true,
  OPP_LANCE = true,
}

-- Gym Leaders use map-owned talk scripts rather than the generic trainer
-- after-text path.  Keep this whitelist exact so rivals, Rocket bosses, the
-- Dojo Master, and Elite Four battles can never enter the rematch path.
-- Giovanni's required farewell hides him permanently, so his completed
-- rematch is offered by the Viridian Gym guide without respawning him.
local GYM_REMATCHES = {
  PEWTER_GYM_obj_1 = {
    map = "PEWTER_GYM", index = 1, name = "PEWTERGYM_BROCK",
    text = "TEXT_PEWTERGYM_BROCK", trainerClass = "OPP_BROCK",
    partyIndex = 1, after = "_PewterGymBrockPostBattleAdviceText",
  },
  CERULEAN_GYM_obj_1 = {
    map = "CERULEAN_GYM", index = 1, name = "CERULEANGYM_MISTY",
    text = "TEXT_CERULEANGYM_MISTY", trainerClass = "OPP_MISTY",
    partyIndex = 1, after = "_CeruleanGymMistyTM11ExplanationText",
  },
  VERMILION_GYM_obj_1 = {
    map = "VERMILION_GYM", index = 1, name = "VERMILIONGYM_LT_SURGE",
    text = "TEXT_VERMILIONGYM_LT_SURGE", trainerClass = "OPP_LT_SURGE",
    partyIndex = 1, after = "_VermilionGymLTSurgePostBattleAdviceText",
  },
  CELADON_GYM_obj_1 = {
    map = "CELADON_GYM", index = 1, name = "CELADONGYM_ERIKA",
    text = "TEXT_CELADONGYM_ERIKA", trainerClass = "OPP_ERIKA",
    partyIndex = 1, after = "_CeladonGymErikaPostBattleAdviceText",
  },
  FUCHSIA_GYM_obj_1 = {
    map = "FUCHSIA_GYM", index = 1, name = "FUCHSIAGYM_KOGA",
    text = "TEXT_FUCHSIAGYM_KOGA", trainerClass = "OPP_KOGA",
    partyIndex = 1, after = "_FuchsiaGymKogaPostBattleAdviceText",
  },
  SAFFRON_GYM_obj_1 = {
    map = "SAFFRON_GYM", index = 1, name = "SAFFRONGYM_SABRINA",
    text = "TEXT_SAFFRONGYM_SABRINA", trainerClass = "OPP_SABRINA",
    partyIndex = 1, after = "_SaffronGymSabrinaPostBattleAdviceText",
  },
  CINNABAR_GYM_obj_1 = {
    map = "CINNABAR_GYM", index = 1, name = "CINNABARGYM_BLAINE",
    text = "TEXT_CINNABARGYM_BLAINE", trainerClass = "OPP_BLAINE",
    partyIndex = 1, after = "_CinnabarGymBlainePostBattleAdviceText",
  },
  VIRIDIAN_GYM_obj_10 = {
    map = "VIRIDIAN_GYM", index = 10, name = "VIRIDIANGYM_GYM_GUIDE",
    text = "TEXT_VIRIDIANGYM_GYM_GUIDE", trainerClass = "OPP_GIOVANNI",
    partyIndex = 3, after = "_ViridianGymGuidePostBattleText",
    giovanniGuide = true, identityId = "VIRIDIAN_GYM_obj_1",
    identityName = "VIRIDIANGYM_GIOVANNI",
    alternateFlag = "EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI",
    x = 2, y = 1, question = "Challenge GIOVANNI\nagain?",
  },
}

local function traceback(err)
  if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
  return tostring(err)
end

local function sameEngagement(pending, battle)
  if type(pending) ~= "table" or type(battle) ~= "table" then return false end
  if pending.trainerClass ~= battle.oppClass then return false end
  return (pending.partyIndex or 1) == (battle.partyIndex or 1)
end

local function hasHealthyParty(game)
  local party = game and game.save and game.save.party or {}
  for _, mon in ipairs(party) do
    if (tonumber(mon.hp) or 0) > 0 then return true end
  end
  return false
end

local function cloneData(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[cloneData(key, seen)] = cloneData(item, seen)
  end
  return setmetatable(copy, getmetatable(value))
end

local function boundedLevel(value)
  value = math.floor(tonumber(value) or 0)
  if value < 2 then return 2 end
  if value > 100 then return 100 end
  return value
end

-- Raw engine tables outlive API-2 Loader generations. If the standalone
-- provider becomes active on a hot reload, retire this generation's
-- dispatcher before yielding ownership. Keep the same owned record so a
-- later provider removal can reactivate it without stacking another wrapper.
local function suspendWorldPatch(mod)
  local ok, OverworldState = pcall(require,
    "src.world.OverworldController")
  if not ok or type(OverworldState) ~= "table" then return end
  local patch = rawget(OverworldState, WORLD_PATCH)
  if type(patch) ~= "table" or patch.owner ~= mod.id then return end
  patch.active = false
  patch.talkHandler = nil
  patch.restoreHandler = nil
  if type(patch.wrapper) == "function"
      and OverworldState.talkTo == patch.wrapper
      and type(patch.original) == "function" then
    OverworldState.talkTo = patch.original
  end
  if type(patch.restoreWrapper) == "function"
      and OverworldState.restoreBattleContinuation == patch.restoreWrapper
      and type(patch.restoreOriginal) == "function" then
    OverworldState.restoreBattleContinuation = patch.restoreOriginal
  end
end

return function(mod, context)
  local standalone = context and context.findMod
    and context.findMod("trainer_forfeit") or nil
  if standalone then
    suspendWorldPatch(mod)
    local delegated = {
      installed = false, delegated = true, provider = "trainer_forfeit",
      reason = "standalone_mod_active", version = "0.6.0",
    }
    mod.exports.trainerForfeit = delegated
    if mod.log and mod.log.info then
      mod.log:info("Trainer Forfeit standalone mod is active; Tweaks delegates")
    end
    return delegated
  end

  local function option(key)
    local fallback = DEFAULT_OPTIONS[key]
    if context and context.settings then
      return context.settings:get(key, fallback)
    end
    if not (mod.options and type(mod.options.get) == "function") then
      return fallback
    end
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  local feature = {
    installed = true, version = "0.6.0", sourceVersion = "0.3.0", cost = COST,
    rematches = true, gymLeaders = true, dialogue = false,
    optionDefaults = {
      trainer_forfeit_enabled = DEFAULT_OPTIONS.trainer_forfeit_enabled,
      trainer_rematches = DEFAULT_OPTIONS.trainer_rematches,
      trainer_adaptive_dialogue = DEFAULT_OPTIONS.trainer_adaptive_dialogue,
      trainer_growth = DEFAULT_OPTIONS.trainer_growth,
    },
  }
  mod.exports.trainerForfeit = feature

  local dialogue, dialogueErr
  local dialogueInstaller = context and context.loadOwn
    and context.loadOwn("modules/trainer_dialogue.lua") or nil
  if type(dialogueInstaller) == "function" then
    local ok, result = xpcall(function()
      return dialogueInstaller(mod, context)
    end, traceback)
    if ok then dialogue = result else dialogueErr = result end
  else
    dialogueErr = "trainer dialogue module is missing"
  end
  if type(dialogue) == "table" then
    feature.dialogue = true
  elseif dialogueErr and mod.log and mod.log.warn then
    mod.log:warn("journey dialogue disabled: %s", tostring(dialogueErr))
  end

  local pending
  local active = setmetatable({}, { __mode = "k" })
  local observedBattles = setmetatable({}, { __mode = "k" })
  local rematchBattles = setmetatable({}, { __mode = "k" })
  local constructingRematch
  local unsubscribe = {}
  local worldPatch
  local worldLease = {}

  local okGame, Game = pcall(require, "src.core.Game")
  local okWorld, OverworldState = pcall(require, "src.world.OverworldController")
  local okScripts, mapScripts = pcall(require, "data.scripts.init")
  local okVictories, victories = pcall(require, "data.scripts.victories")
  victories = okVictories and victories or {}

  local function currentGeneration(patch)
    local loader = okGame and Game and Game.mods or nil
    local exports = type(loader) == "table" and loader.exports or nil
    if type(exports) ~= "table" then return true end
    return exports[patch.owner] == patch.exports
  end

  local function headerFor(ow, npc)
    local game = okGame and Game or nil
    local data = game and game.data
    local label = ow and ow.map and ow.map.def and ow.map.def.label
    local index = npc and npc.def and npc.def.index
    if not (data and type(data.trainerHeader) == "function" and label and index) then
      return nil
    end
    return data:trainerHeader(label, index)
  end

  -- Ordinary means the engine's generic object-event trainer path.  A map
  -- talk script owns its NPC's story choreography and is never intercepted.
  -- Victory-table classes own badges, gifts, doors or story flags and are
  -- excluded even if an object also has an extracted trainer header.
  local function ordinaryTrainer(ow, npc)
    local d = npc and npc.def
    if type(d) ~= "table" or type(d.trainerClass) ~= "string" then return false end
    if SPECIAL_CLASSES[d.trainerClass] then return false end
    if victories[d.trainerClass .. "#" .. tostring(d.trainerParty or 1)] then
      return false
    end
    if not headerFor(ow, npc) then return false end
    if okScripts and mapScripts and type(mapScripts.talkScript) == "function"
        and ow and ow.map and mapScripts.talkScript(ow.map.id, d.text) then
      return false
    end
    return true
  end

  local function positiveAmount(value)
    local numeric = tonumber(value)
    if numeric ~= nil then return numeric > 0 end
    return value == true
  end

  local function memoryNpc(npc, target)
    if not target or not target.identityId then return npc end
    local d = npc and npc.def or {}
    return {
      id = target.identityId, mapId = target.map,
      cellX = target.x or (npc and npc.cellX),
      cellY = target.y or (npc and npc.cellY),
      def = {
        x = target.x or d.x, y = target.y or d.y,
        name = target.identityName or target.name,
        trainerClass = target.trainerClass,
        trainerParty = target.partyIndex,
      },
    }
  end

  -- A Gym Leader is ready only after every one-time reward step is settled.
  -- EVENT_GOT_TM* remains false when the bag was full; in that state the
  -- vanilla talk script must run so the leader can retry the TM handoff.
  local function completedGymLeader(ow, npc)
    local d = npc and npc.def
    local target = npc and GYM_REMATCHES[npc.id] or nil
    local game = okGame and Game or nil
    local save = game and game.save
    if not (target and type(d) == "table" and ow and ow.map
        and ow.map.id == target.map and d.index == target.index
        and d.name == target.name
        and d.text == target.text and type(save) == "table") then
      return nil
    end

    if target.giovanniGuide then
      if d.trainerClass ~= nil then return nil end
      local mapToggles = save.objectToggles
        and save.objectToggles.VIRIDIAN_GYM or nil
      if not mapToggles or mapToggles.VIRIDIANGYM_GIOVANNI ~= false then
        return nil
      end
    elseif d.trainerClass ~= target.trainerClass
        or (d.trainerParty or 1) ~= target.partyIndex then
      return nil
    end

    local reward = victories[target.trainerClass .. "#"
      .. tostring(target.partyIndex)]
    local flags = save.flags or {}
    local inventory = save.inventory or {}
    local leaderBeaten = type(reward) == "table" and reward.flag
      and flags[reward.flag] == true
    if not leaderBeaten and target.alternateFlag then
      leaderBeaten = flags[target.alternateFlag] == true
    end
    if type(reward) ~= "table" or reward.badge == nil
        or reward.flag == nil or reward.gotFlag == nil
        or not leaderBeaten
        or flags[reward.gotFlag] ~= true
        or not positiveAmount(inventory[reward.badge]) then
      return nil
    end
    if not (okScripts and mapScripts
        and type(mapScripts.talkScript) == "function"
        and mapScripts.talkScript(ow.map.id, d.text)) then
      return nil
    end
    return {
      kind = "gym_leader", map = target.map,
      trainerClass = target.trainerClass,
      partyIndex = target.partyIndex, after = target.after,
      identityId = target.identityId, name = target.name,
      identityName = target.identityName,
      x = target.x, y = target.y, question = target.question,
    }
  end

  local function rematchTarget(ow, npc)
    if ordinaryTrainer(ow, npc) and ow:trainerDefeated(npc) then
      local d = npc.def
      return {
        kind = "ordinary", map = ow.map and ow.map.id,
        trainerClass = d.trainerClass,
        partyIndex = d.trainerParty or 1,
      }
    end
    return completedGymLeader(ow, npc)
  end

  local function overworldFor(npc)
    local ow = okGame and Game.overworld or nil
    if ow and ow.map and npc then return ow end
    return nil
  end

  local function detach(battle)
    if type(battle) ~= "table" then return end
    local record = rawget(battle, PATCH_KEY)
    if type(record) ~= "table" or record.owner ~= mod.id then return end
    if rawget(battle, "tryRun") == record.wrapper then
      rawset(battle, "tryRun", record.rawOriginal)
    end
    rawset(battle, PATCH_KEY, nil)
    active[battle] = nil
  end

  local function recordBattle(game, npc, class, party, result, extra)
    if option("trainer_rematches") ~= true then return end
    if dialogue and type(dialogue.recordBattle) == "function" then
      local ok, err = pcall(dialogue.recordBattle, dialogue, game, npc, class,
                            party or 1, result, extra or {})
      if not ok and mod.log and mod.log.warn then
        mod.log:warn("journey record failed: %s", tostring(err))
      end
    end
  end

  local function attach(battle, engagement)
    local owned = rawget(battle, PATCH_KEY)
    if type(owned) == "table" then return owned.owner == mod.id end
    local original = battle.tryRun
    if type(original) ~= "function" or type(battle.sayChoice) ~= "function"
       or type(battle.say) ~= "function" then return false end

    local record = {
      owner = mod.id, rawOriginal = rawget(battle, "tryRun"),
      original = original, npc = engagement.npc,
      turnAway = engagement.turnAway ~= false,
    }
    local function tryRun(self)
      if option("trainer_forfeit_enabled") ~= true then
        return record.original(self)
      end
      self.phase = "messages"
      self.afterQueue = "menu"
      self:sayChoice("Forfeit battle\nfor ¥200?", function(yes)
        if not yes then return end
        local save = self.game and self.game.save
        local money = save and tonumber(save.money) or 0
        if type(save) ~= "table" or money < COST then
          self:say("Not enough money!\nNeed ¥200.")
          return
        end
        save.money = money - COST
        self.paidTrainerForfeit = true
        local npc = record.npc
        if record.turnAway and type(npc) == "table" and OPPOSITE[npc.facing] then
          npc.facing = OPPOSITE[npc.facing]
        end
        self:say("Paid ¥200.\nBattle forfeited!")
        self.result = "run"
        self.afterQueue = "finish"
      end)
    end
    record.wrapper = tryRun
    rawset(battle, PATCH_KEY, record)
    rawset(battle, "tryRun", tryRun)
    active[battle] = true
    return true
  end

  local function startRematch(ow, npc, target)
    local game = okGame and Game or nil
    if not (game and npc and target) then
      if npc then npc.frozen = false end
      return
    end
    local trainerClass = target.trainerClass
    local partyIndex = target.partyIndex or 1
    local rememberedNpc = memoryNpc(npc, target)
    if not hasHealthyParty(game) then
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game, "You need a healthy\nPOKEMON first!",
        function() npc.frozen = false end))
      return
    end

    if dialogue and type(dialogue.beforeRematch) == "function" then
      pcall(dialogue.beforeRematch, dialogue, game, rememberedNpc,
            trainerClass, partyIndex)
    end

    local BattleState = require("src.battle.BattleState")
    local engagement = {
      npc = npc, memoryNpc = rememberedNpc,
      trainerClass = trainerClass, partyIndex = partyIndex,
      turnAway = target.kind == "ordinary",
    }
    constructingRematch = engagement
    local ok, battle = xpcall(function()
      return BattleState.newTrainer(game, trainerClass, partyIndex)
    end, traceback)
    constructingRematch = nil
    if not ok then
      npc.frozen = false
      if mod.log and mod.log.warn then mod.log:warn("rematch build failed: %s", battle) end
      return
    end

    battle.trainerForfeitRematch = true
    battle.checkpointOrigin = {
      kind = "trainer_encounter",
      map = ow.map and ow.map.id,
      npcId = npc.id,
      trainerClass = trainerClass,
      partyIndex = partyIndex,
      trainerForfeitIdentity = rememberedNpc.id,
      trainerForfeitRematch = true,
    }
    rematchBattles[battle] = engagement
    battle.onFinish = function(result)
      recordBattle(game, rememberedNpc, trainerClass, partyIndex, result, {
        isRematch = true, paidForfeit = battle.paidTrainerForfeit == true,
      })
      rematchBattles[battle] = nil
      ow:afterBattle(result, battle)
      ow.engaging = false
      npc.frozen = false
    end
    ow:pushBattle(battle)
  end

  if okWorld and type(OverworldState) == "table"
      and type(OverworldState.talkTo) == "function" then
    local existingPatch = rawget(OverworldState, WORLD_PATCH)
    if type(existingPatch) == "table" and existingPatch.owner == mod.id
        and type(existingPatch.wrapper) == "function" then
      worldPatch = existingPatch
      feature.hotReload = "dispatcher_refreshed"
    elseif existingPatch ~= nil then
      error("trainer rematch adapter is owned by another mod", 0)
    else
      worldPatch = {
        owner = mod.id, active = true, original = OverworldState.talkTo,
      }
    end
    worldPatch.active = true
    worldPatch.lease = worldLease
    worldPatch.exports = mod.exports
    worldPatch.talkHandler = function(ow, npc, ...)
      local target = option("trainer_rematches") == true
        and rematchTarget(ow, npc) or nil
      if not target then
        return worldPatch.original(ow, npc, ...)
      end
      npc.frozen = true
      npc:facePlayer(ow.player)
      local header = headerFor(ow, npc)
      local baseText = target.after and Game.data.text[target.after]
        or (header and header.after and Game.data.text[header.after])
        or "I've been training\nsince our last battle!"
      local journey
      local rememberedNpc = memoryNpc(npc, target)
      if option("trainer_adaptive_dialogue") == true
          and dialogue and type(dialogue.context) == "function" then
        local ok, context = pcall(dialogue.context, dialogue, Game,
                                  rememberedNpc, target.trainerClass,
                                  target.partyIndex)
        if ok and type(context) == "table" then journey = context.text end
      end
      local question = baseText
      if journey and journey ~= "" and journey ~= baseText then
        question = question .. "\f" .. journey
      end
      question = question .. "\f" .. (target.question or "Want a rematch?")
      local TextBox = require("src.render.TextBox")
      Game.stack:push(TextBox.new(Game, question, nil, {
        choice = function(yes)
          if yes then startRematch(ow, npc, target) else npc.frozen = false end
        end,
      }))
    end
    if type(worldPatch.wrapper) ~= "function" then
      worldPatch.wrapper = function(ow, npc, ...)
        local handler = worldPatch.active and currentGeneration(worldPatch)
          and worldPatch.talkHandler or nil
        if type(handler) == "function" then return handler(ow, npc, ...) end
        return worldPatch.original(ow, npc, ...)
      end
    end
    rawset(OverworldState, WORLD_PATCH, worldPatch)
    if OverworldState.talkTo == worldPatch.original then
      OverworldState.talkTo = worldPatch.wrapper
    end

    -- Gen1Recomp 0.1.80 can restore trainer battles from checkpoints.  Its
    -- stock trainer continuation awards victory flags/rewards, which is
    -- correct for a first encounter but unsafe for a rematch.  Recognize only
    -- our explicit marker and rebuild the reward-free continuation.
    if type(OverworldState.restoreBattleContinuation) == "function" then
      worldPatch.restoreHandler = function(ow, battle, origin)
        if type(origin) ~= "table" or origin.trainerForfeitRematch ~= true then
          return worldPatch.restoreOriginal(ow, battle, origin)
        end
        if origin.kind ~= "trainer_encounter" or type(battle) ~= "table"
            or battle.kind ~= "trainer" or not ow.map
            or origin.map ~= ow.map.id
            or origin.trainerClass ~= battle.oppClass
            or (origin.partyIndex or 1) ~= (battle.partyIndex or 1)
            or type(origin.npcId) ~= "string" then
          return false
        end
        local npc = ow.npcPool and ow.npcPool[origin.npcId] or nil
        local target = npc and rematchTarget(ow, npc) or nil
        local rememberedNpc = target and memoryNpc(npc, target) or nil
        local originIdentity = origin.trainerForfeitIdentity or origin.npcId
        if not target or target.trainerClass ~= origin.trainerClass
            or target.partyIndex ~= (origin.partyIndex or 1)
            or not rememberedNpc or rememberedNpc.id ~= originIdentity then
          return false
        end
        local engagement = {
          npc = npc, memoryNpc = rememberedNpc,
          trainerClass = target.trainerClass,
          partyIndex = target.partyIndex,
          turnAway = target.kind == "ordinary",
        }
        battle.trainerForfeitRematch = true
        rematchBattles[battle] = engagement
        if option("trainer_forfeit_enabled") == true then
          attach(battle, engagement)
        end
        battle.onFinish = function(result)
          recordBattle(battle.game or Game, rememberedNpc,
            target.trainerClass, target.partyIndex, result, {
              isRematch = true,
              paidForfeit = battle.paidTrainerForfeit == true,
            })
          rematchBattles[battle] = nil
          ow:afterBattle(result, battle)
          ow.engaging = false
          npc.frozen = false
        end
        return true
      end
      if type(worldPatch.restoreWrapper) ~= "function" then
        worldPatch.restoreOriginal = OverworldState.restoreBattleContinuation
        worldPatch.restoreWrapper = function(ow, battle, origin)
          local handler = worldPatch.active and currentGeneration(worldPatch)
            and worldPatch.restoreHandler or nil
          if type(handler) == "function" then
            return handler(ow, battle, origin)
          end
          return worldPatch.restoreOriginal(ow, battle, origin)
        end
      end
      if OverworldState.restoreBattleContinuation == worldPatch.restoreOriginal then
        OverworldState.restoreBattleContinuation = worldPatch.restoreWrapper
      end
    end
  else
    feature.rematches = false
  end

  if mod.hooks and type(mod.hooks.wrap) == "function" then
    unsubscribe[#unsubscribe + 1] = mod.hooks:wrap("trainer.party",
      function(nextFn, class, party, partyDef)
        local built = nextFn(class, party, partyDef)
        local tag = constructingRematch
        if not tag or tag.trainerClass ~= class
            or tag.partyIndex ~= (party or 1) then return built end
        local isolated = cloneData(built)
        if option("trainer_growth") == "gentle"
            and dialogue and type(dialogue.rematchBoost) == "function" then
          local ok, descriptor = pcall(dialogue.rematchBoost, dialogue, Game,
            tag.memoryNpc or tag.npc, class, party or 1, built)
          if ok and type(descriptor) == "table" then
            if type(descriptor.levels) == "table" then
              for rawSlot, rawTarget in pairs(descriptor.levels) do
                local slotIndex = tonumber(rawSlot)
                if slotIndex and slotIndex == math.floor(slotIndex)
                    and type(isolated[slotIndex]) == "table" then
                  local current = tonumber(isolated[slotIndex].level) or 0
                  local target = boundedLevel(rawTarget)
                  if target > current then isolated[slotIndex].level = target end
                end
              end
            elseif tonumber(descriptor.levelBonus) then
              local bonus = tonumber(descriptor.levelBonus)
              for _, slot in ipairs(isolated) do
                local current = tonumber(slot.level) or 0
                local target = boundedLevel(current + bonus)
                if target > current then slot.level = target end
              end
            end
          end
        end
        return isolated
      end, 200)
  end

  unsubscribe[#unsubscribe + 1] = mod.events:on("world.trainer_engaged", function(event)
    if (option("trainer_forfeit_enabled") ~= true
          and option("trainer_rematches") ~= true)
        or type(event) ~= "table" or type(event.npc) ~= "table"
        or not ordinaryTrainer(overworldFor(event.npc), event.npc) then
      pending = nil
      return
    end
    pending = { npc = event.npc, trainerClass = event.trainerClass,
                partyIndex = event.partyIndex }
  end)

  unsubscribe[#unsubscribe + 1] = mod.events:on("battle.started", function(event)
    local battle = type(event) == "table" and event.battle or nil
    if type(battle) ~= "table" then pending = nil return end
    local engagement
    if rematchBattles[battle] then
      engagement = rematchBattles[battle]
    else
      engagement, pending = pending, nil
    end
    local kind = event.kind or (battle.battleKind and battle:battleKind())
    if kind == "trainer" and sameEngagement(engagement, battle) then
      if option("trainer_rematches") == true
          and battle.trainerForfeitRematch ~= true then
        observedBattles[battle] = engagement
      end
      if option("trainer_forfeit_enabled") == true then
        attach(battle, engagement)
      end
    end
  end)

  unsubscribe[#unsubscribe + 1] = mod.events:on("battle.ended", function(event)
    pending = nil
    local battle = type(event) == "table" and event.battle or nil
    if battle and battle.trainerForfeitRematch ~= true then
      local record = rawget(battle, PATCH_KEY)
      local observed = observedBattles[battle]
      local npc = (record and record.npc) or (observed and observed.npc)
      if npc then
        recordBattle(battle.game, npc, battle.oppClass,
          battle.partyIndex or 1, event.result, {
            isRematch = false, paidForfeit = battle.paidTrainerForfeit == true,
          })
      end
    end
    if battle then observedBattles[battle] = nil end
    detach(battle)
  end)

  function feature.cleanup()
    if not feature.installed then return end
    feature.installed = false
    pending, constructingRematch = nil, nil
    for battle in pairs(active) do detach(battle) end
    for _, stop in ipairs(unsubscribe) do
      if type(stop) == "function" then pcall(stop) end
    end
    if worldPatch and worldPatch.lease == worldLease then
      worldPatch.active = false
      worldPatch.talkHandler = nil
      worldPatch.restoreHandler = nil
      if OverworldState.talkTo == worldPatch.wrapper then
        OverworldState.talkTo = worldPatch.original
      end
      if rawget(OverworldState, WORLD_PATCH) == worldPatch then
        rawset(OverworldState, WORLD_PATCH, nil)
      end
      if worldPatch.restoreWrapper
          and OverworldState.restoreBattleContinuation == worldPatch.restoreWrapper then
        OverworldState.restoreBattleContinuation = worldPatch.restoreOriginal
      end
    end
    if dialogue and type(dialogue.cleanup) == "function" then pcall(dialogue.cleanup, dialogue) end
  end

  return feature
end
