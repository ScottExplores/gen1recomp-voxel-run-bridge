-- Compact categorized controls for every Scott's Tweaks option. These are
-- the same values exposed by the Mod Manager schema in main.lua.

local SCREEN_MAIN = "ScottsTweaksOptions"
local SCREEN_INVENTORY = "ScottsTweaksInventoryOptions"
local SCREEN_TRAINERS = "ScottsTweaksTrainerOptions"
local SCREEN_MOVEMENT = "ScottsTweaksMovementOptions"
local SCREEN_FIELD = "ScottsTweaksFieldOptions"
local SCREEN_DISPLAY = "ScottsTweaksDisplayOptions"
local SCREEN_GEN2 = "ScottsTweaksGen2Options"

return function(mod, context)
  local OptionScreen, screenErr = context.loadOwn("modules/option_screen.lua")
  if type(OptionScreen) ~= "table" or type(OptionScreen.new) ~= "function" then
    error(screenErr or "option screen unavailable", 0)
  end
  local settings = context.settings

  local function push(game, id)
    return mod.ui.push(game, id)
  end
  local function set(game, key, value)
    local ok, err = settings:set(game, key, value)
    return ok, err
  end
  local function toggle(key, label, unavailable)
    return {
      id = mod.id .. ":" .. key,
      label = label,
      value = function()
        local reason = unavailable and unavailable()
        if reason then return reason end
        return settings:get(key) == true and "ON" or "OFF"
      end,
      step = function(game)
        if unavailable and unavailable() then return false end
        return set(game, key, settings:get(key) ~= true)
      end,
    }
  end
  local function choice(key, label, choices, unavailable)
    return {
      id = mod.id .. ":" .. key,
      label = label,
      value = function()
        local reason = unavailable and unavailable()
        if reason then return reason end
        local current = settings:get(key)
        for _, row in ipairs(choices) do
          if row[2] == current then return row[1] end
        end
        return tostring(current or "?")
      end,
      step = function(game, direction)
        if unavailable and unavailable() then return false end
        local current, index = settings:get(key), 1
        for i, row in ipairs(choices) do
          if row[2] == current then index = i break end
        end
        direction = direction and direction < 0 and -1 or 1
        index = ((index - 1 + direction) % #choices) + 1
        return set(game, key, choices[index][2])
      end,
    }
  end
  local function category(label, id)
    return {
      label = label,
      value = function() return "OPEN" end,
      activate = function(game) push(game, id) end,
    }
  end
  local function delegated(exportKey)
    return function()
      local feature = mod.exports[exportKey]
      if type(feature) == "table" and feature.delegated then
        if feature.provider == "random_starters" then return "RANDOM MOD" end
        return "OTHER MOD"
      end
    end
  end

  local trainerUnavailable = delegated("trainerForfeit")
  local oakUnavailable = delegated("oakSpareStarter")
  local runningUnavailable = delegated("running")
  local function dualUnavailable()
    local dual = mod.exports.thorDualScreen
    if type(dual) ~= "table" then return nil end
    if dual.delegated == true then return "OTHER MOD" end
    if type(dual.getStatus) == "function" then
      local ok, status = pcall(dual.getStatus)
      if not ok then ok, status = pcall(dual.getStatus, dual) end
      if ok and type(status) == "table" and status.delegated == true then
        return "OTHER MOD"
      end
    end
  end
  local function gen2Unavailable()
    local controller = context.gen2Assets
    if type(controller) ~= "table" or type(controller.status) ~= "function" then
      return "NEEDS 0.1.96"
    end
    local hasApi = pcall(require, "src.import.RomManifest")
    if not hasApi then return "NEEDS 0.1.96" end
    local ok, status = pcall(controller.status, controller)
    if not ok or type(status) ~= "table" then return "UNAVAILABLE" end
    if status.attempted ~= true and type(controller.load) == "function" then
      pcall(controller.load, controller)
      ok, status = pcall(controller.status, controller)
      if not ok or type(status) ~= "table" then return "UNAVAILABLE" end
    end
    if status.ready == true then return nil end
    if status.reason == "unsupported_engine"
        or status.reason == "gen2_import_api_unavailable" then
      return "NEEDS 0.1.96"
    end
    if status.reason == "optional_import_missing" then
      return "IMPORT GOLD"
    end
    if status.reason == "optional_import_invalid_size"
        or status.reason == "optional_import_invalid_md5" then
      return "WRONG GOLD ROM"
    end
    return "UNAVAILABLE"
  end
  local speedChoices = {
    { "1.25X", 1.25 }, { "1.5X", 1.5 }, { "2X", 2 },
  }
  local bobChoices = {
    { "0.25X", 0.25 }, { "0.5X", 0.5 },
    { "0.75X", 0.75 }, { "1X", 1 },
  }
  local expChoices = {
    { "VANILLA", "vanilla" }, { "LEAD ONLY", "lead" },
    { "PARTY ALL", "party" }, { "EXP.SHARE", "share" },
  }
  local growthChoices = { { "OFF", "off" }, { "GENTLE", "gentle" } }

  local function mainRows()
    return {
      category("BAG & EXPERIENCE", SCREEN_INVENTORY),
      category("TRAINERS & OAK", SCREEN_TRAINERS),
      category("RUNNING", SCREEN_MOVEMENT),
      category("FIELD MOVES", SCREEN_FIELD),
      category("DISPLAY & THOR", SCREEN_DISPLAY),
      category("GEN 2 INTERFACE", SCREEN_GEN2),
    }
  end
  local function inventoryRows()
    return {
      toggle("bag_pockets", "BAG POCKETS"),
      choice("experience_mode", "EXP. MODE", expChoices),
    }
  end
  local function trainerRows()
    return {
      toggle("trainer_forfeit_enabled", "PAID FORFEIT", trainerUnavailable),
      toggle("trainer_rematches", "REMATCHES", trainerUnavailable),
      toggle("trainer_adaptive_dialogue", "JOURNEY DIALOGUE",
        trainerUnavailable),
      choice("trainer_growth", "TRAINER GROWTH", growthChoices,
        trainerUnavailable),
      toggle("oak_spare_starter", "OAK SPARE STARTER", oakUnavailable),
    }
  end
  local function movementRows()
    return {
      toggle("running_enabled", "B-BUTTON RUN", runningUnavailable),
      choice("running_speed", "RUN SPEED", speedChoices, runningUnavailable),
      toggle("running_view_bob", "RUN HEAD BOB", runningUnavailable),
      choice("running_bob_intensity", "BOB INTENSITY", bobChoices,
        runningUnavailable),
    }
  end
  local function fieldRows()
    return {
      toggle("hm_without_badges", "BADGE-FREE HMS"),
      toggle("free_fly_without_badges", "FREE FLY NOW"),
    }
  end
  local function displayRows()
    return {
      toggle("free_fly_cockpit", "FLY COCKPIT"),
      toggle("gapped_land", "GAPPED LAND"),
      toggle("dual_screen", "THOR SECOND SCREEN", dualUnavailable),
    }
  end
  local function gen2Rows()
    return {
      toggle("gen2_menus", "GEN 2 INTERFACE", gen2Unavailable),
    }
  end

  local function screen(title, rows)
    return { new = function(game)
      return OptionScreen.new(game, { title = title, rows = rows })
    end }
  end
  mod.content.screens:register(SCREEN_MAIN,
    screen("SCOTT'S TWEAKS", mainRows))
  mod.content.screens:register(SCREEN_INVENTORY,
    screen("BAG & EXPERIENCE", inventoryRows))
  mod.content.screens:register(SCREEN_TRAINERS,
    screen("TRAINERS & OAK", trainerRows))
  mod.content.screens:register(SCREEN_MOVEMENT,
    screen("RUNNING", movementRows))
  mod.content.screens:register(SCREEN_FIELD,
    screen("FIELD MOVES", fieldRows))
  mod.content.screens:register(SCREEN_DISPLAY,
    screen("DISPLAY & THOR", displayRows))
  mod.content.screens:register(SCREEN_GEN2,
    screen("GEN 2 INTERFACE", gen2Rows))

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" then return out end
    for _, item in ipairs(out) do
      if type(item) == "table" and item.id == "scotts_tweaks.open" then
        return out
      end
    end
    return mod.ui.insertBefore(out, "MODS", {
      id = "scotts_tweaks.open",
      label = "SCOTT'S TWEAKS",
      onSelect = function() push(game, SCREEN_MAIN) end,
    })
  -- Stay inside Modern UI's default-priority grouping wrapper. The separate
  -- Gold Pokegear hook deliberately runs outside it so Pokegear remains a
  -- normal root-menu feature while Scott's settings live under MOD MENUS.
  end, -100)

  local api = {
    installed = true,
    screenIds = {
      main = SCREEN_MAIN, inventory = SCREEN_INVENTORY,
      trainers = SCREEN_TRAINERS, movement = SCREEN_MOVEMENT,
      field = SCREEN_FIELD, display = SCREEN_DISPLAY, gen2 = SCREEN_GEN2,
    },
  }
  mod.exports.tweaksMenu = api
  return api
end
