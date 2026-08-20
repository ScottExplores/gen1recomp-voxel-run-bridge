-- Incorporated from Oak's Spare Starter 0.1.1 (MIT) and adapted to the
-- Scott's Tweaks namespace. See THIRD_PARTY_NOTICES.md.

local MapScripts = require("src.script.MapScripts")
local Commands = require("src.script.Commands")
local Party = require("src.pokemon.Party")
local GameVersion = require("src.core.GameVersion")

local LAB = "OAKS_LAB"
local CLAIMED_FIELD = "oak_spare_starter_claimed"

local BALLS = {
  {
    species = "CHARMANDER",
    text = "TEXT_OAKSLAB_CHARMANDER_POKE_BALL",
    object = "OAKSLAB_CHARMANDER_POKE_BALL",
    remainsWhen = "EVENT_CHOSE_SQUIRTLE",
    claimScript = "oak_spare_starter_claim_charmander",
  },
  {
    species = "SQUIRTLE",
    text = "TEXT_OAKSLAB_SQUIRTLE_POKE_BALL",
    object = "OAKSLAB_SQUIRTLE_POKE_BALL",
    remainsWhen = "EVENT_CHOSE_BULBASAUR",
    claimScript = "oak_spare_starter_claim_squirtle",
  },
  {
    species = "BULBASAUR",
    text = "TEXT_OAKSLAB_BULBASAUR_POKE_BALL",
    object = "OAKSLAB_BULBASAUR_POKE_BALL",
    remainsWhen = "EVENT_CHOSE_CHARMANDER",
    claimScript = "oak_spare_starter_claim_bulbasaur",
  },
}

local FULL_PARTY_SCRIPT = "oak_spare_starter_party_full"

local function objectIsVisible(save, objectName)
  local toggles = save.objectToggles
  local lab = toggles and toggles[LAB]
  return not (lab and lab[objectName] == false)
end

local function onlyVisibleStarterBall(save, objectName)
  local visible = 0
  for _, ball in ipairs(BALLS) do
    if objectIsVisible(save, ball.object) then
      visible = visible + 1
    end
  end
  return visible == 1 and objectIsVisible(save, objectName)
end

local function anyChoiceFlag(flags)
  return flags.EVENT_CHOSE_CHARMANDER
    or flags.EVENT_CHOSE_SQUIRTLE
    or flags.EVENT_CHOSE_BULBASAUR
end

local function isRemainingBall(save, ball)
  if not objectIsVisible(save, ball.object) then return false end

  local flags = save.flags or {}
  -- Native recomp saves carry the choice flags. Imported cartridge saves
  -- identify the same ball through their persistent object toggles.
  if anyChoiceFlag(flags) then
    return flags[ball.remainsWhen] == true
  end
  return onlyVisibleStarterBall(save, ball.object)
end

local function wasClaimed(save, modId)
  local bucket = save.modData and save.modData[modId]
  return bucket and bucket[CLAIMED_FIELD] == true or false
end

local function claimRows(ball)
  return {
    { "face_object", 5, "down" },
    { "ask", "It's PROF.OAK's\nlast POKEMON.\nTake " .. ball.species .. "?" },
    { "jump_if_false", "end" },
    { "play_sound", "Get_Key_Item" },
    { "show_text", "_OaksLabReceivedMonText", { RAM = ball.species } },
    { "give_pokemon", ball.species, 5 },
    { "jump_if_false", "end" },
    -- Keep the one-shot state private to this mod. The object toggle is a
    -- second persistent guard and removes the ball from the live map.
    { "set_field", "mod:" .. CLAIMED_FIELD, true },
    { "hide_object", LAB, ball.object },
  }
end

return function(mod, context)
  local standalone = context and context.findMod
    and context.findMod("oak_spare_starter") or nil
  if standalone then
    local delegated = {
      installed = false, delegated = true, provider = "oak_spare_starter",
      reason = "standalone_mod_active", sourceVersion = "0.1.1",
    }
    mod.exports.oakSpareStarter = delegated
    return delegated
  end
  local random = context and context.findMod
    and context.findMod("random_starters") or nil
  if random then
    local delegated = {
      installed = false, delegated = true, provider = "random_starters",
      reason = "random_starters_owns_lab", sourceVersion = "0.1.1",
    }
    mod.exports.oakSpareStarter = delegated
    return delegated
  end

  -- `games` is enforced by current builds. Releases before that manifest
  -- field existed simply ignore it, so retain a runtime Yellow guard too.
  if GameVersion.isYellow() then
    local disabled = { installed = false, reason = "yellow_not_supported" }
    mod.exports.oakSpareStarter = disabled
    return disabled
  end

  local function enabled()
    if context and context.settings then
      return context.settings:get("oak_spare_starter", true) == true
    end
    if not (mod.options and type(mod.options.get) == "function") then
      return true
    end
    local ok, value = pcall(mod.options.get, mod.options,
      "oak_spare_starter")
    return not ok or value ~= false
  end

  local scripts = {
    [FULL_PARTY_SCRIPT] = {
      { "show_text", "Your party is full!\nMake room, then\ncome back." },
    },
  }

  for _, ball in ipairs(BALLS) do
    scripts[ball.claimScript] = claimRows(ball)
  end

  local function runNamed(name, game, overworld, npc, done)
    local rows = MapScripts.namedScript(LAB, name)
    if type(rows) ~= "table" then
      done()
      return
    end
    overworld.runner:run(rows, {
      npc = npc,
      onDone = done,
      source = MapScripts.namedSource(LAB, name),
    })
  end

  local function runBase(ball, game, overworld, npc, done)
    local base = MapScripts.baseTalk(LAB, ball.text)
    if type(base) == "function" then
      base(game, overworld, npc, done)
    elseif type(base) == "table" then
      overworld.runner:run(base, { npc = npc, onDone = done })
    else
      done()
    end
  end

  local function makeTalkHandler(ball)
    return function(game, overworld, npc, done)
      done = done or function() end
      local save = game.save or {}
      local flags = save.flags or {}

      local ready = flags.EVENT_GOT_STARTER
        and flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB
        and enabled()
        and not wasClaimed(save, mod.id)
        and isRemainingBall(save, ball)

      if not ready then
        runBase(ball, game, overworld, npc, done)
        return
      end

      -- give_pokemon normally falls back to a PC box. The user's promise is
      -- stricter: the spare starter joins the party, or the ball stays put.
      if type(save.party) ~= "table" or #save.party >= Party.MAX then
        runNamed(FULL_PARTY_SCRIPT, game, overworld, npc, done)
        return
      end

      runNamed(ball.claimScript, game, overworld, npc, done)
    end
  end

  local talk = {}
  for _, ball in ipairs(BALLS) do
    talk[ball.text] = makeTalkHandler(ball)
  end

  mod.content.map_scripts:register(LAB, {
    priority = 200,
    talk = talk,
    scripts = scripts,
    onEnter = function(game, overworld)
      local save = game.save or {}
      if not enabled() or not wasClaimed(save, mod.id) then return end

      -- Repair a stale visible object if a save was copied or converted
      -- without its object toggle but retained this mod's private state.
      for _, ball in ipairs(BALLS) do
        if isRemainingBall(save, ball) then
          Commands.hide_object({
            game = game,
            save = save,
            overworld = overworld,
          }, LAB, ball.object)
          return
        end
      end
    end,
  })

  local feature = {
    installed = true, version = "0.12.1", sourceVersion = "0.1.1",
    claimedField = CLAIMED_FIELD,
  }
  mod.exports.oakSpareStarter = feature
  return feature
end
