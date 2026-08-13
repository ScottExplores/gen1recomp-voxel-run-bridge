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

local SKY_RIDE_ID = "DRAMATIC_SKY_RIDE"
local SKY_RIDE_OPTION = "sky_ride_without_badges"

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
      key = SKY_RIDE_OPTION,
      type = "toggle",
      label = "SKY RIDE NOW",
      default = true,
      help = "Let Dramatic Sky Ride take off without THUNDERBADGE. REQUIRE FLY and STORY GATES stay under Sky Ride's control.",
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

-- Dramatic Sky Ride 0.1.6+ deliberately performs its badge test outside the
-- engine's fieldmove.eligibility hook. Its public flightRules.badgeChecks
-- export lets us feature-detect that implementation, while the value it and
-- the private startFlight wrapper actually read lives in the loader's
-- per-mod option table. Override only that one runtime value: no badge, move,
-- story flag or persisted DSR preference is edited.
local function installDramaticSkyRideImmediateFlight(mod)
  local state = {
    active = false,
    reason = "dramatic_sky_ride_not_active",
  }
  local activeLoader
  local priorSet = false
  local priorValue
  local priorBucketExisted = false

  local function findSkyRide()
    if type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, SKY_RIDE_ID)
    if not ok then ok, handle = pcall(mod.find, mod, SKY_RIDE_ID) end
    if ok then return handle end
    return nil
  end

  local function compatible(handle)
    local rules = handle and handle.exports and handle.exports.flightRules
    if type(rules) ~= "table" or type(rules.badgeChecks) ~= "function" then
      return false
    end
    return pcall(rules.badgeChecks)
  end

  local function restore()
    local loader = activeLoader
    local buckets = loader and loader.modOptions
    local bucket = buckets and buckets[SKY_RIDE_ID]
    if bucket then
      if priorSet then
        bucket.badge_checks = priorValue
      else
        bucket.badge_checks = nil
      end
      if not priorBucketExisted and next(bucket) == nil then
        buckets[SKY_RIDE_ID] = nil
      end
    end
    activeLoader = nil
    priorSet, priorValue, priorBucketExisted = false, nil, false
    state.active = false
    state.reason = "disabled"
  end

  local function apply(loader)
    if not optionEnabled(mod, SKY_RIDE_OPTION, true) then
      if activeLoader then restore() end
      state.reason = "disabled"
      return false
    end

    local handle = findSkyRide()
    if not handle then
      state.active = false
      state.reason = "dramatic_sky_ride_not_active"
      return false
    end
    if not compatible(handle) then
      state.active = false
      state.reason = "unsupported_dramatic_sky_ride"
      mod.log:warn("Dramatic Sky Ride does not expose the supported badge-check adapter")
      return false
    end
    if type(loader) ~= "table" then
      state.active = false
      state.reason = "loader_unavailable"
      return false
    end

    loader.modOptions = loader.modOptions or {}
    local bucket = loader.modOptions[SKY_RIDE_ID]
    if activeLoader ~= loader then
      priorBucketExisted = bucket ~= nil
      bucket = bucket or {}
      loader.modOptions[SKY_RIDE_ID] = bucket
      priorSet = bucket.badge_checks ~= nil
      priorValue = bucket.badge_checks
      activeLoader = loader
    else
      bucket = bucket or {}
      loader.modOptions[SKY_RIDE_ID] = bucket
    end
    bucket.badge_checks = false
    state.active = true
    state.reason = "badge_checks_runtime_override"
    state.version = handle.version
    return true
  end

  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("mods.loaded", function(payload)
      apply(payload and payload.loader or Game.mods)
    end)
    mod.events:on("mod.options_changed", function(payload)
      if not payload then return end
      if payload.mod == mod.id and payload.key == SKY_RIDE_OPTION then
        if payload.value == true then apply(Game.mods) else restore() end
      elseif state.active and payload.mod == SKY_RIDE_ID
          and payload.key == "badge_checks" then
        -- Keep the player's latest DSR preference ready for restoration if
        -- Scott's override is later switched off, but hold the live answer
        -- false while the override remains enabled.
        priorSet = payload.value ~= nil
        priorValue = payload.value
        local buckets = activeLoader and activeLoader.modOptions
        local bucket = buckets and buckets[SKY_RIDE_ID]
        if bucket then bucket.badge_checks = false end
      end
    end)
  end

  apply(Game.mods)

  mod.exports.skyRideBadgeBypass = function()
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
  installDramaticSkyRideImmediateFlight(mod)

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

  local innerTick = FreeMove.tick
  local warnedSpeedError = false

  local function bridgedTick(state)
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
    version = "0.2.1",
    original = innerTick,
  })
end
