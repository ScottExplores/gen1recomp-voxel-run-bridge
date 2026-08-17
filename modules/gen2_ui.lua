-- Scott's Tweaks: an opt-in Gold presentation over Red's existing menus.
--
-- Red remains the controller.  Its StartMenu and BagMenu instances keep their
-- update methods, rows and callbacks; this module only replaces their draw
-- methods while the option is on.  The Pokegear is a deliberately separate,
-- small screen with only CLOCK and KANTO MAP cards.  All three screens draw to
-- the ordinary 160x144 UI canvas, so the Thor presenter can transport them
-- without a second presenter or controller.

local OPTION_KEY = "gen2_menus"
local POKEGEAR_SCREEN = "ScottsGoldGear"
local RECORD_KEY = "_scottsTweaksGen2UiDispatcher"
local FACADE_KEY = "_scottsTweaksGen2UiFacade"
local START_MARKER = "_scottsTweaksGoldStartDraw"
local BAG_MARKER = "_scottsTweaksGoldPackDraw"

local API_VERSION = 1
local unpackValues = table.unpack or unpack

local function pack(...)
  return { n = select("#", ...), ... }
end

local function enabledValue(value)
  if value == true then return true end
  if value == false or value == nil then return false end
  if type(value) == "number" then return value ~= 0 end
  if type(value) ~= "string" then return false end
  value = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value ~= "0" and value ~= "off"
    and value ~= "false" and value ~= "disabled" and value ~= "none"
end

local function optionEnabled(mod, context)
  local settings = context and context.settings
  if settings and type(settings.get) == "function" then
    local ok, value = pcall(settings.get, settings, OPTION_KEY)
    if ok then return enabledValue(value) end
  end
  local options = mod and mod.options
  if options and type(options.get) == "function" then
    local ok, value = pcall(options.get, options, OPTION_KEY)
    if ok then return enabledValue(value) end
  end
  return false
end

local function callLogger(mod, level, message)
  local logger = mod and mod.log
  local fn = logger and logger[level]
  if type(fn) == "function" then
    pcall(fn, logger, "%s", tostring(message))
  end
end

local function safeRequire(name)
  local ok, value = pcall(require, name)
  if ok then return value end
  return nil, value
end

local function release(value)
  if value and type(value.release) == "function" then
    pcall(value.release, value)
  end
end

local function releaseQuads(owner)
  if type(owner) ~= "table" or type(owner.quads) ~= "table" then return end
  for _, quad in pairs(owner.quads) do release(quad) end
  owner.quads = {}
end

local function copySequence(source)
  local out = {}
  for index, value in ipairs(source or {}) do out[index] = value end
  return out
end

local function construct(factory, fallback, ...)
  local fn
  if type(factory) == "function" then
    fn = factory
  elseif type(factory) == "table" then
    fn = factory.new
  end
  if type(fn) == "function" then return fn(...) end
  assert(type(fallback) == "table" and type(fallback.new) == "function",
    "Gold interface has no native screen fallback")
  return fallback.new(...)
end

local function graphicsCall(graphics, body)
  if not graphics then return false, "love.graphics is unavailable" end
  local pushed = false
  if type(graphics.push) == "function" and type(graphics.pop) == "function" then
    local ok = pcall(graphics.push, "all")
    if not ok then ok = pcall(graphics.push) end
    pushed = ok
  end
  local result = pack(xpcall(body, function(err)
    if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
    return tostring(err)
  end))
  if pushed then pcall(graphics.pop) end
  if not result[1] then return false, result[2] end
  return true, unpackValues(result, 2, result.n)
end

local function findPocket(list)
  local marker = type(list) == "table"
    and rawget(list, "_scottsTweaksPocketLayer") or nil
  local state = type(marker) == "table" and marker.state or nil
  local index = type(state) == "table" and tonumber(state.pocket) or 1
  index = math.max(1, math.min(4, math.floor(index or 1)))
  return ({ "ITEM", "BALL", "TM_HM", "KEY_ITEM" })[index], index
end

local function selectedItem(list)
  return list and list.items and list.items[list.index or 1] or nil
end

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(mod, context, generation, dependencies)
  return setmetatable({
    mod = mod,
    context = context,
    controller = context and context.gen2Assets,
    generation = generation,
    dependencies = dependencies,
    graphics = (context and context.graphics) or (love and love.graphics),
    payload = nil,
    images = {},
    packGfx = nil,
    playerMarker = nil,
    presenters = setmetatable({}, { __mode = "k" }),
    attempted = false,
    ready = false,
    retired = false,
    lastError = nil,
    warned = {},
  }, Runtime)
end

function Runtime:enabled()
  return not self.retired and optionEnabled(self.mod, self.context)
end

function Runtime:warnOnce(key, message)
  if self.warned[key] then return end
  self.warned[key] = true
  callLogger(self.mod, "warn", "Gold interface: " .. tostring(message))
end

function Runtime:setError(reason)
  self.ready = false
  self.lastError = tostring(reason or "Gold assets are unavailable")
  self:warnOnce(self.lastError, self.lastError)
  return false, self.lastError
end

function Runtime:newImage(imageData, key)
  local graphics = self.graphics
  if not graphics or type(graphics.newImage) ~= "function" then
    return nil, "love.graphics.newImage is unavailable"
  end
  local ok, image = pcall(graphics.newImage, imageData)
  if not ok or not image then
    return nil, tostring(image or ("could not create " .. key .. " image"))
  end
  if type(image.setFilter) == "function" then
    pcall(image.setFilter, image, "nearest", "nearest")
  end
  return image
end

function Runtime:newPlayerMarker(payload, image)
  local graphics = self.graphics
  local def = payload and payload.sprites
    and payload.sprites.SPRITE_CHRIS
  local palettes = payload and payload.palettes
  if not (image and type(def) == "table" and type(palettes) == "table"
      and type(graphics) == "table" and type(graphics.newQuad) == "function") then
    return nil
  end
  local width, height = 16, 96
  if type(image.getDimensions) == "function" then
    local ok, iw, ih = pcall(image.getDimensions, image)
    if not ok or iw ~= width or ih ~= height then return nil end
  end
  if tonumber(def.frames) ~= 6 or tonumber(def.paletteId) ~= 0 then return nil end

  local quads = {}
  for _, frame in ipairs({ 0, 3 }) do
    local ok, quad = pcall(graphics.newQuad,
      0, frame * 16, 16, 16, width, height)
    if not ok or not quad then
      for _, owned in pairs(quads) do release(owned) end
      return nil
    end
    quads[frame] = quad
  end
  return {
    image = image,
    def = def,
    palettes = palettes,
    quads = quads,
  }
end

function Runtime:ensure()
  if self.retired then return false, "Gold interface generation is retired" end
  if self.ready then return true end
  if self.attempted then return false, self.lastError end
  self.attempted = true

  local controller = self.controller
  if type(controller) ~= "table" or type(controller.load) ~= "function" then
    return self:setError("Gold ROM import needs Gen1Recomp 0.1.96 or newer")
  end
  local ok, payload, reason = pcall(controller.load, controller)
  if not ok then return self:setError(payload) end
  if type(payload) ~= "table" then
    if reason == "gen2_import_api_unavailable" then
      reason = "Gold ROM import needs Gen1Recomp 0.1.96 or newer"
    end
    return self:setError(reason or "Import Pokemon Gold to use this interface")
  end
  local menuGfx = payload.menuGfx
  local imageData = payload.imageData
  local packMeta = type(menuGfx) == "table" and menuGfx.pack or nil
  local gearMeta = type(menuGfx) == "table" and menuGfx.pokegear or nil
  if type(packMeta) ~= "table" or type(gearMeta) ~= "table"
      or type(imageData) ~= "table" then
    return self:setError("Gold ROM menu metadata is incomplete")
  end

  local made = {}
  for _, key in ipairs({ "packMenu", "pack", "gear", "sprites" }) do
    if imageData[key] == nil then
      for _, image in pairs(made) do release(image) end
      return self:setError("Gold ROM image data is missing " .. key)
    end
    local image, imageError = self:newImage(imageData[key], key)
    if not image then
      for _, owned in pairs(made) do release(owned) end
      return self:setError(imageError)
    end
    made[key] = image
  end

  -- The menu remains usable if a future/partial payload lacks the optional
  -- Chris marker.  When present, it is another in-memory GPU image owned by
  -- this runtime generation and released with the other imported resources.
  if imageData.chris ~= nil then
    local image, imageError = self:newImage(imageData.chris, "chris")
    if image then
      made.chris = image
    else
      self:warnOnce("chris_image", "Chris marker omitted: "
        .. tostring(imageError))
    end
  end

  local PackGfx = self.dependencies.PackGfx
  local okPack, packGfx = pcall(PackGfx.new, menuGfx)
  if not okPack or type(packGfx) ~= "table" then
    for _, image in pairs(made) do release(image) end
    return self:setError(packGfx or "Gold Pack renderer could not start")
  end
  local menuKey = packMeta.menu or packMeta.menuImageDataKey or "packMenu"
  local packKey = packMeta.pack or packMeta.packImageDataKey or "pack"
  packGfx.images[menuKey] = made.packMenu
  packGfx.images[packKey] = made.pack

  self.payload = payload
  self.images = made
  self.packGfx = packGfx
  self.playerMarker = self:newPlayerMarker(payload, made.chris)
  self.ready = true
  self.lastError = nil
  return true
end

function Runtime:releaseResources(releaseController)
  for presenter in pairs(self.presenters) do
    if type(presenter) == "table" then
      releaseQuads(presenter.sheet)
      releaseQuads(presenter.arrow)
      if type(presenter.sheet) == "table" then presenter.sheet.loaded = false end
      if type(presenter.arrow) == "table" then presenter.arrow.loaded = false end
    end
  end
  self.presenters = setmetatable({}, { __mode = "k" })
  releaseQuads(self.playerMarker)
  self.playerMarker = nil
  releaseQuads(self.packGfx)
  self.packGfx = nil
  for _, image in pairs(self.images) do release(image) end
  self.images = {}
  self.payload = nil
  if releaseController and self.controller
      and type(self.controller.release) == "function" then
    pcall(self.controller.release, self.controller)
  end
  self.ready = false
end

function Runtime:retire()
  if self.retired then return end
  self:releaseResources(true)
  self.retired = true
end

function Runtime:reload()
  if self.retired then return false, "Gold interface generation is retired" end
  self:releaseResources(true)
  self.attempted = false
  self.lastError = nil
  self.warned = {}
  if not self:enabled() then return true end
  return self:ensure()
end

local START_DESCRIPTIONS = {
  ["POKéDEX"] = { "POKéMON", "database" },
  ["POKéMON"] = { "Party POKéMON", "status" },
  ["ITEM"] = { "Contains", "items" },
  ["PACK"] = { "Contains", "items" },
  ["POKéGEAR"] = { "Clock and", "Kanto map" },
  ["SAVE"] = { "Save your", "progress" },
  ["OPTION"] = { "Change", "settings" },
  ["LINK"] = { "Link with", "another game" },
  ["MODS"] = { "Installed", "add-ons" },
  ["QUIT"] = { "Return to", "the title" },
}

local function rowDescription(menu, item)
  if type(item) ~= "table" then return nil end
  if type(item.desc) == "table" then return item.desc end
  if item.id == "scotts_tweaks.open" then
    return { "Scott's", "settings" }
  end
  local label = tostring(item.label or "")
  local player = menu and menu.game and menu.game.save
    and menu.game.save.player and menu.game.save.player.name
  if player and label == player then return { "Your own", "status" } end
  return START_DESCRIPTIONS[label]
end

function Runtime:drawStart(menu)
  if not self:enabled() then return false end
  local ready = self:ensure()
  if not ready then return false end
  local Chrome, Font = self.dependencies.Chrome, self.dependencies.Font
  local graphics = self.graphics
  local ok, drawError = graphicsCall(graphics, function()
    local items = type(menu.items) == "table" and menu.items or {}
    local maxVisible = tonumber(menu.maxVisible) or #items
    local visible = math.min(math.max(1, maxVisible), math.max(1, #items))
    local scroll = math.max(0, math.floor(tonumber(menu.scroll) or 0))
    local index = math.max(1, math.floor(tonumber(menu.index) or 1))
    if index <= scroll then scroll = index - 1 end
    if index > scroll + visible then scroll = index - visible end
    scroll = math.min(scroll, math.max(0, #items - visible))

    local widest = 7
    for row = 1, visible do
      local item = items[scroll + row]
      if item then
        local label = item.label == "ITEM" and "PACK" or item.label
        local pixels = type(Font.width) == "function"
          and Font.width(tostring(label or "")) or #tostring(label or "") * 8
        widest = math.max(widest, math.ceil(pixels / 8))
      end
    end
    local tw = math.max(10, math.min(20, widest + 3))
    local tx = 20 - tw
    local th = math.min(18, visible * 2 + 2)
    Chrome.box(tx, 0, tw, th)
    for row = 1, visible do
      local item = items[scroll + row]
      if item then
        local ty = 1 + (row - 1) * 2
        if scroll + row == index then Chrome.cursor(tx + 1, ty) end
        local label = item.label == "ITEM" and "PACK" or item.label
        Chrome.print(tostring(label or ""), tx + 2, ty)
      end
    end
    if scroll > 0 then Chrome.print("▲", tx + tw - 2, 0) end
    if scroll + visible < #items then Chrome.print("▼", tx + tw - 2, th - 1) end

    local game = menu.game
    local safari = game and game.save and game.save.safari
    local overworld = game and game.overworld
    local inSafari = safari and overworld and overworld.map
      and type(overworld.inSafariStepZone) == "function"
    if inSafari then
      local okSafari, active = pcall(overworld.inSafariStepZone, overworld)
      if okSafari and active then
        Chrome.box(0, 0, 9, 5)
        Chrome.print(("%3d"):format(math.floor(safari.steps or 0)), 1, 1)
        Chrome.print("/500", 4, 1)
        Chrome.print("BALL", 1, 3)
        Chrome.print(("%2d"):format(math.floor(safari.balls or 0)), 6, 3)
      end
    end

    -- Gold's MENU ACCOUNT sits in the lower-left.  Long mod labels can widen
    -- the right box into that area; in that case the rows remain the priority.
    local item = items[index]
    local desc = rowDescription(menu, item)
    if desc and tx >= 10 and type(graphics.rectangle) == "function" then
      graphics.setColor(1, 1, 1, 1)
      graphics.rectangle("fill", 0, 13 * 8, 10 * 8, 5 * 8)
      Chrome.print(desc[1] or "", 0, 14)
      Chrome.print(desc[2] or "", 0, 16)
    end
    if type(graphics.setColor) == "function" then
      graphics.setColor(1, 1, 1, 1)
    end
  end)
  if not ok then
    self.lastError = tostring(drawError)
    self:warnOnce("start_draw", "Start presentation failed; using Red: "
      .. tostring(drawError))
    return false
  end
  return true
end

local function visibleStart(list, rows)
  local count = #(list.items or {})
  local index = math.max(1, math.min(count, tonumber(list.index) or 1))
  local first = math.max(1, index - rows + 1)
  first = math.min(first, math.max(1, count - rows + 1))
  return first
end

local function itemDescription(list, item)
  local game = list and list.game
  local def = game and game.data and game.data.items and item
    and game.data.items[item.value]
  return def and def.description or nil, def
end

function Runtime:drawPack(list)
  if not self:enabled() then return false end
  local ready = self:ensure()
  if not ready or not self.packGfx then return false end
  local Chrome = self.dependencies.Chrome
  local graphics = self.graphics
  local ok, drawError = graphicsCall(graphics, function()
    local pocketId = findPocket(list)
    self.packGfx:draw(pocketId)
    Chrome.box(0, 12, 20, 6)

    local rows, first = 5, visibleStart(list, 5)
    local items = list.items or {}
    if #items == 0 then
      Chrome.print("EMPTY", 8, 2)
    else
      for row = 1, rows do
        local itemIndex = first + row - 1
        local item = items[itemIndex]
        if item then
          local ty = 2 + (row - 1) * 2
          if itemIndex == list.index then
            Chrome.cursor(7, ty, list.swapIndex == itemIndex)
          end
          Chrome.print(tostring(item.label or item.value or ""), 8, ty)
          local description, def = itemDescription(list, item)
          local second
          if pocketId == "TM_HM" and def and def.machine then
            local moveId = def.machine.move or def.machine.teaches
            local move = list.game and list.game.data and list.game.data.moves
              and list.game.data.moves[moveId]
            second = move and move.name
            -- Gold's TM/HM pocket describes the taught move in the bottom
            -- box; Red's item record is only the fallback for a modded
            -- machine whose move metadata has no description.
            description = move and move.description or description
          elseif pocketId == "ITEM" or pocketId == "BALL" then
            second = item.right
            if second then second = tostring(second):gsub("^x", "×") end
          end
          if second then Chrome.print(second, 9, ty + 1) end
          if itemIndex == list.index and description then
            local lines = Chrome.wrap(tostring(description):gsub("<NEXT>", "\n"), 18)
            if lines[1] then Chrome.print(lines[1], 1, 14) end
            if lines[2] then Chrome.print(lines[2], 1, 16) end
          end
        end
      end
    end
    graphics.setColor(1, 1, 1, 1)
  end)
  if not ok then
    self.lastError = tostring(drawError)
    self:warnOnce("pack_draw", "Pack presentation failed; using Red: "
      .. tostring(drawError))
    return false
  end
  return true
end

function Runtime:clock()
  local provider = self.context and self.context.clock
  if type(provider) == "function" then
    local ok, value = pcall(provider)
    if ok and type(value) == "table" then return value end
  end
  local now = os.date and os.date("*t") or nil
  return {
    hour = now and now.hour or 12,
    minute = now and now.min or 0,
    weekday = now and now.wday or 1,
  }
end

function Runtime:currentLandmark(game)
  local landmarks = self.payload and self.payload.landmarks
  local values = landmarks and landmarks.landmarks
  if type(values) ~= "table" then return nil end
  local function normalized(value)
    if type(value) ~= "string" then return nil end
    value = value:upper():gsub("<[^>]+>", " ")
      :gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
  end
  local byName = {}
  local function remember(value, id)
    local key = normalized(value)
    if key then byName[key] = id end
  end
  for id, entry in pairs(values) do
    remember(id, id)
    if type(entry) == "table" then
      remember(entry.id, id)
      remember(entry.name, id)
    end
  end

  local mapId = game and game.overworld and game.overworld.map
    and game.overworld.map.id
  local candidates = { mapId }
  local field = game and game.data and game.data.field
  local townMap = field and field.townMap
  local locations = townMap and (townMap.locations or townMap)
  local location = type(locations) == "table" and locations[mapId] or nil
  if type(location) == "table" then
    candidates[#candidates + 1] = location.id
    candidates[#candidates + 1] = location.name
    candidates[#candidates + 1] = location.label
  elseif type(location) == "string" then
    candidates[#candidates + 1] = location
  end
  local mapDef = game and game.data and game.data.maps
    and game.data.maps[mapId]
  if type(mapDef) == "table" then
    candidates[#candidates + 1] = mapDef.id
    candidates[#candidates + 1] = mapDef.name
    candidates[#candidates + 1] = mapDef.label
  end
  for _, candidate in ipairs(candidates) do
    local key = normalized(candidate)
    local match = values[candidate] and candidate or (key and byName[key])
    if match then
      self.lastLandmark = match
      return match
    end
  end

  -- Interiors normally share their town-map record with the outdoor map.  A
  -- custom/unmapped room should not teleport the Gear marker back to Pallet;
  -- hold the last place that was actually resolved during this session.
  if self.lastLandmark and values[self.lastLandmark] then
    return self.lastLandmark
  end
  if values.PALLET_TOWN then
    self.lastLandmark = "PALLET_TOWN"
    return self.lastLandmark
  end
  for id, entry in pairs(values) do
    local index = type(entry) == "table" and tonumber(entry.index)
    if index and index >= 0x2e and index <= 0x5d then
      self.lastLandmark = id
      return id
    end
  end
  self.lastLandmark = next(values)
  return self.lastLandmark
end

function Runtime:playerMarkerColors(presenter)
  local marker = self.playerMarker
  if not marker then return nil end
  local Palettes = self.dependencies.Palettes
  local game = presenter and presenter.game
  local world = game and game.world
  local daytime = world and world.daytime
  if not daytime and Palettes and type(Palettes.clockDaytime) == "function" then
    daytime = Palettes.clockDaytime(
      presenter and presenter.clock and presenter.clock.hour or nil)
  end
  if type(daytime) == "string" then daytime = daytime:upper() end
  daytime = daytime or "DAY"
  if Palettes and type(Palettes.spritePalette) == "function" then
    return Palettes.spritePalette(
      marker.palettes, daytime, marker.def), daytime
  end
  local set = marker.palettes.objects and marker.palettes.objects[daytime]
  return set and set[(tonumber(marker.def.paletteId) or 0) + 1], daytime
end

function Runtime:drawPlayerMarker(presenter, x, y)
  local marker = self.playerMarker
  local graphics = self.graphics
  -- Returning true is deliberate: Pokegear's false branch draws a generated
  -- square.  If the authentic ROM sprite is absent or a generation was
  -- retired, omitting the marker is safer than silently replacing its art.
  if self.retired or not self.ready or not marker
      or not graphics or type(graphics.draw) ~= "function" then
    return true
  end

  -- .Frameset_RedWalk: stand, walk, stand, mirrored walk, eight frames each.
  -- ChrisSpriteGFX is six vertical 16x16 poses; down-stand is 0 and down-walk
  -- is 3, exactly matching SpriteRenderer's Gen 2 facing table.
  local beat = math.floor((presenter.iconTimer or 0) / 8) % 4
  local frame = (beat % 2 == 1) and 3 or 0
  local quad = marker.quads and marker.quads[frame]
  if not quad then return true end
  local flip = beat == 3
  local draw = function()
    if type(graphics.setColor) == "function" then
      graphics.setColor(1, 1, 1, 1)
    end
    if flip then
      graphics.draw(marker.image, quad, x + 8, y - 8, 0, -1, 1)
    else
      graphics.draw(marker.image, quad, x - 8, y - 8)
    end
  end

  local colors = self:playerMarkerColors(presenter)
  local GbcPalette = self.dependencies.GbcPalette
  if colors and GbcPalette and type(GbcPalette.with) == "function" then
    GbcPalette.with(colors, draw)
  else
    draw()
  end
  return true
end

function Runtime:playerMarkerStatus()
  if self.playerMarker then return "pokemon_gold_sprite_chris" end
  return "omitted_without_authentic_rom_sprite"
end

function Runtime:makePokegear(game, onClose)
  local ready, reason = self:ensure()
  if not ready then return nil, reason end
  local proxySave = {
    pokegearFlags = { map = true },
    engineFlags = {},
    flags = { HALL_OF_FAME = true },
    party = game and game.save and game.save.party or {},
  }
  local Pokegear = self.dependencies.Pokegear
  local ok, presenter = pcall(Pokegear.new, game, {
    save = proxySave,
    menuGfx = self.payload.menuGfx,
    landmarks = self.payload.landmarks,
    currentLandmark = self:currentLandmark(game),
    clock = self:clock(),
    sprites = self.payload.sprites,
    palettes = self.payload.palettes,
    onClose = onClose,
  })
  if not ok or type(presenter) ~= "table" then
    return nil, tostring(presenter or "Pokegear could not start")
  end
  if type(presenter.sheet) ~= "table" then
    return nil, "Gold Pokegear tile sheet is unavailable"
  end
  presenter.sheet.loaded = self.images.gear
  -- Prevent the stock path-backed SpriteRenderer from trying the logical
  -- in-memory key in payload.sprites.  drawPlayerIcon below owns this sheet.
  presenter.playerIcon = false
  if type(presenter.loadArrowSheet) == "function" then
    pcall(presenter.loadArrowSheet, presenter)
  end
  if type(presenter.arrow) == "table" then
    presenter.arrow.loaded = self.images.sprites
    -- STILL_CURSOR reuses RED_WALK's OAM data on the cart.  The stock loader
    -- normally borrows playerIcon.objColors, but our memory-only Chris image
    -- intentionally bypasses its path-backed SpriteRenderer.  Restore that
    -- exact PAL_OW_RED link on the TileSheet itself, evaluated live so a
    -- time-of-day change reaches both the marker and the cursor together.
    presenter.arrow.paletteFor = function()
      return self:playerMarkerColors(presenter)
    end
  end
  -- Keep Pokegear's controller and map math; replace only its path-backed
  -- SpriteRenderer seam so the validated ROM's memory-only Image can be used.
  -- The draw routine above preserves the cart's RED_WALK cadence, flip and
  -- PAL_OW_RED time-of-day palette shader.
  presenter.drawPlayerIcon = function(owner, x, y)
    return self:drawPlayerMarker(owner, x, y)
  end
  presenter._scottsTweaksPlayerMarker = self:playerMarkerStatus()
  self.presenters[presenter] = true
  return presenter
end

local GearScreen = {}
GearScreen.__index = GearScreen
GearScreen.isOpaque = true

function GearScreen.new(game, record, mod)
  return setmetatable({
    game = game,
    record = record,
    mod = mod,
    screenId = POKEGEAR_SCREEN,
    presenter = nil,
    presenterGeneration = nil,
    error = nil,
    closing = false,
  }, GearScreen)
end

function GearScreen:close()
  if self.closing then return end
  self.closing = true
  local stack = self.game and self.game.stack
  if stack and type(stack.pop) == "function" then
    local top = type(stack.top) == "function" and stack:top() or self
    if top == self then stack:pop() end
  end
  local runtime = self.record and self.record.runtime
  local liveMod = runtime and runtime.mod or self.mod
  if liveMod and liveMod.ui and type(liveMod.ui.push) == "function" then
    liveMod.ui.push(self.game, "StartMenu")
  end
end

function GearScreen:ensurePresenter()
  local runtime = self.record and self.record.runtime
  if not runtime or runtime.retired or not runtime:enabled() then
    self.presenter, self.presenterGeneration = nil, nil
    self.error = "GEN 2 INTERFACE IS OFF"
    return nil
  end
  if self.presenter and self.presenterGeneration == runtime.generation then
    return self.presenter
  end
  self.presenter = nil
  local presenter, reason = runtime:makePokegear(self.game,
    function() self:close() end)
  self.presenter = presenter
  self.presenterGeneration = presenter and runtime.generation or nil
  self.error = presenter and nil or reason
  return presenter
end

function GearScreen:update(dt)
  local presenter = self:ensurePresenter()
  if presenter and type(presenter.update) == "function" then
    return presenter:update(dt)
  end
  local input = self.game and self.game.input
  if input and type(input.wasPressed) == "function"
      and (input:wasPressed("b") or input:wasPressed("start")) then
    self:close()
  end
end

function GearScreen:draw()
  local presenter = self:ensurePresenter()
  local runtime = self.record and self.record.runtime
  if presenter and runtime then
    presenter.clock = runtime:clock()
    presenter.currentLandmark = runtime:currentLandmark(self.game)
    local ok, drawError = graphicsCall(runtime.graphics, function()
      presenter:draw()
    end)
    if ok then return end
    self.error = tostring(drawError)
    runtime:warnOnce("gear_draw", "Pokegear presentation failed: "
      .. tostring(drawError))
  end
  local Chrome = runtime and runtime.dependencies.Chrome
  local graphics = runtime and runtime.graphics
  if Chrome and graphics then
    graphicsCall(graphics, function()
      Chrome.clear()
      Chrome.box(0, 4, 20, 10)
      Chrome.print("POKéGEAR UNAVAILABLE", 1, 6)
      Chrome.print("IMPORT POKéMON GOLD", 1, 9)
      Chrome.print("B: BACK", 1, 12)
      graphics.setColor(1, 1, 1, 1)
    end)
  end
end

local function decorateDraw(state, record, markerKey, method)
  if type(state) ~= "table" or type(state.draw) ~= "function" then return state end
  local marker = rawget(state, markerKey)
  if type(marker) == "table" and marker.owner == record.owner then
    marker.record = record
    return state
  elseif marker ~= nil then
    return state
  end
  local baseDraw = state.draw
  local wrapper = function(self, ...)
    local runtime = record.runtime
    if runtime and not runtime.retired and runtime[method](runtime, self) then
      return
    end
    return baseDraw(self, ...)
  end
  state.draw = wrapper
  rawset(state, markerKey, {
    owner = record.owner,
    record = record,
    baseDraw = baseDraw,
    wrapper = wrapper,
  })
  return state
end

local function insertPokegear(items, game, mod)
  for _, item in ipairs(items) do
    if type(item) == "table" and item.id == "scotts_tweaks.pokegear" then
      return items
    end
  end
  local out = copySequence(items)
  local row = {
    id = "scotts_tweaks.pokegear",
    label = "POKéGEAR",
    desc = { "Clock and", "Kanto map" },
    onSelect = function()
      return mod.ui.push(game, POKEGEAR_SCREEN)
    end,
  }
  local at = #out + 1
  for index, item in ipairs(out) do
    local label = type(item) == "table" and item.label or nil
    local id = type(item) == "table" and item.id or nil
    if label == "ITEM" or label == "PACK" or id == "pack" or id == "item" then
      at = index + 1
      break
    end
  end
  table.insert(out, at, row)
  return out
end

return function(mod, context)
  assert(type(mod) == "table", "Gold interface needs the mod API")
  context = type(context) == "table" and context or {}
  assert(mod.content and mod.content.screens,
    "Gold interface needs the screen registry")

  local Chrome, chromeError = safeRequire("src.ui.gen2.Chrome")
  local PackGfx, packError = safeRequire("src.ui.gen2.PackGfx")
  local Pokegear, gearError = safeRequire("src.ui.gen2.Pokegear")
  local Font, fontError = safeRequire("src.render.Font")
  local GbcPalette = safeRequire("src.render.GbcPalette")
  local Palettes = safeRequire("src.world.gen2.Palettes")
  local EngineScreens, engineScreensError = safeRequire("src.ui.Screens")
  if not (type(Chrome) == "table" and type(PackGfx) == "table"
      and type(Pokegear) == "table" and type(Font) == "table"
      and type(EngineScreens) == "table") then
    error("Gold interface needs Gen1Recomp's Gen 2 UI modules: "
      .. tostring(chromeError or packError or gearError or fontError
        or engineScreensError), 0)
  end
  local dependencies = {
    Chrome = Chrome, PackGfx = PackGfx, Pokegear = Pokegear, Font = Font,
    GbcPalette = GbcPalette, Palettes = Palettes,
  }

  local screens = mod.content.screens
  -- `mod.content.screens` is a fresh facade on Loader F5.  Screens is an engine
  -- module and survives that reload, so it is the process-stable handoff point
  -- that lets a new generation retire GPU objects and refresh already-open
  -- Start/Bag/Gear wrappers from the old facade.
  local record = rawget(EngineScreens, RECORD_KEY)
  if record ~= nil and (type(record) ~= "table"
      or record.owner ~= mod.id or record.dispatcher ~= true) then
    error("Gold interface screen dispatcher is owned by another feature", 0)
  end

  if not record then
    record = {
      owner = mod.id,
      dispatcher = true,
      generation = 0,
      runtime = nil,
    }
    rawset(EngineScreens, RECORD_KEY, record)
  end

  local facade = rawget(screens, FACADE_KEY)
  if facade ~= nil and (type(facade) ~= "table"
      or facade.owner ~= mod.id or facade.dispatcher ~= record) then
    error("Gold interface registry facade is owned by another feature", 0)
  end

  if not facade then
    facade = { owner = mod.id, dispatcher = record }
    rawset(screens, FACADE_KEY, facade)

    local priorStart = screens:get("StartMenu")
    local priorBag = screens:get("BagMenu")
    local builtinStart = assert(safeRequire("src.ui.StartMenu"))
    local builtinBag = assert(safeRequire("src.ui.BagMenu"))

    screens:override("StartMenu", {
      new = function(game, ...)
        local state = construct(priorStart, builtinStart, game, ...)
        local live = record.runtime
        if live and live:enabled() and live:ensure() then
          return decorateDraw(state, record, START_MARKER, "drawStart")
        end
        return state
      end,
    })
    screens:override("BagMenu", {
      new = function(game, ...)
        local state = construct(priorBag, builtinBag, game, ...)
        local live = record.runtime
        if live and live:enabled() and live:ensure() then
          return decorateDraw(state, record, BAG_MARKER, "drawPack")
        end
        return state
      end,
    })

    record.newGearScreen = function(game)
      return GearScreen.new(game, record, mod)
    end
    local gearFactory = {
      new = function(game) return record.newGearScreen(game) end,
    }
    if screens:get(POKEGEAR_SCREEN) ~= nil then
      screens:override(POKEGEAR_SCREEN, gearFactory)
    else
      screens:register(POKEGEAR_SCREEN, gearFactory)
    end
  end
  record.newGearScreen = function(game)
    return GearScreen.new(game, record, mod)
  end

  if record.runtime and type(record.runtime.retire) == "function" then
    record.runtime:retire()
  end
  record.generation = (tonumber(record.generation) or 0) + 1
  local runtime = Runtime.new(mod, context, record.generation, dependencies)
  record.runtime = runtime

  assert(mod.hooks and type(mod.hooks.wrap) == "function",
    "Gold interface needs UI hooks")
  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" or not runtime:enabled() then return out end
    local ready = runtime:ensure()
    if not ready then return out end
    return insertPokegear(out, game, mod)
  end, 100)

  local api = {
    apiVersion = API_VERSION,
    installed = true,
    optionKey = OPTION_KEY,
    screenIds = { pokegear = POKEGEAR_SCREEN },
    getEnabled = function() return runtime:enabled() end,
    reload = function() return runtime:reload() end,
    release = function()
      if record.runtime == runtime then runtime:retire() end
    end,
    getStatus = function()
      local assetStatus
      if runtime.controller and type(runtime.controller.status) == "function" then
        local ok, value = pcall(runtime.controller.status, runtime.controller)
        if ok and type(value) == "table" then assetStatus = value end
      end
      return {
        apiVersion = API_VERSION,
        installed = true,
        enabled = runtime:enabled(),
        active = runtime.ready and not runtime.retired,
        ready = runtime.ready,
        attempted = runtime.attempted,
        retired = runtime.retired,
        generation = runtime.generation,
        optionKey = OPTION_KEY,
        style = "pokemon_gold_rom",
        controller = "red_native_callbacks",
        modernUi = "coexists_fail_open",
        presenter = "ui_canvas_only",
        playerMarker = runtime:playerMarkerStatus(),
        screenIds = { pokegear = POKEGEAR_SCREEN },
        lastError = runtime.lastError,
        assets = assetStatus,
      }
    end,
  }
  mod.exports = type(mod.exports) == "table" and mod.exports or {}
  mod.exports.gen2Ui = api
  return api
end
