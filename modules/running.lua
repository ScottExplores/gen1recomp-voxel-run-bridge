-- Scott-authored, always-available B-button running. The movement producer is
-- renderer-neutral; main.lua's public movement.speed bridge carries it into
-- compatible continuous voxel walkers.
-- The producer began with Scott Mod's MIT running module; the distance-based
-- camera dispatcher is new work. See THIRD_PARTY_NOTICES.md.

local Game = require("src.core.Game")

local VOXEL_IDS = {
  "POKEMON_FINAL",
  "DRAMATIC_SHAPE",
  "BATTLE_ART_VOXEL_FORK",
  "DRAMALESS_SHAPE",
  "potato_voxel",
}

local TAU = math.pi * 2
local STRIDE_DISTANCE = 22
local BASE_AMPLITUDE = 0.65
local BOB_TICK_MARKER = "_scottsTweaksRunningBobTick"
local BOB_FRAME_MARKER = "_scottsTweaksRunningBobFrame"
local unpackValues = table.unpack or unpack

local function pack(...)
  return { n = select("#", ...), ... }
end

local function traceback(err)
  if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
  return tostring(err)
end

local function finite(value, fallback)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge
      or value == -math.huge then return fallback end
  return value
end

local function pressed(input, key)
  if not (input and type(input.isDown) == "function") then return false end
  local ok, value = pcall(input.isDown, input, key)
  return ok and value == true
end

local function findVoxel(context)
  for _, id in ipairs(VOXEL_IDS) do
    local found = context and context.findMod and context.findMod(id) or nil
    local lib = found and found.exports and found.exports.lib
    if type(lib) == "table" and type(lib.require) == "function" then
      return id, lib
    end
  end
end

local function suspendOwnedBob(mod, context)
  local _, lib = findVoxel(context)
  if not lib then return false end
  local okMove, FreeMove = pcall(lib.require, "FreeMove")
  local okView, FirstPerson = pcall(lib.require, "FirstPerson")
  if not okMove or not okView or type(FreeMove) ~= "table"
      or type(FirstPerson) ~= "table" then return false end
  local tickOwner = rawget(FreeMove, BOB_TICK_MARKER)
  local frameOwner = rawget(FirstPerson, BOB_FRAME_MARKER)
  if type(tickOwner) ~= "table" or tickOwner.owner ~= mod.id
      or type(frameOwner) ~= "table" or frameOwner.owner ~= mod.id
      or tickOwner.state ~= frameOwner.state
      or type(tickOwner.state) ~= "table" then return false end
  tickOwner.state.active = false
  tickOwner.state.offset = 0
  return true
end

local function currentGeneration(state)
  local loader = Game and Game.mods or nil
  local exports = type(loader) == "table" and loader.exports or nil
  if type(exports) ~= "table" then return true end
  return exports[state.owner] == state.exports
end

return function(mod, context)
  -- Running Shoes owns the run multiplier wherever it is present, so the speed
  -- hook stands down to avoid applying it twice. The camera bob is a different
  -- feature and Running Shoes does not provide one, so it is installed either
  -- way -- bundling Running Shoes used to take the bob down with the speed hook
  -- and left first-person running with no bob at all.
  local speedDelegated = (context and context.findMod
    and context.findMod("running_shoes")) and true or false

  local settings = context and context.settings
  local function option(key, fallback)
    if settings then return settings:get(key, fallback) end
    if mod.options and type(mod.options.get) == "function" then
      local ok, value = pcall(mod.options.get, mod.options, key)
      if ok and value ~= nil then return value end
    end
    return fallback
  end
  local function enabled()
    return option("running_enabled", true) == true
  end
  local function wantsRun(ctx)
    if not enabled() or not ctx or ctx.onBike or ctx.surfing then return false end
    local player = ctx.player
    if player and (player.moving or player.inputLocked) then return false end
    return pressed(ctx.input, "b")
  end
  local function multiplier()
    return math.max(1, finite(option("running_speed", 1.5), 1.5))
  end

  if not speedDelegated then
    mod.hooks:wrap("movement.speed", function(nextFn, frames, ctx)
      local value = finite(nextFn(frames, ctx), frames)
      if not wantsRun(ctx) then return value end
      return math.max(1, math.floor(value / multiplier() + 0.5))
    end, 100)
  end

  local bobState = {
    active = true, phase = 0, offset = 0,
    wantsRun = wantsRun, option = option, game = Game,
    owner = mod.id, exports = mod.exports,
  }
  local bobStatus = { active = false, reason = "no_supported_voxel_mod" }

  local voxelId, lib = findVoxel(context)
  if voxelId then
    local okMove, FreeMove = pcall(lib.require, "FreeMove")
    local okView, FirstPerson = pcall(lib.require, "FirstPerson")
    if okMove and okView and type(FreeMove) == "table"
        and type(FreeMove.tick) == "function"
        and type(FirstPerson) == "table"
        and type(FirstPerson.frame) == "function" then
      local tickOwner = rawget(FreeMove, BOB_TICK_MARKER)
      local frameOwner = rawget(FirstPerson, BOB_FRAME_MARKER)
      if type(tickOwner) == "table" and tickOwner.owner == mod.id
          and type(frameOwner) == "table" and frameOwner.owner == mod.id
          and type(tickOwner.state) == "table"
          and tickOwner.state == frameOwner.state then
        -- Process-global renderer modules can outlive an F5 mod generation.
        -- Keep one owned dispatcher and refresh only its generation-local
        -- callbacks, so the old settings object is never retained as owner.
        bobState = tickOwner.state
        bobState.active = true
        bobState.wantsRun = wantsRun
        bobState.option = option
        bobState.game = Game
        bobState.owner = mod.id
        bobState.exports = mod.exports
        tickOwner.version = context and context.releaseVersion
        frameOwner.version = context and context.releaseVersion
        bobStatus = { active = true, voxel = voxelId,
          reason = "dispatcher_refreshed" }
      elseif tickOwner or frameOwner then
        bobStatus = { active = false, voxel = voxelId,
          reason = "camera_hook_owned" }
      else
        local innerTick = FreeMove.tick
        local innerFrame = FirstPerson.frame
        local shared = bobState

        local function bobTick(state, ...)
          local player = state and state.player
          local beforeX = finite(player and (player.px or player.x), nil)
          local beforeY = finite(player and (player.py or player.y), nil)
          local args = pack(...)
          local results
          local ok, err = xpcall(function()
            results = pack(innerTick(state,
              unpackValues(args, 1, args.n)))
          end, traceback)
          if not ok then error(err, 0) end

          if shared.active ~= true or not currentGeneration(shared) then
            shared.offset = 0
            return unpackValues(results, 1, results.n)
          end

          local afterX = finite(player and (player.px or player.x), nil)
          local afterY = finite(player and (player.py or player.y), nil)
          local runContext = {
            onBike = shared.game.save and shared.game.save.onBike == true,
            surfing = player and player.surfing == true,
            player = player,
            input = shared.game.input,
          }
          local dx = beforeX and afterX and afterX - beforeX or 0
          local dy = beforeY and afterY and afterY - beforeY or 0
          local distance = math.sqrt(dx * dx + dy * dy)
          if shared.wantsRun(runContext) and distance > 0 then
            shared.phase = (shared.phase + distance * TAU / STRIDE_DISTANCE) % TAU
            local strength = math.max(0,
              finite(shared.option("running_bob_intensity", 0.5), 0.5))
            -- One soft rise and fall per measured stride; a small second
            -- harmonic keeps the movement from feeling mechanically uniform.
            shared.offset = BASE_AMPLITUDE * strength
              * (math.sin(shared.phase) + 0.18 * math.sin(shared.phase * 2))
          else
            shared.offset = shared.offset * 0.55
            if math.abs(shared.offset) < 0.001 then shared.offset = 0 end
          end
          return unpackValues(results, 1, results.n)
        end

        local function bobFrame(me, ...)
          if shared.active == true and currentGeneration(shared) and me
              and shared.option("running_view_bob", true) == true
              and shared.offset ~= 0 then
            -- A proxy changes only this camera sample. The player's lift is
            -- never mutated, so collision, jumping and other renderers retain
            -- ownership of the actual world state.
            local camera = setmetatable({
              lift = finite(me.lift, 0) + shared.offset,
            }, { __index = me })
            return innerFrame(camera, ...)
          end
          return innerFrame(me, ...)
        end

        rawset(FreeMove, "tick", bobTick)
        rawset(FirstPerson, "frame", bobFrame)
        rawset(FreeMove, BOB_TICK_MARKER, {
          owner = mod.id, version = context and context.releaseVersion,
          wrapper = bobTick, original = innerTick, state = shared,
        })
        rawset(FirstPerson, BOB_FRAME_MARKER, {
          owner = mod.id, version = context and context.releaseVersion,
          wrapper = bobFrame, original = innerFrame, state = shared,
        })
        bobStatus = { active = true, voxel = voxelId,
          mode = "distance_based_first_person" }
      end
    else
      bobStatus = { active = false, voxel = voxelId,
        reason = "camera_modules_unavailable" }
    end
  end

  local feature = {
    installed = true,
    version = context and context.releaseVersion or "0.11.0",
    alwaysAvailable = true,
    speedDelegated = speedDelegated,
    speedProvider = speedDelegated and "running_shoes" or mod.id,
    bob = bobStatus,
    isRunning = function(ctx) return wantsRun(ctx) end,
    bobOffset = function() return bobState.offset end,
  }
  mod.exports.running = feature
  return feature
end
