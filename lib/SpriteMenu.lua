-- Integrated sprite-provider coordination for Scott's Battle Art Kanto.
--
-- Adapted from Scott's Sprite Menu 0.2.2 (MIT). Copyright (c) 2026 Scott
-- and contributors; see THIRD_PARTY_NOTICES.md. This module contains no art
-- and never enables or disables another mod. It coordinates only providers
-- the Gen1Recomp Loader has already activated.

local V = ...
local mod = V.mod
local BattleArt = V.require("BattleArt")
local ModSetting = V.require("ModSetting")
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

-- The bundled Battle Art library carries one coherent Pokemon collection for
-- each generation.  A preset deliberately changes front and back together;
-- ALL mode still exposes the independent expert rows for mixed-generation
-- combinations.
function SpriteMenu:battleArtGenerations()
  local out = {}
  for _, generation in ipairs(BattleArt.frontAnimationSetting.values or {}) do
    if findIndex(BattleArt.backAnimationSetting.values, generation) then
      out[#out + 1] = generation
    end
  end
  return out
end

function SpriteMenu:packChoices()
  local out = {}
  local crystal, fireRed = self:crystalHandle(), self:fireRedHandle()
  -- Two simultaneously-running replacement providers cannot be selected
  -- independently: both still receive the engine hook.  Do not advertise a
  -- misleading MODDED preset in that conflict; Battle Art can safely render
  -- over either one and remains available below.
  if not (crystal and fireRed) then
    if self:crystalReady() then
      out[#out + 1] = { id = "crystal", label = "CRYSTAL 2.0" }
    elseif fireRed then
      out[#out + 1] = { id = "firered", label = "FIRE RED" }
    end
  end
  for _, generation in ipairs(self:battleArtGenerations()) do
    out[#out + 1] = {
      id = "battle_art_" .. generation,
      generation = generation,
      label = "BATTLE ART G" .. generation:match("%d+$"),
    }
  end
  -- ORIGINAL ROM is selectable only when no replacement provider is running.
  -- Crystal patches the engine's underlying Pokemon definitions at load time,
  -- so advertising ROM while Crystal is present would still show Crystal art.
  if not crystal and not fireRed then
    out[#out + 1] = { id = "rom", label = "ORIGINAL ROM" }
  end
  return out
end

function SpriteMenu:activePackPreset()
  local crystal, fireRed = self:crystalHandle(), self:fireRedHandle()
  local mode = BattleArt.setting:get()
  if mode == "rom" then
    if crystal and fireRed then return "conflict" end
    if crystal then
      return self:crystalReady() and "crystal" or "crystal_update"
    end
    if fireRed then return "firered" end
    return "rom"
  end

  if BattleArt.duplicateSetting:get() == "battle_art" then
    local front = BattleArt.frontAnimationSetting:get()
    local back = BattleArt.backAnimationSetting:get()
    if mode == "animated" and front == back
        and findIndex(self:battleArtGenerations(), front) then
      return "battle_art_" .. front
    end
    return "battle_art_custom"
  end

  if crystal and fireRed then return "conflict" end
  if crystal then
    return self:crystalReady() and "crystal" or "crystal_update"
  end
  if fireRed then return "firered" end
  -- MODDED with no active replacement provider is the engine's own art.
  return "rom"
end

-- Preserve the public provider-family answer used by the older Sprite Menu
-- API. The selectable preset adds generation detail without changing what
-- existing companion code sees as the active provider.
function SpriteMenu:activePack()
  local preset = self:activePackPreset()
  if preset == "battle_art_custom"
      or (type(preset) == "string"
          and preset:find("battle_art_gen", 1, true) == 1) then
    return "battle_art"
  end
  return preset
end

function SpriteMenu:packLabel()
  local pack = self:activePackPreset()
  for _, choice in ipairs(self:packChoices()) do
    if choice.id == pack then return choice.label end
  end
  if pack == "crystal_update" then return "UPDATE CRYSTAL"
  elseif pack == "firered" then return "FIRE RED"
  elseif pack == "conflict" then return "PACK CONFLICT"
  elseif pack == "battle_art_custom" then return "BATTLE ART CUSTOM"
  elseif pack == "rom" then return "ORIGINAL ROM"
  end
  return "UNAVAILABLE"
end

function SpriteMenu:packVersion()
  local pack = self:activePackPreset()
  local found = (pack == "crystal" or pack == "crystal_update")
    and self:crystalHandle() or (pack == "firered" and self:fireRedHandle())
  return found and tostring(found.version or "UNKNOWN") or "BUILT IN"
end

function SpriteMenu:setPack(game, wanted)
  local choice
  for _, candidate in ipairs(self:packChoices()) do
    if candidate.id == wanted then choice = candidate break end
  end
  if not choice then return false, "PACK UNAVAILABLE" end

  local changes = {}
  local function change(setting, value)
    changes[#changes + 1] = { setting = setting, value = value }
  end
  if wanted == "crystal" or wanted == "firered" then
    -- ANIMATED keeps the staged renderer active while MODDED yields Pokemon
    -- picture ownership to the selected provider.  Remember the Battle Art
    -- generation rows so returning to that provider can resume them.
    change(BattleArt.setting, "animated")
    change(BattleArt.duplicateSetting, "modded")
  elseif wanted == "rom" then
    change(BattleArt.setting, "rom")
    change(BattleArt.duplicateSetting, "battle_art")
  else
    local generation = choice.generation
    if not generation then return false, "PACK UNAVAILABLE" end
    change(BattleArt.setting, "animated")
    change(BattleArt.duplicateSetting, "battle_art")
    change(BattleArt.frontAnimationSetting, generation)
    change(BattleArt.backAnimationSetting, generation)
  end

  local ok, err = self:applyTransaction(game, changes)
  if not ok then return false, err end
  return true, self:activePackPreset()
end

function SpriteMenu:cyclePack(game, direction)
  local choices = self:packChoices()
  if #choices == 0 then return false, "PACK UNAVAILABLE" end
  local current = self:activePackPreset()
  local index
  for i, choice in ipairs(choices) do
    if choice.id == current then index = i break end
  end
  -- A custom/mismatched expert profile advances to the first complete preset;
  -- Left begins at the other end so both directions remain intuitive.
  if not index then index = direction and direction < 0 and 1 or 0 end
  local step = direction and direction < 0 and -1 or 1
  index = ((index - 1 + step) % #choices) + 1
  return self:setPack(game, choices[index].id)
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
  local ok, result, detail = pcall(setting.setIndex, setting, index, game)
  if not ok then return false, tostring(result) end
  if result == nil then return false, tostring(detail or "OPTION WRITE FAILED") end
  return true, result
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

function SpriteMenu:opponentFlip()
  return BattleArt.opponentFlipSetting:get() == "flipped"
end

function SpriteMenu:opponentFlipLabel()
  return self:opponentFlip() and "ON" or "OFF"
end

function SpriteMenu:setOpponentFlip(game, enabled)
  if type(enabled) ~= "boolean" then return false, "BOOLEAN REQUIRED" end
  return self:applyOwnership({
    opponentFlip = enabled and "flipped" or "authored",
  }, game)
end

function SpriteMenu:playerBackFlip()
  return BattleArt.backFlipSetting:get() == "flipped"
end

function SpriteMenu:playerBackFlipLabel()
  return self:playerBackFlip() and "ON" or "OFF"
end

function SpriteMenu:setPlayerBackFlip(game, enabled)
  if type(enabled) ~= "boolean" then return false, "BOOLEAN REQUIRED" end
  return self:applyOwnership({
    backFlip = enabled and "flipped" or "authored",
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
  local loaderBuckets = game and game.mods and game.mods.modOptions
  -- Standalone Battle Art historically owned BATTLE_ART_VOXEL_FORK, while
  -- the fused build stores every Battle Art row in Scott's Tweaks' real
  -- Loader bucket. Either explicit key is authoritative and must prevent the
  -- old Sprite Hub mirror from overwriting a newer choice on every boot.
  local stableIds = { mod and mod.id, BATTLE_ART }
  for _, id in ipairs(stableIds) do
    if type(id) == "string" and id ~= "" then
      local saved = buckets[id]
      if type(saved) == "table" and saved.frontFlip ~= nil then return false end
      local live = type(loaderBuckets) == "table" and loaderBuckets[id]
      if type(live) == "table" and live.frontFlip ~= nil then return false end
    end
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

local function currentGame(game)
  if game ~= nil then return game end
  local ok, found = pcall(require, "src.core.Game")
  return ok and found or nil
end

function SpriteMenu:savedPokemonOwner(game)
  game = currentGame(game)
  local options = game and game.save and game.save.options
  local buckets = options and options.modOptions
  local bucket = type(buckets) == "table"
    and buckets[(mod and mod.id) or BATTLE_ART]
  local value = type(bucket) == "table" and rawget(bucket, "duplicateFix")
  if value == "battle_art" or value == "modded" then return value end
  return nil
end

function SpriteMenu:enforceSpecies(game)
  if not self:integrated() then return true, "EXTERNAL HUB" end
  local activeGame = currentGame(game)
  local crystal, fireRed = self:crystalHandle(), self:fireRedHandle()
  if crystal and fireRed then return false, "PACK CONFLICT" end

  -- Before the ART PACK row was selectable, the integrated coordinator chose
  -- Crystal for an untouched install.  Keep that default, but do not clobber
  -- an explicit BATTLE ART / ORIGINAL choice on game.ready, save.loaded, or
  -- hot reload.  The existing duplicateFix key is the durable source of truth,
  -- so no parallel setting or save migration is needed.
  local saved = self:savedPokemonOwner(activeGame)
  if saved then
    BattleArt.duplicateSetting:sync(saved)
    local loader = activeGame and activeGame.mods
    local buckets = loader and loader.modOptions
    local bucket = type(buckets) == "table"
      and buckets[(mod and mod.id) or BATTLE_ART]
    local live = type(bucket) == "table" and rawget(bucket, "duplicateFix")
    if live ~= saved then
      local index = findIndex(BattleArt.duplicateSetting.values, saved)
      local value, err = BattleArt.duplicateSetting:setIndex(index, activeGame)
      if value == nil then return false, err end
    end
    return true, saved
  end
  local pokemon = (self:crystalReady() or fireRed) and "modded" or "battle_art"
  return self:applyOwnership({ pokemon = pokemon }, activeGame)
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

local function runtimeCrystalValue(key, value)
  if key == "crystalTrainers" then
    local valid = value == "none" or value == "player"
      or value == "trainers" or value == "both"
      or value == "overworld" or value == "all"
    return valid and value or "both"
  elseif key == "crystalFront" then
    return value == true
  elseif key == "crystalBattlePic" then
    return value == "back" and "back" or "front"
  elseif key == "crystalAnimations" then
    return value == "once" and "once" or "loop"
  end
  return value
end

-- Persist Crystal's top-level provider preferences and Battle Art's ownership
-- keys as one logical edit. Runtime provider callbacks run only after disk has
-- accepted the complete snapshot; any callback failure restores memory,
-- caches, the provider runtime, and (best effort) the durable old snapshot.
function SpriteMenu:applyTransaction(game, settingValues, crystalValues)
  if not (game and game.save and type(game.save.options) == "table") then
    return false, "GAME NOT READY"
  end
  settingValues = settingValues or {}
  crystalValues = crystalValues or {}

  local staged = {}
  for _, change in ipairs(settingValues) do
    local setting = change and change.setting
    local index = setting and findIndex(setting.values, change.value)
    if not index then return false, "VALUE UNAVAILABLE" end
    local okCurrent, current = pcall(setting.get, setting)
    if not okCurrent or current ~= change.value then
      staged[#staged + 1] = { setting = setting, index = index }
    end
  end
  local token, stageError = ModSetting.stage(staged, game)
  if not token then return false, tostring(stageError) end

  local apply, crystalExports
  if next(crystalValues) ~= nil then
    local found = self:crystalHandle()
    crystalExports = found and found.exports
    apply = crystalExports and crystalExports.applyOption
    if type(apply) ~= "function" then
      token:rollback()
      return false, "UPDATE CRYSTAL"
    end
  end

  local options = game.save.options
  local crystalSnapshots = {}
  for key, value in pairs(crystalValues) do
    local stored = rawget(options, key)
    local runtime = runtimeCrystalValue(key, stored)
    -- crystalPlayerSprite has a game-specific runtime default (Red on Gen 1,
    -- Gold on Gen 2). When its save key is absent, nil is not the value that
    -- is actually active, so capture Crystal's live getter for an exact
    -- rollback instead of assigning nil after a failed provider refresh.
    if key == "crystalPlayerSprite"
        and type(crystalExports.playerSprite) == "function" then
      local okRuntime, active = pcall(crystalExports.playerSprite)
      if okRuntime and type(active) == "string" and active ~= "" then
        runtime = active
      end
    end
    crystalSnapshots[#crystalSnapshots + 1] = {
      key = key,
      present = rawget(options, key) ~= nil,
      value = stored,
      runtime = runtime,
      wanted = value,
    }
    options[key] = value
  end

  local function restoreCrystalOptions()
    for _, snapshot in ipairs(crystalSnapshots) do
      if snapshot.present then
        options[snapshot.key] = snapshot.value
      else
        options[snapshot.key] = nil
      end
    end
  end

  if game.writeOptions then
    local ok, result, detail = pcall(game.writeOptions, game)
    if not ok or result == false then
      restoreCrystalOptions()
      token:rollback()
      return false, not ok and tostring(result)
        or tostring(detail or "game.writeOptions returned false")
    end
  end

  for _, snapshot in ipairs(crystalSnapshots) do
    local ok, result = pcall(apply, snapshot.key, snapshot.wanted)
    if not ok or result == false then
      -- The failing callback may have assigned its runtime value before a
      -- downstream redraw raised, so restore it as well as earlier callbacks.
      for i = #crystalSnapshots, 1, -1 do
        local prior = crystalSnapshots[i]
        pcall(apply, prior.key, prior.runtime)
      end
      restoreCrystalOptions()
      token:rollback()
      if game.writeOptions then pcall(game.writeOptions, game) end
      return false, not ok and tostring(result)
        or "Crystal rejected " .. tostring(snapshot.key)
    end
  end
  token:finish()
  return true
end

function SpriteMenu:setCrystalOption(game, key, value)
  local found = self:crystalHandle()
  local apply = found and found.exports and found.exports.applyOption
  if type(apply) ~= "function" then return false, "UPDATE CRYSTAL" end
  local ok, err = self:applyTransaction(game, nil, { [key] = value })
  if not ok then return false, err end
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
  local crystalChanges, settingChanges = {}, {}

  local function change(setting, value)
    settingChanges[#settingChanges + 1] = {
      setting = setting, value = value,
    }
  end

  if source == "crystal" then
    crystalChanges.crystalTrainers = parts.overworld and "all" or "both"
    change(BattleArt.opponentTrainerSourceSetting, "modded")
    change(BattleArt.playerTrainerSourceSetting, "modded")
    local ok, err = self:applyTransaction(
      game, settingChanges, crystalChanges)
    if not ok then return false, err end
    return true, SpriteControl.profile()
  end

  if crystalMode then
    crystalChanges.crystalTrainers = quietMode
  end
  local rememberedMode
  if source == "battle_art" then
    local current = BattleArt.setting:get()
    if current == "rom" then
      local wanted = self.lastNonRomMode
      if wanted ~= "static" and wanted ~= "animated" then wanted = "animated" end
      change(BattleArt.setting, wanted)
    else
      rememberedMode = current
    end
  end
  local owner = source == "battle_art" and "battle_art" or "modded"
  change(BattleArt.opponentTrainerSourceSetting, owner)
  change(BattleArt.playerTrainerSourceSetting, owner)
  local ok, err = self:applyTransaction(game, settingChanges, crystalChanges)
  if not ok then return false, err end
  if rememberedMode then self.lastNonRomMode = rememberedMode end
  return true, SpriteControl.profile()
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
  if not self:crystalReady() then
    return self:setBattleArtSetting(BattleArt.viewSetting, value, game)
  end
  local ok, err = self:applyTransaction(game, {
    { setting = BattleArt.viewSetting, value = value },
  }, { crystalFront = value == "front" })
  if not ok then return false, err end
  return true, value
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
  local parts = crystalTrainerParts(wanted)
  local settings = {}
  if parts.opponent then
    settings[#settings + 1] = {
      setting = BattleArt.opponentTrainerSourceSetting, value = "modded",
    }
  end
  if parts.player then
    settings[#settings + 1] = {
      setting = BattleArt.playerTrainerSourceSetting, value = "modded",
    }
  end
  local ok, err = self:applyTransaction(
    game, settings, { crystalTrainers = wanted })
  if not ok then return false, err end
  return true, SpriteControl.profile()
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
    {
      label = "ANIMATIONS",
      value = function(g)
        local options = g and g.save and g.save.options
        return options and options.crystalAnimations == "once"
          and "PLAY ONCE" or "LOOP"
      end,
      step = function(g)
        local options = g and g.save and g.save.options
        if not options then return false end
        local wanted = options.crystalAnimations == "once" and "loop" or "once"
        return self:setCrystalOption(g, "crystalAnimations", wanted)
      end,
    },
  }
end

function SpriteMenu:packRows()
  return {
    {
      label = "ACTIVE PACK",
      value = function() return self:packLabel() end,
      step = function(game, direction) return self:cyclePack(game, direction) end,
      -- cyclePack commits its coupled ownership/generation transaction itself;
      -- the generic details screen must not write the same option file again.
      persists = true,
    },
    { label = "VERSION", value = function() return self:packVersion() end },
    { label = "BATTLE ART", value = function() return "GEN 1 - GEN 5" end },
    { label = "ART FILES", value = function() return "BUILT IN" end },
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
  elseif payload.mod == BATTLE_ART or payload.mod == (mod and mod.id) then
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
