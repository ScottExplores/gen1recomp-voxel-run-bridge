-- Voxel world graphics/performance policy (v0.2.87).
--
-- The old renderer had two hidden ModSetting ladders (RES / SHADOWS), but they
-- were no longer surfaced by this Gold package and renderScale never reached
-- the actual world canvas.  v0.2.86 turns the policy into a PC-style graphics
-- panel under MOD SETTINGS and makes every expensive subsystem consult the
-- same preset.  No preset removes a gameplay feature: lower rungs reduce
-- resolution, reflection complexity, far-map residency and background build
-- time; maps/entities still stream in normally as the player/camera reaches
-- them.

local V = ...
local mod = V and V.mod
local ModSetting = V.require("ModSetting")

local Quality = {}

-- Back-compat ladders. Old saves that wrote these keys still provide a useful
-- fallback when the new options schema is unavailable on an older host.
Quality.setting = ModSetting.new("renderScale", "RES",
                                 { 2, 1, 3, 4 },
                                 { "1/2", "FULL", "1/3", "1/4" })
Quality.shadowSetting = ModSetting.new("shadowQuality", "SHADOWS",
                                       { "low", "off", "high", "soft" },
                                       { "LOW", "OFF", "HIGH", "SOFT" })

local PRESETS = {
  low = {
    resolution = 0.40, shadows = "blob", reflections = "sky",
    draw = "near", kanto = 1, build = "smooth",
  },
  medium = {
    resolution = 0.55, shadows = "blob", reflections = "sky",
    draw = "balanced", kanto = 1, build = "smooth",
  },
  high = {
    resolution = 0.75, shadows = "high", reflections = "sky",
    draw = "far", kanto = 2, build = "balanced",
  },
  ultra = {
    resolution = 1.00, shadows = "soft", reflections = "full",
    draw = "max", kanto = 3, build = "fast",
  },
}

local PRESET_CHILDREN = {
  low = {
    graphicsResolution="40", graphicsShadows="blob", graphicsReflections="sky",
    graphicsDrawDistance="near", graphicsKantoRadius="1", graphicsBuildRate="smooth",
  },
  medium = {
    graphicsResolution="55", graphicsShadows="blob", graphicsReflections="sky",
    graphicsDrawDistance="balanced", graphicsKantoRadius="1", graphicsBuildRate="smooth",
  },
  high = {
    graphicsResolution="75", graphicsShadows="high", graphicsReflections="sky",
    graphicsDrawDistance="far", graphicsKantoRadius="2", graphicsBuildRate="balanced",
  },
  ultra = {
    graphicsResolution="100", graphicsShadows="soft", graphicsReflections="full",
    graphicsDrawDistance="max", graphicsKantoRadius="3", graphicsBuildRate="fast",
  },
}

-- v0.4.16 and older stored these child rows under MEDIUM/HIGH.  Keep a narrow
-- migration fingerprint so upgrading an existing install does not accidentally
-- reinterpret a named preset as CUSTOM just because v0.4.17 made its cheap
-- background policy stricter.
local LEGACY_PRESET_CHILDREN = {
  medium = {
    graphicsResolution="55", graphicsShadows="blob", graphicsReflections="sky",
    graphicsDrawDistance="balanced", graphicsKantoRadius="2", graphicsBuildRate="balanced",
  },
  high = {
    graphicsResolution="75", graphicsShadows="high", graphicsReflections="full",
    graphicsDrawDistance="far", graphicsKantoRadius="2", graphicsBuildRate="balanced",
  },
}

-- A PC-style panel should behave like one: touching an individual graphics
-- row means "I am customizing this preset." v0.2.86 labelled those rows
-- CUSTOM-only but left the master preset unchanged, so a player could move
-- SHADOW QUALITY from LOW to SOFT and see absolutely no change. Keep a runtime
-- override immediately, and persist CUSTOM through the same option bucket the
-- Mod Manager owns when that writer is available.
local INDIVIDUAL_GRAPHICS = {
  graphicsResolution = true, graphicsShadows = true,
  graphicsReflections = true, graphicsDrawDistance = true,
  graphicsKantoRadius = true, graphicsBuildRate = true,
}
local runtimePreset = nil
local autoCustomWrites = 0

-- v0.4.17 automatic whole-renderer governor.  Unlike Weather FX's own
-- particle governor, this watches only the cost of the voxel draw itself so
-- the presentation FPS limiter's sleep time cannot trick AUTO into thinking
-- the GPU is slow.  It changes tiers slowly and never touches the saved child
-- rows: AUTO is a runtime policy, not a stream of option-file writes.
local auto = {
  tier = "medium",
  ema = 0.0,
  hold = 0.0,
  samples = 0,
  changes = 0,
  lastCost = 0.0,
  targetFps = 60,
}
local AUTO_ORDER = { "low", "medium", "high" }
local AUTO_RANK = { low = 1, medium = 2, high = 3 }

function Quality.resetAuto()
  auto.tier = "medium"
  auto.ema = 0.0
  auto.hold = 0.0
  auto.samples = 0
  auto.lastCost = 0.0
  auto.targetFps = 60
end

function Quality.autoTier()
  return auto.tier or "medium"
end

-- Called once per finished voxel draw by PerformanceRuntime.  Downgrades react
-- much faster than upgrades; this keeps a route that is barely holding 60 from
-- bouncing LOW/MEDIUM/HIGH every few seconds.  The thresholds reserve frame
-- time for Gold's simulation, audio, UI and OS composition rather than letting
-- the renderer consume the entire target frame budget.
function Quality.noteFrameCost(seconds, targetFps)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 or seconds > 0.25 then return Quality.autoTier() end
  targetFps = math.max(30, math.min(144, tonumber(targetFps) or 60))
  auto.targetFps = targetFps
  auto.lastCost = seconds
  auto.samples = auto.samples + 1
  if auto.ema <= 0 then auto.ema = seconds
  else auto.ema = auto.ema + (seconds - auto.ema) * 0.08 end

  local budget = 1 / targetFps
  local slow = budget * 0.82
  local fast = budget * 0.52
  local want = 0
  if auto.ema > slow then want = -1
  elseif auto.ema < fast then want = 1 end
  if want == 0 then auto.hold = 0 return Quality.autoTier() end

  -- 1.25s to escape a slow tier; 8s before spending newly discovered headroom.
  auto.hold = auto.hold + math.min(seconds, budget * 2)
  local dwell = want < 0 and 1.25 or 8.0
  if auto.hold < dwell then return Quality.autoTier() end
  auto.hold = 0
  local rank = AUTO_RANK[Quality.autoTier()] or 2
  local nextRank = math.max(1, math.min(#AUTO_ORDER, rank + want))
  local nextTier = AUTO_ORDER[nextRank]
  if nextTier ~= auto.tier then
    auto.tier = nextTier
    auto.changes = auto.changes + 1
  end
  return Quality.autoTier()
end

local function liveGame()
  if V and V.game then return V.game end
  local world = mod and mod.world
  return world and world.game or nil
end

local function persistTopLevelOption(key, value)
  local okSD, SaveData = pcall(require, "src.core.SaveData")
  if not (okSD and type(SaveData) == "table"
      and type(SaveData.loadOptions) == "function"
      and type(SaveData.saveOptions) == "function"
      and mod and mod.id) then return false end
  local okLoad, file = pcall(SaveData.loadOptions)
  if not okLoad or type(file) ~= "table" then file = {} end
  file.modOptions = type(file.modOptions) == "table" and file.modOptions or {}
  file.modOptions[mod.id] = type(file.modOptions[mod.id]) == "table"
    and file.modOptions[mod.id] or {}
  file.modOptions[mod.id][key] = value
  local okSave, result = pcall(SaveData.saveOptions, file)
  return okSave and result ~= false
end

local function writeLiveOption(key, value, source)
  local wrote = false
  local okConfig, Config = pcall(V.require, "config")
  if okConfig and type(Config) == "table" and type(Config.setOption) == "function" then
    local ok, result = pcall(Config.setOption, mod, key, value, source or "graphics_policy",
      { game = liveGame() })
    wrote = ok and result ~= false or wrote
  end
  -- Gen2's ManagerState persistence changed over time. Mirror this mod's one
  -- option into the canonical top-level SaveData bucket so a child graphics
  -- edit cannot come back next boot under an older preset.
  if persistTopLevelOption(key, value) then wrote = true end
  return wrote
end

local function persistCustomPreset()
  local wrote = writeLiveOption("performancePreset", "custom", "graphics_row_override")
  if wrote then autoCustomWrites = autoCustomWrites + 1 end
  return wrote
end

local function applyPresetChildren(preset)
  local row = PRESET_CHILDREN[preset]
  if type(row) ~= "table" then return false end
  local wrote = false
  for key, value in pairs(row) do
    if writeLiveOption(key, value, "graphics_preset_sync") then wrote = true end
  end
  return wrote
end

function Quality.noteOptionChanged(payload)
  if type(payload) ~= "table" then return false end
  if payload.mod ~= nil and mod and payload.mod ~= mod.id then return false end
  local key = payload.key
  if key == "performancePreset" then
    runtimePreset = nil
    local preset = tostring(payload.value or "auto"):lower()
    if preset == "auto" then Quality.resetAuto() end
    if PRESET_CHILDREN[preset] then applyPresetChildren(preset) end
    return true
  end
  if INDIVIDUAL_GRAPHICS[key] then
    runtimePreset = "custom"
    persistCustomPreset()
    return true
  end
  return false
end

local function option(key, fallback)
  local opts = V.mod and V.mod.options
  if not (opts and type(opts.get) == "function") then return fallback end
  local ok, value = pcall(opts.get, opts, key)
  if not ok or value == nil then return fallback end
  return value
end

local function childSnapshot()
  local out = {}
  for key in pairs(INDIVIDUAL_GRAPHICS) do out[key] = tostring(option(key, "")) end
  return out
end

local function childrenMatch(values, expected)
  if type(expected) ~= "table" then return false end
  for key, value in pairs(expected) do
    if tostring(values[key] or "") ~= tostring(value) then return false end
  end
  return true
end

-- v0.3.03 boot reconciliation. Older builds could persist 3D RENDER
-- RESOLUTION=100% while leaving PERFORMANCE PRESET=MEDIUM. The UI then said
-- 100% but renderFactor() correctly followed MEDIUM (55%) until the player
-- touched the child row and runtimePreset flipped to CUSTOM. Resolve that
-- inconsistent legacy save at boot so the visible child settings are the ones
-- actually rendered. Pure old preset saves had all child rows at the schema's
-- MEDIUM defaults; those are synchronized to the chosen preset instead.
function Quality.reconcileStartup()
  if runtimePreset then return runtimePreset end
  local preset = tostring(option("performancePreset", "auto")):lower()
  if preset == "auto" then return preset end
  if preset == "custom" or not PRESET_CHILDREN[preset] then return preset end
  local values = childSnapshot()
  if childrenMatch(values, PRESET_CHILDREN[preset]) then return preset end

  local legacy = LEGACY_PRESET_CHILDREN[preset]
  if legacy and childrenMatch(values, legacy) then
    applyPresetChildren(preset)
    return preset
  end

  local mediumDefaults = PRESET_CHILDREN.medium
  local legacyMedium = LEGACY_PRESET_CHILDREN.medium
  if preset ~= "medium" and (childrenMatch(values, mediumDefaults)
      or childrenMatch(values, legacyMedium)) then
    applyPresetChildren(preset)
    return preset
  end

  runtimePreset = "custom"
  persistCustomPreset()
  return runtimePreset
end

function Quality.requestedPreset()
  if runtimePreset then return runtimePreset end
  local v = tostring(option("performancePreset", "auto")):lower()
  if v == "auto" or v == "low" or v == "medium" or v == "high"
      or v == "ultra" or v == "custom" then return v end
  return "auto"
end

function Quality.preset()
  if not runtimePreset then Quality.reconcileStartup() end
  if runtimePreset then return runtimePreset end
  local v = Quality.requestedPreset()
  if v == "auto" then return Quality.autoTier() end
  return v
end

local function presetValue(field, customKey, fallback)
  local p = Quality.preset()
  if p ~= "custom" then
    local row = PRESETS[p] or PRESETS.medium
    return row[field]
  end
  return option(customKey, fallback)
end

function Quality.renderFactor()
  local p = Quality.preset()
  local value
  if p ~= "custom" then
    value = (PRESETS[p] or PRESETS.medium).resolution
  else
    local raw = tostring(option("graphicsResolution", "55"))
    local n = tonumber(raw)
    value = n and n / 100 or 0.55
  end
  if value < 0.30 then value = 0.30 end
  if value > 1.00 then value = 1.00 end
  return value
end

-- Historical helper consumed by sky detail. Convert the true scale factor into
-- the old "1 = full, 4 = quarter" vocabulary.
function Quality.scale()
  local f = Quality.renderFactor()
  if f >= 0.90 then return 1 end
  if f >= 0.65 then return 2 end
  if f >= 0.48 then return 3 end
  return 4
end

function Quality.shadows()
  local value = presetValue("shadows", "graphicsShadows", "low")
  value = tostring(value):lower()
  if value == "off" or value == "blob" or value == "low" or value == "high" or value == "soft" then
    return value
  end
  local ok, legacy = pcall(Quality.shadowSetting.get, Quality.shadowSetting)
  if ok then return legacy end
  return "low"
end

function Quality.shadowsOff()
  return Quality.shadows() == "off"
end

function Quality.blobShadows()
  return Quality.shadows() == "blob"
end

function Quality.softShadows()
  local v = Quality.shadows()
  return v == "high" or v == "soft"
end

function Quality.pcss()
  return Quality.shadows() == "soft"
end

function Quality.shadowSizes()
  local s = Quality.shadows()
  if s == "soft" then return { 1024, 1536, 2048 } end
  if s == "high" then return { 768, 1024, 1536 } end
  return { 384, 512, 768 }
end

function Quality.shadowTarget()
  local s = Quality.shadows()
  if s == "soft" then return 0.45 end
  if s == "high" then return 0.75 end
  return 1.65
end

function Quality.shadowInterval()
  local s = Quality.shadows()
  if s == "soft" then return 1 end
  if s == "high" then return 2 end
  -- LOW updates at 20 Hz while moving.  At voxel/pixel-art scale that remains
  -- visually stable, and the cached signature still means a stationary camera
  -- performs no repeated shadow terrain render at all.
  return 3
end

function Quality.reflections()
  local value = tostring(presetValue("reflections", "graphicsReflections", "sky")):lower()
  if value == "full" or value == "sky" or value == "off" then return value end
  return "sky"
end

-- Kanto terrain-sector radius while actually walking the Yellow excursion.
-- The current map always exists; 1/2/3 controls only how many connected rings
-- are prefetched around it.  Crossing a seam immediately re-roots the ring.
function Quality.kantoRadius()
  local p = Quality.preset()
  local n
  if p ~= "custom" then
    n = (PRESETS[p] or PRESETS.medium).kanto
  else
    n = tonumber(option("graphicsKantoRadius", "2"))
  end
  n = math.floor(tonumber(n) or 2)
  if n < 1 then n = 1 end
  if n > 3 then n = 3 end
  return n
end

function Quality.drawDistance()
  local value = tostring(presetValue("draw", "graphicsDrawDistance", "balanced")):lower()
  if value == "near" or value == "balanced" or value == "far" or value == "max" then
    return value
  end
  return "balanced"
end

-- Extra world-space padding beyond the nominal camera rectangle before a map
-- is considered offscreen. Perspective/tilt can see farther than a flat box,
-- so even NEAR keeps half a view of safety. MAX disables far-map culling.
function Quality.worldCullPadding(vw, vh)
  local mode = Quality.drawDistance()
  if mode == "max" then return math.huge end
  local base = math.max(tonumber(vw) or 160, tonumber(vh) or 144)
  local mult = ({ near = 0.35, balanced = 0.60, far = 1.05 })[mode] or 0.60
  return base * mult
end

-- Actor range is presentation-only. NPC collision and trainer records remain
-- alive outside it; the renderer simply does not spend Stadium/2D draw work on
-- people/Pokemon too far away to contribute to the current view.

-- Distant connected maps still keep their terrain/water so OPEN WORLD never
-- exposes a void, but tiny decorative passes (grass, flowers, furniture
-- figures and their shadow casters) do not need the very generous terrain
-- apron. These paddings are in world pixels beyond the actual camera box.
function Quality.detailCullPadding(vw, vh)
  local mode = Quality.drawDistance()
  local base = math.max(tonumber(vw) or 160, tonumber(vh) or 144)
  local mult = ({ near = 0.12, balanced = 0.24, far = 0.48, max = 0.75 })[mode] or 0.24
  return math.max(48, base * mult)
end

-- Authored furniture/people are separate billboard meshes. Cull only when
-- safely outside the view; their gameplay records remain untouched.
function Quality.figureCullPadding(vw, vh)
  local mode = Quality.drawDistance()
  if mode == "near" then return 40 end
  if mode == "balanced" then return 64 end
  if mode == "far" then return 112 end
  return 160
end

-- Dynamic NPC/Pokemon cards use the same conservative off-screen rule. This
-- does not limit what is visible at wide zoom; it only avoids drawing actors
-- that lie beyond the camera rectangle plus the selected safety margin.
function Quality.actorCullPadding(vw, vh)
  local mode = Quality.drawDistance()
  if mode == "near" then return 48 end
  if mode == "balanced" then return 80 end
  if mode == "far" then return 128 end
  return 192
end

function Quality.actorDistanceCells()
  local mode = Quality.drawDistance()
  if mode == "near" then return 10 end
  if mode == "balanced" then return 16 end
  if mode == "far" then return 26 end
  return math.huge
end

function Quality.buildMode()
  local v = tostring(presetValue("build", "graphicsBuildRate", "balanced")):lower()
  if v == "smooth" or v == "balanced" or v == "fast" then return v end
  return "balanced"
end

-- Seconds of cooperative Lua mesh work allowed in a frame. "SMOOTH" lowers
-- hitch risk; "FAST" lets background terrain become visible sooner.
function Quality.buildSlices()
  local mode = Quality.buildMode()
  -- v0.3.05: these are intentionally smaller than the old values. The Gold
  -- bridge used to pump this cooperative builder twice in a visible frame, so
  -- a BALANCED urgent job could consume roughly 20 ms of CPU before the GPU
  -- even rendered the scene. The bridge now pumps once during steady-state;
  -- keeping the slices tighter also prevents a single new route/atlas from
  -- turning camera motion into visible hitching on phones and integrated GPUs.
  if mode == "smooth" then return 0.0030, 0.0010, 0.008 end
  if mode == "fast" then return 0.0080, 0.0035, 0.022 end
  return 0.0045, 0.0018, 0.012
end

-- How many never-before-decoded Yellow maps may have their colored atlas/map
-- adapter prepared in one survey frame. This converts Kanto toggle-on from one
-- giant synchronous spike into progressive streaming.
function Quality.kantoSurveyBatch()
  local mode = Quality.buildMode()
  if mode == "smooth" then return 1 end
  if mode == "fast" then return 4 end
  return 2
end

function Quality.kantoSurveyLimit(total)
  local mode = Quality.drawDistance()
  total = math.max(1, math.floor(tonumber(total) or 1))
  if mode == "max" then return total end
  local cap = mode == "near" and 8 or (mode == "far" and 28 or 16)
  return math.min(total, cap)
end


function Quality.starCount()
  local s = Quality.scale()
  if s <= 1 then return 96 end
  if s == 2 then return 72 end
  if s == 3 then return 48 end
  return 32
end

function Quality.fogBands()
  local s = Quality.scale()
  if s >= 4 then return 0 end
  if s == 3 then return 2 end
  return 4
end

function Quality.rainbow()
  return Quality.scale() < 4
end

function Quality.cloudSteps()
  local s = Quality.scale()
  if s >= 4 then return 0 end
  if s == 3 then return 4 end
  if s == 2 then return 6 end
  return 8
end

function Quality.neighbourShadows()
  return Quality.softShadows()
end

function Quality.status()
  local u, i, c = Quality.buildSlices()
  return {
    requestedPreset = Quality.requestedPreset(),
    preset = Quality.preset(),
    adaptiveTier = Quality.autoTier(),
    adaptiveDrawMs = auto.ema * 1000,
    adaptiveLastDrawMs = auto.lastCost * 1000,
    adaptiveTargetFps = auto.targetFps,
    adaptiveChanges = auto.changes,
    renderFactor = Quality.renderFactor(),
    shadows = Quality.shadows(),
    reflections = Quality.reflections(),
    drawDistance = Quality.drawDistance(),
    kantoRadius = Quality.kantoRadius(),
    buildMode = Quality.buildMode(),
    buildUrgent = u, buildIdle = i, buildCovered = c,
    runtimePreset = runtimePreset,
    autoCustomWrites = autoCustomWrites,
  }
end

-- Listen once inside the renderer namespace. The engine still owns the actual
-- option write/event; this only applies PC-style "editing a child row means
-- CUSTOM" semantics and makes the change effective in the very same frame.
if mod and mod.events and type(mod.events.on) == "function" then
  pcall(mod.events.on, mod.events, "mod.options_changed", function(payload)
    Quality.noteOptionChanged(payload)
  end)
end

return Quality
