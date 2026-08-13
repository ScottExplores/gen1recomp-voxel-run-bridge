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
local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs({
    [prefix .. "manifest.json"] = read("manifest.json"),
    [prefix .. "main.lua"] = read("main.lua"),
  }),
  generation = 1,
})

T.eq(#run.errors, 0, "Scott's Tweaks loads through the API-2 loader")
T.check(run.mod ~= nil, "loader selected Scott's Tweaks")
T.eq(run.mod and run.mod.manifest.id, "voxel_run_bridge",
  "stable updater identity is retained")
T.eq(run.mod and run.mod.manifest.name, "Scott's Tweaks",
  "new display name is loaded")
T.eq(run.mod and run.mod.manifest.version, "0.2.0",
  "loader selected version 0.2.0")

local schema = run.loader.optionSchemas.voxel_run_bridge or {}
local hmOption
for _, row in ipairs(schema) do
  if row.key == "hm_without_badges" then hmOption = row break end
end
T.check(type(hmOption) == "table", "HM option is registered")
T.eq(hmOption and hmOption.default, true, "HM bypass defaults on")

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
