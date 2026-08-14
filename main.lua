-- Scott's Tweaks
--
-- This keeps the original Voxel Run Bridge identity so existing installs and
-- GitHub updates continue in place, while giving Scott one small home for
-- related quality-of-life rules.

local Runtime = require("src.mods.Runtime")
local Game = require("src.core.Game")
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")

local unpackValues = table.unpack or unpack

local VOXEL_IDS = {
  "POKEMON_FINAL",
  "DRAMATIC_SHAPE",
  "BATTLE_ART_VOXEL_FORK",
  "DRAMALESS_SHAPE",
  "potato_voxel",
}

local HM_ACTIONS = {
  CUT = "cut",
  FLY = "fly",
  SURF = "surf",
  STRENGTH = "strength",
  FLASH = "flash",
}

local FREE_FLY_ID = "free_fly"
local FREE_FLY_OPTION = "free_fly_without_badges"
local FREE_FLY_BADGES_KEY = "badges"
local POKEMON_FINAL_ID = "POKEMON_FINAL"
local CACHE_START_MARKER = "_scottsTweaksCacheStartHook"
local GAPPED_LAND_OPTION = "gapped_land"
local BAG_POCKETS_OPTION = "bag_pockets"
local EXPERIENCE_MODE_OPTION = "experience_mode"
local EXP_SHARE_ID = "SCOTTS_EXP_SHARE"
local TRADE_STONE_ID = "SCOTTS_TRADE_STONE"
local TRADE_STONE_EFFECT = "SCOTTS_TRADE_STONE_EFFECT"
local GAPPED_LAND_RENDER_MARKER = "_scottsTweaksGappedLandRenderHook"
local GAPPED_LAND_INVALIDATE_MARKER = "_scottsTweaksGappedLandInvalidateHook"
local GAPPED_LAND_RADIUS = 1024
local GAPPED_LAND_CELL = 64
-- Native terrain and Flora's detailed apron occupy roughly y=-2..-37.
-- Keep the broad procedural ground below both so it only fills the void.
local GAPPED_LAND_Y = -40
local RELEASE_VERSION = "0.4.0"

local TRADE_EVOLUTIONS = {
  KADABRA = "ALAKAZAM",
  MACHOKE = "MACHAMP",
  GRAVELER = "GOLEM",
  HAUNTER = "GENGAR",
}

local BAG_POCKETS = {
  { id = "items", label = "ITEMS" },
  { id = "balls", label = "BALLS" },
  { id = "machines", label = "TM/HM" },
  { id = "key", label = "KEY ITEMS" },
}

local GAPPED_LAND_VOXEL_IDS = {
  "POKEMON_FINAL",
  "DRAMATIC_SHAPE",
}

-- These maps deliberately read as open sea at the horizon. A green apron
-- there would hide geography instead of filling an accidental visual void.
local GAPPED_LAND_SEA_MAPS = {
  CINNABAR_ISLAND = true,
  ROUTE_19 = true,
  ROUTE_20 = true,
  ROUTE_21 = true,
}

local function pack(...)
  return { n = select("#", ...), ... }
end

local function traceback(err)
  if debug and debug.traceback then
    return debug.traceback(tostring(err), 2)
  end
  return tostring(err)
end

local function finiteNumber(value, fallback)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then
    return fallback
  end
  return value
end

local function runningShoesOwnsFreeMove(FreeMove)
  return type(FreeMove) == "table"
    and type(rawget(FreeMove, "runningShoesTick")) == "function"
    and type(rawget(FreeMove, "runningShoesInner")) == "function"
end

local function findMod(mod, id)
  if type(mod.find) ~= "function" then return nil end
  local ok, found = pcall(mod.find, id)
  if not ok then ok, found = pcall(mod.find, mod, id) end
  return ok and found or nil
end

-- Pokemon Final is private, but it deliberately publishes its cached module
-- loader through mod.exports.lib for small companion adapters.  Some early
-- packages started the disk-cache job successfully and then left the fallback
-- "could not start" text on the screen.  Detect that behavior with a fake
-- screen instance; do not key the patch merely to a version label, and do not
-- carry any Pokemon Final source in this mod.
local function hasCacheStartMessageBug(start)
  local calls = 0
  local fake = {
    game = {},
    message = "probe",
    precache = {
      beginDisk = function()
        calls = calls + 1
        return true
      end,
    },
  }
  local ok = pcall(start, fake, false)
  return ok and calls == 1 and fake.message == "could not start"
end

local function installPokemonFinalCacheCompatibility(mod)
  local status = {
    active = false,
    reason = "pokemon_final_not_active",
    screen = "not_checked",
  }
  local restorers = {}

  status.restore = function()
    local changed = false
    for index = #restorers, 1, -1 do
      if restorers[index]() then changed = true end
    end
    if changed then
      status.active = false
      status.reason = "restored"
    end
    return changed
  end
  mod.exports.pokemonFinalCacheCompat = status

  local handle = findMod(mod, POKEMON_FINAL_ID)
  if not handle then return status end

  local version = handle.version
    or (handle.exports and handle.exports.version)
  status.version = version
  -- These are the only private package revisions whose module contract was
  -- locally verified.  A later build must opt in by exhibiting a newly audited
  -- contract rather than inheriting a raw-table patch forever.
  if version ~= "1.8.1-scott.2" and version ~= "1.8.1-scott.3" then
    status.reason = "unsupported_pokemon_final_version"
    status.screen = "not_checked"
    return status
  end

  local exports = handle.exports
  local lib = exports and exports.lib
  if type(lib) ~= "table" or type(lib.require) ~= "function" then
    status.reason = "module_loader_unavailable"
    status.screen = "unavailable"
    return status
  end

  local okScreen, Screen = pcall(lib.require, "ScottPrecacheScreen")
  if not okScreen or type(Screen) ~= "table" then
    status.reason = "cache_screen_unavailable"
    status.screen = "unavailable"
    return status
  end

  local original = rawget(Screen, "_start")
  if type(original) ~= "function" then
    status.reason = "cache_start_unavailable"
    status.screen = "unavailable"
    return status
  end

  local existing = rawget(Screen, CACHE_START_MARKER)
  if existing ~= nil then
    if type(existing) == "table" and existing.owner == mod.id
        and type(existing.original) == "function"
        and type(existing.wrapper) == "function"
        and rawget(Screen, "_start") == existing.wrapper then
      status.active = true
      status.reason = "already_installed"
      status.screen = "patched"
      restorers[#restorers + 1] = function()
        if rawget(Screen, CACHE_START_MARKER) ~= existing
            or rawget(Screen, "_start") ~= existing.wrapper then
          return false
        end
        rawset(Screen, "_start", existing.original)
        rawset(Screen, CACHE_START_MARKER, nil)
        return true
      end
    else
      status.reason = "cache_start_owned_by_another_mod"
      status.screen = "foreign_owner"
    end
    return status
  end

  if not hasCacheStartMessageBug(original) then
    status.reason = "already_safe"
    status.screen = "already_safe"
    return status
  end

  local function wrappedStart(self, ...)
    local result = pack(original(self, ...))
    -- Only the known false fallback is eligible, and only after the public
    -- precache status confirms that a build actually started.  Real errors,
    -- stale messages, and unfamiliar state shapes are left untouched.
    if self and self.message == "could not start" then
      local precache = self.precache
      if type(precache) == "table" and type(precache.status) == "function" then
        local okStatus, current = pcall(precache.status, self.game)
        if okStatus and type(current) == "table"
            and current.state == "building" then
          self.message = nil
        end
      end
    end
    return unpackValues(result, 1, result.n)
  end

  local marker = {
    owner = mod.id,
    version = RELEASE_VERSION,
    original = original,
    wrapper = wrappedStart,
  }
  -- Installation is deliberately last: every feature/ownership check above
  -- has completed before the shared exported table changes.
  rawset(Screen, "_start", wrappedStart)
  rawset(Screen, CACHE_START_MARKER, marker)
  restorers[#restorers + 1] = function()
    if rawget(Screen, CACHE_START_MARKER) ~= marker
        or rawget(Screen, "_start") ~= wrappedStart then
      return false
    end
    rawset(Screen, "_start", original)
    rawset(Screen, CACHE_START_MARKER, nil)
    return true
  end

  status.active = true
  status.reason = "patched"
  status.screen = "patched"
  mod.log:info("patched Pokemon Final %s cache start result", tostring(version))
  return status
end

local function findVoxelMod(mod)
  for _, id in ipairs(VOXEL_IDS) do
    local found = mod.find(id)
    local lib = found and found.exports and found.exports.lib
    if type(lib) == "table" then return id, found, lib end
  end
  return nil
end

local function moveId(move)
  if type(move) == "table" then return move.id end
  if type(move) == "string" then return move end
  return nil
end

local function knowsMove(mon, wanted)
  for _, move in ipairs((mon and mon.moves) or {}) do
    if moveId(move) == wanted then return true end
  end
  return false
end

local function partyMemberKnowing(save, wanted)
  for _, mon in ipairs((save and save.party) or {}) do
    if knowsMove(mon, wanted) then return mon end
  end
  return nil
end

local function optionEnabled(mod, key, fallback)
  local ok, value = pcall(mod.options.get, mod.options, key)
  if not ok or value == nil then return fallback end
  return value == true
end

local function optionValue(mod, key, fallback)
  local ok, value = pcall(mod.options.get, mod.options, key)
  if not ok or value == nil then return fallback end
  return value
end

local function defineOptions(mod)
  mod.options:define({
    {
      key = "hm_without_badges",
      type = "toggle",
      label = "BADGE-FREE HMS",
      default = true,
      help = "Use CUT, FLY, SURF, STRENGTH and FLASH without badges. A party Pokemon must still know the move.",
    },
    {
      key = FREE_FLY_OPTION,
      type = "toggle",
      label = "FREE FLY NOW",
      default = true,
      help = "Let Free Fly take off without THUNDERBADGE. FLY eligibility, STORY GATES and terrain rules stay under Free Fly's control.",
    },
    {
      key = GAPPED_LAND_OPTION,
      type = "toggle",
      label = "GAPPED LAND",
      default = true,
      help = "Fill the distant visual gap below the horizon in outdoor 1ST/3RD views. The added ground is not walkable.",
    },
    {
      key = BAG_POCKETS_OPTION,
      type = "toggle",
      label = "BAG POCKETS",
      default = true,
      help = "Organize the Gen 1 bag into ITEMS, BALLS, TM/HM and KEY ITEMS. Press Left or Right in the bag to change pockets.",
    },
    {
      key = EXPERIENCE_MODE_OPTION,
      type = "choice",
      label = "EXP. MODE",
      default = "vanilla",
      choices = {
        { "VANILLA", "vanilla" },
        { "LEAD ONLY", "lead" },
        { "PARTY ALL", "party" },
        { "EXP.SHARE", "share" },
      },
      help = "VANILLA keeps normal rules. LEAD ONLY rewards the active Pokemon. PARTY ALL gives full EXP to every healthy party member. EXP.SHARE permanently unlocks its bag item.",
    },
  })
end

local function constructScreen(factory, builtin, ...)
  if type(factory) == "function" then return factory(...) end
  if type(factory) == "table" and type(factory.new) == "function" then
    return factory.new(...)
  end
  return builtin.new(...)
end

local function playMenuSound(game, id)
  pcall(function()
    require("src.core.Sound").play(game.data, id or "Press_AB")
  end)
end

local function showUiMessage(game, message, onDone)
  game.stack:push(require("src.render.TextBox").new(game, message, onDone))
end

local function tradeEvolutionFor(data, mon)
  if not (data and data.pokemon and mon and mon.species) then return nil end
  local def = data.pokemon[mon.species]
  for _, evolution in ipairs((def and def.evolutions) or {}) do
    if evolution.method == "TRADE" then
      local target = evolution.species or evolution.into
      if target and data.pokemon[target] then return target end
    end
  end
  local fallback = TRADE_EVOLUTIONS[mon.species]
  if fallback and data.pokemon[fallback] then return fallback end
  return nil
end

local function pocketForItem(id, def, ItemEffects)
  if (def and def.machine) or id:match("^TM_") or id:match("^HM_") then
    return "machines"
  end
  if (ItemEffects and ItemEffects.isBall and ItemEffects.isBall(id))
      or (def and def.ball) then
    return "balls"
  end
  if id == EXP_SHARE_ID or id == "EXP_ALL"
      or (def and (def.keyItem or def.tossable == false)) then
    return "key"
  end
  return "items"
end

local function installInventoryFeatures(mod)
  local ItemEffects = require("src.inventory.ItemEffects")
  local Bag = require("src.inventory.Bag")

  -- v0.1.83 dispatches registered item effects directly.  The decorated bag
  -- below also handles this exact item on v0.1.75, whose public registry
  -- existed before the consumer-side dispatch was added.
  mod.content.item_effects:register(TRADE_STONE_EFFECT, {
    needsTarget = true,
    battle = false,
    field = true,
    use = function(ctx)
      local target = tradeEvolutionFor(ctx.data, ctx.target)
      if not target then
        return "failed", { "It won't have\nany effect." }
      end
      return "consumed", nil, { evolveTo = target }
    end,
  })
  mod.content.items:register(TRADE_STONE_ID, {
    id = TRADE_STONE_ID,
    name = "TRADE STONE",
    price = 500,
    effect = TRADE_STONE_EFFECT,
    needsTarget = true,
    tossable = true,
  })
  mod.content.items:register(EXP_SHARE_ID, {
    id = EXP_SHARE_ID,
    name = "EXP.SHARE",
    price = 0,
    keyItem = true,
    pocket = "KEY_ITEM",
    tossable = false,
    needsTarget = false,
  })

  -- Gen1Recomp v0.1.75 exposed item_effects content but its consumer did not
  -- dispatch it. Probe that behavior with inert synthetic data: v0.1.83+
  -- stays entirely native, while the older engine receives an exact-ID
  -- adapter. An owned wrapper is first restored on developer hot reload so
  -- a corrected implementation is never frozen in the process-global module.
  local existingTradeHook = rawget(ItemEffects, "_scottsTweaksTradeStoneHook")
  local restoredOwnedHook = false
  if type(existingTradeHook) == "table"
      and existingTradeHook.owner == mod.id
      and ItemEffects.needsTarget == existingTradeHook.wrapperNeedsTarget
      and ItemEffects.use == existingTradeHook.wrapperUse then
    ItemEffects.needsTarget = existingTradeHook.originalNeedsTarget
    ItemEffects.use = existingTradeHook.originalUse
    rawset(ItemEffects, "_scottsTweaksTradeStoneHook", nil)
    existingTradeHook = nil
    restoredOwnedHook = true
  end

  local function nativeItemEffectDispatch()
    local probeId = "__SCOTTS_ITEM_EFFECT_PROBE"
    local probeEffectId = "__SCOTTS_ITEM_EFFECT_PROBE_EFFECT"
    local called = false
    local probeEffect = {
      needsTarget = true,
      battle = false,
      field = true,
      use = function(ctx)
        called = ctx and ctx.itemId == probeId
        return "scotts_probe"
      end,
    }
    local probeData = {
      items = {
        [probeId] = {
          id = probeId,
          name = "PROBE",
          price = 0,
          effect = probeEffectId,
          needsTarget = true,
        },
      },
      item_effects = { [probeEffectId] = probeEffect },
      pokemon = {}, text = {}, field = {}, constants = {},
    }
    local okTarget, needsTarget = pcall(ItemEffects.needsTarget,
      probeId, probeData.items[probeId], probeData)
    local okUse, result = pcall(ItemEffects.use, probeData,
      { inventory = {} }, probeId, { species = "PROBE" })
    return okTarget and needsTarget == true
      and okUse and result == "scotts_probe" and called
  end

  local tradeAdapterMode = "native_item_effects"
  if not nativeItemEffectDispatch() and not existingTradeHook then
    local baseNeedsTarget = ItemEffects.needsTarget
    local baseUse = ItemEffects.use
    local function isLiveTradeStone(data, id, itemDef)
      itemDef = itemDef or (data and data.items and data.items[id])
      return id == TRADE_STONE_ID and type(itemDef) == "table"
        and itemDef.effect == TRADE_STONE_EFFECT
    end
    local wrappedNeedsTarget = function(id, itemDef, data, ...)
      if isLiveTradeStone(data, id, itemDef) then return true end
      return baseNeedsTarget(id, itemDef, data, ...)
    end
    local wrappedUse = function(data, save, id, target, battle, moveIndex, ow, ...)
      local itemDef = data and data.items and data.items[id]
      local effect = data and data.item_effects
        and data.item_effects[TRADE_STONE_EFFECT]
      if isLiveTradeStone(data, id, itemDef)
          and type(effect) == "table" and type(effect.use) == "function" then
        if (battle and effect.battle == false)
            or (not battle and effect.field == false) then
          local text = data.text and data.text._ItemUseNotTimeText
            or "It can't be used\nright now."
          return "failed", { text }
        end
        return effect.use({
          data = data,
          save = save,
          itemId = id,
          item = itemDef,
          target = target,
          battle = battle,
          moveIndex = moveIndex,
          overworld = ow,
        })
      end
      return baseUse(data, save, id, target, battle, moveIndex, ow, ...)
    end
    ItemEffects.needsTarget = wrappedNeedsTarget
    ItemEffects.use = wrappedUse
    rawset(ItemEffects, "_scottsTweaksTradeStoneHook", {
      owner = mod.id,
      version = RELEASE_VERSION,
      originalNeedsTarget = baseNeedsTarget,
      originalUse = baseUse,
      wrapperNeedsTarget = wrappedNeedsTarget,
      wrapperUse = wrappedUse,
    })
    tradeAdapterMode = "v0.1.75_compatibility"
  elseif existingTradeHook then
    tradeAdapterMode = "existing_compatibility_chain"
  elseif restoredOwnedHook then
    tradeAdapterMode = "native_after_hot_reload_cleanup"
  end

  local pocketStatus = {
    active = true,
    mode = "screen_pockets",
    pockets = { "items", "balls", "machines", "key" },
  }
  local shopStatus = {
    active = true,
    tradeStone = TRADE_STONE_ID,
    price = 500,
    ownedCount = true,
  }
  mod.exports.bagPockets = pocketStatus
  mod.exports.shopTweaks = shopStatus
  mod.exports.tradeStone = {
    id = TRADE_STONE_ID,
    price = 500,
    evolutions = TRADE_EVOLUTIONS,
    adapter = tradeAdapterMode,
  }

  local priorBag = mod.content.screens:get("BagMenu")
  local builtinBag = require("src.ui.BagMenu")

  local function decorateBag(game, opts, list)
    if type(list) ~= "table" or type(list.update) ~= "function"
        or type(list.draw) ~= "function" or type(list.onChoose) ~= "function"
        or not optionEnabled(mod, BAG_POCKETS_OPTION, true) then
      return list
    end
    if rawget(list, "_scottsTweaksPocketLayer") then return list end
    -- A lower-priority modern bag that deliberately publishes its own pocket
    -- controller remains the single owner rather than receiving a second set
    -- of Left/Right tabs.
    if type(rawget(list, "switchPocket")) == "function"
        or type(rawget(list, "__pocketIds")) == "table" then
      pocketStatus.reason = "existing_pocket_ui"
      return list
    end

    local state = {
      pocket = 1,
      cursor = {},
      swapId = nil,
    }
    local baseUpdate = list.update
    local baseDraw = list.draw
    local baseChoose = list.onChoose

    local function currentId()
      local item = list.items and list.items[list.index]
      return item and item.value or nil
    end

    local function buildRows(pocketId)
      local rows = {}
      for _, id in ipairs(Bag.order(game.save)) do
        local count = game.save.inventory[id]
        local def = game.data.items[id]
        if count and pocketForItem(id, def, ItemEffects) == pocketId then
          rows[#rows + 1] = {
            value = id,
            label = def and def.name or id,
            right = "x" .. tostring(count),
          }
        end
      end
      return rows
    end

    local function rebuild(preferredId)
      local pocket = BAG_POCKETS[state.pocket]
      local oldId = preferredId or currentId()
      list.items = buildRows(pocket.id)
      list.title = "< " .. pocket.label .. " >"
      local nextIndex = 1
      if oldId then
        for index, item in ipairs(list.items) do
          if item.value == oldId then nextIndex = index break end
        end
      elseif state.cursor[pocket.id] then
        nextIndex = state.cursor[pocket.id]
      end
      list.index = math.max(1, math.min(nextIndex, math.max(1, #list.items)))
      local rows = list.rows or 7
      list.scroll = math.max(0, math.min(list.scroll or 0,
        math.max(0, #list.items - rows)))
      if list.index - list.scroll > rows then
        list.scroll = list.index - rows
      elseif list.index - list.scroll < 1 then
        list.scroll = list.index - 1
      end
    end

    local function finishSwap(secondId)
      local firstId = state.swapId
      state.swapId = nil
      list.swapIndex = nil
      if not firstId or not secondId then return false end
      local order = Bag.order(game.save)
      local firstIndex, secondIndex
      for index, id in ipairs(order) do
        if id == firstId then firstIndex = index end
        if id == secondId then secondIndex = index end
      end
      if firstIndex and secondIndex then
        order[firstIndex], order[secondIndex] = order[secondIndex], order[firstIndex]
        playMenuSound(game, "Swap")
        rebuild(secondId)
        return true
      end
      rebuild(secondId)
      return false
    end

    list.onSelectKey = function(item, current)
      if not item then return end
      if not state.swapId then
        state.swapId = item.value
        current.swapIndex = current.index
      else
        finishSwap(item.value)
      end
    end

    list.onChoose = function(item, ...)
      if state.swapId then
        finishSwap(item and item.value)
        return
      end
      if item and item.value == EXP_SHARE_ID then
        showUiMessage(game,
          "EXP.SHARE works when\nEXP. MODE is set to\nEXP.SHARE.")
        return
      end
      return baseChoose(item, ...)
    end

    list.update = function(self, dt)
      rebuild(currentId())
      local input = game.input
      local left = input and input.wasPressed and input:wasPressed("left")
      local right = input and input.wasPressed and input:wasPressed("right")
      if left or right then
        local pocket = BAG_POCKETS[state.pocket]
        state.cursor[pocket.id] = self.index
        state.swapId = nil
        self.swapIndex = nil
        state.pocket = ((state.pocket - 1 + (right and 1 or -1))
          % #BAG_POCKETS) + 1
        -- Do not carry the selected id from the old pocket into the new
        -- pocket.  Clearing the rendered rows lets rebuild restore that
        -- pocket's own remembered cursor instead.
        self.items = {}
        rebuild()
        playMenuSound(game)
        return
      end
      local result = pack(baseUpdate(self, dt))
      local active = BAG_POCKETS[state.pocket]
      state.cursor[active.id] = self.index
      return unpackValues(result, 1, result.n)
    end

    list.draw = function(self)
      rebuild(currentId())
      return baseDraw(self)
    end

    rawset(list, "_scottsTweaksPocketLayer", {
      owner = mod.id,
      version = RELEASE_VERSION,
      state = state,
    })
    rebuild()
    return list
  end

  mod.content.screens:override("BagMenu", {
    new = function(game, opts)
      return decorateBag(game, opts,
        constructScreen(priorBag, builtinBag, game, opts))
    end,
  })

  local priorShop = mod.content.screens:get("ShopMenu")
  local builtinShop = require("src.ui.ShopMenu")

  local function decorateBuyList(game, list)
    if type(list) ~= "table" or type(list.draw) ~= "function"
        or rawget(list, "_scottsTweaksOwnedCount") then return list end
    if list.title ~= "BUY" and list.kind ~= "BUY" then return list end
    local baseDraw = list.draw
    list.draw = function(self)
      local item = self.items and self.items[self.index]
      local count = item and game.save.inventory[item.value] or 0
      local oldTitle = self.title
      self.title = ("BUY BAG:%d"):format(tonumber(count) or 0)
      local result
      local ok, err = xpcall(function()
        result = pack(baseDraw(self))
      end, traceback)
      self.title = oldTitle
      if not ok then error(err, 0) end
      return unpackValues(result, 1, result.n)
    end
    rawset(list, "_scottsTweaksOwnedCount", {
      owner = mod.id,
      version = RELEASE_VERSION,
    })
    return list
  end

  local function decorateShop(game, menu)
    if type(menu) ~= "table" or type(menu.update) ~= "function"
        or rawget(menu, "_scottsTweaksShopLayer") then return menu end
    local baseUpdate = menu.update
    menu.update = function(self, dt)
      local before = game.stack and game.stack:top()
      local result
      local ok, err = xpcall(function()
        result = pack(baseUpdate(self, dt))
      end, traceback)
      if not ok then error(err, 0) end
      local after = game.stack and game.stack:top()
      if after and after ~= before then decorateBuyList(game, after) end
      return unpackValues(result, 1, result.n)
    end
    rawset(menu, "_scottsTweaksShopLayer", {
      owner = mod.id,
      version = RELEASE_VERSION,
    })
    return menu
  end

  mod.content.screens:override("ShopMenu", {
    new = function(game, stock, onQuit)
      local copied, seen = {}, false
      for _, id in ipairs(stock or {}) do
        copied[#copied + 1] = id
        if id == TRADE_STONE_ID then seen = true end
      end
      if not seen then copied[#copied + 1] = TRADE_STONE_ID end
      return decorateShop(game,
        constructScreen(priorShop, builtinShop, game, copied, onQuit))
    end,
  })
end

local function installExperienceModes(mod)
  local Bag = require("src.inventory.Bag")
  local state = {
    mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla"),
    item = EXP_SHARE_ID,
    itemUnlocked = false,
    pending = false,
    reason = "not_requested",
  }
  mod.exports.experience = state

  local function totalOwned(save)
    local bag = save and save.inventory and save.inventory[EXP_SHARE_ID] or 0
    local pc = save and save.pcItems and save.pcItems[EXP_SHARE_ID] or 0
    return (tonumber(bag) or 0) + (tonumber(pc) or 0)
  end

  local function ensureShareItem(save, data)
    state.mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla")
    if state.mode ~= "share" then
      state.reason = "mode_not_share"
      return false
    end
    if not (save and save.inventory and data and data.items
        and data.items[EXP_SHARE_ID]) then
      state.pending = true
      state.reason = "save_or_item_unavailable"
      return false
    end
    local bagCount = tonumber(save.inventory[EXP_SHARE_ID]) or 0
    local pcCount = save.pcItems and tonumber(save.pcItems[EXP_SHARE_ID]) or 0
    if bagCount > 0 then
      state.itemUnlocked = true
      state.pending = false
      state.reason = "in_bag"
      return true
    end
    -- SaveData may restore a disabled mod's item to the PC when the bag is
    -- full.  Move one existing copy back only after Bag.add succeeds, so a
    -- failed transfer cannot lose or duplicate it.
    if pcCount > 0 then
      if Bag.add(save, EXP_SHARE_ID, 1, data) then
        save.pcItems[EXP_SHARE_ID] = pcCount - 1
        if save.pcItems[EXP_SHARE_ID] <= 0 then
          save.pcItems[EXP_SHARE_ID] = nil
        end
        Bag.order(save)
        state.itemUnlocked = true
        state.pending = false
        state.reason = "moved_from_pc"
        return true
      end
      state.itemUnlocked = true
      state.pending = true
      state.reason = "in_pc_bag_full"
      return true
    end
    if totalOwned(save) > 0 then
      state.itemUnlocked = true
      state.pending = false
      state.reason = "owned"
      return true
    end
    if not Bag.add(save, EXP_SHARE_ID, 1, data) then
      state.pending = true
      state.reason = "bag_full"
      return false
    end
    -- v0.1.75 appended a new id once before Bag.order's defensive pass and
    -- once during it.  Calling order now normalizes that older representation.
    Bag.order(save)
    state.itemUnlocked = true
    state.pending = false
    state.reason = "granted"
    mod.log:info("EXP.SHARE unlocked in the item bag")
    return true
  end

  local function withExpAll(save, value, fn)
    local inventory = save and save.inventory
    if not inventory then return fn() end
    local existed = inventory.EXP_ALL ~= nil
    local previous = inventory.EXP_ALL
    inventory.EXP_ALL = value
    local result
    local ok, err = xpcall(function() result = pack(fn()) end, traceback)
    if existed then inventory.EXP_ALL = previous else inventory.EXP_ALL = nil end
    if not ok then error(err, 0) end
    return unpackValues(result, 1, result.n)
  end

  local function copiedAward(ctx, alive)
    local copy = {}
    for key, value in pairs(ctx) do copy[key] = value end
    copy.alive = alive
    copy.participants = 1
    return copy
  end

  mod.hooks:wrap("battle.exp_award", function(nextFn, ctx)
    local mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla")
    state.mode = mode
    if mode == "vanilla" or type(ctx) ~= "table"
        or type(ctx.applyShare) ~= "function" then
      return nextFn(ctx)
    end
    local battle = ctx.battle
    local game = battle and battle.game
    local save = game and game.save
    if not save then return nextFn(ctx) end

    if mode == "share" then
      ensureShareItem(save, game.data)
      return withExpAll(save, 1, function() return nextFn(ctx) end)
    end

    local alive = {}
    if mode == "lead" then
      local mon = battle.player and battle.player.mon
      if mon and (mon.hp or 0) > 0 then alive[1] = mon end
    elseif mode == "party" then
      for _, mon in ipairs(save.party or {}) do
        if (mon.hp or 0) > 0 then alive[#alive + 1] = mon end
      end
    else
      return nextFn(ctx)
    end
    return withExpAll(save, nil, function()
      return nextFn(copiedAward(ctx, alive))
    end)
  end, 1000)

  local function lifecycle(payload)
    if optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla") ~= "share" then
      state.mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla")
      return
    end
    local game = payload and payload.game
    local save = payload and payload.save or (game and game.save) or Game.save
    local data = game and game.data or Game.data
    ensureShareItem(save, data)
  end

  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("game.ready", lifecycle)
    mod.events:on("save.created", lifecycle)
    mod.events:on("save.loaded", lifecycle)
    mod.events:on("map.entered", lifecycle)
    mod.events:on("mod.options_changed", function(payload)
      if payload and payload.mod == mod.id
          and payload.key == EXPERIENCE_MODE_OPTION then
        state.mode = payload.value
        lifecycle({ game = Game, save = Game.save })
      end
    end)
  end
end

-- POKEMON_FINAL and DRAMATIC_SHAPE deliberately publish a module loader for
-- companion adapters. This layer uses only that public seam and supplies its
-- own tiny procedural texture and mesh; no voxel source, map data, collision,
-- connection, or disk-cache input is copied or changed.
local function findGappedLandVoxel(mod)
  local sawSupportedId = false
  for _, id in ipairs(GAPPED_LAND_VOXEL_IDS) do
    local handle = findMod(mod, id)
    if handle then
      sawSupportedId = true
      local lib = handle.exports and handle.exports.lib
      if type(lib) == "table" and type(lib.require) == "function" then
        return id, handle, lib
      end
    end
  end
  if sawSupportedId then
    return nil, nil, nil, "voxel_exports_missing_require"
  end
  return nil, nil, nil, "no_supported_voxel_mod"
end

local function releaseGpuObject(object)
  if object and type(object.release) == "function" then
    pcall(object.release, object)
  end
end

local function installGappedLand(mod)
  local status = {
    active = false,
    reason = "no_supported_voxel_mod",
    mode = "visual_apron",
  }
  status.restore = function() return false end
  mod.exports.gappedLand = status

  local voxelId, handle, lib, findReason = findGappedLandVoxel(mod)
  if not voxelId then
    status.reason = findReason
    return status
  end
  status.voxel = voxelId
  status.providerVersion = handle.version
    or (handle.exports and handle.exports.version)

  local okModules, VoxelScene, Voxel3D, Voxel, DayNight, Mat4 =
    pcall(function()
      return lib.require("VoxelScene"), lib.require("Voxel3D"),
        lib.require("VoxelState"), lib.require("DayNight"),
        lib.require("Mat4")
    end)
  if not okModules
      or type(VoxelScene) ~= "table"
      or type(VoxelScene.render) ~= "function"
      or type(Voxel3D) ~= "table"
      or type(Voxel3D.beginScene) ~= "function"
      or type(Voxel3D.newMesh) ~= "function"
      or type(Voxel3D.draw) ~= "function"
      or type(Voxel3D.invalidate) ~= "function"
      or type(Voxel3D.seams) ~= "function"
      or type(Voxel3D.glass) ~= "function"
      or type(Voxel) ~= "table"
      or type(Voxel.isFreeCam) ~= "function"
      or type(DayNight) ~= "table"
      or type(DayNight.isCanopy) ~= "function"
      or type(Mat4) ~= "table"
      or type(Mat4.translate) ~= "function" then
    status.reason = "exported_scene_modules_unavailable"
    return status
  end

  local existingScene = rawget(VoxelScene, GAPPED_LAND_RENDER_MARKER)
  local existingInvalidate = rawget(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER)
  if existingScene ~= nil or existingInvalidate ~= nil then
    local sameOwner = type(existingScene) == "table"
      and type(existingInvalidate) == "table"
      and existingScene.owner == mod.id
      and existingInvalidate.owner == mod.id
      and existingScene.controller ~= nil
      and existingScene.controller == existingInvalidate.controller
      and type(existingScene.controller.restore) == "function"
      and type(existingScene.wrapper) == "function"
      and type(existingInvalidate.wrapper) == "function"
    if not sameOwner then
      status.reason = "renderer_hook_owned_by_another_mod"
      return status
    end

    -- A hot reload may construct a fresh mod facade while exported voxel
    -- modules persist. Keep one wrapper and point its live option lookup and
    -- logging at the fresh facade instead of multiplying the draw.
    existingScene.controller.mod = mod
    status.active = true
    status.reason = "already_installed"
    status.restore = function()
      local changed = existingScene.controller.restore()
      if changed then
        status.active = false
        status.reason = "restored"
      end
      return changed
    end
    return status
  end

  local controller = {
    mod = mod,
    mesh = nil,
    texture = nil,
    warnedDraw = false,
    warnedBuild = false,
  }

  local function clearGpuObjects()
    local mesh, texture = controller.mesh, controller.texture
    controller.mesh, controller.texture = nil, nil
    if mesh ~= false then releaseGpuObject(mesh) end
    if texture ~= false then releaseGpuObject(texture) end
  end

  local function buildMesh()
    if controller.mesh ~= nil then return controller.mesh or nil end
    local verts, indices = {}, {}
    local radius, cell = GAPPED_LAND_RADIUS, GAPPED_LAND_CELL
    for x = -radius, radius - cell, cell do
      for z = -radius, radius - cell, cell do
        local base = #verts
        local u0, v0 = (x + radius) / cell, (z + radius) / cell
        local u1, v1 = u0 + 1, v0 + 1
        -- Four vertices per cell keep the quadratic world curve smooth all
        -- the way to the backdrop instead of bending one enormous quad.
        verts[#verts + 1] = { x, 0, z, u0, v0, 1 }
        verts[#verts + 1] = { x + cell, 0, z, u1, v0, 1 }
        verts[#verts + 1] = { x + cell, 0, z + cell, u1, v1, 1 }
        verts[#verts + 1] = { x, 0, z + cell, u0, v1, 1 }
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 2
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 4
      end
    end
    controller.mesh = Voxel3D.newMesh(verts, indices) or false
    return controller.mesh or nil
  end

  local function buildTexture()
    if controller.texture ~= nil then return controller.texture or nil end
    local imageApi = love and love.image
    local graphics = love and love.graphics
    if not (imageApi and type(imageApi.newImageData) == "function"
        and graphics and type(graphics.newImage) == "function") then
      controller.texture = false
      return nil
    end

    local data
    local ok, texture = pcall(function()
      data = imageApi.newImageData(8, 8)
      for y = 0, 7 do
        for x = 0, 7 do
          local light = (math.floor(x / 4) + math.floor(y / 4)) % 2 == 0
          local r, g, b = 0.30, 0.48, 0.18
          if light then r, g, b = 0.35, 0.55, 0.21 end
          -- A sparse third green keeps the procedural floor from reading as
          -- a flat debug colour while remaining quiet behind real terrain.
          if (x * 7 + y * 11) % 17 == 0 then
            r, g, b = 0.39, 0.59, 0.24
          end
          data:setPixel(x, y, r, g, b, 1)
        end
      end
      local image = graphics.newImage(data)
      if type(image.setFilter) == "function" then
        image:setFilter("nearest", "nearest")
      end
      if type(image.setWrap) == "function" then
        image:setWrap("repeat", "repeat")
      end
      return image
    end)
    releaseGpuObject(data)
    controller.texture = (ok and texture) or false
    return controller.texture or nil
  end

  local function eligible(state)
    local liveMod = controller.mod
    if not optionEnabled(liveMod, GAPPED_LAND_OPTION, true) then return false end
    local map = state and state.map
    local def = map and map.def
    if not def or GAPPED_LAND_SEA_MAPS[map.id] then return false end

    local tileset = def.tileset
    if not tileset and type(map.tileset) == "table" then
      tileset = map.tileset.id
    end
    if tileset == "SHIP_PORT" then return false end

    local okOutdoor, outdoor = pcall(Map.isOutdoor, def)
    if not okOutdoor or not outdoor then return false end
    local okCanopy, canopy = pcall(DayNight.isCanopy, map)
    if not okCanopy or canopy then return false end
    local okCamera, freeCamera = pcall(Voxel.isFreeCam)
    return okCamera and freeCamera == true
  end

  local function focusPoint(state)
    local focus = Voxel3D.focus
    local fx = type(focus) == "table" and finiteNumber(focus[1]) or nil
    local fz = type(focus) == "table" and finiteNumber(focus[3]) or nil
    if fx and fz then return fx, fz end

    local player = state and state.player
    local px = player and finiteNumber(player.px) or nil
    local pz = player and finiteNumber(player.py) or nil
    if px and pz then return px + 8, pz + 8 end

    local def = state and state.map and state.map.def
    return finiteNumber(def and def.width, 1) * 16,
      finiteNumber(def and def.height, 1) * 16
  end

  local function draw(state)
    if not eligible(state) then return end
    local mesh, texture = buildMesh(), buildTexture()
    if not (mesh and texture) then
      if not controller.warnedBuild then
        controller.warnedBuild = true
        controller.mod.log:warn("GAPPED LAND GPU objects are unavailable; leaving the native horizon unchanged")
      end
      return
    end

    local fx, fz = focusPoint(state)
    local cell = GAPPED_LAND_CELL
    local cx = math.floor(fx / cell) * cell
    local cz = math.floor(fz / cell) * cell

    -- This draw is deliberately before Backdrop/terrain. It writes ordinary
    -- depth at y=-40; the native y=-2..-37 apron, terrain and water rendered
    -- later therefore remain authoritative everywhere they exist.
    local okDraw, drawErr = xpcall(function()
      Voxel3D.seams(false)
      Voxel3D.glass(false)
      Voxel3D.draw(mesh, texture, Mat4.translate(cx, GAPPED_LAND_Y, cz))
    end, traceback)
    -- beginScene establishes seams/glass=true before this first draw. These
    -- setters normally cannot fail, but a provider/driver error must
    -- not leave later terrain sampling this procedural texture as glass or
    -- carrying its non-voxel wireframe state.
    pcall(Voxel3D.glass, true)
    pcall(Voxel3D.seams, true)
    if not okDraw then error(drawErr, 0) end
  end

  local originalRender = VoxelScene.render
  local originalInvalidate = Voxel3D.invalidate

  local function wrappedRender(state, ...)
    local renderArgs = pack(...)
    local innerBegin = Voxel3D.beginScene
    local wrappedBegin
    wrappedBegin = function(...)
      local beginArgs = pack(...)
      local began = pack(innerBegin(unpackValues(beginArgs, 1, beginArgs.n)))
      if began[1] then
        local okDraw, drawErr = xpcall(function() draw(state) end, traceback)
        if not okDraw and not controller.warnedDraw then
          controller.warnedDraw = true
          controller.mod.log:warn("GAPPED LAND skipped after a draw error: %s",
            tostring(drawErr))
        end
      end
      return unpackValues(began, 1, began.n)
    end

    rawset(Voxel3D, "beginScene", wrappedBegin)
    local rendered
    local okRender, renderErr = xpcall(function()
      rendered = pack(originalRender(state,
        unpackValues(renderArgs, 1, renderArgs.n)))
    end, traceback)
    -- Never leave a frame-local interception in the provider, and never
    -- overwrite a third party that deliberately replaced it during render.
    if rawget(Voxel3D, "beginScene") == wrappedBegin then
      rawset(Voxel3D, "beginScene", innerBegin)
    end
    if not okRender then error(renderErr, 0) end
    return unpackValues(rendered, 1, rendered.n)
  end

  local function wrappedInvalidate(...)
    local invalidateArgs = pack(...)
    local result
    local okInvalidate, invalidateErr = xpcall(function()
      result = pack(originalInvalidate(
        unpackValues(invalidateArgs, 1, invalidateArgs.n)))
    end, traceback)
    clearGpuObjects()
    if not okInvalidate then error(invalidateErr, 0) end
    return unpackValues(result, 1, result.n)
  end

  local sceneMarker = {
    owner = mod.id,
    version = RELEASE_VERSION,
    original = originalRender,
    wrapper = wrappedRender,
    controller = controller,
  }
  local invalidateMarker = {
    owner = mod.id,
    version = RELEASE_VERSION,
    original = originalInvalidate,
    wrapper = wrappedInvalidate,
    controller = controller,
  }

  controller.restore = function()
    -- Refuse a partial unhook if another adapter currently wraps either
    -- function outside ours. Its owner can restore first and this can be
    -- retried without severing anyone's call chain.
    if rawget(VoxelScene, GAPPED_LAND_RENDER_MARKER) ~= sceneMarker
        or rawget(VoxelScene, "render") ~= wrappedRender
        or rawget(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER) ~= invalidateMarker
        or rawget(Voxel3D, "invalidate") ~= wrappedInvalidate then
      return false
    end
    rawset(VoxelScene, "render", originalRender)
    rawset(VoxelScene, GAPPED_LAND_RENDER_MARKER, nil)
    rawset(Voxel3D, "invalidate", originalInvalidate)
    rawset(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER, nil)
    clearGpuObjects()
    return true
  end
  status.restore = function()
    local changed = controller.restore()
    if changed then
      status.active = false
      status.reason = "restored"
    end
    return changed
  end

  -- Shared-table writes are the final installation actions after all public
  -- capabilities and ownership markers have been checked.
  rawset(Voxel3D, "invalidate", wrappedInvalidate)
  rawset(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER, invalidateMarker)
  rawset(VoxelScene, "render", wrappedRender)
  rawset(VoxelScene, GAPPED_LAND_RENDER_MARKER, sceneMarker)

  status.active = true
  status.reason = "attached"
  mod.log:info("GAPPED LAND visual apron attached to %s", voxelId)
  return status
end

local function installBadgeFreeFieldMoves(mod)
  -- Cut and Surf ask this hook again when the move is used. Calling next
  -- first preserves every vanilla or earlier-mod success; we only widen a
  -- rejected answer for one of the five badge-gated Gen 1 HMs.
  mod.hooks:wrap("fieldmove.eligibility",
    function(nextFn, wanted, ctx)
      local vanilla = nextFn(wanted, ctx)
      if vanilla ~= nil then return vanilla end
      if not optionEnabled(mod, "hm_without_badges", true)
          or HM_ACTIONS[wanted] == nil then
        return nil
      end
      local save = (ctx and ctx.save) or Game.save
      return partyMemberKnowing(save, wanted)
    end, 1000)

  -- Vanilla hides HM actions from the party submenu when the badge is
  -- missing. Add only those hidden rows, in the Pokemon's actual move order,
  -- while preserving terrain/context rules and entries supplied by other
  -- mods. Nothing is taught and no badge/save flag is changed.
  mod.hooks:wrap("ui.party.submenu",
    function(nextFn, game, items, mon, ctx)
      local downstream = nextFn(game, items, mon, ctx)
      if type(downstream) == "table" then items = downstream end
      if type(items) ~= "table"
          or not optionEnabled(mod, "hm_without_badges", true)
          or (ctx and ctx.battle)
          or not (ctx and ctx.overworld) then
        return items
      end

      local ow = ctx.overworld
      local outside = ow.map and ow.map.def and Map.isOutside(
        ow.map.def, FieldDefaults.field(game.data, "outsideTilesets")) or false
      local existing = {}
      local insertAt = #items + 1
      for index, item in ipairs(items) do
        if type(item) == "table" then
          if item.action then existing[item.action] = true end
          if insertAt == #items + 1
              and (item.action == "stats" or item.action == "switch") then
            insertAt = index
          end
        end
      end

      for _, move in ipairs((mon and mon.moves) or {}) do
        local id = moveId(move)
        local action = HM_ACTIONS[id]
        local contextAllows = action ~= nil
          and (id ~= "FLY" or outside)
          and (id ~= "FLASH" or ow.dark == true)
        if contextAllows and not existing[action] then
          table.insert(items, insertAt, { label = id, action = action })
          existing[action] = true
          insertAt = insertAt + 1
        end
      end
      return items
    end, 1000)

  mod.exports.hmWithoutBadges = function()
    return optionEnabled(mod, "hm_without_badges", true)
  end
end

-- Free Fly performs its takeoff and water-landing badge tests outside the
-- engine's fieldmove.eligibility hook. Feature-detect the public flight-state
-- export and the exact toggle in its registered option schema before applying
-- a live option overlay. No badge, move, story flag, or persisted Free Fly
-- preference is edited.
local function installFreeFlyImmediateFlight(mod)
  local state = {
    active = false,
    reason = "free_fly_not_active",
  }
  local activeLoader
  local priorSet = false
  local priorValue
  local priorBucketExisted = false

  local function findFreeFly()
    if type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, FREE_FLY_ID)
    if not ok then ok, handle = pcall(mod.find, mod, FREE_FLY_ID) end
    if ok then return handle end
    return nil
  end

  local function compatible(handle, loader)
    local exports = handle and handle.exports
    if type(exports) ~= "table" or type(exports.isFlying) ~= "function" then
      return false, "flight_state_export_missing"
    end
    local schemas = loader and loader.optionSchemas
    local schema = schemas and schemas[FREE_FLY_ID]
    if type(schema) ~= "table" then
      return false, "option_schema_missing"
    end
    for _, row in ipairs(schema) do
      if type(row) == "table" and row.key == FREE_FLY_BADGES_KEY
          and row.type == "toggle" then
        return true
      end
    end
    return false, "badges_toggle_missing"
  end

  local function restore()
    local loader = activeLoader
    local buckets = loader and loader.modOptions
    local bucket = buckets and buckets[FREE_FLY_ID]
    if bucket then
      if priorSet then
        bucket[FREE_FLY_BADGES_KEY] = priorValue
      else
        bucket[FREE_FLY_BADGES_KEY] = nil
      end
      if not priorBucketExisted and next(bucket) == nil then
        buckets[FREE_FLY_ID] = nil
      end
    end
    activeLoader = nil
    priorSet, priorValue, priorBucketExisted = false, nil, false
    state.active = false
    state.reason = "disabled"
  end

  local function apply(loader)
    if not optionEnabled(mod, FREE_FLY_OPTION, true) then
      if activeLoader then restore() end
      state.reason = "disabled"
      return false
    end

    local handle = findFreeFly()
    if not handle then
      state.active = false
      state.reason = "free_fly_not_active"
      return false
    end
    if type(loader) ~= "table" then
      state.active = false
      state.reason = "loader_unavailable"
      return false
    end
    local isCompatible, compatibilityReason = compatible(handle, loader)
    if not isCompatible then
      state.active = false
      state.reason = "unsupported_free_fly_" .. tostring(compatibilityReason)
      mod.log:warn("Free Fly does not expose the supported badge-check adapter (%s)",
        tostring(compatibilityReason))
      return false
    end

    loader.modOptions = loader.modOptions or {}
    local bucket = loader.modOptions[FREE_FLY_ID]
    if activeLoader ~= loader then
      priorBucketExisted = bucket ~= nil
      bucket = bucket or {}
      loader.modOptions[FREE_FLY_ID] = bucket
      priorSet = bucket[FREE_FLY_BADGES_KEY] ~= nil
      priorValue = bucket[FREE_FLY_BADGES_KEY]
      activeLoader = loader
    else
      bucket = bucket or {}
      loader.modOptions[FREE_FLY_ID] = bucket
    end
    bucket[FREE_FLY_BADGES_KEY] = false
    state.active = true
    state.reason = "badges_runtime_override"
    state.version = handle.version
    return true
  end

  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("mods.loaded", function(payload)
      apply(payload and payload.loader or Game.mods)
    end)
    mod.events:on("mod.options_changed", function(payload)
      if not payload then return end
      if payload.mod == mod.id and payload.key == FREE_FLY_OPTION then
        if payload.value == true then apply(Game.mods) else restore() end
      elseif state.active and payload.mod == FREE_FLY_ID
          and payload.key == FREE_FLY_BADGES_KEY then
        -- Keep the player's latest Free Fly preference ready for restoration if
        -- Scott's override is later switched off, but hold the live answer
        -- false while the override remains enabled.
        priorSet = payload.value ~= nil
        priorValue = payload.value
        local buckets = activeLoader and activeLoader.modOptions
        local bucket = buckets and buckets[FREE_FLY_ID]
        if bucket then bucket[FREE_FLY_BADGES_KEY] = false end
      end
    end)
  end

  apply(Game.mods)

  mod.exports.freeFlyBadgeBypass = function()
    return state.active, state.reason, state.version
  end
end

local function resolvedFrames(player, onBike)
  local base = (onBike and player.bikeStepFrames) or player.stepFrames or 16
  base = math.max(1, math.floor(finiteNumber(base, 16)))

  local save = Game.save
  local value = Runtime.call(
    "movement.speed",
    function(frames) return frames end,
    base,
    {
      onBike = onBike,
      surfing = player.surfing and true or false,
      player = player,
      input = Game.input,
      save = save,
      freeMove = true,
      continuous = true,
    }
  )
  value = finiteNumber(value, base)
  return base, math.max(1, math.floor(value))
end

return function(mod)
  defineOptions(mod)
  -- These are ordinary bag/battle features and must remain available even
  -- when the player is using 2D mode or has no supported voxel renderer.
  installInventoryFeatures(mod)
  installExperienceModes(mod)
  installBadgeFreeFieldMoves(mod)
  installFreeFlyImmediateFlight(mod)
  installPokemonFinalCacheCompatibility(mod)
  installGappedLand(mod)

  mod.exports.status = {
    active = false,
    reason = "no_supported_voxel_mod",
  }

  local voxelId, _, lib = findVoxelMod(mod)
  if not voxelId then
    mod.log:info("no supported voxel mod is active; bridge is idle")
    return
  end

  -- Running Shoes 0.2.2+ already carries its own integration for Dramatic
  -- Shape and Battle Art Voxel Fork. Let it remain the single owner there,
  -- otherwise the same multiplier would be applied twice.
  if lib._runningShoesHook then
    mod.exports.status = {
      active = false,
      voxel = voxelId,
      reason = "running_shoes_has_native_voxel_support",
    }
    mod.log:info("%s already has Running Shoes integration; bridge is idle", voxelId)
    return
  end

  if lib._voxelRunBridgeHook then
    mod.exports.status = {
      active = false,
      voxel = voxelId,
      reason = "already_installed",
    }
    mod.log:info("%s is already bridged", voxelId)
    return
  end

  if type(lib.require) ~= "function" then
    mod.exports.status.reason = "voxel_exports_missing_require"
    mod.log:warn("%s does not export its module loader", voxelId)
    return
  end

  local okModule, FreeMove = pcall(lib.require, "FreeMove")
  if not okModule or type(FreeMove) ~= "table"
      or type(FreeMove.tick) ~= "function" then
    mod.exports.status.reason = "voxel_freemove_unavailable"
    mod.log:warn("%s does not expose a compatible FreeMove module", voxelId)
    return
  end

  -- Running Shoes 1.7+ publishes its native voxel wrapper on FreeMove
  -- itself, not on the exported library table used by older integrations.
  -- Trust the paired ownership markers even when another mod subsequently
  -- wraps tick outside it: the shoes' wrapper is still in that call chain,
  -- and adding ours would apply the movement multiplier twice.
  if runningShoesOwnsFreeMove(FreeMove) then
    mod.exports.status = {
      active = false,
      voxel = voxelId,
      reason = "running_shoes_has_native_voxel_support",
    }
    mod.log:info("%s FreeMove is already owned by Running Shoes; bridge is idle",
      voxelId)
    return
  end

  local innerTick = FreeMove.tick
  local warnedSpeedError = false
  local delegatedToNativeShoes = false

  local function bridgedTick(state)
    -- MadeinTaly Running Shoes 1.7 attaches its native wrapper lazily from
    -- input.step, so the ownership markers can appear after this bridge was
    -- installed. In that ordering its wrapper sits outside ours and has
    -- already scaled FreeMove; become a pass-through before sampling the
    -- movement.speed hook or the same run would be multiplied twice.
    if runningShoesOwnsFreeMove(FreeMove) then
      if not delegatedToNativeShoes then
        delegatedToNativeShoes = true
        mod.exports.status = {
          active = false,
          voxel = voxelId,
          reason = "running_shoes_has_native_voxel_support",
        }
        mod.log:info("%s FreeMove gained native Running Shoes support; bridge is idle",
          voxelId)
      end
      return innerTick(state)
    elseif delegatedToNativeShoes then
      delegatedToNativeShoes = false
      mod.exports.status = {
        active = true,
        voxel = voxelId,
        mode = "movement.speed",
      }
      mod.log:info("%s native Running Shoes wrapper left; bridge resumed", voxelId)
    end

    local player = state and state.player

    -- FreeMove itself stands aside during scripted movement. Do the same
    -- before consulting speed hooks, so cutscenes and NPC-controlled walks
    -- cannot inherit a held run button through this bridge.
    if not player or player.moving or player.inputLocked then
      return innerTick(state)
    end

    -- With no producer there is nothing to translate. This path is hit by
    -- players who installed the bridge before choosing a running mod.
    if not Runtime.wantsHook("movement.speed") then
      return innerTick(state)
    end

    local save = Game.save
    local onBike = save and save.onBike and true or false
    local speedKey = onBike and "BIKE" or "WALK"
    local speedBefore = FreeMove[speedKey]
    if finiteNumber(speedBefore) ~= speedBefore or speedBefore <= 0 then
      return innerTick(state)
    end

    local baseFrames, effectiveFrames
    local okSpeed, speedErr = pcall(function()
      baseFrames, effectiveFrames = resolvedFrames(player, onBike)
    end)

    if not okSpeed then
      if not warnedSpeedError then
        warnedSpeedError = true
        mod.log:warn("movement.speed bridge failed; using voxel default: %s",
          tostring(speedErr))
      end
      return innerTick(state)
    end

    local multiplier = baseFrames / effectiveFrames
    FreeMove[speedKey] = speedBefore * multiplier

    local result
    local okTick, tickErr = xpcall(function()
      result = pack(innerTick(state))
    end, traceback)

    -- Never leak a temporary speed into a later frame or another mod, even
    -- when the wrapped voxel tick throws.
    FreeMove[speedKey] = speedBefore

    if not okTick then error(tickErr, 0) end
    return unpackValues(result, 1, result.n)
  end

  mod.exports.status = {
    active = true,
    voxel = voxelId,
    mode = "movement.speed",
  }
  mod.log:info("bridging movement.speed into %s FreeMove", voxelId)

  -- These raw assignments are the final installation actions. Keeping all
  -- validation and logging above them avoids leaving half an adapter behind
  -- if setup fails.
  rawset(FreeMove, "tick", bridgedTick)
  rawset(lib, "_voxelRunBridgeHook", {
    owner = mod.id,
    version = RELEASE_VERSION,
    original = innerTick,
  })
end
