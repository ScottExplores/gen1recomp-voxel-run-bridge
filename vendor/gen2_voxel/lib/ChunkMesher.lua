-- Voxel world mode: turn a map's tile layer into one static 3D mesh.
--
-- The scene description comes from Structures.lua, which -- 3dSen-style --
-- detects each connected drawn thing on the map and picks its model:
--
--   flat      ground / water / void: a single quad.
--   top art   ledges, roofs (profile-authored): a box with the art on its
--             TOP face; partial side bands crop the art (a 6px ledge face
--             is the bottom of the lip drawing).
--   volume    walls, buildings, tree lines: each column rises to the
--             structure's REAL drawn height (Structures measures it,
--             repeat-aware and region-consistent -- a 6-row house is 48px,
--             a 40-row border forest is rows of 16px trees). The south
--             face folds the full artwork upright, 8px band by band, band
--             k sampling the map row k tiles north; the top wears the
--             structure's top rows.
--   object    small props with a silhouette (plants, signs, lone trees):
--             per-pixel voxel prisms prebuilt by Structures, standing on
--             synthesized ground -- this mesher just emits their quads.
--             Round trees arrive as STAMPS (a shared hull template plus a
--             cell offset) and expand here, straight into the vertex
--             stream, so no map retains per-cell copies of its forests.
--
-- Side faces are never stretched: all sides are 8px bands with the art
-- tiled per band and cropped at partial bands.
--
-- Texturing samples the TILESET ATLAS, not a rendered copy of the map. The
-- atlas is 128x48; a map-space canvas covering the biggest routes would be
-- ~5 MB each with up to five live at once (connected maps), which is real
-- memory on the mobile targets. Sampling the atlas costs 24 KB, and costs
-- nothing in fidelity because TerrainAtlas hands back the same atlas
-- TileRenderer draws with -- including the fully recolored one RED++
-- bakes -- so terrain color comes through untouched.
--
-- BUILDS ARE ASYNCHRONOUS. A frame never blocks on meshing: VoxelScene
-- requests what it wants to draw, request() queues a build job, and
-- pump() -- called once a frame from the pipeline's update -- advances
-- the queue inside a few-millisecond budget (BuildBudget suspends the
-- job's coroutine mid-loop when the slice is spent). Until a mesh lands
-- the scene simply draws without it: the engine's flat path while the
-- current map has nothing, the body-only variant while the full one (the
-- border ring) is still cooking, neighbours popping in as they finish.
-- The synchronous get() remains for probes and tests.
--
-- Meshes are cached per map id and EVICTED down to the live set (current
-- map + connected neighbours) whenever that set changes -- setLive()
-- releases far maps' GPU meshes and their Structures analysis, which is
-- what used to grow the heap by gigabytes over a cross-region trek.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")
local Structures = V.require("Structures")
local TileShape = V.require("TileShape")
local Voxel3D = V.require("Voxel3D")
local Budget = V.require("BuildBudget")
local Quality = V.require("Quality")
local DiskCache = V.require("VoxelDiskCache")
local EngineCompat = V.require("EngineCompat")

local ffi = nil
do
  local ok, mod = pcall(require, "ffi")
  if ok then ffi = mod end
end

local ChunkMesher = {}

-- `ledgeDepth` is presentation only. Gold's own collision tables and hop
-- scripts remain the gameplay authority; this function changes only the
-- height emitted into Scott's terrain mesh. Missing/older hosts preserve the
-- established raised ledge art.
local function ledgeDepthEnabled()
  local options = V and V.mod and V.mod.options
  if options and type(options.get) == "function" then
    local ok, value = pcall(options.get, options, "ledgeDepth")
    if ok and value ~= nil then return value ~= false end
  end
  return true
end

local function visualHeight(shape)
  if not shape then return 0 end
  if shape.class == "ledge" and not ledgeDepthEnabled() then return 0 end
  return shape.h or 0
end

ChunkMesher.ledgeDepthEnabled = ledgeDepthEnabled
ChunkMesher.visualHeight = visualHeight

-- Ring of border blocks meshed around the body. v0.2.03 doubles the real
-- outdoor scenery apron from four to eight blocks (32 tiles) so the free,
-- battle and wide diorama cameras keep seeing forest instead of reaching the
-- end of generated geometry. This is actual meshed scenery, not a draw-only
-- backdrop, and connected-neighbour masking below still removes overlap.
local RING = 8

-- A sliver of a texel, to keep a quad's sampling inside its own tile.
-- Without any inset the perspective rasteriser lands on a NEIGHBOURING
-- tile's texel along the shared edge and stitches bright seams across the
-- whole map.
--
-- It has to be a sliver and not, as it first was, half a texel. A tile is
-- 8 texels of art across 8 world pixels -- one texel per pixel exactly --
-- and insetting the uv by half a texel at each end squeezes that art into
-- a 7-texel sample range while the quad still covers 8 world pixels. The
-- art then advances 7/8 of a texel per pixel: boundaries drift off the
-- pixel grid, one art pixel gets sampled twice and another never at all.
-- Nothing showed it until the voxel wireframe drew the grid those pixels
-- were supposed to be sitting on. Interpolation error is nowhere near a
-- fiftieth of a texel, so this is as safe against bleed and costs 0.25% of
-- a pixel of drift across a whole tile.
local INSET = 0.02

-- The south face of a volume is the artwork itself, so it draws at full
-- brightness; its top face darkens a touch so the plateau behind a
-- standing drawing reads as depth rather than repeating the same art at
-- the same energy.
local VOLUME_TOP_SHADE = 0.85

local cache = {}     -- map id -> { full = mesh|false, body = ..., grass = ... }
-- A failed async build used to be indistinguishable from a build that was
-- merely still pending.  Gold's compose bridge needs the actual error so it
-- can stop silently returning the flat world forever.
local lastErrors = {} -- map id -> most recent terrain-mesh build error
local gen = {}       -- map id -> generation, bumped by invalidate/evict

-- Horizontal neighbours: tile step, face direction id (see Voxel3D).
local SIDES = {
  { 1, 0, 1 },    -- +X east
  { -1, 0, 2 },   -- -X west
  { 0, 1, 5 },    -- +Z south
  { 0, -1, 6 },   -- -Z north
}

local function keyOf(tx, ty)
  return (ty + 64) * 4096 + (tx + 64)
end

-- ------------------------------------------------------------ vertex sinks

-- A sink accepts quads (4 corners, 4 uv pairs, flat or per-corner shade)
-- and finishes into a drawable mesh. The TABLE sink reproduces the
-- historical pure-Lua output -- geometry() returns its arrays for the
-- headless suite. The FFI sink packs the same six floats per vertex
-- straight into one growing native buffer, unindexed (v1 v2 v3 v1 v3 v4),
-- skipping ~a million short-lived Lua tables per route and LOVE's slow
-- table-by-table vertex upload.

local function newTableSink()
  local verts, indices, quads = {}, {}, 0
  local function pushRaw(x1, y1, z1, u1, v1,
                         x2, y2, z2, u2, v2,
                         x3, y3, z3, u3, v3,
                         x4, y4, z4, u4, v4, shade)
    local flat = type(shade) ~= "table"
    verts[#verts + 1] = { x1, y1, z1, u1, v1, flat and shade or shade[1] }
    verts[#verts + 1] = { x2, y2, z2, u2, v2, flat and shade or shade[2] }
    verts[#verts + 1] = { x3, y3, z3, u3, v3, flat and shade or shade[3] }
    verts[#verts + 1] = { x4, y4, z4, u4, v4, flat and shade or shade[4] }
    Voxel3D.pushQuad(indices, quads)
    quads = quads + 1
  end
  return {
    pushRaw = pushRaw,
    push = function(c, uv, shade)
      pushRaw(c[1][1], c[1][2], c[1][3], uv[1][1], uv[1][2],
              c[2][1], c[2][2], c[2][3], uv[2][1], uv[2][2],
              c[3][1], c[3][2], c[3][3], uv[3][1], uv[3][2],
              c[4][1], c[4][2], c[4][3], uv[4][1], uv[4][2], shade)
    end,
    results = function()
      return verts, indices, quads
    end,
    finish = function()
      return Voxel3D.newMesh(verts, indices)
    end,
  }
end

local function newFfiSink()
  local cap = 4096 * 6
  local buf = ffi.new("float[?]", cap * 6)
  local n = 0
  local sink

  -- Hot-path quad writer. Terrain used to construct two nested Lua tables
  -- (corners + UVs) for every face even on the FFI sink, only to unpack them
  -- again here. Route-sized builds can emit hundreds of thousands of faces, so
  -- that transient allocation was a major source of GC pressure and frame-time
  -- spikes. The packed path writes the same six unindexed vertices directly.
  local function pushRaw(x1, y1, z1, u1, v1,
                         x2, y2, z2, u2, v2,
                         x3, y3, z3, u3, v3,
                         x4, y4, z4, u4, v4, shade)
    if n + 6 > cap then
      local grown = ffi.new("float[?]", cap * 2 * 6)
      ffi.copy(grown, buf, n * 6 * 4)
      buf, cap = grown, cap * 2
    end
    local flat = type(shade) ~= "table"
    local s1 = flat and shade or shade[1]
    local s2 = flat and shade or shade[2]
    local s3 = flat and shade or shade[3]
    local s4 = flat and shade or shade[4]
    local base = n * 6

    -- 1,2,3, 1,3,4 -- identical winding to TRI_ORDER/pushQuad.
    buf[base] = x1; buf[base + 1] = y1; buf[base + 2] = z1
    buf[base + 3] = u1; buf[base + 4] = v1; buf[base + 5] = s1
    base = base + 6
    buf[base] = x2; buf[base + 1] = y2; buf[base + 2] = z2
    buf[base + 3] = u2; buf[base + 4] = v2; buf[base + 5] = s2
    base = base + 6
    buf[base] = x3; buf[base + 1] = y3; buf[base + 2] = z3
    buf[base + 3] = u3; buf[base + 4] = v3; buf[base + 5] = s3
    base = base + 6
    buf[base] = x1; buf[base + 1] = y1; buf[base + 2] = z1
    buf[base + 3] = u1; buf[base + 4] = v1; buf[base + 5] = s1
    base = base + 6
    buf[base] = x3; buf[base + 1] = y3; buf[base + 2] = z3
    buf[base + 3] = u3; buf[base + 4] = v3; buf[base + 5] = s3
    base = base + 6
    buf[base] = x4; buf[base + 1] = y4; buf[base + 2] = z4
    buf[base + 3] = u4; buf[base + 4] = v4; buf[base + 5] = s4
    n = n + 6
  end

  sink = {
    pushRaw = pushRaw,
    push = function(c, uv, shade)
      pushRaw(c[1][1], c[1][2], c[1][3], uv[1][1], uv[1][2],
              c[2][1], c[2][2], c[2][3], uv[2][1], uv[2][2],
              c[3][1], c[3][2], c[3][3], uv[3][1], uv[3][2],
              c[4][1], c[4][2], c[4][3], uv[4][1], uv[4][2], shade)
    end,
    vertexCount = function()
      return n
    end,
    -- Serialize the native float buffer through the ENGINE persistence
    -- backend.  Normal LÖVE files stream in ~1.5MB chunks with cooperative
    -- budget checks; portable-mode's simpler write-only backend falls back to
    -- one string write without ever touching raw io/love.filesystem here.
    writeRaw = function(_, fs, path)
      if n == 0 then
        if fs and type(fs.remove) == "function" then pcall(fs.remove, path) end
        return true
      end
      if not (fs and type(fs.write) == "function") then
        return false, "persistence filesystem is not writable"
      end
      local totalBytes = n * 6 * 4
      if type(fs.newFile) == "function" then
        local okFile, file = pcall(fs.newFile, path)
        if okFile and file then
          local okOpen, opened = pcall(file.open, file, "w")
          if okOpen and opened ~= false then
            local at = 0
            local CHUNK = 65536
            while at < n do
              local count = math.min(CHUNK, n - at)
              local bytes = count * 6 * 4
              local chunk = ffi.string(buf + at * 6, bytes)
              local okWrite, wrote = pcall(file.write, file, chunk)
              if not okWrite or wrote == false then
                pcall(file.close, file)
                return false, "cached mesh write failed"
              end
              at = at + count
              Budget.check()
            end
            pcall(file.close, file)
            return true
          end
        end
      end
      local raw = ffi.string(buf, totalBytes)
      local okWrite, wrote, err = pcall(fs.write, path, raw)
      if not okWrite then return false, tostring(wrote) end
      if wrote == false then return false, tostring(err or "cached mesh write failed") end
      return true
    end,
    finish = function()
      if n == 0 then return nil end
      -- upload in slices with budget ticks between: a route-sized mesh
      -- is ~10-20MB and one atomic setVertices was the last remaining
      -- frame spike. The mesh is not cached (so never drawn) until the
      -- whole upload lands, and LuaJIT yields fine across pcall.
      local ok, mesh = pcall(function()
        local m = love.graphics.newMesh(Voxel3D.FORMAT, n,
                                        "triangles", "static")
        local CHUNK = 65536              -- vertices per slice (~1.5MB)
        local i = 0
        while i < n do
          local count = math.min(CHUNK, n - i)
          local bytes = count * 6 * 4
          local data = love.data.newByteData(bytes)
          ffi.copy(data:getFFIPointer(), buf + i * 6, bytes)
          m:setVertices(data, i + 1)
          data:release()
          i = i + count
          Budget.check()
        end
        return m
      end)
      return ok and mesh or nil
    end,
  }
  return sink
end

local function newSink()
  if ffi and love and love.data and love.data.newByteData
     and love.graphics and love.graphics.newMesh then
    return newFfiSink()
  end
  return newTableSink()
end

-- -------------------------------------------------------------- geometry

-- Emit the raw geometry for `map` into `sink`. `bodyOnly` skips the
-- border ring -- the shape the 2D path's drawMapOnly has always had: a
-- neighbour map contributes its body, and only the CURRENT map supplies
-- the ring around the view.
--
-- `masks` (full variant only) lists rectangles, in this map's world
-- pixels, where connected neighbour BODIES sit: ring geometry inside them
-- is suppressed. The 2D renderer never needed this because it painted
-- neighbour bodies OVER the ring; with a depth buffer the ring's standing
-- trees would rise straight through the neighbour's flat ground -- cross
-- into Route 1 and a wall of border trees sprouts over Pallet.
--
-- Kept free of any GPU call so it can be exercised headless -- the
-- geometry is the part with the interesting invariants, and a suite that
-- needed a real GL context to check them would never run in CI.
-- `waterSink`, when given, takes the WATER SURFACE quads instead of the
-- main sink -- the one class in this world that is drawn as its own pass
-- (see Water: a mirror cannot be drawn until what it reflects exists).
-- Nothing else moves: the quads are the same quads, emitted by the same
-- corner and uv arithmetic at the same recessed height, and the shoreline
-- faces around them still belong to the GROUND that exposes them.
--
-- Omitted, water stays in the terrain mesh exactly as it always did, which
-- is what the headless geometry() below and the sun's own pass both want.
local function runGeometry(map, bodyOnly, masks, sink, waterSink)
  local push = sink.push
  local pushRaw = sink.pushRaw
  local waterPush = waterSink and waterSink.push or nil
  local waterRaw = waterSink and waterSink.pushRaw or nil
  local tileset = map.tileset
  local S = Structures.forMap(map)
  -- Pull the hottest structure tables into locals. `heightAt` is called for
  -- AO, face exposure and corner shading many times per tile; avoiding repeated
  -- S.* hash lookups matters on the route-sized meshes this module builds.
  local shapeAt, tileAt = S.shapeAt, S.tileAt
  local skipAt, runsAt, groundAt = S.skip, S.runs, S.ground
  local perRow = tileset.tilesPerRow or 16
  local atlasW = tileset.imageWidth or (perRow * 8)
  local atlasH = tileset.imageHeight or 48
  local invAtlasW, invAtlasH = 1 / atlasW, 1 / atlasH

  -- Height queries repeat heavily around each visible column. Cache the scalar
  -- answer once per keyed cell instead of walking skip/runs/shape tables for
  -- every AO corner and every side. Zero is a valid cached value in Lua.
  local heightCache = {}
  local function heightAt(tx, ty)
    local k = keyOf(tx, ty)
    local cached = heightCache[k]
    if cached ~= nil then return cached end
    local h
    if skipAt[k] then
      h = 0
    else
      local run = runsAt[k]
      if run then
        h = run.h
      else
        local shape = shapeAt[k]
        h = visualHeight(shape)
      end
    end
    heightCache[k] = h
    return h
  end

  -- Full-tile UVs are by far the common case. Cache those four scalars per
  -- tile; cropped partial bands still use the exact historical math. Using
  -- reciprocal multiplies also removes four divides from every uncached call.
  local fullU0, fullU1, fullV0, fullV1 = {}, {}, {}, {}
  local function uvRect(tile, vTop, vBot)
    if vTop == 0 and vBot == 8 then
      local u0 = fullU0[tile]
      if u0 ~= nil then
        return u0, fullU1[tile], fullV0[tile], fullV1[tile]
      end
      local ax = (tile % perRow) * 8
      local ay = math.floor(tile / perRow) * 8
      u0 = (ax + INSET) * invAtlasW
      local u1 = (ax + 8 - INSET) * invAtlasW
      local v0 = (ay + INSET) * invAtlasH
      local v1 = (ay + 8 - INSET) * invAtlasH
      fullU0[tile], fullU1[tile] = u0, u1
      fullV0[tile], fullV1[tile] = v0, v1
      return u0, u1, v0, v1
    end
    local ax = (tile % perRow) * 8
    local ay = math.floor(tile / perRow) * 8
    local vi = math.min(INSET, (vBot - vTop) / 4)
    return (ax + INSET) * invAtlasW, (ax + 8 - INSET) * invAtlasW,
           (ay + vTop + vi) * invAtlasH, (ay + vBot - vi) * invAtlasH
  end

  -- ------------------------------------------------------ ambient occlusion
  --
  -- Ambient light is what reaches a surface from the sky at large, so it is
  -- blocked by how much geometry crowds a point rather than by where the
  -- sun happens to be -- which makes it the exact complement of the shadow
  -- pass, and the reason both are worth having. The shadow map draws the
  -- long directional shadow a building throws; this draws the dark seam in
  -- every corner the sky cannot see into, at every scale finer than a
  -- shadow map texel.
  --
  -- Baked per vertex, the classic voxel way: each corner counts the
  -- neighbours that crowd it and steps down once per neighbour, and the
  -- rasteriser interpolates the steps into a smooth falloff. Costs exactly
  -- nothing at draw time, and it is resolution-independent -- a screen
  -- space pass would blur across the pixel grid this whole mode is built
  -- to keep crisp.
  --
  -- (What was here before was a one-directional contact shadow keyed to a
  -- sun in the northwest: two neighbours, one corner, top faces only.)

  -- Intensity. Both terms below are DARKENING amounts rather than
  -- multipliers, so this one number scales the whole effect: 1.0 is the
  -- barely-there first cut, and everything is expressed against it.
  local AO_STRENGTH = 2.4
  local AO_STEP = 0.09 * AO_STRENGTH      -- per crowding neighbour, max 3
  local AO_EDGE = 1 - 0.14 * AO_STRENGTH  -- creases / corners on a face
  local AO_GROUND = 0.12 * AO_STRENGTH    -- a prop's contact with the floor
  local AO_RISE = 6                       -- px over which the floor lets go
  local AO_FLOOR = 0.25                   -- never let a vertex reach black

  -- Both sinks copy a per-corner shade straight out into the vertex stream
  -- and keep no reference, so these two scratch rows are reused for every
  -- quad on the map rather than allocating a table per face -- a route
  -- builds a few hundred thousand of them.
  local aoTop = { 0, 0, 0, 0 }
  local aoSide = { 0, 0, 0, 0 }

  -- A top face's four corners, each occluded by the three cells that touch
  -- it: two edge neighbours and the diagonal between them.
  local function aoShades(tx, ty, h, shade)
    local n = heightAt(tx, ty - 1) > h
    local s = heightAt(tx, ty + 1) > h
    local e = heightAt(tx + 1, ty) > h
    local w = heightAt(tx - 1, ty) > h
    local nw = heightAt(tx - 1, ty - 1) > h
    local ne = heightAt(tx + 1, ty - 1) > h
    local sw = heightAt(tx - 1, ty + 1) > h
    local se = heightAt(tx + 1, ty + 1) > h
    if not (n or s or e or w or nw or ne or sw or se) then return shade end
    local function corner(a, b, d)
      local k = 0
      if a then k = k + 1 end
      if b then k = k + 1 end
      -- a diagonal wedged behind both of its edges adds nothing: the
      -- corner is already as enclosed as it can get, and counting it
      -- again is what turns an ordinary inside corner black
      if d and not (a and b) then k = k + 1 end
      -- floored, so cranking AO_STRENGTH deepens the seams instead of
      -- punching holes of pure black through the world
      return shade * math.max(AO_FLOOR, 1 - AO_STEP * k)
    end
    -- corners in topQuad order: NW, NE, SE, SW
    aoTop[1], aoTop[2] = corner(n, w, nw), corner(n, e, ne)
    aoTop[3], aoTop[4] = corner(s, e, se), corner(s, w, sw)
    return aoTop
  end

  -- The same idea on an upright face, where the crowding is of two kinds:
  -- the CREASE it rises out of (the band sitting on the ground, or on
  -- whatever lower neighbour exposed the face) and the INSIDE CORNERS
  -- where the columns flanking it stand proud of the band. `hl`/`hr` are
  -- those flanking heights in FACE order -- left then right as seen from
  -- outside, per LATERAL below -- so the shades line up with sideQuad's
  -- corners without the caller thinking about compass directions.
  local LATERAL = {
    [1] = { 0, 1, 0, -1 },    -- east face:  left south, right north
    [2] = { 0, -1, 0, 1 },    -- west face:  left north, right south
    [5] = { -1, 0, 1, 0 },    -- south face: left west,  right east
    [6] = { 1, 0, -1, 0 },    -- north face: left east,  right west
  }
  -- Ground contact for the prebuilt prop quads -- the per-pixel plants,
  -- signs and lone trees, and the round-tree stamps. Those arrive from
  -- Structures already finished, so the neighbour counting above has no
  -- columns to count. What it CAN say is that the ground plane itself
  -- blocks half the sky, so the closer a voxel sits to it the less ambient
  -- light reaches it -- which is what plants a prop on the floor instead
  -- of leaving it looking pasted over the top.
  local aoProp = { 0, 0, 0, 0 }
  local function groundShades(c, shade)
    if type(shade) == "table" then return shade end
    local y1, y2, y3, y4 = c[1][2], c[2][2], c[3][2], c[4][2]
    if math.min(y1, y2, y3, y4) >= AO_RISE then return shade end
    for i = 1, 4 do
      local t = c[i][2] / AO_RISE
      aoProp[i] = shade * (t >= 1 and 1 or (1 - AO_GROUND * (1 - t)))
    end
    return aoProp
  end

  local AO_CORNER = math.max(AO_FLOOR, AO_EDGE * AO_EDGE)  -- crease AND flank
  local function sideShades(hl, hr, y0, y1, crease, shade)
    if not (crease or hl > y0 or hr > y0) then return shade end
    -- corners run bottom-left, bottom-right, top-right, top-left
    local base = crease and AO_EDGE or 1
    aoSide[1] = shade * (hl > y0 and (crease and AO_CORNER or AO_EDGE) or base)
    aoSide[2] = shade * (hr > y0 and (crease and AO_CORNER or AO_EDGE) or base)
    aoSide[3] = shade * (hr > y1 and AO_EDGE or 1)
    aoSide[4] = shade * (hl > y1 and AO_EDGE or 1)
    return aoSide
  end

  -- `to` routes the quad somewhere other than the main sink -- the water
  -- surface is the only caller that ever does (see runGeometry's header).
  local function topQuad(x0, z0, h, tile, shade, toWater)
    local u0, u1, v0, v1 = uvRect(tile, 0, 8)
    local shaded = aoShades(x0 / 8, z0 / 8, h, shade)
    local raw = toWater and waterRaw or (not toWater and pushRaw or nil)
    if raw then
      raw(x0,     h, z0,     u0, v0,
          x0 + 8, h, z0,     u1, v0,
          x0 + 8, h, z0 + 8, u1, v1,
          x0,     h, z0 + 8, u0, v1, shaded)
    else
      local target = toWater and waterPush or push
      target({ { x0, h, z0 }, { x0 + 8, h, z0 },
               { x0 + 8, h, z0 + 8 }, { x0, h, z0 + 8 } },
             { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, shaded)
    end
  end

  -- vertical quad for face direction `d` of the tile column at (x0, z0),
  -- spanning heights [y0, y1] and showing art rows [vTop, vBot] of `tile`.
  -- Corners run bottom-left, bottom-right, top-right, top-left as seen
  -- from outside; u follows +X on the north/south faces so a door or sign
  -- never draws mirrored.
  local function sideQuad(d, x0, z0, y0, y1, tile, vTop, vBot, shade)
    local x1, z1 = x0 + 8, z0 + 8
    local u0, u1, v0, v1 = uvRect(tile, vTop, vBot)
    if pushRaw then
      if d == 5 then                                     -- south, at z1
        pushRaw(x0, y0, z1, u0, v1, x1, y0, z1, u1, v1,
                x1, y1, z1, u1, v0, x0, y1, z1, u0, v0, shade)
      elseif d == 6 then                                 -- north, at z0
        pushRaw(x1, y0, z0, u0, v1, x0, y0, z0, u1, v1,
                x0, y1, z0, u1, v0, x1, y1, z0, u0, v0, shade)
      elseif d == 1 then                                 -- east, at x1
        pushRaw(x1, y0, z1, u0, v1, x1, y0, z0, u1, v1,
                x1, y1, z0, u1, v0, x1, y1, z1, u0, v0, shade)
      else                                               -- west, at x0
        pushRaw(x0, y0, z0, u0, v1, x0, y0, z1, u1, v1,
                x0, y1, z1, u1, v0, x0, y1, z0, u0, v0, shade)
      end
      return
    end
    local c
    if d == 5 then
      c = { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 } }
    elseif d == 6 then
      c = { { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 } }
    elseif d == 1 then
      c = { { x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 } }
    else
      c = { { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 } }
    end
    push(c, { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, shade)
  end

  local def = map.def
  local tw, th = def.width * 4, def.height * 4         -- map size in tiles
  local r = bodyOnly and 0 or RING * 4

  -- true when the (ring) position lies under a connected neighbour's body
  local function masked(px0, pz0, px1, pz1)
    if not masks then return false end
    for _, mk in ipairs(masks) do
      if px1 > mk[1] and px0 < mk[3] and pz1 > mk[2] and pz0 < mk[4] then
        return true
      end
    end
    return false
  end

  -- The inclusive variant for OBJECT quads: a quad TOUCHING a neighbour
  -- body counts as under it. The old test took the quad's center with
  -- strict bounds, and a quad whose center sat exactly on the body's
  -- edge line escaped the mask -- stringing stray pixel fragments of
  -- otherwise-dropped border trees along every map seam.
  local function maskedClosed(px0, pz0, px1, pz1)
    if not masks then return false end
    for _, mk in ipairs(masks) do
      if px1 >= mk[1] and px0 <= mk[3] and pz1 >= mk[2] and pz0 <= mk[4] then
        return true
      end
    end
    return false
  end

  for ty = -r, th + r - 1 do
    for tx = -r, tw + r - 1 do
      Budget.tick()
      local k = keyOf(tx, ty)
      local s, tile = shapeAt[k], tileAt[k]
      local inBody = tx >= 0 and ty >= 0 and tx < tw and ty < th
      if not inBody and masked(tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8) then
        s = nil
      end

      -- Under the TREES fill the border wall is MODELLED or it is not there
      -- (see Structures' hullRingOnly): a ring cell nothing claimed would
      -- be a flat-topped box standing beside carved trunks, which reads as
      -- a painted-on plateau rather than forest. Structures already stops
      -- the ring at the carve distance; this catches the odd cell inside it
      -- that the 2x2 grouping could not take -- a canopy whose partners
      -- fall outside the shortened ring is left unclaimed, and one strip of
      -- boxes along an edge is the whole artefact this avoids.
      if not inBody and S.hideBareRing and not skipAt[k]
          and not (s and s.class == "water") then
        s = nil
      end

      if s and skipAt[k] then
        -- an object stands here; paint its synthesized ground and let the
        -- prebuilt prism quads (appended below) carry the art
        local g = groundAt[k]
        if g then
          topQuad(tx * 8, ty * 8, 0, g, 1)
          -- the claimed tile is still ground at height 0, and water next
          -- door still recesses below it: without the same below-ground
          -- side bands ordinary ground emits, the two-pixel shoreline
          -- face is a slit into the sky behind the mesh -- which is
          -- exactly what a building plot or a sign standing at the
          -- waterline showed. Same bands, cut from the synthesized
          -- ground's own art
          for _, side in ipairs(SIDES) do
            local nh = heightAt(tx + side[1], ty + side[2])
            if nh < 0 then
              local d = side[3]
              local lat = LATERAL[d]
              local hl = lat and heightAt(tx + lat[1], ty + lat[2]) or 0
              local hr = lat and heightAt(tx + lat[3], ty + lat[4]) or 0
              for band = math.floor(nh / 8), -1 do
                local y0 = math.max(nh, band * 8)
                local y1 = math.min(0, band * 8 + 8)
                if y1 > y0 then
                  sideQuad(d, tx * 8, ty * 8, y0, y1, g,
                           (band * 8 + 8) - y1, (band * 8 + 8) - y0,
                           sideShades(hl, hr, y0, y1, y0 <= nh,
                                      Voxel3D.FACE_SHADE[d]))
                end
              end
            end
          end
        end
      elseif s then
        local run = runsAt[k]
        local h = run and run.h or visualHeight(s)
        local x0, z0 = tx * 8, ty * 8

        -- top face. A roofed volume gets a GABLE segment: the roof rises
        -- from the facade top at the south eave to a ridge across the
        -- footprint's middle, then falls back to the facade at the north
        -- edge -- so the far side sits LOW. (The first cut was a shed
        -- plane rising all the way north, which turns a building into a
        -- ramp.) The south slope wears the structure's roof rows (ridge
        -- art at the ridge, eaves art at the eave); the back slope
        -- mirrors them. Exposed east/west flanks hip: their outer edge
        -- drops toward the eave, rounding the drawn corner tiles into 45
        -- degree corners. Flat-topped volumes wear their top rows;
        -- everything else its own art.
        if run and run.rise > 0 then
          local mid = run.extent / 2
          local d0 = run.front - ty                -- rows from the south edge
          -- Keep this arithmetic inline: the old local gableH closure was
          -- recreated for every roof tile during meshing.
          local tS = d0 <= mid and d0 / mid
                     or (run.extent - d0) / (run.extent - mid)
          local d1 = d0 + 1
          local tN = d1 <= mid and d1 / mid
                     or (run.extent - d1) / (run.extent - mid)
          local hS = run.h + run.rise * math.max(0, math.min(1, tS))
          local hN = run.h + run.rise * math.max(0, math.min(1, tN))
          -- art by proximity to the ridge, mirrored over the back
          local rel = 1 - math.abs(d0 + 0.5 - mid) / math.max(mid, 0.5)
          local idx = math.min(run.roofRows - 1,
                               math.floor((1 - rel) * run.roofRows))
          local roofTile = map:tileAt(tx, run.north + idx)
          local swY, seY, neY, nwY = hS, hS, hN, hN
          if heightAt(tx - 1, ty) < run.h then     -- west flank: hip
            swY = math.max(run.h, hS - 8)
            nwY = math.max(run.h, hN - 8)
          end
          if heightAt(tx + 1, ty) < run.h then     -- east flank: hip
            seY = math.max(run.h, hS - 8)
            neY = math.max(run.h, hN - 8)
          end
          local u0, u1, v0, v1 = uvRect(roofTile, 0, 8)
          if pushRaw then
            pushRaw(x0, swY, z0 + 8, u0, v1,
                    x0 + 8, seY, z0 + 8, u1, v1,
                    x0 + 8, neY, z0, u1, v0,
                    x0, nwY, z0, u0, v0, 0.95)
          else
            push({ { x0, swY, z0 + 8 }, { x0 + 8, seY, z0 + 8 },
                   { x0 + 8, neY, z0 }, { x0, nwY, z0 } },
                 { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, 0.95)
          end
        elseif run then
          local m = math.min(2, run.extent)
          local topTile = map:tileAt(tx, run.north + ((ty - run.north) % m))
          topQuad(x0, z0, h, topTile, VOLUME_TOP_SHADE)
        else
          local topTile = tile
          if s.art == "upright" and s.authored then
            -- Top art for a pinned box.  A furniture drawing is top-view
            -- rows over floor(h/8) face-on rows the fold stands upright;
            -- a face row's top would repeat its front art lying flat, so
            -- it wears the nearest row above the face block instead --
            -- the drawn tabletop (and whatever sits on it) stays on top,
            -- and a fully-folded structure (wall, desk) tops with its
            -- northmost row.
            local north, front = ty, ty
            while ty - north < 6 do
              local bs = shapeAt[keyOf(tx, north - 1)]
              if bs and bs.authored and bs.class == s.class then
                north = north - 1
              else
                break
              end
            end
            while front - ty < 6 do
              local bs = shapeAt[keyOf(tx, front + 1)]
              if bs and bs.authored and bs.class == s.class then
                front = front + 1
              else
                break
              end
            end
            local row = math.min(ty, front - math.floor(h / 8))
            if row < north then
              -- the whole run folded onto the face: top with the drawn
              -- row just above it when that row is furniture too (a
              -- bookcase wearing its shelf-top trim), else with the
              -- run's own top row
              local above = shapeAt[keyOf(tx, north - 1)]
              row = (above and above.authored and above.art == "upright")
                    and (north - 1) or north
            end
            topTile = tileAt[keyOf(tx, row)]
          end
          -- water's surface, and only water's: the recessed sheet itself,
          -- never the ground's shoreline bands around it. A cell an object
          -- stands on took the branch above and paints synthesized GROUND,
          -- which is right -- a sign at the waterline stands on a plot, not
          -- on the pond.
          topQuad(x0, z0, h, topTile,
                  s.art == "upright" and VOLUME_TOP_SHADE or 1,
                  (s.class == "water") and waterPush ~= nil)
        end

        -- sides: 8px bands wherever the neighbour is lower. Band k spans
        -- heights [8k, 8k+8) and shows one full tile of art; a partial
        -- band crops the art rows to match, so nothing ever stretches.
        for _, side in ipairs(SIDES) do
          local nh = heightAt(tx + side[1], ty + side[2])
          if nh < h then
            local d = side[3]
            -- the columns flanking this face, for the inside-corner term:
            -- fixed for the whole face, so they are read once rather than
            -- once per 8px band
            local lat = LATERAL[d]
            local hl = lat and heightAt(tx + lat[1], ty + lat[2]) or 0
            local hr = lat and heightAt(tx + lat[3], ty + lat[4]) or 0
            for band = math.floor(nh / 8), math.ceil(h / 8) - 1 do
              local y0 = math.max(nh, band * 8)
              local y1 = math.min(h, band * 8 + 8)
              if y1 > y0 then
                local src, shade = tile, Voxel3D.FACE_SHADE[d]
                if run then
                  -- fold the structure's artwork up this face: band k
                  -- samples the map row k tiles north of the structure's
                  -- front, clamped to its extent. The south face is the
                  -- drawing itself (full brightness); the other sides wear
                  -- the same rows darkened, so a building's flank matches
                  -- its face instead of smearing one tile
                  if d == 6 then
                    src = map:tileAt(tx, math.min(run.front,
                                                  run.north + band))
                  else
                    src = map:tileAt(tx, math.max(run.north,
                                                  run.front - band))
                  end
                  if d == 5 then shade = 1 end
                elseif s.art == "upright" then
                  -- profile-authored upright (a pinned wall or furniture
                  -- box): fold the drawing up the face, band 0 the
                  -- structure's southmost same-class row and higher bands
                  -- the rows north of it, repeating past the top.  The
                  -- south face is the drawing itself (full brightness);
                  -- flanks and back wear the same front stack darkened, so
                  -- a desk's side matches its face instead of smearing a
                  -- different jumble per row.
                  if d == 5 then shade = 1 end
                  local front = ty
                  while front < ty + 6 do
                    local fs2 = shapeAt[keyOf(tx, front + 1)]
                    if fs2 and fs2.authored and fs2.class == s.class then
                      front = front + 1
                    else
                      break
                    end
                  end
                  local fk = keyOf(tx, front - band)
                  local fs = shapeAt[fk]
                  if fs and fs.authored and fs.class == s.class then
                    src = tileAt[fk]
                  end
                end
                sideQuad(d, x0, z0, y0, y1, src,
                         (band * 8 + 8) - y1, (band * 8 + 8) - y0,
                         sideShades(hl, hr, y0, y1, y0 <= nh, shade))
              end
            end
          end
        end
      end
    end
  end

  -- Prebuilt quads from Structures (per-pixel voxel props, lathed
  -- columns) plus the round-tree stamps expanded in place. Keep rules,
  -- by the quad's own extent:
  --   body-only   the quad must overlap the OPEN body interval -- a
  --               neighbour's ring props must not march past its edge
  --               into this map, and a quad lying exactly ON the edge
  --               plane would z-fight the map that owns that plane.
  --   full        anything overlapping the body stays whole (props that
  --               straddle the edge no longer shed their outer half);
  --               pure ring quads drop when they touch a neighbour body
  --               (maskedClosed), which is what strings of seam pixels
  --               were: fragments of dropped border trees whose centers
  --               sat exactly on the boundary line.
  local bw, bh = tw * 8, th * 8
  local function keepQuad(x0, z0, x1, z1)
    local overBody = x1 > 0 and x0 < bw and z1 > 0 and z0 < bh
    if bodyOnly then return overBody end
    return overBody or not maskedClosed(x0, z0, x1, z1)
  end

  -- A face lying EXACTLY on a body boundary plane is ambiguous to the
  -- rect tests above: a body structure's outward facade (a Saffron row
  -- house whose front row is the map's last row, its south wall on the
  -- shared plane with Route 6) and the inward face of a ring scrap
  -- occupy the same degenerate rect, and the strict overBody plus the
  -- closed mask dropped BOTH -- which is why those facades were missing.
  -- The winding tells them apart: a face pointing AWAY from the body
  -- belongs to this map's own edge-row structure and nothing in the
  -- neighbour will ever draw that plane, so it stays; a face pointing
  -- INTO the body is the scrap the mask rules exist to kill, and falls
  -- through to them.
  local function outwardOnEdge(q, x0, z0, x1, z1)
    if z0 == z1 and (z0 == 0 or z0 == bh) and x1 > 0 and x0 < bw then
      local nz = (q[2][1] - q[1][1]) * (q[3][2] - q[1][2])
                 - (q[2][2] - q[1][2]) * (q[3][1] - q[1][1])
      return (z0 == bh and nz > 0) or (z0 == 0 and nz < 0)
    end
    if x0 == x1 and (x0 == 0 or x0 == bw) and z1 > 0 and z0 < bh then
      local nx = (q[2][2] - q[1][2]) * (q[3][3] - q[1][3])
                 - (q[2][3] - q[1][3]) * (q[3][2] - q[1][2])
      return (x0 == bw and nx > 0) or (x0 == 0 and nx < 0)
    end
    return false
  end

  local scUV = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
  local function quadUV(q)
    if q.uv then return q.uv end
    for i = 1, 4 do
      scUV[i][1], scUV[i][2] = q.u, q.v
    end
    return scUV
  end

  local function pushExisting(q, corners, shade)
    local uv = quadUV(q)
    if pushRaw then
      pushRaw(corners[1][1], corners[1][2], corners[1][3], uv[1][1], uv[1][2],
              corners[2][1], corners[2][2], corners[2][3], uv[2][1], uv[2][2],
              corners[3][1], corners[3][2], corners[3][3], uv[3][1], uv[3][2],
              corners[4][1], corners[4][2], corners[4][3], uv[4][1], uv[4][2], shade)
    else
      push(corners, uv, shade)
    end
  end

  for _, q in ipairs(S.objectQuads) do
    Budget.tick()
    local x0 = math.min(q[1][1], q[2][1], q[3][1], q[4][1])
    local x1 = math.max(q[1][1], q[2][1], q[3][1], q[4][1])
    local z0 = math.min(q[1][3], q[2][3], q[3][3], q[4][3])
    local z1 = math.max(q[1][3], q[2][3], q[3][3], q[4][3])
    -- q.own: a body-anchored structure's own quad (a building placed by
    -- Buildings.build, whose scan never leaves the body). Exempt from
    -- the edge keep-rules entirely: its eave legitimately overhangs the
    -- boundary plane into the neighbour's airspace, and no variant of
    -- the neighbour will ever draw that geometry
    if q.own or outwardOnEdge(q, x0, z0, x1, z1)
       or keepQuad(x0, z0, x1, z1) then
      pushExisting(q, q, groundShades(q, q.shade))
    end
  end

  -- true when the rect sits entirely inside one neighbour-body rect
  local function containedInMask(x0, z0, x1, z1)
    if not masks then return false end
    for _, mk in ipairs(masks) do
      if x0 >= mk[1] and x1 <= mk[3] and z0 >= mk[2] and z1 <= mk[4] then
        return true
      end
    end
    return false
  end

  -- round-tree stamps: the shared hull template translated per cell,
  -- through reusable scratch corners so expansion allocates nothing.
  -- A hull spans at most its own footprint -- one 16px cell unless the
  -- stamp carries a wider radius (the 2x2-cell canopy groups) -- so one
  -- rect test usually answers for the whole stamp: strictly interior
  -- stamps keep every quad, ring stamps buried under a neighbour body
  -- (or, body-only, ring stamps full stop) skip without touching their
  -- quads. Only stamps crossing a boundary walk quad by quad.
  local sc = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
  for _, st in ipairs(S.roundStamps or {}) do
    local mx, mz = st.mx, st.mz
    local sr = st.r or 8
    local sx0, sz0, sx1, sz1 = mx - sr, mz - sr, mx + sr, mz + sr
    local interior = sx0 > 0 and sx1 < bw and sz0 > 0 and sz1 < bh
    local overBody = sx1 > 0 and sx0 < bw and sz1 > 0 and sz0 < bh
    local keepAll, skipAll
    if bodyOnly then
      keepAll = interior
      skipAll = not overBody
    else
      keepAll = interior or not maskedClosed(sx0, sz0, sx1, sz1)
      skipAll = not overBody and containedInMask(sx0, sz0, sx1, sz1)
    end
    if not skipAll then
      for _, q in ipairs(st.quads) do
        Budget.tick()
        for i = 1, 4 do
          local c, s2 = q[i], sc[i]
          s2[1] = c[1] + mx
          s2[2] = c[2]
          s2[3] = c[3] + mz
        end
        local ok = keepAll
        if not ok then
          local x0 = math.min(sc[1][1], sc[2][1], sc[3][1], sc[4][1])
          local x1 = math.max(sc[1][1], sc[2][1], sc[3][1], sc[4][1])
          local z0 = math.min(sc[1][3], sc[2][3], sc[3][3], sc[4][3])
          local z1 = math.max(sc[1][3], sc[2][3], sc[3][3], sc[4][3])
          ok = keepQuad(x0, z0, x1, z1)
        end
        if ok then
          pushExisting(q, sc, groundShades(sc, q.shade))
        end
      end
    end
  end
end

-- The raw geometry for `map`: (vertex list, triangle index list, quad
-- count). Synchronous and GPU-free -- the headless suite and the probes
-- exercise the invariants through this.
--
-- `split` lifts the water surface out, as it is lifted out for the
-- reflective pass, and appends that sink's own three values -- so the suite
-- can check the same separation the GPU path relies on without a GPU.
-- Without it the water is in the first list, which is what every existing
-- caller reads.
function ChunkMesher.geometry(map, bodyOnly, masks, split)
  local sink = newTableSink()
  local waterSink = split and newTableSink() or nil
  runGeometry(map, bodyOnly, masks, sink, waterSink)
  if not waterSink then return sink.results() end
  local v, i, n = sink.results()
  local wv, wi, wn = waterSink.results()
  return v, i, n, wv, wi, wn
end

-- Build the mesh for `map` synchronously. Returns nil when there is
-- nothing to draw or meshes are unavailable (headless).
--
-- `split` asks for the water surface as a SECOND mesh, returned after the
-- terrain one -- the shape the reflective pass needs (see Water). Without
-- it the water is inside the terrain mesh, which is the historical
-- contract and what every other caller still wants.
function ChunkMesher.build(map, bodyOnly, masks, split)
  local sink = newSink()
  local waterSink = split and newSink() or nil
  runGeometry(map, bodyOnly, masks, sink, waterSink)
  return sink.finish(), waterSink and waterSink.finish() or nil
end

local function quadsMesh(quads)
  if #quads == 0 then return nil end
  local sink = newSink()
  local raw = sink.pushRaw
  for _, q in ipairs(quads) do
    local c1, c2, c3, c4 = q[1], q[2], q[3], q[4]
    local uv = q.uv
    if raw then
      if uv then
        raw(c1[1], c1[2], c1[3], uv[1][1], uv[1][2],
            c2[1], c2[2], c2[3], uv[2][1], uv[2][2],
            c3[1], c3[2], c3[3], uv[3][1], uv[3][2],
            c4[1], c4[2], c4[3], uv[4][1], uv[4][2], q.shade)
      else
        raw(c1[1], c1[2], c1[3], q.u, q.v,
            c2[1], c2[2], c2[3], q.u, q.v,
            c3[1], c3[2], c3[3], q.u, q.v,
            c4[1], c4[2], c4[3], q.u, q.v, q.shade)
      end
    else
      local scuv = uv or { { q.u, q.v }, { q.u, q.v },
                            { q.u, q.v }, { q.u, q.v } }
      sink.push(q, scuv, q.shade)
    end
  end
  return sink.finish()
end

-- The tall-grass rows as their own mesh: VoxelScene draws it AFTER the
-- characters so the southern row of a grass cell still overdraws a
-- walker's feet (characters stamp over terrain, Gen 1 style, so ordinary
-- terrain could never do this).
local function buildGrassMesh(map)
  return quadsMesh(Structures.forMap(map).grassQuads)
end

-- The flower billboards as their own mesh, for the same reason as the
-- grass one: it draws AFTER the characters WITH the same camera-ward
-- pull, so a flower south of a walker occludes their feet and one north
-- of them hides behind them. Baked into the terrain mesh they lost that
-- depth fight against the pulled character card whenever the player
-- stood among flowers. Unlike grass this mesh still CASTS shadows (the
-- sun pass draws it): a handful of flowers per meadow, not thousands of
-- tufts.
local function buildFlowerMesh(map)
  return quadsMesh(Structures.forMap(map).flowerQuads)
end

-- Authored FIGURES (a person drawn into furniture) as one mesh each, in
-- the card's own local space -- because each one is placed by its own
-- matrix at draw time, leaned back by the camera pitch exactly like a
-- character card (VoxelScene). A figure baked into the terrain mesh could
-- not lean, and a shared mesh could not carry per-figure placement.
--
-- A list, not a mesh: `{ mesh, wx, wz, y, w }` per figure. Maps have one
-- or none, so the loop that draws them is shorter than the terrain's.
-- `w` is the card's own width in its local space (its quads start at
-- x = 0), measured here because the first-person pass yaws a card about
-- its middle -- a card yawed about its left edge swings off its seat.
local function buildFigureMeshes(map)
  local out = {}
  for _, f in ipairs(Structures.forMap(map).figures or {}) do
    local mesh = quadsMesh(f.quads)
    if mesh then
      local w = 0
      for _, q in ipairs(f.quads) do
        for c = 1, 4 do
          local x = q[c] and q[c][1]
          if x and x > w then w = x end
        end
      end
      out[#out + 1] = { mesh = mesh, wx = f.wx, wz = f.wz, y = f.y, w = w }
    end
  end
  return out
end

-- Figure lists hold their meshes one level down, so the generic slot
-- release cannot reach them.
local function releaseFigures(list)
  for _, f in ipairs(type(list) == "table" and list or {}) do
    if f.mesh and f.mesh.release then pcall(f.mesh.release, f.mesh) end
  end
end

-- Replace a cached slot, releasing whatever mesh it held.
local function swapSlot(c, slot, mesh)
  local old = c[slot]
  if old and old ~= mesh and old.release then pcall(old.release, old) end
  c[slot] = mesh
end

-- ------------------------------------------------------------- the cache

local function entry(id)
  local c = cache[id]
  if not c then
    c = {}
    cache[id] = c
  end
  return c
end

-- The water surface that came out of a terrain slot's own build. Kept
-- beside it rather than in a slot of its own because the two are ONE
-- answer: a full mesh drawn beside a body build's water would draw the
-- ring's ponds twice and miss the body's own.
local function waterSlot(slot)
  return slot .. "Water"
end

local function releaseEntry(c)
  for _, slot in ipairs({ "full", "body", "fullWater", "bodyWater",
                          "grass", "flowers" }) do
    local mesh = c[slot]
    if mesh and mesh.release then pcall(mesh.release, mesh) end
    c[slot] = nil
  end
  releaseFigures(c.figures)
  c.figures = nil
  c.stale = nil
end

-- ---------------------------------------------------------- async builds

local jobs = {}       -- FIFO of pending jobs
local jobIndex = {}   -- key -> job
local warmStats = { queued = 0, completed = 0, hits = 0, cancelled = 0, errors = 0 }

local clock = (love and love.timer and love.timer.getTime) or os.clock

local function jobKey(id, slot)
  return id .. ":" .. slot
end

local function warmKey(id, slot)
  return "warm:" .. id .. ":" .. slot
end

local function removeJob(job)
  if not job then return end
  jobIndex[job.key or jobKey(job.id, job.slot)] = nil
  for i, j in ipairs(jobs) do
    if j == job then
      table.remove(jobs, i)
      break
    end
  end
end

local function finishJob(job, ok, err)
  removeJob(job)
  if job.cacheOnly then
    if not ok and not job.cancelled then
      warmStats.errors = warmStats.errors + 1
      if err then
        print("[warn] voxel cache warm failed for " .. tostring(job.id)
              .. ": " .. tostring(err))
      end
    end
    return
  end
  if not ok then
    -- name the reason: in a real session a lost build is a black map
    lastErrors[job.id] = tostring(err)
    print("[warn] voxel mesh build failed for " .. tostring(job.id)
          .. ": " .. tostring(err))
    if (gen[job.id] or 0) == job.gen then
      entry(job.id)[job.slot] = false
    end
  else
    lastErrors[job.id] = nil
  end
end

local function clearStale(c, slot)
  if not c.stale then return end
  c.stale[slot] = nil
  if not (c.stale.full or c.stale.body or c.stale.aux) then
    c.stale = nil
  end
end

local function buildAux(job, map, c)
  if c.grass ~= nil and c.flowers ~= nil and c.figures ~= nil
      and not (c.stale and c.stale.aux) then return end
  local okG, grass = pcall(buildGrassMesh, map)
  local okF, flowers = pcall(buildFlowerMesh, map)
  local okX, figures = pcall(buildFigureMeshes, map)
  if (gen[job.id] or 0) ~= job.gen then
    if okG and grass and grass.release then pcall(grass.release, grass) end
    if okF and flowers and flowers.release then pcall(flowers.release, flowers) end
    if okX then releaseFigures(figures) end
    return false
  end
  swapSlot(c, "grass", (okG and grass) or false)
  swapSlot(c, "flowers", (okF and flowers) or false)
  releaseFigures(c.figures)
  c.figures = (okX and figures) or false
  if c.stale then c.stale.aux = nil end
  return true
end

local function releasePair(mesh, water)
  if mesh and mesh.release then pcall(mesh.release, mesh) end
  if water and water.release then pcall(water.release, water) end
end

-- A build only lands if the map's generation still matches the one the
-- job was queued under -- invalidate/evict bump it to cancel in-flight work.
--
-- v0.3.32 IMPORTANT ORDER: terrain is restored/built BEFORE grass/figures.
-- That makes a disk hit or freshly completed sector drawable immediately;
-- decorative meshes can finish during later cooperative slices instead of
-- delaying the entire world behind them.
local function runJob(job)
  local map = job.map

  -- Cache-only jobs never allocate GPU meshes.  They are the aggressive PC
  -- warmer used by Kanto: build a BODY vertex stream once, serialize it, throw
  -- the native buffer away.  The next real request can upload it without
  -- rerunning Structures/runGeometry.
  if job.cacheOnly then
    if DiskCache.probe(map, job.slot, job.masks) then
      warmStats.hits = warmStats.hits + 1
      return
    end
    local sink = newSink()
    local waterSink = newSink()
    runGeometry(map, job.slot == "body", job.masks, sink, waterSink)
    if (gen[job.id] or 0) ~= job.gen then return end
    local stored = DiskCache.store(map, job.slot, job.masks, sink, waterSink)
    if stored then
      warmStats.completed = warmStats.completed + 1
    else
      warmStats.errors = warmStats.errors + 1
    end
    return
  end

  local c = entry(job.id)
  c.map = map

  -- Persistent hit: upload the already-derived raw vertices and make terrain
  -- visible BEFORE auxiliary grass/figure work.  Cache.load itself is chunked
  -- through BuildBudget, so large routes remain cooperative.
  local hit, cachedMesh, cachedWater = DiskCache.load(map, job.slot, job.masks)
  if hit then
    if (gen[job.id] or 0) ~= job.gen then
      releasePair(cachedMesh, cachedWater)
      return
    end
    swapSlot(c, job.slot, cachedMesh or false)
    swapSlot(c, waterSlot(job.slot), cachedWater or false)
    clearStale(c, job.slot)
    buildAux(job, map, c)
    return
  end

  local sink = newSink()
  local waterSink = newSink()
  runGeometry(map, job.slot == "body", job.masks, sink, waterSink)
  local mesh = sink.finish()
  local water = waterSink.finish()
  if (gen[job.id] or 0) ~= job.gen then
    releasePair(mesh, water)
    return
  end

  -- LAND FIRST.  From this point the sector can draw even if cache writing or
  -- decorative meshes spend more cooperative slices.
  swapSlot(c, job.slot, mesh or false)
  swapSlot(c, waterSlot(job.slot), water or false)
  clearStale(c, job.slot)

  buildAux(job, map, c)

  -- Meta is written last by VoxelDiskCache. Failure here never invalidates the
  -- live mesh; it only means this sector will rebuild next process launch.
  if DiskCache.enabled() then
    pcall(DiskCache.store, map, job.slot, job.masks, sink, waterSink)
  end
end

-- Queue a build unless the slot is already cached or queued. Returns the
-- cached mesh when there is one (false-cached misses return nil).
-- `urgent` marks the current map's meshes.  A real render request preempts a
-- cache-only warmer of the same slot instead of waiting for background work.
function ChunkMesher.request(map, bodyOnly, masks, urgent)
  local slot = bodyOnly and "body" or "full"
  local c = cache[map.id]
  if c then c.map = map end
  local stale = c and c.stale and (c.stale[slot] or c.stale.aux)
  if c and c[slot] ~= nil and not stale then return c[slot] or nil end

  local wk = warmKey(map.id, slot)
  local warm = jobIndex[wk]
  if warm then
    warm.cancelled = true
    warmStats.cancelled = warmStats.cancelled + 1
    removeJob(warm)
  end

  local key = jobKey(map.id, slot)
  local job = jobIndex[key]
  if not job then
    job = { id = map.id, map = map, slot = slot, masks = masks,
            urgent = urgent or false, gen = gen[map.id] or 0, key = key }
    jobIndex[key] = job
    jobs[#jobs + 1] = job
  elseif urgent then
    job.urgent = true
  end
  return (c and c[slot]) or nil
end

-- Queue a persistent BODY/FULL derivation without creating a GPU Mesh.  Kanto
-- uses BODY warmers for every outdoor sector, while ordinary visible requests
-- opportunistically persist FULL variants with their exact seam masks.
function ChunkMesher.warmDisk(map, bodyOnly, masks, region)
  if not (map and map.id and DiskCache.enabled()) then return false, "disabled" end
  local slot = bodyOnly and "body" or "full"
  if DiskCache.probe(map, slot, masks) then
    warmStats.hits = warmStats.hits + 1
    return true, "hit"
  end
  if jobIndex[jobKey(map.id, slot)] then return true, "live" end
  local key = warmKey(map.id, slot)
  if jobIndex[key] then return true, "queued" end
  local job = {
    id = map.id, map = map, slot = slot, masks = masks, urgent = false,
    cacheOnly = true, cacheRegion = region or "world", gen = gen[map.id] or 0,
    key = key,
  }
  jobIndex[key] = job
  jobs[#jobs + 1] = job
  warmStats.queued = warmStats.queued + 1
  return true, "queued"
end

function ChunkMesher.cancelWarmRegion(region)
  local n = 0
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if job.cacheOnly and (region == nil or job.cacheRegion == region) then
      job.cancelled = true
      jobIndex[job.key] = nil
      table.remove(jobs, i)
      n = n + 1
    end
  end
  warmStats.cancelled = warmStats.cancelled + n
  return n
end

function ChunkMesher.warmPending(region)
  local n = 0
  for _, job in ipairs(jobs) do
    if job.cacheOnly and (region == nil or job.cacheRegion == region) then n = n + 1 end
  end
  return n
end

function ChunkMesher.pending()
  return #jobs
end

-- Most recent terrain build failure for a map, if any.
function ChunkMesher.lastError(mapId)
  return mapId and lastErrors[mapId] or nil
end

local URGENT_SLICE = 0.012
local IDLE_SLICE = 0.005
local COVERED_SLICE = 0.030

local function buildSlices()
  if Quality and type(Quality.buildSlices) == "function" then
    local ok, urgent, idle, covered = pcall(Quality.buildSlices)
    if ok and tonumber(urgent) and tonumber(idle) and tonumber(covered) then
      return tonumber(urgent), tonumber(idle), tonumber(covered)
    end
  end
  return URGENT_SLICE, IDLE_SLICE, COVERED_SLICE
end

-- Cache warmers are deliberately lower priority than ANY real renderer job.
-- When the queue contains only warmers, desktop gets a much wider slice so the
-- user's CPU can crunch Kanto sectors quickly while an already-cached scene is
-- being played. Phones stay conservative.
local function cacheWarmSlice(covered, interactive)
  local osName = EngineCompat.osName()
  local mobile = osName == "Android" or osName == "iOS"
  local mode = Quality and Quality.buildMode and Quality.buildMode() or "balanced"

  -- v0.3.43: persistent Kanto cooking must never own a gameplay frame.  The
  -- old desktop BALANCED/FAST slices were 22-35 ms while the world was visible,
  -- which by themselves exceeded a 60-Hz frame budget and presented as periodic
  -- Kanto stutter until every sector happened to be cooked.  During actual
  -- player motion, background warmers get only a tiny cooperative nibble; when
  -- standing still they still use spare desktop CPU, and covered/menu frames
  -- remain the place where FAST LOAD may work aggressively.
  if interactive and not covered then
    if mobile then return mode == "fast" and 0.0007 or 0.00035 end
    return mode == "fast" and 0.0015 or (mode == "smooth" and 0.0005 or 0.0010)
  end

  if mobile then
    if mode == "fast" then return covered and 0.010 or 0.0025 end
    if mode == "smooth" then return covered and 0.004 or 0.0010 end
    return covered and 0.006 or 0.0018
  end

  -- Visible gameplay: stay below a normal 16.7 ms frame even when this is the
  -- only queued work. Covered/menu frames can spend more because the player is
  -- not steering the world.
  if mode == "fast" then return covered and 0.040 or 0.010 end
  if mode == "smooth" then return covered and 0.015 or 0.003 end
  return covered and 0.028 or 0.006
end

ChunkMesher._cacheWarmSlice = cacheWarmSlice

-- v0.3.58 Kanto visible-world pacing. Once the CURRENT stitched body is
-- drawable, route-neighbour prefetch jobs do not need the same large slice as
-- a missing current map. Keep building the exact same geometry, just spread
-- that CPU work over more frames so camera/player motion never competes with a
-- 4.5-10 ms terrain coroutine slice. A cold current sector deliberately uses
-- the normal urgent path; GoldVoxelBridge only passes "kanto-visible" after
-- ChunkMesher.peek confirms the current body already exists.
local function kantoVisibleSlice(urgent)
  local mode = Quality and Quality.buildMode and Quality.buildMode() or "balanced"
  if urgent then
    if mode == "fast" then return 0.0040 end
    if mode == "smooth" then return 0.0018 end
    return 0.0028
  end
  if mode == "fast" then return 0.0020 end
  if mode == "smooth" then return 0.0008 end
  return 0.0013
end
ChunkMesher._kantoVisibleSlice = kantoVisibleSlice

local function pickJob()
  -- 1) current/urgent terrain
  for _, j in ipairs(jobs) do if not j.cacheOnly and j.urgent then return j end end
  -- 2) any real visible/prefetch terrain
  for _, j in ipairs(jobs) do if not j.cacheOnly then return j end end
  -- 3) persistent background warming
  return jobs[1]
end

function ChunkMesher.pump(covered, interactive)
  if #jobs == 0 then return end
  local pick = pickJob()
  local urgentSlice, idleSlice, coveredSlice = buildSlices()
  local slice
  if pick.cacheOnly then
    slice = cacheWarmSlice(covered, interactive == true or interactive == "kanto-visible")
  elseif interactive == "kanto-visible" and not covered then
    -- Current Kanto terrain is already drawable; this is neighbour/prefetch
    -- work. Preserve the mesh exactly but cap its contribution to this visible
    -- gameplay frame.
    slice = kantoVisibleSlice(pick.urgent == true)
  else
    -- Native worlds and cold/current Kanto terrain keep the normal slice.
    slice = covered and coveredSlice or (pick.urgent and urgentSlice or idleSlice)
  end
  local deadline = clock() + slice
  while pick do
    if not pick.co then pick.co = coroutine.create(runJob) end
    Budget.begin(pick.co, math.max(0, deadline - clock()))
    local ok, err = coroutine.resume(pick.co, pick)
    Budget.finish()
    if not ok then
      finishJob(pick, false, err)
    elseif coroutine.status(pick.co) == "dead" then
      finishJob(pick, true)
    else
      return
    end
    if clock() >= deadline or #jobs == 0 then return end
    pick = pickJob()
  end
end

-- Meshes for `map`, built SYNCHRONOUSLY on first use -- the historical
-- contract, kept for probes and any direct caller. `false` is cached for
-- a map whose mesh could not be built so a headless run does not retry
-- every frame. `masks` (the full variant's neighbour-body rects) is
-- static per map id -- a map's connections never change -- so it caches
-- like everything else.
function ChunkMesher.get(map, bodyOnly, masks)
  local slot = bodyOnly and "body" or "full"
  local c = entry(map.id)
  c.map = map
  if c.grass == nil or c.flowers == nil or (c.stale and c.stale.aux) then
    local okG, grass = pcall(buildGrassMesh, map)
    local okF, flowers = pcall(buildFlowerMesh, map)
    swapSlot(c, "grass", (okG and grass) or false)
    swapSlot(c, "flowers", (okF and flowers) or false)
    if c.stale then c.stale.aux = nil end
  end
  if c[slot] == nil or (c.stale and c.stale[slot]) then
    local ok, mesh, water = pcall(ChunkMesher.build, map, bodyOnly, masks,
                                  true)
    if not ok then
      lastErrors[map.id] = tostring(mesh)
      print("[warn] voxel mesh build failed for " .. tostring(map.id)
            .. ": " .. tostring(mesh))
    else
      lastErrors[map.id] = nil
    end
    swapSlot(c, slot, (ok and mesh) or false)
    swapSlot(c, waterSlot(slot), (ok and water) or false)
    if c.stale then
      c.stale[slot] = nil
      if not (c.stale.full or c.stale.body or c.stale.aux) then
        c.stale = nil
      end
    end
    local key = jobKey(map.id, slot)
    local job = jobIndex[key]
    if job then finishJob(job, ok, (not ok) and mesh or nil) end
  end
  return c[slot] or nil
end

-- The cached mesh, or nil -- never builds. The async path's read side.
function ChunkMesher.peek(map, bodyOnly)
  local c = cache[map.id]
  local mesh = c and c[bodyOnly and "body" or "full"]
  return mesh or nil
end

-- A slot's terrain mesh AND the water surface lifted out of it, as one
-- answer. Never builds, like peek.
--
-- Both or neither, always from the SAME slot: the water was cut out of that
-- exact geometry, so pairing a full mesh with a body build's water would
-- draw the border ring's ponds twice and leave the body's as holes. Callers
-- that fall back from one variant to the other fall back through this, so
-- there is nowhere for the two to be chosen separately.
function ChunkMesher.pair(map, bodyOnly)
  local c = cache[map.id]
  if not c then return nil, nil end
  local slot = bodyOnly and "body" or "full"
  return c[slot] or nil, c[waterSlot(slot)] or nil
end

function ChunkMesher.grass(map)
  local c = cache[map.id]
  return c and c.grass or nil
end

function ChunkMesher.flowers(map)
  local c = cache[map.id]
  return c and c.flowers or nil
end

-- Authored figures as `{ mesh, wx, wz, y, w }` records -- each placed by
-- its own leaning matrix at draw time, so they cannot share one mesh.
function ChunkMesher.figures(map)
  local c = cache[map.id]
  local list = c and c.figures
  return (type(list) == "table") and list or nil
end

-- Rebuild a map's meshes IN PLACE: the stale meshes keep drawing while
-- replacements cook, and each slot swaps as its build lands. This is
-- the block-edit path (a cut tree, a door stamp) -- invalidate() drops
-- the mesh outright, and until the async rebuild landed the scene fell
-- to the flat 2D path, a whole-world blink for a one-block edit.
function ChunkMesher.refresh(mapId)
  if not mapId then return ChunkMesher.invalidate() end
  local c = cache[mapId]
  -- nothing drawable cached: the plain drop costs nothing visible
  if not (c and (c.full or c.body)) then
    return ChunkMesher.invalidate(mapId)
  end
  Structures.invalidate(mapId)
  if c and c.map then DiskCache.invalidateMap(c.map) end
  gen[mapId] = (gen[mapId] or 0) + 1
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if job.id == mapId then
      job.cancelled = true
      jobIndex[job.key or jobKey(job.id, job.slot)] = nil
      table.remove(jobs, i)
    end
  end
  -- false-cached slots count as stale too: a retry after a failed build
  -- is exactly a rebuild
  c.stale = { aux = true,
              full = (c.full ~= nil) or nil,
              body = (c.body ~= nil) or nil }
end

-- Evict everything outside `live` (a set of map ids): far maps' meshes
-- are released -- GPU buffer and LOVE's CPU copy both -- and their
-- Structures analysis dropped. The live set is the current map plus its
-- rendered neighbours, so memory stays bounded by what is on or near the
-- screen instead of growing with every area ever visited.
--
-- The PREVIOUS live set is retained too: warping into a building
-- collapses the set to one small interior, and evicting the town at the
-- door means rebuilding the whole neighbourhood on the way out -- a
-- flat-world flash after every house. One set of history makes the
-- round trip free while staying bounded at two neighbourhoods.
local prevLive = {}
local prevLiveSpare = {}

local function clearLiveSet(t)
  for id in pairs(t or {}) do t[id] = nil end
  return t
end

function ChunkMesher.setLive(live, forgetPrevious)
  -- Normal streaming keeps one previous neighbourhood warm for cheap
  -- house/door round trips. OPEN WORLD -> OFF is different: the user is
  -- explicitly asking to shed the expensive far-world residency now, so the
  -- caller may discard that one-generation grace set before eviction.
  if forgetPrevious then clearLiveSet(prevLive) end
  for id, c in pairs(cache) do
    if not live[id] and not prevLive[id] then
      releaseEntry(c)
      cache[id] = nil
      gen[id] = (gen[id] or 0) + 1
      Structures.invalidate(id)
    end
  end
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    -- Persistent warmers are intentionally independent of GPU residency. They
    -- may finish a far Kanto sector to disk while the live set stays small.
    -- TwinRegionWorld explicitly cancels Kanto warmers on RETURN TO JOHTO.
    if not job.cacheOnly and not live[job.id] and not prevLive[job.id] then
      job.cancelled = true
      jobIndex[job.key or jobKey(job.id, job.slot)] = nil
      table.remove(jobs, i)
    end
  end

  -- v0.3.59 owns the previous-live snapshot instead of retaining the caller's
  -- table by reference. Kanto now reuses one scratch dictionary every frame;
  -- retaining it here would let the next wipe silently rewrite residency
  -- history. Two internal sets swap roles so even route changes allocate
  -- nothing after initialization.
  clearLiveSet(prevLiveSpare)
  for id, keep in pairs(live or {}) do
    if keep then prevLiveSpare[id] = true end
  end
  prevLive, prevLiveSpare = prevLiveSpare, prevLive
end

-- Drop one map's mesh (Cut swapped a block) or all of them (hot reload).
-- Structures' analysis is derived from the same block layer, so it drops
-- in the same breath; in-flight builds of the map are cancelled through
-- the generation counter.
function ChunkMesher.invalidate(mapId)
  Structures.invalidate(mapId)
  if mapId then
    lastErrors[mapId] = nil
    local c = cache[mapId]
    if c and c.map then DiskCache.invalidateMap(c.map) end
    if c then releaseEntry(c) end
    cache[mapId] = nil
    gen[mapId] = (gen[mapId] or 0) + 1
  else
    for _, c in pairs(cache) do
      if c.map then DiskCache.invalidateMap(c.map) end
      releaseEntry(c)
    end
    DiskCache.invalidateSignatures()
    cache = {}
    lastErrors = {}
    for id in pairs(gen) do gen[id] = gen[id] + 1 end
  end
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if mapId == nil or job.id == mapId then
      job.cancelled = true
      jobIndex[job.key or jobKey(job.id, job.slot)] = nil
      table.remove(jobs, i)
    end
  end
end

function ChunkMesher.diskCacheEnabled()
  -- The persistent format is the raw FFI float sink. A runtime without FFI may
  -- still READ an existing cache through DiskCache, but it cannot safely emit
  -- new entries, so do not schedule aggressive warmers there.
  return DiskCache.enabled() and ffi ~= nil
end

function ChunkMesher.diskCacheStatus()
  local out = DiskCache.status()
  out.warmQueued = warmStats.queued
  out.warmCompleted = warmStats.completed
  out.warmHits = warmStats.hits
  out.warmCancelled = warmStats.cancelled
  out.warmErrors = warmStats.errors
  out.warmPending = ChunkMesher.warmPending()
  out.johtoWarmPending = ChunkMesher.warmPending("johto")
  out.kantoWarmPending = ChunkMesher.warmPending("kanto")
  return out
end

function ChunkMesher.clearDiskCache()
  return DiskCache.clear()
end

Assets.register(function() ChunkMesher.invalidate() end)

return ChunkMesher
