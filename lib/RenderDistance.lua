-- A conservative world-space draw/build budget for the voxel neighborhood.
--
-- Connected maps can be hundreds of world pixels away from the player even
-- though the engine keeps them in state.neighbors. Building and submitting
-- every one mattered less while the legacy FFI sink was available; current
-- sandboxed engines deliberately deny FFI, so avoiding work which cannot enter
-- the camera is the important replacement. The current map is never culled.

local V = ...

local ModSetting = V.require("ModSetting")
local RenderDistance = {}

-- Gen 1 cells are 16 world pixels. MEDIUM covers 32 cells in every direction,
-- comfortably beyond the stock view and the tilted camera; FULL is exact
-- legacy behavior for screenshots or unusually wide survey views.
RenderDistance.setting = ModSetting.new(
  "renderDistance", "R.DIST",
  { 16, 32, 64, false },
  { "SHORT", "MEDIUM", "FAR", "FULL" },
  2)

function RenderDistance.radius()
  local ok, cells = pcall(RenderDistance.setting.get, RenderDistance.setting)
  if not ok or cells == false then return nil end
  cells = tonumber(cells)
  if not cells then return nil end
  return math.max(16, math.min(64, cells)) * 16
end

local function playerPoint(player)
  if not player then return nil end
  local x = tonumber(player.px or player.x)
  local y = tonumber(player.py or player.y)
  local cellX, cellY = tonumber(player.cellX), tonumber(player.cellY)
  if x == nil and cellX ~= nil then x = cellX * 16 end
  if y == nil and cellY ~= nil then y = cellY * 16 end
  if x == nil or y == nil then return nil end
  return x + 8, y + 8
end

function RenderDistance.point(x, y, player)
  local radius = RenderDistance.radius()
  local px, py = playerPoint(player)
  if not radius or not px then return true end
  local dx, dy = (tonumber(x) or 0) - px, (tonumber(y) or 0) - py
  return dx * dx + dy * dy <= radius * radius
end

-- Distance from the player to the nearest point of a connected map's body.
-- A map whose seam is close remains eligible even when its origin is far away.
local function neighborDistanceSquared(nb, player)
  local px, py = playerPoint(player)
  if not px or not (nb and nb.map and nb.map.def) then return nil end
  local x0, y0 = tonumber(nb.ox) or 0, tonumber(nb.oy) or 0
  local x1 = x0 + (tonumber(nb.map.def.width) or 0) * 32
  local y1 = y0 + (tonumber(nb.map.def.height) or 0) * 32
  local dx = px < x0 and (x0 - px) or (px > x1 and (px - x1) or 0)
  local dy = py < y0 and (y0 - py) or (py > y1 and (py - y1) or 0)
  return dx * dx + dy * dy
end

local function neighborWithin(nb, player, radius)
  if not radius then return true end
  local distance = neighborDistanceSquared(nb, player)
  return distance == nil or distance <= radius * radius
end

function RenderDistance.neighbor(nb, player)
  return neighborWithin(nb, player, RenderDistance.radius())
end

-- Building must lead drawing in every voxel mode: the adjacent body needs to
-- be ready before the player reaches its seam, independent of camera angle or
-- current R.DIST. This changes only build timing; all draw passes keep using
-- neighbor() and therefore still obey the player's selected render distance.
function RenderDistance.prefetchNeighbor(nb)
  return nb ~= nil and nb.map ~= nil and nb.map.def ~= nil
end

-- All connected bodies start early, but the engine supplies two BFS hops in an
-- order derived from Lua table iteration. Rank the active build continuously
-- by physical distance so a direct seam cannot wait behind a large two-hop
-- route. Values stay below current-map priority 2 and above speculative 0.
function RenderDistance.prefetchPriority(nb, player)
  local squared = neighborDistanceSquared(nb, player)
  if squared == nil then return 1 end
  local scale = (RenderDistance.radius() or (32 * 16)) * 2
  local closeness = 1 - math.min(1, math.sqrt(squared) / scale)
  return 1 + closeness * 0.9
end

return RenderDistance
