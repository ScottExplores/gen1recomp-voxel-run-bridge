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
  })
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
  installBadgeFreeFieldMoves(mod)
  installFreeFlyImmediateFlight(mod)

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
    version = "0.2.2",
    original = innerTick,
  })
end
