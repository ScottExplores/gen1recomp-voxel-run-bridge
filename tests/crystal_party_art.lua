-- Real-loader regression for Crystal party -> Summary art in the consolidated
-- Scott's Tweaks bundle.
--
-- The runner stages the shipped mod code and Bulbasaur's normal/shiny Crystal
-- frame folders in the Loader's exact-case memfs.  This exercises the actual
-- VendorHost, Crystal provider, pokemon.sprite hook, Gen 1 SummaryMenu wrapper,
-- and BattlePics authored-alpha provider rather than a copied helper.
--
--   luajit tests/crystal_party_art.lua <mod-root> <engine-root> <file-list>

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")
local listPath = assert(argv[3], "staged file list required")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.modkit")

local PREFIX = "mods/voxel_run_bridge/"
local NORMAL_REL = "vendor/crystal/assets/front/normal/1/001.png"
local SHINY_REL = "vendor/crystal/assets/front/shiny/1/001.png"

local function slurp(path)
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

local modFiles, staged = {}, 0
for relative in io.lines(listPath) do
  if relative ~= "" then
    modFiles[PREFIX .. relative] = slurp(sourceRoot .. "/" .. relative)
    staged = staged + 1
  end
end
T.check(staged > 100, "real consolidated code tree was staged")

local normalBytes = modFiles[PREFIX .. NORMAL_REL]
local shinyBytes = modFiles[PREFIX .. SHINY_REL]
T.check(type(normalBytes) == "string", "normal Crystal frame staged at exact case")
T.check(type(shinyBytes) == "string", "shiny Crystal frame staged at exact case")
T.eq(modFiles[PREFIX .. NORMAL_REL:gsub("/normal/", "/Normal/")], nil,
  "case-mismatched normal asset is not present in Loader memfs")
T.eq(modFiles[PREFIX .. SHINY_REL:gsub("/shiny/", "/Shiny/")], nil,
  "case-mismatched shiny asset is not present in Loader memfs")
T.neq(normalBytes, shinyBytes, "normal and shiny frame bytes are distinct")

local function be32(bytes, at)
  local a, b, c, d = bytes:byte(at, at + 3)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Read only PNG structure.  The authored art is indexed PNG: its tRNS chunk
-- makes palette entry zero fully transparent.  Combined with the runtime
-- identity checks below, this proves that alpha-bearing source is what reaches
-- Summary and that BattlePics does not seal those transparent limb gaps white.
local function pngInfo(bytes)
  if type(bytes) ~= "string" or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" then
    return nil
  end
  local info, at = {}, 9
  while at + 11 <= #bytes do
    local length = be32(bytes, at)
    local kind = bytes:sub(at + 4, at + 7)
    local body = bytes:sub(at + 8, at + 7 + length)
    if kind == "IHDR" then
      info.width = be32(body, 1)
      info.height = be32(body, 5)
      info.bitDepth = body:byte(9)
      info.colorType = body:byte(10)
    elseif kind == "tRNS" then
      info.transparency = body
    elseif kind == "IDAT" then
      info.hasImageData = #body > 0
    elseif kind == "IEND" then
      break
    end
    at = at + length + 12
  end
  return info
end

for label, bytes in pairs({ normal = normalBytes, shiny = shinyBytes }) do
  local info = pngInfo(bytes)
  T.check(type(info) == "table", label .. " frame is a PNG")
  T.eq(info and info.width, 56, label .. " frame has authored logical width")
  T.eq(info and info.height, 56, label .. " frame has authored logical height")
  T.eq(info and info.colorType, 3, label .. " frame keeps indexed Crystal art")
  T.eq(info and info.transparency and #info.transparency, 1,
    label .. " frame has one authored transparent palette entry")
  T.eq(info and info.transparency and info.transparency:byte(1), 0,
    label .. " frame declares a fully transparent palette entry")
  T.check(info and info.hasImageData == true, label .. " frame carries pixel data")
end

local data = require("tests.modkit.fixtures").fresh()
-- The ROM-free fixture deliberately names its three species FIXMON_A/B/C.
-- Add one valid Gen 1 record before Loader discovery so Crystal's real content
-- patch and Summary path can address a mapped species without needing a ROM.
data.pokemon.BULBASAUR = {
  id = "BULBASAUR", index = 153, dex = 1, name = "BULBASAUR",
  types = { "GRASS" },
  baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, special = 65 },
  catchRate = 45, baseExp = 64, level1Moves = { "FIX_TACKLE" },
  growthRate = "MEDIUM_SLOW", tmhm = {}, learnset = {}, evolutions = {},
  spriteFront = "tests/fixture_data/assets/fixmon_a_front.png",
  spriteBack = "tests/fixture_data/assets/fixmon_a_back.png",
  frontSize = 5,
  dexEntry = { kind = "SEED", heightFt = 2, heightIn = 4, weight = 150,
    text = "A seed Pokemon." },
}

-- The fixture intentionally produces hundreds of missing-Kanto-reference
-- diagnostics.  They are asserted immediately below; keep the focused
-- regression's command output readable instead of printing each one twice.
local Logger = require("src.core.Logger")
local loggerInfo, loggerWarn, loggerError = Logger.info, Logger.warn, Logger.error
Logger.info, Logger.warn, Logger.error = function() end, function() end, function() end
local run = T.sdk.loadMod("mods/voxel_run_bridge", {
  data = data,
  fs = T.sdk.memfs(modFiles),
  generation = 1,
})
Logger.info, Logger.warn, Logger.error = loggerInfo, loggerWarn, loggerError

-- All Pokemon Catchable intentionally names the real Kanto maps/species that
-- the tiny SDK fixture omits.  Account for only that known fixture limitation.
local dexGap, other = 0, {}
for _, err in ipairs(run.errors) do
  local text = type(err) == "table" and (err.message or err.text or "")
    or tostring(err)
  if text:find("unresolved reference to pokemon", 1, true)
      or text:find("unresolved reference to maps", 1, true) then
    dexGap = dexGap + 1
  else
    other[#other + 1] = text
  end
end
T.eq(#other, 0,
  "no fused load errors beyond the fixture dex gap: "
    .. table.concat(other, " | "):sub(1, 300))
T.check(dexGap > 0, "fixture-only Kanto reference gap was accounted for")
T.eq(run.mod and run.mod.manifest.id, "voxel_run_bridge",
  "real Loader selected the consolidated mod")

local exports = run.loader.exports.voxel_run_bridge
local crystalHandle = exports and exports.vendorHost and exports.vendorHost.loaded
  and exports.vendorHost.loaded.crystal_animated_sprites_with_shiny_visuals
local crystal = crystalHandle and crystalHandle.exports
T.check(type(crystal) == "table", "real VendorHost loaded the Crystal provider")
T.eq(crystal and crystal.dexFor("BULBASAUR"), 1,
  "real Crystal species map resolves the party species")
T.check(crystal and crystal.hasCrystalArt(1),
  "real provider sees exact-case bundled Bulbasaur art through Loader memfs")

-- ADVANCED is Crystal's true-color mode.  Other Gen 1 color modes purposely
-- use one grayscale presentation, in which a shiny would be visually
-- indistinguishable; this mode is the one that must select the authored shiny
-- folder and preserve its colors and alpha.
local PaletteFX = require("src.render.PaletteFX")
local previousMode = PaletteFX.mode
PaletteFX.mode = "redpp"
require("src.core.Game").mods = run.loader

local function mon(dvs)
  return {
    species = "BULBASAUR", nickname = "BULBASAUR", level = 10, hp = 30,
    stats = { hp = 30, attack = 20, defense = 20, speed = 20, special = 20 },
    dvs = dvs, statExp = {}, exp = 1000, moves = {}, ot = "RED", otId = 1,
  }
end

local normalMon = mon({ attack = 0, defense = 0, speed = 0, special = 0 })
local shinyMon = mon({ attack = 10, defense = 10, speed = 10, special = 10 })
local Stats = require("src.pokemon.Stats")
T.eq(Stats.isShiny(normalMon.dvs), false,
  "normal party member is non-shiny by the Gen 1 DV rule")
T.eq(Stats.isShiny(shinyMon.dvs), true,
  "shiny party member is shiny by the Gen 1 DV rule")
local idleInput = { wasPressed = function() return false end }
local game = {
  data = run.data,
  input = idleInput,
  save = { player = { name = "RED", id = 1 }, party = { normalMon, shinyMon } },
  logicSpeed = function() return 1 end,
}

local SummaryMenu = require("src.ui.SummaryMenu")
T.check(SummaryMenu.__crystalAnimHook == true,
  "real fused Crystal provider wrapped Gen 1 SummaryMenu")
local Sprites = require("src.pokemon.Sprites")
local normalHookPath, normalTrueColor = Sprites.path(
  game.data, normalMon.species, "front", { mon = normalMon, kind = "summary" })
local shinyHookPath, shinyTrueColor = Sprites.path(
  game.data, shinyMon.species, "front", { mon = shinyMon, kind = "summary" })
T.eq(normalHookPath, PREFIX .. NORMAL_REL,
  "real pokemon.sprite hook resolves the normal Summary asset")
T.eq(shinyHookPath, PREFIX .. SHINY_REL,
  "real pokemon.sprite hook resolves the shiny Summary asset")
T.eq(normalTrueColor, true, "normal Summary hook reports authored true color")
T.eq(shinyTrueColor, true, "shiny Summary hook reports authored true color")
local normalSummary = SummaryMenu.new(game, game.save.party[1])
local shinySummary = SummaryMenu.new(game, game.save.party[2])

local normalPrefix = PREFIX .. "vendor/crystal/assets/front/normal/1/"
local shinyPrefix = PREFIX .. "vendor/crystal/assets/front/shiny/1/"
T.eq(normalSummary and normalSummary.sprite and normalSummary.sprite.path,
  normalPrefix .. "001.png",
  "normal party member opens exact-case bundled Crystal Summary frame")
T.eq(shinySummary and shinySummary.sprite and shinySummary.sprite.path,
  shinyPrefix .. "001.png",
  "shiny party member opens exact-case bundled Crystal Summary frame")
T.neq(normalSummary and normalSummary.sprite and normalSummary.sprite.path,
  shinySummary and shinySummary.sprite and shinySummary.sprite.path,
  "normal and shiny Summary art resolve to different variant folders")
T.eq(normalSummary and normalSummary.__crystalWhich, "normal",
  "normal party member records the normal Crystal variant")
T.eq(shinySummary and shinySummary.__crystalWhich, "shiny",
  "Gen 1 shiny DVs record the shiny Crystal variant")

for label, summary in pairs({ normal = normalSummary, shiny = shinySummary }) do
  local anim = summary and summary.__crystalAnim
  local expectedPrefix = label == "normal" and normalPrefix or shinyPrefix
  T.check(type(anim) == "table" and #anim.images >= 2,
    label .. " Summary receives multiple real Crystal animation frames")
  T.eq(anim and anim.images[2] and anim.images[2].path,
    expectedPrefix .. "002.png", label .. " second frame keeps exact-case path")
  T.eq(summary and summary.spriteTrueColor, true,
    label .. " Summary keeps authored true-color presentation")
  T.eq(summary and summary.sprite and summary.sprite.minFilter, "nearest",
    label .. " Summary frame uses nearest minification")
  T.eq(summary and summary.sprite and summary.sprite.magFilter, "nearest",
    label .. " Summary frame uses nearest magnification")
  if anim and anim.durations and anim.durations[1] then
    summary:update((anim.durations[1] + 1) / 1000)
    T.eq(summary.sprite, anim.images[2],
      label .. " real Summary update advances to the second Crystal frame")
  end
end

local BattlePics = exports and exports.lib and exports.lib.require("BattlePics")
T.check(type(BattlePics) == "table", "real fused BattlePics module is available")
T.check(crystal and crystal.refreshVoxelPaper(),
  "real Crystal provider registered its authored-alpha predicate")

local originalNewCanvas = love.graphics.newCanvas
local canvasCalls = {}
love.graphics.newCanvas = function(w, h, opts)
  canvasCalls[#canvasCalls + 1] = { w = w, h = h, opts = opts }
  return originalNewCanvas(w, h, opts)
end

for label, summary in pairs({ normal = normalSummary, shiny = shinySummary }) do
  local image = summary and summary.sprite
  T.check(crystal and crystal.isCrystalImage(image),
    label .. " Summary frame remains owned by the real Crystal provider")
  T.check(BattlePics and BattlePics.preservesAuthoredTransparency(image),
    label .. " Summary frame is recognized as authored-alpha art")
  T.eq(BattlePics and BattlePics.filled(image, true), image,
    label .. " authored limb gaps bypass the white-fill recovery path")
end
T.eq(#canvasCalls, 0,
  "authored Crystal Summary frames never enter a readback/fill canvas")

-- If a non-Crystal image does need the renderer's paper recovery, its
-- readback canvas must remain logical-pixel sized on Android/high-DPI devices.
local ordinary = love.graphics.newImage("ordinary-rom-front.png")
if BattlePics then BattlePics.filled(ordinary, true) end
T.eq(#canvasCalls, 1, "ordinary ROM art still reaches paper recovery")
T.eq(canvasCalls[1] and canvasCalls[1].opts and canvasCalls[1].opts.dpiscale, 1,
  "paper recovery forces an Android-safe dpiscale=1 canvas")
love.graphics.newCanvas = originalNewCanvas

PaletteFX.mode = previousMode
run.release()
T.finish("crystal party art")
