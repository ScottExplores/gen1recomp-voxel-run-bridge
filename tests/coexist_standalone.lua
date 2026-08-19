-- Scott's Tweaks must still load when the player has the standalone copies of
-- the mods it bundles.
--
-- This is the case that broke: 0.9.0 declared a manifest conflict with
-- BATTLE_ART_VOXEL_FORK, and Loader:_enforceConflicts fails the DECLARING mod.
-- Anyone who had not yet removed the standalone renderer lost Scott's Tweaks
-- outright, so none of the bundled mods, menus or fixes ran at all.
--
--   luajit tests/coexist_standalone.lua <mod-root> <engine-root> <file-list>

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local listPath = assert(argv[3], "file list required")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.modkit")

local prefix = "mods/voxel_run_bridge/"
local artPrefix = "mods/BATTLE_ART_VOXEL_FORK/"

local function slurp(path)
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local files = {}
for relative in io.lines(listPath) do
  if relative ~= "" then
    files[prefix .. relative] = slurp(sourceRoot .. "/" .. relative)
  end
end

-- A minimal stand-in for the separately installed renderer: same id, and it
-- publishes the module table the companion lookups key on.
files[artPrefix .. "manifest.json"] = [[{
  "id": "BATTLE_ART_VOXEL_FORK",
  "name": "Scott's Battle Art Kanto",
  "version": "1.9.3",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "game_version": "0.0.0-dev || >=0.1.69 <2.0.0",
  "priority": 100,
  "games": ["gen1"],
  "permissions": ["engine_internals"]
}]]
files[artPrefix .. "main.lua"] = [[
local mod = ...
mod.exports.version = "1.9.3"
mod.exports.lib = { require = function() return nil end }
]]

local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs(files),
  generation = 1,
})

local fatal = {}
for _, e in ipairs(run.errors) do
  local text = type(e) == "table" and (e.message or e.text or "") or tostring(e)
  if not (text:find("unresolved reference to pokemon", 1, true)
          or text:find("unresolved reference to maps", 1, true)) then
    fatal[#fatal + 1] = text
  end
end
T.eq(#fatal, 0, "no load failure beside the fixture dex gap: "
  .. table.concat(fatal, " | "):sub(1, 300))

T.check(run.mod ~= nil, "Scott's Tweaks still loads beside the standalone renderer")
local exports = run.loader.exports.voxel_run_bridge
T.check(type(exports) == "table", "Scott's Tweaks published its exports")

-- It must defer, not duplicate.
local fused = exports.fusedRenderer
T.check(type(fused) == "table", "fused renderer reported its state")
T.eq(fused and fused.installed, false, "the bundled renderer stands down")
T.eq(fused and fused.reason, "external_voxel", "and says why")

run.release()
T.finish("coexistence with standalone copies")
