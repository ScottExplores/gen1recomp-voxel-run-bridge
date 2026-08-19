-- Versioned ownership seam for sprite-menu companion mods.
--
-- This intentionally exports values and operations rather than the mutable
-- ModSetting objects.  Callers can ask what owns each surface, make a checked
-- change, and optionally hand over the live battle for an immediate,
-- identity-safe refresh without depending on Battle Art's file layout.
local V = ...

local BattleArt = V.require("BattleArt")
local AnimatedBattleArt = V.require("AnimatedBattleArt")
local SpriteControl = {}
SpriteControl.API_VERSION = 1
SpriteControl.SOURCE_MOD_ID = "BATTLE_ART_VOXEL_FORK"

local definitions = {
  pokemon = {
    setting = BattleArt.duplicateSetting,
    values = { battle_art = true, modded = true },
  },
  opponentTrainer = {
    setting = BattleArt.opponentTrainerSourceSetting,
    values = { battle_art = true, modded = true },
  },
  playerTrainer = {
    setting = BattleArt.playerTrainerSourceSetting,
    values = { battle_art = true, modded = true },
  },
  frontFlip = {
    setting = BattleArt.frontFlipSetting,
    values = { battle_art = true, default = true },
  },
}

local aliases = {
  pokemon = "pokemon",
  species = "pokemon",
  opponent = "opponentTrainer",
  opponent_trainer = "opponentTrainer",
  opponentTrainer = "opponentTrainer",
  player = "playerTrainer",
  player_trainer = "playerTrainer",
  playerTrainer = "playerTrainer",
  flip = "frontFlip",
  front_flip = "frontFlip",
  frontFlip = "frontFlip",
}

local function canonical(surface)
  return type(surface) == "string" and aliases[surface] or nil
end

local function liveGame(game)
  if game ~= nil then return game end
  local ok, current = pcall(require, "src.core.Game")
  return ok and current or nil
end

local function indexFor(def, value)
  if not def or not def.values[value] then return nil end
  for i, candidate in ipairs(def.setting.values) do
    if candidate == value then return i end
  end
  return nil
end

local function setChecked(name, value, game)
  local def = definitions[name]
  local index = indexFor(def, value)
  if not index then
    return false, ("unsupported %s value: %s"):format(
      tostring(name), tostring(value))
  end
  local ok, result = pcall(def.setting.setIndex, def.setting, index,
                           liveGame(game))
  if not ok then return false, tostring(result) end
  return true, result
end

function SpriteControl.get(surface)
  local name = canonical(surface)
  if not name then return nil, "unknown sprite surface: " .. tostring(surface) end
  local ok, value = pcall(definitions[name].setting.get,
                          definitions[name].setting)
  if not ok then return nil, tostring(value) end
  return value
end

function SpriteControl.profile()
  return {
    pokemon = BattleArt.duplicateSetting:get(),
    opponentTrainer = BattleArt.opponentTrainerSourceSetting:get(),
    playerTrainer = BattleArt.playerTrainerSourceSetting:get(),
    frontFlip = BattleArt.frontFlipSetting:get(),
  }
end

function SpriteControl.owners()
  local profile = SpriteControl.profile()
  return {
    pokemon = profile.pokemon,
    opponentTrainer = profile.opponentTrainer,
    playerTrainer = profile.playerTrainer,
  }
end

function SpriteControl.values(surface)
  local name = canonical(surface)
  if not name then return nil, "unknown sprite surface: " .. tostring(surface) end
  local out = {}
  for _, value in ipairs(definitions[name].setting.values) do
    out[#out + 1] = value
  end
  return out
end

function SpriteControl.refresh(battle)
  if not battle then return false, "battle is required" end
  -- Animated state owns playerBackPic independently of BattleArt's static
  -- replacement record.  Release it first; both restorers compare image
  -- identity and therefore cannot trample a later provider.
  AnimatedBattleArt.releasePlayerTrainer(battle)
  BattleArt.applyTrainers(battle)
  return true
end

function SpriteControl.set(surface, value, game, battle)
  local name = canonical(surface)
  if not name then return false, "unknown sprite surface: " .. tostring(surface) end
  local ok, result = setChecked(name, value, game)
  if not ok then return false, result end
  if battle then SpriteControl.refresh(battle) end
  return true, result
end

function SpriteControl.applyProfile(profile, game, battle)
  if type(profile) ~= "table" then
    return false, "sprite profile must be a table"
  end

  -- Validate the complete request before changing any setting, so a typo
  -- cannot leave half of a one-owner profile applied.
  local changes, seen = {}, {}
  for surface, value in pairs(profile) do
    local name = canonical(surface)
    if not name then
      return false, "unknown sprite surface: " .. tostring(surface)
    end
    if seen[name] and seen[name] ~= value then
      return false, "conflicting values for sprite surface: " .. name
    end
    if not indexFor(definitions[name], value) then
      return false, ("unsupported %s value: %s"):format(
        tostring(name), tostring(value))
    end
    seen[name] = value
    changes[#changes + 1] = { name = name, value = value }
  end

  for _, change in ipairs(changes) do
    local ok, err = setChecked(change.name, change.value, game)
    if not ok then return false, err end
  end
  if battle then SpriteControl.refresh(battle) end
  return true, SpriteControl.profile()
end

function SpriteControl.export()
  return {
    apiVersion = SpriteControl.API_VERSION,
    sourceModId = SpriteControl.SOURCE_MOD_ID,
    get = SpriteControl.get,
    profile = SpriteControl.profile,
    owners = SpriteControl.owners,
    values = SpriteControl.values,
    set = SpriteControl.set,
    applyProfile = SpriteControl.applyProfile,
    refresh = SpriteControl.refresh,
  }
end

return SpriteControl
