-- Integrated sprite-provider coordination for Scott's Battle Art Kanto.
--
-- Adapted from Scott's Sprite Menu 0.2.2 (MIT). Copyright (c) 2026 Scott
-- and contributors; see THIRD_PARTY_NOTICES.md. This module contains no art
-- and never enables or disables another mod. It coordinates only providers
-- the Gen1Recomp Loader has already activated.

local V = ...
local mod = V.mod
local BattleArt = V.require("BattleArt")
local SpriteControl = V.require("SpriteControl")

local CRYSTAL = "crystal_animated_sprites_with_shiny_visuals"
local FIRERED = "firered_battle_sprites"
local EXTERNAL_HUB = "scotts_sprite_hub"
local BATTLE_ART = "BATTLE_ART_VOXEL_FORK"

local SpriteMenu = {}
SpriteMenu.__index = SpriteMenu

local function findIndex(values, wanted)
  for index, value in ipairs(values or {}) do
    if value == wanted then return index end
  end
  return nil
end

local function short(text, limit)
  text = tostring(text or "-"):upper()
  limit = limit or 17
  if #text <= limit then return text end
  return text:sub(1, limit - 1) .. "."
end

function SpriteMenu.new()
  return setmetatable({ game = nil, lastNonRomMode = nil }, SpriteMenu)
end

function SpriteMenu:handle(id)
  local ok, found = pcall(mod.find, id)
  return ok and found or nil
end

-- First-upgrade coexistence: Sprite Menu 0.2.2 remains the only provider
-- coordinator for a boot in which it is still active. The integrated UI and
-- lifecycle take over only after that mod is disabled/deleted and restarted.
function SpriteMenu:externalHub()
  return self:handle(EXTERNAL_HUB)
end

function SpriteMenu:integrated()
  return self:externalHub() == nil
end

function SpriteMenu:crystalHandle()
  return self:handle(CRYSTAL)
end

function SpriteMenu:fireRedHandle()
  return self:handle(FIRERED)
end

function SpriteMenu:crystalReady()
  local found = self:crystalHandle()
  local exports = found and found.exports
  return exports and type(exports.applyOption) == "function"
         and type(exports.listPlayerSprites) == "function"
end

function SpriteMenu:activePack()
  local crystal, fireRed = self:crystalHandle(), self:fireRedHandle()
  if crystal and fireRed then return "conflict" end
  if crystal then
    return self:crystalReady() and "crystal" or "crystal_update"
  end
  if fireRed then return "firered" end
  return "battle_art"
end

function SpriteMenu:packLabel()
  local pack = self:activePack()
  if pack == "crystal" then return "CRYSTAL 2.0"
  elseif pack == "crystal_update" then return "UPDATE CRYSTAL"
  elseif pack == "firered" then return "FIRE RED"
  elseif pack == "conflict" then return "PACK CONFLICT"
  end
  return "BATTLE ART"
end

function SpriteMenu:packVersion()
  local pack = self:activePack()
  local found = (pack == "crystal" or pack == "crystal_update")
    and self:crystalHandle() or (pack == "firered" and self:fireRedHandle())
  return found and tostring(found.version or "UNKNOWN") or "BUILT IN"
end

function SpriteMenu:hasTrainerControl()
  local okOpponent, opponent = pcall(SpriteControl.values, "opponentTrainer")
  local okPlayer, player = pcall(SpriteControl.values, "playerTrainer")
  return okOpponent and okPlayer
    and findIndex(opponent, "battle_art") and findIndex(opponent, "modded")
    and findIndex(player, "battle_art") and findIndex(player, "modded")
    and true or false
end

function SpriteMenu:setBattleArtSetting(setting, value, game)
  if not setting or type(setting.get) ~= "function"
      or type(setting.setIndex) ~= "function" then
    return false, "SETTING UNAVAILABLE"
  end
  local index = findIndex(setting.values, value)
  if not index then return false, "VALUE UNAVAILABLE" end
  local okCurrent, current = pcall(setting.get, setting)
  if okCurrent and current == value then return true, value end
  local ok, result = pcall(setting.setIndex, setting, index, game)
  return ok, ok and result or tostring(result)
end

function SpriteMenu:applyOwnership(profile, game)
  local okProfile, current = pcall(SpriteControl.profile)
  if not okProfile or type(current) ~= "table" then current = {} end
  local changes = {}
  for key, value in pairs(profile or {}) do
    if current[key] ~= value then changes[key] = value end
  end
  if next(changes) == nil then return true, current end
  local ok, changed, result = pcall(SpriteControl.applyProfile, changes, game)
  if not ok then return false, tostring(changed) end
  return changed, result
end

function SpriteMenu:playerFrontFlip()
  return BattleArt.frontFlipSetting:get() == "battle_art"
end

function SpriteMenu:playerFrontFlipLabel()
  return self:playerFrontFlip() and "ON" or "OFF"
end

function SpriteMenu:setPlayerFrontFlip(game, enabled)
  if type(enabled) ~= "boolean" then return false, "BOOLEAN REQUIRED" end
  return self:applyOwnership({
    frontFlip = enabled and "battle_art" or "default",
  }, game)
end

-- Import only the old adapter's one preference, only on the first boot where
-- the adapter is no longer active, and only if this stable Battle Art key has
-- never been explicitly saved. The old bucket is retained as rollback data.
function SpriteMenu:migrateLegacyFlip(game)
  if not self:integrated() then return false end
  local options = game and game.save and game.save.options
  local buckets = options and options.modOptions
  if type(buckets) ~= "table" then return false end
  local battleBucket = buckets[BATTLE_ART]
  if type(battleBucket) == "table" and battleBucket.frontFlip ~= nil then
    return false
  end
  local loaderBuckets = game and game.mods and game.mods.modOptions
  local loaderBattle = type(loaderBuckets) == "table"
    and loaderBuckets[BATTLE_ART]
  if type(loaderBattle) == "table" and loaderBattle.frontFlip ~= nil then
    return false
  end
  local oldBucket = buckets[EXTERNAL_HUB]
  local oldValue = type(oldBucket) == "table" and oldBucket.playerFrontFlip
  if type(oldValue) ~= "boolean" then
    local loaderOld = type(loaderBuckets) == "table"
      and loaderBuckets[EXTERNAL_HUB]
    oldValue = type(loaderOld) == "table" and loaderOld.playerFrontFlip
  end
  if type(oldValue) ~= "boolean" then return false end
  -- Force the stable Battle Art key to disk even when the imported value is
  -- the same as Battle Art's live default. The ordinary ownership helper
  -- deliberately skips unchanged values, but migration must distinguish an
  -- explicit imported choice from a fallback default on later boots.
  local wanted = oldValue and "battle_art" or "default"
  local ok = SpriteControl.set("frontFlip", wanted, game)
  return ok and true or false
end

function SpriteMenu:enforceSpecies(game)
  if not self:integrated() then return true, "EXTERNAL HUB" end
  local pack = self:activePack()
  if pack == "conflict" then return false, "PACK CONFLICT" end
  local pokemon = (pack == "crystal" or pack == "crystal_update"
                   or pack == "firered") and "modded" or "battle_art"
  return self:applyOwnership({ pokemon = pokemon }, game)
end

local function crystalTrainerParts(mode)
  return {
    opponent = mode == "trainers" or mode == "both" or mode == "all",
    player = mode == "player" or mode == "both" or mode == "all",
    overworld = mode == "overworld" or mode == "all",
  }
end

function SpriteMenu:crystalMode(game)
  local options = game and game.save and game.save.options
  local mode = options and options.crystalTrainers
  if mode == "none" or mode == "player" or mode == "trainers"
      or mode == "both" or mode == "overworld" or mode == "all" then
    return mode
  end
  return "both"
end

function SpriteMenu:setCrystalOption(game, key, value)
  local found = self:crystalHandle()
  local apply = found and found.exports and found.exports.applyOption
  if type(apply) ~= "function" then return false, "UPDATE CRYSTAL" end
  if not (game and game.save and game.save.options) then
    return false, "GAME NOT READY"
  end
  local ok, err = pcall(apply, key, value)
  if not ok then return false, tostring(err) end
  game.save.options[key] = value
  if game.writeOptions then pcall(game.writeOptions, game) end
  return true, value
end

function SpriteMenu:trainerOwners()
  local ok, profile = pcall(SpriteControl.profile)
  if not ok or type(profile) ~= "table" then return nil end
  return profile.opponentTrainer, profile.playerTrainer
end

function SpriteMenu:trainerSource(game)
  if self:crystalHandle() and not self:crystalReady() then
    return "update_crystal"
  end
  if not self:hasTrainerControl() then return "unavailable" end
  local opponentOwner, playerOwner = self:trainerOwners()
  if not opponentOwner or not playerOwner then return "unavailable" end
  local mode = BattleArt.setting:get()
  local crystal = self:crystalReady()
    and crystalTrainerParts(self:crystalMode(game)) or {}
  local function visible(owner, crystalOwns)
    if owner == "battle_art" then
      return mode == "rom" and "rom" or "battle_art"
    end
    return crystalOwns and "crystal" or "rom"
  end
  local opponent = visible(opponentOwner, crystal.opponent)
  local player = visible(playerOwner, crystal.player)
  return opponent == player and opponent or "mixed"
end

function SpriteMenu:trainerLabel(game)
  local labels = {
    crystal = "CRYSTAL", battle_art = "BATTLE ART", rom = "ROM",
    mixed = "MIXED", update_crystal = "UPDATE CRYSTAL",
    unavailable = "UNAVAILABLE",
  }
  return labels[self:trainerSource(game)] or "UNAVAILABLE"
end

function SpriteMenu:trainerChoices()
  if self:crystalHandle() and not self:crystalReady() then return nil end
  if not self:hasTrainerControl() then return nil end
  if self:crystalReady() then return { "crystal", "battle_art", "rom" } end
  return { "battle_art", "rom" }
end

function SpriteMenu:setTrainerSource(game, source)
  local choices = self:trainerChoices()
  if not findIndex(choices, source) then
    return false, self:trainerLabel(game)
  end
  local crystalMode = self:crystalReady() and self:crystalMode(game) or nil
  local parts = crystalMode and crystalTrainerParts(crystalMode) or {}
  local quietMode = parts.overworld and "overworld" or "none"

  if source == "crystal" then
    local wanted = parts.overworld and "all" or "both"
    local ok, err = self:setCrystalOption(game, "crystalTrainers", wanted)
    if not ok then return false, err end
    return self:applyOwnership({
      opponentTrainer = "modded", playerTrainer = "modded",
    }, game)
  end

  if crystalMode then
    local ok, err = self:setCrystalOption(
      game, "crystalTrainers", quietMode)
    if not ok then return false, err end
  end
  if source == "battle_art" then
    local current = BattleArt.setting:get()
    if current == "rom" then
      local wanted = self.lastNonRomMode
      if wanted ~= "static" and wanted ~= "animated" then wanted = "animated" end
      local ok, err = self:setBattleArtSetting(BattleArt.setting, wanted, game)
      if not ok then return false, err end
    else
      self.lastNonRomMode = current
    end
  end
  local owner = source == "battle_art" and "battle_art" or "modded"
  return self:applyOwnership({
    opponentTrainer = owner, playerTrainer = owner,
  }, game)
end

function SpriteMenu:cycleTrainerSource(game, direction)
  local choices = self:trainerChoices()
  if not choices then return false end
  local current = self:trainerSource(game)
  local index = findIndex(choices, current) or 1
  index = ((index - 1 + (direction or 1)) % #choices) + 1
  return self:setTrainerSource(game, choices[index])
end

function SpriteMenu:reconcileCrystalTrainerMode(game, mode)
  if not self:hasTrainerControl() then return false, "UNAVAILABLE" end
  local parts = crystalTrainerParts(mode)
  local changes = {}
  if parts.opponent then changes.opponentTrainer = "modded" end
  if parts.player then changes.playerTrainer = "modded" end
  if next(changes) == nil then return true, self:trainerOwners() end
  return self:applyOwnership(changes, game)
end

function SpriteMenu:playerViewLabel()
  if self:crystalHandle() and not self:crystalReady() then
    return "UPDATE CRYSTAL"
  end
  return BattleArt.viewSetting:get() == "front" and "FRONT" or "BACK"
end

function SpriteMenu:setPlayerView(game, value)
  if value ~= "front" and value ~= "back" then return false end
  if self:crystalHandle() and not self:crystalReady() then
    return false, "UPDATE CRYSTAL"
  end
  if self:crystalReady() then
    local ok, err = self:setCrystalOption(
      game, "crystalFront", value == "front")
    if not ok then return false, err end
  end
  return self:setBattleArtSetting(BattleArt.viewSetting, value, game)
end

function SpriteMenu:syncPlayerView(game)
  local value = BattleArt.viewSetting:get() == "front" and "front" or "back"
  if not self:crystalReady() then return true, value end
  local options = game and game.save and game.save.options
  local wanted = value == "front"
  if options and options.crystalFront == wanted then return true, value end
  return self:setCrystalOption(game, "crystalFront", wanted)
end

function SpriteMenu:cyclePlayerView(game, direction)
  local values = { "front", "back" }
  local current = BattleArt.viewSetting:get() == "front" and "front" or "back"
  local index = findIndex(values, current) or 1
  local wanted = values[((index - 1 + (direction or 1)) % #values) + 1]
  return self:setPlayerView(game, wanted)
end

function SpriteMenu:crystalModeLabel(game)
  local labels = {
    none = "NONE", player = "PLAYER", trainers = "TRAINER",
    both = "PLAYER + TRAINER", overworld = "OVERWORLD", all = "ALL",
  }
  return labels[self:crystalMode(game)] or "PLAYER + TRAINER"
end

function SpriteMenu:cycleCrystalMode(game, direction)
  local values = { "none", "player", "trainers", "both", "overworld", "all" }
  local index = findIndex(values, self:crystalMode(game)) or 4
  local wanted = values[((index - 1 + (direction or 1)) % #values) + 1]
  local ok, err = self:setCrystalOption(game, "crystalTrainers", wanted)
  if not ok then return false, err end
  return self:reconcileCrystalTrainerMode(game, wanted)
end

function SpriteMenu:crystalPlayerList()
  local found = self:crystalHandle()
  local list = found and found.exports and found.exports.listPlayerSprites
  if type(list) ~= "function" then return { "red.png" } end
  local ok, result = pcall(list)
  if not ok or type(result) ~= "table" or #result == 0 then
    return { "red.png" }
  end
  return result
end

function SpriteMenu:crystalPlayerLabel(game)
  local options = game and game.save and game.save.options
  local value = options and options.crystalPlayerSprite or "red.png"
  value = tostring(value):gsub("%.png$", ""):gsub("_flip$", "")
  return short(value)
end

function SpriteMenu:cycleCrystalPlayer(game, direction)
  local list = self:crystalPlayerList()
  local options = game and game.save and game.save.options
  local current = options and options.crystalPlayerSprite or "red.png"
  local index = findIndex(list, current) or 1
  local wanted = list[((index - 1 + (direction or 1)) % #list) + 1]
  return self:setCrystalOption(game, "crystalPlayerSprite", wanted)
end

function SpriteMenu:crystalRows(game)
  if not self:crystalHandle() then
    return { { label = "CRYSTAL PACK", value = function() return "NOT LOADED" end } }
  end
  if not self:crystalReady() then
    return { { label = "CRYSTAL PACK", value = function() return "UPDATE CRYSTAL" end } }
  end
  return {
    {
      label = "FRONT SPRITES",
      value = function() return self:playerViewLabel() end,
      step = function(g, direction) return self:cyclePlayerView(g, direction) end,
    },
    {
      label = "REPLACE SPRITES",
      value = function(g) return self:crystalModeLabel(g) end,
      step = function(g, direction) return self:cycleCrystalMode(g, direction) end,
    },
    {
      label = "PLAYER SPRITE",
      value = function(g) return self:crystalPlayerLabel(g) end,
      step = function(g, direction) return self:cycleCrystalPlayer(g, direction) end,
    },
    {
      label = "BATTLE PIC",
      value = function(g)
        return g.save.options.crystalBattlePic == "back" and "BACK" or "FRONT"
      end,
      step = function(g)
        local wanted = g.save.options.crystalBattlePic == "back" and "front" or "back"
        return self:setCrystalOption(g, "crystalBattlePic", wanted)
      end,
    },
  }
end

function SpriteMenu:packRows()
  return {
    { label = "ACTIVE PACK", value = function() return self:packLabel() end },
    { label = "VERSION", value = function() return self:packVersion() end },
    { label = "CHANGE PACK", value = function() return "MODS + RESTART" end },
    { label = "ART FILES", value = function() return "SEPARATE MOD" end },
  }
end

function SpriteMenu:enforce(game)
  if not self:integrated() then return true, "EXTERNAL HUB" end
  if game then self.game = game end
  local activeGame = game or self.game
  if activeGame then self:migrateLegacyFlip(activeGame) end
  local ok, result = self:enforceSpecies(activeGame)
  if not ok then return ok, result end
  if activeGame and self:crystalReady() then
    local trainersOK, trainersResult = self:reconcileCrystalTrainerMode(
      activeGame, self:crystalMode(activeGame))
    if not trainersOK then return false, trainersResult end
    local viewOK, viewResult = self:syncPlayerView(activeGame)
    if not viewOK then return false, viewResult end
  end
  local mode = BattleArt.setting:get()
  if mode ~= "rom" then self.lastNonRomMode = mode end
  return true, result
end

function SpriteMenu:onOptionsChanged(payload)
  if not self:integrated() or type(payload) ~= "table" then return end
  if payload.mod == CRYSTAL and payload.key == "crystalTrainers" and self.game then
    self:reconcileCrystalTrainerMode(self.game, self:crystalMode(self.game))
  elseif payload.mod == BATTLE_ART then
    if payload.key == "playerView" and self.game then
      self:syncPlayerView(self.game)
    elseif payload.key == "duplicateFix" or payload.key == "frontFlip"
        or payload.key == "opponentTrainerSource"
        or payload.key == "playerTrainerSource" then
      self:enforce(self.game)
    end
  end
end

function SpriteMenu:ownership()
  local ok, owners = pcall(SpriteControl.owners)
  return ok and owners or nil
end

SpriteMenu.ids = {
  externalHub = EXTERNAL_HUB,
  crystal = CRYSTAL,
  firered = FIRERED,
  battleArt = BATTLE_ART,
}

return SpriteMenu
