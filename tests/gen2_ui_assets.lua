-- Focused contract tests for the private, memory-only Pokemon Gold UI import.
-- Run with LuaJIT 2.1 or Lua 5.1:
--   luajit tests/gen2_ui_assets.lua <tweaks-root> <engine-0.1.96> [gold-rom]

local argv = rawget(_G, "arg") or {}
local sourceRoot = (argv[1] or "."):gsub("\\", "/"):gsub("/$", "")
local temp = (os.getenv("TEMP") or os.getenv("TMP") or "."):gsub("\\", "/")
local engineRoot = (argv[2] or (temp .. "/codex_gen1recomp_source_v0.1.96"))
  :gsub("\\", "/"):gsub("/$", "")
local goldRomPath = argv[3] or os.getenv("SCOTTS_TWEAKS_GOLD_ROM")

local checks = 0
local function check(value, message)
  checks = checks + 1
  if not value then error(("check %d failed: %s"):format(checks, message), 0) end
end

local function eq(actual, expected, message)
  check(actual == expected, ("%s (expected %s, got %s)")
    :format(message, tostring(expected), tostring(actual)))
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function hexBytes(hex)
  return (hex:gsub("..", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

local modulePath = sourceRoot .. "/modules/gen2_ui_assets.lua"
local Assets = assert(loadfile(modulePath), "missing " .. modulePath)()

eq(Assets.importPath, "baseroms/pokemon_gold.gbc", "private import path")
eq(Assets.md5, "a6924ce1f9ad2228e1c6580779b23878", "clean Gold MD5")
eq(Assets.sha1, "d8b8a3600a465308c9953dfa04f0081c05bdcb94",
  "clean Gold SHA1")
eq(Assets.size, 2097152, "clean Gold size")

-- Fail closed if the exact 0.1.96 extraction seams change.  These are the
-- engine functions the behavioral harness below intentionally reuses.
local manifestSource = assert(read(engineRoot .. "/src/import/RomManifest.lua"),
  "Gen1Recomp 0.1.96 RomManifest.lua missing")
local extractorSource = assert(read(engineRoot .. "/src/import/RomExtractorGen2.lua"),
  "Gen1Recomp 0.1.96 RomExtractorGen2.lua missing")
local writerSource = assert(read(engineRoot .. "/src/import/ImageWriter.lua"),
  "Gen1Recomp 0.1.96 ImageWriter.lua missing")
check(manifestSource:find("function RomManifest.decode(version)", 1, true),
  "0.1.96 exposes RomManifest.decode")
check(extractorSource:find(
  "function RomExtractorGen2.new(romData, manifest, progress)", 1, true),
  "0.1.96 exposes RomExtractorGen2.new")
check(extractorSource:find("function RomExtractorGen2:pokegearGfx()", 1, true),
  "0.1.96 exposes targeted Pokegear extraction")
  check(extractorSource:find("function RomExtractorGen2:extractLandmarks()", 1, true),
    "0.1.96 exposes landmark extraction")
check(extractorSource:find("function RomExtractorGen2:extractSprites()", 1, true),
  "0.1.96 exposes the OverworldSprites row contract")
check(extractorSource:find("local objSymbol = self:symbol(\"MapObjectPals\")", 1, true),
  "0.1.96 exposes the MapObjectPals OBJ-palette contract")
check(writerSource:find(
  "function ImageWriter.decode2bpp(raw, width, height, transparent)", 1, true),
  "0.1.96 exposes in-memory 2bpp decoding")

local oldLove = rawget(_G, "love")
local expectedDigest = hexBytes(Assets.md5)
love = {
  data = {
    hash = function(kind, raw)
      eq(kind, "md5", "loader validates with MD5")
      check(type(raw) == "string", "hash receives ROM bytes")
      return expectedDigest
    end,
    encode = function(container, format, raw)
      eq(container, "string", "hash encoding container")
      eq(format, "hex", "hash encoding format")
      return (raw:gsub(".", function(byte)
        return ("%02x"):format(string.byte(byte))
      end))
    end,
  },
}

local reads = 0
local validRom = string.rep("G", Assets.size)
local function modReturning(value, readError)
  return {
    read = function(_, path)
      reads = reads + 1
      eq(path, Assets.importPath, "loader uses scoped optional import")
      return value, readError
    end,
  }
end

local capabilityOnly = {
  RomManifest = { decode = function() end },
  RomExtractorGen2 = { new = function() end },
  ImageWriter = { decode2bpp = function() end },
}

-- Engines before 0.1.96 have neither the Gen 2 import API nor an import UI.
-- Capability probing must happen before file I/O so the menu says NEEDS
-- 0.1.96 instead of instructing the player to perform an impossible import.
reads = 0
local unsupported = Assets.new(modReturning(nil), {
  requireFn = function() error("module not found") end,
})
local unsupportedPayload, unsupportedReason = unsupported:load()
eq(unsupportedPayload, nil, "unsupported engine has no payload")
eq(unsupportedReason, "gen2_import_api_unavailable",
  "unsupported engine reason")
eq(reads, 0, "unsupported engine does not probe the ROM path")

-- Construction is lazy, and a missing optional import is a normal fail-open
-- state rather than a thrown error.
reads = 0
local missing = Assets.new(modReturning(nil, "not found"), capabilityOnly)
eq(reads, 0, "constructor performs no I/O")
eq(missing:status().state, "idle", "new controller is idle")
local missingPayload, missingReason = missing:load()
eq(missingPayload, nil, "missing import has no payload")
eq(missingReason, "optional_import_missing", "missing import reason")
eq(missing:status().state, "missing", "missing import status")
eq(missing:status().ready, false, "missing import is not ready")

reads = 0
local invalidSize = Assets.new(modReturning("too short"), capabilityOnly)
local invalidPayload, invalidReason = invalidSize:load()
eq(invalidPayload, nil, "wrong-size import has no payload")
eq(invalidReason, "optional_import_invalid_size", "wrong-size reason")
eq(invalidSize:status().state, "invalid", "wrong-size state")

reads = 0
local wrongHash = Assets.new(modReturning(validRom), {
  RomManifest = capabilityOnly.RomManifest,
  RomExtractorGen2 = capabilityOnly.RomExtractorGen2,
  ImageWriter = capabilityOnly.ImageWriter,
  md5 = function() return string.rep("0", 32) end,
})
local wrongPayload, wrongReason = wrongHash:load()
eq(wrongPayload, nil, "wrong-hash import has no payload")
eq(wrongReason, "optional_import_invalid_md5", "wrong-hash reason")
eq(wrongHash:status().state, "invalid", "wrong-hash state")

local decoded = {}
local writes = 0
local manifestCalls = 0
local extractorCalls = 0

local FakeManifest = {
  decode = function(version)
    manifestCalls = manifestCalls + 1
    eq(version, "gold", "Gold manifest requested")
    return {
      symbols = {},
      constants = {
        spriteOrder = { "SPRITE_CHRIS" },
        numOverworldSprites = 1,
      },
    }
  end,
}

local symbolSizes = {
  PackMenuGFX = 0x60 * 16,
  PackGFX = 60 * 16,
  ["DrawPocketName.tilemap"] = 60,
  OverworldSprites = 0x6000,
  MapObjectPals = 0x7000,
}

local FakeExtractor = {}
function FakeExtractor.new(raw, manifest)
  extractorCalls = extractorCalls + 1
  eq(raw, validRom, "extractor receives exact validated bytes")
  check(type(manifest) == "table", "extractor receives decoded manifest")
  local self = { _raw = raw }
  self.rom = {
    bytes = function(_, _, address, count)
      local out = {}
      for index = 1, count do out[index] = (address + index) % 256 end
      return out
    end,
    word = function(_, _, address)
      eq(address, symbolSizes.OverworldSprites,
        "SPRITE_CHRIS pointer uses first OverworldSprites row")
      return 0x5000
    end,
    byte = function(_, _, address)
      local offset = address - symbolSizes.OverworldSprites
      if offset == 2 then return 192 end -- standing half; walker doubles it
      if offset == 3 then return 2 end   -- graphics bank
      if offset == 4 then return 1 end   -- WALKING_SPRITE
      if offset == 5 then return 0 end   -- PAL_OW_RED
      error("unexpected fake ROM byte " .. tostring(address), 0)
    end,
  }
  function self:symbol(name)
    check(name == "PackMenuGFX" or name == "PackGFX"
      or name == "DrawPocketName.tilemap"
      or name == "_CGB_PackPals.PackPals"
      or name == "OverworldSprites" or name == "MapObjectPals",
      "only targeted Gold UI/player symbols requested")
    return { bank = 1, address = symbolSizes[name] or 0x4000, name = name }
  end
  function self:colors(_, address, count)
    eq(count, 4, "four colors per Pack palette")
    return { address, address + 1, address + 2, address + 3 }
  end
  function self:write()
    writes = writes + 1
  end
  function self:write2bpp()
    writes = writes + 1
  end
  function self:pokegearGfx()
    self:write2bpp({}, 128, 48, "pokegear/gear.png", false)
    self:write2bpp({}, 16, 40, "pokegear/sprites.png", true)
    return {
      tiles = "assets/generated/pokegear/gear.png",
      tilesWide = 16,
      townMapTiles = 0x30,
      sprites = "assets/generated/pokegear/sprites.png",
      spritesWide = 2,
      cards = { clock = { 1 }, phone = { 2 }, radio = { 3 } },
      maps = { johto = { 4 }, kanto = { 5 } },
      palettes = { { 1, 2, 3, 4 } },
      palMap = { 1 },
    }
  end
  function self:extractLandmarks()
    local result = {
      generation = 2,
      source = "ROM:Landmarks",
      order = { "NEW_BARK_TOWN" },
      landmarks = {
        NEW_BARK_TOWN = { id = "NEW_BARK_TOWN", x = 1, y = 2,
          name = "NEW BARK\nTOWN" },
      },
      spawns = {},
    }
    self:write("landmarks", result)
    return result
  end
  return self
end

local FakeWriter = {
  decode2bpp = function(raw, width, height, transparent)
    local image = {
      rawLength = #raw,
      width = width,
      height = height,
      transparent = transparent == true,
      released = 0,
    }
    function image:getDimensions() return self.width, self.height end
    function image:release()
      self.released = self.released + 1
      if self.released > 1 then error("ImageData released twice", 0) end
    end
    decoded[#decoded + 1] = image
    return image
  end,
}

reads = 0
local ready = Assets.new(modReturning(validRom), {
  RomManifest = FakeManifest,
  RomExtractorGen2 = FakeExtractor,
  ImageWriter = FakeWriter,
})
eq(reads, 0, "ready controller is still lazy")
local payload, loadReason = ready:load()
check(payload ~= nil, "valid Gold import decodes")
eq(loadReason, nil, "successful load has no reason")
eq(reads, 1, "valid import read once")
eq(manifestCalls, 1, "manifest decoded once")
eq(extractorCalls, 1, "extractor constructed once")
eq(writes, 0, "targeted extraction performs no writes")
eq(ready:status().state, "ready", "ready state")
eq(ready:status().ready, true, "ready flag")
eq(ready:status().cached, true, "decoded payload is cached")
eq(payload.menuGfx.pack.menu, "packMenu", "Pack menu in-memory key")
eq(payload.menuGfx.pack.pack, "pack", "Pack picture in-memory key")
eq(payload.menuGfx.pack.menuTiles, 0x60, "Pack tile count")
eq(payload.menuGfx.pack.pocketName[4][15],
  (symbolSizes["DrawPocketName.tilemap"] + 60) % 256,
  "Pack pocket-name tilemap retained")
eq(payload.menuGfx.pokegear.tiles, "gear", "Pokegear in-memory key")
eq(payload.menuGfx.pokegear.sprites, "sprites", "Pokegear sprite key")
eq(payload.landmarks.landmarks.NEW_BARK_TOWN.name, "NEW BARK\nTOWN",
  "landmarks retained")
eq(payload.imageData.packMenu.width, 128, "Pack menu width")
eq(payload.imageData.pack.height, 96, "Pack picture height")
eq(payload.imageData.gear.width, 128, "Pokegear sheet width")
eq(payload.imageData.sprites.transparent, true,
  "Pokegear sprites preserve transparency")
eq(payload.imageData.chris.width, 16, "Chris sheet width")
eq(payload.imageData.chris.height, 96, "Chris sheet height")
eq(payload.imageData.chris.transparent, true,
  "Chris OBJ color 0 preserves transparency")
eq(payload.sprites.SPRITE_CHRIS.frames, 6, "Chris has six cart frames")
eq(payload.sprites.SPRITE_CHRIS.palette, "PAL_OW_RED",
  "Chris keeps PAL_OW_RED")
eq(payload.sprites.SPRITE_CHRIS.paletteId, 0,
  "Chris keeps OBJ palette slot zero")
for day, expectedOffset in pairs({ MORN = 0, DAY = 8, NITE = 16, DARK = 24 }) do
  local colors = payload.palettes.objects[day][1]
  eq(colors[1], symbolSizes.MapObjectPals + expectedOffset * 8,
    day .. " PAL_OW_RED comes from its exact MapObjectPals row")
  eq(#colors, 4, day .. " PAL_OW_RED has four colors")
end
check(rawget(payload, "rom") == nil and rawget(payload, "raw") == nil,
  "payload does not retain ROM bytes")
check(rawget(ready, "_raw") == nil, "controller does not retain ROM bytes")

local cached = ready:load()
eq(cached, payload, "repeated load returns cached payload")
eq(reads, 1, "cached load does not reread ROM")
eq(manifestCalls, 1, "cached load does not re-decode manifest")

eq(payload:release(), true, "payload release succeeds")
eq(payload:release(), false, "payload release is idempotent")
for _, image in ipairs(decoded) do eq(image.released, 1, "ImageData released once") end
eq(ready:status().state, "released", "released status")
eq(ready:status().ready, false, "released payload is not ready")
eq(ready:status().cached, false, "released payload is not cached")

-- Decode failure releases every ImageData produced before the error and never
-- escapes through load().
local failingWriter = {
  decode2bpp = function(raw, width, height, transparent)
    if width == 40 then error("injected decode failure") end
    return FakeWriter.decode2bpp(raw, width, height, transparent)
  end,
}
local beforeFailure = #decoded
local failing = Assets.new(modReturning(validRom), {
  RomManifest = FakeManifest,
  RomExtractorGen2 = FakeExtractor,
  ImageWriter = failingWriter,
})
local failedPayload, failedReason = failing:load()
eq(failedPayload, nil, "decode failure has no payload")
eq(failedReason, "gen2_ui_decode_failed", "decode failure reason")
eq(failing:status().state, "error", "decode failure state")
eq(decoded[beforeFailure + 1].released, 1,
  "partial ImageData released after decode failure")
for index = beforeFailure + 1, #decoded do
  eq(decoded[index].released, 1,
    "every partial ImageData is released after decode failure")
end

-- Optional integration against the exact 0.1.96 modules and a caller-supplied
-- private Gold ROM.  The test never prints, copies, or writes its contents.
if goldRomPath then
  local goldRaw = assert(read(goldRomPath), "could not read Gold integration ROM")
  eq(#goldRaw, Assets.size, "integration Gold size")

  -- The exact engine extractor requires LuaJIT's `bit` module.  The focused
  -- test also runs on stock Lua 5.1, so provide the same signed 32-bit surface
  -- only when that native module is absent.  Production never sees this shim.
  if not pcall(require, "bit") then
    local TWO32, SIGN = 4294967296, 2147483648
    local function unsigned(value) return (tonumber(value) or 0) % TWO32 end
    local function signed(value)
      value = value % TWO32
      return value >= SIGN and value - TWO32 or value
    end
    local function binary(a, b, mode)
      a, b = unsigned(a), unsigned(b)
      local out, place = 0, 1
      for _ = 1, 32 do
        local aa, bb = a % 2, b % 2
        local take = mode == "and" and aa == 1 and bb == 1
          or mode == "or" and (aa == 1 or bb == 1)
          or mode == "xor" and aa ~= bb
        if take then out = out + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
      end
      return signed(out)
    end
    local function reduce(mode, first, ...)
      local out, rest = first, { ... }
      if #rest == 0 then return signed(unsigned(out)) end
      for _, value in ipairs(rest) do out = binary(out, value, mode) end
      return out
    end
    package.preload.bit = function()
      return {
        band = function(a, ...) return reduce("and", a, ...) end,
        bor = function(a, ...) return reduce("or", a, ...) end,
        bxor = function(a, ...) return reduce("xor", a, ...) end,
        bnot = function(a) return signed(TWO32 - 1 - unsigned(a)) end,
        lshift = function(a, n)
          local value = unsigned(a)
          for _ = 1, (tonumber(n) or 0) % 32 do
            value = value * 2 % TWO32
          end
          return signed(value)
        end,
        rshift = function(a, n)
          return signed(math.floor(unsigned(a) / 2 ^ ((tonumber(n) or 0) % 32)))
        end,
        arshift = function(a, n)
          n = (tonumber(n) or 0) % 32
          local value = signed(unsigned(a))
          return signed(math.floor(value / 2 ^ n))
        end,
      }
    end
  end

  package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
    .. package.path
  package.loaded["src.import.RomManifest"] = nil
  package.loaded["src.import.RomExtractorGen2"] = nil
  package.loaded["src.import.ImageWriter"] = nil

  local integrationImages = {}
  love = {
    filesystem = {
      read = function(path)
        local body = read(engineRoot .. "/" .. path)
        if body then return body end
        return nil, "not found"
      end,
    },
    image = {
      newImageData = function(width, height)
        local image = { width = width, height = height, released = 0 }
        function image:setPixel() end
        function image:getDimensions() return self.width, self.height end
        function image:release() self.released = self.released + 1 end
        integrationImages[#integrationImages + 1] = image
        return image
      end,
    },
  }

  local integration = Assets.new({
    read = function(_, path)
      eq(path, Assets.importPath, "integration scoped path")
      return goldRaw
    end,
  }, {
    -- The production path uses love.data.hash.  The portable LuaJIT harness
    -- has no LOVE crypto module, so this seam only supplies the already-known
    -- digest while the exact engine modules perform every decode below.
    md5 = function(raw)
      eq(raw, goldRaw, "integration validates exact supplied bytes")
      return Assets.md5
    end,
  })
  local realPayload, realReason = integration:load()
  check(realPayload ~= nil, "0.1.96 decodes the real Gold UI: "
    .. tostring(realReason or integration:status().detail))
  eq(realPayload.imageData.packMenu.width, 128, "real Pack menu width")
  eq(realPayload.imageData.pack.height, 96, "real Pack picture height")
  eq(realPayload.imageData.gear.height, 48, "real Pokegear sheet height")
  eq(realPayload.imageData.sprites.width, 16, "real Pokegear sprites width")
  eq(realPayload.imageData.chris.width, 16, "real Chris sheet width")
  eq(realPayload.imageData.chris.height, 96, "real Chris sheet height")
  eq(realPayload.sprites.SPRITE_CHRIS.frames, 6,
    "real Chris sheet exposes six poses")
  eq(realPayload.sprites.SPRITE_CHRIS.paletteId, 0,
    "real Chris uses PAL_OW_RED")
  for _, day in ipairs({ "MORN", "DAY", "NITE", "DARK" }) do
    local colors = realPayload.palettes.objects[day]
      and realPayload.palettes.objects[day][1]
    check(type(colors) == "table" and #colors == 4,
      "real " .. day .. " PAL_OW_RED decoded")
    for index = 1, 4 do
      check(type(colors[index]) == "table" and #colors[index] == 3,
        "real " .. day .. " PAL_OW_RED color " .. index .. " is RGB")
    end
  end
  check(type(realPayload.landmarks.order) == "table"
    and #realPayload.landmarks.order > 0, "real landmarks decoded")
  eq(integration:release(), true, "real ImageData released")
  for _, image in ipairs(integrationImages) do
    eq(image.released, 1, "real decoder ImageData released once")
  end
end

love = oldLove
io.write(("gen2_ui_assets: %d checks passed\n"):format(checks))
