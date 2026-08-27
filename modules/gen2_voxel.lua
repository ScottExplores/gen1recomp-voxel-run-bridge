-- Terrain-only Gold/Silver/Crystal voxel adapter for Scott's Tweaks.
--
-- The provider is vendored under vendor/gen2_voxel, but receives a rooted mod
-- facade so its private module/data loader cannot escape into Scott's Gen-1
-- renderer tree. The Gen-2 world/camera plus Scott's shared sky, Moon, and
-- ledge preferences are mapped into the provider; every Stadium/model/ROM/
-- Kanto feature is forced off.

local Gen2Voxel = {}

local ROOT = "vendor/gen2_voxel"
local EXTERNAL_ID = "STADIUM2_OVERWORLD_MODELS"

local DEFAULTS = {
  gen2_voxel_world = true,
  gen2_camera_mode = "diorama",
  gen2_camera_slider = true,
  daytime = "sync",
  moonPhase = "natural",
  ledgeDepth = true,
}

local OPTION_MAP = {
  voxel3d = "gen2_voxel_world",
  cameraMode = "gen2_camera_mode",
  cameraSlider = "gen2_camera_slider",
  -- Scott's shared atmosphere/terrain preferences keep their public names.
  -- Listing them here still matters: it gives the rooted provider the same
  -- default and live-write behavior as the three Gen-2-specific controls.
  daytime = "daytime",
  moonPhase = "moonPhase",
  ledgeDepth = "ledgeDepth",
}

local FORCED_OPTIONS = {
  cameraControl = "stadium",
  openWorld = false,
  gen1Region = false,
  worldOcean = false,
  stadium3dSprites = false,
  player3dModel = false,
  customPlayerSprite = false,
  customUI = false,
  liveOverworldBattles = false,
  overworldCapture = false,
  vr = false,
}

local function enabled(value, default)
  if value == nil then return default ~= false end
  if value == false or value == 0 or value == "0" then return false end
  if type(value) == "string" then
    value = value:lower()
    if value == "false" or value == "off" or value == "no" then return false end
  end
  return true
end

local function realFind(mod, id)
  if not (mod and type(mod.find) == "function") then return nil end
  local ok, found = pcall(mod.find, id)
  if ok and found then return found end
  ok, found = pcall(mod.find, mod, id)
  return ok and found or nil
end

-- Scott's Tweaks loads after the standalone provider (200 vs 110), so find()
-- normally answers this. Loader inspection also covers a headless boot where
-- find is intentionally minimal.
local function externalWillRun(mod)
  local found = realFind(mod, EXTERNAL_ID)
  if found then return true, found end

  local ok, Game = pcall(require, "src.core.Game")
  local loader = ok and Game and Game.mods or nil
  local entry = loader and type(loader.mods) == "table" and loader.mods[EXTERNAL_ID]
  if not entry or entry.failed == true or entry.enabled == false then return false end
  if type(loader.disabled) == "table" and loader.disabled[EXTERNAL_ID] then return false end
  return true, entry
end

local function rooted(relative)
  if relative == nil or relative == "" then return ROOT end
  return ROOT .. "/" .. tostring(relative)
end

local function readOption(mod, key)
  local options = mod and mod.options
  if not (options and type(options.get) == "function") then return nil end
  local ok, value = pcall(options.get, options, key)
  if not ok then ok, value = pcall(options.get, key) end
  if ok then return value end
  return nil
end

local function makeFacade(mod)
  local live = {}
  local facade = setmetatable({}, { __index = mod })
  facade.path = tostring(mod.path) .. "/" .. ROOT
  facade.exports = {}
  facade.read = function(_, relative) return mod:read(rooted(relative)) end
  facade.list = function(_, relative) return mod:list(rooted(relative)) end
  facade.info = function(_, relative) return mod:info(rooted(relative)) end
  facade.find = function(first, second)
    local id = second == nil and first or second
    -- The terrain-only adapter never participates in Character Selector or
    -- Stadium discovery. Other harmless companion lookups still pass through.
    if id == EXTERNAL_ID or id == "red_3d_player" then return nil end
    return realFind(mod, id)
  end

  local assets = mod.assets
  if assets then
    facade.assets = setmetatable({
      path = function(_, relative) return assets:path(rooted(relative)) end,
      image = function(_, relative) return assets:image(rooted(relative)) end,
      list = function(_, relative) return assets:list(rooted(relative)) end,
      info = function(_, relative) return assets:info(rooted(relative)) end,
    }, { __index = assets })
  end

  facade.options = {
    get = function(_, key)
      if FORCED_OPTIONS[key] ~= nil then return FORCED_OPTIONS[key] end
      local hostKey = OPTION_MAP[key]
      if hostKey then
        if live[hostKey] ~= nil then return live[hostKey] end
        local value = readOption(mod, hostKey)
        if value == nil then value = DEFAULTS[hostKey] end
        return value
      end
      -- Renderer-quality/atmosphere settings that Scott does not expose keep
      -- their upstream module defaults by returning nil.
      return nil
    end,
    set = function(_, key, value)
      local hostKey = OPTION_MAP[key]
      if not hostKey then return false end
      live[hostKey] = value
      local options = mod and mod.options
      if options and type(options.set) == "function" then
        local ok, result = pcall(options.set, options, hostKey, value)
        if ok then return result == nil and true or result end
      end
      return true
    end,
  }

  return facade
end

local function loadRooted(mod, relative, arg)
  local source, readErr = mod:read(rooted(relative))
  if type(source) ~= "string" then return nil, tostring(readErr or "missing file") end
  if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end
  local compile = loadstring or load
  local chunk, compileErr = compile(source,
    "@" .. tostring(mod.path) .. "/" .. rooted(relative))
  if not chunk then return nil, tostring(compileErr) end
  local ok, value = pcall(chunk, arg)
  if not ok then return nil, tostring(value) end
  return value
end

local function publish(mod, feature)
  mod.exports = type(mod.exports) == "table" and mod.exports or {}
  mod.exports.gen2Voxel = feature
  return feature
end

function Gen2Voxel.install(mod, context)
  mod.exports = type(mod.exports) == "table" and mod.exports or {}
  local external, handle = externalWillRun(mod)
  if external then
    return publish(mod, {
      installed = false,
      active = false,
      reason = "external_gen2_voxel",
      externalId = EXTERNAL_ID,
      external = handle,
      terrainOnly = true,
      pokemonModels = false,
      playerModels = false,
      romImports = false,
    })
  end

  local facade = makeFacade(mod)
  local provider, providerErr = loadRooted(mod, "lib/GoldVoxelBridge.lua", facade)
  if not (type(provider) == "table" and type(provider.install) == "function") then
    return publish(mod, {
      installed = false, active = false, reason = "provider_load_failed",
      error = tostring(providerErr or "GoldVoxelBridge did not expose install()"),
      terrainOnly = true,
    })
  end

  local okInstall, installed, libOrErr = pcall(provider.install)
  if not okInstall or installed == false then
    return publish(mod, {
      installed = false, active = false, reason = "provider_install_failed",
      error = tostring(okInstall and libOrErr or installed),
      provider = provider, terrainOnly = true,
    })
  end

  local pipeline, pipelineErr = loadRooted(mod, "lib/GoldPipelineBridge.lua", {
    mod = facade,
    VoxelBridge = provider,
  })
  local pipelineInstalled, pipelineInstallErr = false, pipelineErr
  if type(pipeline) == "table" and type(pipeline.install) == "function" then
    local okPipeline, result, err = pcall(pipeline.install)
    pipelineInstalled = okPipeline and result ~= false
    pipelineInstallErr = pipelineInstalled and nil or tostring(okPipeline and err or result)
  elseif pipelineInstallErr == nil then
    pipelineInstallErr = "GoldPipelineBridge did not expose install()"
  end

  if not pipelineInstalled then
    return publish(mod, {
      installed = false, active = false, reason = "pipeline_install_failed",
      error = tostring(pipelineInstallErr), provider = provider,
      pipeline = pipeline, lib = libOrErr or provider.lib, terrainOnly = true,
    })
  end

  if mod.events and type(mod.events.on) == "function" then
    pcall(mod.events.on, mod.events, "game.ready", function(payload)
      local game = type(payload) == "table" and payload.game or payload
      if type(provider.setGame) == "function" then pcall(provider.setGame, game) end
      if type(pipeline.sync) == "function" then pcall(pipeline.sync, game) end
    end)
  end

  local feature = {
    installed = true,
    active = enabled(readOption(mod, "gen2_voxel_world"), true),
    reason = "terrain_renderer_ready",
    generation = 2,
    provider = provider,
    pipeline = pipeline,
    lib = libOrErr or provider.lib,
    terrainOnly = true,
    cameras = { "diorama", "third", "first" },
    pokemonModels = false,
    playerModels = false,
    stadiumBattles = false,
    stadiumUI = false,
    romImports = false,
    kantoExcursion = false,
    status = function()
      local providerStatus = type(provider.status) == "function" and provider.status() or nil
      local pipelineStatus = type(pipeline.status) == "function" and pipeline.status() or nil
      return {
        installed = true,
        active = enabled(readOption(mod, "gen2_voxel_world"), true),
        reason = "terrain_renderer_ready",
        provider = providerStatus,
        pipeline = pipelineStatus,
        terrainOnly = true,
        pokemonModels = false,
        playerModels = false,
        romImports = false,
        kantoExcursion = false,
      }
    end,
  }
  return publish(mod, feature)
end

Gen2Voxel.EXTERNAL_ID = EXTERNAL_ID
Gen2Voxel.ROOT = ROOT
Gen2Voxel.makeFacade = makeFacade
Gen2Voxel.externalWillRun = externalWillRun

return Gen2Voxel
