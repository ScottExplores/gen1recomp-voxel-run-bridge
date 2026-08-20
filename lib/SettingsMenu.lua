-- Categorized Battle Art settings and integrated sprite-provider menu.
--
-- The OptionRows navigation pattern and sprite coordination are adapted from
-- Scott's Sprite Menu 0.2.2 under MIT; see THIRD_PARTY_NOTICES.md. No artwork
-- is included here. Screen ids end in `Options`, the public semantic shape
-- Gen1 Modern UI recognizes and Scott's Dual Screen routes to the lower panel.

local V = ...
local mod = V.mod
local OptionScreen = V.require("OptionScreen")
local SpriteMenu = V.require("SpriteMenu")

local SettingsMenu = {}

local SCREEN = {
  main = "BattleArtSettingsOptions",
  quick = "BattleArtQuickOptions",
  views = "BattleArtViewsCameraOptions",
  world = "BattleArtWorldOptions",
  battles = "BattleArtBattlesOptions",
  sprites = "BattleArtSpritesTrainersOptions",
  player = "BattleArtPlayerOptions",
  advanced = "BattleArtAdvancedOptions",
  crystal = "BattleArtCrystalOptions",
  pack = "BattleArtSpritePackOptions",
}

-- SIMPLE hides the categories a player only visits to tune the renderer, so
-- the everyday menu is five short screens instead of a wall of switches. ALL
-- restores them. Nothing is disabled either way -- a hidden row keeps whatever
-- value it already had.
local CATEGORY_ORDER = {
  { id = "quick",    label = "QUICK" },
  { id = "world",    label = "OPEN WORLD" },
  { id = "player",   label = "PLAYER" },
  { id = "sprites",  label = "SPRITES" },
  { id = "battles",  label = "BATTLES" },
  { id = "views",    label = "VIEWS & CAMERA", advancedOnly = true },
  { id = "advanced", label = "ADVANCED",       advancedOnly = true },
}


-- Every persistent schema key has one canonical category. Quick is a small
-- set of shortcuts and may intentionally repeat frequent rows. Unknown future
-- keys are appended to Advanced at install time instead of becoming orphaned.
local CATEGORY_KEYS = {
  views = {
    "grid", "curve", "dof", "jump", "jumpkey", "jumppad",
  },
  world = {
    "worldFill", "renderDistance", "water", "shadowQuality", "daytime",
    "ceiling", "headroom", "cutaway", "rails", "spill", "fittings",
    "rock", "apron", "talltrees", "peaks", "pools", "sconces", "bats",
    "backdrop", "horizonart", "grass", "windows", "ceildetail",
    "bouldertrees", "doorstep",
  },
  battles = {
    "battles", "letsgo", "hudScale", "spriteLight", "hudColor",
    "arenaFill", "backdropOffset", "bossBg", "textboxFill",
  },
  -- Everything that answers "how do I appear" lives together, so the front
  -- / back trainer choice and the player art sets are one screen rather than
  -- scattered between the sprite and camera pages.
  player = {
    "playerView", "frontFlip", "backPlacement",
    "playerTrainerSource", "playerArtSet", "playerAnimatedSet",
    "headbob", "third", "fpfov",
  },
  sprites = {
    "battleArt", "duplicateFix", "opponentTrainerSource",
    "trainerArtSet", "frontAnimatedSet", "backAnimatedSet",
  },
  advanced = {
    "aa", "fastchunks", "particles", "ambience", "grasssfx", "stepsfx",
    "doorsfx", "rain", "umbrellas", "puddles", "lightning", "lights",
    "shafts", "canopy", "vines", "fog", "clouds", "stars", "birds",
    "aircraft", "rainbows", "insects", "groundflock", "wind", "debug",
  },
}

local QUICK_KEYS = { "battles", "letsgo", "aa" }

local state = {
  installed = false,
  schema = {},
  byKey = {},
  categoryKeys = {},
  sprite = SpriteMenu.new(),
}

local function cloneKeys()
  local out = {}
  for category, keys in pairs(CATEGORY_KEYS) do
    out[category] = {}
    for i, key in ipairs(keys) do out[category][i] = key end
  end
  return out
end

local function optionValue(row)
  local ok, value = pcall(mod.options.get, mod.options, row.key)
  if ok and value ~= nil then return value end
  return row.default
end

local function snapshotBucket(root)
  if type(root) ~= "table" then return nil end
  local all = rawget(root, "modOptions")
  local original = type(all) == "table" and rawget(all, mod.id) or nil
  local snapshot = {
    root = root,
    all = all,
    allWasTable = type(all) == "table",
    original = original,
    bucketWasTable = type(original) == "table",
    values = {},
  }
  if snapshot.bucketWasTable then
    for key, value in pairs(original) do snapshot.values[key] = value end
  end
  return snapshot
end

local function restoreBucket(snapshot)
  if not snapshot then return end
  if not snapshot.allWasTable then
    snapshot.root.modOptions = snapshot.all
    return
  end
  local all = snapshot.all
  snapshot.root.modOptions = all
  if snapshot.bucketWasTable then
    local original = snapshot.original
    for key in pairs(original) do original[key] = nil end
    for key, value in pairs(snapshot.values) do original[key] = value end
    all[mod.id] = original
  else
    all[mod.id] = snapshot.original
  end
end

local function writeOption(game, row, value)
  if not (game and game.save and type(game.save.options) == "table") then
    return false
  end
  local options = game.save.options
  local savedSnapshot = snapshotBucket(options)
  local loader = game.mods
  local liveSnapshot = snapshotBucket(loader)
  options.modOptions = options.modOptions or {}
  options.modOptions[mod.id] = options.modOptions[mod.id] or {}
  options.modOptions[mod.id][row.key] = value

  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
    loader.modOptions[mod.id][row.key] = value
  end
  if game.writeOptions then
    local ok, result, detail = pcall(game.writeOptions, game)
    if not ok or result == false then
      restoreBucket(liveSnapshot)
      restoreBucket(savedSnapshot)
      return false, not ok and tostring(result)
        or tostring(detail or "game.writeOptions returned false")
    end
  end
  if loader and loader.events then
    pcall(loader.events.emit, loader.events, "mod.options_changed",
      { mod = mod.id, key = row.key, value = value })
  end
  return true
end

local function choiceIndex(row, value)
  for i, choice in ipairs(row.choices or {}) do
    if choice[2] == value then return i end
  end
  return 1
end

local function schemaRow(row)
  local descriptor = { id = mod.id .. ":" .. row.key,
                       label = row.label or row.key }
  if row.type == "toggle" then
    descriptor.value = function()
      return optionValue(row) and "ON" or "OFF"
    end
    descriptor.step = function(game)
      return writeOption(game, row, not optionValue(row))
    end
  elseif row.type == "choice" then
    descriptor.value = function()
      local choice = (row.choices or {})[choiceIndex(row, optionValue(row))]
      return choice and tostring(choice[1]) or "----"
    end
    descriptor.step = function(game, direction)
      local choices = row.choices or {}
      if #choices == 0 then return false end
      local index = choiceIndex(row, optionValue(row))
      index = ((index - 1 + (direction or 1)) % #choices) + 1
      return writeOption(game, row, choices[index][2])
    end
  elseif row.type == "number" then
    local function clamp(value)
      if row.min then value = math.max(row.min, value) end
      if row.max then value = math.min(row.max, value) end
      return value
    end
    descriptor.value = function()
      return tostring(optionValue(row) or 0)
    end
    descriptor.step = function(game, direction)
      local value = tonumber(optionValue(row)) or 0
      return writeOption(game, row,
        clamp(value + (direction or 1) * (row.step or 1)))
    end
  elseif row.type == "text" then
    descriptor.value = function() return tostring(optionValue(row) or "") end
    descriptor.activate = function(game)
      local NamingScreen = require("src.ui.NamingScreen")
      game.stack:push(NamingScreen.new(game, {
        title = (row.label or row.key) .. "?",
        maxLen = row.maxLen or 7,
        default = optionValue(row),
        onDone = function(value)
          if value ~= nil then writeOption(game, row, value) end
        end,
      }))
    end
  else
    descriptor.value = function() return "UNAVAILABLE" end
  end
  return descriptor
end

local function pipelineRow(id, label)
  local Pipelines = require("src.render.Pipelines")
  for _, row in ipairs(Pipelines.rows()) do
    if row.id == "pipeline:" .. id then
      row.label = label or row.label
      return row
    end
  end
  return { id = "pipeline:" .. id, label = label or id:upper(),
           value = function() return "UNAVAILABLE" end }
end

local function rowForKey(key)
  local row = state.byKey[key]
  return row and schemaRow(row) or nil
end

local function appendKeyRows(out, keys, skip)
  for _, key in ipairs(keys or {}) do
    if not (skip and skip[key]) then
      local row = rowForKey(key)
      if row then out[#out + 1] = row end
    end
  end
  return out
end

local function push(game, id)
  return mod.ui.push(game, id)
end

local function openRow(label, value, screenId, enabled)
  return {
    label = label,
    value = type(value) == "function" and value or function() return value end,
    activate = function(game)
      if enabled == nil or enabled() then push(game, screenId) end
    end,
  }
end

local function refreshUnderlyingOptions(game)
  local top = game and game.stack and game.stack:top()
  if not top then return end
  local OptionsMenu = require("src.ui.OptionsMenu")
  if getmetatable(top) ~= OptionsMenu then return end
  local selected = top.rows and top.rows[top.index or 1]
  local selectedId = selected and selected.id
  local rebuilt = OptionsMenu.new(game)
  top.rows = rebuilt.rows
  for i, row in ipairs(top.rows) do
    if selectedId and row.id == selectedId then top.index = i break end
  end
  local cancel = #top.rows + 1
  if (top.index or 1) > cancel then top.index = cancel end
end

-- SIMPLE is the default: the everyday screens only. ALL adds the renderer
-- tuning pages back. This hides rows, it never changes their values, so
-- switching back to ALL finds every setting exactly as it was left.
-- The fused host and this standalone fallback share one visibility flag. That
-- keeps an old Battle Art screen id, the Mod Manager route, and MOD SETTINGS
-- from remembering three different ideas of BASIC versus ALL.
local SIMPLE_KEY = "simple_menu"

local function simpleMode()
  local ok, value = pcall(mod.options.get, mod.options, SIMPLE_KEY)
  if ok and value ~= nil then return value and true or false end
  return true
end

local function mainRows()
  local out = {}
  local simple = simpleMode()
  for _, category in ipairs(CATEGORY_ORDER) do
    if not (simple and category.advancedOnly) then
      out[#out + 1] = openRow(category.label, "OPEN", SCREEN[category.id])
    end
  end
  out[#out + 1] = {
    id = mod.id .. ":" .. SIMPLE_KEY,
    label = "OPTIONS SHOWN",
    value = function() return simpleMode() and "BASIC" or "ALL" end,
    step = function(game)
      return writeOption(game, { key = SIMPLE_KEY }, not simpleMode())
    end,
  }
  return out
end

local function quickRows()
  local out = { pipelineRow("voxel", "VIEW") }
  appendKeyRows(out, QUICK_KEYS)
  if state.sprite:integrated() then
    out[#out + 1] = openRow("SPRITE PACK",
      function() return state.sprite:packLabel() end, SCREEN.sprites)
    out[#out + 1] = {
      label = "PLAYER POKEMON",
      value = function() return state.sprite:playerViewLabel() end,
      step = function(game, direction)
        return state.sprite:cyclePlayerView(game, direction)
      end,
    }
  else
    out[#out + 1] = openRow("SPRITE MENU", "EXTERNAL",
      "ScottsSpriteOptions")
  end
  return out
end

local function viewsRows()
  local out = { pipelineRow("voxel"), pipelineRow("tiltshift") }
  return appendKeyRows(out, state.categoryKeys.views)
end

local function worldRows()
  local out = { pipelineRow("lavveil", "LAVENDER VEIL") }
  return appendKeyRows(out, state.categoryKeys.world)
end

local function battleRows()
  return appendKeyRows({}, state.categoryKeys.battles)
end

local function spriteRows()
  local out = {}
  local skip = nil
  if state.sprite:integrated() then
    skip = { playerView = true, frontFlip = true }
    out[#out + 1] = openRow("PACK",
      function() return state.sprite:packLabel() end, SCREEN.pack)
  else
    out[#out + 1] = openRow("SPRITE MENU", "EXTERNAL",
      "ScottsSpriteOptions")
  end
  return appendKeyRows(out, state.categoryKeys.sprites, skip)
end

-- The player screen also carries the Crystal player-art controls when the
-- integrated sprite pack is present, so choosing who you look like and which
-- way you face is one place rather than three.
local function playerRows()
  local out = {}
  if state.sprite:integrated() then
    out[#out + 1] = {
      label = "PLAYER POKEMON",
      value = function() return state.sprite:playerViewLabel() end,
      step = function(game, direction)
        return state.sprite:cyclePlayerView(game, direction)
      end,
    }
    out[#out + 1] = {
      label = "MY POKEMON FLIP",
      value = function() return state.sprite:playerFrontFlipLabel() end,
      step = function(game)
        return state.sprite:setPlayerFrontFlip(
          game, not state.sprite:playerFrontFlip())
      end,
    }
    out[#out + 1] = {
      label = "TRAINER ART",
      value = function(game) return state.sprite:trainerLabel(game) end,
      step = function(game, direction)
        return state.sprite:cycleTrainerSource(game, direction)
      end,
    }
    out[#out + 1] = openRow("CRYSTAL OPTIONS", function()
      if not state.sprite:crystalHandle() then return "NOT LOADED" end
      return state.sprite:crystalReady() and "OPEN" or "UPDATE CRYSTAL"
    end, SCREEN.crystal, function() return state.sprite:crystalReady() end)
  end
  return appendKeyRows(out, state.categoryKeys.player)
end

local function advancedRows()
  return appendKeyRows({}, state.categoryKeys.advanced)
end

local function screen(title, rows, onCancel)
  return {
    new = function(game)
      return OptionScreen.new(game, {
        title = title, rows = rows, onCancel = onCancel,
      })
    end,
  }
end

local function registerScreens()
  mod.content.screens:register(SCREEN.main,
    screen("BATTLE ART", mainRows, refreshUnderlyingOptions))
  mod.content.screens:register(SCREEN.quick,
    screen("QUICK", quickRows))
  mod.content.screens:register(SCREEN.views,
    screen("VIEWS & CAMERA", viewsRows))
  mod.content.screens:register(SCREEN.world,
    screen("OPEN WORLD", worldRows))
  mod.content.screens:register(SCREEN.player,
    screen("PLAYER", playerRows))
  mod.content.screens:register(SCREEN.battles,
    screen("BATTLES", battleRows))
  mod.content.screens:register(SCREEN.sprites,
    screen("SPRITES", spriteRows))
  mod.content.screens:register(SCREEN.advanced,
    screen("ADVANCED", advancedRows))
  mod.content.screens:register(SCREEN.crystal,
    screen("CRYSTAL SPRITES", function(game)
      return state.sprite:crystalRows(game)
    end))
  mod.content.screens:register(SCREEN.pack,
    screen("SPRITE PACK", function() return state.sprite:packRows() end))
end

local function prepareSchema(schema)
  state.schema = schema or {}
  state.byKey = {}
  state.categoryKeys = cloneKeys()
  local assigned = {}
  for category, keys in pairs(state.categoryKeys) do
    if category ~= "quick" then
      for _, key in ipairs(keys) do assigned[key] = category end
    end
  end
  for _, row in ipairs(state.schema) do
    if type(row) == "table" and type(row.key) == "string" then
      state.byKey[row.key] = row
      if not assigned[row.key] then
        state.categoryKeys.advanced[#state.categoryKeys.advanced + 1] = row.key
        assigned[row.key] = "advanced"
      end
    end
  end
  state.assigned = assigned
end

local function installStartEntry()
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" or not state.sprite:integrated() then return out end
    for _, item in ipairs(out) do
      if item.id == "scotts_sprite_hub.open"
          or item.id == "scotts_tweaks.open"
          or item.label == "BATTLE ART"
          or item.label == "MOD SETTINGS" then
        return out
      end
    end
    return mod.ui.insertBefore(out, "MODS", {
      -- Historical id makes an old Sprite Menu wrapper dedupe rather than
      -- adding a second provider screen during first-upgrade coexistence.
      id = "scotts_sprite_hub.open",
      label = "BATTLE ART",
      onSelect = function()
        state.sprite.game = game
        push(game, SCREEN.main)
      end,
    })
  end, 100)
end

local function installManagerRoute()
  local ManagerState = require("src.mods.ManagerState")
  local marker = "battleArtCategorizedOptionsHook"
  local hook = rawget(ManagerState, marker)
  if type(hook) ~= "table" then
    hook = { original = ManagerState.openOptions }
    rawset(ManagerState, marker, hook)
    ManagerState.openOptions = function(self, manifest)
      local live = rawget(ManagerState, marker)
      if manifest and manifest.id == mod.id and live and live.open then
        return live.open(self.game)
      end
      return live.original(self, manifest)
    end
  end
  hook.open = function(game)
    state.sprite.game = game
    -- In the fused package Tweaks registers this screen later in the same
    -- entry load. By the time a player can open Mod Manager it is present, so
    -- every route reaches the same categorized menu. A standalone Battle Art
    -- install has no such screen and keeps its historical fallback.
    local tweaks = mod.exports and mod.exports.tweaksMenu
    local main = tweaks and tweaks.screenIds and tweaks.screenIds.main
    if main then
      local ok, result = pcall(push, game, main)
      if ok then return result end
    end
    push(game, SCREEN.main)
  end
end

local function installSpriteLifecycle()
  mod.events:on("mods.loaded", function()
    if state.sprite:integrated() then state.sprite:enforce(nil) end
  end)
  mod.events:on("game.ready", function(payload)
    local game = payload and payload.game
    if game and state.sprite:integrated() then state.sprite:enforce(game) end
  end)
  local function lifecycle()
    if state.sprite:integrated() and state.sprite.game then
      state.sprite:enforce(state.sprite.game)
    end
  end
  mod.events:on("save.created", lifecycle)
  mod.events:on("save.loaded", lifecycle)
  mod.events:on("mod.options_changed", function(payload)
    state.sprite:onOptionsChanged(payload)
  end)
end

function SettingsMenu.install(schema)
  prepareSchema(schema)
  registerScreens()
  installStartEntry()
  installManagerRoute()
  installSpriteLifecycle()
  state.installed = true
  return SettingsMenu
end

function SettingsMenu.open(game)
  state.sprite.game = game
  return push(game, SCREEN.main)
end

function SettingsMenu.optionsRow()
  return {
    id = mod.id .. ":settingsMenu",
    label = "MOD SETTINGS",
    value = function() return "OPEN" end,
    activate = function(game)
      -- One entry point for the whole fused build: the unified MOD SETTINGS
      -- screen. Falls back to this renderer's own menu if the unified screen
      -- is not registered (a standalone Battle Art install).
      local tweaks = mod.exports and mod.exports.tweaksMenu
      local main = tweaks and tweaks.screenIds and tweaks.screenIds.main
      if main then return push(game, main) end
      return SettingsMenu.open(game)
    end,
  }
end

function SettingsMenu.coverage()
  local total, reached, duplicates = 0, 0, 0
  local seen = {}
  for _, row in ipairs(state.schema) do
    if type(row) == "table" and type(row.key) == "string" then total = total + 1 end
  end
  for category, keys in pairs(state.categoryKeys) do
    if category ~= "quick" then
      for _, key in ipairs(keys) do
        if state.byKey[key] then
          if seen[key] then duplicates = duplicates + 1 else reached = reached + 1 end
          seen[key] = true
        end
      end
    end
  end
  return { total = total, reached = reached, duplicates = duplicates,
           categories = state.categoryKeys }
end

function SettingsMenu.export()
  return {
    screenIds = SCREEN,
    categories = CATEGORY_ORDER,
    coverage = SettingsMenu.coverage,
    integratedSpriteMenu = function() return state.sprite:integrated() end,
    activePack = function() return state.sprite:activePack() end,
    ownership = function() return state.sprite:ownership() end,
    open = SettingsMenu.open,
    schema = function() return state.schema end,
    -- The unified MOD SETTINGS screen composes this renderer's rows into its
    -- own categories, so the row builders are public: descriptors by schema
    -- key, the render-pipeline ladder rows, and the integrated sprite-pack
    -- rows, plus the sub-screen ids it links to (Crystal, sprite pack).
    rowsFor = function(keys, skip) return appendKeyRows({}, keys, skip) end,
    pipelineRow = pipelineRow,
    openRow = openRow,
    spriteMenu = function() return state.sprite end,
  }
end

return SettingsMenu
