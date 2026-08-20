-- Scott's Tweaks: ROM-free PACK + Crystal-inspired POKeGEAR navigation.
--
-- Red remains authoritative. The native ITEM/ITEMS row keeps its callback and
-- is presented as PACK; the inventory module supplies the pockets. POKeGEAR is
-- an opaque 160x144 screen with the cart's CLOCK -> MAP -> PHONE -> RADIO card
-- order and left/right paging. Its art is drawn from original primitives -- no
-- Gold/Crystal ROM, extracted tile sheet, or copyrighted screen asset is used.
--
-- Gen 1 has no Pokegear story flags, phone scripts, or radio program VM. The
-- useful equivalents are capability-detected instead: MAP opens Red's native
-- TownMap, PHONE reads Scott's trainer/rematch journey memory without changing
-- it, and RADIO plays only song ids present in the active Red cache through the
-- public Music API. Missing capabilities remain visible and explain themselves
-- instead of becoming a dead button. No new save field is required, so old
-- saves acquire the screen without migration.

local OPTION_KEY = "gen2_menus"
local POKEGEAR_SCREEN = "ScottsPokegear"
local POKEGEAR_ITEM_ID = "scotts_tweaks.pokegear"
local API_VERSION = 3

local SCREEN_W, SCREEN_H = 160, 144
local CARD_ORDER = {
  { id = "clock", label = "CLOCK" },
  { id = "map", label = "MAP" },
  { id = "phone", label = "PHONE" },
  { id = "radio", label = "RADIO" },
}

local DAYS = {
  "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY",
  "SATURDAY",
}

-- Frequencies and names follow the sort of programs Crystal exposes. The
-- audio candidates are deliberately Gen-1 labels, and are admitted only when
-- the active cache actually owns them.
local RADIO_PRESETS = {
  {
    frequency = "4.5", name = "OAK'S POKéMON TALK",
    songs = { "Music_MeetProfOak", "Music_OaksLab" },
    kind = "oak",
  },
  {
    frequency = "8.0", name = "POKéDEX SHOW",
    songs = { "Music_Pokecenter", "Music_TitleScreen" },
    kind = "dex",
  },
  {
    frequency = "13.5", name = "POKéMON MUSIC",
    songs = { "Music_JigglypuffSong", "Music_SafariZone" },
    kind = "music",
  },
  {
    frequency = "16.5", name = "PLACES & PEOPLE",
    songs = { "Music_Cities1", "Music_PalletTown", "Music_Routes1" },
    kind = "places",
  },
}

local COLORS = {
  ground = { 13, 15, 22 },
  paper = { 248, 248, 216 },
  ink = { 24, 24, 32 },
  blue = { 40, 88, 176 },
  cyan = { 88, 184, 208 },
  pink = { 216, 72, 144 },
  red = { 208, 40, 56 },
  green = { 56, 152, 88 },
  grey = { 128, 128, 128 },
}

local function enabledValue(value)
  if value == true then return true end
  if value == false or value == nil then return false end
  if type(value) == "number" then return value ~= 0 end
  if type(value) ~= "string" then return false end
  value = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value ~= "0" and value ~= "off"
    and value ~= "false" and value ~= "disabled" and value ~= "none"
end

local function setting(mod, context, key, fallback)
  local settings = context and context.settings
  if settings and type(settings.get) == "function" then
    local ok, value = pcall(settings.get, settings, key, fallback)
    if ok and value ~= nil then return value end
  end
  if mod and mod.options and type(mod.options.get) == "function" then
    local ok, value = pcall(mod.options.get, mod.options, key)
    if ok and value ~= nil then return value end
  end
  return fallback
end

local function optionEnabled(mod, context)
  return enabledValue(setting(mod, context, OPTION_KEY, false))
end

local function tryRequire(name)
  local ok, value = pcall(require, name)
  if ok and type(value) == "table" then return value end
  return nil
end

local function copyItem(item)
  if type(item) ~= "table" then return item end
  local out = {}
  for key, value in pairs(item) do out[key] = value end
  return out
end

local function isPackRow(item)
  if type(item) ~= "table" then return false end
  local label = tostring(item.label or ""):upper()
  local id = tostring(item.id or ""):lower()
  return label == "ITEM" or label == "ITEMS" or label == "PACK"
    or id == "item" or id == "items" or id == "pack"
end

local function glyphs(text)
  local out = {}
  for char in tostring(text or ""):gmatch("[\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = char
  end
  return out
end

local function limit(text, width)
  local chars = glyphs(text)
  if #chars <= width then return table.concat(chars) end
  local out = {}
  for index = 1, math.max(0, width - 1) do out[index] = chars[index] end
  return table.concat(out) .. "."
end

local function cleanName(value, fallback)
  local text = tostring(value or fallback or "UNKNOWN")
  text = text:gsub("^OPP_", ""):gsub("_", " ")
  text = text:gsub("[%c]", " "):gsub("%s+", " ")
  text = text:match("^%s*(.-)%s*$") or ""
  return text ~= "" and text or (fallback or "UNKNOWN")
end

local function worldOf(game)
  if type(game) ~= "table" then return nil end
  return game.overworld or game.world
end

local function currentMap(game)
  local world = worldOf(game)
  local map = world and world.map
  local def = type(map) == "table" and (map.def or map) or nil
  local id = type(map) == "table" and map.id or nil
  id = id or (type(def) == "table" and def.id) or "KANTO"
  return tostring(id), def
end

local function clockParts(mod, game)
  local stamp = os.time()
  local date = os.date("*t", stamp) or {}
  local formatter = mod and mod.datetime
  if formatter and type(formatter.time) == "function" then
    local ok, value = pcall(formatter.time, formatter, game, stamp)
    if ok and type(value) == "string" and value ~= "" then
      return value, DAYS[tonumber(date.wday) or 1] or "DAY"
    end
  end
  return os.date("%H:%M", stamp), DAYS[tonumber(date.wday) or 1] or "DAY"
end

local function readOwnSave(mod, key)
  local save = mod and mod.save
  if not (save and type(save.get) == "function") then return nil end
  local ok, value = pcall(save.get, save, key)
  if ok then return value end
  return nil
end

local function trainerClassName(game, trainerClass)
  local trainers = game and game.data and game.data.trainers
  local def = type(trainers) == "table" and trainers[trainerClass] or nil
  return cleanName(type(def) == "table" and def.name or trainerClass, "TRAINER")
end

local function buildContacts(mod, game)
  local memory = readOwnSave(mod, "trainer_memory")
  local records = type(memory) == "table" and memory.trainers or nil
  local out = {}
  for key, record in pairs(type(records) == "table" and records or {}) do
    if type(record) == "table" then
      local class = record.trainerClass or tostring(key):match("|([^|]+)|")
      local name = trainerClassName(game, class)
      local mapId = cleanName(record.mapId or tostring(key):match("^(.-)|"),
        "KANTO")
      out[#out + 1] = {
        key = tostring(key),
        name = name,
        map = mapId,
        battles = math.max(0, math.floor(tonumber(record.battles) or 0)),
        wins = math.max(0, math.floor(tonumber(record.wins) or 0)),
        losses = math.max(0, math.floor(tonumber(record.losses) or 0)),
        rematches = math.max(0, math.floor(tonumber(record.rematches) or 0)),
        lastResult = tostring(record.lastResult or "unknown"):lower(),
        sequence = math.floor(tonumber(record.lastSequence) or 0),
      }
    end
  end
  table.sort(out, function(a, b)
    if a.sequence ~= b.sequence then return a.sequence > b.sequence end
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
  end)
  return out
end

local function firstSong(songs, candidates)
  if type(songs) ~= "table" then return nil end
  for _, id in ipairs(candidates or {}) do
    if songs[id] ~= nil then return id end
  end
  return nil
end

local function buildStations(game)
  local audio = game and game.data and game.data.audio
  local songs = type(audio) == "table" and audio.songs or nil
  local out = {}
  for _, preset in ipairs(RADIO_PRESETS) do
    out[#out + 1] = {
      frequency = preset.frequency,
      name = preset.name,
      kind = preset.kind,
      song = firstSong(songs, preset.songs),
    }
  end
  return out
end

local function countAvailableStations(rows)
  local count = 0
  for _, row in ipairs(rows or {}) do
    if row.song then count = count + 1 end
  end
  return count
end

local function collectMapPoints(game)
  local field = game and game.data and game.data.field or {}
  local townMap = type(field) == "table" and field.townMap or nil
  if type(townMap) == "table" and type(townMap.locations) == "table" then
    townMap = townMap.locations
  end
  local points = {}
  for id, raw in pairs(type(townMap) == "table" and townMap or {}) do
    local entry = type(raw) == "table" and (raw.coords or raw) or nil
    local x = entry and tonumber(entry.x or entry.col)
    local y = entry and tonumber(entry.y or entry.row)
    if x and y then
      points[#points + 1] = {
        id = tostring(id), x = x, y = y,
        name = cleanName(raw.name or raw.label or id, "KANTO"),
      }
    end
  end
  table.sort(points, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return a.id < b.id
  end)
  return points
end

local function setColor(rgb)
  local graphics = love and love.graphics
  if not graphics then return end
  graphics.setColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
end

local function fillRect(x, y, w, h, rgb)
  local graphics = love and love.graphics
  if not graphics then return end
  setColor(rgb)
  graphics.rectangle("fill", x, y, w, h)
end

local function box(x, y, w, h, paper, ink)
  fillRect(x, y, w, h, ink or COLORS.ink)
  fillRect(x + 2, y + 2, w - 4, h - 4, paper or COLORS.paper)
end

-- Gen1Recomp's cartridge Font sheet carries black RGB with glyph coverage in
-- alpha. LÖVE's ordinary draw tint multiplies RGB, so black ink stays black no
-- matter whether setColor asks for cream, cyan or red. The shader preserves
-- only the source alpha and supplies the requested ink RGB, matching the Pack
-- renderer's proven path while keeping this screen asset-free.
local INK_SHADER_SOURCE = [[
  vec4 effect(vec4 color, Image texture, vec2 texture_coords,
      vec2 screen_coords) {
    vec4 source = Texel(texture, texture_coords);
    return vec4(color.rgb, source.a * color.a);
  }
]]

-- A graphics context owns its Shader. Keying the one-shot attempt by the
-- love.graphics table avoids reusing a stale object if a test, hot reload or
-- context recovery replaces that table.
local inkShaders = setmetatable({}, { __mode = "k" })

local function inkShader(graphics)
  local state = inkShaders[graphics]
  if state then return state.shader end
  state = { attempted = true, shader = nil }
  inkShaders[graphics] = state
  if type(graphics.newShader) ~= "function" then return nil end
  local ok, shader = pcall(graphics.newShader, INK_SHADER_SOURCE)
  if ok and shader then state.shader = shader end
  return state.shader
end

local function captureGraphicsState(graphics)
  local state = {}
  if type(graphics.getShader) == "function" then
    local ok, shader = pcall(graphics.getShader)
    if ok then state.hasShader, state.shader = true, shader end
  end
  if type(graphics.getColor) == "function" then
    local ok, r, g, b, a = pcall(graphics.getColor)
    if ok then state.hasColor, state.color = true, { r, g, b, a } end
  end
  return state
end

local function restoreGraphicsState(graphics, state)
  if state.hasShader and type(graphics.setShader) == "function" then
    -- If restoring the exact prior shader fails, clearing the temporary one is
    -- safer than leaking it into every later world/UI draw.
    local ok = pcall(graphics.setShader, state.shader)
    if not ok then pcall(graphics.setShader) end
  end
  if state.hasColor and type(graphics.setColor) == "function" then
    local c = state.color
    pcall(graphics.setColor, c[1], c[2], c[3], c[4])
  end
end

local function drawInk(Font, method, value, x, y, rgb, allowSystemFallback)
  local graphics = love and love.graphics
  local draw = Font and Font[method]
  if not (graphics and type(draw) == "function") then return nil end
  rgb = rgb or COLORS.ink

  -- Only use a custom shader when the previous shader can be read back. That
  -- makes restoration provable; a renderer exposing setShader but not
  -- getShader takes the safe fallback instead of losing an unknown pipeline.
  local shader = inkShader(graphics)
  if shader and type(graphics.setShader) == "function"
      and type(graphics.getShader) == "function" then
    local state = captureGraphicsState(graphics)
    local setOk = state.hasShader and state.hasColor
      and pcall(graphics.setShader, shader)
    local colorOk = setOk and pcall(graphics.setColor,
      rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
    local drawOk, result = false, nil
    if colorOk then drawOk, result = pcall(draw, value, x, y) end
    restoreGraphicsState(graphics, state)
    if drawOk then return result end
  end

  -- Shader creation/draw failures degrade to LÖVE's system font for strings.
  -- Temporarily clear an existing shader so an unrelated world pipeline cannot
  -- recolor or discard the fallback, then restore both shader and color.
  if allowSystemFallback and type(graphics.print) == "function" then
    local state = captureGraphicsState(graphics)
    if state.hasShader and type(graphics.setShader) == "function" then
      pcall(graphics.setShader)
    end
    pcall(graphics.setColor,
      rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
    local ok, result = pcall(graphics.print, tostring(value or ""), x, y)
    restoreGraphicsState(graphics, state)
    if ok then return result end
  end

  -- Minimal/headless drivers may have neither shader nor system font. The
  -- cartridge font remains the last safe path (black ink is readable on every
  -- cream card, even though a colored black-header label cannot be promised).
  local state = captureGraphicsState(graphics)
  pcall(graphics.setColor, 1, 1, 1, 1)
  local ok, result = pcall(draw, value, x, y)
  restoreGraphicsState(graphics, state)
  if ok then return result end
  return nil
end

local function printText(Font, text, x, y, color)
  return drawInk(Font, "draw", tostring(text or ""), x, y,
    color or COLORS.ink, true)
end

local function printCode(Font, code, x, y, color)
  return drawInk(Font, "drawCode", code, x, y, color or COLORS.ink, false)
end

local function wrapText(text, width, rows)
  local lines, line = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    local candidate = line == "" and word or (line .. " " .. word)
    if #glyphs(candidate) > width and line ~= "" then
      lines[#lines + 1] = line
      line = word
      if #lines >= rows then break end
    else
      line = candidate
    end
  end
  if line ~= "" and #lines < rows then lines[#lines + 1] = line end
  return lines
end

local function printWrapped(Font, text, x, y, width, rows, spacing)
  for index, line in ipairs(wrapText(text, width, rows)) do
    printText(Font, line, x, y + (index - 1) * (spacing or 8))
  end
end

local function drawIcon(graphics, id, x, y, selected)
  local accent = id == "clock" and COLORS.pink
    or id == "map" and COLORS.blue
    or id == "phone" and COLORS.green or COLORS.red
  fillRect(x, y, 16, 16, selected and accent or COLORS.paper)
  fillRect(x + 2, y + 2, 12, 12, selected and COLORS.paper or accent)
  setColor(selected and accent or COLORS.ink)
  if id == "clock" then
    if type(graphics.circle) == "function" then
      graphics.circle("line", x + 8, y + 8, 4)
    end
    if type(graphics.line) == "function" then
      graphics.line(x + 8, y + 8, x + 8, y + 5)
      graphics.line(x + 8, y + 8, x + 11, y + 8)
    end
  elseif id == "map" then
    if type(graphics.line) == "function" then
      graphics.line(x + 4, y + 4, x + 4, y + 12)
      graphics.line(x + 8, y + 3, x + 8, y + 11)
      graphics.line(x + 12, y + 4, x + 12, y + 12)
      graphics.line(x + 4, y + 4, x + 8, y + 3, x + 12, y + 4)
      graphics.line(x + 4, y + 12, x + 8, y + 11, x + 12, y + 12)
    end
  elseif id == "phone" then
    fillRect(x + 4, y + 3, 8, 3, selected and accent or COLORS.ink)
    fillRect(x + 6, y + 6, 4, 5, selected and accent or COLORS.ink)
    fillRect(x + 3, y + 10, 10, 3, selected and accent or COLORS.ink)
  else
    fillRect(x + 3, y + 5, 10, 7, selected and accent or COLORS.ink)
    fillRect(x + 5, y + 7, 4, 3, selected and COLORS.paper or accent)
    if type(graphics.line) == "function" then
      graphics.line(x + 11, y + 3, x + 13, y + 1)
    end
  end
end

local Pokegear = {}
Pokegear.__index = Pokegear
Pokegear.isOpaque = true

function Pokegear:wantsFillScale() return true end

function Pokegear.new(mod, context, game, deps)
  local self = setmetatable({}, Pokegear)
  self.mod = mod
  self.context = context
  self.game = game
  self.Font = deps.Font
  self.Theme = deps.Theme
  self.Sound = deps.Sound
  self.Music = deps.Music
  self.cards = CARD_ORDER
  -- Keep a public descriptor list for screen introspection and old consumers.
  self.items = CARD_ORDER
  self.cardIndex = 1
  self.phoneIndex = 1
  self.phoneScroll = 0
  self.phoneDetail = false
  self.radioIndex = 1
  self.radioPlaying = false
  self.radioMessage = nil
  self.closed = false
  self.screenId = POKEGEAR_SCREEN
  self.contacts = buildContacts(mod, game)
  self.stations = buildStations(game)
  local songs = game and game.data and game.data.audio
    and game.data.audio.songs
  self.capabilities = {
    map = mod and mod.ui and type(mod.ui.push) == "function",
    phone = mod and mod.save and type(mod.save.get) == "function",
    radio = type(deps.Music) == "table"
      and type(deps.Music.play) == "function"
      and type(deps.Music.restoreMap) == "function"
      and type(songs) == "table" and next(songs) ~= nil,
  }
  return self
end

function Pokegear:card()
  return self.cards[self.cardIndex]
end

function Pokegear:playPress()
  local sound = self.Sound
  if sound and type(sound.play) == "function" and self.game and self.game.data then
    pcall(sound.play, self.game.data, "Press_AB")
  end
end

function Pokegear:stopRadio()
  if not self.radioPlaying then return end
  self.radioPlaying = false
  local music = self.Music
  if music and type(music.restoreMap) == "function" and self.game then
    pcall(music.restoreMap, self.game.data)
  end
end

function Pokegear:exit()
  self:stopRadio()
end

function Pokegear:close()
  if self.closed then return end
  self.closed = true
  self:playPress()
  self:stopRadio()
  local game = self.game
  local stack = game and game.stack
  if stack and type(stack.pop) == "function" then
    local top = type(stack.top) == "function" and stack:top() or self
    if top == self then pcall(stack.pop, stack) end
  end
  if self.mod and self.mod.ui and type(self.mod.ui.push) == "function" then
    pcall(self.mod.ui.push, game, "StartMenu")
  end
end

function Pokegear:switch(delta)
  local old = self:card()
  if old and old.id == "radio" then self:stopRadio() end
  self.cardIndex = ((self.cardIndex - 1 + delta) % #self.cards) + 1
  self.phoneDetail = false
  self.radioMessage = nil
end

function Pokegear:openMap()
  if not self.capabilities.map then return false end
  local ok, result = pcall(self.mod.ui.push, self.game, "TownMap")
  return ok and result ~= false
end

function Pokegear:movePhone(delta)
  local count = #self.contacts
  if count == 0 then return end
  self.phoneIndex = math.max(1, math.min(count, self.phoneIndex + delta))
  if self.phoneIndex <= self.phoneScroll then
    self.phoneScroll = self.phoneIndex - 1
  elseif self.phoneIndex > self.phoneScroll + 4 then
    self.phoneScroll = self.phoneIndex - 4
  end
end

function Pokegear:phoneMessage()
  if not self.capabilities.phone then
    return "PHONE DATA ISN'T AVAILABLE IN THIS ENGINE SESSION."
  end
  local contact = self.contacts[self.phoneIndex]
  if not contact then
    return "NO NUMBERS STORED. BEAT A TRAINER TO ADD THEIR JOURNEY RECORD."
  end
  local rematches = enabledValue(
    setting(self.mod, self.context, "trainer_rematches", true))
  if contact.lastResult == "forfeit" then
    return "NO BACKING OUT NEXT TIME. FIND ME IN " .. contact.map .. "."
  elseif rematches and contact.wins > 0 then
    return "I'M TRAINING IN " .. contact.map .. ". COME FIND ME FOR A REMATCH!"
  elseif not rematches then
    return "REMATCHES ARE OFF IN SCOTT'S TWEAKS SETTINGS."
  end
  return "OUR BATTLE RECORD IS SAVED. FIND ME IN " .. contact.map .. "."
end

function Pokegear:radioBlurb(station)
  if not station then return "NO STATION" end
  if not station.song then
    return "THIS PROGRAM ISN'T IN RED'S ACTIVE AUDIO DATA."
  end
  local mapId = cleanName(currentMap(self.game), "KANTO")
  if station.kind == "oak" then
    local party = self.game and self.game.save and self.game.save.party or {}
    local mon = type(party) == "table" and party[1] or nil
    local species = type(mon) == "table" and cleanName(mon.species, "POKéMON")
      or "POKéMON"
    return "OAK: " .. species .. " IS TRAVELING WITH YOU TODAY!"
  elseif station.kind == "dex" then
    return "TODAY'S POKéDEX REPORT COMES LIVE FROM " .. mapId .. "."
  elseif station.kind == "places" then
    return "PLACES & PEOPLE: NOW VISITING " .. mapId .. "."
  end
  return "LET'S ALL SING! NOW PLAYING A KANTO FAVORITE."
end

function Pokegear:toggleRadio()
  local station = self.stations[self.radioIndex]
  if not self.capabilities.radio then
    self.radioMessage = "RADIO AUDIO ISN'T AVAILABLE IN THIS ENGINE SESSION."
    return false
  end
  if not (station and station.song) then
    self.radioMessage = self:radioBlurb(station)
    return false
  end
  if self.radioPlaying then
    self:stopRadio()
    self.radioMessage = "RADIO OFF"
    return true
  end
  local ok, result = pcall(self.Music.play, self.game.data, station.song, true,
    { reason = "radio" })
  if ok and result ~= false then
    self.radioPlaying = true
    self.radioMessage = self:radioBlurb(station)
    return true
  end
  self.radioMessage = "THE STATION COULDN'T START."
  return false
end

function Pokegear:moveRadio(delta)
  self.radioIndex = math.max(1,
    math.min(#self.stations, self.radioIndex + delta))
  self.radioMessage = nil
  if self.radioPlaying then
    self:stopRadio()
    self:toggleRadio()
  end
end

function Pokegear:update(_dt)
  local input = self.game and self.game.input
  if not (input and type(input.wasPressed) == "function") then return end

  if self.phoneDetail and input:wasPressed("b") then
    self.phoneDetail = false
    self:playPress()
    return
  end
  if input:wasPressed("b") then
    self:close()
    return
  elseif input:wasPressed("left") then
    self:switch(-1)
    return
  elseif input:wasPressed("right") then
    self:switch(1)
    return
  end

  local card = self:card()
  if not card then return end
  if card.id == "map" then
    if input:wasPressed("a") then
      self:playPress()
      if not self:openMap() then self.mapMessage = "TOWN MAP IS UNAVAILABLE." end
    end
  elseif card.id == "phone" then
    if input:wasPressed("up") then
      self:movePhone(-1)
    elseif input:wasPressed("down") then
      self:movePhone(1)
    elseif input:wasPressed("a") then
      self:playPress()
      self.phoneDetail = self.contacts[self.phoneIndex] ~= nil
    end
  elseif card.id == "radio" then
    if input:wasPressed("up") then
      self:moveRadio(1)
    elseif input:wasPressed("down") then
      self:moveRadio(-1)
    elseif input:wasPressed("a") then
      self:playPress()
      self:toggleRadio()
    end
  elseif input:wasPressed("a") then
    -- The clock is already live; A simply acknowledges the original
    -- "press a button" behavior without changing save state.
    self:playPress()
    self.clockAcknowledged = true
  end
end

function Pokegear:drawStrip()
  local graphics = love and love.graphics
  if not graphics then return end
  fillRect(0, 0, SCREEN_W, 23, COLORS.ground)
  for index, card in ipairs(self.cards) do
    drawIcon(graphics, card.id, (index - 1) * 16, 0,
      index == self.cardIndex)
  end
  local card = self:card()
  printText(self.Font, card and card.label or "POKéGEAR", 76, 4, COLORS.paper)
  printText(self.Font, "L/R", 132, 4, COLORS.cyan)
  local arrowX = (self.cardIndex - 1) * 16 + 5
  setColor(COLORS.paper)
  if type(graphics.polygon) == "function" then
    graphics.polygon("fill", arrowX, 17, arrowX + 6, 17, arrowX + 3, 22)
  else
    fillRect(arrowX + 2, 17, 3, 5, COLORS.paper)
  end
end

function Pokegear:drawPrompt(text)
  box(0, 96, 160, 48, COLORS.paper, COLORS.ink)
  printWrapped(self.Font, text, 8, 106, 18, 3, 10)
end

function Pokegear:drawClock()
  local time, day = clockParts(self.mod, self.game)
  box(20, 34, 120, 54, COLORS.paper, COLORS.blue)
  printText(self.Font, day, 42, 46)
  printText(self.Font, time, 50, 66, COLORS.red)
  self:drawPrompt(self.clockAcknowledged
    and "CLOCK CHECKED. L/R SWITCHES CARDS; B RETURNS TO START."
    or "A CHECKS THE CLOCK. L/R SWITCHES CARDS; B RETURNS TO START.")
end

function Pokegear:drawMap()
  local graphics = love and love.graphics
  box(5, 25, 150, 68, COLORS.paper, COLORS.blue)
  fillRect(10, 30, 140, 58, COLORS.cyan)
  local points = collectMapPoints(self.game)
  local current = currentMap(self.game)
  if #points > 0 then
    local minX, maxX, minY, maxY = points[1].x, points[1].x,
      points[1].y, points[1].y
    for _, point in ipairs(points) do
      minX, maxX = math.min(minX, point.x), math.max(maxX, point.x)
      minY, maxY = math.min(minY, point.y), math.max(maxY, point.y)
    end
    local spanX, spanY = math.max(1, maxX - minX), math.max(1, maxY - minY)
    for _, point in ipairs(points) do
      local x = 15 + math.floor((point.x - minX) / spanX * 128)
      local y = 34 + math.floor((point.y - minY) / spanY * 48)
      fillRect(x, y, point.id == current and 5 or 3,
        point.id == current and 5 or 3,
        point.id == current and COLORS.red or COLORS.green)
    end
  else
    -- A small abstract Kanto silhouette keeps the card readable when an old
    -- cache lacks field.townMap; A still opens TownMap's own list fallback.
    fillRect(30, 45, 72, 28, COLORS.green)
    fillRect(82, 38, 30, 20, COLORS.green)
    fillRect(52, 68, 24, 14, COLORS.green)
  end
  box(74, 24, 81, 18, COLORS.paper, COLORS.ink)
  printText(self.Font, limit(cleanName(current, "KANTO"), 9), 82, 29)
  local prompt = self.mapMessage or (self.capabilities.map
    and "A OPENS RED'S FULL KANTO TOWN MAP. L/R SWITCHES CARDS."
    or "RED'S TOWN MAP ISN'T AVAILABLE IN THIS ENGINE SESSION.")
  self:drawPrompt(prompt)
  if graphics then setColor(COLORS.paper) end
end

function Pokegear:drawPhone()
  if self.phoneDetail then
    local contact = self.contacts[self.phoneIndex]
    box(4, 26, 152, 67, COLORS.paper, COLORS.green)
    printText(self.Font, "CALLING " .. limit(contact and contact.name, 10), 12, 34)
    if contact then
      printText(self.Font, "AREA " .. limit(contact.map, 12), 12, 50)
      printText(self.Font, ("BATTLES %d  WINS %d"):format(
        contact.battles, contact.wins), 12, 66)
      printText(self.Font, ("REMATCHES %d"):format(contact.rematches), 12, 78)
    end
    self:drawPrompt(self:phoneMessage() .. " B HANGS UP.")
    return
  end

  box(4, 25, 152, 68, COLORS.paper, COLORS.green)
  printText(self.Font, "PHONE", 10, 29, COLORS.green)
  -- Four bars, matching the visual purpose of Crystal's signal indicator.
  for index = 1, 4 do
    fillRect(133 + (index - 1) * 4, 38 - index * 3, 3, index * 3,
      self.capabilities.phone and COLORS.green or COLORS.grey)
  end
  if #self.contacts == 0 then
    printText(self.Font, "----------", 24, 54)
    printText(self.Font, "NO NUMBERS", 24, 70, COLORS.grey)
  else
    for row = 1, 4 do
      local index = self.phoneScroll + row
      local contact = self.contacts[index]
      if contact then
        local y = 37 + (row - 1) * 13
        if index == self.phoneIndex then
          printCode(self.Font, self.Theme and self.Theme.cursor or 0xED, 10, y)
        end
        printText(self.Font, limit(contact.name, 10), 20, y)
        printText(self.Font, tostring(contact.wins), 135, y)
      end
    end
  end
  local prompt = self.capabilities.phone
    and "UP/DOWN SELECTS A TRAINER. A CALLS FOR THEIR REMATCH UPDATE."
    or "PHONE DATA ISN'T AVAILABLE IN THIS ENGINE SESSION."
  self:drawPrompt(prompt)
end

function Pokegear:drawRadio()
  local station = self.stations[self.radioIndex]
  box(5, 25, 150, 68, COLORS.paper, COLORS.red)
  printText(self.Font, "RADIO", 10, 29, COLORS.red)
  -- Tuner rail and a knob at one of the four station stops.
  fillRect(18, 47, 124, 3, COLORS.ink)
  for index = 1, #self.stations do
    local x = 18 + math.floor((index - 1) * 124 / (#self.stations - 1))
    fillRect(x, 43, 2, 11, COLORS.ink)
  end
  local knobX = 18 + math.floor((self.radioIndex - 1) * 124
    / (#self.stations - 1))
  fillRect(knobX - 3, 40, 8, 17, COLORS.pink)
  printText(self.Font, station and station.frequency or "--.-", 13, 62)
  printText(self.Font, limit(station and station.name or "NO STATION", 17),
    13, 76)
  printText(self.Font, self.radioPlaying and "ON AIR" or "RADIO OFF", 106, 62,
    self.radioPlaying and COLORS.green or COLORS.grey)
  local prompt = self.radioMessage or (self.capabilities.radio
    and "UP/DOWN TUNES. A PLAYS OR STOPS MUSIC. L/R CHANGES CARDS."
    or "RADIO AUDIO ISN'T AVAILABLE IN THIS ENGINE SESSION.")
  self:drawPrompt(prompt)
end

function Pokegear:draw()
  local graphics = love and love.graphics
  if not graphics then return end
  fillRect(0, 0, SCREEN_W, SCREEN_H, COLORS.ground)
  self:drawStrip()
  local card = self:card()
  if card and card.id == "map" then
    self:drawMap()
  elseif card and card.id == "phone" then
    self:drawPhone()
  elseif card and card.id == "radio" then
    self:drawRadio()
  else
    self:drawClock()
  end
  graphics.setColor(1, 1, 1, 1)
end

local function decorateStartItems(items, game, mod)
  local out = {}
  local packAt
  local hasPokegear = false

  for _, original in ipairs(items or {}) do
    local item = copyItem(original)
    if isPackRow(item) and not packAt then
      item.label = "PACK"
      item.desc = item.desc or { "Items and", "pockets" }
      packAt = #out + 1
    end
    if type(item) == "table" and item.id == POKEGEAR_ITEM_ID then
      hasPokegear = true
    end
    out[#out + 1] = item
  end

  if not hasPokegear then
    local row = {
      id = POKEGEAR_ITEM_ID,
      label = "POKéGEAR",
      desc = { "Clock Map", "Phone Radio" },
      onSelect = function()
        return mod.ui.push(game, POKEGEAR_SCREEN)
      end,
    }
    table.insert(out, packAt and (packAt + 1) or (#out + 1), row)
  end
  return out
end

return function(mod, context)
  assert(type(mod) == "table", "Pokegear needs the mod API")
  context = type(context) == "table" and context or {}
  assert(mod.content and mod.content.screens,
    "Pokegear needs the screen registry")
  assert(mod.hooks and type(mod.hooks.wrap) == "function",
    "Pokegear needs UI hooks")

  local deps = {
    Font = tryRequire("src.render.Font"),
    Theme = tryRequire("src.ui.Theme"),
    Sound = tryRequire("src.core.Sound"),
    Music = tryRequire("src.core.Music"),
  }

  local screens = mod.content.screens
  local factory = {
    new = function(game) return Pokegear.new(mod, context, game, deps) end,
  }
  if screens:get(POKEGEAR_SCREEN) ~= nil then
    screens:override(POKEGEAR_SCREEN, factory)
  else
    screens:register(POKEGEAR_SCREEN, factory)
  end

  -- Run outside Modern UI's Start grouping wrapper. PACK and POKeGEAR stay
  -- on the normal root menu while Modern UI retains every screen it owns.
  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" or not optionEnabled(mod, context) then return out end
    return decorateStartItems(out, game, mod)
  end, 100)

  local api = {
    apiVersion = API_VERSION,
    installed = true,
    optionKey = OPTION_KEY,
    screenIds = { pokegear = POKEGEAR_SCREEN },
    getEnabled = function() return optionEnabled(mod, context) end,
    getStatus = function(game)
      local enabled = optionEnabled(mod, context)
      local stations = buildStations(game)
      local phone = mod.save and type(mod.save.get) == "function"
      local music = deps.Music
      local songs = game and game.data and game.data.audio
        and game.data.audio.songs
      return {
        apiVersion = API_VERSION,
        installed = true,
        enabled = enabled,
        active = enabled,
        ready = true,
        optionKey = OPTION_KEY,
        style = "crystal_inspired_native_160x144",
        controller = "red_capability_adapters",
        modernUi = "coexists",
        presenter = "opaque_ui_canvas_only",
        romImport = false,
        cards = { "clock", "map", "phone", "radio" },
        capabilities = {
          clock = true,
          map = mod.ui and type(mod.ui.push) == "function" or false,
          phone = phone or false,
          radio = type(music) == "table" and type(music.play) == "function"
            and type(music.restoreMap) == "function"
            and type(songs) == "table" and next(songs) ~= nil or false,
        },
        phoneContacts = game and #buildContacts(mod, game) or 0,
        radioStations = countAvailableStations(stations),
        limitations = {
          phone = "trainer_rematch_history_not_gen2_phone_scripts",
          radio = "active_red_song_registry_not_gen2_radio_vm",
        },
        screenIds = { pokegear = POKEGEAR_SCREEN },
      }
    end,
  }
  mod.exports = type(mod.exports) == "table" and mod.exports or {}
  mod.exports.gen2Ui = api
  return api
end
