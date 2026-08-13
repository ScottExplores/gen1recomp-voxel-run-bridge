-- Voxel Run Bridge
--
-- Gen1Recomp's public movement.speed hook is evaluated by the grid walker.
-- Voxel first/third-person modes replace that walker with FreeMove.tick, so
-- speed mods never reach those camera modes. This adapter asks the existing
-- movement.speed chain for the same effective step duration the grid walker
-- would use, then applies that ratio to FreeMove for one tick only.

local Runtime = require("src.mods.Runtime")
local Game = require("src.core.Game")

local unpackValues = table.unpack or unpack

local VOXEL_IDS = {
  "DRAMATIC_SHAPE",
  "BATTLE_ART_VOXEL_FORK",
  "DRAMALESS_SHAPE",
  "potato_voxel",
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

local function findVoxelMod(mod)
  for _, id in ipairs(VOXEL_IDS) do
    local found = mod.find(id)
    local lib = found and found.exports and found.exports.lib
    if type(lib) == "table" then return id, found, lib end
  end
  return nil
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
    version = "0.1.1",
    original = innerTick,
  })
end
