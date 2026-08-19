-- Scott's private Kanto presentation layer for the fused Battle Art build.
--
-- The former compatibility mod had to discover another mod, write payloads
-- into its directory, and ask for a restart.  This build owns those payloads,
-- so this module contains only the live pieces: one config bridge, the option
-- rows, the Lavender veil, the jump button, panorama selection and a debug
-- readout.  It never edits an installed mod and never touches another mod's
-- files.

local V = ...
local mod = V.mod

local ScottKanto = {}

-- These rows are appended to Battle Art's existing schema before its one
-- and only options:define call.  "shadows" deliberately is not repeated:
-- Dramatic Shape already owns that key, and the Kanto geometry reads the same
-- value through config() below.  One SHADOWS switch therefore governs the sun
-- pass, ceiling contact shadows and foliage shadows without duplicate keys.
local ROWS = {
  { key = "ceiling", label = "CEILING", type = "toggle", default = true },
  { key = "headroom", label = "HEADROOM", type = "choice", default = "AIRY",
    choices = { { "AIRY", "AIRY" }, { "MID", "MID" }, { "SNUG", "SNUG" } } },
  { key = "cutaway", label = "SIMS CUTAWAY", type = "toggle", default = true },
  { key = "rails", label = "RAIL AND SKIRTING", type = "toggle", default = true },
  { key = "spill", label = "DOORWAY LIGHT", type = "toggle", default = true },
  { key = "fittings", label = "CEILING LAMPS", type = "toggle", default = true },
  { key = "rock", label = "CAVE ROCK", type = "toggle", default = true },
  { key = "apron", label = "WORLD APRON", type = "toggle", default = true },
  { key = "talltrees", label = "TALL TREES", type = "toggle", default = true },
  { key = "peaks", label = "MOUNTAIN PEAKS", type = "toggle", default = true },
  { key = "fastchunks", label = "FAST CHUNKS", type = "toggle", default = true },
  { key = "headbob", label = "HEAD BOB", type = "toggle", default = false },
  { key = "jumpkey", label = "JUMP KEY", type = "choice", default = "space",
    choices = { { "SPACE", "space" }, { "J", "j" },
                { "L-CTRL", "lctrl" }, { "OFF", "off" } } },
  { key = "jumppad", label = "PAD BUTTON", type = "choice", default = "y",
    choices = { { "Y", "y" }, { "X", "x" }, { "OFF", "off" } } },
  { key = "pools", label = "CAVE POOLS", type = "toggle", default = true },
  { key = "sconces", label = "CAVE TORCHES", type = "toggle", default = true },
  { key = "bats", label = "BATS", type = "toggle", default = true },
  { key = "third", label = "3RD CEILING", type = "choice", default = "CUTAWAY",
    choices = { { "NONE", "NONE" }, { "CUTAWAY", "CUTAWAY" },
                { "FULL", "FULL" } } },
  { key = "backdrop", label = "HORIZON", type = "toggle", default = true },
  { key = "horizonart", label = "HORIZON ART", type = "choice", default = "VALLEY",
    choices = { { "KANTO", "KANTO" }, { "FUJI", "FUJI" },
                { "VALLEY", "VALLEY" }, { "CITY", "CITY" } } },
  { key = "grass", label = "GRASS HEIGHT", type = "choice", default = "SUBTLE",
    choices = { { "OFF", "OFF" }, { "SUBTLE", "SUBTLE" },
                { "WILD", "WILD" } } },
  { key = "particles", label = "PARTICLES", type = "toggle", default = true },
  { key = "ambience", label = "AMBIENT SOUND", type = "choice", default = "MID",
    choices = { { "OFF", "OFF" }, { "LOW", "LOW" }, { "MID", "MID" },
                { "HIGH", "HIGH" } } },
  { key = "grasssfx", label = "GRASS STEPS", type = "toggle", default = true },
  { key = "stepsfx", label = "FOOTSTEPS", type = "toggle", default = true },
  { key = "doorsfx", label = "DOOR SOUND", type = "toggle", default = true },
  { key = "windows", label = "WINDOWS", type = "toggle", default = true },
  { key = "ceildetail", label = "CEILING DETAIL", type = "toggle", default = true },
  { key = "fpfov", label = "FP FOV", type = "choice", default = "NORMAL",
    choices = { { "NARROW", "NARROW" }, { "NORMAL", "NORMAL" },
                { "WIDE", "WIDE" }, { "ULTRA", "ULTRA" } } },
  { key = "bouldertrees", label = "BOULDER TREES", type = "toggle", default = false },
  { key = "dof", label = "DEPTH BLUR", type = "choice", default = "OFF",
    choices = { { "OFF", "OFF" }, { "1", "1" }, { "2", "2" }, { "3", "3" } } },
  { key = "rain", label = "RAIN", type = "choice", default = "SOMETIMES",
    choices = { { "OFF", "OFF" }, { "SOMETIMES", "SOMETIMES" },
                { "ALWAYS", "ALWAYS" } } },
  { key = "umbrellas", label = "NPC UMBRELLAS", type = "toggle", default = true },
  { key = "puddles", label = "PUDDLES", type = "toggle", default = true },
  { key = "lightning", label = "LIGHTNING", type = "toggle", default = true },
  { key = "lights", label = "LAMPLIGHT", type = "toggle", default = true },
  { key = "shafts", label = "SUN SHAFTS", type = "toggle", default = true },
  { key = "canopy", label = "FOREST CANOPY", type = "toggle", default = true },
  { key = "vines", label = "HANGING VINES", type = "toggle", default = true },
  { key = "fog", label = "LAVENDER FOG", type = "toggle", default = true },
  { key = "doorstep", label = "DOORWAY STEP", type = "toggle", default = true },
  { key = "clouds", label = "CLOUDS", type = "toggle", default = true },
  { key = "stars", label = "NIGHT SKY", type = "toggle", default = true },
  { key = "birds", label = "BIRDS", type = "toggle", default = true },
  { key = "aircraft", label = "AIRCRAFT", type = "toggle", default = true },
  { key = "rainbows", label = "RAINBOWS", type = "toggle", default = true },
  { key = "insects", label = "INSECTS", type = "toggle", default = true },
  { key = "groundflock", label = "GROUND FLOCK", type = "toggle", default = true },
  { key = "wind", label = "WIND", type = "choice", default = "BREEZE",
    choices = { { "OFF", "OFF" }, { "BREEZE", "BREEZE" },
                { "GUSTY", "GUSTY" } } },
  { key = "jump", label = "JUMP FEEL", type = "choice", default = "SUBTLE",
    choices = { { "OFF", "OFF" }, { "SUBTLE", "SUBTLE" }, { "BIG", "BIG" } } },
  { key = "debug", label = "DEBUG HUD", type = "toggle", default = false },
}

function ScottKanto.optionRows()
  return ROWS
end

local function opt(key, fallback)
  local ok, value = pcall(function() return mod.options:get(key) end)
  if ok and value ~= nil then return value end
  return fallback
end

local HEADROOM = { AIRY = 32, MID = 24, SNUG = 16 }

function ScottKanto.config()
  return {
    ceiling = opt("ceiling", true) ~= false,
    headroom = HEADROOM[opt("headroom", "AIRY")] or 32,
    cutaway = opt("cutaway", true) ~= false,
    -- Shared with Battle Art's native shadowQuality row (no duplicate schema).
    shadows = opt("shadowQuality", "high") ~= "off",
    rails = opt("rails", true) ~= false,
    spill = opt("spill", true) ~= false,
    fittings = opt("fittings", true) ~= false,
    rock = opt("rock", true) ~= false,
    backs = false,
    apron = opt("apron", true) ~= false,
    talltrees = opt("talltrees", true) ~= false,
    peaks = opt("peaks", true) ~= false,
    fastchunks = opt("fastchunks", true) ~= false,
    headbob = opt("headbob", false) == true,
    pools = opt("pools", true) ~= false,
    sconces = opt("sconces", true) ~= false,
    bats = opt("bats", true) ~= false,
    third = opt("third", "CUTAWAY"),
    backdrop = opt("backdrop", true) ~= false,
    horizonart = opt("horizonart", "VALLEY"),
    jump = opt("jump", "SUBTLE"),
    grass = opt("grass", "SUBTLE"),
    particles = opt("particles", true) ~= false,
    ambience = opt("ambience", "MID"),
    grasssfx = opt("grasssfx", true) ~= false,
    stepsfx = opt("stepsfx", true) ~= false,
    doorsfx = opt("doorsfx", true) ~= false,
    windows = opt("windows", true) ~= false,
    ceildetail = opt("ceildetail", true) ~= false,
    fpfov = opt("fpfov", "NORMAL"),
    dof = opt("dof", "OFF"),
    bouldertrees = opt("bouldertrees", false) == true,
    rain = opt("rain", "SOMETIMES"),
    umbrellas = opt("umbrellas", true) ~= false,
    puddles = opt("puddles", true) ~= false,
    lightning = opt("lightning", true) ~= false,
    lights = opt("lights", true) ~= false,
    shafts = opt("shafts", true) ~= false,
    canopy = opt("canopy", true) ~= false,
    vines = opt("vines", true) ~= false,
    fog = opt("fog", true) ~= false,
    doorstep = opt("doorstep", true) ~= false,
    clouds = opt("clouds", true) ~= false,
    stars = opt("stars", true) ~= false,
    birds = opt("birds", true) ~= false,
    aircraft = opt("aircraft", true) ~= false,
    rainbows = opt("rainbows", true) ~= false,
    insects = opt("insects", true) ~= false,
    groundflock = opt("groundflock", true) ~= false,
    wind = opt("wind", "BREEZE"),
  }
end

local ART = {
  KANTO = "backdrop.png", FUJI = "backdrop2.png",
  VALLEY = "backdrop3.png", CITY = "backdrop4.png",
}

local panoramaChoice, panoramaCachedPath = nil, nil
local function panoramaPath(force)
  local choice = opt("horizonart", "VALLEY")
  if not force and choice == panoramaChoice and panoramaCachedPath then
    return panoramaCachedPath
  end
  local name = ART[choice] or "backdrop3.png"
  local ok, blob = pcall(mod.read, mod, "lib/" .. name)
  if not (ok and blob) then name = "backdrop.png" end
  panoramaChoice = choice
  panoramaCachedPath = V.path .. "/lib/" .. name
  return panoramaCachedPath
end

function ScottKanto.refreshPaths(force)
  _G.__ds_patch_base = V.path
  _G.__ds_backdrop_path = panoramaPath(force)
  _G.__ds_posters_dir = V.path .. "/lib/"
end

-- Called before any renderer modules are required.  ChunkMesher and the Kanto
-- payloads can therefore see FAST CHUNKS and their other values during their
-- own module initialisation, just as they did when a lower-priority companion
-- loaded first.
function ScottKanto.bootstrap()
  _G.__ds_ceiling_config = ScottKanto.config
  ScottKanto.refreshPaths()
  mod.exports.config = ScottKanto.config
  mod.exports.scottKanto = true
end

local function installLavenderVeil()
  local veilScratch = nil
  mod.content.render_pipelines:register("lavveil", {
    label = "LAV VEIL",
    levels = { "OFF", "AUTO" },
    priority = 9,
    update = function() end,
    worldPresent = function(canvas)
      local env = tonumber(rawget(_G, "__ds_lavfog")) or 0
      if env <= 0.01 or not canvas then return canvas end
      local pushed = false
      local ok, out = pcall(function()
        local w, h = canvas:getDimensions()
        if not veilScratch or veilScratch:getWidth() ~= w
            or veilScratch:getHeight() ~= h then
          veilScratch = love.graphics.newCanvas(w, h)
        end
        love.graphics.push("all")
        pushed = true
        love.graphics.setCanvas(veilScratch)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas)
        local alpha = 0.34 * env
        for band = 0, 5 do
          local y = h * band / 6
          love.graphics.setColor(0.78, 0.76, 0.84,
                                 alpha * (1 - band / 6.5))
          love.graphics.rectangle("fill", 0, y, w, h / 6 + 1)
        end
        return veilScratch
      end)
      -- A failed canvas allocation or draw must not strand the game's render
      -- target, colour or blend state inside this optional effect.
      if pushed then pcall(function() love.graphics.pop() end) end
      return (ok and out) or canvas
    end,
    invalidate = function() veilScratch = nil end,
  })
end

local function pipelineReport()
  local ok, out = pcall(function()
    local Pipelines = require("src.render.Pipelines")
    local bits = {}
    for _, entry in ipairs(Pipelines.list() or {}) do
      local id = entry.id
      local level = Pipelines.level and Pipelines.level(id) or -1
      local eligible = Pipelines.eligible and Pipelines.eligible(id)
      bits[#bits + 1] = ("%s=%s"):format(
        id, eligible and "ok" or (level > 0 and "DEAD?" or "off"))
    end
    return table.concat(bits, " ")
  end)
  return (ok and out ~= "" and out) or "no pipelines visible"
end

local installed = false
function ScottKanto.install()
  if installed then return end
  installed = true

  -- Registration errors should not take the voxel renderer with them on an
  -- older engine that lacks worldPresent; every other Kanto feature remains.
  pcall(installLavenderVeil)

  pcall(function()
    local installJumpButton = V.require("ScottJumpButton")
    if type(installJumpButton) == "function" then installJumpButton(mod) end
  end)

  mod.events:on("mod.options_changed", function(payload)
    if payload and payload.mod == mod.id and payload.key == "horizonart" then
      ScottKanto.refreshPaths(true)
    end
  end)

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    -- Cheap on unchanged frames: panoramaPath caches the choice and path and
    -- does not read the (hundreds-of-KB) PNG again.
    ScottKanto.refreshPaths()
    next(game, viewport)
    if opt("debug", false) ~= true then return end
    pcall(function()
      local lines = {
        "FUSED: Scott's Battle Art Kanto 1.9.2-scott-kfp.7",
        "CEIL: " .. (rawget(_G, "__ds_ceiling_status") or "not loaded"),
        "HRZN: " .. (rawget(_G, "__ds_backdrop_status") or "not loaded"),
        "SKY:  " .. (rawget(_G, "__ds_sky_status") or "not loaded"),
        "FLOR: " .. (rawget(_G, "__ds_flora_status") or "not loaded"),
        "PIPE: " .. pipelineReport(),
      }
      local x = (viewport and viewport.gameX or 0) + 8
      local y = (viewport and viewport.gameY or 0) + 8
      local width, font = 0, love.graphics.getFont()
      for _, line in ipairs(lines) do
        width = math.max(width, font and font:getWidth(line) or #line * 8)
      end
      love.graphics.setColor(0, 0, 0, 0.7)
      love.graphics.rectangle("fill", x - 4, y - 4,
                              width + 8, #lines * 16 + 8)
      love.graphics.setColor(1, 1, 0.3, 1)
      for i, line in ipairs(lines) do
        love.graphics.print(line, x, y + (i - 1) * 16)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end)
end

return ScottKanto
