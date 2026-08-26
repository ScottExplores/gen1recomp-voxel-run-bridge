-- Focused contract tests for Scott's Tweaks' clean physical-Thor presenter.
-- Run with LuaJIT 2.1 or Lua 5.1:
--   luajit tests/thor_dual_screen.lua <tweaks-root> <engine-.88> <engine-.96> <live-engine>

local argv = rawget(_G, "arg") or {}
local sourceRoot = (argv[1] or "."):gsub("\\", "/"):gsub("/$", "")
local temp = (os.getenv("TEMP") or os.getenv("TMP") or "."):gsub("\\", "/")
local engineRoots = {
  { label = "v0.1.88", path = (argv[2]
      or (temp .. "/codex_gen1recomp_source_v0.1.88")):gsub("\\", "/") },
  { label = "v0.1.96", path = (argv[3]
      or (temp .. "/codex_gen1recomp_source_v0.1.96")):gsub("\\", "/") },
}

local checks = 0
local function check(value, message)
  checks = checks + 1
  if not value then error(("check %d failed: %s"):format(checks, message), 0) end
end

local function eq(actual, expected, message)
  check(actual == expected, ("%s (expected %s, got %s)")
    :format(message, tostring(expected), tostring(actual)))
end

local function near(actual, expected, message)
  check(type(actual) == "number" and math.abs(actual - expected) < 0.00001,
    ("%s (expected %.5f, got %s)")
      :format(message, expected, tostring(actual)))
end

local unpackValues = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local modulePath = sourceRoot .. "/modules/thor_dual_screen.lua"
local function loadThor()
  return assert(loadfile(modulePath), "missing " .. modulePath)()
end

-- The two released engine fixtures expose the same documented seams. These
-- static checks make the behavioral harness below fail closed if either seam
-- changes instead of silently testing an invented API.
local function verifyEngineContract(profile)
  local second = assert(read(profile.path .. "/src/render/SecondScreen.lua"),
    profile.label .. " SecondScreen.lua missing")
  local renderer = assert(read(profile.path .. "/src/render/Renderer.lua"),
    profile.label .. " Renderer.lua missing")
  local hooks = assert(read(profile.path .. "/src/mods/Hooks.lua"),
    profile.label .. " Hooks.lua missing")
  local battle = assert(read(profile.path .. "/src/battle/BattleState.lua"),
    profile.label .. " BattleState.lua missing")
  local activity = assert(read(profile.path
      .. "/mobile/android/love/src/main/java/org/love2d/android/GameActivity.java"),
    profile.label .. " GameActivity.java missing")
  check(second:find("function SecondScreen.available()", 1, true),
    profile.label .. " publishes live availability")
  check(second:find("function SecondScreen.push(imageData, w, h)", 1, true),
    profile.label .. " publishes sized frame push")
  check(second:find("function SecondScreen.setEnabled(on)", 1, true),
    profile.label .. " publishes presentation enable")
  check(renderer:find("worldOverride = self.worldOverride", 1, true),
    profile.label .. " compose context publishes worldOverride")
  check(renderer:find("secondScreen = require(\"src.render.SecondScreen\")",
    1, true), profile.label .. " compose context publishes SecondScreen")
  check(renderer:find("Runtime.call(\"render.compose\"", 1, true),
    profile.label .. " renderer calls public compose seam")
  check(hooks:find("a.priority > b.priority", 1, true),
    profile.label .. " highest-priority presenter is outermost")
  check(activity:find("public static void setSecondaryEnabled", 1, true),
    profile.label .. " publishes native presentation activation")
  check(activity:find("return secondaryPresentation != null;", 1, true),
    profile.label .. " reports unavailable until activation creates a presentation")
  check(battle:find("Font.drawBox(0, 12, 20, 6)", 1, true),
    profile.label .. " keeps dialogue in the classic y=96..143 band")
  check(battle:find("Font.drawBox(0, 8, 11, 5)", 1, true),
    profile.label .. " keeps TYPE/PP at the classic y=64 start")
  check(battle:find("Font.drawBox(4, 12, 16, 6)", 1, true),
    profile.label .. " keeps the move list joined below TYPE/PP")
  check(battle:find("Font.drawBox(0, 7, 16, 6)", 1, true),
    profile.label .. " keeps Mimic controls in the classic y=56 band")
end

for _, profile in ipairs(engineRoots) do verifyEngineContract(profile) end

local Hooks = {}
Hooks.__index = Hooks
function Hooks.new()
  return setmetatable({ chains = {} }, Hooks)
end
function Hooks:wrap(name, callback, priority, owner)
  local chain = self.chains[name] or {}
  self.chains[name] = chain
  chain[#chain + 1] = {
    callback = callback, priority = priority or 0, owner = owner,
  }
  table.sort(chain, function(a, b) return a.priority > b.priority end)
end
function Hooks:count(name, owner)
  local count = 0
  for _, entry in ipairs(self.chains[name] or {}) do
    if owner == nil or entry.owner == owner then count = count + 1 end
  end
  return count
end
function Hooks:call(name, vanilla, ...)
  local chain = self.chains[name] or {}
  local args = pack(...)
  local function run(index)
    if index > #chain then return vanilla(unpackValues(args, 1, args.n)) end
    local entry = chain[index]
    local function nextFn(...)
      if select("#", ...) == 0 then return run(index + 1) end
      local previous = args
      args = pack(...)
      local results = pack(run(index + 1))
      args = previous
      return unpackValues(results, 1, results.n)
    end
    return entry.callback(nextFn, unpackValues(args, 1, args.n))
  end
  return run(1)
end

local Events = {}
Events.__index = Events
function Events.new()
  return setmetatable({ listeners = {} }, Events)
end
function Events:on(name, callback)
  local listeners = self.listeners[name] or {}
  self.listeners[name] = listeners
  listeners[#listeners + 1] = callback
end
function Events:count(name)
  return #(self.listeners[name] or {})
end
function Events:emit(name, payload)
  for _, callback in ipairs(self.listeners[name] or {}) do callback(payload) end
end

local function copyArray(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = item end
  return out
end

local function fakeGraphics()
  local graphics = {
    canvases = {}, images = {}, screenDraws = {}, screenClears = 0,
    state = {
      canvas = nil, color = { 0.2, 0.3, 0.4, 0.5 },
      scissor = { 7, 8, 9, 10 }, origin = 17,
      shader = { name = "baseline-shader" },
    },
    stack = {}, failReadback = false, failDrawSource = nil,
  }

  local function canvas(width, height, opts, external, name)
    local out = {
      kind = external and "external" or "canvas",
      name = name, width = width, height = height, options = opts,
      draws = {}, blits = {}, rectangles = {}, clears = 0, released = 0,
    }
    function out:getDimensions() return self.width, self.height end
    function out:getWidth() return self.width end
    function out:getHeight() return self.height end
    function out:setFilter(min, mag, anisotropy)
      self.filter = { min, mag, anisotropy }
    end
    function out:release()
      self.released = self.released + 1
      if self.released > 1 then error("canvas released more than once: "
        .. tostring(self.name), 0) end
    end
    function out:newImageData()
      if graphics.failReadback then error("injected readback failure", 0) end
      local image = {
        source = self, width = self.width, height = self.height, released = 0,
      }
      function image:release()
        self.released = self.released + 1
        if self.released > 1 then error("image released more than once", 0) end
      end
      graphics.images[#graphics.images + 1] = image
      return image
    end
    if not external then graphics.canvases[#graphics.canvases + 1] = out end
    return out
  end

  function graphics.external(width, height, name)
    return canvas(width, height, nil, true, name)
  end
  function graphics.newCanvas(width, height, opts)
    return canvas(width, height, opts, false,
      ("owned-%d-%dx%d"):format(#graphics.canvases + 1, width, height))
  end
  function graphics.newQuad(...)
    return { kind = "quad", args = pack(...) }
  end
  function graphics.push(mode)
    graphics.stack[#graphics.stack + 1] = {
      canvas = graphics.state.canvas,
      color = copyArray(graphics.state.color),
      scissor = copyArray(graphics.state.scissor),
      origin = graphics.state.origin,
      shader = graphics.state.shader,
      mode = mode,
    }
  end
  function graphics.pop()
    local state = table.remove(graphics.stack)
    assert(state, "graphics pop without push")
    graphics.state = state
  end
  function graphics.setCanvas(target) graphics.state.canvas = target end
  function graphics.getCanvas() return graphics.state.canvas end
  function graphics.origin() graphics.state.origin = 0 end
  function graphics.clear(...)
    local target = graphics.state.canvas
    if target then
      target.clears = target.clears + 1
      target.draws, target.blits, target.rectangles = {}, {}, {}
    else
      graphics.screenClears = graphics.screenClears + 1
      graphics.screenDraws = {}
    end
  end
  function graphics.setColor(...) graphics.state.color = { ... } end
  function graphics.setShader(shader) graphics.state.shader = shader end
  function graphics.setScissor(...)
    graphics.state.scissor = select("#", ...) == 0 and nil or { ... }
  end
  function graphics.rectangle(mode, x, y, width, height)
    local target = graphics.state.canvas
    if not target then return end
    target.rectangles[#target.rectangles + 1] = {
      mode = mode, x = x, y = y, width = width, height = height,
      color = copyArray(graphics.state.color),
    }
  end
  function graphics.draw(source, ...)
    if graphics.failDrawSource == source then error("injected draw failure", 0) end
    local args = pack(...)
    local offset, quad = 0, nil
    if type(args[1]) == "table" and args[1].kind == "quad" then
      quad, offset = args[1], 1
    end
    local draw = {
      source = source, quad = quad,
      x = args[1 + offset], y = args[2 + offset],
      rotation = args[3 + offset], sx = args[4 + offset],
      sy = args[5 + offset], target = graphics.state.canvas,
    }
    local target = graphics.state.canvas
    if target then
      target.draws[#target.draws + 1] = draw
    else
      graphics.screenDraws[#graphics.screenDraws + 1] = draw
    end
  end
  function graphics.resetFrame()
    graphics.screenDraws = {}
    graphics.screenClears = 0
  end
  return graphics
end

local function fakeBridge(opts)
  opts = opts or {}
  local bridge = {
    availableFlag = opts.availableFlag ~= false,
    enables = {}, pushes = {}, touchPolls = 0,
    failPush = false, enablePending = false,
  }
  function bridge.available() return bridge.availableFlag end
  function bridge.setEnabled(on)
    bridge.enables[#bridge.enables + 1] = on == true
    if opts.asyncEnable then
      bridge.enablePending = on == true
      if not on then bridge.availableFlag = false end
    elseif opts.enableControlsAvailability then
      bridge.availableFlag = on == true
    end
  end
  function bridge.completeEnable()
    if bridge.enablePending then bridge.availableFlag = true end
    bridge.enablePending = false
  end
  function bridge.push(image, width, height)
    bridge.pushes[#bridge.pushes + 1] = {
      image = image, source = image and image.source,
      width = width, height = height,
    }
    return not bridge.failPush
  end
  function bridge.pollTouch()
    bridge.touchPolls = bridge.touchPolls + 1
    return nil
  end
  return bridge
end

local function findDraw(draws, source)
  for _, draw in ipairs(draws or {}) do
    if draw.source == source then return draw end
  end
  return nil
end

local function makeFixture(opts)
  opts = opts or {}
  local graphics = opts.graphics or fakeGraphics()
  local bridge = opts.bridge or fakeBridge(opts.bridgeOptions)
  local hooks = opts.hooks or Hooks.new()
  local events = opts.events or Events.new()
  local optionValues = opts.optionValues or { dual_screen = true }
  local handles = opts.handles or {}
  if opts.legacy then handles.gen1recomp_ds = { exports = {} } end
  local warnings = {}
  local clock = opts.clock or { value = 0 }
  local mod = {
    id = "voxel_run_bridge", exports = {},
    options = { values = optionValues },
    hooks = {}, events = {}, log = {},
  }
  function mod.options:get(key) return self.values[key] end
  function mod.hooks:wrap(name, callback, priority)
    return hooks:wrap(name, callback, priority, mod.id)
  end
  function mod.events:on(name, callback)
    return events:on(name, callback)
  end
  function mod:find(id) return handles[id] end
  function mod.log:warn(format, ...)
    warnings[#warnings + 1] = tostring(format):format(...)
  end

  local renderer = { calls = {} }
  function renderer:blitCanvas(source, ...)
    local target = graphics.state.canvas
    local args = pack(...)
    local call = {
      source = source, target = target, args = args,
      prepared = source and source.prepared,
    }
    self.calls[#self.calls + 1] = call
    if target then target.blits[#target.blits + 1] = call end
  end

  local modernMarker = { name = "modern-ui-hud" }
  local overlayMarker = { name = "controller-overlay" }
  local modernComposeCalls, modernHudCalls, overlayCalls = 0, 0, 0
  local function addProviders()
    hooks:wrap("render.compose", function(nextFn, liveRenderer, ctx)
      local results = pack(nextFn(liveRenderer, ctx))
      modernComposeCalls = modernComposeCalls + 1
      if ctx.uiCanvas then ctx.uiCanvas.prepared = modernComposeCalls end
      return unpackValues(results, 1, results.n)
    end, 100, "gen1_modern_ui")
    hooks:wrap("render.hud", function(nextFn, game, viewport)
      local results = pack(nextFn(game, viewport))
      modernHudCalls = modernHudCalls + 1
      graphics.draw(modernMarker, 11, 12, 0, 1, 1)
      return unpackValues(results, 1, results.n)
    end, 100, "gen1_modern_ui")
    hooks:wrap("render.hud", function(nextFn, game, viewport)
      local results = pack(nextFn(game, viewport))
      overlayCalls = overlayCalls + 1
      graphics.draw(overlayMarker, 21, 22, 0, 1, 1)
      return unpackValues(results, 1, results.n)
    end, 10000, "voxel_run_bridge_overlay")
  end

  local function context(kind)
    local ctx = {
      renderer = renderer,
      worldCanvas = graphics.external(160, 144, "world-canvas"),
      uiCanvas = graphics.external(160, 144, "ui-canvas"),
      worldOverride = graphics.external(800, 480, "world-override"),
      worldActive = true,
      zones = {}, worldZones = {},
      ww = 800, wh = 480, pw = 800, ph = 480,
      uiw = 160, uih = 144, dpiX = 1, dpiY = 1,
      secondScreen = bridge,
    }
    if kind == "menu" then
      ctx.worldOverride = nil
      ctx.worldCanvas = nil
      ctx.worldActive = false
    elseif kind == "classic" then
      ctx.worldOverride = nil
      ctx.worldActive = true
    end
    return ctx
  end

  local function frame(ctx)
    graphics.resetFrame()
    local before = {
      canvas = graphics.state.canvas,
      color = copyArray(graphics.state.color),
      scissor = copyArray(graphics.state.scissor),
      origin = graphics.state.origin,
      shader = graphics.state.shader,
    }
    local handled = hooks:call("render.compose", function() return false end,
      renderer, ctx)
    local hudCalls = 0
    local first, middle, tail = hooks:call("render.hud", function()
      hudCalls = hudCalls + 1
      return "hud", nil, "tail"
    end, {}, {
      width = ctx.ww, height = ctx.wh,
      gameX = 0, gameY = 0, gameWidth = ctx.ww, gameHeight = ctx.wh,
    })
    return {
      handled = handled, hudCalls = hudCalls,
      first = first, middle = middle, tail = tail,
      before = before,
    }
  end

  return {
    graphics = graphics, bridge = bridge, hooks = hooks, events = events,
    mod = mod, handles = handles, warnings = warnings, clock = clock,
    renderer = renderer, addProviders = addProviders,
    context = context, frame = frame,
    modernMarker = modernMarker, overlayMarker = overlayMarker,
    providerCounts = function()
      return modernComposeCalls, modernHudCalls, overlayCalls
    end,
  }
end

local function installFixture(fixture, Thor)
  local controller = Thor.install(fixture.mod, {
    optionKey = "dual_screen", graphics = fixture.graphics,
    now = function() return fixture.clock.value end,
  })
  fixture.controller = controller
  fixture.addProviders()
  return controller
end

-- Mirrors the production Free Fly cockpitOverlay export and its HUD routing
-- decision without replacing either presenter's implementation. The provider
-- draws distinct rider/mount markers so ownership of both halves is visible.
local function installFreeFlyProbe(fixture)
  local state = {
    airborne = true,
    firstPerson = true,
    calls = 0,
  }
  local rider = { name = "free-fly-rider" }
  local mount = { name = "free-fly-mount" }
  local provider = {
    apiVersion = 1,
    kind = "player_mount",
  }
  provider.draw = function(game, viewport, opts)
    state.calls = state.calls + 1
    state.lastGame = game
    state.lastViewport = viewport
    state.lastOptions = opts
    if opts and opts.fullComposite == true then
      fixture.graphics.draw(rider, 300, 200, 0, 1, 1)
    end
    fixture.graphics.draw(mount, 300, 220, 0, 1, 1)
    return true
  end
  fixture.hooks:wrap("render.hud", function(nextFn, game, viewport)
    local results = pack(nextFn(game, viewport))
    state.routedViewport = viewport
    if state.airborne and state.firstPerson then
      local route = viewport
        and viewport._scottsTweaksThorRouteWorldOverlay
      local accepted = type(route) == "function"
        and route(provider, "free_fly") == true
      if not accepted then provider.draw(game, viewport) end
    end
    return unpackValues(results, 1, results.n)
  end, 0, "free_fly")
  return state, provider, rider, mount
end

local Thor = loadThor()
eq(Thor.API_VERSION, 1, "presenter API version is stable")
local BattleStage = assert(loadfile(sourceRoot .. "/lib/BattleStage.lua"),
  "missing BattleStage.lua")()
eq(BattleStage.API_VERSION, 3,
  "Battle Stage v3 publishes split-presentation control")
local stageSplit = false
local stageApi = BattleStage.export({
  ANCHOR = { player = { 26, 96 }, enemy = { 124, 56 } },
  battle = function() return {} end,
  splitPresentation = function() return stageSplit end,
  setSplitPresentation = function(on) stageSplit = on == true return true end,
})
eq(stageApi.setSplitPresentation(true), true,
  "Battle Stage accepts a physical split request")
eq(stageSplit, true, "Battle Stage forwards the split request to renderer state")
eq(stageApi.state().splitPresentation, true,
  "Battle Stage state reports the active split")
eq(stageApi.setSplitPresentation(false), true,
  "Battle Stage restores ordinary single-screen composition")
eq(Thor.OUTPUT_WIDTH, 400, "logical lower width is transport-sized")
eq(Thor.OUTPUT_HEIGHT, 360, "logical lower height is transport-sized")
near(Thor.OUTPUT_WIDTH / Thor.OUTPUT_HEIGHT, 10 / 9,
  "logical lower surface preserves exact Game Boy aspect")
local integerFit = assert(Thor.integerContain(160, 144, 400, 360))
eq(integerFit.scaleX, 2, "Game Boy pixels stay at a crisp integer scale")
eq(integerFit.x, 40, "integer playfield is horizontally centered")
eq(integerFit.y, 36, "integer playfield is vertically centered")
eq(integerFit.width, 320, "Modern UI receives a readable 320px playfield")
eq(integerFit.height, 288, "Modern UI receives a readable 288px playfield")
eq(Thor.enabledValue("off"), false, "OFF option string is false")
eq(Thor.enabledValue("on"), true, "ON option string is true")
local dialogueRegion = assert(Thor.battlePanelRegion("messages", 160, 144))
eq(dialogueRegion.y, 96, "ordinary battle wording owns the bottom 48px band")
eq(dialogueRegion.height, 48, "ordinary battle wording keeps its full box")
local moveRegion = assert(Thor.battlePanelRegion("moveSelect", 160, 144))
eq(moveRegion.y, 64, "move controls begin at the TYPE/PP panel")
eq(moveRegion.height, 80, "TYPE/PP and move list remain one joined cluster")
eq(Thor.battlePanelRegion("messages", 304, 144), nil,
  "wide and unknown battle layouts retain their complete surface")

-- Android's native Presentation does not exist until setEnabled(true) posts
-- to its UI thread.  A saved ON option must issue that request before asking
-- available(), then take over the same menu once the asynchronous attach
-- completes; no OFF/ON toggle or close/reopen cycle is involved.
local startupBridge = fakeBridge({ availableFlag = false, asyncEnable = true })
local startup = makeFixture({ bridge = startupBridge })
installFixture(startup, loadThor())
local startupMenu = startup.context("menu")
eq(startup.frame(startupMenu).handled, false,
  "cold menu falls through while Android completes its attach")
eq(#startupBridge.enables, 1,
  "saved ON issues one native enable request on the first compose")
eq(startupBridge.enables[1], true,
  "cold-start native request uses the saved ON value")
eq(startupBridge.enablePending, true,
  "cold-start request is pending on the simulated Android UI thread")
startupBridge.completeEnable()
startup.clock.value = 0.04
eq(startup.frame(startupMenu).handled, true,
  "the same already-open menu activates after native attach")
eq(#startupBridge.enables, 1,
  "automatic attach does not repeat or require an option toggle")
eq(#startupBridge.pushes, 1,
  "already-open menu reaches the lower display immediately after attach")
eq(startup.controller.status().topSource, "blank",
  "a neutral primary lets a cold menu split before the first world frame")
local startupTop = startup.graphics.screenDraws[1]
  and startup.graphics.screenDraws[1].source
check(startupTop and startupTop.clears == 1 and #startupTop.draws == 0,
  "cold-menu primary is a clean neutral surface")
startup.clock.value = 0.08
eq(startup.frame(startup.context("live")).handled, true,
  "the first live frame replaces the neutral primary without reopening UI")
eq(startup.controller.status().topSource, "worldOverride",
  "cold-start handoff adopts the first staged world normally")

-- Full physical path: Battle Art arena and move effect stay on top while the
-- finished classic/Modern UI and later HUD overlays are captured below.
local fixture = makeFixture()
local battle, effect = {}, fixture.graphics.external(160, 144, "move-effect")
fixture.handles.BATTLE_ART_VOXEL_FORK = {
  exports = { battleStage = {
    apiVersion = 2,
    state = function()
      return { battle = battle, staged = true, ready = true }
    end,
    animationSurface = function(expected)
      if expected ~= battle then return nil end
      return { canvas = effect, lx = 80, ly = 24, scale = 3,
        pw = 800, ph = 480 }
    end,
  } },
}
local controller = installFixture(fixture, Thor)
eq(fixture.hooks:count("render.compose", fixture.mod.id), 1,
  "one outer compose wrapper is installed")
eq(fixture.hooks:count("render.hud", fixture.mod.id), 1,
  "one outer HUD wrapper is installed")
eq(fixture.hooks:count("core.quit_to_launcher", fixture.mod.id), 1,
  "one quit wrapper is installed")
eq(fixture.events:count("mod.options_changed"), 1,
  "one option dispatcher is installed")
eq(fixture.events:count("screen.pushed"), 1,
  "one Start-layout push dispatcher is installed")
eq(fixture.events:count("screen.popped"), 1,
  "one Start-layout restoration dispatcher is installed")

local liveCtx = fixture.context("live")
local live = fixture.frame(liveCtx)
eq(live.handled, true, "attached Thor owns the primary composition")
eq(live.hudCalls, 1, "HUD chain runs exactly once")
eq(live.first, "hud", "HUD first return is preserved")
eq(live.middle, nil, "HUD interior nil return is preserved")
eq(live.tail, "tail", "HUD tail return is preserved")
eq(#fixture.bridge.enables, 1, "native presentation is enabled once")
eq(fixture.bridge.enables[1], true, "native presentation enable is ON")
eq(#fixture.bridge.pushes, 1, "one completed lower frame is pushed")
eq(fixture.bridge.pushes[1].width, 400, "lower push uses logical width")
eq(fixture.bridge.pushes[1].height, 360, "lower push uses logical height")
local lower = fixture.bridge.pushes[1].source
check(lower and lower.width == 400 and lower.height == 360,
  "pushed source is the DPI-stable logical lower canvas")
eq(lower.options and lower.options.dpiscale, 1,
  "lower canvas has explicit one-to-one texels")
eq(lower.filter and lower.filter[1], "nearest",
  "lower canvas keeps pixel art nearest-filtered")
check(#lower.blits == 1 and lower.blits[1].prepared == 1,
  "lower uiCanvas is staged after Modern UI compose")
eq(lower.blits[1].args[1], 2, "lower uiCanvas blit is integer-scaled")
eq(lower.blits[1].args[6], 40, "lower uiCanvas x offset is centered")
eq(lower.blits[1].args[7], 36, "lower uiCanvas y offset is centered")
check(findDraw(lower.draws, fixture.modernMarker) ~= nil,
  "Modern UI presenter draws into lower canvas")
check(findDraw(lower.draws, fixture.overlayMarker) ~= nil,
  "later controller HUD contribution draws into lower canvas")
check(findDraw(fixture.graphics.screenDraws, fixture.modernMarker) == nil,
  "Modern UI is absent from the upper scene")
check(findDraw(fixture.graphics.screenDraws, fixture.overlayMarker) == nil,
  "lower HUD overlay is absent from the upper scene")
local upper = fixture.graphics.screenDraws[1]
  and fixture.graphics.screenDraws[1].source
check(upper and findDraw(upper.draws, liveCtx.worldOverride) ~= nil,
  "Battle Art worldOverride is the upper scene source")
local effectDraw = assert(findDraw(fixture.graphics.screenDraws, effect),
  "Battle Stage v2 move effect is projected onto upper scene")
eq(effectDraw.x, 80, "move effect keeps Battle Art x projection")
eq(effectDraw.y, 24, "move effect keeps Battle Art y projection")
eq(effectDraw.sx, 3, "move effect keeps Battle Art scale")
eq(effectDraw.sy, 3, "move effect uses the same y scale")
eq(fixture.bridge.pushes[1].image.released, 1,
  "synchronous bridge readback image is released once")
eq(fixture.bridge.touchPolls, 0, "presenter never polls touch input")
eq(fixture.graphics.state.canvas, live.before.canvas,
  "graphics canvas target is restored")
eq(fixture.graphics.state.origin, live.before.origin,
  "graphics transform state is restored")
eq(fixture.graphics.state.color[1], live.before.color[1],
  "graphics color state is restored")
eq(fixture.graphics.state.scissor[1], live.before.scissor[1],
  "graphics scissor state is restored")
eq(fixture.graphics.state.shader, live.before.shader,
  "graphics shader state is restored")
local status = controller.status()
eq(status.active, true, "public status reports active presentation")
eq(status.attached, true, "public status reports attached display")
eq(status.controllerOnly, true, "public status records controller-only policy")
eq(status.touchPolling, false, "public status records no touch translation")
eq(status.outputPolicy, "logical_10_9_integer_scaled",
  "public status explains device-neutral output policy")

-- Staged classic battles compact only their control band toward the hinge.
-- The TYPE/PP panel and move list travel together, while a full-screen battle
-- submenu (waitingUI) keeps the ordinary centered surface.
local panelFixture = makeFixture()
local panelBattle = { phase = "messages" }
panelFixture.mod.exports.battleStage = {
  apiVersion = 2,
  state = function()
    return { battle = panelBattle, staged = true, ready = true }
  end,
  animationSurface = function() return nil end,
}
installFixture(panelFixture, loadThor())
local panelCtx = panelFixture.context("live")
eq(panelFixture.frame(panelCtx).handled, true,
  "staged dialogue frame owns physical composition")
local panelLower = panelFixture.bridge.pushes[1].source
local panelBlit = assert(panelLower.blits[1], "dialogue panel blit missing")
eq(panelBlit.args[7], -180,
  "dialogue source origin moves its y=96 box to the hinge margin")
eq(panelBlit.args[9], Thor.BATTLE_PANEL_TOP,
  "dialogue destination begins at the lower screen top margin")
eq(panelBlit.args[11], 96,
  "dialogue scissor keeps the complete 48px box at crisp 2x")

panelBattle.phase = "moveSelect"
panelFixture.clock.value = 1
eq(panelFixture.frame(panelCtx).handled, true,
  "move-selection frame keeps physical composition")
panelBlit = assert(panelLower.blits[1], "move panel blit missing")
eq(panelBlit.args[7], -116,
  "move source origin places TYPE/PP at the same hinge margin")
eq(panelBlit.args[9], Thor.BATTLE_PANEL_TOP,
  "TYPE/PP panel starts where ordinary dialogue starts")
eq(panelBlit.args[11], 160,
  "move scissor keeps the joined 80px control cluster at crisp 2x")
eq(panelBlit.args[7] + 96 * panelBlit.args[2], 76,
  "move-list panel follows immediately below TYPE/PP at authored spacing")
local movePaper = assert(panelLower.rectangles[1],
  "move-selection upper-right paper fill missing")
eq(movePaper.mode, "fill", "move-selection gap uses an opaque fill")
eq(movePaper.x, 216,
  "move-selection paper begins immediately right of TYPE/PP")
eq(movePaper.y, Thor.BATTLE_PANEL_TOP,
  "move-selection paper shares the TYPE/PP top edge")
eq(movePaper.width, 144,
  "move-selection paper reaches the joined panel's right edge")
eq(movePaper.height, 64,
  "move-selection paper ends where the move-list box begins")
eq(movePaper.color[1], 1,
  "move-selection transparent gap is filled with white paper")

panelBattle.phase = "mimicSelect"
panelFixture.clock.value = 1.5
eq(panelFixture.frame(panelCtx).handled, true,
  "Mimic selection keeps physical composition")
local mimicPaper = assert(panelLower.rectangles[1],
  "Mimic-selection upper-right paper fill missing")
eq(mimicPaper.x, 296,
  "Mimic paper starts immediately right of its authored box")
eq(mimicPaper.y, Thor.BATTLE_PANEL_TOP,
  "Mimic paper shares the popup's top edge")
eq(mimicPaper.width, 64,
  "Mimic paper reaches the joined panel's right edge")
eq(mimicPaper.height, 80,
  "Mimic paper meets the full-width wording box below")

-- BattleState:sayChoice owns the question in its y=96 message band and
-- pushes a standalone ChoiceBox above it. Compose those authored regions as
-- question then answer instead of centering their old answer-above-question
-- source positions on Thor.
local battleChoice = {
  onChoose = function() end, index = 1,
  tx = 14, ty = 7, tw = 6, th = 5,
}
local battleStack = { states = { panelBattle, battleChoice } }
function battleStack:top() return self.states[#self.states] end
panelFixture.mod.game = { stack = battleStack }
panelBattle.phase = "messages"
panelBattle.waitingUI = true
panelBattle.current = { choice = function() end }
panelFixture.clock.value = 1.75
eq(panelFixture.frame(panelCtx).handled, true,
  "battle choice prompt keeps physical composition")
eq(#panelLower.blits, 2,
  "battle choice composes question and answer as separate authored regions")
local questionBlit, answerBlit = panelLower.blits[1], panelLower.blits[2]
eq(questionBlit.args[7], -180,
  "battle-choice question moves from y=96 to the hinge margin")
eq(questionBlit.args[9], Thor.BATTLE_PANEL_TOP,
  "battle-choice question is the first panel")
eq(questionBlit.args[11], 96,
  "battle-choice question retains its complete six-tile frame")
eq(answerBlit.args[6], 40,
  "answer source offset preserves the authored right alignment")
eq(answerBlit.args[7], -4,
  "answer source moves directly below the question")
eq(answerBlit.args[8], 264,
  "answer box remains right-aligned inside the paper band")
eq(answerBlit.args[9], 108,
  "answer box begins immediately below the question")
eq(answerBlit.args[10], 96,
  "answer crop retains the complete six-tile width")
eq(answerBlit.args[11], 80,
  "answer crop retains the complete five-tile height")
local answerPaper = assert(panelLower.rectangles[1],
  "battle-choice horizontal paper band missing")
eq(answerPaper.x, 40,
  "battle-choice paper begins at the classic UI left edge")
eq(answerPaper.y, 108,
  "battle-choice paper begins only on the answer row")
eq(answerPaper.width, 320,
  "battle-choice paper fills left and right of the answer")
eq(answerPaper.height, 80,
  "battle-choice paper is limited to the answer row")

panelBattle.current = nil
panelFixture.mod.game = {
  stack = { states = {}, top = function() return { isOpaque = true } end },
}
panelBattle.waitingUI = true
panelFixture.clock.value = 2
eq(panelFixture.frame(panelCtx).handled, true,
  "full-screen battle submenu keeps physical presentation")
panelBlit = assert(panelLower.blits[1], "full submenu blit missing")
eq(panelBlit.args[7], 36,
  "full-screen battle submenu retains ordinary centered placement")
eq(panelBlit.args[9], 0,
  "full-screen battle submenu retains the complete output scissor")
eq(panelBlit.args[11], Thor.OUTPUT_HEIGHT,
  "full-screen battle submenu is never cropped to the dialogue band")

panelBattle.waitingUI = nil
panelBattle.game = { stack = { top = function() return { isOpaque = true } end } }
panelFixture.clock.value = 3
eq(panelFixture.frame(panelCtx).handled, true,
  "an arbitrary overlay above battle keeps physical presentation")
panelBlit = assert(panelLower.blits[1], "stack-overlay blit missing")
eq(panelBlit.args[7], 36,
  "live stack identity prevents cropping settings and other overlays")
eq(panelBlit.args[11], Thor.OUTPUT_HEIGHT,
  "stack overlay keeps the complete lower-screen UI surface")

-- Ordinary overworld TextBox states use the same hinge-side placement as
-- battle wording, even with CENTERED UI selected in the engine. The crop is
-- performed only in the private lower canvas; the upper world stays intact.
local dialogueFixture = makeFixture()
local dialogueState = {
  isTextBox = true,
  boxTx = 0, boxTy = 12, boxTw = 20, boxTh = 6,
}
dialogueFixture.mod.game = {
  stack = { top = function() return dialogueState end },
}
installFixture(dialogueFixture, loadThor())
local dialogueCtx = dialogueFixture.context("live")
eq(dialogueFixture.frame(dialogueCtx).handled, true,
  "ordinary overworld dialogue keeps the Thor split active")
local dialogueLower = dialogueFixture.bridge.pushes[1].source
local dialogueBlit = assert(dialogueLower.blits[1],
  "ordinary dialogue lower blit missing")
eq(dialogueBlit.args[1], 2,
  "ordinary dialogue retains crisp 2x Game Boy pixels")
eq(dialogueBlit.args[7], -180,
  "ordinary dialogue source y=96 moves to the hinge margin")
eq(dialogueBlit.args[9], Thor.BATTLE_PANEL_TOP,
  "ordinary dialogue begins at the top of the lower display")
eq(dialogueBlit.args[11], 96,
  "ordinary dialogue keeps the complete six-tile box")
local dialogueUpper = dialogueFixture.graphics.screenDraws[1]
  and dialogueFixture.graphics.screenDraws[1].source
check(dialogueUpper
    and findDraw(dialogueUpper.draws, dialogueCtx.worldOverride) ~= nil,
  "ordinary dialogue relocation leaves the primary world unchanged")

dialogueState = {
  -- 0.1.75 TextBox shape: no isTextBox marker yet.
  boxTx = 0, boxTy = 12, boxTw = 20, boxTh = 6,
  maxCols = 18, textX = 8, line1Y = 112, line2Y = 128,
  pages = { { "HELLO" } }, shown = {},
  pageIndex = 1, lineIndex = 1, charIndex = 0,
  waiting = false, done = false,
}
dialogueFixture.clock.value = 1
eq(dialogueFixture.frame(dialogueCtx).handled, true,
  "0.1.75-shaped dialogue keeps the Thor split active")
dialogueBlit = assert(dialogueLower.blits[1],
  "0.1.75-shaped dialogue lower blit missing")
eq(dialogueBlit.args[7], -180,
  "0.1.75 dialogue uses the same top-docked source origin")
eq(dialogueBlit.args[11], 96,
  "0.1.75 dialogue retains its complete six-tile frame")

local textboxPrompt = dialogueState
local textboxChoice = {
  onChoose = function() end, index = 2, anchor = "bottom",
  tx = 14, ty = 7, tw = 6, th = 5,
}
local dialogueStack = dialogueFixture.mod.game.stack
dialogueStack.states = { textboxPrompt, textboxChoice }
function dialogueStack:top() return self.states[#self.states] end
dialogueFixture.clock.value = 1.5
eq(dialogueFixture.frame(dialogueCtx).handled, true,
  "TextBox-backed choice prompt keeps the Thor split active")
eq(#dialogueLower.blits, 2,
  "TextBox choice composes the prompt and answer independently")
questionBlit, answerBlit = dialogueLower.blits[1], dialogueLower.blits[2]
eq(questionBlit.args[9], Thor.BATTLE_PANEL_TOP,
  "TextBox question remains top-docked")
eq(questionBlit.args[11], 96,
  "TextBox question keeps the complete six-tile panel")
eq(answerBlit.args[9], 108,
  "TextBox answer follows directly beneath its question")
eq(answerBlit.args[10], 96,
  "TextBox answer keeps the authored narrow width")
local textboxPaper = assert(dialogueLower.rectangles[1],
  "TextBox-choice horizontal paper band missing")
eq(textboxPaper.x, 40,
  "TextBox-choice paper starts at the prompt's left edge")
eq(textboxPaper.width, 320,
  "TextBox-choice paper fills only the answer's horizontal band")
eq(textboxPaper.height, 80,
  "TextBox-choice paper does not fill the lower-screen remainder")

dialogueStack.states = nil
dialogueStack.top = function() return dialogueState end
dialogueState = {
  -- A menu-like state can expose box geometry, but has no typewriter model.
  boxTx = 0, boxTy = 12, boxTw = 20, boxTh = 6,
  items = { {} }, index = 1,
}
dialogueFixture.clock.value = 2
eq(dialogueFixture.frame(dialogueCtx).handled, true,
  "menu-like geometry still keeps physical presentation")
dialogueBlit = assert(dialogueLower.blits[1],
  "menu-like full-surface blit missing")
eq(dialogueBlit.args[7], 36,
  "box geometry alone cannot trigger the old TextBox fallback")
eq(dialogueBlit.args[11], Thor.OUTPUT_HEIGHT,
  "a non-dialogue state keeps the complete lower surface")

-- The physical Start menu keeps the original bordered Menu renderer, normal
-- 2x text and double-spaced rows. Eight visible rows use the available height
-- without stretching the narrow box across the lower screen. screen.popped
-- still restores the exact single-screen values.
local startFixture = makeFixture()
local activeStartState
startFixture.mod.game = {
  stack = { top = function() return activeStartState end },
}
local startController = installFixture(startFixture, loadThor())
eq(startFixture.frame(startFixture.context("live")).handled, true,
  "a live frame binds the attached Thor before Start opens")
local startState = {
  screenId = "StartMenu",
  items = { {}, {}, {}, {}, {}, {}, {}, {} },
  index = 1, scroll = 0,
  tx = 9, ty = 0, tw = 11, th = 18,
  rowStep = 2, maxVisible = 8,
}
function startState:clampScroll()
  if self.index - self.scroll > self.maxVisible then
    self.scroll = self.index - self.maxVisible
  elseif self.index - self.scroll < 1 then
    self.scroll = self.index - 1
  end
end
activeStartState = startState
startFixture.events:emit("screen.pushed", { state = startState })
eq(startState.maxVisible, 8,
  "physical Start menu shows all eight original rows at once")
eq(startState.th, 18,
  "physical Start menu keeps double spacing in an eighteen-tile frame")
startFixture.clock.value = 1
eq(startFixture.frame(startFixture.context("live")).handled, true,
  "vertically expanded Start menu keeps the Thor split active")
local startLower = startFixture.bridge.pushes[#startFixture.bridge.pushes].source
local startBlit = assert(startLower.blits[1],
  "vertically expanded Start-menu blit missing")
eq(startBlit.args[1], 2,
  "Start menu artwork and text use the normal crisp 2x scale")
eq(startBlit.args[6], -32,
  "Start menu source origin centers its narrow authored box")
eq(startBlit.args[7], 36,
  "Start menu is vertically centered in the lower display")
eq(startBlit.args[8], 112,
  "Start menu visible box is horizontally centered")
eq(startBlit.args[9], 36,
  "Start menu visible box uses the full-height composition margin")
eq(startBlit.args[10], 176,
  "Start menu retains its authored narrow width at normal scale")
eq(startBlit.args[11], 288,
  "Start menu uses the normal UI viewport's full vertical height")
startFixture.events:emit("screen.popped", { state = startState })
eq(startState.maxVisible, 8,
  "closing physical Start restores the original visible-row count")
eq(startState.th, 18,
  "closing physical Start restores the original frame height")

-- A developer F5 can happen while Start is still open. The retiring runtime
-- must first remove its live geometry decoration; if the replacement cannot
-- attach (simulated here by unplugging the panel), ordinary single-screen
-- dimensions must be left behind rather than stale Thor-owned geometry.
startFixture.events:emit("screen.pushed", { state = startState })
eq(startState.maxVisible, 8,
  "open Start menu is configured again before the F5 handoff")
local refreshedStartController = installFixture(startFixture, loadThor())
startFixture.bridge.availableFlag = false
startFixture.clock.value = 2
startFixture.frame(startFixture.context("live"))
eq(startState.maxVisible, 8,
  "F5 retirement restores Start rows when the new presenter is detached")
eq(startState.th, 18,
  "F5 retirement restores the original Start frame height")
startController.release()
refreshedStartController.release()

local detachedStart = {
  screenId = "StartMenu", items = { {}, {}, {}, {}, {}, {}, {}, {} },
  tx = 9, ty = 0, tw = 11, th = 18, rowStep = 2, maxVisible = 8,
  clampScroll = function() end,
}
startFixture.bridge.availableFlag = false
startFixture.events:emit("screen.pushed", { state = detachedStart })
eq(detachedStart.maxVisible, 8,
  "a detached lower display never changes Start-menu geometry")
eq(detachedStart.th, 18,
  "a detached lower display preserves the original Start artwork frame")

-- Safari Start has a second authored steps/BALL box on the left. It must keep
-- the full classic surface instead of applying the single-box center crop.
local safariFixture = makeFixture()
local safariStart = {
  screenId = "StartMenu",
  items = { {}, {}, {}, {}, {}, {}, {}, {} },
  tx = 9, ty = 0, tw = 11, th = 18, rowStep = 2, maxVisible = 8,
  clampScroll = function() end,
  game = {
    save = { safari = {} },
    overworld = {
      map = {},
      inSafariStepZone = function() return true end,
    },
  },
}
safariFixture.mod.game = {
  stack = { top = function() return safariStart end },
}
installFixture(safariFixture, loadThor())
eq(safariFixture.frame(safariFixture.context("live")).handled, true,
  "Safari Start keeps physical composition")
eq(safariStart.maxVisible, 8,
  "Safari Start keeps its engine-authored row geometry")
local safariLower = safariFixture.bridge.pushes[1].source
local safariBlit = assert(safariLower.blits[1], "Safari Start blit missing")
eq(safariBlit.args[6], 40,
  "Safari Start retains the complete centered classic canvas")
eq(safariBlit.args[10], Thor.OUTPUT_WIDTH,
  "Safari Start is not cropped around only the right-side menu")
eq(safariBlit.args[11], Thor.OUTPUT_HEIGHT,
  "Safari Start retains both authored boxes at normal scale")

-- Battle Stage v3 is armed before Thor publishes a physical frame. The first
-- compose arrived after the engine already rendered uiCanvas, so it falls
-- through once; the next frame is guaranteed to have omitted combat pictures
-- and move OAM from the lower canvas while the exported effect stays upstairs.
local splitFixture = makeFixture()
local splitBattle = {}
local splitEffect = splitFixture.graphics.external(160, 144, "split-effect")
local splitCalls = {}
-- The shipped package is one fused Loader entry: Battle Stage is exported by
-- Scott's Tweaks itself and Loader.find cannot resolve its historical
-- standalone Battle Art id. This fixture intentionally has no such handle.
splitFixture.mod.exports.battleStage = {
    apiVersion = 3,
    state = function()
      return { battle = splitBattle, staged = true, ready = true }
    end,
    animationSurface = function(expected)
      if expected ~= splitBattle then return nil end
      return { canvas = splitEffect, lx = 80, ly = 24, scale = 3,
        pw = 800, ph = 480 }
    end,
    setSplitPresentation = function(on)
      splitCalls[#splitCalls + 1] = on == true
      return true
    end,
}
eq(splitFixture.handles.BATTLE_ART_VOXEL_FORK, nil,
  "consolidated split fixture has no standalone Battle Art handle")
installFixture(splitFixture, loadThor())
local splitCtx = splitFixture.context("live")
eq(splitFixture.frame(splitCtx).handled, false,
  "v3 split request warms one engine draw before physical takeover")
eq(#splitFixture.bridge.pushes, 0,
  "pre-split uiCanvas is never pushed to the lower display")
eq(#splitCalls, 1, "split presenter makes one initial stage request")
eq(splitCalls[1], true, "initial stage request enables UI-only battle drawing")
eq(splitFixture.frame(splitCtx).handled, true,
  "v3 presenter takes over after the clean battle layer is ready")
eq(#splitFixture.bridge.pushes, 1,
  "first physical lower frame is the post-request UI canvas")
check(findDraw(splitFixture.graphics.screenDraws, splitEffect) ~= nil,
  "v3 move surface remains projected on the upper arena")
eq(splitFixture.controller.status().battleSplit, true,
  "status reports the active Battle Stage split contract")
splitFixture.mod.options.values.dual_screen = false
splitFixture.events:emit("mod.options_changed",
  { mod = splitFixture.mod.id, key = "dual_screen", value = false })
eq(splitCalls[#splitCalls], false,
  "disabling Thor restores ordinary single-screen battle layers")

local classic = makeFixture()
installFixture(classic, loadThor())
local classicCtx = classic.context("classic")
eq(classic.frame(classicCtx).handled, true,
  "stock worldCanvas also drives the physical upper display")
eq(classic.controller.status().topSource, "worldCanvas",
  "status distinguishes the stock world source")
local classicTop = classic.graphics.screenDraws[1]
  and classic.graphics.screenDraws[1].source
check(classicTop and #classicTop.blits == 1
    and classicTop.blits[1].source == classicCtx.worldCanvas,
  "stock worldCanvas uses the renderer's palette-aware blit")

-- Free Fly's first-person cockpit is a world/player composite even though its
-- compatibility hook runs during render.hud. Under the physical split, defer
-- it out of the lower HUD capture and paint rider+mount exactly once on top.
local flight = makeFixture()
installFixture(flight, loadThor())
local flightState, flightProvider, flightRider, flightMount =
  installFreeFlyProbe(flight)
local flightCtx = flight.context("classic")
local flightFrame = flight.frame(flightCtx)
eq(flightFrame.handled, true,
  "airborne Thor frame owns the physical presentation")
eq(flightState.calls, 1,
  "first-person Free Fly provider draws exactly once")
eq(flightState.lastOptions and flightState.lastOptions.target, "primary",
  "Free Fly overlay target is the physical primary")
eq(flightState.lastOptions and flightState.lastOptions.presentation,
  "ayn_thor", "Free Fly overlay receives Thor presentation identity")
eq(flightState.lastOptions and flightState.lastOptions.fullComposite, true,
  "Thor requests the complete rider and mount composite")
local flightLower = flight.bridge.pushes[1].source
check(findDraw(flightLower.draws, flightRider) == nil,
  "rider is absent from the physical lower display")
check(findDraw(flightLower.draws, flightMount) == nil,
  "mount is absent from the physical lower display")
check(findDraw(flight.graphics.screenDraws, flightRider) ~= nil,
  "first-person rider is drawn on the physical primary")
check(findDraw(flight.graphics.screenDraws, flightMount) ~= nil,
  "first-person mount is drawn on the physical primary")
eq(flightState.routedViewport._scottsTweaksThorRouteWorldOverlay, nil,
  "one-frame world-overlay route is consumed and removed")

-- Third person already carries the full composite in worldCanvas. It neither
-- queues nor duplicates the cockpit, and a subsequent landing cannot replay
-- the prior frame's provider.
flightState.firstPerson = false
flight.clock.value = 1
flight.frame(flightCtx)
eq(flightState.calls, 1,
  "third person does not duplicate the world-space rider or mount")
check(findDraw(flight.graphics.screenDraws, flightRider) == nil
    and findDraw(flight.graphics.screenDraws, flightMount) == nil,
  "third-person primary contains no extra cockpit overlay")
flightState.firstPerson = true
flightState.airborne = false
flight.clock.value = 2
flight.frame(flightCtx)
eq(flightState.calls, 1,
  "landing clears the frame-local cockpit route")

-- A physical unplug falls through to the exact ordinary HUD path: Free Fly
-- still draws its historical mount-only cockpit on the single active screen.
flightState.airborne = true
flight.bridge.availableFlag = false
flight.clock.value = 3
local flightUnplugged = flight.frame(flightCtx)
eq(flightUnplugged.handled, false,
  "airborne hot-unplug restores stock single-screen composition")
eq(flightState.calls, 2,
  "unplugged Free Fly draws once through its ordinary HUD path")
check(findDraw(flight.graphics.screenDraws, flightRider) == nil,
  "non-Thor cockpit retains its historical mount-only presentation")
check(findDraw(flight.graphics.screenDraws, flightMount) ~= nil,
  "non-Thor cockpit remains visible on the active screen")
eq(flightProvider.kind, "player_mount",
  "probe uses the production Free Fly provider kind")

local offBoot = makeFixture({ optionValues = { dual_screen = false } })
installFixture(offBoot, loadThor())
eq(offBoot.frame(offBoot.context("live")).handled, false,
  "an initially OFF option is completely stock")
eq(#offBoot.bridge.enables, 0,
  "an initially OFF option does not touch native presentation")
eq(#offBoot.bridge.pushes, 0,
  "an initially OFF option pushes no transport frame")
eq(#offBoot.graphics.canvases, 0,
  "an initially OFF option allocates no presenter canvases")

-- Push cadence is capped independently of render rate.
fixture.clock.value = 0.01
fixture.frame(liveCtx)
eq(#fixture.bridge.pushes, 1, "lower readback is throttled inside 30 Hz interval")
fixture.clock.value = 0.04
fixture.frame(liveCtx)
eq(#fixture.bridge.pushes, 2, "lower readback resumes at 30 Hz cadence")

-- A full-screen menu has no world pass. Keep the previously copied top scene
-- frozen while the lower UI continues to update.
local frozenTop = assert(findDraw(fixture.graphics.screenDraws,
  fixture.graphics.screenDraws[1].source) and fixture.graphics.screenDraws[1].source)
local frozenClearCount = frozenTop.clears
fixture.clock.value = 0.08
local menu = fixture.frame(fixture.context("menu"))
eq(menu.handled, true, "menu frame keeps physical split active")
local menuTop = fixture.graphics.screenDraws[1] and
  fixture.graphics.screenDraws[1].source
eq(menuTop, frozenTop, "menu reuses the frozen upper world snapshot")
eq(frozenTop.clears, frozenClearCount,
  "frozen upper snapshot is not destructively redrawn")

-- Hotplug never creates a desktop stack: unplug falls through to stock; the
-- same ON request resumes automatically when Android reports the panel again.
fixture.bridge.availableFlag = false
fixture.clock.value = 0.12
local unplugged = fixture.frame(liveCtx)
eq(unplugged.handled, false, "unplugged display falls through to stock layout")
eq(#fixture.bridge.enables, 1, "unplug does not spam enable requests")
eq(#fixture.bridge.pushes, 3, "unplug does not push an unreadable frame")
check(findDraw(fixture.graphics.screenDraws, fixture.modernMarker) ~= nil,
  "stock HUD remains visible while physical display is absent")
fixture.bridge.availableFlag = true
fixture.clock.value = 0.16
eq(fixture.frame(liveCtx).handled, true,
  "replug resumes split without an option toggle")
eq(#fixture.bridge.enables, 1, "replug reuses the existing enable request")
eq(#fixture.bridge.pushes, 4, "replug pushes one fresh completed lower frame")

-- OFF releases both owned canvases, disables native output, and leaves the
-- exact stock composition path. ON can be restored through the live option.
fixture.mod.options.values.dual_screen = false
fixture.events:emit("mod.options_changed",
  { mod = fixture.mod.id, key = "dual_screen", value = false })
eq(fixture.bridge.enables[#fixture.bridge.enables], false,
  "OFF disables native presentation")
eq(frozenTop.released, 1, "OFF releases the frozen upper canvas once")
eq(lower.released, 1, "OFF releases the lower canvas once")
fixture.clock.value = 0.20
eq(fixture.frame(liveCtx).handled, false, "OFF uses normal stock composition")
eq(controller.status().mode, "off", "public mode follows Tweaks option")
fixture.mod.options.values.dual_screen = true
fixture.events:emit("mod.options_changed",
  { mod = fixture.mod.id, key = "dual_screen", value = true })
eq(fixture.bridge.enables[#fixture.bridge.enables], true,
  "ON requests native presentation again")
fixture.clock.value = 0.24
eq(fixture.frame(liveCtx).handled, true, "ON rebuilds clean canvases")

-- A downstream full-output owner wins cleanly; this presenter does not draw
-- or push a partial split on top of it.
local owned = makeFixture()
installFixture(owned, loadThor())
owned.hooks:wrap("render.compose", function() return true end,
  15000, "other_output_owner")
local ownerFrame = owned.frame(owned.context("live"))
eq(ownerFrame.handled, true, "downstream full-output owner remains authoritative")
eq(#owned.bridge.enables, 0, "downstream owner prevents bridge activation")
eq(#owned.bridge.pushes, 0, "downstream owner prevents lower push")
eq(owned.controller.status().active, false,
  "status is inactive while another output owner handles the frame")

-- Readback failure disables this owner and returns subsequent frames to stock;
-- graphics state and the one-shot HUD chain are still intact.
local broken = makeFixture()
local brokenController = installFixture(broken, loadThor())
broken.graphics.failReadback = true
local brokenFrame = broken.frame(broken.context("live"))
eq(brokenFrame.hudCalls, 1, "failed readback never reruns the HUD chain")
eq(brokenController.status().faulted, true, "readback failure is reported")
eq(broken.bridge.enables[#broken.bridge.enables], false,
  "readback failure disables native presentation")
eq(broken.graphics.state.canvas, brokenFrame.before.canvas,
  "readback failure restores the graphics target")
broken.clock.value = 0.04
eq(broken.frame(broken.context("live")).handled, false,
  "faulted presenter falls through to stock")
broken.graphics.failReadback = false
broken.mod.options.values.dual_screen = false
broken.events:emit("mod.options_changed",
  { mod = broken.mod.id, key = "dual_screen", value = false })
broken.mod.options.values.dual_screen = true
broken.events:emit("mod.options_changed",
  { mod = broken.mod.id, key = "dual_screen", value = true })
broken.clock.value = 0.08
eq(broken.frame(broken.context("live")).handled, true,
  "OFF/ON clears a recoverable runtime fault")

-- Legacy compatibility is sticky for one entry/boot. No hook, canvas, bridge
-- request, or push is duplicated, even if a developer removes the handle
-- without constructing the next entry.
local delegated = makeFixture({ legacy = true })
local delegatedController = installFixture(delegated, loadThor())
eq(delegated.frame(delegated.context("live")).handled, false,
  "legacy gen1recomp_ds makes Tweaks stand aside")
eq(#delegated.bridge.enables, 0, "delegated boot never touches native enable")
eq(#delegated.bridge.pushes, 0, "delegated boot never pushes")
local delegatedStatus = delegatedController.status()
eq(delegatedStatus.delegated, true, "status exposes delegation")
eq(delegatedStatus.delegateId, "gen1recomp_ds",
  "status names the legacy provider")
eq(delegatedStatus.blockedReason, "delegated_to_gen1recomp_ds",
  "status explains why Tweaks is inactive")
delegated.handles.gen1recomp_ds = nil
eq(delegated.frame(delegated.context("live")).handled, false,
  "legacy ownership remains sticky until a fresh entry")
eq(#delegated.bridge.enables, 0,
  "same-entry legacy removal cannot race the retired presenter")
local afterLegacy = makeFixture({ bridge = delegated.bridge,
  graphics = delegated.graphics })
installFixture(afterLegacy, loadThor())
eq(afterLegacy.frame(afterLegacy.context("live")).handled, true,
  "fresh entry owns the display after legacy mod is removed")
eq(#delegated.bridge.enables, 1,
  "post-legacy fresh entry enables the bridge exactly once")

local takeoverGraphics = fakeGraphics()
local takeoverBridge = fakeBridge()
local cleanBeforeLegacy = makeFixture({ graphics = takeoverGraphics,
  bridge = takeoverBridge })
local cleanBeforeController = installFixture(cleanBeforeLegacy, loadThor())
eq(cleanBeforeLegacy.frame(cleanBeforeLegacy.context("live")).handled, true,
  "clean presenter owns the boot before a legacy F5")
local takeoverTop = takeoverGraphics.screenDraws[1].source
local takeoverLower = takeoverBridge.pushes[1].source
local legacyTakeover = makeFixture({ graphics = takeoverGraphics,
  bridge = takeoverBridge, legacy = true })
local legacyTakeoverController = installFixture(legacyTakeover, loadThor())
eq(legacyTakeover.frame(legacyTakeover.context("live")).handled, false,
  "fresh legacy entry takes ownership without double composition")
eq(#takeoverBridge.enables, 1,
  "legacy takeover never disables the shared native bridge")
eq(#takeoverBridge.pushes, 1,
  "legacy takeover never pushes a second Tweaks frame")
eq(takeoverTop.released, 1,
  "legacy takeover releases prior clean upper surface once")
eq(takeoverLower.released, 1,
  "legacy takeover releases prior clean lower surface once")
eq(cleanBeforeController.status().retired, true,
  "legacy takeover retires the prior clean generation")
eq(legacyTakeoverController.status().delegated, true,
  "legacy takeover export remains explicitly delegated")

-- Two true module entries sharing the engine's persistent SecondScreen table:
-- entry 2 adopts a mid-menu frozen top, retires entry 1's lower canvas, uses
-- the refreshed Battle Stage v2 effect, and neither stacks active wrappers nor
-- repeats setEnabled(true). Old callbacks explicitly pass through after handoff.
local sharedGraphics = fakeGraphics()
local sharedBridge = fakeBridge()
local firstEntry = makeFixture({ graphics = sharedGraphics,
  bridge = sharedBridge })
local firstBattle = {}
local firstEffect = sharedGraphics.external(160, 144, "first-effect")
firstEntry.handles.BATTLE_ART_VOXEL_FORK = { exports = { battleStage = {
  apiVersion = 2,
  state = function() return { battle = firstBattle, staged = true } end,
  animationSurface = function()
    return { canvas = firstEffect, lx = 80, ly = 24, scale = 3,
      pw = 800, ph = 480 }
  end,
} } }
local firstController = installFixture(firstEntry, loadThor())
local firstFrame = firstEntry.frame(firstEntry.context("live"))
eq(firstFrame.handled, true, "entry 1 owns a live battle frame")
eq(#sharedBridge.enables, 1, "entry 1 enables bridge once")
eq(#sharedBridge.pushes, 1, "entry 1 pushes one lower frame")
local firstLower = sharedBridge.pushes[1].source
local firstTop = sharedGraphics.screenDraws[1].source

local secondEntry = makeFixture({ graphics = sharedGraphics,
  bridge = sharedBridge })
local secondBattle = {}
local secondEffect = sharedGraphics.external(160, 144, "second-effect")
secondEntry.handles.BATTLE_ART_VOXEL_FORK = { exports = { battleStage = {
  apiVersion = 2,
  state = function() return { battle = secondBattle, staged = true } end,
  animationSurface = function()
    return { canvas = secondEffect, lx = 70, ly = 20, scale = 2,
      pw = 800, ph = 480 }
  end,
} } }
local secondController = installFixture(secondEntry, loadThor())
secondEntry.clock.value = 1
local reloaded = secondEntry.frame(secondEntry.context("menu"))
eq(reloaded.handled, true, "entry 2 stays active through mid-menu F5")
eq(#sharedBridge.enables, 1,
  "entry 2 adopts the existing native enable request")
eq(#sharedBridge.pushes, 2, "entry 2 pushes exactly once after reload")
eq(sharedGraphics.screenDraws[1].source, firstTop,
  "entry 2 adopts entry 1's frozen upper surface")
eq(firstTop.released, 0, "adopted upper surface is not prematurely released")
eq(firstLower.released, 1, "entry 1 lower surface is retired exactly once")
check(findDraw(sharedGraphics.screenDraws, secondEffect) ~= nil,
  "entry 2 uses the refreshed Battle Stage move effect")
check(findDraw(sharedGraphics.screenDraws, firstEffect) == nil,
  "entry 1 move-effect callback is not retained")
eq(secondController.status().generation, 2,
  "public status exposes the adopted presenter generation")
eq(firstController.status().retired, true,
  "old public controller reports its retired generation")
eq(firstEntry.hooks:count("render.compose", firstEntry.mod.id), 1,
  "old Loader bus contains one compose wrapper, not a growing chain")
eq(secondEntry.hooks:count("render.compose", secondEntry.mod.id), 1,
  "new Loader bus contains one compose wrapper")
eq(firstEntry.hooks:count("render.hud", firstEntry.mod.id), 1,
  "old Loader bus contains one HUD wrapper")
eq(secondEntry.hooks:count("render.hud", secondEntry.mod.id), 1,
  "new Loader bus contains one HUD wrapper")
eq(firstEntry.hooks:count("core.quit_to_launcher", firstEntry.mod.id), 1,
  "old Loader bus contains one quit wrapper")
eq(secondEntry.hooks:count("core.quit_to_launcher", secondEntry.mod.id), 1,
  "new Loader bus contains one quit wrapper")
local pushesBeforeOld = #sharedBridge.pushes
local enablesBeforeOld = #sharedBridge.enables
eq(firstEntry.frame(firstEntry.context("live")).handled, false,
  "retired entry compose and HUD wrappers pass through")
eq(#sharedBridge.pushes, pushesBeforeOld,
  "retired entry cannot push after handoff")
firstEntry.hooks:call("core.quit_to_launcher", function() return "quit" end)
eq(#sharedBridge.enables, enablesBeforeOld,
  "retired quit wrapper cannot disable the current generation")
secondEntry.hooks:call("core.quit_to_launcher", function() return "quit" end)
eq(sharedBridge.enables[#sharedBridge.enables], false,
  "current quit wrapper disables presentation once")
eq(firstTop.released, 1, "adopted upper surface is released once at current quit")
local secondLower = sharedBridge.pushes[2].source
eq(secondLower.released, 1, "current lower surface is released once at quit")

-- Re-installing on one facade refreshes stable dispatchers instead of adding
-- wrappers/listeners. Only the newest generation can compose, push, or quit.
local sameFacade = makeFixture()
local sameFirst = loadThor().install(sameFacade.mod, {
  optionKey = "dual_screen", graphics = sameFacade.graphics,
  now = function() return sameFacade.clock.value end,
})
local sameSecond = loadThor().install(sameFacade.mod, {
  optionKey = "dual_screen", graphics = sameFacade.graphics,
  now = function() return sameFacade.clock.value end,
})
sameFacade.addProviders()
eq(sameFacade.hooks:count("render.compose", sameFacade.mod.id), 1,
  "same-facade reload keeps one compose dispatcher")
eq(sameFacade.hooks:count("render.hud", sameFacade.mod.id), 1,
  "same-facade reload keeps one HUD dispatcher")
eq(sameFacade.hooks:count("core.quit_to_launcher", sameFacade.mod.id), 1,
  "same-facade reload keeps one quit dispatcher")
eq(sameFacade.events:count("mod.options_changed"), 1,
  "same-facade reload keeps one option dispatcher")
eq(sameFacade.frame(sameFacade.context("live")).handled, true,
  "refreshed same-facade generation owns the frame")
eq(#sameFacade.bridge.enables, 1,
  "same-facade generation enables exactly once")
eq(#sameFacade.bridge.pushes, 1,
  "same-facade generation pushes exactly once")
sameFirst.release()
eq(#sameFacade.bridge.enables, 1,
  "stale same-facade controller cannot disable current owner")
sameSecond.release()
eq(sameFacade.bridge.enables[#sameFacade.bridge.enables], false,
  "current same-facade controller releases native owner")

-- Optional production-Loader mode. Invoke this file once per engine root so
-- package.loaded belongs to exactly one release, matching a real process. The
-- entry is evaluated twice without releasing entry 1, reproducing F5's fresh
-- Loader bus over persistent engine/SecondScreen state.
local function realLoaderRegression(engineRoot)
  package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
    .. package.path
  local loaderGraphics = fakeGraphics()
  local loaderBridge = fakeBridge()
  local loaderClock = { value = 0 }
  local previousLove = rawget(_G, "love")
  _G.love = {
    graphics = loaderGraphics,
    timer = { getTime = function() return loaderClock.value end },
  }

  local T = require("tests.modkit")
  local fixtures = require("tests.modkit.fixtures")
  local moduleSource = assert(read(modulePath), "Thor module source missing")
  local loaderSource = assert(read(engineRoot .. "/src/mods/Loader.lua"),
    "live Loader source missing")
  local expectsGameFacade = loaderSource:find(
    'if key == "game" then', 1, true) ~= nil
  local prefix = "mods/voxel_run_bridge/"
  local files = {
    [prefix .. "manifest.json"] = [[{
      "id":"voxel_run_bridge","name":"Scott's Tweaks Thor Loader Test",
      "version":"0.12.12","api":2,"entry":"main.lua",
      "profile":"content","priority":200,"dependencies":[],
      "optional_dependencies":[],"conflicts":[],"games":["gen1"],
      "permissions":["engine_internals"]
    }]],
    [prefix .. "main.lua"] = [[return function(mod)
      mod.options:define({
        { key = "dual_screen", type = "toggle", default = true },
      })
      local battle = {}
      local battleActive = true
      local effect = love.graphics.newCanvas(160, 144, { dpiscale = 1 })
      local splitCalls = {}
      mod.exports.testBattleSplitCalls = splitCalls
      mod.exports.testHasGameFacade = type(mod.game) == "table"
      mod.exports.testSetBattleActive = function(active)
        battleActive = active == true
      end
      mod.exports.battleStage = {
        apiVersion = 3,
        state = function()
          if not battleActive then return nil end
          return { battle = battle, staged = true, ready = true }
        end,
        animationSurface = function(expected)
          if expected ~= battle then return nil end
          return { canvas = effect, lx = 80, ly = 24, scale = 3,
            pw = 800, ph = 480 }
        end,
        setSplitPresentation = function(on)
          splitCalls[#splitCalls + 1] = on == true
          return true
        end,
      }
      local source = assert(mod:read("modules/thor_dual_screen.lua"))
      local compile = loadstring or load
      local chunk = assert(compile(source,
        "@voxel_run_bridge/thor_dual_screen.lua"))
      local Thor = chunk()
      Thor.install(mod, { optionKey = "dual_screen" })
    end]],
    [prefix .. "modules/thor_dual_screen.lua"] = moduleSource,
  }

  local function loadEntry()
    local run = T.sdk.loadMod("mods/voxel_run_bridge", {
      data = fixtures.fresh(), fs = T.sdk.memfs(files), generation = 1,
    })
    eq(#run.errors, 0, "real API-2 entry loads without errors")
    return run
  end

  local renderer = {}
  function renderer:blitCanvas(source, ...)
    local target = loaderGraphics.state.canvas
    local call = { source = source, target = target, args = pack(...) }
    if target then target.blits[#target.blits + 1] = call end
  end
  local function ctx(kind)
    local out = {
      renderer = renderer,
      worldCanvas = loaderGraphics.external(160, 144, "loader-world"),
      uiCanvas = loaderGraphics.external(160, 144, "loader-ui"),
      worldOverride = loaderGraphics.external(800, 480, "loader-override"),
      worldActive = true, zones = {}, worldZones = {},
      ww = 800, wh = 480, pw = 800, ph = 480,
      uiw = 160, uih = 144, dpiX = 1, dpiY = 1,
      secondScreen = loaderBridge,
    }
    if kind == "menu" then
      out.worldCanvas, out.worldOverride, out.worldActive = nil, nil, false
    end
    return out
  end
  local function draw(loader, frameCtx)
    local handled = loader.hooks:call("render.compose",
      function() return false end, renderer, frameCtx)
    loader.hooks:call("render.hud", function() return "hud" end, {}, {
      width = 800, height = 480,
      gameX = 0, gameY = 0, gameWidth = 800, gameHeight = 480,
    })
    return handled
  end
  local function ownedCount(loader, name)
    local count = 0
    for _, entry in ipairs(loader.hooks.chains[name] or {}) do
      if entry.owner == "voxel_run_bridge" then count = count + 1 end
    end
    return count
  end

  local run1 = loadEntry()
  local run1Exports = run1.loader.exports.voxel_run_bridge
  eq(run1Exports.testHasGameFacade, expectsGameFacade,
    "real Loader exposes exactly its release's mod.game facade")
  eq(draw(run1.loader, ctx("live")), false,
    "real Loader own export warms the pre-split battle frame")
  eq(run1Exports.testBattleSplitCalls[1], true,
    "real Loader resolves its own Battle Stage export without mod.find")
  eq(#loaderBridge.pushes, 0,
    "real Loader never pushes the pre-split lower battle canvas")
  eq(draw(run1.loader, ctx("live")), true,
    "real Loader entry 1 owns the clean physical frame after warm-up")
  eq(#loaderBridge.enables, 1, "real Loader entry 1 enables once")
  eq(#loaderBridge.pushes, 1, "real Loader entry 1 pushes once")
  local run1Top = loaderGraphics.screenDraws[1].source
  local run1Lower = loaderBridge.pushes[1].source

  local run2 = loadEntry()
  loaderClock.value = 1
  eq(draw(run2.loader, ctx("menu")), false,
    "real Loader entry 2 warms its refreshed split contract after F5")
  eq(run1Exports.testBattleSplitCalls[2], false,
    "real Loader F5 retires the prior split request")
  local run2Exports = run2.loader.exports.voxel_run_bridge
  eq(run2Exports.testBattleSplitCalls[1], true,
    "real Loader F5 arms the new own-export split contract")
  eq(draw(run2.loader, ctx("menu")), true,
    "real Loader entry 2 survives mid-menu F5 after warm-up")
  eq(#loaderBridge.enables, 1,
    "real Loader F5 preserves one native enable request")
  eq(#loaderBridge.pushes, 2, "real Loader F5 pushes exactly once")
  eq(loaderGraphics.screenDraws[1].source, run1Top,
    "real Loader F5 adopts frozen top")
  eq(run1Lower.released, 1, "real Loader F5 retires old lower once")
  eq(run2.loader.exports.voxel_run_bridge.thorDualScreen
      .getStatus().generation, 2,
    "real Loader export reports second presenter generation")

  -- Exercise state lookup through the actual Loader facade. In 0.1.75 this
  -- facade intentionally has no mod.game property, so these checks can pass
  -- only through ThorDualScreen's narrow src.core.Game compatibility fallback;
  -- newer fixtures exercise the sanctioned property with the same behavior.
  local EngineGame = require("src.core.Game")
  local originalStack = EngineGame.stack
  local activeState
  EngineGame.stack = {
    top = function() return activeState end,
  }
  run2Exports.testSetBattleActive(false)

  local legacyDialogue = {
    -- The unmarked 0.1.75 TextBox typewriter shape.
    boxTx = 0, boxTy = 12, boxTw = 20, boxTh = 6,
    maxCols = 18, textX = 8, line1Y = 112, line2Y = 128,
    pages = { { "LEGACY" } }, shown = {},
    pageIndex = 1, lineIndex = 1, charIndex = 0,
    waiting = false, done = false,
  }
  activeState = legacyDialogue
  loaderClock.value = 2
  eq(draw(run2.loader, ctx("menu")), true,
    "real Loader top-docks legacy unmarked dialogue")
  local dialogueLower = loaderBridge.pushes[#loaderBridge.pushes].source
  local dialogueBlit = assert(dialogueLower.blits[1],
    "real Loader legacy dialogue lower blit missing")
  eq(dialogueBlit.args[7], -180,
    "real Loader legacy dialogue source reaches the hinge")
  eq(dialogueBlit.args[11], 96,
    "real Loader legacy dialogue keeps its complete six-tile frame")

  -- Use this release's real ChoiceBox constructor. The presenter recognizes
  -- the stable behavioral/geometry shape on every supported Loader, then
  -- independently crops the legacy TextBox underneath it.
  local ChoiceBox = require("src.ui.ChoiceBox")
  local liveChoice = ChoiceBox.new(EngineGame, function() end,
    { anchor = "bottom" })
  EngineGame.stack.states = { legacyDialogue, liveChoice }
  activeState = liveChoice
  loaderClock.value = 2.5
  eq(draw(run2.loader, ctx("menu")), true,
    "real Loader composes its native ChoiceBox beneath the question")
  local choiceLower = loaderBridge.pushes[#loaderBridge.pushes].source
  eq(#choiceLower.blits, 2,
    "real Loader choice prompt has independent question and answer crops")
  local liveQuestion, liveAnswer = choiceLower.blits[1], choiceLower.blits[2]
  eq(liveQuestion.args[9], 12,
    "real Loader choice question stays at the hinge margin")
  eq(liveAnswer.args[8], 264,
    "real Loader native ChoiceBox remains right-aligned")
  eq(liveAnswer.args[9], 108,
    "real Loader native ChoiceBox follows below the question")
  local liveChoicePaper = assert(choiceLower.rectangles[1],
    "real Loader choice paper band missing")
  eq(liveChoicePaper.x, 40,
    "real Loader choice paper retains black outside classic UI width")
  eq(liveChoicePaper.y, 108,
    "real Loader choice paper begins below the question")
  eq(liveChoicePaper.width, 320,
    "real Loader choice paper fills the horizontal answer band")
  eq(liveChoicePaper.height, 80,
    "real Loader choice paper does not fill the lower-screen remainder")
  EngineGame.stack.states = nil

  local startState = {
    screenId = "StartMenu",
    items = { {}, {}, {}, {}, {}, {}, {}, {} },
    index = 1, scroll = 0,
    tx = 9, ty = 0, tw = 11, th = 18,
    rowStep = 2, maxVisible = 8,
  }
  function startState:clampScroll()
    if self.index - self.scroll > self.maxVisible then
      self.scroll = self.index - self.maxVisible
    elseif self.index - self.scroll < 1 then
      self.scroll = self.index - 1
    end
  end
  activeState = startState
  run2.loader.events:emit("screen.pushed", { state = startState })
  eq(startState.maxVisible, 8,
    "real Loader configures Start through its public push event")
  eq(startState.th, 18,
    "real Loader applies the eight-row Start frame before draw")
  loaderClock.value = 3
  eq(draw(run2.loader, ctx("menu")), true,
    "real Loader detects the live Start state")
  local startLower = loaderBridge.pushes[#loaderBridge.pushes].source
  local startBlit = assert(startLower.blits[1],
    "real Loader vertically expanded Start lower blit missing")
  eq(startBlit.args[1], 2,
    "real Loader Start artwork uses normal crisp 2x scaling")
  eq(startBlit.args[6], -32,
    "real Loader Start crop centers its narrow authored box")
  eq(startBlit.args[10], 176,
    "real Loader Start crop retains the authored width")
  eq(startBlit.args[11], 288,
    "real Loader Start crop uses the full normal UI height")
  run2.loader.events:emit("screen.popped", { state = startState })
  eq(startState.maxVisible, 8,
    "real Loader Start pop restores the engine row count")
  eq(startState.th, 18,
    "real Loader Start pop restores the engine frame height")
  EngineGame.stack = originalStack
  run2Exports.testSetBattleActive(true)

  for _, name in ipairs({
    "render.compose", "render.hud", "core.quit_to_launcher",
  }) do
    eq(ownedCount(run1.loader, name), 1,
      "real Loader old bus keeps one " .. name .. " wrapper")
    eq(ownedCount(run2.loader, name), 1,
      "real Loader new bus keeps one " .. name .. " wrapper")
  end
  local beforeOldPush = #loaderBridge.pushes
  eq(draw(run1.loader, ctx("live")), false,
    "real Loader retired callbacks pass through")
  eq(#loaderBridge.pushes, beforeOldPush,
    "real Loader retired callbacks cannot push")
  local beforeOldQuit = #loaderBridge.enables
  run1.loader.hooks:call("core.quit_to_launcher", function() end)
  eq(#loaderBridge.enables, beforeOldQuit,
    "real Loader retired quit cannot disable current owner")
  run2.loader.hooks:call("core.quit_to_launcher", function() end)
  eq(loaderBridge.enables[#loaderBridge.enables], false,
    "real Loader current quit disables exactly once")
  eq(run2Exports.testBattleSplitCalls[#run2Exports.testBattleSplitCalls], false,
    "real Loader current quit restores ordinary battle layers")
  eq(run1Top.released, 1, "real Loader adopted top releases at current quit")
  local run2Lower = loaderBridge.pushes[2].source
  eq(run2Lower.released, 1, "real Loader current lower releases at quit")

  run2.release()
  run1.release()
  _G.love = previousLove
end

-- Load the production VendorHost, production Free Fly 1.8.0 entry and
-- production Thor presenter as one API-2 mod. This is the shipping ownership
-- shape (Free Fly's public export is nested in the fused host), not a second
-- standalone bridge or an invented render callback.
local function realFusedFreeFlyRegression(engineRoot)
  package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
    .. package.path
  local previousLove = rawget(_G, "love")
  local previousPlayer = package.loaded["src.world.Player"]
  local previousSpriteRenderer = package.loaded["src.render.SpriteRenderer"]
  local graphics = fakeGraphics()
  local bridge = fakeBridge()
  local clock = { value = 0 }
  _G.love = {
    graphics = graphics,
    timer = { getTime = function() return clock.value end },
  }

  local Player = {}
  package.loaded["src.world.Player"] = Player
  package.loaded["src.render.SpriteRenderer"] = {
    STAND = { down = 0, up = 1, left = 2, right = 2 },
    WALK = { down = 3, up = 4, left = 5, right = 5 },
  }

  local T = require("tests.modkit")
  local fixtures = require("tests.modkit.fixtures")
  local prefix = "mods/voxel_run_bridge/"
  local files = {
    [prefix .. "manifest.json"] = [[{
      "id":"voxel_run_bridge","name":"Scott's Tweaks Fused Flight Test",
      "version":"0.12.12","api":2,"entry":"main.lua",
      "profile":"content","priority":200,"dependencies":[],
      "optional_dependencies":[],"conflicts":[],"games":["gen1"],
      "permissions":["engine_internals"]
    }]],
    [prefix .. "main.lua"] = [[return function(mod)
      local compile = loadstring or load
      local function own(path)
        return assert(compile(assert(mod:read(path)),
          "@voxel_run_bridge/" .. path))()
      end
      local FirstPerson = { hidden = true }
      function FirstPerson.hidePlayer() return FirstPerson.hidden end
      local VoxelState = {}
      mod.exports.lib = { require = function(name)
        if name == "FirstPerson" then return FirstPerson end
        if name == "VoxelState" then return VoxelState end
      end }
      mod.exports.testFirstPerson = FirstPerson

      local VendorHost = own("modules/vendor_host.lua")
      local host = VendorHost.new(mod)
      local freeFly
      for _, entry in ipairs(VendorHost.MODS) do
        if entry.id == "free_fly" then freeFly = entry break end
      end
      assert(freeFly and host:install(freeFly),
        host.failures.free_fly or "bundled Free Fly failed")
      mod.exports.vendorHost = host
      mod.exports.testFreeFly = assert(host.loaded.free_fly).exports

      local schema = {
        { key = "dual_screen", type = "toggle", default = true },
      }
      for _, row in ipairs(host:mergedSchema()) do
        schema[#schema + 1] = row
      end
      mod.options:define(schema)
      local Thor = own("modules/thor_dual_screen.lua")
      Thor.install(mod, { optionKey = "dual_screen" })
    end]],
    [prefix .. "modules/thor_dual_screen.lua"] = assert(read(modulePath)),
    [prefix .. "modules/vendor_host.lua"] = assert(read(
      sourceRoot .. "/modules/vendor_host.lua")),
    [prefix .. "vendor/free_fly/main.lua"] = assert(read(
      sourceRoot .. "/vendor/free_fly/main.lua")),
    [prefix .. "vendor/free_fly/lib/FlightInput.lua"] = assert(read(
      sourceRoot .. "/vendor/free_fly/lib/FlightInput.lua")),
    [prefix .. "vendor/free_fly/lib/VoxelProvider.lua"] = assert(read(
      sourceRoot .. "/vendor/free_fly/lib/VoxelProvider.lua")),
    [prefix .. "vendor/free_fly/lib/FollowerLanding.lua"] = assert(read(
      sourceRoot .. "/vendor/free_fly/lib/FollowerLanding.lua")),
    [prefix .. "vendor/free_fly/lib/shared/skylib.lua"] = assert(read(
      sourceRoot .. "/vendor/free_fly/lib/shared/skylib.lua")),
  }
  local run = T.sdk.loadMod("mods/voxel_run_bridge", {
    data = fixtures.fresh(), fs = T.sdk.memfs(files), generation = 1,
  })
  eq(#run.errors, 0,
    "real fused Free Fly and Thor load through one API-2 entry")
  local rootExports = assert(run.loader.exports.voxel_run_bridge,
    "fused root exports missing")
  local freeFly = assert(rootExports.testFreeFly,
    "fused Free Fly exports missing")
  local cockpit = freeFly.cockpitOverlay
  eq(type(cockpit), "table",
    "production bundled Free Fly publishes its cockpit provider")
  eq(cockpit and cockpit.apiVersion, 1,
    "production cockpit provider API version is recognized")
  eq(cockpit and cockpit.kind, "player_mount",
    "production cockpit provider identifies a player/mount overlay")
  eq(type(cockpit and cockpit.draw), "function",
    "production cockpit provider publishes its renderer")

  local function upvalue(fn, wanted)
    if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
      return nil
    end
    for index = 1, 64 do
      local name, value = debug.getupvalue(fn, index)
      if not name then break end
      if name == wanted then return value end
    end
    return nil
  end
  local flying = upvalue(freeFly.isFlying, "flying")
  local flightState = upvalue(flying, "state")
  check(type(flightState) == "table" and flightState.phase == "idle",
    "production flight export closes over the real state machine")

  local mountRaw = graphics.external(16, 96, "raw-pidgeot-cockpit")
  local riderRaw = graphics.external(16, 96, "raw-player-rider")
  local mountImage = graphics.external(16, 96, "resolved-pidgeot-cockpit")
  local riderImage = graphics.external(16, 96, "resolved-player-rider")
  local mountResolves, riderResolves = 0, 0
  Player.__freeFlyMount = {
    image = mountRaw,
    resolveImage = function()
      mountResolves = mountResolves + 1
      return mountImage
    end,
  }
  -- Pidgeot is 4'11": this is production Sky.dexScale's exact ladder value.
  local pidgeotScale = 0.75 + (4 + 11 / 12) * 0.14
  Player.__freeFlyMountScale = pidgeotScale
  flightState.phase = "cruise"
  flightState.walkSprite = {
    image = riderRaw,
    resolveImage = function()
      riderResolves = riderResolves + 1
      return riderImage
    end,
  }

  local renderer = {}
  function renderer:blitCanvas(source, ...)
    local target = graphics.state.canvas
    local call = { source = source, target = target, args = pack(...) }
    if target then target.blits[#target.blits + 1] = call end
  end
  local function context()
    return {
      renderer = renderer,
      worldCanvas = graphics.external(160, 144, "real-flight-world"),
      uiCanvas = graphics.external(160, 144, "real-flight-ui"),
      worldActive = true, zones = {}, worldZones = {},
      ww = 800, wh = 480, pw = 800, ph = 480,
      uiw = 160, uih = 144, dpiX = 1, dpiY = 1,
      secondScreen = bridge,
    }
  end
  local game = {
    mods = { exports = run.loader.exports },
    overworld = { player = { freeFlyWalkSprite = flightState.walkSprite } },
  }
  local viewport = {
    width = 800, height = 480, scale = 3,
    gameX = 0, gameY = 0, gameWidth = 800, gameHeight = 480,
  }
  local function countDraw(draws, source)
    local count = 0
    for _, draw in ipairs(draws or {}) do
      if draw.source == source then count = count + 1 end
    end
    return count
  end
  local function frame()
    graphics.resetFrame()
    local handled = run.loader.hooks:call("render.compose",
      function() return false end, renderer, context())
    run.loader.hooks:call("render.hud", function() return "hud" end,
      game, viewport)
    return handled
  end

  eq(frame(), true,
    "real fused airborne frame uses the Thor split presenter")
  eq(#bridge.pushes, 1,
    "real fused airborne frame pushes one completed lower surface")
  local lower = bridge.pushes[1].source
  eq(countDraw(lower.draws, mountImage), 0,
    "real Pidgeot sprite is absent from the lower display")
  eq(countDraw(lower.draws, riderImage), 0,
    "real rider sprite is absent from the lower display")
  eq(countDraw(graphics.screenDraws, mountRaw), 0,
    "raw opaque Pidgeot sheet is never blitted to the primary")
  eq(countDraw(graphics.screenDraws, riderRaw), 0,
    "raw opaque rider sheet is never blitted to the primary")
  eq(countDraw(graphics.screenDraws, mountImage), 1,
    "real Pidgeot sprite draws exactly once on the primary")
  eq(countDraw(graphics.screenDraws, riderImage), 1,
    "real rider sprite draws exactly once on the primary")
  eq(mountResolves, 1,
    "top-screen Pidgeot uses SpriteRenderer transparency resolution")
  eq(riderResolves, 1,
    "top-screen rider uses SpriteRenderer transparency resolution")
  local mountDraw = assert(findDraw(graphics.screenDraws, mountImage),
    "real Pidgeot draw missing")
  local riderDraw = assert(findDraw(graphics.screenDraws, riderImage),
    "real rider draw missing")
  local cockpitScale = viewport.scale * 2.2
  local scaledPidgeot = pidgeotScale * 1.15 -- NORMAL Free Fly size
  local expectedMountScale = cockpitScale * scaledPidgeot
  local expectedMountX = viewport.gameWidth / 2 - 8 * expectedMountScale
  local expectedMountY = viewport.gameHeight - 10 * expectedMountScale
  local expectedSeat = 1 + 2 * scaledPidgeot
  local expectedRiderX = viewport.gameWidth / 2 - 8 * cockpitScale
  local expectedRiderY = expectedMountY + 16 * expectedMountScale
    - (16 + expectedSeat) * cockpitScale
  near(mountDraw.sx, expectedMountScale,
    "Pidgeot keeps its dex and Free Fly size multipliers")
  near(mountDraw.sy, expectedMountScale,
    "Pidgeot keeps uniform authored cockpit scaling")
  near(riderDraw.sx, cockpitScale,
    "rider scale is independent of Pidgeot's species size")
  near(riderDraw.sy, cockpitScale,
    "rider keeps uniform base cockpit scaling")
  near(mountDraw.x, expectedMountX,
    "Pidgeot remains horizontally centered at its enlarged size")
  near(riderDraw.x, expectedRiderX,
    "rider is independently centered on the same flight anchor")
  near(mountDraw.y, expectedMountY,
    "Pidgeot retains its established cockpit vertical placement")
  near(riderDraw.y, expectedRiderY,
    "rider uses the production seat offset behind Pidgeot")
  near(mountDraw.x + 8 * mountDraw.sx,
    riderDraw.x + 8 * riderDraw.sx,
    "rider and Pidgeot share one horizontal anchor")
  eq(riderDraw.quad and riderDraw.quad.args[4], 8,
    "cockpit rider uses the same top-half crop as the world composite")

  rootExports.testFirstPerson.hidden = false
  clock.value = 1
  eq(frame(), true,
    "real fused third-person flight keeps the Thor split active")
  eq(countDraw(graphics.screenDraws, mountImage), 0,
    "third person does not duplicate the world-space mount")
  eq(countDraw(graphics.screenDraws, riderImage), 0,
    "third person does not duplicate the world-space rider")

  rootExports.testFirstPerson.hidden = true
  run.loader.modOptions.voxel_run_bridge =
    run.loader.modOptions.voxel_run_bridge or {}
  run.loader.modOptions.voxel_run_bridge.dual_screen = false
  clock.value = 2
  eq(frame(), false,
    "real fused Thor OFF frame falls through to stock composition")
  eq(countDraw(graphics.screenDraws, mountImage), 1,
    "non-Thor Free Fly retains its mount-only cockpit")
  eq(countDraw(graphics.screenDraws, riderImage), 0,
    "non-Thor Free Fly does not adopt Thor's full-composite policy")

  run.release()
  Player.__freeFlyMount, Player.__freeFlyMountScale = nil, nil
  package.loaded["src.world.Player"] = previousPlayer
  package.loaded["src.render.SpriteRenderer"] = previousSpriteRenderer
  _G.love = previousLove
end

if argv[4] and argv[4] ~= "" then
  local liveEngine = tostring(argv[4]):gsub("\\", "/")
  realLoaderRegression(liveEngine)
  realFusedFreeFlyRegression(liveEngine)
end

print(("thor_dual_screen: %d checks passed (.88/.96 public seams)")
  :format(checks))
