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

package.preload["src.mods.Runtime"] = function() return Runtime end
package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.Map"] = function() return Map end
package.preload["src.world.FieldDefaults"] = function() return FieldDefaults end
package.preload["src.core.Strings"] = function()
  return function(value) return value end
end

local entry = assert(loadfile("main.lua"))()

local function fixture(opts)
  opts = opts or {}
  local seen = {}
  local hooks = {}
  local eventListeners = {}
  local optionSchema
  local FreeMove = { WALK = 1, BIKE = 2 }
  local originalTick
  originalTick = function(state)
    seen.walk, seen.bike = FreeMove.WALK, FreeMove.BIKE
    if opts.throwTick then error("tick exploded") end
    return "tick-result", 42
  end
  FreeMove.tick = originalTick

  local lib = {
    _runningShoesHook = opts.runningShoesHook,
    _voxelRunBridgeHook = opts.bridgeHook,
    require = function(name)
      eq(name, "FreeMove", "requested voxel module")
      if opts.requireError then error("provider loader failed") end
      return FreeMove
    end,
  }
  local exportedLib = opts.malformedLib and 42 or lib
  local voxel = { exports = { lib = exportedLib } }
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
    if key == "sky_ride_without_badges"
        and opts.skyRideWithoutBadges ~= nil then
      return opts.skyRideWithoutBadges
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

  local loader = { modOptions = {} }
  if opts.skyRideStoredBadgeChecks ~= nil then
    loader.modOptions.DRAMATIC_SKY_RIDE = {
      badge_checks = opts.skyRideStoredBadgeChecks,
    }
  end
  Game.mods = loader

  local skyRules = {
    badgeChecks = function()
      local bucket = loader.modOptions.DRAMATIC_SKY_RIDE
      if bucket and bucket.badge_checks ~= nil then
        return bucket.badge_checks
      end
      return true
    end,
    requireFlyMove = function() return true end,
    storyGates = function() return true end,
  }
  local skyRide = {
    version = opts.skyRideVersion or "0.1.6",
    exports = opts.skyRideMalformed and {} or { flightRules = skyRules },
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
    log = {
      info = function(_, message) logs[#logs + 1] = message end,
      warn = function(_, message) logs[#logs + 1] = message end,
    },
    find = function(id)
      if opts.skyRide and id == "DRAMATIC_SKY_RIDE" then return skyRide end
      if not opts.noVoxel and id == (opts.voxelId or "DRAMATIC_SHAPE") then
        return voxel
      end
    end,
  }

  entry(mod)
  return {
    mod = mod,
    lib = lib,
    FreeMove = FreeMove,
    originalTick = originalTick,
    seen = seen,
    logs = logs,
    hooks = hooks,
    optionSchema = function() return optionSchema end,
    events = events,
    loader = loader,
    skyRules = skyRules,
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
eq(manifest:match('"version"%s*:%s*"([^"]+)"'), "0.2.1",
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

local skyOption
for _, row in ipairs(schema or {}) do
  if row.key == "sky_ride_without_badges" then skyOption = row end
end
eq(type(skyOption), "table", "Sky Ride option row exists")
eq(skyOption and skyOption.type, "toggle", "Sky Ride option type")
eq(skyOption and skyOption.default, true, "Sky Ride option default")

-- Dramatic Sky Ride's private startFlight gate reads badge_checks directly
-- from its own mod.options API. Scott's runtime overlay changes that exact
-- answer without manufacturing the badge or changing other DSR rules.
local sky = fixture({
  noVoxel = true,
  skyRide = true,
  skyRideStoredBadgeChecks = true,
})
eq(sky.skyRules.badgeChecks(), false, "Sky Ride badge answer is overridden")
eq(sky.skyRules.requireFlyMove(), true, "REQUIRE FLY remains enabled")
eq(sky.skyRules.storyGates(), true, "STORY GATES remain enabled")
local flightSave = { inventory = {} }
local function privateStartFlightGate(save)
  if sky.skyRules.badgeChecks()
      and not save.inventory.THUNDERBADGE then
    return false, "THUNDERBADGE REQUIRED"
  end
  return true, "TAKEOFF"
end
local tookOff, takeoffReason = privateStartFlightGate(flightSave)
eq(tookOff, true, "private-style startFlight gate permits takeoff")
eq(takeoffReason, "TAKEOFF", "takeoff does not show badge error")
eq(next(flightSave.inventory), nil, "Sky Ride bypass does not grant a badge")
local skyActive, skyReason, skyVersion = sky.mod.exports.skyRideBadgeBypass()
eq(skyActive, true, "Sky Ride adapter reports active")
eq(skyReason, "badge_checks_runtime_override", "Sky Ride adapter reason")
eq(skyVersion, "0.1.6", "Sky Ride adapter reports detected version")

-- A DSR settings change remains the player's stored preference. It is held
-- false only while Scott's override is on, then restored exactly when off.
sky.loader.modOptions.DRAMATIC_SKY_RIDE.badge_checks = true
sky.events:emit("mod.options_changed", {
  mod = "DRAMATIC_SKY_RIDE", key = "badge_checks", value = true,
})
eq(sky.loader.modOptions.DRAMATIC_SKY_RIDE.badge_checks, false,
  "DSR badge setting stays overridden live")
sky.events:emit("mod.options_changed", {
  mod = "voxel_run_bridge", key = "sky_ride_without_badges", value = false,
})
eq(sky.loader.modOptions.DRAMATIC_SKY_RIDE.badge_checks, true,
  "turning Scott override off restores DSR preference")

local skyDisabled = fixture({
  noVoxel = true,
  skyRide = true,
  skyRideStoredBadgeChecks = true,
  skyRideWithoutBadges = false,
})
eq(skyDisabled.skyRules.badgeChecks(), true,
  "disabled Scott option leaves DSR badge check intact")

local noSky = fixture({ noVoxel = true })
eq(noSky.loader.modOptions.DRAMATIC_SKY_RIDE, nil,
  "missing DSR leaves its option namespace untouched")

local unsupportedSky = fixture({
  noVoxel = true,
  skyRide = true,
  skyRideMalformed = true,
  skyRideStoredBadgeChecks = true,
})
eq(unsupportedSky.loader.modOptions.DRAMATIC_SKY_RIDE.badge_checks, true,
  "unsupported DSR leaves its badge setting untouched")
local unsupportedActive, unsupportedReason =
  unsupportedSky.mod.exports.skyRideBadgeBypass()
eq(unsupportedActive, false, "unsupported DSR adapter stays inactive")
eq(unsupportedReason, "unsupported_dramatic_sky_ride",
  "unsupported DSR reports its reason")

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

print(("voxel_run_bridge: %d checks passed"):format(checks))
if love and love.event then love.event.quit(0) end
