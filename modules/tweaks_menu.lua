-- Compact categorized controls for every Scott's Tweaks option. These are
-- the same values exposed by the Mod Manager schema in main.lua.

local SCREEN_MAIN = "ScottsTweaksOptions"
local SCREEN_INVENTORY = "ScottsTweaksInventoryOptions"
local SCREEN_TRAINERS = "ScottsTweaksTrainerOptions"
local SCREEN_MOVEMENT = "ScottsTweaksMovementOptions"
local SCREEN_FIELD = "ScottsTweaksFieldOptions"
local SCREEN_DISPLAY = "ScottsTweaksDisplayOptions"
local SCREEN_GEN2 = "ScottsTweaksPokegearOptions"
local SCREEN_MODS = "ScottsTweaksModsOptions"

-- Every bundled mod keeps its own settings screen. Rather than restate their
-- rows here -- which would drift the moment one of them is updated -- the MODS
-- page links to each, so one entry point reaches all of them.
local MOD_SCREENS = {
  { label = "BATTLE ART",   screen = "BattleArtSettingsOptions" },
  { label = "WILDS OF KANTO", screen = "overworld_wild_spawns:wilds_menu" },
  { label = "FOLLOWERS",    screen = "overworld_wild_spawns:followers_ex_menu" },
  { label = "CRYSTAL SPRITES", screen = "CrystalSpriteOptions" },
}

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
  -- These must stay in step with the option definitions in main.lua; the menu
  -- keeps its own copies so it can label them.
  local speedChoices = {
    { "1.25X", 1.25 }, { "1.5X", 1.5 }, { "2X", 2 },
    { "2.5X", 2.5 }, { "3X", 3 }, { "4X", 4 },
  }
  local bobChoices = {
    { "0.1X", 0.1 }, { "0.15X", 0.15 }, { "0.25X", 0.25 },
    { "0.5X", 0.5 }, { "0.75X", 0.75 }, { "1X", 1 },
  }
  local expChoices = {
    { "VANILLA", "vanilla" }, { "LEAD ONLY", "lead" },
    { "PARTY ALL", "party" }, { "EXP.SHARE", "share" },
  }
  local growthChoices = { { "OFF", "off" }, { "GENTLE", "gentle" } }

  -- SIMPLE is the default and keeps this page short. ALL adds the pages that
  -- are only visited to tune something. Hiding a page never changes a value,
  -- so switching back finds every setting as it was left.
  local function simpleMode()
    local ok, value = pcall(mod.options.get, mod.options, "simple_menu")
    if ok and value ~= nil then return value and true or false end
    return true
  end

  local function modsRows()
    local rows = {}
    for _, entry in ipairs(MOD_SCREENS) do
      rows[#rows + 1] = {
        label = entry.label,
        value = function() return "OPEN" end,
        activate = function(game) pcall(push, game, entry.screen) end,
      }
    end
    return rows
  end

  local function mainRows()
    local rows = {
      category("MODS", SCREEN_MODS),
      category("BAG & EXPERIENCE", SCREEN_INVENTORY),
      category("TRAINERS & OAK", SCREEN_TRAINERS),
      category("RUNNING", SCREEN_MOVEMENT),
      category("PACK + POKéGEAR", SCREEN_GEN2),
    }
    if not simpleMode() then
      rows[#rows + 1] = category("FIELD MOVES", SCREEN_FIELD)
      rows[#rows + 1] = category("DISPLAY & THOR", SCREEN_DISPLAY)
    end
    rows[#rows + 1] = {
      label = "SETTINGS",
      value = function() return simpleMode() and "SIMPLE" or "ALL" end,
      activate = function(game) return set(game, "simple_menu", not simpleMode()) end,
      step = function(game) return set(game, "simple_menu", not simpleMode()) end,
    }
    return rows
  end
  local function inventoryRows()
    local rows = {}
    -- PACK always needs Scott's Red-inventory pocket projection. Hide the
    -- classic-only preference while PACK + POKeGEAR owns that presentation,
    -- without overwriting the saved preference used when the feature is off.
    if settings:get("gen2_menus") ~= true then
      rows[#rows + 1] = toggle("bag_pockets", "CLASSIC BAG POCKETS")
    end
    rows[#rows + 1] = choice("experience_mode", "EXP. MODE", expChoices)
    return rows
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
      toggle("gen2_menus", "PACK + POKéGEAR"),
    }
  end

  local function screen(title, rows)
    return { new = function(game)
      return OptionScreen.new(game, { title = title, rows = rows })
    end }
  end
  mod.content.screens:register(SCREEN_MAIN,
    screen("SCOTT'S TWEAKS", mainRows))
  mod.content.screens:register(SCREEN_MODS,
    screen("MODS", modsRows))
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
    screen("PACK + POKéGEAR", gen2Rows))

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
  -- Pokegear's hook deliberately runs outside it so Pokegear remains a
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
