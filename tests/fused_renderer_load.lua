-- Production-loader check that the vendored Scott's Battle Art Kanto renderer
-- actually initialises inside Scott's Tweaks.
--
-- The memfs fixtures elsewhere deliberately carry only the Tweaks modules, so
-- installBattleArt stands down there and the renderer is never exercised. This
-- one feeds the loader the real vendored lib/ and data/ tree and asserts the
-- fused renderer reports itself installed.
--
--   luajit tests/fused_renderer_load.lua <mod-root> <engine-root> <file-list>

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local listPath = assert(argv[3], "file list required")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.modkit")

local prefix = "mods/voxel_run_bridge/"

local function slurp(path)
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local modFiles = {}
local count = 0
for relative in io.lines(listPath) do
  if relative ~= "" then
    modFiles[prefix .. relative] = slurp(sourceRoot .. "/" .. relative)
    count = count + 1
  end
end
T.check(count > 80, "vendored code tree was staged (" .. count .. " files)")
T.check(modFiles[prefix .. "battle_art_main.lua"] ~= nil, "renderer entry staged")

local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs(modFiles),
  generation = 1,
})

-- All Pokemon Catchable 151 repatches real Kanto encounter tables, and the
-- modkit fixture only defines synthetic species (FIXMON_A/B/C) and maps, so
-- every one of its species references reads as dangling here. That is a gap in
-- the harness, not in the mod: assert the shape of the errors rather than
-- hiding them, so any other class of load failure still fails this test.
local dexGap, other = 0, {}
for _, e in ipairs(run.errors) do
  local text = type(e) == "table" and (e.message or e.text or "") or tostring(e)
  if text:find("unresolved reference to pokemon", 1, true)
     or text:find("unresolved reference to maps", 1, true) then
    dexGap = dexGap + 1
  else
    other[#other + 1] = text
  end
end
T.eq(#other, 0, "no load errors beyond the fixture dex gap: " .. table.concat(other, " | "):sub(1, 300))
T.check(dexGap > 0, "fixture dex gap accounted for (" .. dexGap .. " references)")
T.check(run.mod ~= nil, "loader selected the fused mod")
T.eq(run.mod and run.mod.manifest.id, "voxel_run_bridge", "updater identity retained")

local exports = run.loader.exports.voxel_run_bridge
T.check(type(exports) == "table", "fused mod publishes exports")
T.check(type(exports.fusedRenderer) == "table", "fused renderer reported its state")
T.eq(exports.fusedRenderer and exports.fusedRenderer.installed, true,
  "vendored Battle Art renderer installed")
T.check(type(exports.lib) == "table", "renderer published its module table")
T.check(type(exports.lib and exports.lib.require) == "function",
  "renderer module loader is available to companion adapters")
T.eq(exports.version, "1.9.3", "vendored renderer reports its own version")

local vend = exports.vendored
T.check(type(vend) == "table", "vendor host reported status")
local loadedSet = {}
for _, id in ipairs(vend and vend.loaded or {}) do loadedSet[id] = true end
for _, id in ipairs({
  "overworld_wild_spawns", "free_fly", "choose_lead",
  "all_pokemon_catchable_151_mod", "unique_menu_icons", "Dynamic_Scaling",
  "running_shoes", "crystal_animated_sprites_with_shiny_visuals",
}) do
  T.check(loadedSet[id], "bundled mod loaded: " .. id
    .. (vend and vend.failed and vend.failed[id] and (" -- " .. tostring(vend.failed[id])) or ""))
end

run.release()
T.finish("fused renderer load")
