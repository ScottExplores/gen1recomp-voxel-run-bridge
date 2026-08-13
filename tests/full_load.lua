-- ROM-free production-loader smoke.
-- Run from a Gen1Recomp checkout:
--   luajit <mod>/tests/full_load.lua <mod-root> [fixture-root]

local argv = rawget(_G, "arg") or {}
local sourceRoot = argv[1] or os.getenv("SCOTTS_TWEAKS_MOD_ROOT")
local fixtureRoot = argv[2] or os.getenv("SCOTTS_TWEAKS_FIXTURE_ROOT") or "."
local engineRoot = os.getenv("SCOTTS_TWEAKS_ENGINE_ROOT") or fixtureRoot
assert(sourceRoot, "pass the Scott's Tweaks source root")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. fixtureRoot .. "/?.lua;" .. fixtureRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

local function read(relative)
  local path = sourceRoot .. "/" .. relative
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local prefix = "mods/voxel_run_bridge/"
local skyPrefix = "mods/DRAMATIC_SKY_RIDE/"
local skyManifest = [[{
  "id": "DRAMATIC_SKY_RIDE",
  "name": "Dramatic Sky Ride Test Double",
  "version": "0.1.6",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "priority": 900,
  "dependencies": [],
  "optional_dependencies": [],
  "conflicts": [],
  "games": ["gen1"],
  "permissions": []
}]]
local skyEntry = [[return function(mod)
  mod.options:define({
    { key = "require_fly_move", type = "toggle", default = true },
    { key = "badge_checks", type = "toggle", default = true },
    { key = "story_gates", type = "toggle", default = true }
  })
  local function option(key, default)
    local value = mod.options:get(key)
    if value == nil then return default end
    return value
  end
  local function badgeChecksEnabled() return option("badge_checks", true) == true end
  local function startFlight(save)
    if option("require_fly_move", true) == true and not save.knowsFly then
      return false, "FLY REQUIRED"
    end
    if badgeChecksEnabled() and not (save.inventory or {}).THUNDERBADGE then
      return false, "THUNDERBADGE REQUIRED"
    end
    return true, "TAKEOFF"
  end
  mod.exports.flightRules = {
    badgeChecks = badgeChecksEnabled,
    requireFlyMove = function() return option("require_fly_move", true) == true end,
    storyGates = function() return option("story_gates", true) == true end
  }
  mod.exports.testStartFlight = startFlight
end]]
local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs({
    [prefix .. "manifest.json"] = read("manifest.json"),
    [prefix .. "main.lua"] = read("main.lua"),
    [skyPrefix .. "manifest.json"] = skyManifest,
    [skyPrefix .. "main.lua"] = skyEntry,
  }),
  generation = 1,
})

T.eq(#run.errors, 0, "Scott's Tweaks loads through the API-2 loader")
T.check(run.mod ~= nil, "loader selected Scott's Tweaks")
T.eq(run.mod and run.mod.manifest.id, "voxel_run_bridge",
  "stable updater identity is retained")
T.eq(run.mod and run.mod.manifest.name, "Scott's Tweaks",
  "new display name is loaded")
T.eq(run.mod and run.mod.manifest.version, "0.2.1",
  "loader selected version 0.2.1")

local schema = run.loader.optionSchemas.voxel_run_bridge or {}
local hmOption
for _, row in ipairs(schema) do
  if row.key == "hm_without_badges" then hmOption = row break end
end
T.check(type(hmOption) == "table", "HM option is registered")
T.eq(hmOption and hmOption.default, true, "HM bypass defaults on")

local skyOption
for _, row in ipairs(schema) do
  if row.key == "sky_ride_without_badges" then skyOption = row break end
end
T.check(type(skyOption) == "table", "Sky Ride option is registered")
T.eq(skyOption and skyOption.default, true, "Sky Ride bypass defaults on")

local skyOptions = run.loader.modOptions.DRAMATIC_SKY_RIDE
T.check(type(skyOptions) == "table", "Sky Ride live option bucket exists")
T.eq(skyOptions and skyOptions.badge_checks, false,
  "production loader applies DSR's own badge_checks override")
local skyExports = run.loader.exports.DRAMATIC_SKY_RIDE
T.check(type(skyExports) == "table", "Sky Ride exports are feature-detected")
T.eq(skyExports.flightRules.requireFlyMove(), true, "REQUIRE FLY remains on")
T.eq(skyExports.flightRules.storyGates(), true, "STORY GATES remain on")
local flightSave = { inventory = {}, knowsFly = true }
local flew, reason = skyExports.testStartFlight(flightSave)
T.eq(flew, true, "DSR private-style startFlight passes without badge")
T.eq(reason, "TAKEOFF", "DSR does not return THUNDERBADGE error")
T.eq(next(flightSave.inventory), nil, "DSR adapter never grants a badge")

local hooks = run.loader.hooks
local pidgeot = { species = "PIDGEOT", moves = { { id = "FLY" } } }
local save = { inventory = {}, party = { pidgeot } }
local user = hooks:call("fieldmove.eligibility", function() return nil end,
  "FLY", { save = save, data = run.data })
T.eq(user, pidgeot, "production hook returns the real FLY user")
T.eq(next(save.inventory), nil, "production hook does not grant a badge")

local items = {
  { label = "STATS", action = "stats" },
  { label = "SWITCH", action = "switch" },
}
local cutter = { species = "BULBASAUR", moves = { { id = "CUT" } } }
local menu = hooks:call("ui.party.submenu", function(_, list) return list end,
  { data = run.data }, items, cutter,
  { battle = false, overworld = { dark = false, map = { def = {} } } })
T.eq(menu[1] and menu[1].action, "cut",
  "production party hook exposes known CUT before STATS")
T.eq(menu[2] and menu[2].action, "stats", "STATS remains after field moves")

local exported = run.loader.exports.voxel_run_bridge
T.check(type(exported) == "table", "exports are published")
T.eq(exported.status and exported.status.reason, "no_supported_voxel_mod",
  "HM feature loads even when the voxel bridge is idle")
T.eq(type(exported.hmWithoutBadges), "function",
  "live HM option accessor is published")
T.eq(exported.hmWithoutBadges(), true, "live HM option reports enabled")

run.release()
T.finish("Scott's Tweaks full load")
