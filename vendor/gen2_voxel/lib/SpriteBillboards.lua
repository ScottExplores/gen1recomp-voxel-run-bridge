-- Voxel world mode: characters as flat forward-facing sprite billboards.
--
-- Every character -- the player, NPCs, the ghosts standing on a neighbour
-- map -- is its CURRENT 2D sprite frame on a single flat quad. The sheets
-- carry real alpha and the shader discards it, so the quad cuts the
-- sprite's exact silhouette out of itself; no geometry is built from the
-- pixels and nothing about a sprite is voxelized.
--
-- That is deliberate. A sprite is a DRAWING, not an object seen from one
-- side: Gen 1's overworld figures are 16x16 icons with a fixed front-on
-- reading, and turning one into a solid -- whether a contoured slab or a
-- carved visual hull -- reconstructs a body the artist never drew and the
-- game never implied. It also had the mod ship a description of the ROM
-- art. One quad wearing the real frame is both more faithful and cheaper:
-- it needs no pixel access at all, only the sheet's dimensions.
--
-- The card always faces SOUTH -- the direction the 2D game implies -- and
-- only LEANS BACK, pivoting at its feet, by exactly the camera's pitch
-- (VoxelScene's billboardMatrix), so at every tilt level it reads face-on
-- like the flat game. Right-facing and the alternating walk step are
-- matrix mirrors, not extra meshes. UVs point into the live sheet image,
-- so RED++ OBP bakes, SGB palette bakes and sprite-replacing mods all
-- texture it with no rebuild.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")
local Voxel3D = V.require("Voxel3D")

local SpriteBillboards = {}

local meshes = {}

-- One flat quad UV-mapped to the current frame. Vanilla is 16x16; custom
-- player definitions may supply larger frameWidth/frameHeight + foot anchors. A hair of inset keeps
-- the sampler inside this frame rather than picking up the neighbouring
-- one along the shared edge.
local function buildCard(def, frame)
  local img = def and def._stadiumImage or nil
  local ok = img ~= nil
  if not img then ok, img = pcall(Assets.image, def.image) end
  if not (ok and img) then return nil end
  local iw, ih = img:getDimensions()

  -- v0.3.38: custom players are not required to be 16x16. The 2D engine
  -- already exposes the real frame dimensions and foot anchor on the sprite
  -- definition; the voxel card must honor the same contract. The old fixed
  -- 16x16 quad sampled only a 16px slice and treated x=8 as the pivot, which
  -- drew wider custom characters (for example Sonic) visibly left/right of
  -- their actual player/collision body.
  local fw = math.max(1, tonumber(def.frameWidth) or 16)
  local fh = math.max(1, tonumber(def.frameHeight) or 16)
  local anchorX = tonumber(def.anchorX) or fw / 2
  local anchorY = tonumber(def.anchorY) or fh
  if fw > iw then fw = iw end
  if fh > ih then fh = ih end

  local fy = frame * fh
  if fy + fh > ih then fy = 0 end
  local insetX, insetY = math.min(0.02, fw * 0.001), math.min(0.05, fh * 0.002)
  local u0, u1 = insetX / iw, (fw - insetX) / iw
  local v0, v1 = (fy + insetY) / ih, (fy + fh - insetY) / ih

  -- billboardMatrix/casterMatrix translate mesh x=8 onto the CELL CENTER.
  -- Place the authored anchor there, while y=0 remains the authored foot
  -- point. Default 16x16 definitions therefore produce the exact old quad.
  local left = 8 - anchorX
  local right = left + fw
  local bottom = anchorY - fh
  local top = anchorY
  local verts = {
    { left,  bottom, 0, u0, v1, 1 }, { right, bottom, 0, u1, v1, 1 },
    { right, top,    0, u1, v0, 1 }, { left,  top,    0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  return Voxel3D.newMesh(verts, indices)
end

-- The card for one (sprite def, frame index), or nil (headless / no
-- image), cached like every other derived GPU object.
--
-- The solid draw, the sun pass and the player's occlusion silhouette all
-- take THIS mesh. That the three agree is load-bearing, not tidiness: the
-- silhouette is drawn with the depth test INVERTED, so any self-overlap in
-- the mesh would read as "behind something" and repaint the figure on open
-- ground whether or not anything hides it; and the sun must see the same
-- outline the camera does, or a shadow stops matching what casts it.
function SpriteBillboards.mesh(def, frame)
  local key = table.concat({ tostring(def.image), tostring(frame),
    tostring(def.frameWidth or 16), tostring(def.frameHeight or 16),
    tostring(def.anchorX or "auto"), tostring(def.anchorY or "auto") }, "#")
  if meshes[key] == nil then
    local ok, m = pcall(buildCard, def, frame)
    meshes[key] = (ok and m) or false
  end
  return meshes[key] or nil
end

-- Kept as its own name because the shadow and ghost passes read as their
-- own thing at the call sites; it once carried a different mesh from the
-- solid draw, and now deliberately does not.
SpriteBillboards.shadowQuad = SpriteBillboards.mesh

function SpriteBillboards.invalidate()
  meshes = {}
end

Assets.register(SpriteBillboards.invalidate)

return SpriteBillboards
