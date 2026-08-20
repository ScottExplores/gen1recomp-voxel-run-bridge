-- SPDX-License-Identifier: MIT
--
-- Scott's Tweaks: physical AYN Thor presentation.
--
-- This module is an independent implementation over Gen1Recomp's public
-- render.compose, render.hud, and SecondScreen contracts.  It deliberately
-- provides no desktop stacking, no touch translation, and no direct access to
-- battle-state drawing methods.  Battle Art integration uses only its public
-- Battle Stage export (v2 projection, v3 split-presentation request).

local ThorDualScreen = {
  API_VERSION = 1,
  -- This is a logical 10:9 transport surface, not a guessed panel size.  The
  -- public Android Presentation bridge integer-scales it to whichever second
  -- display is attached.  At 400x360 the canonical 160x144 UI has a crisp 2x
  -- playfield with room for Modern UI's responsive HUD, while 30 Hz readback
  -- stays well below the cost of a native-resolution buffer.
  OUTPUT_WIDTH = 400,
  OUTPUT_HEIGHT = 360,
  PUSH_HZ = 30,
  COMPOSE_PRIORITY = 20000,
  HUD_PRIORITY = 20000,
}

local BRIDGE_RECORD_KEY = "_scottsTweaksThorPresentation"
local HOOK_RECORD_KEY = "_scottsTweaksThorHookDispatch"
local EVENT_RECORD_KEY = "_scottsTweaksThorEventDispatch"

local unpackValues = table.unpack or unpack

local function pack(...)
  return { n = select("#", ...), ... }
end

local function finite(value)
  return type(value) == "number" and value == value
    and value > -math.huge and value < math.huge
end

local function positive(value, fallback)
  value = tonumber(value)
  if not finite(value) or value <= 0 then return fallback end
  return value
end

local function integer(value, fallback)
  value = positive(value, fallback)
  if not value then return nil end
  return math.max(1, math.floor(value + 0.5))
end

local function enabledValue(value)
  if value == true then return true end
  if value == false or value == nil then return false end
  if type(value) == "number" then return value ~= 0 end
  if type(value) ~= "string" then return false end
  local normalized = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return normalized ~= "" and normalized ~= "0" and normalized ~= "off"
    and normalized ~= "false" and normalized ~= "disabled"
    and normalized ~= "none"
end

local function dimensions(value)
  if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
  if type(value.getDimensions) == "function" then
    local ok, width, height = pcall(value.getDimensions, value)
    if ok then
      width, height = positive(width), positive(height)
      if width and height then return width, height end
    end
  end
  if type(value.getWidth) == "function"
      and type(value.getHeight) == "function" then
    local okW, width = pcall(value.getWidth, value)
    local okH, height = pcall(value.getHeight, value)
    width, height = okW and positive(width) or nil,
      okH and positive(height) or nil
    if width and height then return width, height end
  end
  return nil
end

local function release(resource)
  if resource and type(resource.release) == "function" then
    pcall(resource.release, resource)
  end
end

local function cover(sourceWidth, sourceHeight, targetWidth, targetHeight)
  sourceWidth, sourceHeight = positive(sourceWidth), positive(sourceHeight)
  targetWidth, targetHeight = positive(targetWidth), positive(targetHeight)
  if not (sourceWidth and sourceHeight and targetWidth and targetHeight) then
    return nil
  end
  local scale = math.max(targetWidth / sourceWidth,
    targetHeight / sourceHeight)
  return {
    x = (targetWidth - sourceWidth * scale) * 0.5,
    y = (targetHeight - sourceHeight * scale) * 0.5,
    width = sourceWidth * scale,
    height = sourceHeight * scale,
    scaleX = scale,
    scaleY = scale,
  }
end

local function contain(sourceWidth, sourceHeight, targetWidth, targetHeight)
  sourceWidth, sourceHeight = positive(sourceWidth), positive(sourceHeight)
  targetWidth, targetHeight = positive(targetWidth), positive(targetHeight)
  if not (sourceWidth and sourceHeight and targetWidth and targetHeight) then
    return nil
  end
  local scale = math.min(targetWidth / sourceWidth,
    targetHeight / sourceHeight)
  return {
    x = (targetWidth - sourceWidth * scale) * 0.5,
    y = (targetHeight - sourceHeight * scale) * 0.5,
    width = sourceWidth * scale,
    height = sourceHeight * scale,
    scaleX = scale,
    scaleY = scale,
  }
end

local function integerContain(sourceWidth, sourceHeight,
    targetWidth, targetHeight)
  local transform = contain(sourceWidth, sourceHeight,
    targetWidth, targetHeight)
  if not transform then return nil end
  local scale = transform.scaleX
  if scale >= 1 then scale = math.max(1, math.floor(scale)) end
  local width, height = sourceWidth * scale, sourceHeight * scale
  return {
    x = math.floor((targetWidth - width) * 0.5),
    y = math.floor((targetHeight - height) * 0.5),
    width = width,
    height = height,
    scaleX = scale,
    scaleY = scale,
  }
end

local function graphicsGuard(graphics, body)
  if not graphics or type(graphics.push) ~= "function"
      or type(graphics.pop) ~= "function" then
    return false, "graphics state guard is unavailable"
  end
  local pushed, pushError = pcall(graphics.push, "all")
  if not pushed then return false, tostring(pushError) end
  local result = pack(xpcall(body, function(err) return tostring(err) end))
  local popped, popError = pcall(graphics.pop)
  if not result[1] then return false, tostring(result[2]) end
  if not popped then return false, tostring(popError) end
  return true, unpackValues(result, 2, result.n)
end

local function neutralGraphics(graphics)
  if type(graphics.origin) == "function" then graphics.origin() end
  if type(graphics.setScissor) == "function" then graphics.setScissor() end
  if type(graphics.setShader) == "function" then graphics.setShader() end
  if type(graphics.setColor) == "function" then
    graphics.setColor(1, 1, 1, 1)
  end
end

local function callLogger(mod, level, message)
  local log = mod and mod.log
  local fn = log and log[level]
  if type(fn) == "function" then
    pcall(fn, log, "%s", tostring(message))
  end
end

local function optionEnabled(mod, key)
  local options = mod and mod.options
  local get = options and options.get
  if type(get) ~= "function" then return false end
  local ok, value = pcall(get, options, key)
  return ok and enabledValue(value) or false
end

local function findHandle(mod, id)
  if not mod or type(mod.find) ~= "function" then return nil end
  local ok, handle = pcall(mod.find, mod, id)
  if not ok then ok, handle = pcall(mod.find, id) end
  return ok and type(handle) == "table" and handle or nil
end

local function externalPresenterActive(mod)
  return findHandle(mod, "gen1recomp_ds") ~= nil
end

local function bridgeCall(bridge, name, ...)
  local fn = bridge and bridge[name]
  if type(fn) ~= "function" then return false, nil end
  local result = pack(pcall(fn, ...))
  if not result[1] then return false, result[2] end
  return true, unpackValues(result, 2, result.n)
end

local function bridgeAvailable(bridge)
  local ok, available = bridgeCall(bridge, "available")
  return ok and available == true
end

local function privateRecord(host, key)
  if type(host) ~= "table" then return nil end
  local ok, value = pcall(rawget, host, key)
  return ok and value or nil
end

local function setPrivateRecord(host, key, value)
  if type(host) ~= "table" then return false end
  return pcall(rawset, host, key, value)
end

local function makeCanvas(graphics, width, height)
  if not graphics or type(graphics.newCanvas) ~= "function" then
    return nil, "canvas allocation is unavailable"
  end
  local ok, canvas = pcall(graphics.newCanvas, width, height,
    { dpiscale = 1, format = "rgba8" })
  if not ok or not canvas then
    ok, canvas = pcall(graphics.newCanvas, width, height)
  end
  if not ok or not canvas then return nil, tostring(canvas) end
  if type(canvas.setFilter) == "function" then
    pcall(canvas.setFilter, canvas, "nearest", "nearest", 0)
  end
  return canvas
end

local function validStageApi(stage)
  local apiVersion = type(stage) == "table" and tonumber(stage.apiVersion)
    or nil
  return apiVersion and apiVersion >= 2
    and type(stage.state) == "function"
    and type(stage.animationSurface) == "function"
end

local function stageApi(mod)
  -- In Scott's Tweaks, Battle Art is fused into this same loader entry and
  -- publishes its compatibility seam directly on the root mod exports. A
  -- standalone BATTLE_ART_VOXEL_FORK handle exists only in older/separate
  -- installs, so use it strictly as the compatibility fallback.
  local ownExports = mod and mod.exports
  local ownStage = type(ownExports) == "table" and ownExports.battleStage or nil
  if validStageApi(ownStage) then return ownStage end

  local handle = findHandle(mod, "BATTLE_ART_VOXEL_FORK")
  local exports = handle and handle.exports
  local stage = type(exports) == "table" and exports.battleStage or nil
  return validStageApi(stage) and stage or nil
end

local function animationSurface(mod)
  local stage = stageApi(mod)
  if not stage then return nil end
  local okState, state = pcall(stage.state)
  if not okState or type(state) ~= "table" or state.battle == nil
      or state.staged == false then
    return nil
  end
  local okSurface, surface = pcall(stage.animationSurface, state.battle)
  if not okSurface or type(surface) ~= "table" then return nil end
  local canvasWidth, canvasHeight = dimensions(surface.canvas)
  local framebufferWidth = positive(surface.pw)
  local framebufferHeight = positive(surface.ph)
  local layerScale = positive(surface.scale)
  if not (canvasWidth and canvasHeight and framebufferWidth
      and framebufferHeight and layerScale and finite(tonumber(surface.lx))
      and finite(tonumber(surface.ly))) then
    return nil
  end
  return {
    canvas = surface.canvas,
    lx = tonumber(surface.lx),
    ly = tonumber(surface.ly),
    scale = layerScale,
    pw = framebufferWidth,
    ph = framebufferHeight,
  }
end

local function setSplitPresentation(mod, active)
  local stage = stageApi(mod)
  if not stage or (tonumber(stage.apiVersion) or 0) < 3
      or type(stage.setSplitPresentation) ~= "function" then
    return false
  end
  local ok, accepted = pcall(stage.setSplitPresentation, active == true)
  return ok and accepted == true
end

local function cloneStatus(runtime, mod, optionKey)
  local desired = optionEnabled(mod, optionKey)
  local external = externalPresenterActive(mod)
  local delegated = runtime.delegated == true or external
  return {
    apiVersion = ThorDualScreen.API_VERSION,
    optionKey = optionKey,
    mode = desired and "on" or "off",
    enabled = desired,
    active = runtime.active == true and not delegated,
    attached = bridgeAvailable(runtime.bridge),
    externalPresenter = external,
    delegated = delegated,
    delegateId = delegated and "gen1recomp_ds" or nil,
    blockedReason = delegated and "delegated_to_gen1recomp_ds"
      or runtime.faulted and "runtime_error" or nil,
    faulted = runtime.faulted == true,
    generation = runtime.generation,
    retired = runtime.retired == true,
    lastError = runtime.lastError,
    topSource = runtime.topSource,
    outputWidth = ThorDualScreen.OUTPUT_WIDTH,
    outputHeight = ThorDualScreen.OUTPUT_HEIGHT,
    outputPolicy = "logical_10_9_integer_scaled",
    pushHz = ThorDualScreen.PUSH_HZ,
    controllerOnly = true,
    touchPolling = false,
    battleSplit = runtime.splitRequested == true,
  }
end

function ThorDualScreen.install(mod, opts)
  assert(type(mod) == "table", "Thor Dual Screen needs the mod API")
  opts = type(opts) == "table" and opts or {}
  local optionKey = type(opts.optionKey) == "string" and opts.optionKey ~= ""
    and opts.optionKey or "dual_screen"
  local graphics = opts.graphics or (love and love.graphics)
  local timer = opts.timer or (love and love.timer)
  local now = type(opts.now) == "function" and opts.now or function()
    if timer and type(timer.getTime) == "function" then
      local ok, value = pcall(timer.getTime)
      if ok and finite(tonumber(value)) then return tonumber(value) end
    end
    return os.clock()
  end

  local runtime = {
    bridge = nil,
    bridgeRecord = nil,
    bridgeRequested = nil,
    generation = 1,
    retired = false,
    delegated = false,
    topCanvas = nil,
    topWidth = nil,
    topHeight = nil,
    topValid = false,
    topSource = nil,
    lowerCanvas = nil,
    pending = nil,
    active = false,
    faulted = false,
    lastError = nil,
    lastPushAt = nil,
    splitRequested = nil,
    warned = {},
  }

  local function requestBattleSplit(on)
    on = on == true
    if runtime.splitRequested == on then return true end
    local accepted = setSplitPresentation(mod, on)
    if accepted then
      runtime.splitRequested = on
      return true
    end
    -- Battle Stage v2 and a boot with no staged-battle provider are valid.
    -- Retain nil so a provider loaded later in this same process is probed.
    if not on then runtime.splitRequested = nil end
    return false
  end

  local function warnOnce(key, message)
    if runtime.warned[key] then return end
    runtime.warned[key] = true
    callLogger(mod, "warn", "Thor display: " .. tostring(message))
  end

  local function releaseCanvases()
    requestBattleSplit(false)
    runtime.pending = nil
    runtime.active = false
    release(runtime.topCanvas)
    release(runtime.lowerCanvas)
    runtime.topCanvas, runtime.lowerCanvas = nil, nil
    runtime.topWidth, runtime.topHeight = nil, nil
    runtime.topValid, runtime.topSource = false, nil
    runtime.lastPushAt = nil
  end

  local function ownsBridgeRecord()
    local record = runtime.bridgeRecord
    return type(record) == "table" and record.owner == mod.id
      and record.runtime == runtime
      and privateRecord(runtime.bridge, BRIDGE_RECORD_KEY) == record
  end

  local function recordRequest(value)
    runtime.bridgeRequested = value
    if ownsBridgeRecord() then runtime.bridgeRecord.requested = value end
  end

  -- Old Loader hook buses disappear on F5, but the public SecondScreen module
  -- survives.  Its namespaced record hands the frozen world and enable request
  -- to the fresh generation and retires every old GPU resource exactly once.
  local function retireForHandoff(adoptTop)
    if runtime.retired then return nil end
    requestBattleSplit(false)
    runtime.retired = true
    runtime.pending = nil
    runtime.active = false
    release(runtime.lowerCanvas)
    runtime.lowerCanvas = nil
    runtime.lastPushAt = nil
    local snapshot
    if adoptTop and runtime.topCanvas and runtime.topValid then
      snapshot = {
        canvas = runtime.topCanvas,
        width = runtime.topWidth,
        height = runtime.topHeight,
        source = runtime.topSource,
      }
      runtime.topCanvas = nil
    else
      release(runtime.topCanvas)
      runtime.topCanvas = nil
    end
    runtime.topWidth, runtime.topHeight = nil, nil
    runtime.topValid, runtime.topSource = false, nil
    return snapshot
  end

  local function setFault(message)
    requestBattleSplit(false)
    runtime.faulted = true
    runtime.lastError = tostring(message)
    runtime.pending = nil
    runtime.active = false
    warnOnce("fault:" .. runtime.lastError, runtime.lastError)
    if runtime.bridge and runtime.bridgeRequested == true
        and not runtime.delegated and not externalPresenterActive(mod) then
      bridgeCall(runtime.bridge, "setEnabled", false)
      recordRequest(false)
    end
  end

  local function desired()
    return not runtime.retired and optionEnabled(mod, optionKey)
      and not runtime.faulted
      and not runtime.delegated and not externalPresenterActive(mod)
  end

  local function bindBridge(bridge)
    if runtime.retired then return false, "presenter generation is retired" end
    if runtime.bridge == bridge and ownsBridgeRecord() then return true end
    if runtime.bridge and ownsBridgeRecord() then
      if runtime.bridgeRequested == true and not runtime.delegated
          and not externalPresenterActive(mod) then
        bridgeCall(runtime.bridge, "setEnabled", false)
      end
      setPrivateRecord(runtime.bridge, BRIDGE_RECORD_KEY, nil)
    end
    runtime.bridge = bridge
    runtime.bridgeRecord = nil
    runtime.bridgeRequested = nil
    if type(bridge) ~= "table" then return false, "bridge is unavailable" end

    local previous = privateRecord(bridge, BRIDGE_RECORD_KEY)
    if previous ~= nil and (type(previous) ~= "table"
        or previous.owner ~= mod.id) then
      return false, "secondary display ownership record is unavailable"
    end

    local snapshot
    if type(previous) == "table" and previous.runtime ~= runtime then
      runtime.generation = math.max(1,
        (tonumber(previous.generation) or 0) + 1)
      runtime.bridgeRequested = previous.requested
      if type(previous.retire) ~= "function" then
        return false, "previous presenter cannot retire safely"
      end
      local ok, adopted = pcall(previous.retire, true)
      if not ok then
        return false, "previous presenter retirement failed: "
          .. tostring(adopted)
      end
      snapshot = adopted
    end
    if type(snapshot) == "table" and dimensions(snapshot.canvas) then
      runtime.topCanvas = snapshot.canvas
      runtime.topWidth = positive(snapshot.width)
      runtime.topHeight = positive(snapshot.height)
      runtime.topValid = runtime.topWidth ~= nil and runtime.topHeight ~= nil
      runtime.topSource = runtime.topValid and snapshot.source or nil
      if not runtime.topValid then
        release(runtime.topCanvas)
        runtime.topCanvas = nil
      end
    end

    local record = {
      owner = mod.id,
      apiVersion = ThorDualScreen.API_VERSION,
      generation = runtime.generation,
      runtime = runtime,
      requested = runtime.bridgeRequested,
      retire = retireForHandoff,
    }
    if not setPrivateRecord(bridge, BRIDGE_RECORD_KEY, record) then
      releaseCanvases()
      return false, "secondary display ownership record cannot be published"
    end
    runtime.bridgeRecord = record
    return true
  end

  local function relinquishBridge(bridge)
    runtime.bridge = bridge
    runtime.bridgeRecord = nil
    runtime.bridgeRequested = nil
    local previous = privateRecord(bridge, BRIDGE_RECORD_KEY)
    if type(previous) == "table" and previous.owner == mod.id then
      if previous.runtime ~= runtime and type(previous.retire) == "function" then
        pcall(previous.retire, false)
      else
        releaseCanvases()
      end
      setPrivateRecord(bridge, BRIDGE_RECORD_KEY, nil)
    else
      releaseCanvases()
    end
  end

  local function requestBridge(on)
    local bridge = runtime.bridge
    if runtime.retired or not bridge or not ownsBridgeRecord() then return false end
    if runtime.delegated or externalPresenterActive(mod) then
      -- The bridge is shared process state.  Do not turn it off underneath a
      -- separately installed presenter; simply relinquish our request record.
      recordRequest(nil)
      return false
    end
    on = on == true
    if runtime.bridgeRequested == on then return true end
    if not on and runtime.bridgeRequested == nil then
      recordRequest(false)
      return true
    end
    local ok, err = bridgeCall(bridge, "setEnabled", on)
    if not ok then
      setFault("secondary display enable failed: " .. tostring(err))
      return false
    end
    recordRequest(on)
    return true
  end

  local function ensureLowerCanvas()
    local width, height = dimensions(runtime.lowerCanvas)
    if width == ThorDualScreen.OUTPUT_WIDTH
        and height == ThorDualScreen.OUTPUT_HEIGHT then
      return runtime.lowerCanvas
    end
    local canvas, err = makeCanvas(graphics, ThorDualScreen.OUTPUT_WIDTH,
      ThorDualScreen.OUTPUT_HEIGHT)
    if not canvas then return nil, err end
    release(runtime.lowerCanvas)
    runtime.lowerCanvas = canvas
    return canvas
  end

  local function freshTopCanvas(width, height)
    width, height = integer(width), integer(height)
    if not (width and height) then return nil, "invalid primary dimensions" end
    local currentWidth, currentHeight = dimensions(runtime.topCanvas)
    if currentWidth == width and currentHeight == height then
      return runtime.topCanvas, false
    end
    local canvas, err = makeCanvas(graphics, width, height)
    if not canvas then return nil, err end
    return canvas, true
  end

  local function renderWorldInto(canvas, ctx, source, sourceKind,
      targetWidth, targetHeight)
    local sourceWidth, sourceHeight = dimensions(source)
    local transform = cover(sourceWidth, sourceHeight, targetWidth, targetHeight)
    if not transform then return false, "world surface has no dimensions" end
    local ok, err = graphicsGuard(graphics, function()
      graphics.setCanvas(canvas)
      neutralGraphics(graphics)
      graphics.clear(0, 0, 0, 1)
      if sourceKind == "worldCanvas" and ctx.renderer
          and type(ctx.renderer.blitCanvas) == "function" then
        local zones = ctx.worldZones or ctx.zones
        local drew, drawError = pcall(ctx.renderer.blitCanvas, ctx.renderer,
          source, transform.scaleX, transform.scaleY,
          zones, transform.scaleX, transform.scaleY,
          transform.x, transform.y, 0, 0, targetWidth, targetHeight, 1, 1)
        if not drew then error(drawError, 0) end
      else
        graphics.draw(source, transform.x, transform.y, 0,
          transform.scaleX, transform.scaleY)
      end
    end)
    return ok, err
  end

  local function updateTop(ctx)
    local source, sourceKind
    if ctx.worldOverride and dimensions(ctx.worldOverride) then
      source, sourceKind = ctx.worldOverride, "worldOverride"
    elseif ctx.worldActive == true and ctx.worldCanvas
        and dimensions(ctx.worldCanvas) then
      source, sourceKind = ctx.worldCanvas, "worldCanvas"
    else
      return runtime.topValid
    end

    local targetWidth = integer(ctx.pw,
      integer((tonumber(ctx.ww) or 1) * positive(ctx.dpiX, 1), 1))
    local targetHeight = integer(ctx.ph,
      integer((tonumber(ctx.wh) or 1) * positive(ctx.dpiY, 1), 1))
    local canvas, replacementOrError = freshTopCanvas(targetWidth, targetHeight)
    if not canvas then return false, replacementOrError end
    local replacement = replacementOrError == true
    local rendered, renderError = renderWorldInto(canvas, ctx, source,
      sourceKind, targetWidth, targetHeight)
    if not rendered then
      if replacement then release(canvas) end
      return false, renderError
    end
    if replacement then
      release(runtime.topCanvas)
      runtime.topCanvas = canvas
    end
    runtime.topWidth, runtime.topHeight = targetWidth, targetHeight
    runtime.topValid = true
    runtime.topSource = sourceKind
    return true
  end

  local function stageLower(ctx)
    local canvas, canvasError = ensureLowerCanvas()
    if not canvas then return false, canvasError end
    local uiWidth = positive(ctx.uiw)
    local uiHeight = positive(ctx.uih)
    if not (uiWidth and uiHeight) and ctx.uiCanvas then
      uiWidth, uiHeight = dimensions(ctx.uiCanvas)
    end
    uiWidth, uiHeight = uiWidth or 160, uiHeight or 144
    local transform = integerContain(uiWidth, uiHeight,
      ThorDualScreen.OUTPUT_WIDTH, ThorDualScreen.OUTPUT_HEIGHT)
    local ok, err = graphicsGuard(graphics, function()
      graphics.setCanvas(canvas)
      neutralGraphics(graphics)
      graphics.clear(0, 0, 0, 1)
      if ctx.uiCanvas and ctx.renderer
          and type(ctx.renderer.blitCanvas) == "function" then
        local drew, drawError = pcall(ctx.renderer.blitCanvas, ctx.renderer,
          ctx.uiCanvas, transform.scaleX, transform.scaleY,
          ctx.zones, transform.scaleX, transform.scaleY,
          transform.x, transform.y,
          0, 0, ThorDualScreen.OUTPUT_WIDTH,
          ThorDualScreen.OUTPUT_HEIGHT, 1, 1)
        if not drew then error(drawError, 0) end
      elseif ctx.uiCanvas then
        graphics.draw(ctx.uiCanvas, transform.x, transform.y, 0,
          transform.scaleX, transform.scaleY)
      end
    end)
    if not ok then return false, err end
    return true, {
      width = ThorDualScreen.OUTPUT_WIDTH,
      height = ThorDualScreen.OUTPUT_HEIGHT,
      gameX = transform.x,
      gameY = transform.y,
      gameWidth = transform.width,
      gameHeight = transform.height,
      scale = transform.scaleX,
      dpiX = 1,
      dpiY = 1,
      generation = 1,
      safeX = 0,
      safeY = 0,
      safeWidth = ThorDualScreen.OUTPUT_WIDTH,
      safeHeight = ThorDualScreen.OUTPUT_HEIGHT,
      safe = {
        x = 0, y = 0,
        width = ThorDualScreen.OUTPUT_WIDTH,
        height = ThorDualScreen.OUTPUT_HEIGHT,
      },
      fullSafe = {
        x = 0, y = 0,
        width = ThorDualScreen.OUTPUT_WIDTH,
        height = ThorDualScreen.OUTPUT_HEIGHT,
      },
      game = {
        x = transform.x, y = transform.y,
        width = transform.width, height = transform.height,
      },
      _scottsTweaksThorLower = true,
    }
  end

  local function drawTop(ctx)
    local dpiX, dpiY = positive(ctx.dpiX, 1), positive(ctx.dpiY, 1)
    local windowWidth = positive(ctx.ww,
      runtime.topWidth and runtime.topWidth / dpiX or nil)
    local windowHeight = positive(ctx.wh,
      runtime.topHeight and runtime.topHeight / dpiY or nil)
    if not (runtime.topCanvas and runtime.topValid and windowWidth
        and windowHeight) then
      return false, "no live or frozen world surface is available"
    end
    local effect = animationSurface(mod)
    return graphicsGuard(graphics, function()
      if type(graphics.setCanvas) == "function" then graphics.setCanvas() end
      neutralGraphics(graphics)
      graphics.clear(0, 0, 0, 1)
      if type(graphics.setScissor) == "function" then
        graphics.setScissor(0, 0, windowWidth, windowHeight)
      end
      graphics.draw(runtime.topCanvas, 0, 0, 0, 1 / dpiX, 1 / dpiY)
      if effect then
        local transform = cover(effect.pw, effect.ph,
          runtime.topWidth, runtime.topHeight)
        if transform then
          graphics.draw(effect.canvas,
            (transform.x + effect.lx * transform.scaleX) / dpiX,
            (transform.y + effect.ly * transform.scaleY) / dpiY,
            0,
            effect.scale * transform.scaleX / dpiX,
            effect.scale * transform.scaleY / dpiY)
        end
      end
      if type(graphics.setScissor) == "function" then graphics.setScissor() end
    end)
  end

  local function shouldPush()
    local timestamp = now()
    if not finite(timestamp) then return true, nil end
    local interval = 1 / ThorDualScreen.PUSH_HZ
    if runtime.lastPushAt == nil or timestamp < runtime.lastPushAt
        or timestamp - runtime.lastPushAt + 1e-9 >= interval then
      return true, timestamp
    end
    return false, timestamp
  end

  local function pushLower()
    local due, timestamp = shouldPush()
    if not due then return true end
    local canvas = runtime.lowerCanvas
    if not canvas or type(canvas.newImageData) ~= "function" then
      return false, "lower display readback is unavailable"
    end
    local okData, imageData = pcall(canvas.newImageData, canvas)
    if not okData or not imageData then
      return false, "lower display readback failed: " .. tostring(imageData)
    end
    local okPush, pushedOrError = bridgeCall(runtime.bridge, "push", imageData,
      ThorDualScreen.OUTPUT_WIDTH, ThorDualScreen.OUTPUT_HEIGHT)
    release(imageData)
    if not okPush or pushedOrError == false then
      return false, "lower display push failed: " .. tostring(pushedOrError)
    end
    runtime.lastPushAt = timestamp
    return true
  end

  local composeHook = function(nextFn, renderer, ctx)
    if runtime.retired then return nextFn(renderer, ctx) end
    runtime.pending = nil
    runtime.active = false
    ctx = type(ctx) == "table" and ctx or {}
    if externalPresenterActive(mod) then
      -- Ownership is sticky for this entry/boot.  If the legacy presenter is
      -- removed during a developer hot reload we still do not race its old
      -- wrappers or shared native bridge; a fresh entry owns the next boot.
      runtime.delegated = true
      runtime.bridgeRequested = nil
      requestBattleSplit(false)
    end
    local bound, bindError
    if runtime.delegated then
      relinquishBridge(ctx.secondScreen)
    else
      bound, bindError = bindBridge(ctx.secondScreen)
    end
    local downstream = nextFn(renderer, ctx)
    if downstream == true then
      requestBattleSplit(false)
      return true
    end

    if runtime.delegated then
      requestBattleSplit(false)
      runtime.bridgeRequested = nil
      return downstream
    end
    if not bound then
      requestBattleSplit(false)
      if bindError and ctx.secondScreen ~= nil then
        setFault("secondary display handoff failed: " .. tostring(bindError))
      end
      return downstream
    end
    if not optionEnabled(mod, optionKey) then
      requestBattleSplit(false)
      requestBridge(false)
      return downstream
    end
    if runtime.faulted then
      requestBattleSplit(false)
      return downstream
    end
    if not bridgeAvailable(runtime.bridge) then
      requestBattleSplit(false)
      -- Keep the already-issued native enable request latched across a
      -- physical hot-unplug. Android's Presentation bridge will resume that
      -- same request when the panel returns; toggling it here both spams the
      -- transport and defeats the existing automatic-replug contract.
      return downstream
    end

    -- Arm Battle Stage v3 one frame before taking over composition. The frame
    -- that reached this hook was already drawn, so publishing it immediately
    -- would still contain the old move/pic layers on the lower panel. Falling
    -- through once lets the next engine draw produce the clean UI-only canvas;
    -- v2 providers simply skip this optional warm-up.
    local splitWasReady = runtime.splitRequested == true
    local splitReady = requestBattleSplit(true)
    if splitReady and not splitWasReady then return downstream end
    if not requestBridge(true) then return downstream end

    local topReady, topError = updateTop(ctx)
    if not topReady then
      requestBattleSplit(false)
      if topError then setFault("top surface failed: " .. tostring(topError)) end
      return downstream
    end
    local lowerReady, lowerViewportOrError = stageLower(ctx)
    if not lowerReady then
      requestBattleSplit(false)
      setFault("lower surface failed: " .. tostring(lowerViewportOrError))
      return downstream
    end
    local topDrawn, topDrawError = drawTop(ctx)
    if not topDrawn then
      requestBattleSplit(false)
      setFault("primary presentation failed: " .. tostring(topDrawError))
      return downstream
    end

    runtime.pending = {
      bridge = runtime.bridge,
      viewport = lowerViewportOrError,
    }
    runtime.active = true
    return true
  end

  local hudHook = function(nextFn, game, viewport)
    if runtime.retired then return nextFn(game, viewport) end
    local pending = runtime.pending
    runtime.pending = nil
    if not pending or not runtime.active or not desired()
        or pending.bridge ~= runtime.bridge
        or not bridgeAvailable(runtime.bridge) then
      runtime.active = false
      return nextFn(game, viewport)
    end
    local downstream
    local captured, captureError = graphicsGuard(graphics, function()
      graphics.setCanvas(runtime.lowerCanvas)
      neutralGraphics(graphics)
      downstream = pack(nextFn(game, pending.viewport))
    end)
    if not captured then
      setFault("lower HUD capture failed: " .. tostring(captureError))
      -- nextFn may already have run before a post-draw graphics error.  Never
      -- run a stateful HUD chain twice in one frame.
      if downstream then return unpackValues(downstream, 1, downstream.n) end
      return nextFn(game, viewport)
    end
    local pushed, pushError = pushLower()
    if not pushed then setFault(pushError) end
    if downstream then return unpackValues(downstream, 1, downstream.n) end
  end

  local hookRecord
  local eventRecord

  local function shutdown()
    if runtime.retired then return end
    -- A second install on one facade refreshes its dispatcher.  Releasing a
    -- stale controller must never tear down the newer generation.
    if hookRecord and hookRecord.runtime ~= runtime then
      retireForHandoff(false)
      return
    end
    if runtime.bridgeRequested == true and ownsBridgeRecord()
        and not runtime.delegated and not externalPresenterActive(mod) then
      bridgeCall(runtime.bridge, "setEnabled", false)
    end
    recordRequest(false)
    if ownsBridgeRecord() then
      setPrivateRecord(runtime.bridge, BRIDGE_RECORD_KEY, nil)
    end
    releaseCanvases()
    runtime.retired = true
  end

  local quitHook = function(nextFn, ...)
    shutdown()
    return nextFn(...)
  end

  assert(mod.hooks and type(mod.hooks.wrap) == "function",
    "Thor Dual Screen needs render hooks")
  hookRecord = privateRecord(mod.hooks, HOOK_RECORD_KEY)
  if hookRecord ~= nil and (type(hookRecord) ~= "table"
      or hookRecord.owner ~= mod.id or hookRecord.dispatcher ~= true) then
    error("Thor Dual Screen hook dispatcher is owned by another feature", 0)
  end
  if not hookRecord then
    hookRecord = {
      owner = mod.id,
      dispatcher = true,
      generation = 0,
      callbacks = {},
    }
    assert(setPrivateRecord(mod.hooks, HOOK_RECORD_KEY, hookRecord),
      "Thor Dual Screen cannot publish its hook dispatcher")
    mod.hooks:wrap("render.compose", function(nextFn, renderer, ctx)
      local callback = hookRecord.callbacks.compose
      if callback then return callback(nextFn, renderer, ctx) end
      return nextFn(renderer, ctx)
    end, ThorDualScreen.COMPOSE_PRIORITY)
    mod.hooks:wrap("render.hud", function(nextFn, game, viewport)
      local callback = hookRecord.callbacks.hud
      if callback then return callback(nextFn, game, viewport) end
      return nextFn(game, viewport)
    end, ThorDualScreen.HUD_PRIORITY)
    mod.hooks:wrap("core.quit_to_launcher", function(nextFn, ...)
      local callback = hookRecord.callbacks.quit
      if callback then return callback(nextFn, ...) end
      return nextFn(...)
    end, ThorDualScreen.COMPOSE_PRIORITY)
  end
  hookRecord.generation = (tonumber(hookRecord.generation) or 0) + 1
  hookRecord.runtime = runtime
  hookRecord.callbacks.compose = composeHook
  hookRecord.callbacks.hud = hudHook
  hookRecord.callbacks.quit = quitHook

  local function optionChanged(payload)
    if runtime.retired or type(payload) ~= "table" or payload.mod ~= mod.id
        or payload.key ~= optionKey then return end
    if enabledValue(payload.value) then
      runtime.faulted = false
      runtime.lastError = nil
      runtime.warned = {}
      requestBridge(true)
    else
      requestBridge(false)
      releaseCanvases()
    end
  end

  if mod.events and type(mod.events.on) == "function" then
    eventRecord = privateRecord(mod.events, EVENT_RECORD_KEY)
    if eventRecord ~= nil and (type(eventRecord) ~= "table"
        or eventRecord.owner ~= mod.id or eventRecord.dispatcher ~= true) then
      error("Thor Dual Screen event dispatcher is owned by another feature", 0)
    end
    if not eventRecord then
      eventRecord = {
        owner = mod.id,
        dispatcher = true,
        generation = 0,
      }
      assert(setPrivateRecord(mod.events, EVENT_RECORD_KEY, eventRecord),
        "Thor Dual Screen cannot publish its event dispatcher")
      mod.events:on("mod.options_changed", function(payload)
        local callback = eventRecord.callback
        if callback then return callback(payload) end
      end)
    end
    eventRecord.generation = (tonumber(eventRecord.generation) or 0) + 1
    eventRecord.runtime = runtime
    eventRecord.callback = optionChanged
  end

  local public = {
    apiVersion = ThorDualScreen.API_VERSION,
    controllerOnly = true,
    getEnabled = function() return optionEnabled(mod, optionKey) end,
    getMode = function()
      return optionEnabled(mod, optionKey) and "on" or "off"
    end,
    secondDisplayAttached = function()
      return bridgeAvailable(runtime.bridge)
    end,
    getStatus = function() return cloneStatus(runtime, mod, optionKey) end,
  }
  mod.exports = type(mod.exports) == "table" and mod.exports or {}
  mod.exports.thorDualScreen = public

  return {
    apiVersion = ThorDualScreen.API_VERSION,
    exports = public,
    status = public.getStatus,
    release = function()
      shutdown()
      if hookRecord and hookRecord.runtime == runtime then
        hookRecord.callbacks.compose = nil
        hookRecord.callbacks.hud = nil
        hookRecord.callbacks.quit = nil
      end
      if eventRecord and eventRecord.runtime == runtime then
        eventRecord.callback = nil
      end
    end,
  }
end

ThorDualScreen.cover = cover
ThorDualScreen.contain = contain
ThorDualScreen.integerContain = integerContain
ThorDualScreen.enabledValue = enabledValue

return ThorDualScreen
