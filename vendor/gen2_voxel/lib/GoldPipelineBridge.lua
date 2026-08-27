-- Gold/Silver official render_pipelines bridge.
--
-- Current Gen1Recomp builds give Gold the same engine-owned drawWorld pipeline
-- seam that Gen 1 already had. Scott's terrain-only subset intentionally omits
-- the upstream compose/model integration; a host without the public drawWorld
-- seam therefore keeps native 2D rather than receiving a private fallback.
local first, second = ...
local mod, VoxelBridge
if second == nil and type(first) == "table" and first.mod then
  mod, VoxelBridge = first.mod, first.VoxelBridge
else
  mod, VoxelBridge = first, second
end

local Bridge = {
  id = "scotts_gen2_voxel",
  registered = false,
  runtimeInstalled = false,
  runtimeActive = false,
  game = nil,
  frames = 0,
  renderedFrames = 0,
  fallbackFrames = 0,
  lastError = nil,
  lastStatus = nil,
  renderedForCompose = false,
  selectorComposeFallback = false,
  selectorDetected = false,
}

local function optionOn()
  if VoxelBridge and type(VoxelBridge.voxelModeEnabled) == "function" then
    local ok, yes = pcall(VoxelBridge.voxelModeEnabled)
    if ok then return yes and true or false end
  end
  local opts = mod and mod.options
  if not (opts and type(opts.get) == "function") then return true end
  local ok, value = pcall(opts.get, opts, "voxel3d")
  if not ok or value == nil then return true end
  return not (value == false or value == 0 or value == "0"
    or value == "false" or value == "off")
end

local function resolveGame(value)
  if type(value) == "table" then
    if value.world or value.stack then return value end
    if type(value.game) == "table" then return value.game end
  end
  return Bridge.game
end

local function resolveWorld(ctx)
  local world = ctx and ctx.state
  if type(world) == "table" and world.map then return world end

  local game = Bridge.game
  world = game and game.world
  if type(world) == "table" and world.map then return world end

  local api = mod and mod.world
  if api and type(api.overworld) == "function" then
    local ok, value = pcall(api.overworld, api)
    if ok and type(value) == "table" and value.map then return value end
  end
  return nil
end

-- GoldVoxelBridge was originally fed render.compose metrics. Translate the
-- official drawWorld context without mutating the engine's table. Gold does
-- NOT use Gen1 Renderer:endFrame for this pass: World:drawPipeline draws the
-- returned canvas directly at (0,0).  `generation = 2` is therefore part of
-- the sizing contract -- GoldVoxelBridge must return ctx.width x ctx.height
-- logical output even on HiDPI Android, while Gen1 keeps its physical
-- framebuffer worldOverride rules.  Physical metrics are retained only as
-- diagnostics/compatibility data.
local function voxelContext(ctx)
  local w = tonumber(ctx and ctx.width)
  local h = tonumber(ctx and ctx.height)
  if not (w and h and w > 0 and h > 0) then
    local G = love and love.graphics
    if G and type(G.getDimensions) == "function" then w, h = G.getDimensions() end
  end
  w, h = tonumber(w) or 1, tonumber(h) or 1
  -- Preserve physical metrics only when the engine actually supplied them.
  -- Leaving them nil lets GoldVoxelBridge fall through to GameViewport's
  -- pixelDimensions() on current hosts instead of mistaking LOVE units for
  -- framebuffer pixels on HiDPI / reserved-viewport layouts.
  local pw = tonumber(ctx and (ctx.pw or ctx.pixelWidth))
  local ph = tonumber(ctx and (ctx.ph or ctx.pixelHeight))
  return {
    generation = 2,
    ww = w, wh = h,
    pw = pw, ph = ph,
    vw = tonumber(ctx and ctx.vw),
    vh = tonumber(ctx and ctx.vh),
    scale = tonumber(ctx and ctx.scale),
    cam = ctx and ctx.cam,
    state = ctx and ctx.state,
    level = ctx and ctx.level,
    drawFx = ctx and ctx.drawFx,
    fx = ctx and ctx.fx,
  }
end

local function available()
  -- Keep this gate intentionally cheap.  GoldVoxelBridge performs the actual
  -- depth/shader capability check and returns nil on unsupported hardware, at
  -- which point Pipelines falls back to native 2D for that frame.
  return optionOn()
end

local function drawWorld(ctx)
  Bridge.frames = Bridge.frames + 1
  Bridge.renderedForCompose = false
  if not optionOn() then
    Bridge.lastStatus = "disabled"
    Bridge.fallbackFrames = Bridge.fallbackFrames + 1
    return nil
  end
  if not (VoxelBridge and type(VoxelBridge.renderFrame) == "function") then
    Bridge.lastError = "Gold voxel provider is unavailable"
    Bridge.lastStatus = "failed"
    Bridge.fallbackFrames = Bridge.fallbackFrames + 1
    return nil
  end

  local world = resolveWorld(ctx)
  if not world then
    Bridge.lastError = "Gold world is unavailable"
    Bridge.lastStatus = "pending"
    Bridge.fallbackFrames = Bridge.fallbackFrames + 1
    return nil
  end

  if type(VoxelBridge.setGame) == "function" then
    pcall(VoxelBridge.setGame, (world and world.game) or Bridge.game)
  end

  local ok, canvas, err, status = pcall(
    VoxelBridge.renderFrame, world, voxelContext(ctx))
  if not ok then
    Bridge.lastError = tostring(canvas)
    Bridge.lastStatus = "failed"
    Bridge.fallbackFrames = Bridge.fallbackFrames + 1
    return nil
  end
  Bridge.lastStatus = status or (canvas and "rendered" or "pending")
  if not canvas then
    Bridge.lastError = err and tostring(err) or nil
    Bridge.fallbackFrames = Bridge.fallbackFrames + 1
    return nil
  end

  Bridge.renderedFrames = Bridge.renderedFrames + 1
  Bridge.lastError = nil
  -- render.compose runs after World:drawPipeline on current Gold.  Let the
  -- compose bridge consume this bit so it does not render the same voxel scene
  -- a second time; on older Gold the callback never runs and the compose bridge
  -- remains fully active.
  Bridge.renderedForCompose = true
  return canvas
end

local function pipelineModule()
  local ok, Pipelines = pcall(require, "src.render.Pipelines")
  if ok and type(Pipelines) == "table" then return Pipelines end
  return nil
end

local function selectorNeedsCompose(Pipelines)
  -- Scott's terrain-only bundle intentionally omits GoldComposeBridge and all
  -- Character Selector/Stadium model integration. Mistaking any unrelated
  -- public `voxel` pipeline for the selector would disable this drawWorld
  -- record with no compose fallback, producing native 2D instead of terrain.
  Bridge.selectorDetected = false
  return false
end

function Bridge.sync(gameOrEvent)
  Bridge.game = resolveGame(gameOrEvent) or Bridge.game
  local Pipelines = pipelineModule()
  if not (Pipelines and type(Pipelines.get) == "function"
      and type(Pipelines.setLevel) == "function") then
    Bridge.runtimeInstalled = false
    Bridge.runtimeActive = false
    return false, "engine drawWorld pipelines unavailable"
  end
  local def = Pipelines.get(Bridge.id)
  if type(def) ~= "table" or type(def.drawWorld) ~= "function" then
    Bridge.runtimeInstalled = false
    Bridge.runtimeActive = false
    return false, "Gold voxel drawWorld pipeline not present in merged registry"
  end

  Bridge.runtimeInstalled = true

  -- Kept as an explicit seam inherited from upstream. Scott's terrain-only
  -- build always returns false above because it has no model-selector compose
  -- fallback to hand ownership to.
  if selectorNeedsCompose(Pipelines) then
    pcall(Pipelines.setLevel, Bridge.id, 0)
    Bridge.runtimeActive = false
    Bridge.selectorComposeFallback = true
    Bridge.lastError = nil
    return true, false
  end
  Bridge.selectorComposeFallback = false

  local wanted = optionOn() and 1 or 0
  local ok, level = pcall(Pipelines.setLevel, Bridge.id, wanted)
  if not ok then
    Bridge.runtimeActive = false
    Bridge.lastError = tostring(level)
    return false, Bridge.lastError
  end
  Bridge.runtimeActive = tonumber(level) and tonumber(level) > 0 or false
  return true, Bridge.runtimeActive
end

function Bridge.consumeRenderedFrame()
  local rendered = Bridge.renderedForCompose == true
  Bridge.renderedForCompose = false
  return rendered
end

function Bridge.install()
  if Bridge.registered then return true end
  local content = mod and mod.content
  local registry = content and content.render_pipelines
  if not (registry and type(registry.register) == "function") then
    -- Older engines can still use GoldComposeBridge.  This is deliberately a
    -- non-fatal "not installed" result, not a reason to take the mod down.
    return false, "render_pipelines registry is unavailable"
  end

  local ok, err = pcall(registry.register, registry, Bridge.id, {
    label = "SCOTT'S GEN 2 VOXEL",
    levels = { "OFF", "ON" },
    priority = 1100,
    available = available,
    drawWorld = drawWorld,
  })
  if not ok then return false, tostring(err) end
  Bridge.registered = true

  if mod.events and type(mod.events.on) == "function" then
    pcall(mod.events.on, mod.events, "game.ready", function(ev)
      Bridge.sync(ev)
    end)
    pcall(mod.events.on, mod.events, "map.entered", function(ev)
      Bridge.sync(ev)
    end)
    pcall(mod.events.on, mod.events, "mod.options_changed", function(ev)
      if type(ev) ~= "table" then return end
      if ev.mod ~= nil and ev.mod ~= mod.id then return end
      -- Standalone upstream uses `voxel3d`; the rooted Scott facade maps that
      -- read to the public `gen2_voxel_world` option, whose live event keeps
      -- its host key. Accept both so an OFF-at-boot save can turn on now.
      if ev.key == "voxel3d" or ev.key == "gen2_voxel_world"
          or ev.key == "openWorld" then Bridge.sync() end
    end)
  end

  return true
end

function Bridge.status()
  return {
    id = Bridge.id,
    registered = Bridge.registered,
    runtimeInstalled = Bridge.runtimeInstalled,
    runtimeActive = Bridge.runtimeActive,
    frames = Bridge.frames,
    renderedFrames = Bridge.renderedFrames,
    fallbackFrames = Bridge.fallbackFrames,
    lastError = Bridge.lastError,
    lastStatus = Bridge.lastStatus,
    selectorDetected = Bridge.selectorDetected,
    selectorComposeFallback = Bridge.selectorComposeFallback,
  }
end

Bridge._drawWorld = drawWorld
Bridge._available = available
Bridge._voxelContext = voxelContext
return Bridge
