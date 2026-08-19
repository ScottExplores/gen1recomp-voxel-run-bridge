-- Visual blackout for destination loads which cannot safely reveal a partly
-- generated voxel scene. Ordinary doors, stairs, caves and map connections do
-- not use it: only Continue/boot and explicit travel moves (Fly, Teleport, Dig
-- and Escape Rope) arm the gate.

local V = ...

local Gate = {
  HOLD_SECONDS = 0.5,
  -- A corrupt cache record, unsupported neighbour or driver failure must never
  -- turn a presentation effect into a soft lock. Healthy builds normally clear
  -- in a fraction of this; after the ceiling the engine's 2D world is safer.
  MAX_SECONDS = 20,
}

local active = false
local map = nil
local targetId = nil
local ready = false
local elapsed = 0

function Gate.qualifies(opts, arrival)
  local via = opts and opts.via
  return via == "boot" or via == "fly"
         or arrival == "fly" or arrival == "teleport"
end

local function voxelEnabled()
  local Voxel = V.require("VoxelState")
  local Voxel3D = V.require("Voxel3D")
  return Voxel.active() and Voxel3D.available()
end

function Gate.arm(destinationOrId)
  if not destinationOrId then return end
  map = type(destinationOrId) == "table" and destinationOrId or nil
  targetId = map and map.id or destinationOrId
  active = true
  ready = false
  elapsed = 0
end

-- startWarpTo arms before the engine's fade and before the destination Map
-- object exists. Bind that object at setMap without restarting the clock.
function Gate.bind(destination)
  if not destination then return end
  if active and tostring(targetId) == tostring(destination.id) then
    map = destination
  end
end

function Gate.cancel(destination)
  if destination ~= nil and destination ~= map then return end
  active, map, targetId, ready, elapsed = false, nil, nil, false, 0
end

function Gate.observe(destination, isReady)
  if not active or destination ~= map then return end
  if isReady then
    ready = true
  else
    ready = false
  end
end

function Gate.update(dt, enabled, destination)
  if not active then return end
  if not enabled then
    Gate.cancel()
    return
  end
  elapsed = elapsed + math.max(0, dt or 0)
  if elapsed >= Gate.MAX_SECONDS then
    Gate.cancel()
    return
  end
  if ready and elapsed >= Gate.HOLD_SECONDS then
    Gate.cancel()
  end
end

function Gate.blocking(destination)
  -- Once a qualifying transition begins, cover whichever world the engine is
  -- currently drawing: initially the departing map, then the bound destination.
  return active
end

function Gate.install()
  local OverworldState = require("src.world.OverworldController")
  if OverworldState.dramaticShapeVoxelTransitionGate then return end

  local startWarpTo = OverworldState.startWarpTo
  function OverworldState:startWarpTo(mapId, x, y, facing, onDone, opts)
    -- startWarpTo consumes and clears arriveWarp, so inspect it before the
    -- engine call. Dig, Teleport and Escape Rope all arrive as "teleport".
    local arrival = self.arriveWarp
    if voxelEnabled() and Gate.qualifies(opts, arrival) then
      Gate.arm(mapId)
    end
    return startWarpTo(self, mapId, x, y, facing, onDone, opts)
  end

  local setMap = OverworldState.setMap
  function OverworldState:setMap(mapId, x, y, facing, opts)
    local boot = voxelEnabled() and Gate.qualifies(opts, nil)
    if boot then Gate.arm(mapId) end
    local result = setMap(self, mapId, x, y, facing, opts)
    -- A travel move was armed by startWarpTo; boot was armed just above.
    -- bind() deliberately ignores every unrelated ordinary destination.
    if voxelEnabled() then Gate.bind(self.map) end
    return result
  end

  OverworldState.dramaticShapeVoxelTransitionGate = true
end

-- Test-only state reset; harmless to expose and useful to keep the module's
-- temporal contract deterministic in the headless SDK suite.
function Gate._reset()
  Gate.cancel()
end

return Gate
