-- Focused, ROM-free contract checks for the terrain-only Gen-2 wrapper.
--   luajit tests/gen2_voxel_adapter.lua <mod-root>

local argv = rawget(_G, "arg") or {}
local root = assert(argv[1], "Scott's Tweaks source root required")
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

local wrapper = assert(loadstring(slurp("modules/gen2_voxel.lua"),
  "@modules/gen2_voxel.lua"))()

local reads = {}
local host = {
  id = "voxel_run_bridge",
  path = "mods/voxel_run_bridge",
  exports = {},
  options = {
    get = function(_, key)
      if key == "gen2_voxel_world" then return false end
      if key == "gen2_camera_mode" then return "third" end
      if key == "gen2_camera_slider" then return false end
      if key == "daytime" then return "night" end
      if key == "moonPhase" then return "new" end
      if key == "ledgeDepth" then return false end
    end,
  },
  read = function(_, relative) reads[#reads + 1] = relative return "body" end,
  list = function(_, relative) return { relative } end,
  info = function(_, relative) return { path = relative } end,
  find = function(id)
    if id == "harmless_companion" then return { id = id } end
  end,
}

local facade = wrapper.makeFacade(host)
eq(facade.path, "mods/voxel_run_bridge/vendor/gen2_voxel",
  "provider path is rooted")
facade:read("lib/GoldVoxelBridge.lua")
eq(reads[1], "vendor/gen2_voxel/lib/GoldVoxelBridge.lua",
  "provider reads stay in its vendor root")
eq(facade.options:get("voxel3d"), false, "world option maps to Scott's key")
eq(facade.options:get("cameraMode"), "third", "camera mode maps to Scott's key")
eq(facade.options:get("cameraSlider"), false, "camera slider maps to Scott's key")
eq(facade.options:get("daytime"), "night", "day/night setting maps through facade")
eq(facade.options:get("moonPhase"), "new", "moon phase setting maps through facade")
eq(facade.options:get("ledgeDepth"), false, "ledge setting maps through facade")
eq(facade.options:get("stadium3dSprites"), false, "Pokemon models are forced off")
eq(facade.options:get("player3dModel"), false, "player models are forced off")
eq(facade.options:get("gen1Region"), false, "Kanto excursion is forced off")
eq(facade.options:get("cameraControl"), "stadium",
  "private sprite-card camera owns the three views")
eq(facade.find("red_3d_player"), nil, "Character Selector integration is blocked")
check(facade.find("harmless_companion") ~= nil,
  "unrelated companion discovery still delegates")

local externalReads = 0
local externalHandle = { id = wrapper.EXTERNAL_ID, exports = { active = true } }
local externalHost = {
  id = host.id,
  path = host.path,
  exports = {},
  options = host.options,
  find = function(id)
    if id == wrapper.EXTERNAL_ID then return externalHandle end
  end,
  read = function() externalReads = externalReads + 1 return nil end,
}
local externalResult = wrapper.install(externalHost, { generation = 2 })
eq(externalResult.reason, "external_gen2_voxel",
  "standalone Gen-2 renderer makes the bundled copy stand aside")
eq(externalResult.external, externalHandle,
  "stand-aside status identifies the active external provider")
eq(externalReads, 0, "stand-aside does not load a second renderer")

for _, forbidden in ipairs({
  "Stadium.lua", "StadiumRom.lua", "StadiumRom2.lua", "StadiumPack.lua",
  "OverworldBattle.lua", "OverworldCapture.lua", "TwinRegionWorld.lua",
  "VR.lua", "VRXR.lua",
}) do
  local f = io.open(root .. "/vendor/gen2_voxel/lib/" .. forbidden, "rb")
  check(f == nil, "terrain-only package omits " .. forbidden)
  if f then f:close() end
end

local provider = slurp("vendor/gen2_voxel/lib/GoldVoxelBridge.lua"):gsub("\r", "")
check(provider:find("BLOCKED_MODULES", 1, true) ~= nil,
  "provider has a lazy-module deny list")
check(provider:find("local function modelsEnabled()\n  return false", 1, true) ~= nil,
  "Pokemon models are hard-disabled in the provider")
check(provider:find("local function playerModelsEnabled()\n  return false", 1, true) ~= nil,
  "player models are hard-disabled in the provider")

local diskCache = slurp("vendor/gen2_voxel/lib/VoxelDiskCache.lua")
check(diskCache:find('local BASE_DIR = "scotts_gen2_voxel_cache/', 1, true) ~= nil,
  "terrain cache uses Scott's private namespace")
check(diskCache:find('local BASE_DIR = "stadium2_voxel_cache/', 1, true) == nil,
  "terrain cache cannot collide with the standalone renderer")

local engineCompat = slurp("vendor/gen2_voxel/lib/EngineCompat.lua")
check(engineCompat:find("function Compat.fs()", 1, true) ~= nil,
  "terrain keeps only its engine-owned persistence facade")
check(engineCompat:find("function Compat.osName()", 1, true) ~= nil,
  "terrain keeps only its platform-name helper")
for _, forbidden in ipairs({
  "RomImporter", ".z64", "picked_stadium", "chooseFile",
  "stageExternal", "HostShell", "popen",
}) do
  check(engineCompat:find(forbidden, 1, true) == nil,
    "terrain utility excludes host/import capability: " .. forbidden)
end

io.stdout:write(("Gen-2 voxel adapter: %d checks passed\n"):format(checks))
