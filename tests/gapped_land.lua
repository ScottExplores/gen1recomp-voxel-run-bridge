-- Focused contract test for Scott's Tweaks' procedural GAPPED LAND layer.
-- Run from the mod root: lua tests/gapped_land.lua

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
local function has(list, wanted)
  for _, value in ipairs(list) do if value == wanted then return true end end
  return false
end

local Runtime = {}
function Runtime.wantsHook() return false end
function Runtime.call(_, vanilla, value, ctx) return vanilla(value, ctx) end

local Game = { save = { party = {} }, input = {} }
local Map = {}
function Map.isOutdoor(def) return def and def.outdoor == true or false end
function Map.isOutside() return false end
local FieldDefaults = {}
function FieldDefaults.field() return {} end

package.preload["src.mods.Runtime"] = function() return Runtime end
package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.Map"] = function() return Map end
package.preload["src.world.FieldDefaults"] = function() return FieldDefaults end

local entry = assert(loadfile("main.lua"))()

local function fixture(config)
  config = config or {}
  local calls = {
    draws = {}, events = {}, seams = {}, glass = {}, required = {},
    meshes = 0, textures = 0, invalidates = 0,
  }
  local control = { freeCam = true, begin = true }

  local Voxel3D = { focus = { 130, 0, 190 } }
  local originalBegin
  originalBegin = function()
    calls.events[#calls.events + 1] = "begin"
    if control.beginThrows then error("begin exploded") end
    return control.begin, "begin-extra"
  end
  Voxel3D.beginScene = originalBegin
  function Voxel3D.newMesh(verts, indices)
    calls.meshes = calls.meshes + 1
    local mesh = { verts = verts, indices = indices, released = false }
    function mesh:release() self.released = true end
    calls.lastMesh = mesh
    return mesh
  end
  function Voxel3D.draw(mesh, texture, model)
    if control.drawThrows then error("draw exploded") end
    calls.events[#calls.events + 1] = "gap"
    calls.draws[#calls.draws + 1] = {
      mesh = mesh, texture = texture, model = model,
    }
  end
  function Voxel3D.seams(value) calls.seams[#calls.seams + 1] = value end
  function Voxel3D.glass(value) calls.glass[#calls.glass + 1] = value end
  local originalInvalidate
  originalInvalidate = function()
    calls.invalidates = calls.invalidates + 1
    if control.invalidateThrows then error("invalidate exploded") end
    return "invalidated", 17
  end
  Voxel3D.invalidate = originalInvalidate

  local VoxelScene = {}
  local originalRender
  originalRender = function(state, ...)
    local began = Voxel3D.beginScene(...)
    if not began then return nil, "not-started" end
    if control.renderThrows then error("render exploded") end
    calls.events[#calls.events + 1] = "terrain"
    return "canvas", 99
  end
  VoxelScene.render = originalRender

  local Voxel = {}
  function Voxel.isFreeCam() return control.freeCam end
  local DayNight = {}
  function DayNight.isCanopy(map) return map and map.canopy == true end
  local Mat4 = {}
  function Mat4.translate(x, y, z) return { x = x, y = y, z = z } end
  local FreeMove = { WALK = 1, BIKE = 2 }
  function FreeMove.tick() return "tick" end

  local modules = {
    VoxelScene = VoxelScene, Voxel3D = Voxel3D, VoxelState = Voxel,
    DayNight = DayNight, Mat4 = Mat4, FreeMove = FreeMove,
  }
  if config.missingModule then modules[config.missingModule] = nil end
  if config.missingDraw then Voxel3D.draw = nil end
  local lib = {}
  function lib.require(name)
    calls.required[#calls.required + 1] = name
    if modules[name] == nil then error("missing " .. name) end
    return modules[name]
  end
  local provider = {
    version = config.version or "1.8.2",
    exports = config.missingRequire and { lib = {} } or { lib = lib },
  }

  local values, schema = {}, nil
  local options = {}
  function options:define(rows)
    schema = rows
    for _, row in ipairs(rows) do
      if values[row.key] == nil then values[row.key] = row.default end
    end
  end
  function options:get(key) return values[key] end
  local hooks = {}
  function hooks:wrap() return function() end end
  local events = {}
  function events:on() end
  local logs = {}
  local log = {}
  function log:info(message) logs[#logs + 1] = message end
  function log:warn(message) logs[#logs + 1] = message end
  local mod = {
    id = "voxel_run_bridge", exports = {}, options = options, hooks = hooks,
    events = events, log = log,
  }
  function mod.find(id)
    if not config.noProvider and id == (config.providerId or "POKEMON_FINAL") then
      return provider
    end
  end

  if config.foreignMarker then
    VoxelScene._scottsTweaksGappedLandRenderHook = { owner = "foreign" }
  end

  local oldLove = love
  love = {
    image = {
      newImageData = function(w, h)
        local data = { w = w, h = h, pixels = 0, released = false }
        function data:setPixel() self.pixels = self.pixels + 1 end
        function data:release() self.released = true end
        calls.imageData = data
        return data
      end,
    },
    graphics = {
      newImage = function(data)
        calls.textures = calls.textures + 1
        local texture = { data = data, released = false }
        function texture:setFilter(a, b) self.filter = { a, b } end
        function texture:setWrap(a, b) self.wrap = { a, b } end
        function texture:release() self.released = true end
        calls.lastTexture = texture
        return texture
      end,
    },
  }

  entry(mod)
  return {
    mod = mod, calls = calls, control = control, values = values,
    schema = function() return schema end, Voxel3D = Voxel3D,
    VoxelScene = VoxelScene, originalBegin = originalBegin,
    originalRender = originalRender, originalInvalidate = originalInvalidate,
    oldLove = oldLove,
  }
end

local function outdoorState(id, extra)
  local map = {
    id = id or "PALLET_TOWN",
    def = { outdoor = true, tileset = "OVERWORLD", width = 20, height = 18 },
    collision = { 1, 2, 3 },
  }
  for key, value in pairs(extra or {}) do
    if key == "def" then
      for dk, dv in pairs(value) do map.def[dk] = dv end
    else
      map[key] = value
    end
  end
  return { map = map, player = { px = 120, py = 180 }, neighbors = {} }
end

local ctx = fixture()
local gapRow
for _, row in ipairs(ctx.schema()) do
  if row.key == "gapped_land" then gapRow = row end
end
check(gapRow ~= nil, "GAPPED LAND option is registered")
eq(gapRow.type, "toggle", "GAPPED LAND option type")
eq(gapRow.default, true, "GAPPED LAND default")
eq(ctx.mod.exports.gappedLand.active, true, "adapter active")
eq(ctx.mod.exports.gappedLand.reason, "attached", "adapter status reason")
eq(ctx.mod.exports.gappedLand.mode, "visual_apron", "adapter mode")
eq(ctx.mod.exports.gappedLand.voxel, "POKEMON_FINAL", "adapter provider")

local state = outdoorState()
local collision = state.map.collision
local neighbors = state.neighbors
local first, second = ctx.VoxelScene.render(state, 320, 180, 320, 180)
eq(first, "canvas", "render first return")
eq(second, 99, "render second return")
eq(ctx.calls.events[1], "begin", "scene begins first")
eq(ctx.calls.events[2], "gap", "visual apron precedes terrain")
eq(ctx.calls.events[3], "terrain", "native terrain follows apron")
eq(#ctx.calls.draws, 1, "one apron draw")
eq(#ctx.calls.lastMesh.verts, 4096, "tessellated apron vertex count")
eq(#ctx.calls.lastMesh.indices, 6144, "tessellated apron index count")
eq(ctx.calls.draws[1].model.x, 128, "apron x is cell-snapped")
eq(ctx.calls.draws[1].model.y, -40, "apron is below native Flora apron")
eq(ctx.calls.draws[1].model.z, 128, "apron z is cell-snapped")
eq(ctx.calls.imageData.pixels, 64, "procedural texture pixels")
eq(ctx.calls.lastTexture.wrap[1], "repeat", "procedural texture wrap x")
eq(ctx.calls.lastTexture.wrap[2], "repeat", "procedural texture wrap y")
eq(ctx.calls.seams[1], false, "beginScene seam default temporarily disabled")
eq(ctx.calls.seams[2], true, "beginScene seam default restored")
eq(ctx.calls.glass[1], false, "beginScene glass default temporarily disabled")
eq(ctx.calls.glass[2], true, "beginScene glass default restored")
eq(state.map.collision, collision, "collision identity unchanged")
eq(state.neighbors, neighbors, "connection list identity unchanged")
check(not has(ctx.calls.required, "ChunkMesher"), "disk/cache mesher is untouched")

local function noDraw(label, candidate)
  local before = #ctx.calls.draws
  ctx.VoxelScene.render(candidate or outdoorState(), 1, 1, 1, 1)
  eq(#ctx.calls.draws, before, label)
end

ctx.values.gapped_land = false
noDraw("live toggle disables draw")
ctx.values.gapped_land = true
ctx.control.freeCam = false
noDraw("non-1ST/3RD camera is skipped")
ctx.control.freeCam = true
noDraw("interior is skipped", outdoorState("HOUSE", { def = { outdoor = false } }))
noDraw("canopy is skipped", outdoorState("VIRIDIAN_FOREST", { canopy = true }))
noDraw("ship port is skipped", outdoorState("VERMILION_DOCK", {
  def = { tileset = "SHIP_PORT" },
}))
for _, id in ipairs({ "CINNABAR_ISLAND", "ROUTE_19", "ROUTE_20", "ROUTE_21" }) do
  noDraw(id .. " sea horizon is skipped", outdoorState(id))
end

ctx.control.begin = false
noDraw("failed beginScene is skipped")
ctx.control.begin = true
local drawBeforeError = #ctx.calls.draws
ctx.control.renderThrows = true
local okRender = pcall(ctx.VoxelScene.render, outdoorState(), 1, 1, 1, 1)
eq(okRender, false, "provider render error propagates")
eq(ctx.Voxel3D.beginScene, ctx.originalBegin, "frame interception restores on error")
eq(#ctx.calls.draws, drawBeforeError + 1, "apron still drew before later render error")
ctx.control.renderThrows = false

local mesh, texture = ctx.calls.lastMesh, ctx.calls.lastTexture
local invA, invB = ctx.Voxel3D.invalidate("token")
eq(invA, "invalidated", "invalidate first return")
eq(invB, 17, "invalidate second return")
eq(mesh.released, true, "invalidate releases apron mesh")
eq(texture.released, true, "invalidate releases apron texture")
ctx.VoxelScene.render(outdoorState(), 1, 1, 1, 1)
eq(ctx.calls.meshes, 2, "apron mesh rebuilds after invalidate")
eq(ctx.calls.textures, 2, "apron texture rebuilds after invalidate")

local installedRender = ctx.VoxelScene.render
entry(ctx.mod)
eq(ctx.mod.exports.gappedLand.active, true, "duplicate install remains active")
eq(ctx.mod.exports.gappedLand.reason, "already_installed", "duplicate install status")
eq(ctx.VoxelScene.render, installedRender, "duplicate install does not nest renderer")
eq(ctx.mod.exports.gappedLand.restore(), true, "owned hooks restore")
eq(ctx.VoxelScene.render, ctx.originalRender, "renderer restored")
eq(ctx.Voxel3D.invalidate, ctx.originalInvalidate, "invalidate restored")
eq(ctx.mod.exports.gappedLand.reason, "restored", "restore status")

local noProvider = fixture({ noProvider = true })
eq(noProvider.mod.exports.gappedLand.reason, "no_supported_voxel_mod",
  "no-provider status")
local missingRequire = fixture({ missingRequire = true })
eq(missingRequire.mod.exports.gappedLand.reason, "voxel_exports_missing_require",
  "missing-loader status")
local missingModule = fixture({ missingModule = "DayNight" })
eq(missingModule.mod.exports.gappedLand.reason,
  "exported_scene_modules_unavailable", "missing-module status")
local foreign = fixture({ foreignMarker = true })
eq(foreign.mod.exports.gappedLand.reason, "renderer_hook_owned_by_another_mod",
  "foreign-owner status")
eq(foreign.VoxelScene.render, foreign.originalRender,
  "foreign renderer is not replaced")
local dramatic = fixture({ providerId = "DRAMATIC_SHAPE", version = "1.8.0" })
eq(dramatic.mod.exports.gappedLand.active, true, "Dramatic Shape capability contract")
eq(dramatic.mod.exports.gappedLand.providerVersion, "1.8.0",
  "provider version is diagnostic, not a gate")

print(("gapped land tests passed (%d checks)"):format(checks))
