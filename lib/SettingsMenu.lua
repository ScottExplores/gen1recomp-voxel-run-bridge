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
  advanced = "BattleArtAdvancedOptions",
  crystal = "BattleArtCrystalOptions",
  pack = "BattleArtSpritePackOptions",
}

local CATEGORY_ORDER = {
  { id = "quick", label = "QUICK" },
  { id = "views", label = "VIEWS & CAMERA" },
  { id = "world", label = "WORLD" },
  { id = "battles", label = "BATTLES" },
  { id = "sprites", label = "SPRITES & TRAINERS" },
  { id = "advanced", label = "ADVANCED" },
}

-- Every persistent schema key has one canonical category. Quick is a small
-- set of shortcuts and may intentionally repeat frequent rows. Unknown future
-- keys are appended to Advanced at install time instead of becoming orphaned.
local CATEGORY_KEYS = {
  views = {
    "grid", "curve", "headbob", "fpfov", "dof", "jump",
    "jumpkey", "jumppad", "third",
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
  sprites = {
    "battleArt", "duplicateFix", "opponentTrainerSource",
    "playerTrainerSource", "trainerArtSet", "playerArtSet",
    "playerAnimatedSet", "frontAnimatedSet", "backAnimatedSet",
    "playerView", "frontFlip", "backPlacement",
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

local function writeOption(game, row, value)
  if not (game and game.save and type(game.save.options) == "table") then
    return false
  end
  local options = game.save.options
  options.modOptions = options.modOptions or {}
  options.modOptions[mod.id] = options.modOptions[mod.id] or {}
  options.modOptions[mod.id][row.key] = value

  local loader = game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
    loader.modOptions[mod.id][row.key] = value
  end
  if game.writeOptions then pcall(game.writeOptions, game) end
  if loader and loader.events then
    loader.events:emit("mod.options_changed",
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

local function mainRows()
  local out = {}
  for _, category in ipairs(CATEGORY_ORDER) do
    out[#out + 1] = openRow(category.label, "OPEN", SCREEN[category.id])
  end
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
  else
    out[#out + 1] = openRow("SPRITE MENU", "EXTERNAL",
      "ScottsSpriteOptions")
  end
  return appendKeyRows(out, state.categoryKeys.sprites, skip)
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
    screen("WORLD", worldRows))
  mod.content.screens:register(SCREEN.battles,
    screen("BATTLES", battleRows))
  mod.content.screens:register(SCREEN.sprites,
    screen("SPRITES & TRAINERS", spriteRows))
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
      if item.id == "scotts_sprite_hub.open" or item.label == "BATTLE ART" then
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
    label = "BATTLE ART",
    value = function() return "OPEN" end,
    activate = function(game) SettingsMenu.open(game) end,
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
  }
end

return SettingsMenu
