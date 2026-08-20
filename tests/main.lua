-- Run from the mod root with either:
--   luajit tests/main.lua
--   lovec tests

local checks = 0

local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(
      label, tostring(expected), tostring(actual)), 2)
  end
end

local function countAction(items, action)
  local count = 0
  for _, item in ipairs(items) do
    if item.action == action then count = count + 1 end
  end
  return count
end

local function indexOfAction(items, action)
  for index, item in ipairs(items) do
    if item.action == action then return index end
  end
end

local speedResponder
local speedCalls = 0

local Runtime = {}
function Runtime.wantsHook(name)
  return name == "movement.speed" and speedResponder ~= nil
end
function Runtime.call(name, vanilla, frames, ctx)
  eq(name, "movement.speed", "hook name")
  speedCalls = speedCalls + 1
  if speedResponder then return speedResponder(frames, ctx) end
  return vanilla(frames, ctx)
end

local Game = {
  save = { onBike = false },
  input = { isDown = function() return true end },
}

local Map = {}
function Map.isOutside(def, outsideTilesets)
  eq(outsideTilesets, "fixture-outside-tilesets", "outside tileset data")
  return def and def.fixtureOutside == true or false
end

local FieldDefaults = {}
function FieldDefaults.field(data, key)
  eq(key, "outsideTilesets", "outside field key")
  return data and data.fields and data.fields.outsideTilesets
end

local ItemEffects = {
  isBall = function() return false end,
  needsTarget = function() return false end,
  use = function() return "failed", { "No effect." } end,
}
local Bag = {}
function Bag.order(save)
  save.bagOrder = save.bagOrder or {}
  return save.bagOrder
end
function Bag.add(save, id, qty)
  save.inventory[id] = (save.inventory[id] or 0) + (qty or 1)
  return true
end
function Bag.remove(save, id, qty)
  save.inventory[id] = (save.inventory[id] or 0) - (qty or 1)
  if save.inventory[id] <= 0 then save.inventory[id] = nil end
end

package.preload["src.mods.Runtime"] = function() return Runtime end
package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.Map"] = function() return Map end
package.preload["src.world.FieldDefaults"] = function() return FieldDefaults end
package.preload["src.core.Strings"] = function()
  return function(value) return value end
end
package.preload["src.inventory.ItemEffects"] = function() return ItemEffects end
package.preload["src.inventory.Bag"] = function() return Bag end
package.preload["src.ui.BagMenu"] = function()
  return { new = function() return {} end }
end
package.preload["src.ui.ShopMenu"] = function()
  return { new = function() return {} end }
end

local entry = assert(loadfile("main.lua"))()

local function fixture(opts)
  opts = opts or {}
  local seen = {}
  local hooks = {}
  local eventListeners = {}
  local optionSchema
  local FreeMove = { WALK = 1, BIKE = 2 }
  local FirstPerson = {
    hidePlayer = function()
      return opts.firstPersonHidden ~= false
    end,
  }
  local originalTick
  originalTick = function(state)
    seen.walk, seen.bike = FreeMove.WALK, FreeMove.BIKE
    if opts.throwTick then error("tick exploded") end
    return "tick-result", 42
  end
  FreeMove.tick = originalTick

  local runningShoesTick
  if opts.runningShoesTick then
    local runningShoesInner = FreeMove.tick
    runningShoesTick = function(state)
      return runningShoesInner(state)
    end
    FreeMove.tick = runningShoesTick
    FreeMove.runningShoesTick = runningShoesTick
    FreeMove.runningShoesInner = runningShoesInner
  end

  local lib = {
    _runningShoesHook = opts.runningShoesHook,
    _voxelRunBridgeHook = opts.bridgeHook,
    require = function(name)
      if opts.requireError then error("provider loader failed") end
      if name == "FreeMove" then return FreeMove end
      if name == "FirstPerson" then return FirstPerson end
      if name == "ScottPrecacheScreen" and opts.cacheScreen then
        return opts.cacheScreen
      end
      error("provider module unavailable: " .. tostring(name))
    end,
  }
  local exportedLib = opts.malformedLib and 42 or lib
  local voxel = {
    version = opts.voxelVersion,
    exports = { lib = exportedLib, version = opts.voxelExportVersion },
  }
  local logs = {}
  local options = {}
  function options:define(schema)
    eq(type(schema), "table", "options schema type")
    optionSchema = schema
    return schema
  end
  function options:get(key)
    if key == "hm_without_badges" and opts.hmWithoutBadges ~= nil then
      return opts.hmWithoutBadges
    end
    if key == "free_fly_without_badges"
        and opts.freeFlyWithoutBadges ~= nil then
      return opts.freeFlyWithoutBadges
    end
    if key == "free_fly_cockpit" and opts.freeFlyCockpit ~= nil then
      return opts.freeFlyCockpit
    end
    for _, row in ipairs(optionSchema or {}) do
      if row.key == key then return row.default end
    end
  end

  local events = {}
  function events:on(name, callback)
    eventListeners[name] = eventListeners[name] or {}
    table.insert(eventListeners[name], callback)
  end
  function events:emit(name, payload)
    for _, callback in ipairs(eventListeners[name] or {}) do callback(payload) end
  end

  local loader = { modOptions = {}, optionSchemas = {} }
  if opts.freeFlyStoredBadges ~= nil then
    loader.modOptions.free_fly = {
      badges = opts.freeFlyStoredBadges,
    }
  end
  if opts.freeFly and not opts.freeFlySchemaMissing then
    loader.optionSchemas.free_fly = {
      {
        key = "badges",
        type = opts.freeFlySchemaWrong and "choice" or "toggle",
        default = true,
      },
      { key = "gates", type = "toggle", default = true },
    }
  end
  Game.mods = loader

  local function freeFlyBadgeChecks()
      local bucket = loader.modOptions.free_fly
      if bucket and bucket.badges ~= nil then
        return bucket.badges
      end
      return true
  end
  local function freeFlyStartFlight(save)
    if not save.knowsFly then return false, "FLY REQUIRED" end
    if save.storyBlocked then return false, "STORY BLOCKED" end
    if freeFlyBadgeChecks()
        and not (save.inventory or {}).THUNDERBADGE then
      return false, "THUNDERBADGE REQUIRED"
    end
    return true, "TAKEOFF"
  end
  local freeFly = {
    version = opts.freeFlyVersion or "1.5.0",
    exports = opts.freeFlyMalformed and {} or {
      isFlying = function() return opts.freeFlyFlying == true end,
    },
  }

  local hookApi = {}
  function hookApi:wrap(name, callback)
    hooks[name] = callback
    return function()
      if hooks[name] == callback then hooks[name] = nil end
    end
  end

  local mod = {
    id = "voxel_run_bridge",
    exports = {},
    hooks = hookApi,
    events = events,
    options = options,
    content = {
      items = { register = function() end },
      item_effects = { register = function() end },
      screens = {
        get = function() return nil end,
        override = function() end,
      },
    },
    log = {
      info = function(_, message) logs[#logs + 1] = message end,
      warn = function(_, message) logs[#logs + 1] = message end,
    },
    find = function(id)
      if opts.freeFly and id == "free_fly" then return freeFly end
      if not opts.noVoxel and id == (opts.voxelId or "DRAMATIC_SHAPE") then
        return voxel
      end
    end,
  }

  entry(mod)

  if opts.lateRunningShoesTick then
    local runningShoesInner = FreeMove.tick
    runningShoesTick = function(state)
      local baseWalk, baseBike = FreeMove.WALK, FreeMove.BIKE
      FreeMove.WALK = baseWalk * 2
      local first, second = runningShoesInner(state)
      FreeMove.WALK, FreeMove.BIKE = baseWalk, baseBike
      return first, second
    end
    FreeMove.tick = runningShoesTick
    FreeMove.runningShoesTick = runningShoesTick
    FreeMove.runningShoesInner = runningShoesInner
  end

  return {
    mod = mod,
    lib = lib,
    FreeMove = FreeMove,
    FirstPerson = FirstPerson,
    originalTick = originalTick,
    runningShoesTick = runningShoesTick,
    seen = seen,
    logs = logs,
    hooks = hooks,
    optionSchema = function() return optionSchema end,
    events = events,
    loader = loader,
    freeFlyBadgeChecks = freeFlyBadgeChecks,
    freeFlyStartFlight = freeFlyStartFlight,
    cacheScreen = opts.cacheScreen,
  }
end

local function player(fields)
  local p = {
    stepFrames = 16,
    bikeStepFrames = 8,
    surfing = false,
    moving = false,
    inputLocked = false,
  }
  for key, value in pairs(fields or {}) do p[key] = value end
  return p
end

-- Foot speed: 16 frames -> 8 frames is a 2x FreeMove walk.
speedResponder = function(frames, ctx)
  eq(frames, 16, "foot base frames")
  eq(ctx.onBike, false, "foot context")
  eq(ctx.freeMove, true, "free-move context")
  eq(ctx.continuous, true, "continuous context")
  return 8
end
speedCalls = 0
Game.save = { onBike = false }
local foot = fixture()
local a, b = foot.FreeMove.tick({ player = player() })
eq(a, "tick-result", "first tick return")
eq(b, 42, "second tick return")
eq(foot.seen.walk, 2, "foot multiplier visible inside tick")
eq(foot.seen.bike, 2, "bike speed untouched on foot")
eq(foot.FreeMove.WALK, 1, "walk speed restored")
eq(foot.FreeMove.BIKE, 2, "bike speed restored after foot tick")
eq(speedCalls, 1, "foot hook call count")

-- Pokemon Final is Scott's fused Dramatic Shape/Kanto package. It keeps the
-- same exported FreeMove seam under its own stable manifest id, so running in
-- its 1ST/3RD camera modes must be bridged exactly like Dramatic Shape.
speedCalls = 0
local pokemonFinal = fixture({ voxelId = "POKEMON_FINAL" })
eq(pokemonFinal.mod.exports.status.active, true,
  "Pokemon Final bridge is active")
eq(pokemonFinal.mod.exports.status.voxel, "POKEMON_FINAL",
  "Pokemon Final provider is reported")
pokemonFinal.FreeMove.tick({ player = player() })
eq(pokemonFinal.seen.walk, 2,
  "Pokemon Final first-person walk receives running multiplier")
eq(pokemonFinal.FreeMove.WALK, 1,
  "Pokemon Final walk speed is restored after tick")
eq(speedCalls, 1, "Pokemon Final hook call count")
eq(pokemonFinal.lib._voxelRunBridgeHook.version, "0.12.2",
  "Pokemon Final bridge marker reports release version")

-- Early Pokemon Final packages could start the disk-cache job successfully
-- while leaving a false fallback message on the cache screen. The companion
-- patch is selected by behavior, preserves the private module's implementation,
-- and never needs its source in this public test fixture.
local buggyCacheScreen = {}
local buggyCacheStart = function(self, rebuild)
  if self.throwStart then error("cache start exploded") end
  local ok, err = self.precache.beginDisk(self.game, rebuild)
  if ok then
    self.message = "could not start"
  else
    self.message = tostring(err or "could not start")
  end
  return "cache-result", 17
end
buggyCacheScreen._start = buggyCacheStart

local cachePatched = fixture({
  voxelId = "POKEMON_FINAL",
  voxelVersion = "1.8.1-scott.2",
  cacheScreen = buggyCacheScreen,
})
local cacheCompat = cachePatched.mod.exports.pokemonFinalCacheCompat
eq(cacheCompat.active, true, "buggy Pokemon Final cache screen is patched")
eq(cacheCompat.reason, "patched", "cache compatibility patch reason")
eq(cacheCompat.screen, "patched", "cache screen compatibility status")
eq(type(buggyCacheScreen._scottsTweaksCacheStartHook), "table",
  "cache screen receives an ownership marker")
eq(buggyCacheScreen._scottsTweaksCacheStartHook.owner, "voxel_run_bridge",
  "cache screen marker identifies its owner")
eq(buggyCacheScreen._scottsTweaksCacheStartHook.version, "0.12.2",
  "cache screen marker identifies its release")
eq(buggyCacheScreen._scottsTweaksCacheStartHook.original, buggyCacheStart,
  "cache screen marker retains the exact original")

local beginCalls, statusCalls = 0, 0
local cacheScreenInstance = {
  game = {},
  message = "old message",
  precache = {
    beginDisk = function(_, rebuild)
      beginCalls = beginCalls + 1
      eq(rebuild, false, "cache start forwards rebuild argument")
      return true
    end,
    status = function()
      statusCalls = statusCalls + 1
      return { state = "building" }
    end,
  },
}
local cacheA, cacheB = buggyCacheScreen._start(cacheScreenInstance, false)
eq(cacheA, "cache-result", "cache wrapper preserves first return")
eq(cacheB, 17, "cache wrapper preserves second return")
eq(beginCalls, 1, "cache wrapper calls the original exactly once")
eq(statusCalls, 1, "cache wrapper verifies the successful build state")
eq(cacheScreenInstance.message, nil,
  "cache wrapper clears only the false successful-start fallback")

local failedCacheScreen = {
  game = {},
  precache = {
    beginDisk = function() return false, "storage denied" end,
    status = function() return { state = "idle" } end,
  },
}
buggyCacheScreen._start(failedCacheScreen, true)
eq(failedCacheScreen.message, "storage denied",
  "cache wrapper preserves a real start failure")

local notBuildingScreen = {
  game = {},
  precache = {
    beginDisk = function() return true end,
    status = function() return { state = "idle" } end,
  },
}
buggyCacheScreen._start(notBuildingScreen, false)
eq(notBuildingScreen.message, "could not start",
  "cache wrapper requires a confirmed building state")

local throwingScreen = {
  throwStart = true,
  game = {},
  precache = {
    beginDisk = function() error("must not be reached") end,
    status = function() return { state = "building" } end,
  },
}
local okCacheError, cacheError = pcall(
  buggyCacheScreen._start, throwingScreen, false)
eq(okCacheError, false, "cache wrapper preserves original errors")
eq(tostring(cacheError):find("cache start exploded", 1, true) ~= nil, true,
  "cache wrapper preserves original error text")

local firstCacheWrapper = buggyCacheScreen._start
local cacheReloaded = fixture({
  voxelId = "POKEMON_FINAL",
  voxelVersion = "1.8.1-scott.2",
  cacheScreen = buggyCacheScreen,
})
eq(buggyCacheScreen._start, firstCacheWrapper,
  "cache compatibility install is idempotent")
eq(cacheReloaded.mod.exports.pokemonFinalCacheCompat.reason,
  "already_installed", "idempotent cache compatibility status")

local foreignScreen = { _start = buggyCacheStart }
foreignScreen._scottsTweaksCacheStartHook = { owner = "another_mod" }
local foreignCache = fixture({
  voxelId = "POKEMON_FINAL",
  voxelVersion = "1.8.1-scott.2",
  cacheScreen = foreignScreen,
})
eq(foreignScreen._start, buggyCacheStart,
  "foreign-owned cache screen is not overwritten")
eq(foreignCache.mod.exports.pokemonFinalCacheCompat.screen, "foreign_owner",
  "foreign cache ownership is reported")

local fixedCacheScreen = {}
local fixedCacheStart = function(self, rebuild)
  local ok, err = self.precache.beginDisk(self.game, rebuild)
  if ok then self.message = nil
  else self.message = tostring(err or "could not start") end
end
fixedCacheScreen._start = fixedCacheStart
local cacheAlreadyFixed = fixture({
  voxelId = "POKEMON_FINAL",
  voxelVersion = "1.8.1-scott.3",
  cacheScreen = fixedCacheScreen,
})
eq(fixedCacheScreen._start, fixedCacheStart,
  "fixed Pokemon Final cache screen remains untouched")
eq(fixedCacheScreen._scottsTweaksCacheStartHook, nil,
  "fixed cache screen receives no ownership marker")
eq(cacheAlreadyFixed.mod.exports.pokemonFinalCacheCompat.screen,
  "already_safe", "fixed cache screen is recognized by behavior")

eq(cacheReloaded.mod.exports.pokemonFinalCacheCompat.restore(), true,
  "cache wrapper can restore its exact original")
eq(buggyCacheScreen._start, buggyCacheStart,
  "cache restore reinstates the original function")
eq(buggyCacheScreen._scottsTweaksCacheStartHook, nil,
  "cache restore removes only its own marker")

-- Bike speed uses the bike frame baseline and scales only BIKE.
speedResponder = function(frames, ctx)
  eq(frames, 8, "bike base frames")
  eq(ctx.onBike, true, "bike context")
  return 4
end
Game.save = { onBike = true }
local bike = fixture({ voxelId = "potato_voxel" })
bike.FreeMove.tick({ player = player() })
eq(bike.seen.walk, 1, "walk speed untouched on bike")
eq(bike.seen.bike, 4, "bike multiplier visible inside tick")
eq(bike.FreeMove.BIKE, 2, "bike speed restored")

-- Invalid hook output degrades to the voxel defaults.
speedResponder = function() return "not-a-speed" end
Game.save = { onBike = false }
local invalid = fixture({ voxelId = "DRAMALESS_SHAPE" })
invalid.FreeMove.tick({ player = player() })
eq(invalid.seen.walk, 1, "invalid speed falls back")

-- Numeric zero/negative output follows the engine's >=1 frame clamp.
speedResponder = function() return 0 end
local clamped = fixture({ voxelId = "BATTLE_ART_VOXEL_FORK" })
clamped.FreeMove.tick({ player = player() })
eq(clamped.seen.walk, 16, "zero speed result clamps to one frame")
eq(clamped.FreeMove.WALK, 1, "clamped walk speed restored")

-- Slower hooks are translated too; this is not hard-coded as a run boost.
speedResponder = function() return 32 end
local slowed = fixture()
slowed.FreeMove.tick({ player = player() })
eq(slowed.seen.walk, 0.5, "slower hook halves free movement")
eq(slowed.FreeMove.WALK, 1, "slower walk speed restored")

-- The bridge is dormant until another mod registers movement.speed.
speedResponder = nil
speedCalls = 0
local noProducer = fixture()
local passA, passB = noProducer.FreeMove.tick({ player = player() })
eq(passA, "tick-result", "no-producer first return")
eq(passB, 42, "no-producer second return")
eq(noProducer.seen.walk, 1, "no producer keeps voxel default")
eq(speedCalls, 0, "no producer hook calls")

-- A broken speed producer fails closed and warns only once per session.
speedResponder = function() error("speed hook exploded") end
speedCalls = 0
local brokenSpeed = fixture()
brokenSpeed.FreeMove.tick({ player = player() })
brokenSpeed.FreeMove.tick({ player = player() })
eq(brokenSpeed.seen.walk, 1, "broken speed hook keeps voxel default")
eq(brokenSpeed.FreeMove.WALK, 1, "broken speed hook leaves walk restored")
eq(speedCalls, 2, "broken speed hook was sampled")
eq(#brokenSpeed.logs, 2, "broken speed hook warns once after install log")

-- Scripted and input-locked movement never consults the hook.
speedResponder = function() return 1 end
speedCalls = 0
local scripted = fixture()
scripted.FreeMove.tick({ player = player({ moving = true }) })
scripted.FreeMove.tick({ player = player({ inputLocked = true }) })
eq(speedCalls, 0, "scripted movement hook calls")
eq(scripted.seen.walk, 1, "scripted movement keeps default")

-- Temporary constants are restored even if the voxel tick errors.
speedResponder = function() return 8 end
local broken = fixture({ throwTick = true })
local ok, err = pcall(broken.FreeMove.tick, { player = player() })
eq(ok, false, "tick error propagates")
eq(type(err), "string", "tick error has traceback text")
eq(broken.FreeMove.WALK, 1, "walk restored after error")
eq(broken.FreeMove.BIKE, 2, "bike restored after error")

-- Native Running Shoes integration remains the only wrapper when present.
local delegated = fixture({ runningShoesHook = true })
eq(delegated.FreeMove.tick, delegated.originalTick, "native integration not wrapped")
eq(delegated.mod.exports.status.reason,
  "running_shoes_has_native_voxel_support", "delegation reason")

-- Running Shoes 1.7 publishes ownership on the FreeMove table rather than
-- the voxel library. Scott's bridge must feature-detect that live wrapper
-- after loading the module or both adapters multiply the same run.
speedCalls = 0
local delegatedTick = fixture({
  voxelId = "DRAMATIC_SHAPE",
  runningShoesTick = true,
})
eq(delegatedTick.FreeMove.tick, delegatedTick.runningShoesTick,
  "Running Shoes FreeMove wrapper remains the single owner")
eq(delegatedTick.mod.exports.status.reason,
  "running_shoes_has_native_voxel_support",
  "FreeMove ownership delegation reason")
delegatedTick.FreeMove.tick({ player = player() })
eq(speedCalls, 0, "bridge does not double-sample native Running Shoes")

-- MadeinTaly 1.7 discovers Dramatic Shape from input.step, after all mods
-- have loaded. Its native wrapper can therefore appear outside an already
-- installed Scott bridge. The call-time ownership check must pass through
-- the native 2x speed instead of multiplying it a second time.
speedCalls = 0
local lateDelegated = fixture({
  voxelId = "DRAMATIC_SHAPE",
  lateRunningShoesTick = true,
})
lateDelegated.FreeMove.tick({ player = player() })
eq(lateDelegated.seen.walk, 2,
  "late native Running Shoes wrapper applies exactly one multiplier")
eq(lateDelegated.FreeMove.WALK, 1,
  "late native Running Shoes restores the walk constant")
eq(speedCalls, 0,
  "late native wrapper prevents Scott from sampling movement.speed again")
eq(lateDelegated.mod.exports.status.active, false,
  "late native wrapper switches Scott's bridge status to idle")
eq(lateDelegated.mod.exports.status.reason,
  "running_shoes_has_native_voxel_support",
  "late native wrapper reports delegation reason")

-- A previous bridge marker prevents nested wrappers on a reload.
local already = fixture({ bridgeHook = { owner = "previous" } })
eq(already.FreeMove.tick, already.originalTick, "bridge is not installed twice")
eq(already.mod.exports.status.reason, "already_installed",
  "existing bridge reason")

-- Malformed companion exports and throwing module loaders fail closed.
local malformed = fixture({ malformedLib = true })
eq(malformed.mod.exports.status.reason, "no_supported_voxel_mod",
  "malformed export reason")
local loaderError = fixture({ requireError = true })
eq(loaderError.FreeMove.tick, loaderError.originalTick,
  "throwing provider loader is not wrapped")
eq(loaderError.mod.exports.status.reason, "voxel_freemove_unavailable",
  "throwing provider loader reason")

-- Installing without a supported voxel mod is a clean no-op.
local absent = fixture({ noVoxel = true })
eq(absent.mod.exports.status.active, false, "no-voxel status")
eq(absent.mod.exports.status.reason, "no_supported_voxel_mod",
  "no-voxel reason")

-- The player-facing rename must not change the installed mod's stable id.
local manifestFile = assert(io.open("manifest.json", "rb"))
local manifest = manifestFile:read("*a")
manifestFile:close()
eq(manifest:match('"id"%s*:%s*"([^"]+)"'), "voxel_run_bridge",
  "stable manifest id")
eq(manifest:match('"name"%s*:%s*"([^"]+)"'), "Scott's Tweaks",
  "player-facing manifest name")
eq(manifest:match('"version"%s*:%s*"([^"]+)"'), "0.12.2",
  "manifest patch version")

-- Scott's Tweaks exposes the badge bypass as an ordinary, default-on option.
local schema = absent.optionSchema()
eq(type(schema), "table", "HM option schema exists")
local hmOption
for _, row in ipairs(schema or {}) do
  if row.key == "hm_without_badges" then hmOption = row end
end
eq(type(hmOption), "table", "HM option row exists")
eq(hmOption and hmOption.type, "toggle", "HM option type")
eq(hmOption and hmOption.default, true, "HM option default")

local freeFlyOption
for _, row in ipairs(schema or {}) do
  if row.key == "free_fly_without_badges" then freeFlyOption = row end
end
eq(type(freeFlyOption), "table", "Free Fly option row exists")
eq(freeFlyOption and freeFlyOption.type, "toggle", "Free Fly option type")
eq(freeFlyOption and freeFlyOption.default, true, "Free Fly option default")

local cockpitOption
for _, row in ipairs(schema or {}) do
  if row.key == "free_fly_cockpit" then cockpitOption = row end
end
eq(type(cockpitOption), "table", "Free Fly cockpit option row exists")
eq(cockpitOption and cockpitOption.type, "toggle",
  "Free Fly cockpit option type")
eq(cockpitOption and cockpitOption.default, false,
  "Free Fly cockpit defaults to a clear first-person view")

-- Free Fly 1.6.2's cockpit picture is gated by FirstPerson.hidePlayer inside
-- its render.hud wrapper. Scott's higher-priority HUD link changes that one
-- answer only while the downstream HUD chain runs, then restores the exact
-- function identity. This simulates Free Fly's check without copying its draw.
local cockpitHidden = fixture({
  freeFly = true,
  freeFlyVersion = "1.6.2",
  freeFlyFlying = true,
})
local cockpitStatus = cockpitHidden.mod.exports.freeFlyCockpitControl
eq(cockpitStatus.active, true, "Free Fly cockpit adapter reports active")
eq(cockpitStatus.reason, "first_person_hud_overlay_controlled",
  "Free Fly cockpit adapter reports its narrow HUD mode")
eq(cockpitStatus.version, "1.6.2",
  "Free Fly cockpit adapter reports verified version")
local originalHidePlayer = cockpitHidden.FirstPerson.hidePlayer
local hiddenDuringHud
local hudA, hudB = cockpitHidden.hooks["render.hud"](
  function()
    hiddenDuringHud = cockpitHidden.FirstPerson.hidePlayer()
    return "hud-result", 17
  end, {}, {})
eq(hiddenDuringHud, false,
  "default-off cockpit makes only the downstream HUD see a visible card")
eq(hudA, "hud-result", "cockpit adapter preserves first HUD return value")
eq(hudB, 17, "cockpit adapter preserves second HUD return value")
eq(cockpitHidden.FirstPerson.hidePlayer, originalHidePlayer,
  "cockpit adapter restores FirstPerson visibility function")
eq(cockpitHidden.FirstPerson.hidePlayer(), true,
  "world-render first-person visibility remains hidden after HUD")

local bundledCockpit = fixture({
  freeFly = true,
  freeFlyVersion = "1.8.0",
  freeFlyFlying = true,
})
eq(bundledCockpit.mod.exports.freeFlyCockpitControl.active, true,
  "bundled Free Fly 1.8.0 cockpit adapter is active")
local bundledDuringHud
bundledCockpit.hooks["render.hud"](function()
  bundledDuringHud = bundledCockpit.FirstPerson.hidePlayer()
end, {}, {})
eq(bundledDuringHud, false,
  "bundled Free Fly cockpit is hidden by the default setting")

local cockpitShown = fixture({
  freeFly = true,
  freeFlyVersion = "1.6.2",
  freeFlyFlying = true,
  freeFlyCockpit = true,
})
local shownHide = cockpitShown.FirstPerson.hidePlayer
local shownDuringHud
cockpitShown.hooks["render.hud"](function()
  shownDuringHud = cockpitShown.FirstPerson.hidePlayer()
end, {}, {})
eq(shownDuringHud, true,
  "enabled cockpit leaves Free Fly's original first-person gate intact")
eq(cockpitShown.FirstPerson.hidePlayer, shownHide,
  "enabled cockpit never substitutes the visibility function")

local groundedCockpit = fixture({
  freeFly = true,
  freeFlyVersion = "1.6.2",
  freeFlyFlying = false,
})
local groundedHide = groundedCockpit.FirstPerson.hidePlayer
local groundedDuringHud
groundedCockpit.hooks["render.hud"](function()
  groundedDuringHud = groundedCockpit.FirstPerson.hidePlayer()
end, {}, {})
eq(groundedDuringHud, true,
  "grounded HUD does not receive the cockpit substitution")
eq(groundedCockpit.FirstPerson.hidePlayer, groundedHide,
  "grounded HUD leaves visibility ownership untouched")

local thirdPersonCockpit = fixture({
  freeFly = true,
  freeFlyVersion = "1.6.2",
  freeFlyFlying = true,
  firstPersonHidden = false,
})
local thirdHide = thirdPersonCockpit.FirstPerson.hidePlayer
local thirdDuringHud
thirdPersonCockpit.hooks["render.hud"](function()
  thirdDuringHud = thirdPersonCockpit.FirstPerson.hidePlayer()
end, {}, {})
eq(thirdDuringHud, false,
  "third-person visibility remains the provider's ordinary answer")
eq(thirdPersonCockpit.FirstPerson.hidePlayer, thirdHide,
  "third-person flight never substitutes the visibility function")

local throwingCockpit = fixture({
  freeFly = true,
  freeFlyVersion = "1.6.2",
  freeFlyFlying = true,
})
local throwingHide = throwingCockpit.FirstPerson.hidePlayer
local okCockpit, cockpitErr = pcall(
  throwingCockpit.hooks["render.hud"],
  function() error("hud exploded") end, {}, {})
eq(okCockpit, false, "throwing downstream HUD still propagates its error")
eq(type(cockpitErr), "string", "throwing downstream HUD returns an error")
eq(throwingCockpit.FirstPerson.hidePlayer, throwingHide,
  "cockpit adapter restores visibility after a downstream error")

local futureCockpit = fixture({
  freeFly = true,
  freeFlyVersion = "1.6.3",
  freeFlyFlying = true,
})
eq(futureCockpit.mod.exports.freeFlyCockpitControl.active, false,
  "unverified future Free Fly cockpit adapter stays inactive")
eq(futureCockpit.mod.exports.freeFlyCockpitControl.reason,
  "unsupported_free_fly_version",
  "unverified future Free Fly reports its compatibility gate")
eq(futureCockpit.hooks["render.hud"], nil,
  "unverified future Free Fly receives no HUD wrapper")

-- Free Fly's private takeoff gate reads `badges` directly from its own
-- mod.options API. Scott's runtime overlay changes that exact answer without
-- manufacturing a badge or changing Free Fly's FLY and story rules.
local freeFly = fixture({
  noVoxel = true,
  freeFly = true,
  freeFlyStoredBadges = true,
})
eq(freeFly.freeFlyBadgeChecks(), false,
  "Free Fly badge answer is overridden")
local flightSave = { inventory = {}, knowsFly = true }
local tookOff, takeoffReason = freeFly.freeFlyStartFlight(flightSave)
eq(tookOff, true, "private-style startFlight gate permits takeoff")
eq(takeoffReason, "TAKEOFF", "takeoff does not show badge error")
eq(next(flightSave.inventory), nil, "Free Fly bypass does not grant a badge")
local hasNoMove, noMoveReason = freeFly.freeFlyStartFlight({
  inventory = {}, knowsFly = false,
})
eq(hasNoMove, false, "Free Fly still requires an eligible FLY user")
eq(noMoveReason, "FLY REQUIRED", "Free Fly move rule stays enabled")
local crossesStory, storyReason = freeFly.freeFlyStartFlight({
  inventory = {}, knowsFly = true, storyBlocked = true,
})
eq(crossesStory, false, "Free Fly story gate remains enabled")
eq(storyReason, "STORY BLOCKED", "Free Fly story rule stays unchanged")
local freeFlyActive, freeFlyReason, freeFlyVersion =
  freeFly.mod.exports.freeFlyBadgeBypass()
eq(freeFlyActive, true, "Free Fly adapter reports active")
eq(freeFlyReason, "badges_runtime_override", "Free Fly adapter reason")
eq(freeFlyVersion, "1.5.0", "Free Fly adapter reports detected version")

-- A Free Fly settings change remains the player's stored preference. It is
-- held false only while Scott's override is on, then restored exactly.
freeFly.loader.modOptions.free_fly.badges = true
freeFly.events:emit("mod.options_changed", {
  mod = "free_fly", key = "badges", value = true,
})
eq(freeFly.loader.modOptions.free_fly.badges, false,
  "Free Fly badge setting stays overridden live")
freeFly.events:emit("mod.options_changed", {
  mod = "voxel_run_bridge", key = "free_fly_without_badges", value = false,
})
eq(freeFly.loader.modOptions.free_fly.badges, true,
  "turning Scott override off restores Free Fly preference")

local freeFlyDisabled = fixture({
  noVoxel = true,
  freeFly = true,
  freeFlyStoredBadges = true,
  freeFlyWithoutBadges = false,
})
eq(freeFlyDisabled.freeFlyBadgeChecks(), true,
  "disabled Scott option leaves Free Fly badge check intact")

local noFreeFly = fixture({ noVoxel = true })
eq(noFreeFly.loader.modOptions.free_fly, nil,
  "missing Free Fly leaves its option namespace untouched")

local unsupportedFreeFly = fixture({
  noVoxel = true,
  freeFly = true,
  freeFlyMalformed = true,
  freeFlyStoredBadges = true,
})
eq(unsupportedFreeFly.loader.modOptions.free_fly.badges, true,
  "unsupported Free Fly leaves its badge setting untouched")
local unsupportedActive, unsupportedReason =
  unsupportedFreeFly.mod.exports.freeFlyBadgeBypass()
eq(unsupportedActive, false, "unsupported Free Fly adapter stays inactive")
eq(unsupportedReason, "unsupported_free_fly_flight_state_export_missing",
  "unsupported Free Fly reports its reason")

local unsupportedSchema = fixture({
  noVoxel = true,
  freeFly = true,
  freeFlySchemaWrong = true,
  freeFlyStoredBadges = true,
})
eq(unsupportedSchema.loader.modOptions.free_fly.badges, true,
  "wrong Free Fly option schema is not overridden")
local schemaActive, schemaReason =
  unsupportedSchema.mod.exports.freeFlyBadgeBypass()
eq(schemaActive, false, "wrong Free Fly schema stays inactive")
eq(schemaReason, "unsupported_free_fly_badges_toggle_missing",
  "wrong Free Fly schema reports its reason")

-- HM support is installed even when there is no voxel provider to bridge.
local eligibility = absent.hooks["fieldmove.eligibility"]
local submenu = absent.hooks["ui.party.submenu"]
eq(type(eligibility), "function", "no-voxel field-move hook")
eq(type(submenu), "function", "no-voxel party-menu hook")

-- Vanilla answers win and are returned before the fallback scans the party.
local vanillaUser = { species = "BLASTOISE" }
local vanillaCalls = 0
local vanillaResult = eligibility(function(moveId, ctx)
  vanillaCalls = vanillaCalls + 1
  eq(moveId, "SURF", "vanilla eligibility move")
  eq(type(ctx), "table", "vanilla eligibility context")
  return vanillaUser
end, "SURF", {
  -- This malformed fallback data would throw if the wrapper scanned after a
  -- successful vanilla answer instead of returning it immediately.
  save = { inventory = {}, party = { { moves = false } } },
})
eq(vanillaResult, vanillaUser, "vanilla field-move user wins")
eq(vanillaCalls, 1, "vanilla eligibility called once")

-- With no badge, the fallback returns only a party member that really knows
-- the requested HM. It never grants the badge or teaches a move.
local pidgeot = {
  species = "PIDGEOT",
  moves = { { id = "WING_ATTACK" }, { id = "FLY" } },
}
local lapras = {
  species = "LAPRAS",
  moves = { { id = "SURF" }, { id = "ICE_BEAM" } },
}
local noBadgeSave = {
  inventory = {},
  party = { pidgeot, lapras },
}
local fallbackCalls = 0
local flyUser = eligibility(function(moveId, ctx)
  fallbackCalls = fallbackCalls + 1
  eq(moveId, "FLY", "fallback eligibility move")
  eq(ctx.save, noBadgeSave, "fallback eligibility save")
  return nil
end, "FLY", { save = noBadgeSave, data = {} })
eq(flyUser, pidgeot, "badge-free FLY still needs a move user")
eq(fallbackCalls, 1, "fallback eligibility called once")
eq(next(noBadgeSave.inventory), nil, "badge inventory remains untouched")

local unknownUser = eligibility(function() return nil end, "CUT", {
  save = noBadgeSave,
})
eq(unknownUser, nil, "unknown HM is not invented")

-- The party hook composes with earlier hooks, keeps their table and entries,
-- and inserts the known HMs in move-slot order before STATS/SWITCH.
local custom = { label = "QUESTS", action = "quests" }
local stats = { label = "STATS", action = "stats" }
local switch = { label = "SWITCH", action = "switch" }
local inputItems = { { label = "IGNORED", action = "ignored" } }
local chainedItems = { custom, stats, switch }
local hmMon = {
  moves = {
    { id = "CUT" },
    { id = "FLY" },
    { id = "SURF" },
    { id = "FLASH" },
    { id = "STRENGTH" },
  },
}
local fieldGame = {
  data = { fields = { outsideTilesets = "fixture-outside-tilesets" } },
  save = { inventory = {} },
}
local fieldCtx = {
  battle = false,
  overworld = {
    dark = true,
    map = { def = { fixtureOutside = true } },
  },
}
local submenuCalls = 0
local fieldItems = submenu(function(game, items, mon, ctx)
  submenuCalls = submenuCalls + 1
  eq(game, fieldGame, "submenu chained game")
  eq(items, inputItems, "submenu chained input")
  eq(mon, hmMon, "submenu chained mon")
  eq(ctx, fieldCtx, "submenu chained context")
  return chainedItems
end, fieldGame, inputItems, hmMon, fieldCtx)
eq(submenuCalls, 1, "submenu chain called once")
eq(fieldItems, chainedItems, "submenu keeps chained table")
eq(fieldItems[indexOfAction(fieldItems, "quests")], custom,
  "custom submenu row preserved")
eq(fieldItems[indexOfAction(fieldItems, "stats")], stats,
  "STATS submenu row preserved")
eq(fieldItems[indexOfAction(fieldItems, "switch")], switch,
  "SWITCH submenu row preserved")

local orderedActions = { "cut", "fly", "surf", "flash", "strength" }
local previousIndex = 0
for _, action in ipairs(orderedActions) do
  eq(countAction(fieldItems, action), 1, action .. " appears once")
  local actionIndex = indexOfAction(fieldItems, action)
  eq(type(actionIndex), "number", action .. " has a menu index")
  eq(actionIndex > previousIndex, true, action .. " keeps move-slot order")
  eq(actionIndex < indexOfAction(fieldItems, "stats"), true,
    action .. " appears before STATS")
  previousIndex = actionIndex
end

-- A vanilla/other-mod row is not duplicated when the same HM is known.
local existingFly = { label = "FLY", action = "fly" }
local existingCut = { label = "CUT", action = "cut" }
local duplicateItems = { existingFly, existingCut, stats, switch }
local deduped = submenu(function() return duplicateItems end, fieldGame, {}, {
  moves = { { id = "FLY" }, { id = "CUT" } },
}, fieldCtx)
eq(deduped, duplicateItems, "de-dup keeps submenu table")
eq(countAction(deduped, "fly"), 1, "FLY is not duplicated")
eq(countAction(deduped, "cut"), 1, "CUT is not duplicated")
eq(deduped[indexOfAction(deduped, "fly")], existingFly,
  "existing FLY row is preserved")
eq(deduped[indexOfAction(deduped, "cut")], existingCut,
  "existing CUT row is preserved")

-- FLY remains outdoors-only and FLASH remains useful only while the map is
-- dark; badge bypassing does not erase their normal environment rules.
local indoorItems = { stats, switch }
local indoorCtx = {
  battle = false,
  overworld = {
    dark = false,
    map = { def = { fixtureOutside = false } },
  },
}
local indoors = submenu(function() return indoorItems end, fieldGame, {}, {
  moves = { { id = "FLY" }, { id = "FLASH" }, { id = "CUT" } },
}, indoorCtx)
eq(countAction(indoors, "fly"), 0, "FLY stays hidden indoors")
eq(countAction(indoors, "flash"), 0, "FLASH stays hidden on a lit map")
eq(countAction(indoors, "cut"), 1, "CUT remains available indoors")

-- Battle party menus pass through byte-for-byte, even for an HM-heavy mon.
local battleItems = {
  { label = "SWITCH", action = "battle_switch" },
  { label = "STATS", action = "stats" },
  { label = "CANCEL", action = "cancel" },
}
local battleResult = submenu(function() return battleItems end, fieldGame, {},
  hmMon, { battle = true, overworld = false })
eq(battleResult, battleItems, "battle submenu table untouched")
eq(#battleResult, 3, "battle submenu row count untouched")
eq(countAction(battleResult, "fly"), 0, "battle submenu gets no FLY")

-- Turning the option off is a strict pass-through for both hook surfaces.
local disabled = fixture({ noVoxel = true, hmWithoutBadges = false })
local disabledEligibility = disabled.hooks["fieldmove.eligibility"]
local disabledSubmenu = disabled.hooks["ui.party.submenu"]
local denied = { reason = "vanilla_denied" }
local disabledResult = disabledEligibility(function() return denied end,
  "FLY", { save = { party = { pidgeot } } })
eq(disabledResult, denied, "disabled eligibility uses vanilla result")
local disabledItems = { stats, switch }
local disabledMenuResult = disabledSubmenu(function() return disabledItems end,
  fieldGame, {}, hmMon, fieldCtx)
eq(disabledMenuResult, disabledItems, "disabled submenu table untouched")
eq(#disabledMenuResult, 2, "disabled submenu rows untouched")

-- Developer hot reload rebuilds the mod without reloading required engine
-- modules. The owned v0.1.75 item adapter must therefore restore and replace
-- its exact wrapper instead of freezing the first closure forever.
local beforeReload = rawget(ItemEffects, "_scottsTweaksTradeStoneHook")
fixture({ noVoxel = true })
local afterReload = rawget(ItemEffects, "_scottsTweaksTradeStoneHook")
eq(type(beforeReload), "table", "Trade Stone compatibility marker exists")
eq(type(afterReload), "table", "Trade Stone marker survives hot reload")
eq(afterReload ~= beforeReload, true,
  "hot reload replaces the owned compatibility controller")
eq(ItemEffects.needsTarget, afterReload.wrapperNeedsTarget,
  "hot reload publishes the refreshed target wrapper")
eq(ItemEffects.use, afterReload.wrapperUse,
  "hot reload publishes the refreshed use wrapper")

print(("voxel_run_bridge: %d checks passed"):format(checks))
if love and love.event then love.event.quit(0) end
