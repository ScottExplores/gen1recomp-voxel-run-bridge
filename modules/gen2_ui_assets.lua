-- Lazily decodes the small set of authentic Pokemon Gold UI resources used by
-- Scott's Tweaks.  The user's ROM remains a private optional import: nothing
-- decoded here is written to disk or included in the mod archive.

local Assets = {
  importPath = "baseroms/pokemon_gold.gbc",
  md5 = "a6924ce1f9ad2228e1c6580779b23878",
  sha1 = "d8b8a3600a465308c9953dfa04f0081c05bdcb94",
  size = 2097152,
}

Assets.constants = {
  importPath = Assets.importPath,
  md5 = Assets.md5,
  sha1 = Assets.sha1,
  size = Assets.size,
  version = "gold",
  generation = 2,
}

-- Upper-case aliases make the immutable import contract easy to inspect in a
-- focused test without changing the friendlier public field names above.
Assets.IMPORT_PATH = Assets.importPath
Assets.MD5 = Assets.md5
Assets.SHA1 = Assets.sha1
Assets.ROM_SIZE = Assets.size

local IMAGE_KEYS = { "packMenu", "pack", "gear", "sprites", "chris" }
local DAYTIMES = { "MORN", "DAY", "NITE", "DARK" }
local SPRITEDATA_LENGTH = 6
local WALKING_SPRITE = 1
local OW_PALETTE_COUNT = 8

local Controller = {}
Controller.__index = Controller

local function traceback(err)
  if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
  return tostring(err)
end

local function statusMessage(reason)
  local messages = {
    optional_import_missing =
      "Pokemon Gold has not been imported for Scott's Tweaks.",
    optional_import_invalid_size =
      "The Pokemon Gold import has the wrong file size.",
    optional_import_invalid_md5 =
      "The Pokemon Gold import is not the supported clean ROM.",
    optional_import_unreadable =
      "The Pokemon Gold import could not be read.",
    hash_unavailable =
      "This engine build cannot validate the Pokemon Gold import.",
    gen2_import_api_unavailable =
      "This Gen1Recomp build does not provide the Gold UI import API.",
    gen2_ui_decode_failed =
      "The Pokemon Gold UI resources could not be decoded.",
    released = "The decoded Pokemon Gold UI resources were released.",
  }
  return messages[reason]
end

local function setState(self, state, reason, detail)
  self._state = state
  self._reason = reason
  self._detail = detail
end

local function fail(self, state, reason, detail)
  self._payload = nil
  self._cacheKey = nil
  setState(self, state, reason, detail)
  return nil, reason
end

local function hexDigest(raw)
  return (raw:gsub(".", function(byte)
    return ("%02x"):format(string.byte(byte))
  end))
end

local function calculateMd5(self, raw)
  if type(self._dependencies.md5) == "function" then
    local digest = self._dependencies.md5(raw)
    if type(digest) == "string" then return digest:lower() end
    return nil, "hash_unavailable"
  end

  local data = love and love.data
  if not (data and type(data.hash) == "function") then
    return nil, "hash_unavailable"
  end
  local ok, digest = pcall(data.hash, "md5", raw)
  if not ok or digest == nil then return nil, "hash_unavailable" end
  if type(digest) == "userdata" and digest.getString then
    local stringOk, value = pcall(digest.getString, digest)
    if not stringOk then return nil, "hash_unavailable" end
    digest = value
  end
  if type(digest) ~= "string" then return nil, "hash_unavailable" end

  if data.encode then
    local encodeOk, encoded = pcall(data.encode, "string", "hex", digest)
    if encodeOk and type(encoded) == "string" then return encoded:lower() end
  end
  return hexDigest(digest):lower()
end

local function engineModules(self)
  local dependencies = self._dependencies
  if dependencies.RomManifest and dependencies.RomExtractorGen2
      and dependencies.ImageWriter then
    return dependencies.RomManifest, dependencies.RomExtractorGen2,
      dependencies.ImageWriter
  end

  local requireFn = dependencies.requireFn or require
  local okManifest, RomManifest = pcall(requireFn, "src.import.RomManifest")
  local okExtractor, RomExtractorGen2 =
    pcall(requireFn, "src.import.RomExtractorGen2")
  local okWriter, ImageWriter = pcall(requireFn, "src.import.ImageWriter")
  if not okManifest or not okExtractor or not okWriter
      or type(RomManifest) ~= "table"
      or type(RomExtractorGen2) ~= "table"
      or type(ImageWriter) ~= "table"
      or type(RomManifest.decode) ~= "function"
      or type(RomExtractorGen2.new) ~= "function"
      or type(ImageWriter.decode2bpp) ~= "function" then
    return nil
  end
  return RomManifest, RomExtractorGen2, ImageWriter
end

local function safeRelease(resource)
  if resource and type(resource.release) == "function" then
    pcall(resource.release, resource)
  end
end

local function decodePayload(self, raw, RomManifest, RomExtractorGen2,
    ImageWriter)
  local owned = {}

  local function decode2bpp(bytes, width, height, transparent)
    local imageData = ImageWriter.decode2bpp(bytes, width, height, transparent)
    if imageData == nil or type(imageData.release) ~= "function" then
      error("ImageWriter.decode2bpp did not return releaseable ImageData")
    end
    owned[#owned + 1] = imageData
    return imageData
  end

  local function work()
    local manifest = RomManifest.decode("gold")
    local extractor = RomExtractorGen2.new(raw, manifest)
    if type(extractor) ~= "table" or not extractor.rom
        or type(extractor.symbol) ~= "function"
        or type(extractor.colors) ~= "function"
        or type(extractor.pokegearGfx) ~= "function"
        or type(extractor.extractLandmarks) ~= "function" then
      error("RomExtractorGen2 does not expose the expected 0.1.96 API")
    end

    -- Pokegear_LoadGFX copies ChrisSpriteGFX into the RED_WALK animation
    -- slots.  Decode that exact OverworldSprites row rather than substituting
    -- a hand-made marker.  The row's length is the standing half; a walking
    -- sheet stores the equally-sized walking half immediately after it.
    local constants = manifest.constants or {}
    local chrisIndex
    for index, id in ipairs(constants.spriteOrder or {}) do
      if id == "SPRITE_CHRIS" then chrisIndex = index break end
    end
    if not chrisIndex
        or chrisIndex > (constants.numOverworldSprites or math.huge) then
      error("Pokemon Gold manifest does not expose SPRITE_CHRIS")
    end
    local spriteTable = extractor:symbol("OverworldSprites")
    local rowAddress = spriteTable.address
      + (chrisIndex - 1) * SPRITEDATA_LENGTH
    local spritePointer = extractor.rom:word(spriteTable.bank, rowAddress)
    local spriteSize = extractor.rom:byte(spriteTable.bank, rowAddress + 2)
    local spriteBank = extractor.rom:byte(spriteTable.bank, rowAddress + 3)
    local spriteType = extractor.rom:byte(spriteTable.bank, rowAddress + 4)
    local paletteId = extractor.rom:byte(spriteTable.bank, rowAddress + 5)
    local spriteBytes = spriteSize
    if spriteType == WALKING_SPRITE then spriteBytes = spriteBytes * 2 end
    if spriteType ~= WALKING_SPRITE or paletteId ~= 0
        or spriteBytes ~= 16 * 96 / 4 then
      error("SPRITE_CHRIS is not the expected 16x96 walking sheet")
    end

    local imageData = {}
    imageData.chris = decode2bpp(
      extractor.rom:bytes(spriteBank, spritePointer, spriteBytes),
      16, 96, true)

    -- _CGB_PokegearPals changes BG palettes only.  RED_WALK therefore keeps
    -- PAL_OW_RED from MapObjectPals, including its distinct MORN, DAY, NITE
    -- and DARK rows.  Keep only that exact OBJ slot: the Gear marker cannot
    -- accidentally borrow palette art from another sprite.
    local objectPals = extractor:symbol("MapObjectPals")
    local objects = {}
    for day = 0, #DAYTIMES - 1 do
      local set = {}
      set[paletteId + 1] = extractor:colors(objectPals.bank,
        objectPals.address
          + (day * OW_PALETTE_COUNT + paletteId) * 8, 4)
      objects[DAYTIMES[day + 1]] = set
    end
    local sprites = {
      SPRITE_CHRIS = {
        id = "SPRITE_CHRIS",
        source = ("ROM:OverworldSprites[%d]"):format(chrisIndex - 1),
        image = "chris",
        frames = 6,
        frameWidth = 16,
        frameHeight = 16,
        walker = true,
        spriteType = "WALKING_SPRITE",
        palette = "PAL_OW_RED",
        paletteId = paletteId,
      },
    }
    local palettes = {
      generation = 2,
      source = "ROM:MapObjectPals/PAL_OW_RED",
      daytimes = { DAYTIMES[1], DAYTIMES[2], DAYTIMES[3], DAYTIMES[4] },
      objects = objects,
    }

    local pack = {
      -- These are logical in-memory keys, not filesystem paths.  They also let
      -- a caller seed a PackGfx instance's per-instance image cache directly.
      menu = "packMenu",
      pack = "pack",
      menuImageDataKey = "packMenu",
      packImageDataKey = "pack",
      menuTiles = 0x60,
      menuTilesWide = 16,
      backgroundTile = 0x24,
      headerFirstTile = 0x28,
      packFirstTile = 0x50,
      packTilesWide = 5,
      packTilesHigh = 3,
      pocketPicture = {
        ITEM = 15, BALL = 45, KEY_ITEM = 0, TM_HM = 30,
      },
      pocketOrder = { "ITEM", "BALL", "KEY_ITEM", "TM_HM" },
      paletteZones = {
        { 0, 0, 10, 1, 2 },
        { 10, 0, 10, 1, 3 },
        { 7, 2, 1, 9, 4 },
        { 0, 7, 5, 3, 5 },
        { 0, 3, 5, 3, 6 },
      },
    }

    local packMenu = extractor:symbol("PackMenuGFX")
    imageData.packMenu = decode2bpp(
      extractor.rom:bytes(packMenu.bank, packMenu.address, 0x60 * 16),
      128, 48, false)

    local packPicture = extractor:symbol("PackGFX")
    imageData.pack = decode2bpp(
      extractor.rom:bytes(packPicture.bank, packPicture.address, 60 * 16),
      40, 96, false)

    local pocketMap = extractor:symbol("DrawPocketName.tilemap")
    local pocketRaw = extractor.rom:bytes(pocketMap.bank, pocketMap.address, 60)
    pack.pocketName = {}
    for block = 0, 3 do
      local tiles = {}
      for index = 1, 15 do
        tiles[index] = pocketRaw[block * 15 + index]
      end
      pack.pocketName[block + 1] = tiles
    end

    local packPals = extractor:symbol("_CGB_PackPals.PackPals")
    pack.palettes = {}
    for index = 0, 5 do
      pack.palettes[index + 1] =
        extractor:colors(packPals.bank, packPals.address + index * 8, 4)
    end

    -- pokegearGfx contains exactly the cart's Pokegear sheets and metadata.
    -- Replace its sole output seam so its normal ImageWriter.save path can
    -- never run; only ImageData objects are captured here.
    local previousWrite2bpp = rawget(extractor, "write2bpp")
    extractor.write2bpp = function(_, bytes, width, height, relative, transparent)
      local decoded = decode2bpp(bytes, width, height, transparent)
      if relative == "pokegear/gear.png" then
        imageData.gear = decoded
      elseif relative == "pokegear/sprites.png" then
        imageData.sprites = decoded
      else
        error("unexpected Pokegear output: " .. tostring(relative))
      end
    end
    local gearOk, pokegear = xpcall(function()
      return extractor:pokegearGfx()
    end, traceback)
    extractor.write2bpp = previousWrite2bpp
    if not gearOk then error(pokegear) end
    if not imageData.gear or not imageData.sprites then
      error("Pokegear extraction did not produce both image sheets")
    end
    pokegear.tiles = "gear"
    pokegear.sprites = "sprites"
    pokegear.tilesImageDataKey = "gear"
    pokegear.spritesImageDataKey = "sprites"

    -- extractLandmarks normally serializes its answer after decoding it.  Its
    -- instance-local write override makes this call memory-only as well.
    local previousWrite = rawget(extractor, "write")
    extractor.write = function() end
    local landmarksOk, landmarks = xpcall(function()
      return extractor:extractLandmarks()
    end, traceback)
    extractor.write = previousWrite
    if not landmarksOk then error(landmarks) end

    local payload = {
      menuGfx = { pack = pack, pokegear = pokegear },
      imageData = imageData,
      landmarks = landmarks,
      sprites = sprites,
      palettes = palettes,
      source = {
        version = "gold",
        generation = 2,
        md5 = Assets.md5,
        size = Assets.size,
        importPath = Assets.importPath,
      },
      released = false,
    }

    function payload:release()
      if self.released then return false end
      self.released = true
      for _, key in ipairs(IMAGE_KEYS) do
        safeRelease(self.imageData[key])
        self.imageData[key] = nil
      end
      if self._owner and self._owner._payload == self then
        self._owner._payload = nil
        self._owner._cacheKey = nil
        setState(self._owner, "released", "released")
      end
      self._owner = nil
      return true
    end

    payload._owner = self
    return payload
  end

  local ok, payload = xpcall(work, traceback)
  if not ok then
    for _, resource in ipairs(owned) do safeRelease(resource) end
    return nil, payload
  end
  return payload
end

function Assets.new(mod, dependencies)
  return setmetatable({
    _mod = mod,
    _dependencies = dependencies or {},
    _state = "idle",
    _payload = nil,
    _cacheKey = nil,
    _reason = nil,
    _detail = nil,
  }, Controller)
end

function Controller:status()
  return {
    state = self._state,
    ready = self._state == "ready" and self._payload ~= nil
      and not self._payload.released,
    attempted = self._state ~= "idle",
    cached = self._payload ~= nil and not self._payload.released,
    reason = self._reason,
    message = statusMessage(self._reason),
    detail = self._detail,
    importPath = Assets.importPath,
    md5 = Assets.md5,
    sha1 = Assets.sha1,
    size = Assets.size,
    version = "gold",
    generation = 2,
  }
end

function Controller:load()
  if self._payload and not self._payload.released
      and self._cacheKey == Assets.md5 then
    setState(self, "ready")
    return self._payload
  end

  if not self._mod or type(self._mod.read) ~= "function" then
    return fail(self, "unavailable", "optional_import_unreadable")
  end

  -- Probe the Gen 2 import surface before looking for the optional ROM.  Older
  -- engines (notably 0.1.88) do not expose this API or an import screen, so a
  -- missing file there must be reported as an engine capability issue rather
  -- than an actionable "import Gold" prompt.
  local RomManifest, RomExtractorGen2, ImageWriter = engineModules(self)
  if not RomManifest then
    return fail(self, "unavailable", "gen2_import_api_unavailable")
  end

  setState(self, "loading")
  local readOk, raw, readError =
    pcall(self._mod.read, self._mod, Assets.importPath)
  if not readOk then
    return fail(self, "unavailable", "optional_import_unreadable", tostring(raw))
  end
  if raw == nil then
    return fail(self, "missing", "optional_import_missing", readError)
  end
  if type(raw) ~= "string" then
    return fail(self, "invalid", "optional_import_unreadable")
  end
  if #raw ~= Assets.size then
    return fail(self, "invalid", "optional_import_invalid_size")
  end

  local digest, hashError = calculateMd5(self, raw)
  if not digest then return fail(self, "unavailable", hashError) end
  if digest ~= Assets.md5 then
    return fail(self, "invalid", "optional_import_invalid_md5")
  end

  local payload, decodeError = decodePayload(
    self, raw, RomManifest, RomExtractorGen2, ImageWriter)
  -- `raw` is deliberately not retained by the controller or the payload.
  raw = nil
  if not payload then
    return fail(self, "error", "gen2_ui_decode_failed", decodeError)
  end

  self._payload = payload
  self._cacheKey = digest
  setState(self, "ready")
  return payload
end

function Controller:release()
  if not self._payload then return false end
  return self._payload:release()
end

return Assets
