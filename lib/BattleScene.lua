-- Overworld battles: a frame of the arena, as geometry.
--
-- The same world the free-roam mode draws, from a placed camera instead of
-- the orbit, at the WINDOW's own pixel resolution -- not the GB's. The
-- backdrop reaches the screen through Renderer's worldOverride, the seam a
-- render pipeline's finished world image already composites through, which
-- is drawn one canvas pixel to one screen pixel; the 160x144 battle screen
-- then blits over it in the classic letterbox. So the world is as crisp as
-- the free-roam diorama and the pics, HUDs and text box stay exactly the
-- chunky GB art they are.
--
-- Rendering the whole window rather than just the letterbox means the
-- framing has to be split in two. The RIG frames the GB's 160x144 (see
-- BattleCam, which is solved against coordinates in that frame); this
-- module widens the lens by exactly the ratio the window bears to the
-- letterbox, so the letterbox sub-rectangle of what gets rendered is
-- bit-for-bit the framing the rig asked for, and everything outside it is
-- extra picture. That is what lets the two mons be PINNED: their cells
-- project to the same GB coordinates at any window size or zoom.
--
-- Characters are deliberately absent. The overworld cast is culled for the
-- length of the battle (see OverworldBattle), so this pass has terrain,
-- grass and flowers and nothing that walks -- the arena is empty, which is
-- what makes it an arena.
--
-- Everything expensive is shared with the free-roam mode rather than
-- duplicated: the same chunk meshes out of ChunkMesher, the same palette
-- atlas out of TerrainAtlas, the same sun out of ShadowMap. A battle on a
-- map already meshed for walking around costs the frame it draws and
-- nothing else.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")
local ChunkMesher = V.require("ChunkMesher")
local TerrainAtlas = V.require("TerrainAtlas")
local VoxelScene = V.require("VoxelScene")
local BattleCam = V.require("BattleCam")
local BattleBillboard = V.require("BattleBillboard")
local DayNight = V.require("DayNight")
local UiBackplates = V.require("UiBackplates")
local Gen6Backdrop = V.require("Gen6Backdrop")
local Images = V.require("BackdropImage")
local BossBackdrop = V.require("BossBackdrop")
local AntiAlias = V.require("AntiAlias")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.Map")

local BattleScene = {}

-- LET'S GO capture mode's stake in the staged scene. CatchThrow owns this
-- table while a throw (or FULL-mode veil) is live; keeping the seam here
-- avoids a require cycle between the renderer and capture controller.
BattleScene.capture = nil

-- The GB frame the battle screen is drawn in, and the frame BattleCam's rig
-- is solved against.
BattleScene.GB_W = 160
BattleScene.GB_H = 144

-- A map cell in world pixels: the overworld square a mon stands on, which is
-- both what the arena is measured in and what a mon is sized to.
BattleScene.CELL = 16

-- How far into black a shadow goes in the arena, against the free-roam
-- mode's own lighter setting.
--
-- Darker on purpose, and only here. Walking around, a shadow is scenery and
-- wants to stay out of the way of reading the map. In a battle it is doing
-- one specific job: the two mons are flat cards, and the ONLY thing telling
-- the eye they are standing on that floor rather than hanging in front of it
-- is the shadow they put on it. A faint one leaves them floating.
BattleScene.SHADOW_ALPHA = 0.68

-- Which rung of the sky ramp an indoor void is painted with. A room has no
-- sky, but it does have somewhere the geometry stops, and leaving that
-- transparent would show the letterbox clear through the gaps.
local INDOOR_SHADE = 4

-- ------- where the GB frame sits inside the window
--
-- Renderer blits worldOverride one canvas pixel to one screen pixel and then
-- blits the 160x144 UI canvas into a centred, integer-scaled letterbox. So
-- these have to agree with Renderer:endFrame exactly, or the pins land off
-- the mons by however much they disagree.
function BattleScene.letterbox()
  local Renderer = require("src.render.Renderer")
  local pw, ph = BattleScene.pixelSize()
  local s = Renderer:fitScale()
  return math.floor((pw - BattleScene.GB_W * s) / 2),
         math.floor((ph - BattleScene.GB_H * s) / 2),
         s, pw, ph
end

-- The window in FRAMEBUFFER pixels, which is what the override blit works
-- in. love.graphics.getDimensions is in LOVE units and differs from this by
-- the display density on mobile.
function BattleScene.pixelSize()
  if love.graphics.getPixelDimensions then
    local pw, ph = love.graphics.getPixelDimensions()
    if pw and ph and pw > 0 and ph > 0 then return pw, ph end
  end
  return love.graphics.getDimensions()
end

-- Widen the rig's vertical field of view from the GB frame to the whole
-- window, so the letterbox rows show exactly what the rig framed.
--
-- The horizontal falls out of it: at aspect pw/ph the window's half-width is
-- tan(fov/2) * pw/ph, and the letterbox is 160*s of those pw pixels, which
-- works back out to the GB frame's own 160/144. So one scale on the vertical
-- pins both axes.
function BattleScene.letterboxFov(fovGB, ph, s)
  local span = BattleScene.GB_H * s
  if span <= 0 then return fovGB end
  return 2 * math.atan(math.tan(fovGB / 2) * ph / span)
end

-- ------- palette
--
-- The world palette a map draws under, in the shape VoxelScene's colour
-- helpers take. Rebuilt per frame from the overworld state, which is where
-- the engine's own pipeline context gets it too (OverworldController's
-- ctx.paletteFor).
local function paletteFor(state, home)
  return function(map)
    return PaletteFX.pal(require("src.core.Game").data,
                         state:paletteNameFor(map or home))
  end
end

-- ------- the map the fight is staged on
--
-- Normally the one the player is standing on. An authored arena may name
-- another floor of the same cave or building (see BattleArena), and then the
-- scene is THAT map: its terrain, its palette, its sky. Nothing else in the
-- battle changes -- the fight, the party, the player's own position are all
-- exactly where they were.
--
-- A foreign floor is meshed alone, with no connected neighbours: connections
-- are the player's neighbourhood, and the map the camera has gone to visit is
-- not standing in it. Both maps are kept live so neither the arena's mesh nor
-- the one waiting to be walked back onto is evicted mid-battle.
local function prefetchArena(state, host)
  if host == state.map then return VoxelScene.prefetch(state) end
  local live = { [host.id] = true, [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do live[nb.map.id] = true end
  ChunkMesher.setLive(live)
  TerrainAtlas.setLive(live)
  ChunkMesher.request(host, false, nil, true)
  local terrain, water = ChunkMesher.pair(host, false)
  if not terrain then terrain, water = ChunkMesher.pair(host, true) end
  return terrain, {}, water, {}
end

-- ------- the sun
--
-- Only has to be drawn once per battle: the arena does not move, and neither
-- does the light. So the signature is the map, the arena and the meshes --
-- not the camera, which is the one thing that IS moving and the one thing
-- the sun does not care about.
-- ------- the two mons, hung on their cells
--
-- The billboard texture is the battle screen's own 160x144 pics layer with
-- one side rendered into it (see OverworldBattle.sideTexture), so the quad is
-- that whole frame stood up on the map -- which is what carries every pic
-- effect the engine applies without any of them being reimplemented here.
--
-- Its size follows from one number: a full 7x7-tile mon covers one overworld
-- square, so a canvas pixel is FULL_W / FULL_PIC world pixels and the card is
-- the canvas at that scale. Its placement follows from the anchor the
-- texture reports -- the column the pic was centred on and the row its feet
-- were put on -- which is translated onto the cell before the card is stood
-- up, so a mon of any size in any pose has its feet on the ground.
-- `mirror` flips the card about its own anchor column. It is explicit metadata
-- on each Pokemon card: the player-front path retains its historical default,
-- while opponent and player-back cards have independent authored/flipped
-- choices. Because the flip is about the pic's own centre, its feet do not
-- move off the tile.
--
-- The player's TRAINER pic is the exception, and it is exempted below. That
-- one is a BACK view -- the player seen from behind, already turned to face
-- up the field -- so it arrives pointing the right way and mirroring it would
-- turn it around to face the camera it is standing in front of.
local function monMatrix(tex, x, groundY, z, mirror)
  local k = BattleBillboard.FULL_W / BattleBillboard.FULL_PIC
  local tw, th = tex.canvas:getWidth(), tex.canvas:getHeight()
  local w, h = tw * k, th * k
  local ox = (tw / 2 - tex.ax) * k
  local oy = -(th - tex.ay) * k
  local yaw = BattleBillboard.yawToward(x, z, Voxel3D.eye)
  local card = Mat4.mul(Mat4.translate(ox, oy, 0), Mat4.scale(w, h, 1))
  if mirror then card = Mat4.mul(Mat4.scale(-1, 1, 1), card) end
  local presentationScale = tonumber(tex.presentationScale) or 1
  if presentationScale ~= 1 then
    -- Scale about the reported foot anchor. This is deliberately metadata on
    -- trainer cards, not a texture resize and not a Pokemon-wide multiplier.
    card = Mat4.mul(Mat4.scale(presentationScale, presentationScale, 1), card)
  end
  return Mat4.mul(Mat4.mul(Mat4.translate(x, groundY, z), Mat4.rotateY(yaw)),
                  card)
end

-- Every mon that has something to show this frame, as (texture, matrix).
local function monCards(arena, groundY, textures)
  local out = {}
  if not textures then return out end
  local cap = BattleScene.capture
  for _, side in ipairs({ "enemy", "player" }) do
    local tex = textures[side]
    local cell = (side == "player") and arena.player or arena.enemy
    if side == "player" and cap and cap.hidePlayer then tex = nil end
    if tex and tex.canvas and cell then
      local mirror = tex.mirror
      if mirror == nil then
        -- v2 texture records only described the historical player-front
        -- mirror. Keep accepting them so a hot reload can finish a frame
        -- assembled by the previous OverworldBattle entry.
        mirror = (side == "player") and not tex.trainer
                 and not tex.noMirror
      end
      local model = monMatrix(tex, cell[1], groundY, cell[2], mirror)
      -- Pull the foe into the ball about its chest rather than its feet.
      if side == "enemy" and cap and cap.shrink then
        local k = cap.shrink
        local ax, ay, az = cell[1], groundY + 8, cell[2]
        model = Mat4.mul(
          Mat4.mul(Mat4.translate(ax, ay, az),
                   Mat4.mul(Mat4.scale(k, k, k),
                            Mat4.translate(-ax, -ay, -az))),
          model)
      end
      out[#out + 1] = { tex = tex.canvas,
                        noDayTint = tex.noDayTint,
                        model = model }
    end
  end
  return out
end

BattleScene.monCards = monCards

-- The sun has to see the mons too, or they stand on the ground without
-- putting anything on it. They are the one thing in this scene that MOVES,
-- so `token` -- a counter the caller bumps whenever a pic could have changed
-- -- goes in the signature; the terrain half of the answer would otherwise
-- keep a stale pass alive and freeze the shadows in whatever pose they were
-- first drawn in.
local function shadowSignature(state, arena, terrain, nbMesh, token)
  local host = arena.map or state.map
  local parts = { "battle", host.id, arena.x, arena.y, arena.shape,
                  tostring(arena.turn or 0),
                  tostring(terrain), tostring(token or 0),
                  -- UNLIT removes the cards from the caster pass. Carry that
                  -- decision so switching SPRITE LIGHT or ARENA FILL cannot
                  -- reuse a map that still contains their old silhouettes.
                  tostring(UiBackplates.spritesUnlit()),
                  -- the cycle keeps running through a fight, and an arena lit
                  -- from somewhere new must be re-cast from there
                  math.floor(ShadowMap.KX * 128),
                  math.floor(ShadowMap.KZ * 128) }
  local cap = BattleScene.capture
  if cap and cap.sig then
    local okSig, sig = pcall(cap.sig)
    parts[#parts + 1] = okSig and sig or "cap"
  end
  for i = 1, #nbMesh do parts[#parts + 1] = tostring(nbMesh[i]) end
  return table.concat(parts, ",")
end

local function castShadows(state, arena, terrain, nbMesh, cx, cy, vw, vh,
                           atlasFor, cards, token, host, neighbors,
                           water, nbWater)
  if not ShadowMap.available() then return end
  local sig = shadowSignature(state, arena, terrain, nbMesh, token)
  if not ShadowMap.stale(sig) then return end
  if not ShadowMap.begin(cx, cy, vw, vh) then return end

  ShadowMap.draw(terrain, atlasFor(host), nil)
  for i, nb in ipairs(neighbors) do
    ShadowMap.draw(nbMesh[i], atlasFor(nb.map), Mat4.translate(nb.ox, 0, nb.oy))
  end
  -- the water surface is its own reflective pass now (see Water) and so is
  -- no longer inside the terrain mesh; the sun still has to see it, or the
  -- light's map has a hole at every lake
  ShadowMap.draw(water, atlasFor(host), nil)
  for i, nb in ipairs(neighbors) do
    ShadowMap.draw(nbWater and nbWater[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
  end
  -- thin cards are snugged toward the sun (ShadowMap.snug) so their shadows
  -- keep contact with their bases instead of starting a bias-width away
  ShadowMap.draw(ChunkMesher.flowers(host), atlasFor(host),
                 ShadowMap.snug(nil))
  for _, nb in ipairs(neighbors) do
    ShadowMap.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
  end

  -- the mons themselves, as the same cards the camera will see. Their alpha
  -- is the silhouette, so what lands on the ground is the shape of the
  -- Pokemon rather than a blob standing in for one.
  -- marked as the CAST, so a fight staged at the water's edge does not lay a
  -- cut-out of a Pokemon across the lake (see ShadowMap.sprites); the arena's
  -- own floor still takes them, which is the shadow that matters here
  --
  -- UNLIT cards are absent from this pass as well as bypassing it when they
  -- are drawn below. That makes the contract symmetric: they neither receive
  -- somebody else's shadow nor cast/self-cast one of their own, independent
  -- of the selected arena fill.
  if not UiBackplates.spritesUnlit() then
    ShadowMap.sprites(true)
    for _, card in ipairs(cards or {}) do
      ShadowMap.draw(BattleBillboard.mesh(), card.tex,
                     ShadowMap.snug(card.model))
    end
    ShadowMap.sprites(false)
  end

  -- A thrown ball is real scene geometry and needs the same moving shadow
  -- that sells its arc to the eye.
  local cap = BattleScene.capture
  if cap and cap.cast then pcall(cap.cast, ShadowMap) end

  ShadowMap.finish(sig)
end

-- The height of the arena floor: the ground the two mons stand on. Both
-- cells are open, so they are normally the same; take the player's, which is
-- the one nearer the camera and therefore the one a mismatch would show up
-- against.
function BattleScene.groundY(map, arena)
  local ok, h = pcall(VoxelScene.groundAt, map,
                      arena.playerCell[1], arena.playerCell[2])
  return (ok and h) or 0
end

-- Where a world point lands in GB frame coordinates under `vp`, or nil when
-- it is behind the camera. This is the function the pins are built on: it
-- takes the window-resolution clip position and divides the letterbox back
-- out of it, so the answer is in the same 160x144 space the battle screen
-- draws its pics in.
function BattleScene.toGB(vp, wx, wy, wz, lx, ly, s, pw, ph)
  local cx = vp[1] * wx + vp[2] * wy + vp[3] * wz + vp[4]
  local cy = vp[5] * wx + vp[6] * wy + vp[7] * wz + vp[8]
  local cw = vp[13] * wx + vp[14] * wy + vp[15] * wz + vp[16]
  if cw <= 1e-6 then return nil end
  -- viewProjection already flipped clip Y into LOVE's Y-down convention
  local px = (cx / cw * 0.5 + 0.5) * pw
  local py = (cy / cw * 0.5 + 0.5) * ph
  return (px - lx) / s, (py - ly) / s
end

-- Render the arena and hand back { canvas, player = {x,y}, enemy = {x,y} },
-- the two marks in GB coordinates -- or nil when there is nothing to draw
-- yet (the terrain mesh is still building, the driver has no depth support).
-- nil is not a failure: the caller simply leaves the battle screen as the
-- engine drew it for that frame.
-- White, for the hit flash, and how far toward it the card goes.
--
-- The shader replaces the card's colour rather than multiplying it, so at
-- full strength this is the sprite turned into a solid white silhouette --
-- which is what the effect is on a flat GB screen and far too much on a
-- sprite standing in a lit world. Held well short of 1, the mon's own
-- shading still reads through the flash: it looks struck rather than
-- deleted.
BattleScene.FLASH_COLOR = { 1, 1, 1 }
BattleScene.FLASH_STRENGTH = 0.5

-- ------- the tile clock, while the overworld is not the one drawing
--
-- Water and flowers animate off TileRenderer's 60Hz counter, and the ENGINE
-- only advances it from OverworldState:drawWorld -- which runs under dialogs
-- and menus, but not under a battle, because a battle draws instead of the
-- overworld rather than over it. So for the length of a staged fight the
-- counter stood still: the water tiles stopped rotating their pixels and the
-- wave field, which is driven off the same number so the two cannot drift
-- (see Water), stopped with them. A lake in the background of a battle was a
-- photograph.
--
-- Ticked HERE rather than from the mod's update hook, because here is the
-- one place that means "a staged battle is drawing this frame, and the
-- overworld is not". From the update hook the condition would have to be
-- guessed at, and a frame where both ran would double the rate.
local function tickTiles()
  local Game = require("src.core.Game")
  local ow = Game and Game.overworld
  local top = Game and Game.stack and Game.stack:top()
  -- during the wipe INTO a battle the overworld can still be the one
  -- drawing, and it is ticking the clock itself; two ticks in a frame would
  -- run the water at double speed
  if top and ow and top == ow then return end
  pcall(require("src.render.TileRenderer").tick)
end

function BattleScene.render(state, arena, textures, token, battle)
  if not (state and state.map and arena) then return nil end
  if not Voxel3D.available() then return nil end
  tickTiles()

  -- the floor the fight is staged on: normally the player's own, sometimes
  -- another floor of the same cave or building (see BattleArena)
  local host = arena.map or state.map
  local neighbors = (host == state.map) and (state.neighbors or {}) or {}
  local whiteFill = UiBackplates.arenaWhite()
  local gen6Fill = UiBackplates.arenaGen6()
  local pngFill = UiBackplates.arenaPng()
  local gen6Image = gen6Fill and Gen6Backdrop.image(state.map, battle) or nil
  local pngImage = pngFill and Images.load("bosses", "arena.png") or nil
  -- Boss art is an encounter override, not an ARENA FILL collection.  It may
  -- therefore sit above GEN6 now and GEN4/OPENART later, while OFF/WHITE keep
  -- their established meanings. Use the actual battle map for identity even
  -- when BattleArena stages the camera on an adjacent host floor.
  local bossImage = UiBackplates.arenaArt()
                    and UiBackplates.bossEnabled()
                    and BossBackdrop.image(state.map, battle) or nil
  local artImage = bossImage or pngImage or gen6Image
  -- A missing/corrupt optional plate fails open to the ordinary voxel arena,
  -- never to an opaque black battle.
  local flatFill = whiteFill or artImage ~= nil

  -- the hour's light reaches the arena exactly as it reaches free-roam: the
  -- shared rig follows the clock on an outdoor floor and stays at noon on an
  -- indoor one, and the same tint multiplies the staged shot -- with the
  -- same window glass on whatever buildings stand in the background
  local outdoor = host.def and Map.isOutdoor(host.def) or false
  DayNight.applyRig(outdoor)
  -- a canopy floor (Viridian Forest) fights under the hour's tint too,
  -- with the rig and the void exactly as they were
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(host))
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(host.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  -- no glint in the arena: the drift is the shot breathing, not the player
  -- moving, and a shimmer on background windows would fight the mons
  Voxel3D.glassGlint = 0

  -- A flat plate does not wait for or touch voxel meshes. The world arena
  -- still shares free-roam's request/evict bookkeeping and warms nothing
  -- extra; illustrated plates can therefore enter immediately on a cold map.
  local terrain, nbMesh, water, nbWater
  if not flatFill then
    terrain, nbMesh, water, nbWater = prefetchArena(state, host)
    if not terrain then return nil end
  end

  local lx, ly, s, pw, ph = BattleScene.letterbox()
  if not (pw > 0 and ph > 0 and s > 0) then return nil end

  local palette = paletteFor(state, host)
  local function atlasFor(map)
    return TerrainAtlas.forMap(map, VoxelScene._modeColors(palette, map))
  end

  local groundY = BattleScene.groundY(host, arena)
  local cam, pitch, capFrameH
  local cap = BattleScene.capture
  if cap and cap.rig then
    local okRig, c, p, fh = pcall(cap.rig, arena, groundY)
    if okRig and c then cam, pitch, capFrameH = c, p or math.rad(80), fh end
  end
  if not cam then cam, pitch = BattleCam.rig(arena, groundY) end
  cam.fov = BattleScene.letterboxFov(cam.fov, ph, s)

  local cx, cy = arena.mid[1], arena.mid[2]
  -- the world extents the sun frustum is fitted to; the camera itself is
  -- framed by cam.fov, so these only have to describe the ground in shot
  local vh = (capFrameH or BattleCam.frameH(arena)) * ph
             / (BattleScene.GB_H * s)
  local vw = vh * pw / ph

  -- the cards need the camera's eye to face it, so the rig has to be live
  -- before they are built; Voxel3D.eye is set by viewProjection, which
  -- beginScene calls -- so a provisional one is taken here for the sun pass
  -- and the real one is rebuilt inside the scene below.
  Voxel3D.camera = cam
  Voxel3D.viewProjection(cx, cy, vw, vh)
  local cards = monCards(arena, groundY, textures)
  Voxel3D.camera = nil
  if flatFill then
    -- WHITE is a genuinely flat stage: there is no visible world receiver,
    -- and its cards must neither cast nor receive. Do not merely omit the
    -- cards from a newly built map; discard any map left by the preceding
    -- overworld/battle too, so beginScene binds the blank sampler.
    ShadowMap.discard()
  else
    castShadows(state, arena, terrain, nbMesh, cx, cy, vw, vh, atlasFor,
                cards, token, host, neighbors, water, nbWater)
  end

  -- An opaque void either way. Outdoors the camera is low enough that the
  -- horizon is genuinely in frame, so it is sky; indoors it is the dark end
  -- of the same ramp, which is a room's "past the wall". Transparent -- the
  -- free-roam default -- would let the letterbox clear through wherever the
  -- geometry stops.
  local sky = VoxelScene.skyColor(host, 1)
             or VoxelScene.skyShade(INDOOR_SHADE, 1)

  Voxel3D.camera = cam
  -- the sun is turned up for the arena and put back afterwards, so the
  -- free-roam world it shares this module with keeps its own weight -- and
  -- the hour still has the last word: a sunset fades the arena's shadows
  -- out and the moon presses more softly, exactly as it does outside
  local sunWas = Voxel3D.SHADOW_ALPHA
  Voxel3D.SHADOW_ALPHA = BattleScene.SHADOW_ALPHA
                         * DayNight.shadowScale(outdoor)
  -- The same V-GRID row owns the wireframe here and in free roam. OFF means
  -- no seams anywhere; ON keeps the constructed look on both the overworld
  -- and this staged battle shot. Reading the setting through Voxel3D leaves
  -- the player's choice untouched.
  local out = nil
  local ok, err = pcall(function()
    -- its own canvas slot: this renders at the window's pixel size and the
    -- free-roam pass does too, but the two are alive at different moments
    -- and a shared slot would reallocate on every battle entry and exit
    --
    -- AA, if the row asks for it, renders it larger still and folds it back
    -- to pw x ph below (see AntiAlias). The framing is untouched by that:
    -- the lens was widened by the window's RATIO to the letterbox and the
    -- rig solved in the GB's own frame, so a bigger canvas is more samples
    -- of the identical shot -- which is why the pins below still measure in
    -- pw and ph, and why the HUDs and the depth of field, drawn onto the
    -- folded canvas afterwards, stay the chunky GB art they are.
    local rw, rh = AntiAlias.expand(pw, ph)
    -- ARENA FILL: WHITE covers the whole voxel world with a solid field and
    -- keeps only the mons (drawn below) above it -- the step between the OG
    -- battle and the full 3D one. Implemented by clearing the scene to white
    -- and skipping the terrain/water/grass/flower draws; the 2D attack
    -- animations and the menus composite on top afterwards, so they stay
    -- above the white too. Requires sprite light UNLIT (see UiBackplates).
    local skyFill = whiteFill and { 1, 1, 1 }
                    or (artImage and { 0, 0, 0 } or sky)
    if not Voxel3D.beginScene(rw, rh, cx, cy, vw, vh, skyFill, "battle") then
      return
    end
    if artImage then
      Voxel3D.backdrop(artImage, UiBackplates.backdropOffsetPixels())
    end
    if not flatFill then
    Voxel3D.draw(terrain, atlasFor(host), nil)
    for i, nb in ipairs(neighbors) do
      Voxel3D.draw(nbMesh[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
    end
    -- Raised canopies are baked into the terrain, while their trunks, rock
    -- supports and foliage hoods are live Flora meshes.  Draw those same
    -- support meshes in staged battles so trees and rocks never float or
    -- disappear when a fight starts.
    pcall(function()
      local live = rawget(_G, "__ds_live")
      if live and live.Flora and live.Flora.battleProps then
        live.Flora.battleProps(host, neighbors)
      end
    end)
    -- and the water over it -- PLAIN, always: the flat animated tiles, never
    -- the reflective pass, whatever the WATER row says. The reflection is
    -- tuned for the overworld's ladder of cameras; this shot's is PLACED --
    -- low, tilted and framed like a picture -- and under it the pass reads
    -- wrong: Fresnel opens all the way up, the leaned sky lands on bands the
    -- framing never shows, and a lake-sized arena comes out as murk wearing
    -- the tile art. The battle is a stage set, and stage water is painted.
    -- (No mirror also means the mons need no second draw into one -- they
    -- just composite over the water below, like everything else on the set.)
    if water then Voxel3D.draw(water, atlasFor(host)) end
    for i, nb in ipairs(neighbors) do
      if nbWater and nbWater[i] then
        Voxel3D.draw(nbWater[i], atlasFor(nb.map),
                     Mat4.translate(nb.ox, 0, nb.oy))
      end
    end
    end
    -- The mons, standing on their tiles. Depth-tested like everything else,
    -- so a ledge or a tree between the camera and a Pokemon really is in
    -- front of it, and the alpha discard cuts the sprite's own outline out of
    -- the card. A small camera-ward pull keeps a card rooted to the ground
    -- plane from z-fighting the tile it is standing on.
    -- The engine's hit flash is a full-screen white rectangle, which on a
    -- white battle field is a flash and over a world is a whiteout of the
    -- map, the HUD and the text box alike. It is dropped on the way past
    -- (see OverworldBattle) and put back HERE, on the two things it was ever
    -- about: the mons themselves go solid white for those frames.
    local flashing = textures and textures.flash
    if flashing then
      Voxel3D.flatten(BattleScene.FLASH_COLOR, BattleScene.FLASH_STRENGTH)
    end
    -- and no voxel wireframe on the pair. Everything else in this frame is
    -- built a unit per voxel and wears the seams that fall out of that; a
    -- mon's card is one quad wearing the battle screen (see
    -- BattleBillboard), so it is off the grid and has no seams to draw.
    Voxel3D.seams(false)
    -- and no glass either: the cards wear the battle screen, not the
    -- tileset atlas, so the mask's coordinates mean nothing on them
    Voxel3D.glass(false)
    for _, card in ipairs(monCards(arena, groundY, textures)) do
      -- Static front illustrations retain their authored brightness instead
      -- of being dimmed or colour-cast by the clock. Only the hour tint is
      -- neutral here; depth and alpha-shaped lighting/shadows stay active.
      if card.noDayTint then Voxel3D.dayTint({ 1, 1, 1 }) end
      -- SPRITE LIGHT: UNLIT draws the card flat and full bright -- no cast
      -- shadow (nil snug) AND no hour/day tint, so a cave or night tint does
      -- not dim it. Most visible on the white arena fill, where a darkened
      -- card would read wrong; but it is flat/full-bright everywhere. SHADED
      -- (the default) keeps the tints and its own shadow, as intended.
      local unlit = UiBackplates.spritesUnlit()
      local savedTint = Voxel3D.tint
      if unlit then
        Voxel3D.tint = { 1, 1, 1 }
        Voxel3D.dayTint({ 1, 1, 1 })
        -- dayTint alone is not enough: the shared scene shader also samples
        -- the sun map. The old ternary-like `unlit and nil or snug` expression
        -- selected snug even when unlit (nil falls through `or`), so the card
        -- still received scene shadows and could darken on a white arena.
        -- Bypass the complete equation and restore it immediately afterward.
        Voxel3D.lighting(false)
      end
      local sunModel = not unlit and ShadowMap.snug(card.model) or nil
      Voxel3D.draw(BattleBillboard.mesh(), card.tex, card.model,
                   BattleBillboard.PULL, sunModel)
      if unlit then
        Voxel3D.lighting(true)
        Voxel3D.tint = savedTint
        Voxel3D.dayTint()
      end
      if card.noDayTint then Voxel3D.dayTint() end
    end
    Voxel3D.glass(true)
    Voxel3D.seams(true)
    -- Draw the physical Poke Ball in the same depth/flash window as the
    -- battlers. Pokeball brackets its own seam, glass and additive state.
    local cap = BattleScene.capture
    if cap and cap.draw then pcall(cap.draw, BattleBillboard.PULL) end
    if flashing then Voxel3D.flatten(nil) end
    -- grass and flowers ride the same camera-ward pull the free-roam pass
    -- gives them, measured against THIS camera's pitch rather than the
    -- orbit's -- there is no character here for them to overdraw, but the
    -- pull is also what keeps a tuft from z-fighting the floor it stands on
    if not flatFill then
    local pull = VoxelScene.pull(math.max(pitch, 0.05))
    Voxel3D.draw(ChunkMesher.grass(host), atlasFor(host), nil, pull)
    for _, nb in ipairs(neighbors) do
      Voxel3D.draw(ChunkMesher.grass(nb.map), atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy), pull)
    end
    local fpull = math.max(0, pull - 8 * math.sin(math.max(pitch, 0.05)))
    Voxel3D.draw(ChunkMesher.flowers(host), atlasFor(host), nil, fpull,
                 ShadowMap.snug(nil))
    for _, nb in ipairs(neighbors) do
      Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy), fpull,
                   ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
    end
    end
    local canvas = AntiAlias.resolve(Voxel3D.endScene(), pw, ph, "battle")
    if not canvas then return end

    local vp = Voxel3D.vp
    local pmx, pmy = BattleScene.toGB(vp, arena.player[1], groundY,
                                      arena.player[2], lx, ly, s, pw, ph)
    local emx, emy = BattleScene.toGB(vp, arena.enemy[1], groundY,
                                      arena.enemy[2], lx, ly, s, pw, ph)
    if not (pmx and emx) then return end
    -- How wide one overworld square is on screen where each mon stands, in
    -- GB pixels. This is what the pics are scaled to: a mon covers its own
    -- square and no more, at whatever the drift has done to the distance.
    -- Measure both world axes as 2D projected distances. A one-axis width
    -- collapses to zero when the head-on capture seat looks along that axis.
    local half = BattleScene.CELL / 2
    local function cellSpan(wx, wz)
      local x1, y1 = BattleScene.toGB(vp, wx - half, groundY, wz,
                                      lx, ly, s, pw, ph)
      local x2, y2 = BattleScene.toGB(vp, wx + half, groundY, wz,
                                      lx, ly, s, pw, ph)
      local x3, y3 = BattleScene.toGB(vp, wx, groundY, wz - half,
                                      lx, ly, s, pw, ph)
      local x4, y4 = BattleScene.toGB(vp, wx, groundY, wz + half,
                                      lx, ly, s, pw, ph)
      if not (x1 and x2 and x3 and x4) then return nil end
      local ew = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
      local ns = math.sqrt((x4 - x3) ^ 2 + (y4 - y3) ^ 2)
      return math.max(ew, ns)
    end
    local pSpan = cellSpan(arena.player[1], arena.player[2])
    local eSpan = cellSpan(arena.enemy[1], arena.enemy[2])
    if not (pSpan and eSpan) then return end
    out = {
      canvas = canvas,
      player = { pmx, pmy },
      enemy = { emx, emy },
      playerSpan = pSpan,
      enemySpan = eSpan,
      -- the letterbox, so the depth-of-field pass can put its sharp band on
      -- the two marks rather than on a fraction of the window
      lx = lx, ly = ly, scale = s, pw = pw, ph = ph,
      eye = { cam.eye[1], cam.eye[2], cam.eye[3] },
      focus = { cam.focus[1], cam.focus[2], cam.focus[3] },
      vp = vp,
      -- and the hour's light, for anything drawn over this shot that is NOT
      -- geometry and so never went past the shader that applied it -- the back
      -- pic pinned to the menu (see OverworldBattle.backPinned). Neutral
      -- indoors, which is what DayNight.tint answers for a room.
      tint = Voxel3D.tint,
    }
  end)
  -- the placed camera is ours for exactly this pass; anything else that
  -- renders (the free-roam pipeline, next frame) must find the orbit back
  Voxel3D.camera = nil
  Voxel3D.SHADOW_ALPHA = sunWas
  if not ok then
    -- endScene never ran, so the canvas is still bound and the shader still
    -- set; put the frame back the way it was found before rethrowing
    pcall(love.graphics.setShader)
    pcall(love.graphics.setDepthMode)
    pcall(love.graphics.setCanvas)
    error(err, 0)
  end
  return out
end

return BattleScene
