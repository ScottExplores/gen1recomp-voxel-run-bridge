-- Procedural pixel hills beyond the loaded Kanto map.
--
-- Adapted from Kanto Dynamic Weather 1.0.3's DistantWorld.lua:
--   https://github.com/1-Camp0-1/Kanto-Dynamic-Weather
-- Copyright (c) 2026 1-Camp0-1, MIT licensed. The complete notice and
-- permission text are retained in THIRD_PARTY_NOTICES.md.
--
-- Scott's adaptation keeps the original layered ridge/parallax idea while
-- fitting the fused renderer's low-detail Gen 1 look. Silhouettes land on the
-- diorama pixel grid and are cached as five small, two-tile triangle meshes:
-- no concave polygon calls, no per-frame point-table garbage, and five bounded
-- land draws on a native-resolution AYN Thor. Camera yaw translates/wraps the
-- already-built meshes, so turning looks around one repeating horizon without
-- allocating a new Mesh at every stick sample. No image, Stadium model,
-- Gen 2 runtime, network request or extra canvas is involved.

local V = ...

local Sky = V.require("Sky")
local DayNight = V.require("DayNight")

local DistantWorld = {}

local sin, cos, floor, max, min = math.sin, math.cos, math.floor, math.max, math.min
local PI, PI2 = math.pi, math.pi * 2
local atan2 = math.atan2 or function(y, x)
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and PI or -PI) end
  if y > 0 then return PI * 0.5 end
  if y < 0 then return -PI * 0.5 end
  return 0
end

-- Quality ceilings, not targets. Wider canvases increase sample spacing
-- instead of increasing Lua work or vertex count without bound.
local MAX_RIDGE_COLUMNS = 48
local MAX_TREES_PER_BELT = 52

local cache = { key = nil, meshes = nil, builds = 0 }

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function mix(a, b, t)
  return a + (b - a) * t
end

local function mix3(a, b, t)
  return { clamp01(mix(a[1], b[1], t)),
           clamp01(mix(a[2], b[2], t)),
           clamp01(mix(a[3], b[3], t)) }
end

local function snap(v, cell)
  return floor(v / cell + 0.5) * cell
end

local function pushPoint(points, x, y)
  local n = #points
  if n >= 2 and points[n - 1] == x and points[n] == y then return end
  points[n + 1], points[n + 2] = x, y
end

-- Periodic deterministic ridge noise. Integer harmonics make a full 360-degree
-- camera turn land on precisely the same generated horizon again.
local function noise1(x, seed)
  local a = sin(x + seed * 1.73)
  local b = sin(x * 2 - seed * 3.11) * 0.46
  local c = cos(x * 3 + seed * 0.79) * 0.21
  return (a + b + c) / 1.67
end

-- Returns one x-monotone, stair-stepped top edge. The fill is triangulated
-- explicitly below; love.graphics.polygon never sees this concave silhouette.
local function ridgeLine(w, baseY, amp, wavelength, phase, seed, wantedStep,
                         cell)
  baseY, amp = snap(baseY, cell), snap(amp, cell)
  local points = {}
  local step = max(10, wantedStep or 22, w / MAX_RIDGE_COLUMNS)
  step = max(cell, snap(step, cell))
  local x = 0
  while x < w do
    local u = (x / max(w, 1)) * wavelength + phase
    local n = noise1(u, seed)
    local peak = 0.22 + 0.78 * (0.5 + n * 0.5)
    peak = peak * peak
    local y = snap(baseY - amp * peak, cell)
    local nextX = min(w, x + step)
    pushPoint(points, snap(x, cell), y)
    pushPoint(points, nextX == w and w or snap(nextX, cell), y)
    x = nextX
  end
  return points, baseY + cell
end

-- Returns one monotone forest skyline. Each crown is part of the same cached
-- mesh, while the explicit triangle strip below keeps the GPU input simple.
local function treeLine(w, baseY, height, phase, cell)
  baseY, height = snap(baseY, cell), max(cell * 2, snap(height, cell))
  local spacing = max(cell * 2, 7, height * 0.46,
                      w / MAX_TREES_PER_BELT)
  spacing = max(cell, snap(spacing, cell))
  local turns = phase / PI2
  local shift = snap(((turns * 3 * spacing) % spacing) - spacing, cell)
  local points = { 0, baseY }
  local x, i = shift, 0
  while x < w do
    i = i + 1
    local n = 0.72 + 0.28 * (0.5 + 0.5 * sin(i * 1.71 + phase * 2))
    local treeH = max(cell * 2, snap(height * n, cell))
    local treeW = min(spacing * 0.92,
                      treeH * (0.38 + 0.05 * sin(i * 2.17 + phase * 3)))
    treeW = max(cell * 2, snap(treeW, cell))
    local left, right = max(0, x), min(w, x + treeW)
    if right > left then
      local mid = snap((left + right) * 0.5, cell)
      local q1 = snap((left + mid) * 0.5, cell)
      local q3 = snap((mid + right) * 0.5, cell)
      pushPoint(points, snap(left, cell), baseY)
      pushPoint(points, q1, snap(baseY - treeH * 0.38, cell))
      pushPoint(points, mid, baseY - treeH)
      pushPoint(points, q3, snap(baseY - treeH * 0.42, cell))
      pushPoint(points, snap(right, cell), baseY)
    end
    x = x + spacing
  end
  pushPoint(points, w, baseY)
  return points, baseY + cell
end

local function releaseMeshes(meshes)
  for _, mesh in pairs(meshes or {}) do
    if mesh and mesh.release then pcall(mesh.release, mesh) end
  end
end

-- Turn an x-monotone skyline into independent quads (two triangles each)
-- down to a shallow base. Default 2D Mesh vertices are enough because this
-- pass temporarily unbinds the voxel shader and draws in canvas coordinates.
local function meshFromLine(g, points, bottom, tileWidth)
  local vertices = {}
  -- Two exact copies in one mesh. A single translated draw then always covers
  -- the canvas while its first tile slides out and its second slides in.
  for tile = 0, 1 do
    local dx = tile * tileWidth
    for i = 1, #points - 2, 2 do
      local x0, y0 = points[i] + dx, points[i + 1]
      local x1, y1 = points[i + 2] + dx, points[i + 3]
      if x1 > x0 then
        -- Four-value vertices use LOVE's standard 2D position/UV format; the
        -- untextured mesh ignores UV, but including it keeps old and new LOVE
        -- runtimes on the same well-tested newMesh overload.
        vertices[#vertices + 1] = { x0, y0, 0, 0 }
        vertices[#vertices + 1] = { x1, y1, 0, 0 }
        vertices[#vertices + 1] = { x1, bottom, 0, 0 }
        vertices[#vertices + 1] = { x0, y0, 0, 0 }
        vertices[#vertices + 1] = { x1, bottom, 0, 0 }
        vertices[#vertices + 1] = { x0, bottom, 0, 0 }
      end
    end
  end
  if #vertices < 3 then return nil end
  local ok, mesh = pcall(g.newMesh, vertices, "triangles", "static")
  return ok and mesh or nil
end

local function buildMeshes(g, w, h, edge, cell)
  local step = max(cell * 2, snap(w / 44, cell))
  local specs = {}
  specs.far, specs.farBottom = ridgeLine(
    w, edge + h * 0.025, h * 0.105, PI2 * 2,
    0.3, 2.6, step * 1.5, cell)
  specs.mid, specs.midBottom = ridgeLine(
    w, edge + h * 0.058, h * 0.077, PI2 * 3,
    1.8, 4.9, step, cell)
  specs.hills, specs.hillsBottom = ridgeLine(
    w, edge + h * 0.094, h * 0.043, PI2 * 4,
    3.7, 8.1, step * 0.75, cell)
  specs.forestFar, specs.forestFarBottom = treeLine(
    w, edge + h * 0.119, h * 0.026,
    0.6, cell)
  specs.forestNear, specs.forestNearBottom = treeLine(
    w, edge + h * 0.140, h * 0.038,
    2.2, cell)

  local meshes = {}
  for _, name in ipairs({ "far", "mid", "hills", "forestFar", "forestNear" }) do
    meshes[name] = meshFromLine(g, specs[name], specs[name .. "Bottom"], w)
    if not meshes[name] then
      releaseMeshes(meshes)
      return nil
    end
  end
  return meshes
end

local function meshesFor(g, w, h, edge, cell)
  local key = table.concat({ w, h, edge, cell }, ":")
  if cache.key == key and cache.meshes then return cache.meshes end

  local meshes = buildMeshes(g, w, h, edge, cell)
  if not meshes then return nil end
  releaseMeshes(cache.meshes)
  cache.key, cache.meshes = key, meshes
  cache.builds = cache.builds + 1
  return meshes
end

-- `edge` is the sky/horizon join in canvas pixels. `cx/cy` are the current
-- world focus and `viewX/viewZ` are Voxel3D.lookFlat. The very small position
-- shift provides parallax, while yaw rotates through a periodic generated
-- world. `cell` is the live displayed diorama-pixel size.
function DistantWorld.draw(w, h, edge, cx, cy, cell, viewX, viewZ)
  if not (w and h and w > 0 and h > 0) then return false end
  local g = love and love.graphics
  if not (g and g.setColor and g.rectangle and g.newMesh and g.draw) then
    return false
  end

  local bands = Sky.bands and Sky.bands() or nil
  if not (bands and bands[1]) then return false end
  cell = max(1, floor((cell or 1) + 0.5))
  edge = edge or (Sky.region and Sky.region(h, nil)) or h * (Sky.SPAN or 0.23)
  edge = snap(max(1, min(h * 0.55, edge)), cell)

  local meshes = meshesFor(g, w, h, edge, cell)
  if not meshes then return false end

  local haze = bands[#bands] or { 0.55, 0.72, 0.84 }
  local upper = bands[max(1, #bands - 1)] or haze
  local tint = (DayNight.tint and DayNight.tint(true)) or { 1, 1, 1 }
  local landBase = mix3(haze,
    { 0.22 * tint[1], 0.34 * tint[2], 0.24 * tint[3] }, 0.44)
  local farMount = mix3(haze,
    { 0.23 * tint[1], 0.30 * tint[2], 0.34 * tint[3] }, 0.34)
  local midMount = mix3(haze,
    { 0.16 * tint[1], 0.26 * tint[2], 0.24 * tint[3] }, 0.55)
  local hills = mix3(haze,
    { 0.12 * tint[1], 0.24 * tint[2], 0.16 * tint[3] }, 0.66)
  local forest = mix3(haze,
    { 0.055 * tint[1], 0.15 * tint[2], 0.075 * tint[3] }, 0.78)

  local oldShader = g.getShader and g.getShader() or nil
  local oldBlend, oldAlpha
  if g.getBlendMode then oldBlend, oldAlpha = g.getBlendMode() end
  local oldDepth, oldWrite
  if g.getDepthMode then oldDepth, oldWrite = g.getDepthMode() end
  if g.setShader then g.setShader() end
  if g.setBlendMode then g.setBlendMode("alpha", "alphamultiply") end
  if g.setDepthMode and oldDepth then g.setDepthMode("always", false) end

  local bandH = max(cell * 2, snap(h * 0.055, cell))
  for i = 0, 5 do
    local y0 = snap(edge + i * bandH, cell)
    local c = mix3(landBase, hills, (i / 5) * 0.72)
    g.setColor(c[1], c[2], c[3], 1)
    g.rectangle("fill", 0, y0, w,
                max(bandH + cell, snap(h - y0, cell)))
  end

  local yaw = atan2(viewZ or -1, viewX or 0)
  local heading = (yaw / PI2 % 1) * w
  local travel = (cx or 0) * 0.0041 + (cy or 0) * 0.0027
  local function offset(rate)
    return -(snap((heading + travel * rate * w / PI2) % w, cell) % w)
  end
  local function draw(mesh, color, alpha, rate)
    g.setColor(color[1], color[2], color[3], alpha or 1)
    g.draw(mesh, offset(rate), 0)
  end
  draw(meshes.far, farMount, 0.95, 0.055)
  draw(meshes.mid, midMount, 0.98, 0.095)
  draw(meshes.hills, hills, 1, 0.145)
  draw(meshes.forestFar, mix3(forest, haze, 0.24), 0.94, 0.19)
  draw(meshes.forestNear, forest, 1, 0.27)

  local veil = mix3(haze, upper, 0.20)
  g.setColor(veil[1], veil[2], veil[3], 0.16)
  g.rectangle("fill", 0, snap(edge - h * 0.006, cell), w,
              max(cell, snap(h * 0.032, cell)))

  g.setColor(1, 1, 1, 1)
  if g.setDepthMode and oldDepth then g.setDepthMode(oldDepth, oldWrite) end
  if g.setBlendMode and oldBlend then g.setBlendMode(oldBlend, oldAlpha) end
  if g.setShader then g.setShader(oldShader) end
  return true
end

function DistantWorld.invalidate()
  releaseMeshes(cache.meshes)
  cache.key, cache.meshes = nil, nil
end

DistantWorld.MAX_RIDGE_COLUMNS = MAX_RIDGE_COLUMNS
DistantWorld.MAX_TREES_PER_BELT = MAX_TREES_PER_BELT
DistantWorld._cacheStats = function()
  return cache.builds, cache.key, cache.meshes
end

return DistantWorld
