-- Loads the real terrain provider against current Gen1Recomp Gen-2 classes.
-- No ROM, game/save mutation, or GPU frame is required.
--   luajit tests/gen2_voxel_headless.lua <mod-root> <engine-root>

local argv = rawget(_G, "arg") or {}
local root = assert(argv[1], "Scott's Tweaks source root required")
local engine = assert(argv[2], "Gen1Recomp engine root required")

package.path = engine .. "/?.lua;" .. engine .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function eq(actual, expected, message)
  checks = checks + 1
  assert(actual == expected,
    ("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
end

local function slurp(relative)
  local f = assert(io.open(root .. "/" .. relative, "rb"), "missing " .. relative)
  local source = f:read("*a")
  f:close()
  return source
end

local pipelineRecords, listeners = {}, {}
local options = {
  -- Reproduce the important live-toggle case: the save boots in native 2D,
  -- then the player enables Scott's Gen 2 voxel world without changing maps.
  gen2_voxel_world = false,
  gen2_camera_mode = "diorama",
  gen2_camera_slider = true,
  daytime = "night",
  moonPhase = "new",
  ledgeDepth = true,
}
local function noop() end
local mod = {
  id = "voxel_run_bridge",
  path = root,
  exports = {},
  read = function(_, relative)
    local ok, value = pcall(slurp, relative)
    if ok then return value end
    return nil, value
  end,
  list = function() return {} end,
  info = function() return nil end,
  find = function() return nil end,
  options = { get = function(_, key) return options[key] end },
  assets = {
    path = function(_, relative) return root .. "/" .. relative end,
    image = function() return nil end,
    list = function() return {} end,
    info = function() return nil end,
  },
  events = {
    on = function(_, name, callback)
      listeners[name] = listeners[name] or {}
      listeners[name][#listeners[name] + 1] = callback
    end,
  },
  hooks = { wrap = noop },
  content = {
    render_pipelines = {
      register = function(_, id, def)
        pipelineRecords[id] = def
        return def
      end,
    },
  },
  log = { info = noop, warn = noop, error = noop, debug = noop },
}

local wrapper = assert(loadstring(slurp("modules/gen2_voxel.lua"),
  "@modules/gen2_voxel.lua"))()
local feature = wrapper.install(mod, { generation = 2 })
eq(feature.installed, true, "terrain provider installs")
eq(feature.reason, "terrain_renderer_ready", "provider reports ready")
eq(feature.active, false, "OFF-at-boot save starts in native 2D")
eq(feature.terrainOnly, true, "provider reports terrain-only scope")
eq(feature.pokemonModels, false, "Pokemon models remain disabled")
eq(feature.playerModels, false, "player models remain disabled")
eq(feature.romImports, false, "ROM imports remain disabled")
eq(feature.kantoExcursion, false, "Kanto excursion remains disabled")
check(type(feature.lib) == "table" and type(feature.lib.require) == "function",
  "private renderer module namespace is exported")
check(type(pipelineRecords.scotts_gen2_voxel) == "table",
  "official Gen-2 drawWorld pipeline is registered")
check(type(pipelineRecords.scotts_gen2_voxel.drawWorld) == "function",
  "registered pipeline exposes drawWorld")
eq(pipelineRecords.scotts_gen2_voxel.label, "SCOTT'S GEN 2 VOXEL",
  "pipeline uses a neutral Scott/Gen-2 label")
eq(feature.provider.modelsEnabled(), false, "provider hard-disables Pokemon models")
eq(feature.provider.playerModelsEnabled(), false, "provider hard-disables player models")
check(type(listeners["game.ready"]) == "table",
  "game-ready binding is registered")

-- GoldPipelineBridge consults the public Pipelines registry when synchronizing
-- a live option change. Mirror the registered record while retaining the real
-- provider and current-engine module load above.
local pipelineLevels = {}
package.loaded["src.render.Pipelines"] = {
  get = function(id) return pipelineRecords[id] end,
  setLevel = function(id, level)
    pipelineLevels[id] = level
    return level
  end,
}
for _, callback in ipairs(listeners["game.ready"] or {}) do
  callback({ game = {} })
end
eq(pipelineLevels.scotts_gen2_voxel, 0,
  "OFF-at-boot pipeline starts at native 2D level")
eq(feature.provider.status().active, false,
  "OFF-at-boot provider is inactive")

options.gen2_voxel_world = true
for _, callback in ipairs(listeners["mod.options_changed"] or {}) do
  callback({ mod = mod.id, key = "gen2_voxel_world", value = true })
end
eq(pipelineLevels.scotts_gen2_voxel, 1,
  "public Gen 2 option enables the pipeline immediately")
eq(feature.provider.status().active, true,
  "public Gen 2 option enables the provider immediately")

options.gen2_voxel_world = false
for _, callback in ipairs(listeners["mod.options_changed"] or {}) do
  callback({ mod = mod.id, key = "gen2_voxel_world", value = false })
end
eq(pipelineLevels.scotts_gen2_voxel, 0,
  "public Gen 2 option disables the pipeline immediately")
eq(feature.provider.status().active, false,
  "public Gen 2 option disables the provider immediately")
options.gen2_voxel_world = true

local DayNight = feature.lib.require("DayNight")
local Sky = feature.lib.require("Sky")
local Astronomy = feature.lib.require("Astronomy")
eq(DayNight.setting:get(), "night", "rooted day/night setting reads host option")
eq(DayNight.moonPhaseSetting:get(), "new", "rooted moon setting reads host option")
check(type(Astronomy.equatorialDirection) == "function", "astronomy helper is rooted")
eq(#Sky.DEEP_SKY_CATALOG, 6, "all six deep-sky photographs are cataloged")
for _, entry in ipairs(Sky.DEEP_SKY_CATALOG) do
  local f = io.open(root .. "/vendor/gen2_voxel/" .. entry.path, "rb")
  check(f ~= nil, "rooted deep-sky asset exists: " .. entry.id)
  if f then f:close() end
end

local ChunkMesher = feature.lib.require("ChunkMesher")
local TileShape = feature.lib.require("TileShape")
eq(ChunkMesher.visualHeight({ class="ledge", h=6 }), 6,
  "ledge depth is visually enabled by default")
options.ledgeDepth = false
eq(ChunkMesher.visualHeight({ class="ledge", h=6 }), 0,
  "ledge depth can flatten the optional visual height")
eq(ChunkMesher.visualHeight({ class="wall", h=6 }), 6,
  "ledge toggle does not flatten ordinary collision terrain")
local mesherInvalidations, shapeInvalidations = 0, 0
local oldMesherInvalidate, oldShapeInvalidate = ChunkMesher.invalidate, TileShape.invalidate
ChunkMesher.invalidate = function(...) mesherInvalidations=mesherInvalidations+1; return oldMesherInvalidate(...) end
TileShape.invalidate = function(...) shapeInvalidations=shapeInvalidations+1; return oldShapeInvalidate(...) end
for _,callback in ipairs(listeners["mod.options_changed"] or {}) do
  callback({ mod=mod.id, key="ledgeDepth", value=false })
end
check(mesherInvalidations > 0, "ledge option invalidates terrain mesh cache")
check(shapeInvalidations > 0, "ledge option invalidates tile-shape cache")

io.stdout:write(("Gen-2 voxel headless load: %d checks passed\n"):format(checks))
