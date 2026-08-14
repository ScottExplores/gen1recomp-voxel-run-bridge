-- Production-loader check against an extracted local Pokemon Final package.
-- No private source is copied into this repository; pass its directory in:
--   luajit tests/cache_compat_full_load.lua <mod-root> <engine-root> <pokemon-final-root> <patched|safe>

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local pokemonRoot = assert(argv[3], "extracted Pokemon Final root required")
local expected = assert(argv[4], "expected result must be patched or safe")
assert(expected == "patched" or expected == "safe",
  "expected result must be patched or safe")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

local function readFrom(root, relative)
  local path = root .. "/" .. relative
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local sourceManifest = readFrom(pokemonRoot, "manifest.json")
local pokemonVersion = assert(sourceManifest:match(
  '"version"%s*:%s*"([^"]+)"'), "Pokemon Final version missing")
local expectedVersion = expected == "patched" and "1.8.1-scott.2"
  or "1.8.1-scott.3"
T.eq(pokemonVersion, expectedVersion,
  "the supplied private package is the intended cache revision")

local scottPrefix = "mods/voxel_run_bridge/"
local pokemonPrefix = "mods/POKEMON_FINAL/"
local pokemonManifest = ([=[{
  "id": "POKEMON_FINAL",
  "name": "Pokemon Final Local Compatibility Fixture",
  "version": "%s",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "priority": 100,
  "dependencies": [],
  "optional_dependencies": [],
  "conflicts": [],
  "games": ["gen1"],
  "permissions": []
}]=]):format(pokemonVersion)

-- This small proxy recreates only Pokemon Final's documented exported-module
-- seam. ScottPrecacheScreen itself is loaded byte-for-byte from the supplied
-- private package at test time.
local pokemonEntry = [[return function(mod)
  local modules = {}
  local V = { mod = mod, path = mod.path }
  local FreeMove = { WALK = 1, BIKE = 2 }
  FreeMove.tick = function(state) return state end

  function V.require(name)
    if name == "FreeMove" then return FreeMove end
    if modules[name] ~= nil then return modules[name] end
    local relative = "lib/" .. name .. ".lua"
    local source = assert(mod:read(relative), relative .. " is missing")
    local chunk = assert(load(source, "@" .. mod.path .. "/" .. relative))
    local value = chunk(V)
    modules[name] = value
    return value
  end

  local Screen = V.require("ScottPrecacheScreen")
  mod.exports.version = mod.version
  mod.exports.lib = V
  mod.exports.testScreen = Screen
  mod.exports.originalStart = Screen._start
end]]

local files = {
  [scottPrefix .. "manifest.json"] = readFrom(sourceRoot, "manifest.json"),
  [scottPrefix .. "main.lua"] = readFrom(sourceRoot, "main.lua"),
  [pokemonPrefix .. "manifest.json"] = pokemonManifest,
  [pokemonPrefix .. "main.lua"] = pokemonEntry,
  [pokemonPrefix .. "lib/ScottPrecacheScreen.lua"] =
    readFrom(pokemonRoot, "lib/ScottPrecacheScreen.lua"),
}

local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs(files),
  generation = 1,
})

T.eq(#run.errors, 0, "local cache compatibility fixture loads")
local orderAt = {}
for index, id in ipairs(run.loader.order or {}) do orderAt[id] = index end
T.check(orderAt.POKEMON_FINAL ~= nil, "Pokemon Final appears in load order")
T.check(orderAt.voxel_run_bridge ~= nil, "Scott's Tweaks appears in load order")
T.check(orderAt.POKEMON_FINAL < orderAt.voxel_run_bridge,
  "Pokemon Final loads before the optional compatibility consumer")

local pokemon = assert(run.loader.exports.POKEMON_FINAL,
  "Pokemon Final exports missing")
local scott = assert(run.loader.exports.voxel_run_bridge,
  "Scott's Tweaks exports missing")
local Screen = assert(pokemon.testScreen, "cache screen export missing")
local compat = assert(scott.pokemonFinalCacheCompat,
  "cache compatibility status missing")
T.eq(compat.version, pokemonVersion, "compatibility status reports package version")

if expected == "patched" then
  T.eq(compat.screen, "patched", "buggy local screen is patched")
  T.check(Screen._start ~= pokemon.originalStart,
    "buggy local start function receives one wrapper")
  T.eq(Screen._scottsTweaksCacheStartHook.owner, "voxel_run_bridge",
    "local screen wrapper is ownership marked")
else
  T.eq(compat.screen, "already_safe", "fixed local screen behavior is detected")
  T.eq(Screen._start, pokemon.originalStart,
    "fixed local start function remains bytecode-identical")
  T.eq(Screen._scottsTweaksCacheStartHook, nil,
    "fixed local screen receives no marker")
end

local beginCalls = 0
local instance = {
  game = {},
  message = "stale",
  precache = {
    beginDisk = function()
      beginCalls = beginCalls + 1
      return true
    end,
    status = function() return { state = "building" } end,
  },
}
Screen._start(instance, false)
T.eq(beginCalls, 1, "local screen start delegates exactly once")
T.eq(instance.message, nil, "successful local cache start has no error message")

T.finish("Scott's Tweaks local Pokemon Final cache compatibility")
