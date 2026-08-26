-- Focused ROM-free contract for HORIZON ART -> PIXEL HILLS.
-- Run from the mod root:
--   lua tests/pixel_hills.lua .
--   luajit tests/pixel_hills.lua .

local argv = rawget(_G, "arg") or {}
local root = argv[1] or "."

local checks = 0
local function check(value, label)
  checks = checks + 1
  if not value then error(label, 2) end
end
local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(
      label, tostring(expected), tostring(actual)), 2)
  end
end

-- The real generated layer: high-resolution Thor-sized input must retain a
-- fixed number of GPU calls and pixel-grid coordinates without loading art.
local meshBuilds, meshDraws, rectangles = {}, {}, {}
local depthModes, shaderSets, releases = {}, {}, 0
local originalShader = {}
local g = {}
function g.getShader() return originalShader end
function g.setShader(shader) shaderSets[#shaderSets + 1] = shader end
function g.getBlendMode() return "alpha", "alphamultiply" end
function g.setBlendMode() end
function g.getDepthMode() return "lequal", true end
function g.setDepthMode(mode, write)
  depthModes[#depthModes + 1] = { mode, write }
end
function g.setColor() end
function g.rectangle(mode, x, y, w, h)
  rectangles[#rectangles + 1] = { mode, x, y, w, h }
end
function g.newMesh(vertices, mode, usage)
  local mesh = { vertices = vertices, mode = mode, usage = usage }
  function mesh:release() releases = releases + 1 end
  meshBuilds[#meshBuilds + 1] = mesh
  return mesh
end
function g.draw(mesh, x, y)
  meshDraws[#meshDraws + 1] = { mesh = mesh, x = x or 0, y = y or 0 }
end

_G.love = { graphics = g }
local modules = {
  Sky = {
    SPAN = 0.23,
    bands = function()
      return {
        { 0.11, 0.19, 0.38 }, { 0.22, 0.40, 0.65 },
        { 0.43, 0.64, 0.82 }, { 0.68, 0.82, 0.91 },
      }
    end,
    region = function(h) return h * 0.23 end,
  },
  DayNight = { tint = function() return { 0.72, 0.78, 0.88 } end },
}
local DistantWorld = assert(loadfile(root .. "/lib/DistantWorld.lua"))({
  require = function(name)
    assert(modules[name], "unexpected DistantWorld dependency: " .. name)
    return modules[name]
  end,
})

local cell = 4
check(DistantWorld.draw(1920, 1080, 244, 1234, -432, cell, 0, -1),
  "procedural layer draws without images, canvases or model assets")
eq(#rectangles, 7, "six depth strips plus one atmospheric veil")
eq(#meshBuilds, 5, "three ridges plus two forest belts build once")
eq(#meshDraws, 5, "five cached land layers need five bounded draws")
eq(depthModes[1][1], "always", "screen-space hills ignore stale scene depth")
eq(depthModes[1][2], false, "hills never write depth")
eq(depthModes[#depthModes][1], "lequal", "scene depth mode is restored")
eq(depthModes[#depthModes][2], true, "scene depth write flag is restored")
eq(shaderSets[#shaderSets], originalShader, "scene shader is restored")

local maxVertices = 0
for _, mesh in ipairs(meshBuilds) do
  eq(mesh.mode, "triangles", "concave skylines become explicit triangles")
  eq(mesh.usage, "static", "cached horizon geometry is immutable")
  eq(#mesh.vertices % 3, 0, "every cached mesh contains complete triangles")
  maxVertices = math.max(maxVertices, #mesh.vertices)
  local finite, aligned, neutralUV = true, true, true
  for _, vertex in ipairs(mesh.vertices) do
    for i, coordinate in ipairs(vertex) do
      finite = finite and type(coordinate) == "number"
               and coordinate == coordinate
               and coordinate > -math.huge and coordinate < math.huge
      if i <= 2 then
        local grid = coordinate / cell
        aligned = aligned
                  and math.abs(grid - math.floor(grid + 0.5)) < 0.000001
      else
        neutralUV = neutralUV and coordinate == 0
      end
    end
  end
  check(finite, "horizon coordinates stay finite")
  check(aligned, "silhouette positions land on the diorama pixel grid")
  check(neutralUV, "untextured standard-mesh UVs stay neutral")
end
check(maxVertices <= DistantWorld.MAX_TREES_PER_BELT * 60 + 24,
  "two-tile triangle mesh stays Thor-bounded")

local builds = DistantWorld._cacheStats()
eq(builds, 1, "first draw performs one five-mesh geometry build")
check(DistantWorld.draw(1920, 1080, 244, 1300, -400, cell, 1, 0),
  "travel and a 90-degree camera turn reuse cached geometry")
eq(#meshBuilds, 5, "camera movement allocates no replacement meshes")
eq(#meshDraws, 10, "cached meshes still render after a camera turn")
eq(DistantWorld._cacheStats(), 1,
  "camera yaw and travel are draw translations, not cache keys")
check(meshDraws[1].x ~= meshDraws[6].x,
  "turning the camera rotates the wrapped horizon")
check(meshDraws[6].x <= 0 and meshDraws[6].x > -1920,
  "wrapped yaw translation keeps the doubled mesh over the screen")
DistantWorld.invalidate()
eq(releases, 5, "invalidation releases all five cached GPU meshes")
local _, invalidKey, invalidMeshes = DistantWorld._cacheStats()
eq(invalidKey, nil, "invalidation clears the geometry cache key")
eq(invalidMeshes, nil, "invalidation clears the cached mesh set")

-- The existing setting row gains one value; all four painted choices retain
-- their exact path mapping, while generated art performs no filesystem read.
local selected, reads = "VALLEY", {}
local fakeMod = {
  id = "voxel_run_bridge", exports = {},
  options = { get = function(_, key)
    if key == "horizonart" then return selected end
    return nil
  end },
}
function fakeMod:read(path)
  reads[#reads + 1] = path
  return "present"
end
local ScottKanto = assert(loadfile(root .. "/lib/ScottKanto.lua"))({
  mod = fakeMod, path = "C:/staged/scotts-tweaks",
})

local horizonRow
for _, row in ipairs(ScottKanto.optionRows()) do
  if row.key == "horizonart" then horizonRow = row end
end
check(horizonRow ~= nil, "HORIZON ART row remains present")
eq(#horizonRow.choices, 5, "PIXEL HILLS extends rather than replaces art")
local values = {}
for _, choice in ipairs(horizonRow.choices) do values[choice[2]] = choice[1] end
for _, original in ipairs({ "KANTO", "FUJI", "VALLEY", "CITY" }) do
  eq(values[original], original, original .. " panorama remains selectable")
end
eq(values.PIXEL_HILLS, "PIXEL HILLS", "generated choice has the requested label")

selected, reads = "PIXEL_HILLS", {}
_G.__ds_backdrop_path = "stale.png"
ScottKanto.refreshPaths(true)
eq(#reads, 0, "PIXEL HILLS does not probe panorama files")
eq(rawget(_G, "__ds_backdrop_path"), nil,
  "generated art publishes no fake texture path")
ScottKanto.refreshPaths()
eq(#reads, 0, "generated nil path is cached on ordinary HUD frames")

local expectedArt = {
  KANTO = "backdrop.png", FUJI = "backdrop2.png",
  VALLEY = "backdrop3.png", CITY = "backdrop4.png",
}
for choice, file in pairs(expectedArt) do
  selected = choice
  ScottKanto.refreshPaths(true)
  eq(rawget(_G, "__ds_backdrop_path"),
    "C:/staged/scotts-tweaks/lib/" .. file,
    choice .. " keeps its original panorama path")
end

-- Backdrop remains the single config/outdoor gate and dispatches the new
-- choice without touching its image/mesh path.
local distantCalls, meshCalls = {}, 0
local backdropModules = {
  Voxel3D = {
    skyEdge = 88, cell = 3, lookFlat = { 1, 0, 0 },
    size = function() return 640, 360 end,
    pushQuad = function() error("panorama mesh path should be bypassed") end,
    newMesh = function() meshCalls = meshCalls + 1 end,
    draw = function() error("panorama draw path should be bypassed") end,
  },
  Mat4 = { translate = function() return {} end },
  DistantWorld = { draw = function(...)
    distantCalls[#distantCalls + 1] = { ... }
    return true
  end },
  DayNight = { isCanopy = function() return false end },
}
local Backdrop = assert(loadfile(root .. "/lib/Backdrop.lua"))({
  path = "C:/staged/scotts-tweaks",
  require = function(name)
    assert(backdropModules[name], "unexpected Backdrop dependency: " .. name)
    return backdropModules[name]
  end,
})
function g.push() end
function g.pop() end
_G.__ds_ceiling_config = function()
  return { backdrop = true, horizonart = "PIXEL_HILLS" }
end
Backdrop.draw({
  map = { def = { tileset = "OVERWORLD" } },
  player = { px = 96, py = 144 },
})
eq(#distantCalls, 1, "Backdrop dispatches PIXEL HILLS exactly once")
eq(distantCalls[1][1], 640, "dispatch supplies current canvas width")
eq(distantCalls[1][2], 360, "dispatch supplies current canvas height")
eq(distantCalls[1][3], 88, "dispatch supplies the current sky edge")
eq(distantCalls[1][4], 96, "dispatch supplies player east/west focus")
eq(distantCalls[1][5], 144, "dispatch supplies player north/south focus")
eq(distantCalls[1][6], 3, "dispatch supplies the live diorama pixel size")
eq(distantCalls[1][7], 1, "dispatch supplies camera look X")
eq(distantCalls[1][8], 0, "dispatch supplies camera look Z")
eq(meshCalls, 0, "generated art never allocates the panorama mesh")
check((rawget(_G, "__ds_backdrop_status") or ""):find("PIXEL HILLS", 1, true),
  "debug status identifies the active generated horizon")

-- The executable sequencing seam proves atmospheric art cannot be painted on
-- top of opaque pixel land, without altering the legacy panorama order.
local HorizonLayers = assert(loadfile(root .. "/lib/HorizonLayers.lua"))()
local order = {}
local orderedBackdrop = {
  usesPixelHills = function() return true end,
  draw = function() order[#order + 1] = "hills" end,
}
local orderedSky = { draw = function() order[#order + 1] = "sky" end }
local orderedUnderlay = {
  draw = function() order[#order + 1] = "underlay" end,
}
eq(HorizonLayers.draw(orderedBackdrop, orderedSky, orderedUnderlay,
  {}, 0, 0, {}), "PIXEL_HILLS", "generated ordering branch is selected")
eq(table.concat(order, ","), "sky,hills,underlay",
  "PIXEL HILLS draws after atmosphere and before depth underlay")

order = {}
orderedBackdrop.usesPixelHills = function() return false end
eq(HorizonLayers.draw(orderedBackdrop, orderedSky, orderedUnderlay,
  {}, 0, 0, {}), "PANORAMA", "legacy ordering branch is selected")
eq(table.concat(order, ","), "underlay,hills,sky",
  "painted panoramas preserve their exact original layer order")

_G.__ds_backdrop_path = nil
_G.__ds_ceiling_config = nil
_G.__ds_backdrop_status = nil
_G.love = nil

print(("pixel hills: %d checks passed"):format(checks))
