-- Voxel world mode: assemble and draw one frame of the 3D scene.
--
-- World space is world pixels and shares its origin with the 2D paths, so
-- the terrain mesh needs no transform at all and a connected map just
-- translates by the same (ox, oy) the flat renderer already offsets it by.
--
-- Order is: the sun's shadow pass, then terrain, then characters, then a 2D
-- overlay for the field FX. There is no y-sort anywhere -- the depth buffer
-- resolves occlusion, which is the whole point of the mode. Walk behind a
-- building and the building is simply in front.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")
local ChunkMesher = V.require("ChunkMesher")
local SpriteBillboards = V.require("SpriteBillboards")
local TileShape = V.require("TileShape")
local Structures = V.require("Structures")
local TerrainAtlas = V.require("TerrainAtlas")
local Voxel = V.require("VoxelState")
local Sky = V.require("Sky")
local Water = V.require("Water")
local VoxelGrid = V.require("VoxelGrid")
local DayNight = V.require("DayNight")
local FirstPerson = V.require("FirstPerson")
local ThirdPerson = V.require("ThirdPerson")
local Quality = V.require("Quality")
local BattleCinematic = V.require("BattleCinematic")
local BattleBillboard = V.require("BattleBillboard")
local Pokedex = V.require("Pokedex")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.gen2.Map")

local VoxelScene = {}

-- v0.3.59 Kanto frame-scratch helpers. These are methods rather than locals so
-- this already-large module does not spend extra main-chunk local slots. Native
-- Johto callers that do not provide `_stadiumFrameScratch` keep the historical
-- fresh-table behavior.
function VoxelScene._scratchArray(scratch, name)
  if not scratch then return {} end
  local t = scratch[name]
  if not t then t = {}; scratch[name] = t end
  for i = #t, 1, -1 do t[i] = nil end
  return t
end

-- Arrays such as neighbour mesh readiness may contain holes, so Lua's `#`
-- cannot safely tell us how much of the previous frame must be cleared. Keep a
-- tiny high-water mark on the scratch object and clear that numeric range in
-- place. This avoids allocating replacement arrays without retaining stale
-- meshes when a nearer slot becomes nil.
function VoxelScene._scratchIndexed(scratch, name, count)
  if not scratch then return {} end
  local t = scratch[name]
  if not t then t = {}; scratch[name] = t end
  local countKey = name .. "Count"
  local prev = tonumber(scratch[countKey]) or 0
  local n = math.max(prev, math.max(0, tonumber(count) or 0))
  for i = 1, n do t[i] = nil end
  scratch[countKey] = math.max(0, tonumber(count) or 0)
  return t
end

-- Map-id live sets are dictionaries rather than arrays. Reuse their table too;
-- the live set is presentation scratch only and ChunkMesher copies it into its
-- own two-generation residency buffer when membership actually changes.
function VoxelScene._scratchSet(scratch, name)
  if not scratch then return {} end
  local t = scratch[name]
  if not t then t = {}; scratch[name] = t end
  for k in pairs(t) do t[k] = nil end
  return t
end

function VoxelScene._sameSet(a, b)
  for k, v in pairs(a or {}) do if v and not (b and b[k]) then return false end end
  for k, v in pairs(b or {}) do if v and not (a and a[k]) then return false end end
  return true
end

function VoxelScene._copySet(dst, src)
  dst = dst or {}
  for k in pairs(dst) do dst[k] = nil end
  for k, v in pairs(src or {}) do if v then dst[k] = true end end
  return dst
end

function VoxelScene._scratchRecord(scratch, poolName, index)
  if not scratch then return {} end
  local pool = scratch[poolName]
  if not pool then pool = {}; scratch[poolName] = pool end
  local rec = pool[index]
  if not rec then
    rec = {}; pool[index] = rec
  else
    for k in pairs(rec) do rec[k] = nil end
  end
  return rec
end

function VoxelScene._trimScratchPool(scratch, poolName, used)
  if not scratch then return end
  local pool = scratch[poolName]
  if not pool then return end
  used = math.max(0, math.floor(tonumber(used) or 0))
  local key = poolName .. "Used"
  local prev = tonumber(scratch[key])
  if prev == nil then prev = #pool end
  if used < prev then
    for i = used + 1, prev do
      local rec = pool[i]
      if rec then for k in pairs(rec) do rec[k] = nil end end
    end
  end
  scratch[key] = used
end

function VoxelScene._neighborModel(nb)
  local x, z = tonumber(nb and nb.ox) or 0, tonumber(nb and nb.oy) or 0
  if nb and nb._stadiumModel and nb._stadiumModelX == x and nb._stadiumModelZ == z then
    return nb._stadiumModel
  end
  local model = Mat4.translate(x, 0, z)
  if nb then
    nb._stadiumModel, nb._stadiumModelX, nb._stadiumModelZ = model, x, z
  end
  return model
end

function VoxelScene._waterRow(scratch, list, mesh, texture, model)
  local i = #list + 1
  local row
  if scratch then
    row = VoxelScene._scratchRecord(scratch, "waterPool", i)
  else
    row = {}
  end
  row[1], row[2], row[3] = mesh, texture, model
  list[i] = row
  return row
end

-- What the active display mode actually paints with.
--
-- paletteFor hands back a map's RAW SGB zone palette, and that is not what
-- any of the non-colour modes draw. The flat path runs it through
-- PaletteFX.effectiveColors on the way to the shade-remap shader, and that
-- call IS where GRAY, INVERTED and CLASSIC happen -- OG / OG INV replace
-- the palette with the DMG greys (inverted for the latter), CLASSIC
-- replaces it with the green DMG set, and GBC INV permutes the zone's own
-- shades. GBC and RED++ pass through untouched.
--
-- This pass has no shader to apply that in: colour is baked into the atlas
-- and into the sprite sheets ahead of the draw, so it has to run the same
-- transform itself. Without it every mode that is not already a colour mode
-- comes through wearing the SGB palette -- grey and inverted both rendering
-- as plain SGB blue.
local function modeColors(paletteFor, map)
  local c = paletteFor and paletteFor(map) or nil
  return PaletteFX.effectiveColors(c)
end

VoxelScene._modeColors = modeColors   -- named for the suite

-- ------------------------------------------------------------------ sky --
--
-- The void behind the diorama is SKY, at every rung -- so the world reads as
-- standing under something rather than floating on a black plate.
--
-- What is up there differs by rung, and the sky follows it rather than being
-- retuned for each. At 75 degrees the camera is pitched far enough over that
-- the horizon is genuinely in frame, and the bands run down to meet it. At the
-- steeper rungs the horizon is above the top edge and the void that shows is
-- where the ground runs OUT -- past the map edge, past the curve -- so the
-- bands take a fixed slice of the frame instead (lib/Sky.lua, Sky.SPAN) and the
-- haze below them fills the rest.
--
-- INDOORS THERE IS NO SKY. A house, a cave or a gym is a room with a
-- ceiling, and the void past its walls is the outside of a box, not open
-- air. Map.isOutdoor is the same test the engine uses for door SFX and the
-- town map, and the same one Structures already asks to decide whether a
-- map rings with trees.
--
-- The colour is a four-shade ramp shaped like a world palette so the
-- display mode can transform it exactly like one: GRAY gets a grey sky,
-- CLASSIC a green one, GBC INV a dark one, and the colour modes the blue.
-- A hardcoded blue would sit wrong in every non-colour mode -- the same
-- mismatch the terrain bake had.
--
-- This ramp is the FLAT sky -- what a caller clears the void to. The free-roam
-- camera's banded sky has a palette of its own (lib/Sky.lua), transformed the
-- same way by the same seam; they are separate because the flat one also has to
-- serve an indoor void and a battle's arena, which want a colour rather than a
-- sky.
local SKY_SHADES = { { 222, 242, 255 }, { 135, 196, 240 },
                     { 64, 120, 192 }, { 16, 40, 80 } }
local SKY_SHADE = 2       -- the ramp's "sky" proper; 1 is its highlight

-- the ramp as the display mode has it, which is the only form anything here
-- should be reading it in
local function skyRamp()
  return PaletteFX.effectiveColors(SKY_SHADES) or SKY_SHADES
end

-- Full strength at every rung: the sky is painted wherever the diorama is.
--
-- The ramp that is left is for ARRIVAL alone. Switching the mode on eases the
-- camera up from flat, and the sky comes up with it over the first few degrees
-- rather than appearing whole on the keypress -- which is also what keeps a
-- top-down camera, where there is no void worth speaking of, from painting one.
local SKY_FADE_DEG = 8

local function skyStrength(angleRad)
  local deg = math.deg(angleRad or 0)
  if deg <= 0 then return 0 end
  local t = deg / SKY_FADE_DEG
  return t < 1 and t or 1
end

-- One shade off the sky ramp, transformed by the display mode, as an
-- {r, g, b, a} in 0..1. `shade` picks the rung (SKY_SHADE is the sky
-- proper; 4 is its darkest, which is what an indoor void wants).
function VoxelScene.skyShade(shade, alpha)
  local shades = skyRamp()
  local c = shades[shade] or SKY_SHADES[shade] or SKY_SHADES[SKY_SHADE]
  return { c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1 }
end

-- The sky `map` stands under at strength `t`, or nil where there is no sky
-- to paint: indoors, or with the horizon out of frame.
--
-- One flat colour, which is what a caller that only needs something to clear the
-- void to wants -- the overworld battle's arena shot is one of those. The
-- gradient is added on top of this by skyFor, for the free-roam camera alone.
function VoxelScene.skyColor(map, t)
  if not (map and map.def and Map.isOutdoor(map.def)) then return nil end
  if not t or t <= 0 then return nil end
  local sky = VoxelScene.skyShade(SKY_SHADE, t)
  -- outdoors the flat fill follows the CLOCK: it becomes the hour's haze --
  -- gold at dusk, navy at night -- so a battle staged on the map at
  -- midnight is under a midnight void, not a noon one. Free-roam is
  -- unchanged by this: Sky.dress overwrites the fill with the same value.
  local haze = Sky.haze()
  if haze then sky[1], sky[2], sky[3] = haze[1], haze[2], haze[3] end
  return sky
end

-- The free-roam sky: the flat one above, dressed with the banded gradient
-- (lib/Sky.lua).
--
-- Only here, and deliberately. This is the sky the walking camera stands under,
-- where the horizon is a quarter of the way down the frame at the top rung and
-- one flat blue reads as a wall of paint. A battle is a staged shot with its own
-- placed camera whose horizon sits above the frame entirely, so it keeps the
-- flat fill it has always had -- there is no gradient to see from down there,
-- and the arena's look is not this rung's to change.
local function skyFor(map)
  local sky = VoxelScene.skyColor(map, skyStrength(Voxel.angle))
  if not sky then return nil end
  return Sky.dress(sky)
end

VoxelScene._skyFor = skyFor           -- named for the suite
VoxelScene._skyStrength = skyStrength

-- A facing as a yaw about +Y, kept for callers that reason about which way
-- an entity points (the mod exports it). The character cards themselves
-- never yaw -- they face south and lean, like the flat game.
local YAW = {
  down = 0,
  up = math.pi,
  right = math.pi / 2,
  left = -math.pi / 2,
}

-- The ground height a cell stands at, so a character on a ledge stands on
-- top of it rather than sunk into it. Uses the same bottom-left collision
-- tile the engine walks on (Map:cellTile).
local function groundAt(map, cellX, cellY)
  -- Off the map, cellTile border-extends into the map's borderBlock --
  -- which on maps ringed with trees is a RAISED tile. The only entity
  -- ever standing off-map is the player mid seam-step (placed one cell
  -- before the connection entry), and the ground actually rendered
  -- there is the departed neighbour's flat walkway: height 0. Without
  -- this, crossing into such a map hoisted the walker tree-high for
  -- exactly one step -- the "hops like a ledge" seam bug.
  if not map:inBounds(cellX, cellY) then return 0 end
  local shapes = TileShape.forMap(map)
  -- the same full resolution the mesher draws with, NOT the raw tile table:
  -- on Gen 2 map:cellTile answers a COLLISION CLASS rather than a tile id,
  -- so indexing the tile shapes with it read some unrelated tile's box and
  -- stood every character 16px above the ground they were walking on
  local tx, ty = cellX * 2, cellY * 2 + 1
  local s = TileShape.at(map, shapes, map:tileAt(tx, ty), tx, ty)
  if not s then return 0 end
  -- a box the walker passes THROUGH rather than onto: Gen 2 pins its
  -- doorways solid so the facade closes over them, and the cell they are
  -- cut into stays walkable
  if s.art == "upright" and map:isWalkableCell(cellX, cellY) then return 0 end
  -- a recessed class (water) still supports whatever stands on it; only
  -- raised ground lifts the model.  Stairs never do: the class height is
  -- the flight's TALL end, but the player enters at floor level and the
  -- warp fires as they step in -- lifting them onto the geometry read as
  -- climbing an invisible block
  if s.art == "stair" then return 0 end
  -- ...and a cell the mesher gave a MEASURED height to answers with that
  -- one, not with its class default: the river above a waterfall is drawn
  -- at the fall's crest (Structures.buildFalls), and a surfer reading the
  -- class height alone swam four cells under the sheet he was floating on.
  local measured = Structures.runHeight(map, tx, ty)
  if measured and measured > 0 then return measured end
  return s.h > 0 and s.h or 0
end

VoxelScene.YAW = YAW
-- shared with the overworld battle, which stands its mons on map cells and
-- needs the same answer about what height "the floor" is there
VoxelScene.groundAt = groundAt

-- Camera-ward pull distance for billboards (and the grass rows, which
-- must keep their relative depth to feet): just enough that a leaned-back
-- slab clears the wall it leans over. The lean flattens toward top-down,
-- so the needed pull grows exactly as real occlusion stops mattering.
function VoxelScene.pull(a)
  return 6 + math.max(0, 16 * math.cos(a) - 8) / math.max(math.sin(a), 0.2)
end

-- The sheet frame and mirror flag the 2D path would draw for this pose
-- (same tables as SpriteRenderer). Shared by the billboard pass and the
-- shadow pass so a walking character's shadow swings its legs too.
local function frameFor(def, facing, phase, flip)
  local SR = require("src.render.SpriteRenderer")
  local frame, mirror = 0, false
  -- SPRITE_POKEMON objects carry a 2-frame party icon with no facing at all,
  -- so the pose tables (which index up to 5) do not apply to them
  if def.monIcon then
    return math.floor((love.timer and love.timer.getTime() or 0) * 4) % 2, false
  end
  if (def.frames or 1) > 1 then
    frame = (def.walker and phase == 1) and SR.WALK[facing]
            or SR.STAND[facing]
    mirror = facing == "right"
      or ((facing == "down" or facing == "up") and phase == 1 and flip)
  end
  return frame, mirror
end

-- The facing a pose SHOWS this camera. The flat frames are "how this pose
-- looks from the south", which is where the orbit always stands; a
-- first-person eye stands anywhere, so deep enough into the blend the
-- facing is remapped to how the pose looks from THERE -- walk behind an
-- NPC and their card wears the back sprite. Used by the camera draw and
-- the sun pass BOTH: the card the sun stored and the transform a lit card
-- reads its own shadowing with must describe the same frame, or the
-- mirror-flip half of the pair asks the map about texels the sun filed
-- under the other cheek.
-- The player's own card asks a different function for the same answer:
-- their body's bearing is what the camera is derived FROM, so it is known
-- continuously rather than as one of four directions, and measuring
-- against the compass point instead flicks the card to a profile for a
-- frame or two when the camera is spun fast (see playerFacing).
local function viewFacing(p)
  if FirstPerson.cardBlend() > 0.5 then
    if p.isPlayer then
      return FirstPerson.playerFacing(p.facing, p.px + 8, p.py + 8)
    end
    return FirstPerson.apparentFacing(p.facing, p.px + 8, p.py + 8)
  end
  return p.facing
end

-- FALLBACK ONLY (see castShadows below). Draw one entity's drop shadow as
-- a decal: its current sprite frame as a single quad, flattened onto the
-- ground along the sun line (Voxel3D.shadowMatrix). Runs inside
-- beginShadows, which supplies the translucent black; the texture is only
-- consulted for its alpha, so no palette work is needed.
local fastShadowMesh, fastShadowTex
local function ensureFastShadow()
  if fastShadowMesh and fastShadowTex then return fastShadowMesh, fastShadowTex end
  if not (love and love.graphics and love.image and love.image.newImageData) then return nil end
  local ok, mesh, tex = pcall(function()
    local data = love.image.newImageData(32, 16)
    for y = 0, 15 do
      for x = 0, 31 do
        local nx = (x - 15.5) / 15.5
        local ny = (y - 7.5) / 7.5
        local d = nx * nx + ny * ny
        local a = math.max(0, math.min(1, (1.0 - d) * 2.5))
        data:setPixel(x, y, 1, 1, 1, a)
      end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("linear", "linear")
    local verts = {
      { -11, 0, -5.5, 0, 0, 1 }, { 11, 0, -5.5, 1, 0, 1 },
      { 11, 0,  5.5, 1, 1, 1 }, { -11, 0,  5.5, 0, 1, 1 },
    }
    local indices = {}
    Voxel3D.pushQuad(indices, 0)
    return Voxel3D.newMesh(verts, indices), image
  end)
  if ok then fastShadowMesh, fastShadowTex = mesh, tex end
  return fastShadowMesh, fastShadowTex
end

local shadowMatrixScaled
local function drawShadow(sprite, px, py, facing, phase, flip, gh, lift,
                          visualScale)
  if Quality.blobShadows and Quality.blobShadows() then
    local mesh, tex = ensureFastShadow()
    if not (mesh and tex) then return end
    local air = math.max(0, tonumber(lift) or 0)
    local scale = math.max(0.55, 1 - air / 96)
      * math.max(0.05, tonumber(visualScale) or 1)
    local model = Mat4.mul(Mat4.translate((px or 0) + 8, (gh or 0) + Voxel3D.SHADOW_EPS, (py or 0) + 8),
                           Mat4.scale(scale, 1, scale))
    Voxel3D.draw(mesh, tex, model)
    return
  end
  local def = sprite.def
  local frame, mirror = frameFor(def, facing, phase, flip)
  local mesh = SpriteBillboards.shadowQuad(def, frame)
  if not mesh then return end
  Voxel3D.draw(mesh, sprite:resolveImage(),
               shadowMatrixScaled(px, py, gh, lift, mirror, visualScale))
end

-- Where a billboard character's card stands: on the middle of its cell at
-- height `y`, pivoted at the feet and tipped back by exactly the camera's
-- pitch. The slab is built centred on its sprite plane (z = 0), so only the
-- x anchor shifts; the relief bulges symmetrically front and back of it.
--
-- Shared by the solid draw and the silhouette below, so the two can never
-- drift apart -- a silhouette standing anywhere but exactly behind the
-- figure would read as a second character.
--
-- IN FIRST PERSON the card stops leaning and starts TURNING: upright, yawed
-- about its feet to face the eye (cylindrical billboarding). A south-facing
-- card is invisible edge-on to an eye standing east of it, which no orbit
-- camera could ever do and a first-person one does constantly. The blend
-- carries one pose into the other -- the lean eases out as the yaw eases in
-- -- and cardBlend is zero for every camera that is not the first-person
-- rig, the battle's placed shot included, so nothing else moves.
-- The pitch the sprite cards lean back by -- normally the rung's own
-- camera angle, overridable in radians. VR sets the override to the top
-- rung's 75 degrees for every diorama and battle frame: a table watched
-- from a freely moving head has no one camera pitch for the cards to
-- match, and the near-upright top-rung lean is the pose that reads as
-- "standing" from anywhere around it. nil (the default, and the flat
-- screen always) leans with the rung as ever.
VoxelScene.spriteLean = nil

local function leanAngle()
  return VoxelScene.spriteLean or V.require("VoxelState").angle
end

local function billboardMatrix(px, py, y, mirror, visualScale)
  local b = FirstPerson.cardBlend()
  local m = Mat4.translate(px + 8, y, py + 8)
  if b > 0 then
    m = Mat4.mul(m, Mat4.rotateY(FirstPerson.cardYaw(px + 8, py + 8) * b))
  end
  m = Mat4.mul(m, Mat4.rotateX((leanAngle() - math.pi / 2) * (1 - b)))
  if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
  local scale = tonumber(visualScale) or 1
  if math.abs(scale - 1) > 1e-6 then
    -- The mesh is centred by the final -8 translation and its feet sit at y=0.
    -- Scaling BEFORE that centring therefore shrinks around the feet/cell centre
    -- instead of pulling the trainer sideways or underground.
    m = Mat4.mul(m, Mat4.scale(scale, scale, 1))
  end
  return Mat4.mul(m, Mat4.translate(-8, 0, 0))
end

local function billboardPull()
  return VoxelScene.pull(math.max(leanAngle(), 0.05))
end

-- One presentation scale for the player's card, its occlusion silhouette and
-- both shadow paths.  Keeping all four copies on the same transform is what
-- prevents the fix for a giant third-person trainer from leaving behind an
-- oversized shadow/ghost outline.
local function playerCardScale(p)
  if not (p and p.isPlayer and p.sprite and p.sprite.def) then return 1 end
  return ThirdPerson.playerCardScale(p.sprite.def.frameHeight or 16)
end

local function casterMatrixScaled(px, py, y, mirror, visualScale)
  local scale = tonumber(visualScale) or 1
  if math.abs(scale - 1) <= 1e-6 then
    return Voxel3D.casterMatrix(px, py, y, mirror)
  end
  local m = Mat4.translate(px + 8, y, py + 8)
  if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
  m = Mat4.mul(m, Mat4.scale(scale, scale, 1))
  m = Mat4.mul(m, Mat4.translate(-8, 0, 0))
  return Mat4.mul(m, Mat4.scale(1, 1, 0))
end

shadowMatrixScaled = function(px, py, gh, lift, mirror, visualScale)
  local scale = tonumber(visualScale) or 1
  if math.abs(scale - 1) <= 1e-6 then
    return Voxel3D.shadowMatrix(px, py, gh, lift, mirror)
  end
  local card = casterMatrixScaled(px, py, gh + (lift or 0), mirror, scale)
  local squash = { 1, Voxel3D.SHADOW_KX, 0, 0,
                   0, 0,                 0, 0,
                   0, Voxel3D.SHADOW_KZ, 1, 0,
                   0, 0,                 0, 1 }
  local m = Mat4.mul(squash, Mat4.mul(Mat4.translate(0, -gh, 0), card))
  return Mat4.mul(Mat4.translate(0, gh + Voxel3D.SHADOW_EPS, 0), m)
end

-- An authored FIGURE's card -- a person the tileset draws INTO a piece of
-- furniture, cut out by the profile's mask (Structures.buildFigures). It is
-- a sprite, so it gets the sprite treatment: the mesh arrives in its own
-- local space with its feet on y = 0, and this stands it at its drawn
-- position and tips it back by exactly the camera's pitch -- the same
-- pivot-at-the-feet lean billboardMatrix gives a character, so the man on
-- the Pokemon Center couch reads face-on at every tilt like the NPCs
-- around him. No cell centring: unlike a character he is not standing on a
-- cell, he is standing where he was drawn, which may straddle two.
--
-- First person turns him at the eye like the walkers (see billboardMatrix)
-- -- about his own middle, because unlike a character card his local space
-- starts at x = 0 rather than being anchored by a -8 shift, and a yaw about
-- his edge would swing him off his seat. The width rode in on the record
-- for exactly this (ChunkMesher.buildFigureMeshes).
local function figureMatrix(f, offX, offZ)
  local b = FirstPerson.cardBlend()
  local wx, wz = f.wx + (offX or 0), f.wz + (offZ or 0)
  local m = Mat4.translate(wx, f.y, wz)
  if b > 0 and f.w and f.w > 0 then
    local half = f.w / 2
    m = Mat4.mul(m, Mat4.translate(half, 0, 0))
    m = Mat4.mul(m, Mat4.rotateY(FirstPerson.cardYaw(wx + half, wz) * b))
    m = Mat4.mul(m, Mat4.translate(-half, 0, 0))
  end
  return Mat4.mul(m, Mat4.rotateX((leanAngle() - math.pi / 2) * (1 - b)))
end

-- What the sun sees: the same card UNLEANED and flattened, exactly as
-- Voxel3D.casterMatrix does it for a character.
local function figureCaster(f, offX, offZ)
  return Mat4.mul(
    Mat4.translate(f.wx + (offX or 0), f.y, f.wz + (offZ or 0)),
    Mat4.scale(1, 1, 0))
end

-- Every figure on `map`, drawn with `draw(mesh, model, caster)`.
local function eachFigure(map, offX, offZ, draw, view)
  local pad = 96
  if view and Quality and type(Quality.figureCullPadding) == "function" then
    local ok, got = pcall(Quality.figureCullPadding, view.vw, view.vh)
    if ok and tonumber(got) then pad = tonumber(got) end
  end
  offX, offZ = offX or 0, offZ or 0
  for _, f in ipairs(ChunkMesher.figures(map) or {}) do
    local visible = true
    if view then
      local wx = (tonumber(f.wx) or 0) + offX
      local wz = (tonumber(f.wz) or 0) + offZ
      local fw = math.max(16, tonumber(f.w) or 16)
      visible = wx + fw >= view.cx - view.vw * 0.5 - pad
        and wx - fw <= view.cx + view.vw * 0.5 + pad
        and wz + 32 >= view.cy - view.vh * 0.5 - pad
        and wz - 32 <= view.cy + view.vh * 0.5 + pad
    end
    if visible then
      draw(f.mesh, figureMatrix(f, offX, offZ), figureCaster(f, offX, offZ))
    end
  end
end

-- Draw one posed entity. Returns true if 3D geometry carried it, false
-- when nothing could be built and the caller should fall back.
-- `colors` is the 4-color world palette the entity stands under in the SGB
-- modes (nil under RED++/trueColor): the 2D path colorizes sprites with a
-- screen-space shader the voxel canvas never runs through, so the model's
-- texture gets the palette baked in instead (TerrainAtlas.forSprite).
-- `lift` raises the figure off the ground plane (ledge hops arc UP in 3D,
-- where the 2D path could only slide the sprite north).
local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,
                          lift, visualScale)
  local def = sprite.def
  local tex = sprite:resolveImage()
  if colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, colors) or tex
  end
  local y = gh + (lift or 0)

  -- pick the very frame the 2D path would draw (same tables). The card
  -- always faces SOUTH -- the direction the 2D game implies -- and only
  -- LEANS BACK, pivoting at its feet, by exactly the camera's pitch, so
  -- at every tilt level the sprite reads face-on like the flat game.
  -- No camera-tracking yaw: every sprite leans in parallel.
  local frame, mirror = frameFor(def, facing, phase, flip)
  local mesh = SpriteBillboards.mesh(def, frame)
  if not mesh then return false end
  -- Camera-ward pull (applied per vertex in the shader, along each
  -- vertex's own eye ray, so it is a PURE depth bias with zero screen
  -- drift): lets the leaned-back head win against the wall it leans
  -- OVER while a character genuinely BEHIND a building is dozens of
  -- pixels deeper and still loses, so real occlusion works.
  -- the same card UNLEANED -- and SNUGGED, exactly as the sun stored it
  -- (castShadows draws this mesh through ShadowMap.snug) -- is where each
  -- vertex asks whether the light reached it; see ShadowMap.snug for why
  -- the lookup must match the stored transform to the letter
  Voxel3D.draw(mesh, tex, billboardMatrix(px, py, y, mirror, visualScale),
               billboardPull(),
               ShadowMap.snug(casterMatrixScaled(px, py, y, mirror, visualScale)))
  return true
end

VoxelScene.drawEntity = drawEntity

-- The player's silhouette, for wherever the scenery is standing in front of
-- them (Voxel3D.beginGhost inverts the depth test around this call).
--
-- The same flat card the solid pass and the sun pass draw. That it has no
-- self-overlap is what makes it safe here: with the depth test inverted, a
-- mesh carrying both front and back faces would read its own back faces as
-- "behind something" and repaint the figure on open ground, occluded or
-- not. One quad cannot do that, and cannot double-blend into a mottled
-- patch either. A silhouette is an outline, so an outline is the right
-- mesh for it.
local function drawGhost(p)
  local def = p.sprite.def
  local frame, mirror = frameFor(def, viewFacing(p), p.phase, p.flip)
  local mesh = SpriteBillboards.shadowQuad(def, frame)
  if not mesh then return end
  local tex = p.sprite:resolveImage()
  if p.colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, p.colors) or tex
  end
  local y = p.gh + (p.lift or 0)
  local visualScale = playerCardScale(p)
  Voxel3D.draw(mesh, tex, billboardMatrix(p.px, p.py, y, mirror, visualScale),
               billboardPull())
end

-- Render the world. `state` is the OverworldState; `vw`/`vh` the world view
-- size in world pixels; `w`/`h` the pixel size of the canvas to render
-- into; `paletteFor(map)` yields a map's 4-color world palette (nil in the
-- color modes whose atlas is already true color). Returns the finished
-- canvas, or nil if the 3D pass could not run (headless, no depth support)
-- so the caller can fall back to 2D.
-- The last live-set key, so eviction only runs when the neighbourhood
-- actually changes (a map crossing), not every frame.
local lastLiveKey = nil
local lastOpenWorld = nil
local lastResidencyRegion = nil

-- Request everything `state`'s frame wants and evict what it no longer
-- does; returns the current map's terrain mesh (or nil while it builds)
-- and the neighbour meshes ready to draw. render() calls this for the
-- frame it is drawing, and the pipeline's update hook calls it EVERY
-- frame -- including the frames a warp's Transition covers, when the
-- world pass is off. That update-side call is what lets a door fade hide
-- the destination's build: the map swaps behind the fade, and waiting
-- for the first visible frame to request meshes would show the flat
-- fallback while the first slices run.
-- OPEN WORLD is not a flat overview. Every connected map is meshed with the
-- same FULL voxel geometry the current map uses. Internal seams are masked by
-- the bodies of the map's own cardinal neighbours, while the outside edge keeps
-- the normal 32-tile voxel border/apron. That gives the whole stitched region a
-- continuous 3D perimeter instead of exposing sky/void between or around maps.
local function openWorldFullMasks(state, rec)
  if not (state and state._stadiumOpenWorldNeighbors) then return nil end
  local placements = { [state.map.id] = { map = state.map, ox = 0, oy = 0 } }
  for _, nb in ipairs(state.neighbors or {}) do
    placements[nb.map.id] = { map = nb.map, ox = nb.ox, oy = nb.oy }
  end
  local here = rec or placements[state.map.id]
  if not (here and here.map and here.map.def) then return nil end
  local masks = {}
  for _, conn in pairs(here.map.def.connections or {}) do
    local id = conn and (conn.mapId or conn.map)
    local other = id and placements[id]
    if other and other.map and other.map.def then
      -- ChunkMesher masks are LOCAL to the map being built. Convert the other
      -- body's solved world rectangle back into this map's local coordinates.
      local ox = (tonumber(other.ox) or 0) - (tonumber(here.ox) or 0)
      local oy = (tonumber(other.oy) or 0) - (tonumber(here.oy) or 0)
      masks[#masks + 1] = {
        ox, oy,
        ox + other.map.def.width * 32,
        oy + other.map.def.height * 32,
      }
    end
  end
  return masks
end

local function readyNeighbor(state, i)
  -- Terrain/water residency is intentionally broader than decorative detail.
  -- Distant maps can keep filling the horizon while grass/flowers/figures and
  -- their extra shadow draws are skipped outside a tighter camera apron.
  local detail = state and state._stadiumNeighborDetailReady
  if detail ~= nil then return detail[i] ~= nil end
  local ready = state and state._stadiumNeighborReady
  return ready == nil or ready[i] ~= nil
end

VoxelScene.openWorldFullMasks = openWorldFullMasks

-- v0.3.59: calculate quality padding and expanded camera bounds once per
-- rendered frame. Older code called the Quality functions through pcall once
-- for every neighbour/actor test, even though vw/vh and the quality preset are
-- constant for the whole frame.
function VoxelScene._prepareCullView(view, cx, cy, vw, vh)
  view = view or {}
  cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
  vw, vh = tonumber(vw) or 160, tonumber(vh) or 144
  view.cx, view.cy, view.vw, view.vh = cx, cy, vw, vh
  local halfW, halfH = vw * 0.5, vh * 0.5
  view.x1, view.y1, view.x2, view.y2 =
    cx - halfW, cy - halfH, cx + halfW, cy + halfH

  local function pad(name, fallback)
    local fn = Quality and Quality[name]
    if type(fn) == "function" then
      local ok, got = pcall(fn, vw, vh)
      if ok and tonumber(got) then return tonumber(got) end
    end
    return fallback
  end

  view.worldPad = pad("worldCullPadding", math.huge)
  view.detailPad = pad("detailCullPadding", 96)
  view.actorPad = pad("actorCullPadding", 96)

  if view.worldPad == math.huge then
    view.worldX1, view.worldY1, view.worldX2, view.worldY2 =
      -math.huge, -math.huge, math.huge, math.huge
  else
    view.worldX1, view.worldY1 = view.x1 - view.worldPad, view.y1 - view.worldPad
    view.worldX2, view.worldY2 = view.x2 + view.worldPad, view.y2 + view.worldPad
  end
  view.detailX1, view.detailY1 = view.x1 - view.detailPad, view.y1 - view.detailPad
  view.detailX2, view.detailY2 = view.x2 + view.detailPad, view.y2 + view.detailPad
  view.actorX1, view.actorY1 = view.x1 - view.actorPad, view.y1 - view.actorPad
  view.actorX2, view.actorY2 = view.x2 + view.actorPad, view.y2 + view.actorPad
  return view
end

-- Far-map culling is the v0.2.86 open-world performance hinge.  OPEN WORLD
-- still owns the complete graph, but a map several screens outside the camera
-- no longer burns mesh uploads, terrain draws, grass draws, water draws and
-- shadow work every frame.  As the camera zooms/pans toward it, the same map
-- becomes visible and streams back through the existing async mesher.
local function neighborVisible(state, nb)
  if not (state and nb and nb.map and nb.map.def) then return false end
  local view = state._stadiumCullView
  if not view then return true end
  local pad = view.worldPad
  if pad == nil then
    VoxelScene._prepareCullView(view, view.cx, view.cy, view.vw, view.vh)
    pad = view.worldPad
  end
  if pad == math.huge then return true end
  -- Include the full voxel apron (8 blocks = 256 world px) in the visibility
  -- test so a border forest cannot pop at the camera edge.
  local apron = 288
  local x1 = (tonumber(nb.ox) or 0) - apron
  local y1 = (tonumber(nb.oy) or 0) - apron
  local x2 = (tonumber(nb.ox) or 0) + (tonumber(nb.map.def.width) or 0) * 32 + apron
  local y2 = (tonumber(nb.oy) or 0) + (tonumber(nb.map.def.height) or 0) * 32 + apron
  return x2 >= view.worldX1 and x1 <= view.worldX2
     and y2 >= view.worldY1 and y1 <= view.worldY2
end

VoxelScene.neighborVisible = neighborVisible

-- A tighter visibility box for expensive decorative passes. The terrain mesh
-- keeps its much wider apron so an OPEN WORLD survey never exposes empty sky;
-- only grass/flowers/authored figures and far-map shadow casters use this.
local function neighborDetailVisible(state, nb)
  if not (state and nb and nb.map and nb.map.def) then return false end
  local view = state._stadiumCullView
  if not view then return true end
  if view.detailPad == nil then
    VoxelScene._prepareCullView(view, view.cx, view.cy, view.vw, view.vh)
  end
  local apron = 96
  local x1 = (tonumber(nb.ox) or 0) - apron
  local y1 = (tonumber(nb.oy) or 0) - apron
  local x2 = (tonumber(nb.ox) or 0) + (tonumber(nb.map.def.width) or 0) * 32 + apron
  local y2 = (tonumber(nb.oy) or 0) + (tonumber(nb.map.def.height) or 0) * 32 + apron
  return x2 >= view.detailX1 and x1 <= view.detailX2
     and y2 >= view.detailY1 and y1 <= view.detailY2
end

VoxelScene.neighborDetailVisible = neighborDetailVisible


local function rectHitsView(r, cx, cy, vw, vh, pad)
  if not r then return false end
  pad = tonumber(pad) or 96
  local vx1, vy1 = cx - vw * 0.5 - pad, cy - vh * 0.5 - pad
  local vx2, vy2 = cx + vw * 0.5 + pad, cy + vh * 0.5 + pad
  return (tonumber(r.x2) or -math.huge) >= vx1
     and (tonumber(r.x1) or math.huge) <= vx2
     and (tonumber(r.y2) or -math.huge) >= vy1
     and (tonumber(r.y1) or math.huge) <= vy2
end

-- A perimeter ocean can be many screens away from the player.  Do not start
-- Water.begin's reflection/depth copy merely because the toggle is ON; only do
-- the expensive pass once at least one coastline strip can contribute pixels.
local function oceanVisible(ocean, cx, cy, vw, vh)
  if not ocean then return false end
  local rects = ocean.rects
  if type(rects) == "table" and #rects > 0 then
    for _, r in ipairs(rects) do
      if rectHitsView(r, cx, cy, vw, vh, 160) then return true end
    end
    return false
  end
  return rectHitsView(ocean.bounds, cx, cy, vw, vh, 160)
end

VoxelScene.oceanVisible = oceanVisible

-- v0.4.31 persistent sector preloader. Kanto already has a whole-region BODY
-- cooker in TwinRegionWorld; native Johto previously relied almost entirely on
-- visible/predicted render requests. That meant a sector could be perfectly
-- known in the connection graph but still have no persistent BODY cache until
-- the player was already approaching it. Warm nearby prepared Johto maps into
-- VoxelDiskCache ahead of time without allocating GPU meshes. Real renderer
-- jobs always preempt these cache-only jobs in ChunkMesher.
VoxelScene._sectorDiskWarmSeen = VoxelScene._sectorDiskWarmSeen or {}

function VoxelScene._scheduleNeighborDiskWarm(state, neighbors)
  if not (state and state.map and state.map.id) then return 0 end
  if state._stadiumYellowKanto == true then return 0 end
  if not (ChunkMesher and type(ChunkMesher.diskCacheEnabled) == "function"
      and ChunkMesher.diskCacheEnabled()
      and type(ChunkMesher.warmDisk) == "function") then return 0 end

  local osName = nil
  if love and love.system and type(love.system.getOS) == "function" then
    local ok, got = pcall(love.system.getOS)
    if ok then osName = got end
  end
  local mobile = osName == "Android" or osName == "iOS"
  local mode = Quality and type(Quality.buildMode) == "function"
    and Quality.buildMode() or "balanced"
  local targetPending
  if mobile then
    targetPending = mode == "fast" and 2 or 1
  else
    targetPending = mode == "fast" and 6 or (mode == "smooth" and 2 or 4)
  end

  local regionTag = "johto"
  local pending = type(ChunkMesher.warmPending) == "function"
    and ChunkMesher.warmPending(regionTag) or 0
  if pending >= targetPending then return 0 end

  local seen = VoxelScene._sectorDiskWarmSeen
  local queued = 0
  local function consider(nb)
    if pending >= targetPending then return end
    local map = nb and nb.map
    local id = map and map.id
    if not id or id == state.map.id or seen[id] then return end
    local ok, status = ChunkMesher.warmDisk(map, true, nil, regionTag)
    if ok then
      -- A hit/live/queued result all mean this prepared sector no longer needs
      -- probing every presentation frame. Real invalidation/build paths still
      -- persist edited geometry when a map changes later.
      seen[id] = true
      if status == "queued" then
        pending = pending + 1
        queued = queued + 1
        VoxelScene.sectorPreloadQueued = (VoxelScene.sectorPreloadQueued or 0) + 1
      elseif status == "hit" then
        VoxelScene.sectorPreloadHits = (VoxelScene.sectorPreloadHits or 0) + 1
      elseif status == "live" then
        VoxelScene.sectorPreloadLive = (VoxelScene.sectorPreloadLive or 0) + 1
      end
    end
  end

  -- Direct connections first, then second ring, then any deeper map already
  -- prepared by the active quality radius. This fills the disk cache in the
  -- same order the player is most likely to reach those sectors.
  for depth = 1, 3 do
    for _, nb in ipairs(neighbors or {}) do
      if math.floor(tonumber(nb.depth) or 99) == depth then consider(nb) end
      if pending >= targetPending then break end
    end
    if pending >= targetPending then break end
  end
  if pending < targetPending then
    for _, nb in ipairs(neighbors or {}) do
      if (tonumber(nb.depth) or 99) > 3 then consider(nb) end
      if pending >= targetPending then break end
    end
  end
  return queued
end

function VoxelScene.prefetch(state)
  local Voxel = V.require("VoxelState")

  -- The live set is the current map plus its rendered neighbours. When
  -- it changes, everything outside it (and the previous set, which
  -- ChunkMesher retains so stepping into a house keeps the town warm)
  -- is evicted -- meshes released, analysis dropped -- so memory stays
  -- bounded by the neighbourhood instead of growing with every area
  -- ever visited.
  local residencyRegion = tostring(state._stadiumResidencyRegion or "world")
  -- Do not let background Johto cache-only jobs retain prepared Johto map
  -- adapters after the player explicitly switches into Kanto. Kanto owns its
  -- own region warmer and RETURN TO JOHTO already cancels that queue.
  if residencyRegion == "kanto" and lastResidencyRegion ~= nil
      and lastResidencyRegion ~= residencyRegion
      and type(ChunkMesher.cancelWarmRegion) == "function" then
    pcall(ChunkMesher.cancelWarmRegion, "johto")
  end
  local openWorld = state._stadiumOpenWorldNeighbors == true
  local neighbors = state.neighbors or {}
  local scratch = state._stadiumFrameScratch
  local visibleFlags = scratch
    and VoxelScene._scratchIndexed(scratch, "neighborVisible", #neighbors) or nil
  local live = scratch and VoxelScene._scratchSet(scratch, "live") or {}
  live[state.map.id] = true

  -- v0.3.59 computes neighbour visibility once. The previous path repeated the
  -- same camera/quality/bounds test for residency and again for mesh requests.
  for i, nb in ipairs(neighbors) do
    local visible = neighborVisible(state, nb)
    if visibleFlags then visibleFlags[i] = visible end
    -- Directly connected maps stay warm for seamless crossings even when the
    -- camera currently faces away from them. Far maps are resident only while
    -- their expanded bounds can contribute to the current view.
    if (tonumber(nb.depth) or 1) <= 1 or visible then
      live[nb.map.id] = true
    end
  end

  if scratch then
    scratch.liveApplied = scratch.liveApplied or {}
    local membershipChanged = not VoxelScene._sameSet(live, scratch.liveApplied)
    local regionChanged = lastResidencyRegion ~= nil
      and residencyRegion ~= lastResidencyRegion
    local modeChanged = scratch.liveAppliedOpenWorld ~= openWorld
      or scratch.liveAppliedRegion ~= residencyRegion
    if membershipChanged or modeChanged or regionChanged then
      -- Normal house/route streaming keeps one previous neighbourhood warm. A
      -- Johto<->Yellow switch is different: the inactive region cannot be
      -- reached without an explicit transition, so evict it immediately.
      local trimFarNow = regionChanged or (lastOpenWorld == true and not openWorld)
      ChunkMesher.setLive(live, trimFarNow)
      TerrainAtlas.setLive(live)
      VoxelScene._copySet(scratch.liveApplied, live)
      scratch.liveAppliedOpenWorld = openWorld
      scratch.liveAppliedRegion = residencyRegion
    end
    -- A scalar sentinel deliberately makes the next non-scratch/native-world
    -- live key differ even if it returns to the exact Johto map seen before
    -- Kanto. Do NOT retain the scratch table here: RETURN TO JOHTO must be able
    -- to release every Kanto map/mesh reference even if 3D is disabled before
    -- the native world performs another prefetch.
    lastLiveKey = "__stadium_scratch_live__"
    lastOpenWorld = openWorld
    lastResidencyRegion = residencyRegion
  else
    -- Native/non-scratch callers retain the historical string signature.
    local liveKey = residencyRegion .. "|"
      .. (openWorld and "open|" or "stream|") .. state.map.id
    for _, nb in ipairs(neighbors) do
      if live[nb.map.id] then liveKey = liveKey .. "|" .. nb.map.id end
    end
    if liveKey ~= lastLiveKey then
      local regionChanged = lastResidencyRegion ~= nil
        and residencyRegion ~= lastResidencyRegion
      local trimFarNow = regionChanged or (lastOpenWorld == true and not openWorld)
      lastLiveKey = liveKey
      lastOpenWorld = openWorld
      lastResidencyRegion = residencyRegion
      ChunkMesher.setLive(live, trimFarNow)
      TerrainAtlas.setLive(live)
    end
  end

  -- Prebuild nearby native-Johto BODY sectors into the persistent cache before
  -- they become visible. Kanto has its own whole-region scheduler, so this is
  -- intentionally a no-op there.
  VoxelScene._scheduleNeighborDiskWarm(state, neighbors)

  -- masks: where connected neighbour BODIES sit, so each full map's border
  -- ring is suppressed under the maps touching it. Kanto's shared-body mode
  -- never draws those synthetic FULL aprons, so v0.3.59 skips the entire
  -- placement/mask construction path there instead of allocating dead tables
  -- at presentation FPS.
  local sharedBodies = state._stadiumSharedWorldBodies == true
  local masks
  if not sharedBodies then
    if openWorld then
      masks = openWorldFullMasks(state, { map = state.map, ox = 0, oy = 0 })
    else
      masks = {}
      for _, nb in ipairs(neighbors) do
        if nb.depth == nil or nb.depth <= 1 then
          masks[#masks + 1] = { nb.ox, nb.oy,
                                nb.ox + nb.map.def.width * 32,
                                nb.oy + nb.map.def.height * 32 }
        end
      end
    end
  end

  -- Builds are asynchronous (ChunkMesher.pump runs in the pipeline's
  -- update): request what this frame wants and draw what is ready.
  -- The current map draws its body-only mesh while the full one (the
  -- border ring) is still building -- a seam crossing promotes a
  -- neighbour whose body is already cached, and the ring pops in a few
  -- frames later, mostly hidden behind the map just left. A neighbour
  -- missing its body-only mesh draws its cached FULL mesh instead -- a
  -- crossing demotes the map just left, and it must not vanish from
  -- behind the player while its body variant builds; its ring is
  -- already masked out under this map's body, so the stand-in is safe.
  -- The water surface rides along with whichever variant answers: it was
  -- cut out of that build's own geometry (ChunkMesher.pair), so the two
  -- always come from the same slot and a lake is never drawn twice or left
  -- as a hole.
  -- Kanto's persistent BODY cache is also the instant stand-in for direct
  -- warps / KANTO FREE ROAM resumes that did not approach this map through a
  -- visible seam. Queue BODY first so a disk hit can land in one cooperative
  -- upload pass; the exact FULL mesh remains urgent and replaces it as soon as
  -- its apron/seam variant is ready.
  if state._stadiumYellowKanto == true and ChunkMesher.diskCacheEnabled
      and ChunkMesher.diskCacheEnabled() then
    ChunkMesher.request(state.map, true, nil, true)
  end
  if sharedBodies then
    -- v0.3.42 Kanto shares one connected world-space.  A FULL mesh contains
    -- this map's synthetic border/apron; drawing one for every Yellow map is
    -- what produced the enormous repeated rock/tree belts.  Render the actual
    -- authored bodies only and stitch them with the already-solved neighbour
    -- offsets, exactly like one continuous world component.
    ChunkMesher.request(state.map, true, nil, true)
  else
    ChunkMesher.request(state.map, false, masks, true)
  end
  local terrain, water = ChunkMesher.pair(state.map, sharedBodies)
  if not terrain and not sharedBodies then
    terrain, water = ChunkMesher.pair(state.map, true)
  end
  local nbMesh = scratch
    and VoxelScene._scratchIndexed(scratch, "nbMesh", #neighbors) or {}
  local nbWater = scratch
    and VoxelScene._scratchIndexed(scratch, "nbWater", #neighbors) or {}
  local detailReady = scratch
    and VoxelScene._scratchIndexed(scratch, "detailReady", #neighbors) or {}
  local culled = 0
  for i, nb in ipairs(neighbors) do
    local visible
    if visibleFlags then visible = visibleFlags[i] == true
    else visible = neighborVisible(state, nb) end
    if not visible then
      culled = culled + 1
      -- A direct/predicted sector should be READY before the camera reaches the
      -- seam. Build its cheaper body mesh cooperatively while it is still
      -- offscreen; once visible/open-world the full bordered mesh is requested
      -- and can temporarily draw this already-finished body instead of popping
      -- in only after the player starts walking into it.
      if nb.prefetch == true or (tonumber(nb.depth) or 99) <= 1 then
        -- v0.3.32 persistent-cache path: Kanto prefetches BOTH the cheap BODY
        -- stand-in and the exact FULL/seam-masked mesh while the sector is
        -- still offscreen. BODY normally comes straight from the background
        -- disk warmer; FULL then finishes before the camera reaches the seam.
        -- This deliberately spends more desktop CPU ahead of time to remove
        -- zone pop rather than waiting for visibility to trigger the expensive
        -- variant for the first time.
        ChunkMesher.request(nb.map, true, nil, false)
        if openWorld and not sharedBodies and state._stadiumYellowKanto == true
            and ChunkMesher.diskCacheEnabled
            and ChunkMesher.diskCacheEnabled() then
          local nbMasks = openWorldFullMasks(state, nb)
          ChunkMesher.request(nb.map, false, nbMasks, false)
        end
      end
      nbMesh[i], nbWater[i] = nil, nil
    elseif openWorld and not sharedBodies then
      -- Full meshes on all connected maps that can contribute to this camera.
      -- from the old one-ring streamer: body-only meshes have no border/apron,
      -- so a world-scale camera exposes empty void at the outside perimeter.
      -- Each map gets masks for its own connected seams and retains its outer
      -- voxel ring everywhere else.
      local nbMasks = openWorldFullMasks(state, nb)
      ChunkMesher.request(nb.map, false, nbMasks, nb.urgent == true)
      nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, false)
      if not nbMesh[i] then
        -- A previously cached body mesh is still useful while the full variant
        -- cooks; use it temporarily instead of dropping the ENTIRE scene back
        -- to native 2D. The full ring replaces it automatically when ready.
        nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, true)
      end
    else
      -- Shared-world Kanto and ordinary non-open-world neighbours both use
      -- authored BODY geometry here; no per-map synthetic apron is resident.
      ChunkMesher.request(nb.map, true, nil, nb.urgent == true)
      nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, true)
      if not nbMesh[i] and not sharedBodies then
        nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, false)
      end
    end
  end
  -- Record exactly which far maps have drawable terrain THIS frame. Every
  -- later terrain/figure/grass/shadow loop consults this, so one map still
  -- building (or one bad far-map asset) cannot take the proven current 3D
  -- world down with it. This directly prevents the all-flat fallback seen in
  -- v0.2.46 while the full region is warming.
  state._stadiumNeighborReady = nbMesh
  for i, nb in ipairs(neighbors) do
    if nbMesh[i] and neighborDetailVisible(state, nb) then
      detailReady[i] = nbMesh[i]
    end
  end
  state._stadiumNeighborDetailReady = detailReady
  state._stadiumCulledNeighbors = culled
  VoxelScene.culledNeighbors = culled
  Voxel.ready = terrain ~= nil
  return terrain, nbMesh, water, nbWater
end

-- Capture every entity's pose for this frame. pose() advances the hop /
-- surf bob / spinner timers, so it must be called EXACTLY once per entity
-- per frame -- the sun pass and the character pass then read the same
-- answer instead of disagreeing by a tick. Ghost NPCs live on a neighbour
-- map, so their position, ground lookup and palette all belong to that
-- map. pose() returns the VISUAL y (ledge hops arc it, surfing bobs it);
-- the difference from the entity's base y becomes vertical LIFT in 3D, so
-- a hop rises off the ground instead of sliding north.
-- Returns the pose list and, separately, the PLAYER's entry in it (nil
-- during a Fly animation, which draws the player itself and is skipped
-- below). Only that one entry gets the see-through treatment: NPCs and the
-- ghosts standing on a neighbour map are left to honest occlusion, because
-- it is only your own character you cannot afford to lose behind a roof.
local function actorVisible(state, px, py)
  local view = state and state._stadiumCullView
  if not view then return true end
  if view.actorPad == nil then
    VoxelScene._prepareCullView(view, view.cx, view.cy, view.vw, view.vh)
  end
  px, py = tonumber(px) or 0, tonumber(py) or 0
  return px + 24 >= view.actorX1 and px - 24 <= view.actorX2
     and py + 32 >= view.actorY1 and py - 32 <= view.actorY2
end

local function followerEntity(e)
  return type(e) == "table" and (e.wildsFollower == true or e.isFollower == true
    or e.isPokemonFollower == true or e.pokepcTrailer == true
    or e._wildsFollowerSpecies ~= nil or e._pokepcFollowerSpecies ~= nil)
end

local function followerLift(state, e, vy)
  local lift = (tonumber(e and e.py) or 0) - (tonumber(vy) or tonumber(e and e.py) or 0)
  if not followerEntity(e) then return lift end
  -- Follower sheets for serpentine/levitating species often draw the artwork
  -- several pixels above the 2D tile. That is a sprite-composition offset, not
  -- real world altitude. Preserve real ledge hops and water bobbing, but ground
  -- ordinary land followers so Gyarados/Haunter/etc. do not float in 3D.
  if e.jumping == true or e.hopping == true then return lift end
  -- Ghost callers already have the foreign map itself. Accept either a render
  -- state or a map so Kanto does not allocate `{ map = ... }` once per ghost.
  local map = state and (state.map or (state.def and state))
  if map and type(map.isWaterCell) == "function" and e.cellX and e.cellY then
    local ok, water = pcall(map.isWaterCell, map, e.cellX, e.cellY)
    if ok and water == true then return lift end
  end
  return 0
end

local function posesOf(state, spriteColors)
  local colors = spriteColors(state.map)
  local scratch = state and state._stadiumFrameScratch
  local posed = VoxelScene._scratchArray(scratch, "posed")
  local me = nil
  for _, g in ipairs(state.ghosts or {}) do
    -- pose() still runs exactly once so off-screen hops/spinners keep time; the
    -- renderer simply avoids building ground/palette/draw work for a card that
    -- cannot contribute to this camera.
    local sprite, vx, vy, facing, phase, flip = g.npc:pose()
    local px, py = vx + g.ox, g.npc.py + g.oy
    if actorVisible(state, px, py) then
      local pi = #posed + 1
      local p = VoxelScene._scratchRecord(scratch, "posePool", pi)
      p.sprite, p.px, p.py = sprite, px, py
      p.facing, p.phase, p.flip = facing, phase, flip
      p.gh = groundAt(g.map or state.map, g.npc.cellX, g.npc.cellY)
      p.lift, p.colors = followerLift(g.map or state.map, g.npc, vy), spriteColors(g.map or state.map)
      p.isPlayer = nil
      p.stadiumVisualMoving, p.stadiumVisualAnimDist = nil, nil
      p.stadiumMoveWorldX, p.stadiumMoveWorldZ = nil, nil
      posed[pi] = p
    end
  end
  for _, e in ipairs(state.entities or {}) do
    if not (state.flyAnim and e == state.player)
       and not e._stadiumCaptureHidden then
      local sprite, vx, vy, facing, phase, flip = e:pose()
      local visible = e == state.player or actorVisible(state, vx, e.py)
      if visible then
        local pi = #posed + 1
        local p = VoxelScene._scratchRecord(scratch, "posePool", pi)
        p.sprite, p.px, p.py = sprite, vx, e.py
        p.facing, p.phase, p.flip = facing, phase, flip
        p.gh, p.lift, p.colors = groundAt(state.map, e.cellX, e.cellY), followerLift(state, e, vy), colors
        p.isPlayer = nil
        p.stadiumVisualMoving, p.stadiumVisualAnimDist = nil, nil
        p.stadiumMoveWorldX, p.stadiumMoveWorldZ = nil, nil
        posed[pi] = p
      end
      if e == state.player and visible then
        me = posed[#posed]
        -- marked so the camera draw can leave the card out in first
        -- person, where it would fill the lens from inside; the SUN pass
        -- reads the same list and deliberately does not check the mark
        me.isPlayer = true
        -- v0.2.14: the free-camera walking bit belongs to THIS rendered world
        -- frame.  Carry it on the captured pose so the external 3D trainer
        -- renderer never has to rediscover Game2.world through a facade that
        -- may still refer to the pre-transition/boot state.
        me.stadiumVisualMoving = state._stadiumFreeMoveActive == true
          and state._stadiumFreeVisualMoving == true
        me.stadiumVisualAnimDist = tonumber(state._stadiumFreeAnimDist) or 0
        me.stadiumMoveWorldX = tonumber(state._stadiumFreeWorldX) or 0
        me.stadiumMoveWorldZ = tonumber(state._stadiumFreeWorldZ) or 0
        -- THIRD PERSON owns continuous px/py directly and intentionally leaves
        -- Gen-2 Player.moving false. That is correct for collision, but pose()
        -- therefore returns the standing frame before this renderer sees the
        -- presentation-only movement bit. Repair the captured PLAYER pose here
        -- so every renderer path (stock/custom sprite card AND external 3D skin)
        -- gets the same walk phase DIORAMA receives from native grid movement.
        if me.stadiumVisualMoving and not state._stadiumLiveBattle then
          -- Tie the 2D card cadence to actual free-roam travel distance.  That
          -- remains live for analogue movement even on hosts where
          -- Player.animClock is not advanced by the continuous controller.
          local q = (tonumber(me.stadiumVisualAnimDist) or 0) % 16
          me.phase = (q >= 4 and q < 12) and 1 or 0
          me.flip = e.stepFlip == true
        elseif not state._stadiumLiveBattle and type(e.walkPhase) == "function" then
          -- DIORAMA/native grid movement: always refresh from Gold/Silver's
          -- public Player walk phase instead of trusting a stale pose capture.
          local okWalk, walk = pcall(e.walkPhase, e)
          if okWalk and walk ~= nil then me.phase = walk end
          me.flip = e.stepFlip == true or me.flip == true
        end
        if me.sprite and type(me.sprite.def) == "table"
           and (tonumber(me.sprite.def.frames) or 1) > 1 then
          me.sprite.def.walker = true
        end
      end
    end
  end
  VoxelScene._trimScratchPool(scratch, "posePool", #posed)
  return posed, me
end

-- ------- the glint's drive
--
-- A reflection is something the VIEWPOINT does, so the window glint is fed
-- by the camera's own travel rather than by a clock: its phase advances
-- with distance covered and its strength fades in over a few steps of
-- walking and back out within a beat of standing still. Stand still and
-- the glass is still; move and the light crosses it.
-- The rate is slow on purpose: the sweep pattern lives in the pane's own
-- texels (see the scene shader), so this is a FRACTION of a texel per world
-- pixel walked -- one full pass of the glint across a pane per eight or so
-- cells of travel, with no frame ever jumping it far enough to strobe.
VoxelScene.GLINT_RATE = 0.05     -- radians of sweep per world pixel travelled
VoxelScene.GLINT_IN = 0.12      -- strength gained per moving frame
VoxelScene.GLINT_OUT = 0.08     -- and lost per resting frame

function VoxelScene.glintStep(g, cx, cy)
  local dist = 0
  if g.x then
    dist = math.abs(cx - g.x) + math.abs(cy - g.y)
  end
  g.x, g.y = cx, cy
  g.phase = ((g.phase or 0) + dist * VoxelScene.GLINT_RATE) % (2 * math.pi)
  if dist > 0.05 then
    g.amp = math.min(1, (g.amp or 0) + VoxelScene.GLINT_IN)
  else
    g.amp = math.max(0, (g.amp or 0) - VoxelScene.GLINT_OUT)
  end
  return g
end

local glint = {}

-- ------- the cast
--
-- Everybody standing on the map: the walkers, and the authored FIGURES the
-- tileset draws into its own furniture (they ARE characters as far as the
-- artwork is concerned, just ones drawn by the tileset instead of by a
-- sprite sheet, so they get the same lean and the same camera-ward pull).
--
-- One function because it is drawn TWICE and the two must be identical: once
-- into the frame, and once into the water's reflection copy (see drawWater --
-- Gen 1 draws people over the world, and water is world, so the cast cannot
-- be composited before the water it has to appear in).
--
-- Characters carry no wireframe out here, whatever the V-GRID row says. The
-- seams are what makes the WORLD read as built out of voxels, and the people
-- walking around in it are the one thing that should read as drawn instead --
-- a grid over a 16x16 sprite lands a line every couple of display pixels and
-- turns a face into a mesh. (The battle pass makes the opposite call for its
-- own combatants, deliberately -- see BattleBillboard.)
--
-- Sprite sheets until the figure pass: their texture coordinates mean
-- nothing to the tileset-shaped glass mask, so the glass is off or the
-- panes' atlas positions stripe the cast with lamplight at night.
local function drawCast(state, posed, atlasFor)
  Voxel3D.glass(false)
  Voxel3D.seams(false)
  -- Characters, normally depth-tested: the camera-ward pull inside
  -- drawEntity resolves the lean-over-the-wall-in-front case, and a
  -- character genuinely behind a building is far deeper and loses the
  -- test, so buildings and trees really occlude.
  --
  -- In first person two of them change: the player's own card is left out
  -- (the eye is standing in it), and every other card wears the frame its
  -- pose SHOWS this eye (viewFacing) rather than the one it shows the
  -- south. Both run through here, so the water's reflection copy -- drawn
  -- by this same function -- agrees with the frame to the pixel.
  local hideMe = FirstPerson.hidePlayer()
  for _, p in ipairs(posed) do
    if not (p.isPlayer and hideMe) then
      drawEntity(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,
                 p.colors, p.lift, playerCardScale(p))
    end
  end
  -- back on for everything textured from the atlas again -- figures, grass
  -- and flowers all sample it, where the mask's coordinates are honest
  Voxel3D.glass(true)
  -- Figures after the walkers, so a player standing in front of the couch
  -- wins the overlap -- the order the flat game draws them in.
  local figPull = billboardPull()
  eachFigure(state.map, 0, 0, function(mesh, model, caster)
    Voxel3D.draw(mesh, atlasFor(state.map), model, figPull,
                 ShadowMap.snug(caster))
  end, state._stadiumCullView)
  for i, nb in ipairs(state.neighbors or {}) do
    if readyNeighbor(state, i) then
      eachFigure(nb.map, nb.ox, nb.oy, function(mesh, model, caster)
        Voxel3D.draw(mesh, atlasFor(nb.map), model, figPull,
                     ShadowMap.snug(caster))
      end, state._stadiumCullView)
    end
  end
  -- and the seams are back on for the terrain art that follows: grass and
  -- flowers are the world's own drawing, not people
  Voxel3D.seams(true)
end

-- ------- the water pass
--
-- Between the terrain and everything that stands on it, because water is a
-- MIRROR and a mirror can only reflect what is already down: the ground, the
-- shoreline, the trees and buildings behind it, and the sky the frame opened
-- with.
--
-- THE CAST IS THE AWKWARD ONE, and it is settled by drawing it twice. Gen 1
-- draws people over the world and water is world, so a surfing player has to
-- composite OVER the water they are sitting on -- which puts them after it,
-- and a reflection can only hold what came before it. So `cast` is painted
-- into the reflection copy alone (Voxel3D.beginWater), where it is in the
-- picture the water reflects and not yet in the picture the water is drawn
-- into. Both draws go through drawCast, so they cannot come out different.
--
-- The ray march finds them the honest way round: a sprite is not in the
-- DEPTH buffer at that point, so a ray aimed at one passes through to the
-- terrain standing behind it and reads the copy there -- where the sprite is
-- already painted. The reflection lands a hair off the sprite's own depth
-- and exactly on its colour, which at a lake's worth of ripple is the same
-- picture.
--
-- `draws` is a list of { mesh, texture, model }. Nothing is a special case:
-- with the row OFF, no depth texture to read, or a shader that would not
-- build, the same meshes go through the ordinary scene shader and come out
-- as the flat animated water this mode always drew.
-- The overworld's alone: the staged battle draws its water plain, always --
-- its placed camera reads this pass wrong, and a stage set wants painted
-- water anyway (see BattleScene, where the choice is argued).
-- ------- and why the flat draw happens FIRST while the world is curved
--
-- The reflective pass writes no depth -- it cannot, the depth canvas is
-- detached for the length of it so the shader can READ it -- and it does its
-- own depth test against that texture instead. That test asks whether
-- something opaque is in front, and it answers correctly for every case but
-- one: WATER IN FRONT OF WATER. Nothing puts water in the depth buffer, so
-- no lake can hide another, and the pass simply paints them in mesh order.
--
-- On a flat world that never matters: every surface lies in the one plane
-- at its own recessed height, and a farther sheet always lands farther down
-- the screen. THE WORLD CURVE ENDS THAT. The bend drops the world by the
-- square of its distance, so the far side of the map swings down and back
-- up into the near field of view -- and a sheet of sea a hundred and fifty
-- tiles away, drawn later in the same mesh, paints straight over the pond
-- at the player's feet. Not a reflection of the far shore: the far shore
-- itself, rasterised on top of the water in front of you.
--
-- So WHILE THE CURVE IS ON, the meshes go down flat first, through the
-- ordinary scene shader with depth writes on, and the reflective pass draws
-- over the top of what survived: the depth buffer now holds the water
-- surface, so the pass's own test throws the far sheet away, and the
-- reflection COPY holds it too, so a ray grazing another part of the lake
-- reads water rather than the void behind it.
--
-- With the curve OFF the prepass is not just unnecessary, it is a LIABILITY,
-- and it stays off -- the reflective pass tests only against terrain, as it
-- always did. Painting the surface into the depth texture turns the pass's
-- test into a comparison of the surface against ITSELF, which asks the two
-- rasterisations to agree to within interpolation error -- and on mobile
-- GPUs they don't reliably (that fight is what put the Android port back on
-- flat water). Confined to the curve there is no regression to reach: the
-- flat world never had the far-shore bug in the first place.
function VoxelScene.drawWater(draws, cast)
  -- prepass only under the bend; see the header
  local curved = (Voxel3D.curveK or 0) > 0
  if curved then
    for _, d in ipairs(draws) do
      Voxel3D.draw(d[1], d[2], d[3])
    end
  end
  local plain = not curved
  local reflectionLevel = Water.level()
  if reflectionLevel > 0 and Voxel3D.depthReadable() then
    -- SKY / FAST never samples the reflected world. Skip both the full-scene
    -- mirror copy and the duplicate character/figure draw; only FULL SSR pays
    -- for those. The depth texture remains attached/detached exactly as before
    -- so shore/building occlusion is unchanged.
    local fullWorldReflection = reflectionLevel >= 2
    local mirror, depth = Voxel3D.beginWater(fullWorldReflection and cast or nil,
                                             fullWorldReflection)
    local w, h = Voxel3D.size()
    local ok = mirror and depth and Water.begin({
      reflect = mirror, depth = depth,
      vp = Voxel3D.vp, eye = Voxel3D.eye, curve = { Voxel3D.curveX or 0,
                                                    Voxel3D.curveZ or 0,
                                                    Voxel3D.curveK or 0 },
      screen = { w, h }, cell = Voxel3D.cell, fov = Voxel3D.fovY,
      skyEdge = Voxel3D.skyEdge, grid = VoxelGrid.enabled(),
      lookFlat = Voxel3D.lookFlat, descent = Voxel3D.descent,
    })
    if ok then
      for _, d in ipairs(draws) do
        Water.draw(d[1], d[2], d[3])
      end
      Water.finish()
      plain = false
    end
    -- Unconditionally, and OUTSIDE the success branch: beginWater unbinds
    -- the shader and the depth mode BEFORE it can discover it cannot go on,
    -- so a frame that bails halfway through has to be put back together
    -- exactly like one that succeeded -- otherwise every pass after it runs
    -- with no shader and no depth test.
    Voxel3D.endWater()
  end
  -- the fallback flat draw -- unless the curve's prepass already put the
  -- same meshes down, in which case a bailed frame is already whole
  if plain then
    for _, d in ipairs(draws) do
      Voxel3D.draw(d[1], d[2], d[3])
    end
  end
end

-- A stamp of everything the sun pass depends on. Nothing in it moving
-- means the shadow map it produced last frame is still exactly right, and
-- redrawing the whole world from the sun would buy nothing -- which is
-- most of a dialog, a menu, or any moment standing still.
local sigBuf = {}
local function shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  local n = 0
  local function put(v)
    n = n + 1
    sigBuf[n] = v
  end
  -- quarter-pixel camera granularity: the light frustum is snapped to
  -- whole texels anyway, each a third of a world pixel
  put(math.floor(cx * 4))
  put(math.floor(cy * 4))
  -- the view size and the camera PITCH are both what the light frustum is
  -- fitted to (a lower camera sees further north, so the box grows), so a
  -- zoom step, a window resize or a rung change invalidates the map even
  -- standing perfectly still
  put(vw); put(vh)
  put(math.floor((V.require("VoxelState").angle or 0) * 512))
  -- the sun itself: the cycle swings the shear as the clock runs, and a map
  -- lit from somewhere new must be redrawn from there too. Quantised by the
  -- rig's own step (DayNight.rigTime), so a running cycle redraws the map a
  -- few times a minute rather than every frame.
  put(math.floor(ShadowMap.KX * 128))
  put(math.floor(ShadowMap.KZ * 128))
  -- and the first-person head: the box is fitted around wherever it looks
  -- and the sprite cards swap frames as it circles them, so a turn on the
  -- spot re-fits and redraws exactly like a camera move ("" outside 1ST)
  put(FirstPerson.signature())
  put(tostring(terrain))
  for i = 1, #nbMesh do put(tostring(nbMesh[i])) end
  for _, p in ipairs(posed) do
    put(p.sprite.def.image)
    put(p.px); put(p.py); put(p.gh); put(p.lift or 0)
    put(p.facing); put(p.phase); put(p.flip and 1 or 0)
  end
  for i = n + 1, #sigBuf do sigBuf[i] = nil end
  return table.concat(sigBuf, ",")
end

-- The sun pass: render the scene once from the light, so the main pass can
-- ask any fragment whether the sun reached it. Every caster the main pass
-- draws goes in -- the terrain mesh, which is where buildings, trees,
-- ledges, signs and every prop live, plus one UPRIGHT card per character
-- (Voxel3D.casterMatrix; the leaning slab is a trick for the camera, not
-- for the sun) -- so shadows land on walls, roofs, ledges and passing NPCs
-- as readily as on the floor.
--
-- Runs BEFORE Voxel3D.beginScene, because canvases do not nest. Grass is
-- left out on purpose: thousands of tufts would cast a speckle no bigger
-- than the pixels it lands on, at the cost of the mesh being drawn twice.
local function castShadows(state, terrain, nbMesh, posed, cx, cy, vw, vh,
                           atlasFor, water, nbWater, battleCards, battleToken)
  if not ShadowMap.available() then return end
  local sig = shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  local ocean = state and state._stadiumOcean
  local oceanHere = oceanVisible(ocean, cx, cy, vw, vh)
  if oceanHere and ocean and ocean.mesh then sig = sig .. "|ocean" .. tostring(ocean.mesh) end
  -- a staged fight's pics move every frame the animation does, and the sun
  -- has to follow them (VR frames only; see render)
  if battleToken then sig = sig .. "|btl" .. tostring(battleToken) end
  if not ShadowMap.stale(sig) then return end

  -- v0.4.07 controller-look stability. FirstPerson.signature() includes yaw
  -- because a settled free-camera view deserves a refitted sun frustum, but
  -- rebuilding that full shadow pass on EVERY right-stick sample can hit a
  -- driver/mesh failure or a severe forest/caster spike exactly while the
  -- player is looking around. Reuse the last valid sun map while analog look
  -- is moving; the first frame after the stick settles refreshes it once.
  -- This changes only shadows -- never the camera, terrain or 3D renderer.
  if type(FirstPerson.analogLookActive) == "function"
      and FirstPerson.analogLookActive() and ShadowMap.active() then
    VoxelScene.shadowLookDeferrals = (VoxelScene.shadowLookDeferrals or 0) + 1
    return
  end

  local okBegin, beganOrErr = pcall(ShadowMap.begin, cx, cy, vw, vh)
  if not okBegin then
    if type(ShadowMap.abort) == "function" then pcall(ShadowMap.abort) end
    VoxelScene.shadowRefreshErrors = (VoxelScene.shadowRefreshErrors or 0) + 1
    VoxelScene.lastShadowError = tostring(beganOrErr)
    return
  end
  if not beganOrErr then return end
  local okShadow, shadowErr = pcall(function()
    ShadowMap.draw(terrain, atlasFor(state.map), nil)
    for i, nb in ipairs(state.neighbors or {}) do
      if nbMesh[i] and readyNeighbor(state, i) then
        ShadowMap.draw(nbMesh[i], atlasFor(nb.map),
                       VoxelScene._neighborModel(nb))
      end
    end
    -- The water surface, which the terrain mesh no longer carries (it is its
    -- own reflective pass now -- see Water). The sun still has to see it, or
    -- the map the light records has a hole at every lake and the frustum's
    -- far plane answers for the surface a shoreline tree's shadow falls on.
    ShadowMap.draw(water, atlasFor(state.map), nil)
    for i, nb in ipairs(state.neighbors or {}) do
      if nbWater and nbWater[i] and readyNeighbor(state, i) then
        ShadowMap.draw(nbWater[i], atlasFor(nb.map),
                       VoxelScene._neighborModel(nb))
      end
    end
    -- v0.2.82's optional world ocean is already in world coordinates and sits
    -- below native lake surfaces. Put it in the light pass too so the shadow
    -- frustum records a real surface beyond the stitched land instead of its
    -- far plane.
    if oceanHere and ocean and ocean.mesh and ocean.texture then
      ShadowMap.draw(ocean.mesh, ocean.texture, ocean.model)
    end
    -- flower billboards live outside the terrain mesh (they draw after the
    -- characters, pulled -- see render), but the sun still sees them: a
    -- handful of cutouts per meadow, unlike the grass left out below.
    -- Every thin card from here down is SNUGGED toward the sun along its own
    -- ray (ShadowMap.snug) so its shadow keeps contact with its feet instead
    -- of starting a bias-width away.
    ShadowMap.draw(ChunkMesher.flowers(state.map), atlasFor(state.map),
                   ShadowMap.snug(nil))
    for i, nb in ipairs(state.neighbors or {}) do
      if readyNeighbor(state, i) then
        ShadowMap.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                       ShadowMap.snug(VoxelScene._neighborModel(nb)))
      end
    end
    -- From here down it is the CAST, marked as such in the map (see
    -- ShadowMap.sprites) so water can decline them: everything the world casts
    -- still shades a lake, a silhouette of somebody standing beside it does
    -- not. Ground, roofs and the characters themselves take them as before.
    ShadowMap.sprites(true)
    -- authored figures cast too, for the same reason the flowers do: a
    -- handful of cards per map, and a person with no shadow reads as pasted on
    eachFigure(state.map, 0, 0, function(mesh, _, caster)
      ShadowMap.draw(mesh, atlasFor(state.map), ShadowMap.snug(caster))
    end, state._stadiumCullView)
    for i, nb in ipairs(state.neighbors or {}) do
      if readyNeighbor(state, i) then
        eachFigure(nb.map, nb.ox, nb.oy, function(mesh, _, caster)
          ShadowMap.draw(mesh, atlasFor(nb.map), ShadowMap.snug(caster))
        end, state._stadiumCullView)
      end
    end
    for _, p in ipairs(posed) do
      local def = p.sprite.def
      -- viewFacing, exactly as the camera draw picks it (see viewFacing for
      -- why the two passes must agree): in first person the sun's card
      -- swaps frame as the eye circles, which costs a redraw the signature
      -- already charges for (FirstPerson.signature) and keeps a card from
      -- fringing against a mirror-flipped record of itself
      local frame, mirror = frameFor(def, viewFacing(p), p.phase, p.flip)
      local mesh = SpriteBillboards.shadowQuad(def, frame)
      if mesh then
        ShadowMap.draw(mesh, p.sprite:resolveImage(),
                       ShadowMap.snug(
                         casterMatrixScaled(p.px, p.py, p.gh + (p.lift or 0),
                                            mirror, playerCardScale(p))))
      end
    end
    -- a staged fight's mons (VR frames only): the same cards the eye pass
    -- stands on the arena, snugged like every thin card, marked as the cast
    -- so the water can decline them like everybody else's silhouette
    for _, card in ipairs(battleCards or {}) do
      ShadowMap.draw(BattleBillboard.mesh(), card.tex, ShadowMap.snug(card.model))
    end
    -- Gold v0.1.89 keeps battles in the normal overworld camera. The Stadium
    -- combatants therefore belong to this ordinary world shadow pass instead of
    -- BattleScene's separate staged pass.
    if state and state._stadiumLiveBattle then
      pcall(function() V.require("Stadium").cast(ShadowMap) end)
    end
    ShadowMap.sprites(false)

  end)
  if okShadow then
    ShadowMap.finish(sig)
  else
    if type(ShadowMap.abort) == "function" then pcall(ShadowMap.abort) end
    VoxelScene.shadowRefreshErrors = (VoxelScene.shadowRefreshErrors or 0) + 1
    VoxelScene.lastShadowError = tostring(shadowErr)
    -- Shadows are optional presentation. The main Voxel3D pass proceeds in
    -- this same frame with the blank/decal fallback instead of bubbling the
    -- failure out to GoldPipelineBridge, which would expose native 2D.
  end
end

-- Render the world. Without `eyes`, one frame into one canvas -- the flat
-- path every rung has always taken. With `eyes` -- a list of
-- { camera, w, h, slot, adopt } records, plus optional cx/cy for the
-- scene centre -- the same frame is drawn once per entry and the list of
-- canvases comes back: the VR path, two eyes over one shared shadow map,
-- pose capture and glint step.
function VoxelScene.render(state, w, h, vw, vh, paletteFor, eyes)
  local cam = state.camera
  local cx, cy = cam.x + vw / 2, cam.y + vh / 2
  local frameScratch = state and state._stadiumFrameScratch
  if frameScratch then
    state._stadiumCullView = VoxelScene._prepareCullView(
      frameScratch.cullView, cx, cy, vw, vh)
  else
    state._stadiumCullView = VoxelScene._prepareCullView({}, cx, cy, vw, vh)
  end

  -- With nothing cached at all (the first frame of a fresh toggle),
  -- return nil: the engine keeps the 2D path for the frame and
  -- Voxel.ready holds the camera tween at flat, so the switch waits
  -- invisibly instead of freezing or tilting an empty stage.
  local terrain, nbMesh, water, nbWater = VoxelScene.prefetch(state)
  if not terrain then return nil end

  -- the hour's light, before anything is cast or drawn: point the shared
  -- rig at the clock (or at noon, indoors -- a cave at midnight is exactly
  -- as dark as a cave at noon) and set the tint the scene shader multiplies
  -- every surface by. A CANOPY map (Viridian Forest) is the case between:
  -- the rig stays at noon and no sky is painted, but the hour's tint still
  -- falls through the leaves -- night reaches a forest floor.
  local outdoor = state.map.def and Map.isOutdoor(state.map.def) or false
  DayNight.applyRig(outdoor)
  do
    local okWeather, Weather = pcall(V.require, "Weather")
    if okWeather and type(Weather) == "table" and type(Weather.setContext) == "function" then
      pcall(Weather.setContext, outdoor, state.map)
    end
  end
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(state.map))
  -- Yellow Rock Tunnel darkness is presentation-local to the Kanto companion
  -- world. Multiply the normal day/night light instead of swapping shaders or
  -- palettes, so FLASH can lift it instantly without rebuilding any sector.
  if state and type(state._stadiumDarkTint) == "table" then
    local t, d = Voxel3D.tint or { 1, 1, 1 }, state._stadiumDarkTint
    if frameScratch then
      local tint = frameScratch.darkTint
      tint[1] = (tonumber(t[1]) or 1) * (tonumber(d[1]) or 1)
      tint[2] = (tonumber(t[2]) or 1) * (tonumber(d[2]) or 1)
      tint[3] = (tonumber(t[3]) or 1) * (tonumber(d[3]) or 1)
      Voxel3D.tint = tint
    else
      Voxel3D.tint = {
        (tonumber(t[1]) or 1) * (tonumber(d[1]) or 1),
        (tonumber(t[2]) or 1) * (tonumber(d[2]) or 1),
        (tonumber(t[3]) or 1) * (tonumber(d[3]) or 1),
      }
    end
  end
  -- and the window glass: the tileset's own panes (found in its art --
  -- GlassMask), lit after dark. Outdoors only, like everything the clock
  -- touches, which also keeps any pane-shaped art in an interior tileset
  -- from picking up a glint.
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(state.map.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  local g = VoxelScene.glintStep(glint, cx, cy)
  Voxel3D.glassPhase, Voxel3D.glassGlint = g.phase, g.amp

  local atlasCache = frameScratch and frameScratch.atlasCache or {}
  if frameScratch then for k in pairs(atlasCache) do atlasCache[k] = nil end end
  local function atlasFor(map)
    if not map then return nil end
    local key = map.id or tostring(map)
    if atlasCache[key] ~= nil then return atlasCache[key] or nil end
    local ok, atlas = pcall(TerrainAtlas.forMap, map, modeColors(paletteFor, map))
    if not ok or not atlas then
      -- GoldVoxelBridge already attached the exact live Gen-2 tileset atlas to
      -- map.renderer.image. It is a safe static texture fallback if an animated
      -- per-map atlas cannot be created for one distant map.
      atlas = map.renderer and map.renderer.image or nil
    end
    atlasCache[key] = atlas or false
    return atlas
  end

  -- sprite palettes only exist in the SGB modes; under RED++ the OBP bake
  -- inside sprite:resolveImage() already colors the sheet
  local function spriteColors(map)
    if PaletteFX.usesGbcPack() then return nil end
    return modeColors(paletteFor, map)
  end

  local posed, me = posesOf(state, spriteColors)

  -- The first-person rig, built (or blended) for this frame and handed to
  -- Voxel3D BEFORE either pass runs: the sun's box is fitted around this
  -- camera, and every card matrix asks it which way to turn. With the
  -- blend fully out the call clears the placed camera and the orbit is
  -- exactly what it always was. The scene centre it returns walks from
  -- the orbit's view centre into the head, so the curve's focus and the
  -- depth reference follow the camera actually in charge.
  --
  -- A VR frame skips all of it: the caller brought its own cameras, and
  -- its own idea of the scene centre with them.
  if not eyes then
    -- ThirdPerson's boom collision must use the map graph THIS frame renders,
    -- not whatever world object happens to remain installed on Game2.  The
    -- distinction matters in Yellow/Kanto free roam, where Johto intentionally
    -- stays resident underneath while this state points at a foreign Kanto map.
    if ThirdPerson and type(ThirdPerson.setWorldContext) == "function" then
      if frameScratch then
        local wc = frameScratch.worldContext
        wc.map, wc.neighbors = state.map, state.neighbors or {}
        ThirdPerson.setWorldContext(wc)
      else
        ThirdPerson.setWorldContext({ map = state.map, neighbors = state.neighbors or {} })
      end
    end
    local fpRig, fpCx, fpCy = FirstPerson.frame(me, cx, cy, vw, vh)
    if fpRig then cx, cy = fpCx, fpCy end
    -- Gold live-overworld battles get a real Stadium-style orbit around both
    -- combatants. It deliberately overrides the free-roam placed camera only
    -- while a live battle session exists; menus/ordinary overworld remain on
    -- FirstPerson/ThirdPerson or the diorama orbit exactly as before.
    local battleRig, battleCx, battleCy = BattleCinematic.frame(1 / 60)
    if battleRig then
      Voxel3D.camera = battleRig
      cx, cy = battleCx, battleCy
    end
  elseif eyes.cx then
    cx, cy = eyes.cx, eyes.cy
  end

  -- Live Gold battles render through THIS VoxelScene, not BattleScene. Keep the
  -- arena/ground context here so the terrain and late grass passes can open a
  -- real visibility clearing around the fight. v0.2.28 only enabled the shader
  -- in BattleScene, which is why live Gold trees/bushes were never affected.
  local liveBattleArena, liveBattleGround = nil, nil
  if state and state._stadiumLiveBattle then
    local okCtx, ctx = pcall(function()
      return V.require("OverworldBattle").cameraContext()
    end)
    if okCtx and type(ctx) == "table" and type(ctx.arena) == "table" then
      liveBattleArena = ctx.arena
      liveBattleGround = tonumber(ctx.groundY) or 0
    end
  end

  -- A staged fight, seen by the VR eyes: the flat screen draws the battle
  -- SCREEN while one is up (this pass never runs), but the headset keeps
  -- looking at the world, so the world had better have the fight on it.
  -- Fetched per frame for the sun, and again per EYE in drawScene, because
  -- the cards yaw toward whichever eye is asking.
  local battleCards, battleTex, battleToken = nil, nil, nil
  if eyes then
    local okB, cards, tex, token = pcall(function()
      return V.require("OverworldBattle").worldCards()
    end)
    if okB and cards then
      battleCards, battleTex, battleToken = cards, tex, token
    end
  end

  -- The sun's box, pushed along the first-person look so it covers the
  -- ground THIS camera sees (a no-op at blend zero): the orbit's fit
  -- reaches far north and barely south, which is right for every rung
  -- but a head free to face south.
  local shCx, shCy = FirstPerson.shadowCenter(cx, cy, vh)
  castShadows(state, terrain, nbMesh, posed, shCx, shCy, vw, vh, atlasFor,
              water, nbWater, battleCards, battleToken)

  -- Everything between beginScene and endScene, as one function: the flat
  -- path runs it once, a VR frame runs it once PER EYE -- same posed
  -- list, same shadow map, same glint, so the two eyes can never disagree
  -- about anything but their viewpoint.
  local function drawScene()

  if liveBattleArena then Voxel3D.battleOcclusion(liveBattleArena, liveBattleGround) end
  Voxel3D.draw(terrain, atlasFor(state.map), nil)
  for i, nb in ipairs(state.neighbors or {}) do
    if nbMesh[i] then
      Voxel3D.draw(nbMesh[i], atlasFor(nb.map),
                   VoxelScene._neighborModel(nb))
    end
  end
  if liveBattleArena then Voxel3D.battleOcclusion(nil) end

  -- Without a shadow map because the DRIVER cannot make one, the old flat
  -- decals stand in: ground-only, characters only. SHADOW QUALITY = OFF skips
  -- this block too, so OFF is visually and computationally different.
  -- but better than a world with nothing under anybody. They go down
  -- first, as decals the characters then stand over -- depth-tested
  -- against the terrain just drawn (a shadow behind a building stays
  -- hidden) but never depth-writing, so the grass pass at the end of the
  -- frame still wins its feet-overdraw fights.
  if not Voxel3D.shadowsActive() and not Quality.shadowsOff() then
    Voxel3D.beginShadows()
    for _, p in ipairs(posed) do
      drawShadow(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,
                 p.lift, playerCardScale(p))
    end
    Voxel3D.endShadows()
  end

  -- and the water over the top of it, reflecting everything just drawn plus
  -- the sky the frame opened with (see drawWater).
  --
  -- After the fallback decals deliberately: those are the stand-in drop
  -- shadows for a frame with no shadow map, they write no depth, and a
  -- lake would otherwise wear one as a black smear. Water covers them,
  -- which is the same answer the shadow map's own pass gives (see
  -- ShadowMap.sprites) -- people do not shadow water either way.
  local waterDraws = VoxelScene._scratchArray(frameScratch, "waterDraws")
  if water then
    VoxelScene._waterRow(frameScratch, waterDraws, water, atlasFor(state.map), nil)
  end
  for i, nb in ipairs(state.neighbors or {}) do
    if nbWater and nbWater[i] then
      VoxelScene._waterRow(frameScratch, waterDraws, nbWater[i], atlasFor(nb.map),
        VoxelScene._neighborModel(nb))
    end
  end
  -- The ocean is a single four-vertex plane beneath both regions. Feeding it
  -- through the existing water pass gives it the same sky/world reflections
  -- as native lakes without introducing a second renderer or shader stack.
  local ocean = state._stadiumOcean
  local oceanHere = oceanVisible(ocean, cx, cy, vw, vh)
  if oceanHere and ocean and ocean.mesh and ocean.texture then
    VoxelScene._waterRow(frameScratch, waterDraws, ocean.mesh, ocean.texture, ocean.model)
  end
  VoxelScene.oceanCulled = ocean ~= nil and not oceanHere
  VoxelScene._trimScratchPool(frameScratch, "waterPool", #waterDraws)
  -- the cast goes into the reflection copy only -- see drawWater for why it
  -- cannot be composited yet and why it is drawn through the same function
  -- the real pass below uses
  if #waterDraws > 0 then
    VoxelScene.drawWater(waterDraws, function()
      drawCast(state, posed, atlasFor)
    end)
  end


  -- Sprite sheets from here to the figure pass: their texture coordinates
  -- mean nothing to the tileset-shaped glass mask, so the glass is off or
  -- the panes' atlas positions stripe the cast with lamplight at night
  Voxel3D.glass(false)

  -- The player's silhouette goes down BEFORE the characters, so the only
  -- thing it can meet in the depth buffer is the WORLD -- terrain, buildings,
  -- trees. Drawn after the solid pass it would meet the player's own card
  -- instead, and every fragment of a figure sits behind the one that just
  -- wrote it, so the silhouette would paint over the player at all times.
  -- Every character then draws on top as usual, which leaves the silhouette
  -- showing in exactly one situation: where the world hides them.
  --
  -- Not in first person: the card it silhouettes is the one the camera is
  -- standing inside, and "the world is in front of the player" is every
  -- wall the player faces.
  if me and not FirstPerson.hidePlayer() then
    Voxel3D.beginGhost()
    drawGhost(me)
    Voxel3D.endGhost()
  end

  -- Characters carry no wireframe out here, whatever the V-GRID row says.
  -- The seams are what makes the WORLD read as built out of voxels, and
  -- the people walking around in it are the one thing that should read as
  -- drawn instead -- a grid over a 16x16 sprite lands a line every couple
  -- of display pixels and turns a face into a mesh. (The battle pass makes
  -- the opposite call for its own combatants, deliberately: that is a
  -- staged shot rather than the world being walked around in -- see
  -- BattleBillboard.)
  --
  -- Characters, normally depth-tested: the camera-ward pull inside
  -- drawEntity resolves the lean-over-the-wall-in-front case, and a
  -- character genuinely behind a building is far deeper and loses the
  -- test, so buildings and trees really occlude.
  drawCast(state, posed, atlasFor)
  -- Live Gold battles are rendered by this SAME VoxelScene instead of by a
  -- second arena camera. Their real Stadium models are ordinary world-space
  -- actors here: terrain/buildings can occlude them, weather stays in place,
  -- and the camera never cuts away from the encounter view.
  if state and state._stadiumLiveBattle then
    pcall(function() V.require("Stadium").draw(0) end)
  end
  -- The staged fight's mons, standing on their arena cells in THIS eye's
  -- view (VR frames only; battleTex is nil otherwise). Rebuilt per eye
  -- because the cards yaw toward the eye that is looking. No wireframe
  -- and no glass on them for the reasons BattleBillboard and the battle
  -- pass each argue: the cards are not on the voxel grid, and their
  -- texcoords mean nothing to the tileset's pane mask. The hit flash
  -- rides the same flatten the battle pass uses, held short of solid.
  if battleTex then
    local okB, cards = pcall(function()
      return V.require("OverworldBattle").worldCards()
    end)
    if okB and cards then
      local BattleScene = V.require("BattleScene")
      Voxel3D.glass(false)
      Voxel3D.seams(false)
      if battleTex.flash then
        Voxel3D.flatten(BattleScene.FLASH_COLOR, BattleScene.FLASH_STRENGTH)
      end
      for _, card in ipairs(cards) do
        Voxel3D.draw(BattleBillboard.mesh(), card.tex, card.model,
                     BattleBillboard.PULL)
      end
      if battleTex.flash then Voxel3D.flatten(nil) end
      -- and the MOVE ANIMATIONS, standing on the same arena: the
      -- engine's own effects layer on the plane through both cells
      -- (BattleScene.fxCard), pulled a little harder than the mons so
      -- a burst plays over the card it is bursting on
      local okA, fxTex, fxModel = pcall(function()
        return V.require("OverworldBattle").worldAnim()
      end)
      if okA and fxTex and fxModel then
        Voxel3D.draw(BattleBillboard.mesh(), fxTex, fxModel,
                     BattleBillboard.PULL + 6)
      end
      Voxel3D.seams(true)
      Voxel3D.glass(true)
    end
  end
  -- The overworld capture minigame's user-supplied 3D Poké Ball.  It is
  -- a world-space prop, so terrain/buildings can occlude it honestly.  The
  -- target itself remains an ordinary roaming entity until ball impact; on
  -- impact OverworldCapture marks only that entity hidden while the ball
  -- shakes, then restores it on breakout or removes it on a successful catch.
  do
    local okCapture, Capture = pcall(V.require, "OverworldCapture")
    if okCapture and Capture and Capture.active and Capture.active() then
      Voxel3D.glass(false)
      Voxel3D.seams(false)
      pcall(Capture.drawWorld, state)
      Voxel3D.seams(true)
      Voxel3D.glass(true)
    end
  end

  -- tall grass last, pulled camera-ward exactly as far as the characters
  -- were (same per-vertex shader bias, so grass never drifts either):
  -- relative depth between a walker and the tuft row south of their feet
  -- is preserved, so the row still overdraws feet -- the 3D version of
  -- the GB's grass-over-feet trick -- while grass keeps losing to the
  -- buildings it genuinely stands behind (far deeper than the pull).
  -- the same angle the cards leaned by (leanAngle honours VR's override),
  -- so the tuft rows keep exactly the characters' own depth handicap
  local lean = math.max(leanAngle(), 0.05)
  local pull = VoxelScene.pull(lean)
  if liveBattleArena then Voxel3D.battleOcclusion(liveBattleArena, liveBattleGround) end
  Voxel3D.draw(ChunkMesher.grass(state.map), atlasFor(state.map), nil, pull)
  for i, nb in ipairs(state.neighbors or {}) do
    if readyNeighbor(state, i) then
      Voxel3D.draw(ChunkMesher.grass(nb.map), atlasFor(nb.map),
                   VoxelScene._neighborModel(nb), pull)
    end
  end
  -- flower billboards: pulled like the characters and the grass, MINUS
  -- the depth of 8 world pixels along the view (8 sin a -- the camera
  -- looks along (0, -cos a, -sin a), so that is exactly one tile row of
  -- northness). A pure depth handicap with zero screen drift: every
  -- flower is judged as if it stood one tile row further north. The
  -- character card's feet plane sits at its cell's MIDDLE (py + 8), so
  -- a flower on the walker's own cell (z +4 or +12 across the cell)
  -- lands behind the card and the player obscures the patch they stand
  -- ON, while the nearest flower of the cell south (+20) stays in front
  -- and keeps overdrawing their feet.
  local fpull = math.max(0, pull - 8 * math.sin(lean))
  -- flowers are snugged casters too, so they read their own shadowing
  -- through the same snugged transform the sun stored them with
  Voxel3D.draw(ChunkMesher.flowers(state.map), atlasFor(state.map), nil,
               fpull, ShadowMap.snug(nil))
  for i, nb in ipairs(state.neighbors or {}) do
    if readyNeighbor(state, i) then
      Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   VoxelScene._neighborModel(nb), fpull,
                   ShadowMap.snug(VoxelScene._neighborModel(nb)))
    end
  end
  if liveBattleArena then Voxel3D.battleOcclusion(nil) end

  -- The VR pokedex in the player's left hand, last of all: a prop over
  -- the world drawn with real depth, so leaning it into a wall still
  -- occludes honestly. Its frame only exists while a session is live and
  -- the left hand is tracked (VR.lua sets it), so every flat frame skips
  -- this in one field read. No wireframe and no glass, like the cast:
  -- the device is a drawing riding the scene, not part of the terrain.
  if Pokedex.frame then
    Voxel3D.glass(false)
    Voxel3D.seams(false)
    Pokedex.draw()
    Voxel3D.seams(true)
    Voxel3D.glass(true)
  end


  end   -- drawScene

  if not eyes then
    if not Voxel3D.beginScene(w, h, cx, cy, vw, vh, skyFor(state.map)) then
      return nil
    end
    drawScene()
    -- Paint the capture reticle/ring directly into the still-bound scene
    -- canvas after all 3D geometry.  Do not call Voxel3D.endOverlay here:
    -- endScene still owns the active pass and will unbind it after weather.
    local okCapture, Capture = pcall(V.require, "OverworldCapture")
    if okCapture and Capture and Capture.active and Capture.active() then
      love.graphics.setShader()
      love.graphics.setDepthMode()
      pcall(Capture.drawOverlay, w, h)
    end

    -- Finalize the 3D pass first. endScene() paints weather and then returns
    -- the same window-sized canvas seen by GoldComposeBridge. The controller
    -- HUD is composited AFTER that into the returned canvas, guaranteeing it
    -- cannot be hidden by weather or lost at the later Game2 UI seam.
    local out = Voxel3D.endScene()
    if out and state and state._stadiumLiveBattle then
      local G = love.graphics
      local previous = G.getCanvas()
      local okHud = pcall(function()
        G.setCanvas(out)
        G.push("all")
        G.origin()
        G.setShader()
        G.setDepthMode()
        G.setBlendMode("alpha")
        local battle = V.require("OverworldBattle").battle()
        local ui = V.BattleControllerUI or V.require("BattleControllerUI")
        if battle and ui and type(ui.drawIntoScene) == "function" then
          ui.drawIntoScene(battle, w, h)
        elseif ui and type(ui.clearSceneHudFlag) == "function" then
          ui.clearSceneHudFlag()
        end
        G.pop()
      end)
      if not okHud then
        pcall(G.pop)
        pcall(function()
          local ui = V.BattleControllerUI or V.require("BattleControllerUI")
          if ui and type(ui.clearSceneHudFlag) == "function" then ui.clearSceneHudFlag() end
        end)
      end
      if previous then pcall(G.setCanvas, previous) else pcall(G.setCanvas) end
    end
    return out
  end

  -- The VR frame: the same scene once per eye, each into its own named
  -- canvas slot under its own placed camera. `adopt` hands the eye's
  -- record to FirstPerson as the live rig, which is what turns the
  -- billboards toward THIS eye in first person (cardBlend keys on rig
  -- identity -- see FirstPerson) and leaves them leaning in the diorama,
  -- where the blend is zero.
  local out = {}
  for i, eye in ipairs(eyes) do
    Voxel3D.camera = eye.camera
    if eye.adopt then FirstPerson.adoptVReye(eye.camera) end
    if not Voxel3D.beginScene(eye.w, eye.h, cx, cy, vw, vh,
                              skyFor(state.map), eye.slot) then
      return nil
    end
    drawScene()
    out[i] = Voxel3D.endScene()
  end
  return out
end

return VoxelScene
