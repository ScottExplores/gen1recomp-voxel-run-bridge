-- Ordinary Gen 1 follower walking regression against a real Gen1Recomp tree.
--
-- This deliberately uses the engine's real Player, NPC, Collision, and
-- SpriteRenderer modules.  Only the flat test map and the mod API handle are
-- headless fixtures.  Run once per supported engine checkout:
--
--   luajit tests/wilds_follower_gen1_walk.lua <mod-root> <engine-root>

local argv = rawget(_G, "arg") or {}
local modRoot = assert(argv[1], "Scott's Tweaks source root required")
local engineRoot = assert(argv[2], "Gen1Recomp engine root required")

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL " .. tostring(message) .. "\n")
  end
end
local function eq(got, wanted, message)
  check(got == wanted, string.format("%s (got %s, want %s)",
    message, tostring(got), tostring(wanted)))
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function inList(list, wanted)
  for _, value in ipairs(list or {}) do
    if value == wanted then return true end
  end
  return false
end

local function pngDimensions(path)
  local body = read(path)
  if not body or #body < 24 then return nil, nil end
  if body:sub(1, 8) ~= "\137PNG\13\10\26\10" then return nil, nil end
  local function be32(offset)
    local a, b, c, d = body:byte(offset, offset + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(17), be32(21)
end

-- Pin this regression to the public Gen 1 engine movement/draw contracts
-- shared by 0.1.88 and 0.1.96.  The executable assertions below then use
-- those modules, rather than recreating their behavior in the test.
local playerSource = assert(read(engineRoot .. "/src/world/Player.lua"),
  "real Gen1Recomp Player.lua is required")
local npcSource = assert(read(engineRoot .. "/src/world/NPC.lua"),
  "real Gen1Recomp NPC.lua is required")
check(playerSource:find("function Player:tryMove", 1, true) ~= nil,
  "engine exposes ordinary grid-step Player:tryMove")
check(playerSource:find("self.cellX, self.cellY = self.targetX, self.targetY", 1, true) ~= nil,
  "engine lands player grid steps through targetX/targetY")
check(npcSource:find("function NPC:draw", 1, true) ~= nil,
  "engine NPC remains a native drawable entity")

local Player = require("src.world.Player")
local NPC = require("src.world.NPC")
local Collision = require("src.world.Collision")
local SpriteRenderer = require("src.render.SpriteRenderer")
local EngineGame = require("src.core.Game")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("red")

check(type(Player.new) == "function" and type(Player.tryMove) == "function"
    and type(Player.update) == "function",
  "real Gen 1 Player API loaded")
check(type(NPC.new) == "function" and type(NPC.pose) == "function"
    and type(NPC.draw) == "function",
  "real Gen 1 NPC API loaded")
check(type(SpriteRenderer.new) == "function",
  "real Gen 1 SpriteRenderer API loaded")

-- Load Wilds modules with their real V.require contract.  Narrow substitutes
-- cover only optional debug/image-generation/voxel concerns irrelevant to an
-- ordinary Classic-size land walk.
local modules = {
  debug_log = {
    debug = function() end, info = function() end, warn = function() end,
    followerGen2 = function() end, followerGen2Always = function() end,
  },
  animated_sprites = {
    normalizeVariant = function(variant)
      return (variant == "shiny" or variant == "s" or variant == true)
        and "shiny" or "normal"
    end,
  },
  luminance_sheet = { pathFor = function() return nil end },
  variable_size = {
    canApplyTrueSize = function() return false end,
    applyToDef = function(_, def)
      return def, { applied = false, reason = "classic_test" }
    end,
  },
}

local wildRoot = modRoot .. "/vendor/wilds"
local optionValues = {
  sprite_style = "followers",
  use_animated_overworld_sprites = true,
}
local mod = {
  id = "overworld_wild_spawns",
  path = wildRoot,
  exports = {},
  options = {
    get = function(_, key) return optionValues[key] end,
  },
  log = { debug = function() end, info = function() end, warn = function() end },
  find = function() return nil end,
}
function mod:read(relative)
  return read(self.path .. "/" .. relative)
end
mod.assets = {
  path = function(_, relative) return wildRoot .. "/" .. relative end,
}

local V = { mod = mod, path = wildRoot }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile(wildRoot .. "/lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local RuntimeSheets = V.require("runtime_sheets")
local SpriteProviders = V.require("sprite_providers")
local SpriteService = V.require("follower/sprite_service")
local ControlEngine = V.require("follower/control_engine")

local render = {}
function render:_modAssetPath(relative)
  return wildRoot .. "/" .. relative
end
render.runtimeSheets = RuntimeSheets.new(mod)
local sheetsReady, sheetsError = render.runtimeSheets:load()
check(sheetsReady, "bundled runtime follower-sheet manifest loads: "
  .. tostring(sheetsError))
render.spriteProviders = SpriteProviders.new(mod, render)

-- ADVANCED serves the authored colored GSC sheet directly.  This keeps the
-- headless check on a packaged file while exercising the same provider chain
-- and trueColor contract used by the live renderer.
local PaletteFX = require("src.render.PaletteFX")
local previousPaletteMode = PaletteFX.mode
PaletteFX.mode = "redpp"

local mon = {
  species = "CHARMANDER", hp = 20, maxHp = 20, level = 10,
  nickname = "CHARMANDER",
}
local data = {
  constants = { world = { stepFrames = 16, turnFrames = 4 } },
  field = {
    playerSprites = { walk = "SPRITE_RED" },
    tilePairs = { land = {}, water = {} },
    ledges = {},
  },
  pokemon = { CHARMANDER = { dex = 4 } },
  sprites = {},
}

-- Player.new and NPC.new both build the real SpriteRenderer immediately.
-- The control engine then replaces the trailer's seed sprite with the
-- production SpriteService result from Scott's bundled GSC pack.
local seedArt = wildRoot
  .. "/assets/generated/followsprites_runtime/004-normal.png"
data.sprites.SPRITE_RED = {
  id = "SPRITE_RED", image = seedArt, frames = 6,
  walker = true, trueColor = true,
}
data.sprites.SPRITE_PIKACHU = {
  id = "SPRITE_PIKACHU", image = seedArt, frames = 6,
  walker = true, trueColor = true,
}
local seedW, seedH = pngDimensions(seedArt)
eq(seedW, 16, "bundled runtime seed sheet is 16 pixels wide")
eq(seedH, 96, "bundled runtime seed sheet carries six 16px walk frames")

Collision.load(data)
local player = Player.new(data, 3, 3, "right")
local map = {
  id = "WILDS_GEN1_WALK_TEST",
  def = { tileset = "OVERWORLD" },
}
function map:inBounds(x, y)
  return x >= 0 and y >= 0 and x < 16 and y < 12
end
function map:isWalkableCell(x, y) return self:inBounds(x, y) end
function map:isWaterCell() return false end
function map:cellTile() return 1 end
function map:warpAtCell() return nil end

local game = {
  generation = 1,
  version = "red",
  data = data,
  save = {
    party = { mon },
    pokepcFollowerCount = 1,
    pokepcControlMode = "follow",
    pokepcLeader = { source = "party", index = 1 },
    followerPartyIndex = 1,
    options = { modOptions = {} },
  },
}
local ow = {
  game = game, map = map, player = player,
  entities = { player }, npcs = {},
}
game.overworld = ow
mod.world = {
  game = game,
  overworld = function() return ow end,
}
EngineGame.data = data
EngineGame.save = game.save
EngineGame.overworld = ow
EngineGame.input = EngineGame.input or {
  isTouchDown = function() return false end,
}

render.spriteProviders:finalize(game)
local spriteService = SpriteService.new(mod, { render = render })
local resolved = spriteService:resolveFollowerSprite({
  species = mon.species,
  surface = "land",
  role = "party_trailer",
  game = game,
})
check(type(resolved) == "table" and resolved.fallback == false,
  "production SpriteService resolves the ordinary follower without fallback")
eq(resolved and resolved.providerId, "followers_ex",
  "default FOLLOWERS/GSC style selects the bundled GSC provider")
local bundledArt = wildRoot
  .. "/assets/enhanced_overworld/poke_followers/follower_004_normal.png"
eq(resolved and resolved.image, bundledArt,
  "Charmander resolves to Scott's bundled GSC follower art")
local artW, artH = pngDimensions(bundledArt)
eq(artW, 16, "selected bundled follower art is 16 pixels wide")
eq(artH, 96, "selected bundled follower art has six native walk frames")

local engine = ControlEngine.new(mod, {
  game = game,
  render = render,
  spriteService = spriteService,
})
local synced, syncReason = engine:syncTrailers(game, ow, {
  mapEnter = true,
  spawnAtPlayer = true,
})
check(synced, "ordinary Gen 1 follower spawns: " .. tostring(syncReason))
eq(#(ow.pokepcTrailers or {}), 1,
  "one configured party follower becomes one trailer")

local trailer = ow.pokepcTrailers and ow.pokepcTrailers[1]
check(trailer ~= nil and getmetatable(trailer) == NPC,
  "follower is a real Gen1Recomp NPC")
check(inList(ow.entities, trailer) and inList(ow.npcs, trailer),
  "follower is attached to both Gen 1 draw/entity containers")
check(trailer and trailer.sprite and getmetatable(trailer.sprite) == SpriteRenderer,
  "follower owns a real native SpriteRenderer")
eq(trailer and trailer.sprite and trailer.sprite.def.image, bundledArt,
  "spawned follower keeps the selected bundled art")
eq(trailer and trailer.sprite and trailer.sprite.frameCount, 6,
  "spawned follower renderer exposes all six walk frames")
eq(trailer and trailer.cellX, 3,
  "fresh-map follower starts parked under the player")
eq(trailer and trailer.cellY, 3,
  "fresh-map follower starts on the player's row")

local drawCalls = 0
local previousDraw = love.graphics.draw
love.graphics.draw = function(...)
  drawCalls = drawCalls + 1
  return previousDraw(...)
end
local drawOk, drawError = pcall(function() trailer:draw(0, 0) end)
check(drawOk, "spawned native follower draws: " .. tostring(drawError))
check(drawCalls > 0, "spawned follower reaches love.graphics.draw")

-- Four uninterrupted ordinary grid steps.  This mirrors the live ordering:
-- Player:update lands/interpolates first, then the wrapped overworld update
-- calls ControlEngine:update once for that same logic frame.
local expectedFollowerX = { 3, 4, 5, 6 }
for step = 1, 4 do
  local move, why = player:tryMove("right", map, ow.entities)
  eq(move, "moved", "player starts ordinary grid step " .. step
    .. ": " .. tostring(why))
  local frames = player.stepFramesCur or player.stepFrames or 16
  for _ = 1, frames do
    player:update()
    local updated, updateError = engine:update(game, ow, {
      force = true,
      source = "gen1_walk_regression",
    })
    check(updated, "follower update succeeds during grid step " .. step
      .. ": " .. tostring(updateError))
  end
  eq(player.cellX, 3 + step,
    "player lands ordinary grid step " .. step)
  eq(player.cellY, 3, "player stays on the test row at step " .. step)
  eq(trailer.cellX, expectedFollowerX[step],
    "follower occupies the player's vacated cell after step " .. step)
  eq(trailer.cellY, 3,
    "follower remains on the walked trail after step " .. step)
  eq(player.cellX - trailer.cellX, 1,
    "follower remains exactly one cell behind after step " .. step)
  check(ow.pokepcTrailers[1] == trailer,
    "ordinary walking preserves follower identity at step " .. step)
  check(inList(ow.entities, trailer) and inList(ow.npcs, trailer),
    "follower remains attached/drawable at step " .. step)
  eq(trailer.sprite and trailer.sprite.def.image, bundledArt,
    "follower keeps bundled art while walking at step " .. step)
end

check(trailer.cellX > 3,
  "follower advances rather than remaining at its spawn cell")
check((engine.diag.advanceTrailerStepCalls or 0) >= 3 * 16,
  "control engine advances the follower on ordinary logic frames")
check(trailer.moving == false and trailer.targetX == nil
    and trailer.targetY == nil,
  "follower lands cleanly after the final ordinary step")

local finalDraws = drawCalls
local finalDrawOk, finalDrawError = pcall(function() trailer:draw(0, 0) end)
check(finalDrawOk, "walked follower still draws: " .. tostring(finalDrawError))
check(drawCalls > finalDraws,
  "walked follower still reaches the native draw path")

love.graphics.draw = previousDraw
PaletteFX.mode = previousPaletteMode

if failures > 0 then
  io.stderr:write(string.format("%d/%d checks passed, %d FAILURES\n",
    checks - failures, checks, failures))
  os.exit(1)
end

print(string.format("wilds follower Gen 1 walk: %d checks passed (%s)",
  checks, engineRoot))
