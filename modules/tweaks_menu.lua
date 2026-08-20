-- MOD SETTINGS: the one menu for the whole fused build.
--
-- Every setting in the bundle -- Scott's Tweaks' own, the fused Battle Art
-- renderer's, and each vendored community mod's -- appears in exactly one of
-- seven categories. Three row sources feed it:
--   * Tweaks' own options (context.settings),
--   * Battle Art's ModSetting descriptors (mod.exports.settingsMenu.rowsFor),
--   * bundled mods' schemas (mod.exports.vendorHost, stored per-vendor and
--     written through vendorHost:writeOption so each mod hears its change
--     under its own id and reacts live, exactly as it did standalone).
--
-- BASIC (default) shows the everyday rows; ALL shows everything. Hiding a
-- row never changes its value. A bundled mod that stood down for a standalone
-- copy shows OTHER MOD on its rows instead of silently vanishing.

local SCREEN_MAIN = "ScottsTweaksOptions"
local SCREEN_GRAPHICS = "ScottsTweaksGraphicsOptions"
local SCREEN_WORLD = "ScottsTweaksWorldOptions"
local SCREEN_SPRITES = "ScottsTweaksSpritesOptions"
local SCREEN_BATTLES = "ScottsTweaksBattlesOptions"
local SCREEN_WILDS = "ScottsTweaksWildsOptions"
local SCREEN_MOVEMENT = "ScottsTweaksMovementOptions"
local SCREEN_SYSTEM = "ScottsTweaksSystemOptions"

-- Historical screen ids stay live with their historical logical rows. They
-- are no longer linked from the root, but older UI routers and hot-reloaded
-- screens do not land in a category whose contents changed underneath them.
local SCREEN_INVENTORY_OLD = "ScottsTweaksInventoryOptions"
local SCREEN_TRAINERS_OLD = "ScottsTweaksTrainerOptions"
local SCREEN_FIELD_OLD = "ScottsTweaksFieldOptions"
local SCREEN_DISPLAY_OLD = "ScottsTweaksDisplayOptions"
local SCREEN_GEN2_OLD = "ScottsTweaksPokegearOptions"
local SCREEN_MODS_OLD = "ScottsTweaksModsOptions"

local WILDS = "overworld_wild_spawns"
local CRYSTAL = "crystal_animated_sprites_with_shiny_visuals"
local FREE_FLY = "free_fly"
local CHOOSE_LEAD = "choose_lead"
local DYNAMIC = "Dynamic_Scaling"
local ICONS = "unique_menu_icons"
local CATCHABLE = "all_pokemon_catchable_151_mod"

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
  local function simpleMode()
    local ok, value = pcall(mod.options.get, mod.options, "simple_menu")
    if ok and value ~= nil then return value and true or false end
    return true
  end

  -- ------- Tweaks' own rows

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

  -- ------- Battle Art rows (absent when the fused renderer stood down)

  local function sm()
    local exported = mod.exports.settingsMenu
    return type(exported) == "table" and exported or nil
  end
  local function baRows(keys)
    local menu = sm()
    if not (menu and type(menu.rowsFor) == "function") then return {} end
    local ok, rows = pcall(menu.rowsFor, keys)
    return ok and type(rows) == "table" and rows or {}
  end
  local function baRow(key, label)
    local rows = baRows({ key })
    local row = rows[1]
    if row and label then row.label = label end
    return row
  end
  local function baPipelineRow(name, label)
    local menu = sm()
    if not (menu and type(menu.pipelineRow) == "function") then return nil end
    local ok, row = pcall(menu.pipelineRow, name, label)
    return ok and row or nil
  end
  local function baScreenId(name)
    local menu = sm()
    return menu and menu.screenIds and menu.screenIds[name] or nil
  end

  -- ------- bundled-mod rows

  local host = mod.exports.vendorHost
  local function vendorState(id)
    if not host then return "absent" end
    if host.loaded and host.loaded[id] then return "bundled" end
    local why = host.failures and host.failures[id]
    if why == "standalone copy is installed" then return "standalone" end
    return "absent"
  end
  local function vendorSchemaRow(vendorId, key)
    if not (host and host.schemas) then return nil end
    for _, row in ipairs(host.schemas[vendorId] or {}) do
      if row.key == key then return row end
    end
    return nil
  end
  -- One row for one bundled mod's option: reads through the vendor bucket,
  -- writes through vendorHost:writeOption so the change is announced under
  -- the mod's own id and applies live. When a standalone copy owns the mod,
  -- the row reports OTHER MOD -- adjust it in that mod's own menu instead.
  local function vrow(vendorId, key, labelOverride, simple, valueLabels)
    local schema = vendorSchemaRow(vendorId, key)
    if not schema then return nil end
    local state = vendorState(vendorId)
    if state == "absent" then return nil end
    local label = labelOverride or schema.label or key
    local row = { id = vendorId .. ":" .. key, label = label, simple = simple }
    if state == "standalone" then
      row.value = function() return "OTHER MOD" end
      row.step = function() return false end
      return row
    end
    if schema.type == "toggle" then
      row.value = function()
        return host:readOption(vendorId, key) == true and "ON" or "OFF"
      end
      row.step = function(game)
        return host:writeOption(game, vendorId, key,
          host:readOption(vendorId, key) ~= true)
      end
    elseif schema.type == "choice" then
      row.value = function()
        local current = host:readOption(vendorId, key)
        if valueLabels and valueLabels[current] then
          return tostring(valueLabels[current])
        end
        for _, c in ipairs(schema.choices or {}) do
          if c[2] == current then return tostring(c[1]) end
        end
        return tostring(current or "?")
      end
      row.step = function(game, direction)
        local choices = schema.choices or {}
        if #choices == 0 then return false end
        local current, index = host:readOption(vendorId, key), 1
        for i, c in ipairs(choices) do
          if c[2] == current then index = i break end
        end
        direction = direction and direction < 0 and -1 or 1
        index = ((index - 1 + direction) % #choices) + 1
        return host:writeOption(game, vendorId, key, choices[index][2])
      end
    elseif schema.type == "number" then
      row.value = function()
        return tostring(host:readOption(vendorId, key))
      end
      row.step = function(game, direction)
        local current = tonumber(host:readOption(vendorId, key)) or 0
        local stepBy = tonumber(schema.step) or 1
        local next = current + (direction and direction < 0 and -stepBy or stepBy)
        if schema.min then next = math.max(schema.min, next) end
        if schema.max then next = math.min(schema.max, next) end
        return host:writeOption(game, vendorId, key, next)
      end
    else
      return nil
    end
    return row
  end
  -- Every schema key of a bundled mod that the curated lists did not place,
  -- appended to its home category's ALL view so nothing is orphaned.
  local function vendorRest(vendorId, curated)
    local out = {}
    if not (host and host.schemas) then return out end
    for _, schema in ipairs(host.schemas[vendorId] or {}) do
      if not curated[schema.key] then
        local row = vrow(vendorId, schema.key)
        if row then out[#out + 1] = row end
      end
    end
    return out
  end
  local function openScreen(label, screenId, simple)
    return {
      label = label,
      value = function() return "OPEN" end,
      activate = function(game) pcall(push, game, screenId) end,
      simple = simple,
    }
  end

  local ENCOUNTER_ORDER = { "visible", "both", "classic", "off" }
  local ENCOUNTER_LABEL = {
    visible = "VISIBLE", both = "BOTH", classic = "CLASSIC", off = "OFF",
  }
  local function encounterMode()
    if not host or vendorState(WILDS) ~= "bundled" then return nil end
    if host:readOption(WILDS, "enable_hidden") == true then return "custom" end
    local visible = host:readOption(WILDS, "enabled") == true
    local classic = host:readOption(WILDS, "random_encounters") == true
    if visible and classic then return "both" end
    if visible then return "visible" end
    if classic then return "classic" end
    return "off"
  end
  local function encounterRow()
    if not vendorSchemaRow(WILDS, "enabled")
        or not vendorSchemaRow(WILDS, "random_encounters")
        or not vendorSchemaRow(WILDS, "enable_hidden")
        or vendorState(WILDS) == "absent" then
      return nil
    end
    if vendorState(WILDS) == "standalone" then
      return { label = "ENCOUNTER MODE", simple = true,
        value = function() return "OTHER MOD" end,
        step = function() return false end }
    end
    return {
      id = WILDS .. ":encounter_mode",
      -- Synthetic row replaces the two raw switches without removing either
      -- canonical option from persistence or Mod Manager.
      schemaKeys = {
        WILDS .. ":enabled", WILDS .. ":random_encounters",
      },
      label = "ENCOUNTER MODE",
      simple = true,
      value = function()
        local mode = encounterMode()
        return mode == "custom" and "CUSTOM" or (ENCOUNTER_LABEL[mode] or "?")
      end,
      step = function(game, direction)
        direction = direction and direction < 0 and -1 or 1
        local current, index = encounterMode(), nil
        for i, mode in ipairs(ENCOUNTER_ORDER) do
          if mode == current then index = i break end
        end
        if not index then index = direction < 0 and 1 or 0 end
        index = ((index - 1 + direction) % #ENCOUNTER_ORDER) + 1
        local wanted = ENCOUNTER_ORDER[index]
        local visible = wanted == "visible" or wanted == "both"
        local classic = wanted == "classic" or wanted == "both"
        local okHidden = host:writeOption(game, WILDS, "enable_hidden", false)
        local okClassic = host:writeOption(
          game, WILDS, "random_encounters", classic)
        local okVisible = host:writeOption(game, WILDS, "enabled", visible)
        return okHidden and okClassic and okVisible
      end,
    }
  end

  -- ------- category assembly

  local function mark(row, simple)
    if row then row.simple = simple end
    return row
  end
  local function add(rows, row)
    if row then rows[#rows + 1] = row end
    return rows
  end
  local function addAll(rows, more, simple)
    for _, row in ipairs(more or {}) do
      if simple ~= nil and row.simple == nil then row.simple = simple end
      rows[#rows + 1] = row
    end
    return rows
  end
  -- In SIMPLE mode only rows marked simple survive; ALL shows everything.
  local function filtered(build)
    return function()
      local rows = build()
      if not simpleMode() then return rows end
      local out = {}
      for _, row in ipairs(rows) do
        if row.simple then out[#out + 1] = row end
      end
      return out
    end
  end

  local function graphicsRows()
    local rows = {}
    add(rows, mark(baPipelineRow("voxel", "VIEW"), true))
    add(rows, mark(baPipelineRow("tiltshift", "TILT SHIFT"), false))
    addAll(rows, baRows({ "aa" }), true)
    addAll(rows, baRows({ "renderDistance" }), true)
    addAll(rows, baRows({ "fpfov", "dof", "grid", "curve", "fastchunks",
      "third" }), false)
    return rows
  end

  local function worldRows()
    local rows = {}
    addAll(rows, baRows({ "worldFill", "daytime", "water",
      "shadowQuality" }), true)
    add(rows, mark(toggle("gapped_land", "GAPPED LAND"), false))
    add(rows, mark(baPipelineRow("lavveil", "LAVENDER VEIL"), false))
    addAll(rows, baRows({
      -- interiors
      "ceiling", "headroom", "cutaway", "rails", "spill", "fittings",
      "windows", "ceildetail", "doorstep",
      -- terrain and horizon
      "rock", "apron", "talltrees", "peaks", "bouldertrees", "grass",
      "backdrop", "horizonart",
      -- caves
      "pools", "sconces", "bats",
      -- weather and sky
      "rain", "umbrellas", "puddles", "lightning", "lights", "shafts",
      "canopy", "vines", "fog", "clouds", "stars", "wind",
      -- life
      "particles", "birds", "aircraft", "rainbows", "insects", "groundflock",
      -- audio
      "ambience", "grasssfx", "stepsfx", "doorsfx",
    }), false)
    return rows
  end

  local function spritesRows()
    local rows = {}
    local menu = sm()
    local sprite = menu and type(menu.spriteMenu) == "function"
      and select(2, pcall(menu.spriteMenu)) or nil
    local integrated = sprite and sprite.integrated and sprite:integrated()
    if integrated then
      add(rows, {
        label = "ART PACK", simple = true,
        value = function() return sprite:packLabel() end,
        activate = function(game)
          local id = baScreenId("pack")
          if id then pcall(push, game, id) end
        end,
      })
      add(rows, {
        id = mod.id .. ":playerView",
        label = "PLAYER BATTLE VIEW", simple = true,
        value = function() return sprite:playerViewLabel() end,
        step = function(game, direction)
          return sprite:cyclePlayerView(game, direction)
        end,
      })
      add(rows, {
        id = mod.id .. ":frontFlip",
        label = "MY POKEMON FLIP", simple = false,
        value = function() return sprite:playerFrontFlipLabel() end,
        step = function(game)
          return sprite:setPlayerFrontFlip(game, not sprite:playerFrontFlip())
        end,
      })
      add(rows, {
        label = "TRAINER ART SOURCE", simple = true,
        value = function(game) return sprite:trainerLabel(game) end,
        step = function(game, direction)
          return sprite:cycleTrainerSource(game, direction)
        end,
      })
      add(rows, {
        label = "CRYSTAL OPTIONS", simple = false,
        value = function()
          if not sprite:crystalHandle() then return "NOT LOADED" end
          return sprite:crystalReady() and "OPEN" or "UPDATE CRYSTAL"
        end,
        activate = function(game)
          local id = baScreenId("crystal")
          if id and sprite:crystalReady() then pcall(push, game, id) end
        end,
      })
    end
    add(rows, vrow(ICONS, "icon_color_mode", "MENU ICONS", true, {
      original = "ORIGINAL", gbc_red = "GBC RED", unique_colors = "UNIQUE",
    }))
    addAll(rows, baRows({ "battleArt", "duplicateFix", "opponentTrainerSource",
      "frontAnimatedSet", "backAnimatedSet", "playerTrainerSource",
      "playerArtSet", "playerAnimatedSet", "backPlacement" }), false)
    add(rows, mark(baRow("trainerArtSet", "TRAINER ART SET"), false))
    if not integrated then
      addAll(rows, baRows({ "playerView", "frontFlip" }), false)
    end
    addAll(rows, vendorRest(ICONS, { icon_color_mode = true }), false)
    return rows
  end

  local function battlesRows()
    local rows = {}
    addAll(rows, baRows({ "battles", "letsgo" }), true)
    add(rows, mark(choice("experience_mode", "EXP. MODE", expChoices), true))
    addAll(rows, baRows({ "hudScale", "spriteLight", "hudColor", "arenaFill",
      "backdropOffset", "bossBg", "textboxFill" }), false)
    add(rows, mark(toggle("trainer_forfeit_enabled", "PAID FORFEIT",
      trainerUnavailable), false))
    add(rows, mark(toggle("trainer_rematches", "REMATCHES",
      trainerUnavailable), false))
    add(rows, mark(toggle("trainer_adaptive_dialogue", "JOURNEY DIALOGUE",
      trainerUnavailable), false))
    add(rows, mark(choice("trainer_growth", "TRAINER GROWTH", growthChoices,
      trainerUnavailable), false))
    add(rows, mark(toggle("oak_spare_starter", "OAK SPARE STARTER",
      oakUnavailable), false))
    local choose = { enabled = true, when = true }
    add(rows, vrow(CHOOSE_LEAD, "enabled", "CHOOSE LEAD", true))
    add(rows, vrow(CHOOSE_LEAD, "when", "ASK BEFORE", false))
    addAll(rows, vendorRest(CHOOSE_LEAD, choose), false)
    local dynamic = { difficulty = true, randomize = true }
    add(rows, vrow(DYNAMIC, "difficulty", "DIFFICULTY", true, {
      off = "OFF", normal = "NORMAL +2", medium = "MEDIUM +5",
      hard = "HARD +10",
    }))
    add(rows, vrow(DYNAMIC, "randomize", "TRAINER TEAMS", false, {
      off = "VANILLA", chaos = "CHAOS", themed = "THEMED",
    }))
    addAll(rows, vendorRest(DYNAMIC, dynamic), false)
    addAll(rows, vendorRest(CATCHABLE, {}), false)
    return rows
  end

  local function wildsRows()
    local rows = {}
    local curated = {}
    local function place(key, label, simple)
      curated[key] = true
      add(rows, vrow(WILDS, key, label, simple))
    end
    curated.enabled = true
    curated.random_encounters = true
    add(rows, encounterRow())
    place("spawn_density", "SPAWN AMOUNT", true)
    place("follower_count", "FOLLOWERS", true)
    curated.sprite_style = true
    add(rows, vrow(WILDS, "sprite_style", "SPRITE STYLE", true, {
      followers = "FOLLOWERS/GSC", pokemmo = "HGSS", pokedex = "POKEDEX",
    }))
    place("pokemon_grass_render_mode", "GRASS VIEW", true)
    place("overworld_catching", "OVERWORLD CATCH", true)
    place("town_pokemon", nil, false)
    place("water_spawns", nil, false)
    place("cave_spawns", nil, false)
    place("sprite_fade", nil, false)
    place("wild_silhouettes", nil, false)
    place("follow_control", nil, false)
    place("trainer_trail", nil, false)
    place("enable_hidden", "HIDDEN MONS", false)
    if vendorState(WILDS) == "bundled" then
      add(rows, openScreen("TEST SPAWN", "OverworldSpawnPreview", false))
    end
    addAll(rows, vendorRest(WILDS, curated), false)
    return rows
  end

  local function movementRows()
    local rows = {}
    add(rows, mark(toggle("running_enabled", "B-BUTTON RUN",
      runningUnavailable), true))
    add(rows, mark(choice("running_speed", "RUN SPEED", speedChoices,
      runningUnavailable), true))
    add(rows, mark(toggle("running_view_bob", "RUN HEAD BOB",
      runningUnavailable), true))
    add(rows, mark(choice("running_bob_intensity", "BOB INTENSITY", bobChoices,
      runningUnavailable), true))
    add(rows, mark(toggle("hm_without_badges", "BADGE-FREE HMS"), false))
    local freeFlyNow = mark(
      toggle("free_fly_without_badges", "FREE FLY NOW"), true)
    if freeFlyNow then
      -- The host adapter mirrors this preference into Free Fly's inverse
      -- BADGE CHECKS key, so presenting both controls would make them fight.
      freeFlyNow.schemaKeys = { FREE_FLY .. ":badges" }
    end
    add(rows, freeFlyNow)
    add(rows, mark(toggle("free_fly_cockpit", "FLY COCKPIT"), false))
    addAll(rows, baRows({ "jump", "jumpkey", "jumppad" }), false)
    add(rows, mark(baRow("headbob", "JUMP CAMERA BOB"), false))
    -- FREE FLY NOW is the single badge-bypass control; exposing Free Fly's
    -- inverse BADGE CHECKS row beside it would make two switches fight.
    addAll(rows, vendorRest(FREE_FLY, { badges = true }), false)
    return rows
  end

  local function systemRows()
    local rows = {}
    -- PACK always needs Scott's Red-inventory pocket projection. Hide the
    -- classic-only preference while PACK + POKeGEAR owns that presentation,
    -- without overwriting the saved preference used when the feature is off.
    if settings:get("gen2_menus") ~= true then
      add(rows, mark(toggle("bag_pockets", "CLASSIC BAG POCKETS"), true))
    end
    add(rows, mark(toggle("gen2_menus", "PACK + POKéGEAR"), true))
    add(rows, mark(toggle("dual_screen", "THOR SECOND SCREEN",
      dualUnavailable), true))
    addAll(rows, baRows({ "debug" }), false)
    return rows
  end

  local CATEGORIES = {
    { label = "VIEW & CAMERA", screen = SCREEN_GRAPHICS, rows = graphicsRows },
    { label = "WORLD & WEATHER", screen = SCREEN_WORLD, rows = worldRows },
    { label = "POKEMON ART", screen = SCREEN_SPRITES, rows = spritesRows },
    { label = "BATTLES", screen = SCREEN_BATTLES, rows = battlesRows },
    { label = "WILD & FOLLOWERS", screen = SCREEN_WILDS, rows = wildsRows },
    { label = "MOVEMENT", screen = SCREEN_MOVEMENT, rows = movementRows },
    { label = "MENUS & DEVICE", screen = SCREEN_SYSTEM, rows = systemRows },
  }

  local function mainRows()
    local rows = {}
    -- A partial install must announce itself instead of failing quietly: the
    -- engine's installer can be interrupted mid-copy on a handheld and the
    -- half-written tree still loads. See modules/integrity.lua.
    local integrity = mod.exports.integrity
    if type(integrity) == "table" and integrity.ok == false then
      rows[#rows + 1] = {
        label = "!! PARTIAL INSTALL",
        value = function()
          return "REINSTALL (" .. tostring(integrity.missingCount or "?")
            .. " MISSING)"
        end,
        step = function() return false end,
      }
    end
    for _, category in ipairs(CATEGORIES) do
      rows[#rows + 1] = {
        label = category.label,
        value = function() return "OPEN" end,
        activate = function(game) push(game, category.screen) end,
      }
    end
    rows[#rows + 1] = {
      id = mod.id .. ":simple_menu",
      label = "OPTIONS SHOWN",
      value = function() return simpleMode() and "BASIC" or "ALL" end,
      activate = function(game) return set(game, "simple_menu", not simpleMode()) end,
      step = function(game) return set(game, "simple_menu", not simpleMode()) end,
    }
    return rows
  end

  local function screen(title, rows)
    return { new = function(game)
      return OptionScreen.new(game, { title = title, rows = rows })
    end }
  end
  mod.content.screens:register(SCREEN_MAIN,
    screen("MOD SETTINGS", mainRows))
  for _, category in ipairs(CATEGORIES) do
    mod.content.screens:register(category.screen,
      screen(category.label, filtered(category.rows)))
  end

  -- Old ids remain valid for external UI routers and hot reloads. These are
  -- compatibility views only; the root no longer links them, so the everyday
  -- path stays the seven-category layout above.
  local function legacyInventoryRows()
    local rows = {}
    if settings:get("gen2_menus") ~= true then
      add(rows, toggle("bag_pockets", "CLASSIC BAG POCKETS"))
    end
    add(rows, choice("experience_mode", "EXP. MODE", expChoices))
    return rows
  end
  local function legacyTrainerRows()
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
  local function legacyFieldRows()
    return {
      toggle("hm_without_badges", "BADGE-FREE HMS"),
      toggle("free_fly_without_badges", "FREE FLY NOW"),
    }
  end
  local function legacyDisplayRows()
    return {
      toggle("free_fly_cockpit", "FLY COCKPIT"),
      toggle("gapped_land", "GAPPED LAND"),
      toggle("dual_screen", "THOR SECOND SCREEN", dualUnavailable),
    }
  end
  mod.content.screens:register(SCREEN_INVENTORY_OLD,
    screen("BAG & EXPERIENCE", legacyInventoryRows))
  mod.content.screens:register(SCREEN_TRAINERS_OLD,
    screen("TRAINERS & OAK", legacyTrainerRows))
  mod.content.screens:register(SCREEN_FIELD_OLD,
    screen("FIELD MOVES", legacyFieldRows))
  mod.content.screens:register(SCREEN_DISPLAY_OLD,
    screen("DISPLAY & THOR", legacyDisplayRows))
  mod.content.screens:register(SCREEN_GEN2_OLD,
    screen("PACK + POKéGEAR", function()
      return { toggle("gen2_menus", "PACK + POKéGEAR") }
    end))
  mod.content.screens:register(SCREEN_MODS_OLD,
    screen("MOD SETTINGS", mainRows))

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
      label = "MOD SETTINGS",
      onSelect = function() push(game, SCREEN_MAIN) end,
    })
  -- Stay inside Modern UI's default-priority grouping wrapper. The separate
  -- Pokegear's hook deliberately runs outside it so Pokegear remains a
  -- normal root-menu feature while Scott's settings live under MOD MENUS.
  end, -100)

  local api = {
    installed = true,
    unified = true,
    screenIds = {
      main = SCREEN_MAIN, graphics = SCREEN_GRAPHICS, world = SCREEN_WORLD,
      sprites = SCREEN_SPRITES, battles = SCREEN_BATTLES, wilds = SCREEN_WILDS,
      movement = SCREEN_MOVEMENT, system = SCREEN_SYSTEM,
      -- Historical names retain their old logical row sets.
      inventory = SCREEN_INVENTORY_OLD, trainers = SCREEN_TRAINERS_OLD,
      field = SCREEN_FIELD_OLD, display = SCREEN_DISPLAY_OLD,
      gen2 = SCREEN_GEN2_OLD, mods = SCREEN_MODS_OLD,
    },
    categories = CATEGORIES,
  }
  mod.exports.tweaksMenu = api
  return api
end
