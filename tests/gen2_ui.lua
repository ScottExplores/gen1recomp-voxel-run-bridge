-- ROM-free contract test for Scott's Tweaks' Gold presentation adapter.
--
-- Run from the mod root with a Lua 5.1-compatible runtime:
--   lua tests/gen2_ui.lua
--   luajit tests/gen2_ui.lua

local checks = 0

local function check(value, label)
  checks = checks + 1
  if not value then error(label, 2) end
end

local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(
      label, tostring(expected), tostring(actual)), 2)
  end
end

local function countId(rows, id)
  local count = 0
  for _, row in ipairs(rows or {}) do
    if type(row) == "table" and row.id == id then count = count + 1 end
  end
  return count
end

local calls = {}
local function resetCalls()
  calls = {
    chrome = {}, pack = {}, gearDraws = 0, gearUpdates = 0,
    images = {}, pushes = {}, baseStartDraws = 0, baseBagDraws = 0,
    spriteDraws = {}, paletteUses = {}, quads = {},
  }
end
resetCalls()

local function image(name, width, height)
  local result = {
    name = name, width = width, height = height, releases = 0,
  }
  function result:setFilter(min, mag)
    self.filter = { min, mag }
  end
  function result:release() self.releases = self.releases + 1 end
  function result:getDimensions() return self.width, self.height end
  return result
end

local graphics = {}
function graphics.newImage(data)
  local result = image(data.name, data.width, data.height)
  calls.images[#calls.images + 1] = result
  return result
end
function graphics.newQuad(x, y, width, height, imageWidth, imageHeight)
  local result = {
    x = x, y = y, width = width, height = height,
    imageWidth = imageWidth, imageHeight = imageHeight, releases = 0,
  }
  function result:release() self.releases = self.releases + 1 end
  calls.quads[#calls.quads + 1] = result
  return result
end
function graphics.draw(gpu, quad, x, y, rotation, sx, sy)
  calls.spriteDraws[#calls.spriteDraws + 1] = {
    image = gpu, quad = quad, x = x, y = y,
    rotation = rotation, sx = sx, sy = sy,
  }
end
function graphics.push() end
function graphics.pop() end
function graphics.setColor() end
function graphics.rectangle() end

love = { graphics = graphics }

local Chrome = { SCREEN_H = 18 }
local function chrome(name, ...)
  calls.chrome[#calls.chrome + 1] = { name = name, args = { ... } }
end
function Chrome.box(...) chrome("box", ...) end
function Chrome.print(...) chrome("print", ...) end
function Chrome.cursor(...) chrome("cursor", ...) end
function Chrome.clear(...) chrome("clear", ...) end
function Chrome.wrap(text)
  local out = {}
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  return out
end

local Font = {}
function Font.width(text) return #tostring(text) * 8 end

local GbcPalette = {}
function GbcPalette.with(colors, body)
  calls.paletteUses[#calls.paletteUses + 1] = colors
  local previous = calls.activePalette
  calls.activePalette = colors
  local result = body()
  calls.activePalette = previous
  return result
end

local Palettes = {}
function Palettes.clockDaytime(hour)
  hour = tonumber(hour) or 12
  if hour < 10 then return "MORN" end
  if hour < 18 then return "DAY" end
  return "NITE"
end
function Palettes.spritePalette(data, daytime, def)
  local set = data and data.objects and data.objects[daytime]
  return set and set[(tonumber(def and def.paletteId) or 0) + 1]
end

local PackGfx = {}
function PackGfx.new(menuGfx)
  local result = {
    gfx = menuGfx.pack,
    images = {},
    quads = {},
  }
  function result:draw(pocket)
    calls.pack[#calls.pack + 1] = {
      pocket = pocket,
      menu = self.images[self.gfx.menu],
      pack = self.images[self.gfx.pack],
    }
  end
  return result
end

local Pokegear = {}
function Pokegear.new(game, opts)
  local result = {
    game = game,
    opts = opts,
    sheet = { quads = {} },
    cards = { { id = "clock" }, { id = "map" } },
    cardIndex = 1,
  }
  function result:loadArrowSheet()
    self.arrow = { quads = {} }
  end
  function result:update(dt)
    calls.gearUpdates = calls.gearUpdates + 1
    self.lastDt = dt
    self.iconTimer = ((self.iconTimer or 0) + 1) % 32
  end
  function result:draw()
    calls.gearDraws = calls.gearDraws + 1
  end
  calls.lastGear = result
  return result
end

local BuiltinStart = {}
function BuiltinStart.new()
  error("fixture expected preserved StartMenu registry factory")
end

local BuiltinBag = {}
function BuiltinBag.new()
  error("fixture expected preserved BagMenu registry factory")
end

package.preload["src.ui.gen2.Chrome"] = function() return Chrome end
package.preload["src.ui.gen2.PackGfx"] = function() return PackGfx end
package.preload["src.ui.gen2.Pokegear"] = function() return Pokegear end
package.preload["src.render.Font"] = function() return Font end
package.preload["src.render.GbcPalette"] = function() return GbcPalette end
package.preload["src.world.gen2.Palettes"] = function() return Palettes end
package.preload["src.ui.StartMenu"] = function() return BuiltinStart end
package.preload["src.ui.BagMenu"] = function() return BuiltinBag end
local EngineScreens = {}
package.preload["src.ui.Screens"] = function() return EngineScreens end

local scriptSource = debug.getinfo(1, "S").source
local scriptPath = scriptSource:sub(1, 1) == "@" and scriptSource:sub(2)
  or "tests/gen2_ui.lua"
local testDirectory = scriptPath:match("^(.*[\\/])") or ""
local modRoot = testDirectory:gsub("tests[\\/]$", "")
local installer = assert(loadfile(modRoot .. "modules/gen2_ui.lua"))()

local function registry(initial)
  local result = { values = initial or {}, overrides = 0, registers = 0 }
  function result:get(id) return self.values[id] end
  function result:override(id, value)
    self.values[id] = value
    self.overrides = self.overrides + 1
    return value
  end
  function result:register(id, value)
    assert(self.values[id] == nil, "duplicate " .. id)
    self.values[id] = value
    self.registers = self.registers + 1
    return value
  end
  return result
end

local function newStack()
  local stack = { states = {} }
  function stack:push(value)
    self.states[#self.states + 1] = value
    return value
  end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function newInput()
  local input = { pressed = {} }
  function input:press(key) self.pressed[key] = true end
  function input:wasPressed(key)
    local hit = self.pressed[key] == true
    self.pressed[key] = nil
    return hit
  end
  return input
end

local function assetController(tag, config)
  config = config or {}
  local controller = { loads = 0, releases = 0, tag = tag }
  local imageData = {
    packMenu = { name = tag .. ":packMenu", width = 128, height = 48 },
    pack = { name = tag .. ":pack", width = 40, height = 96 },
    gear = { name = tag .. ":gear", width = 128, height = 48 },
    sprites = { name = tag .. ":sprites", width = 16, height = 40 },
  }
  if not config.noChris then
    imageData.chris = { name = tag .. ":chris", width = 16, height = 96 }
  end
  local markerColors = {
    MORN = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 10, 11, 12 } },
    DAY = { { 13, 14, 15 }, { 16, 17, 18 }, { 19, 20, 21 }, { 22, 23, 24 } },
    NITE = { { 25, 26, 27 }, { 28, 29, 30 }, { 31, 32, 33 }, { 34, 35, 36 } },
    DARK = { { 37, 38, 39 }, { 40, 41, 42 }, { 43, 44, 45 }, { 46, 47, 48 } },
  }
  local payload = {
    menuGfx = {
      pack = {
        menu = "packMenu", pack = "pack",
        menuImageDataKey = "packMenu", packImageDataKey = "pack",
      },
      pokegear = {
        tiles = "gear", sprites = "sprites",
        tilesWide = 16, spritesWide = 2,
      },
    },
    imageData = imageData,
    sprites = not config.noChris and {
      SPRITE_CHRIS = {
        id = "SPRITE_CHRIS", image = "chris", frames = 6,
        walker = true, palette = "PAL_OW_RED", paletteId = 0,
      },
    } or nil,
    palettes = not config.noChris and {
      objects = {
        MORN = { markerColors.MORN }, DAY = { markerColors.DAY },
        NITE = { markerColors.NITE }, DARK = { markerColors.DARK },
      },
    } or nil,
    landmarks = {
      landmarks = {
        PALLET_TOWN = {
          id = "PALLET_TOWN", index = 0x2e,
          x = 10, y = 20, name = "PALLET TOWN",
        },
        ROUTE_1 = {
          id = "ROUTE_1", index = 0x2f,
          x = 12, y = 18, name = "ROUTE 1",
        },
        CERULEAN_CITY = {
          id = "CERULEAN_CITY", index = 0x35,
          x = 40, y = 28, name = "CERULEAN CITY",
        },
      },
    },
  }
  function payload:release() self.released = (self.released or 0) + 1 end
  function controller:load()
    self.loads = self.loads + 1
    if config.fail then return nil, config.fail end
    return payload
  end
  function controller:status()
    return {
      state = config.fail and "missing" or (self.loads > 0 and "ready" or "idle"),
      ready = not config.fail and self.loads > 0,
      reason = config.fail,
    }
  end
  function controller:release()
    self.releases = self.releases + 1
    payload:release()
  end
  controller.payload = payload
  controller.markerColors = markerColors
  return controller
end

local function makeBaseStart(game)
  local update = function(self) self.baseUpdates = (self.baseUpdates or 0) + 1 end
  local draw = function(self)
    calls.baseStartDraws = calls.baseStartDraws + 1
    return "base-start", self
  end
  return {
    game = game,
    items = game.startItems or {},
    index = game.startIndex or 1,
    scroll = 0,
    maxVisible = 8,
    update = update,
    draw = draw,
    expectedUpdate = update,
    expectedDraw = draw,
  }
end

local function makeBaseBag(game)
  local update = function(self) self.baseUpdates = (self.baseUpdates or 0) + 1 end
  local choose = function(item) return "choose", item and item.value end
  local draw = function(self)
    calls.baseBagDraws = calls.baseBagDraws + 1
    return "base-bag", self
  end
  return {
    game = game,
    title = "< ITEMS >",
    items = {
      { value = "POTION", label = "POTION", right = "x2" },
      { value = "ESCAPE_ROPE", label = "ESCAPE ROPE", right = "x1" },
    },
    index = 1,
    scroll = 0,
    rows = 7,
    update = update,
    onChoose = choose,
    draw = draw,
    expectedUpdate = update,
    expectedChoose = choose,
    expectedDraw = draw,
    _scottsTweaksPocketLayer = {
      owner = "voxel_run_bridge",
      state = { pocket = 1, cursor = {} },
    },
  }
end

local function fixture(config)
  config = config or {}
  resetCalls()
  if not config.keepStable then
    rawset(EngineScreens, "_scottsTweaksGen2UiDispatcher", nil)
  end
  local values = { gen2_menus = config.enabled == true }
  local controller = config.controller or assetController(config.tag or "one",
    { fail = config.fail, noChris = config.noChris })
  local game = {
    save = { player = { name = "RED" }, party = {} },
    data = {
      items = {
        POTION = { description = "RESTORES HP<NEXT>BY 20." },
        ESCAPE_ROPE = { description = "ESCAPE FROM CAVES." },
        TM01 = {
          description = "RED ITEM FALLBACK.",
          machine = { move = "MEGA_PUNCH" },
        },
      },
      moves = {
        MEGA_PUNCH = {
          name = "MEGA PUNCH", description = "A POWERFUL PUNCH.",
        },
      },
      field = {
        townMap = { locations = {
          PALLET_TOWN = { name = "PALLET TOWN", x = 1, y = 1 },
          CERULEAN_POKECENTER = { name = "CERULEAN CITY", x = 4, y = 3 },
        } },
      },
      maps = {
        PALLET_TOWN = { label = "PalletTown" },
        CERULEAN_POKECENTER = { label = "CeruleanPokecenter" },
      },
    },
    input = newInput(),
    stack = newStack(),
    overworld = { map = { id = "PALLET_TOWN" } },
  }
  local screens = config.screens or registry({
    StartMenu = { new = function(received) return makeBaseStart(received) end },
    BagMenu = { new = function(received) return makeBaseBag(received) end },
  })
  local hooks = { values = {}, priorities = {} }
  function hooks:wrap(name, callback, priority)
    self.values[name] = self.values[name] or {}
    self.values[name][#self.values[name] + 1] = callback
    self.priorities[name] = priority
  end
  function hooks:call(name, base, ...)
    local chain = base
    for _, wrapper in ipairs(self.values[name] or {}) do
      local nextFn = chain
      chain = function(...) return wrapper(nextFn, ...) end
    end
    return chain(...)
  end
  local mod = {
    id = "voxel_run_bridge",
    content = { screens = screens },
    hooks = hooks,
    exports = {},
    ui = {},
    log = { warn = function() end },
  }
  function mod.ui.push(receivedGame, id)
    calls.pushes[#calls.pushes + 1] = id
    local factory = screens:get(id)
    local screen = factory and factory.new(receivedGame)
    if screen then receivedGame.stack:push(screen) end
    return screen
  end
  local context = {
    gen2Assets = controller,
    graphics = graphics,
    clock = function() return { hour = 9, minute = 41, weekday = 1 } end,
    settings = {},
  }
  function context.settings:get(key) return values[key] end
  local api = installer(mod, context)
  return {
    game = game, screens = screens, hooks = hooks, mod = mod,
    context = context, values = values, controller = controller, api = api,
  }
end

local function invokeStartHook(ctx, rows)
  return ctx.hooks:call("ui.start_menu.items",
    function(game, items)
      eq(game, ctx.game, "start hook preserves game")
      eq(items, rows, "start hook preserves incoming rows for downstream")
      return items
    end, ctx.game, rows)
end

-- OFF is a strict pass-through.  The adapter exists, but does not load the ROM,
-- add a row, or change either native screen's controller behavior.
local off = fixture({ enabled = false, tag = "off" })
local stock = {
  { id = "pokedex", label = "POKéDEX", onSelect = function() end },
  { id = "pokemon", label = "POKéMON", onSelect = function() end },
  { id = "item", label = "ITEM", onSelect = function() end },
  { id = "battle_art", label = "BATTLE ART", onSelect = function() end },
  { id = "scotts_tweaks.open", label = "SCOTT'S TWEAKS", onSelect = function() end },
  { id = "sprites", label = "SPRITES & TRAINERS", onSelect = function() end },
  { id = "mods", label = "MODS", onSelect = function() end },
  { id = "quit", label = "QUIT", onSelect = function() end },
}
local offRows = invokeStartHook(off, stock)
eq(offRows, stock, "option-off keeps exact start row table")
eq(off.controller.loads, 0, "option-off performs no Gold ROM work")
eq(off.hooks.values["render.compose"], nil, "no render.compose presenter")
eq(off.hooks.values["render.hud"], nil, "no render.hud presenter")

off.game.startItems = stock
local offStart = off.screens:get("StartMenu").new(off.game)
eq(offStart.update, offStart.expectedUpdate, "Start update identity untouched")
eq(offStart.draw, offStart.expectedDraw,
  "option-off Start is the exact prior/Modern-compatible draw")
eq(rawget(offStart, "_scottsTweaksGoldStartDraw"), nil,
  "option-off Start has no Gold ownership marker")
local offA, offB = offStart:draw()
eq(offA, "base-start", "option-off Start uses Red draw return")
eq(offB, offStart, "option-off Start preserves second draw return")
local offBag = off.screens:get("BagMenu").new(off.game)
eq(offBag.update, offBag.expectedUpdate, "Bag update identity untouched")
eq(offBag.onChoose, offBag.expectedChoose, "Bag choose callback identity untouched")
eq(offBag.draw, offBag.expectedDraw,
  "option-off Bag is the exact prior/Modern-compatible draw")
eq(rawget(offBag, "_scottsTweaksGoldPackDraw"), nil,
  "option-off Bag has no Gold ownership marker")
eq(offBag:draw(), "base-bag", "option-off Bag uses Red draw")

-- ON preserves every hook-produced row/action and inserts exactly one Pokegear
-- before MODS.  It copies only the sequence, retaining every descriptor.
local on = fixture({ enabled = true, tag = "gold" })
local rows = invokeStartHook(on, stock)
check(rows ~= stock, "option-on copies the row sequence before insertion")
eq(#stock, 8, "input row sequence is not mutated")
eq(#rows, 9, "Pokegear is the only added row")
eq(countId(rows, "scotts_tweaks.pokegear"), 1, "Pokegear row de-duplicates")
eq(rows[1], stock[1], "Pokedex descriptor identity preserved")
eq(rows[2], stock[2], "Pokemon descriptor identity preserved")
eq(rows[3], stock[3], "ITEM callback descriptor identity preserved")
eq(rows[4].label, "POKéGEAR", "Pokegear follows ITEM in Gold order")
eq(rows[5], stock[4], "Battle Art descriptor identity preserved")
eq(rows[6], stock[5], "Scott's Tweaks descriptor identity preserved")
eq(rows[7], stock[6], "sprite category descriptor identity preserved")
eq(rows[8], stock[7], "MODS descriptor identity preserved")
eq(rows[9], stock[8], "QUIT descriptor identity preserved")
eq(on.hooks.priorities["ui.start_menu.items"], 100,
  "Pokegear root insertion runs after Modern UI priority 90")
eq(on.controller.loads, 1, "opening enabled Start loads Gold payload once")
eq(#calls.images, 5,
  "four UI sheets plus authentic Chris become GPU Images")
for _, gpu in ipairs(calls.images) do
  eq(gpu.filter[1], "nearest", gpu.name .. " nearest minification")
  eq(gpu.filter[2], "nearest", gpu.name .. " nearest magnification")
end

on.game.startItems = rows
on.game.startIndex = 3
local start = on.screens:get("StartMenu").new(on.game)
check(type(rawget(start, "_scottsTweaksGoldStartDraw")) == "table",
  "Start has an instance draw marker for Modern UI fail-open")
eq(start.update, start.expectedUpdate, "Gold Start still owns native Red update")
start:draw()
eq(calls.baseStartDraws, 0, "Gold Start replaces presentation only")
check(#calls.chrome > 0, "Gold Start uses Gen 2 Chrome")
local drewPackLabel = false
for _, call in ipairs(calls.chrome) do
  if call.name == "print" and call.args[1] == "PACK" then drewPackLabel = true end
end
check(drewPackLabel, "Gold Start presents native ITEM callback as PACK")
eq(rows[3].label, "ITEM", "PACK presentation does not mutate native row")
eq(on.controller.loads, 1, "draw reuses loaded payload")

-- Released Start providers use ITEM, ITEMS, or PACK for the same native bag
-- callback.  Every spelling keeps its descriptor identity, presents as PACK,
-- and receives Pokegear immediately after it.
for _, nativeLabel in ipairs({ "ITEMS", "PACK" }) do
  local descriptor = {
    id = nativeLabel:lower(),
    label = nativeLabel,
    onSelect = function() return nativeLabel end,
  }
  local aliasRows = invokeStartHook(on, {
    descriptor,
    { id = "mods", label = "MODS", onSelect = function() end },
  })
  eq(aliasRows[1], descriptor,
    nativeLabel .. " descriptor identity remains native")
  eq(aliasRows[2].label, "POKéGEAR",
    "Pokegear follows native " .. nativeLabel)
  on.game.startItems = aliasRows
  on.game.startIndex = 1
  local aliasStart = on.screens:get("StartMenu").new(on.game)
  local beforeAliasDraw = #calls.chrome
  aliasStart:draw()
  local renderedPack = false
  for index = beforeAliasDraw + 1, #calls.chrome do
    local call = calls.chrome[index]
    if call.name == "print" and call.args[1] == "PACK" then
      renderedPack = true
      break
    end
  end
  check(renderedPack, nativeLabel .. " is rendered as PACK")
  eq(aliasRows[1].label, nativeLabel,
    nativeLabel .. " label is not mutated")
end

local bag = on.screens:get("BagMenu").new(on.game)
check(type(rawget(bag, "_scottsTweaksGoldPackDraw")) == "table",
  "Bag has an instance draw marker for Modern UI fail-open")
eq(rawget(bag, "__pocketIndex"), nil,
  "Bag does not impersonate Modern UI's Useful Bag contract")
eq(bag.update, bag.expectedUpdate, "Gold Pack keeps Red bag update")
eq(bag.onChoose, bag.expectedChoose, "Gold Pack keeps Red item callback")
bag:draw()
eq(calls.baseBagDraws, 0, "Gold Pack replaces presentation only")
eq(calls.pack[#calls.pack].pocket, "ITEM", "Items pocket maps to Gold ITEM")
eq(calls.pack[#calls.pack].menu.name, "gold:packMenu",
  "PackGfx receives in-memory menu Image")
eq(calls.pack[#calls.pack].pack.name, "gold:pack",
  "PackGfx receives in-memory pack Image")
bag._scottsTweaksPocketLayer.state.pocket = 2
bag:draw()
eq(calls.pack[#calls.pack].pocket, "BALL", "Balls pocket maps to Gold BALL")
bag._scottsTweaksPocketLayer.state.pocket = 3
bag:draw()
eq(calls.pack[#calls.pack].pocket, "KEY_ITEM",
  "third pocket maps to Gold KEY_ITEM")
bag._scottsTweaksPocketLayer.state.pocket = 4
bag:draw()
eq(calls.pack[#calls.pack].pocket, "TM_HM",
  "fourth pocket maps to Gold TM_HM")
local originalBagItems = bag.items
bag.items = { { value = "TM01", label = "TM01" } }
bag.index = 1
local chromeBeforeTm = #calls.chrome
bag:draw()
local drewMoveDescription, drewItemFallback = false, false
for index = chromeBeforeTm + 1, #calls.chrome do
  local call = calls.chrome[index]
  if call.name == "print" and call.args[1] == "A POWERFUL PUNCH." then
    drewMoveDescription = true
  elseif call.name == "print" and call.args[1] == "RED ITEM FALLBACK." then
    drewItemFallback = true
  end
end
check(drewMoveDescription,
  "Gold TM/HM bottom box uses the taught move description")
eq(drewItemFallback, false,
  "Gold TM/HM bottom box does not prefer Red's item description")
bag.items = originalBagItems

-- The custom screen is not a Menu/ListMenu/OptionRows model.  Its engine
-- Pokegear presenter is private, receives only CLOCK+MAP unlock state, and its
-- ROM images are injected into instance-local TileSheets.
local gearRow = rows[4]
on.game.overworld.map.id = "CERULEAN_POKECENTER"
gearRow.onSelect()
local gear = on.game.stack:top()
eq(gear.screenId, "ScottsGoldGear", "custom Pokegear screen id")
eq(rawget(gear, "items"), nil, "Pokegear is not a generic Menu model")
eq(rawget(gear, "rows"), nil, "Pokegear is not an OptionRows model")
eq(getmetatable(gear).isOpaque, true, "custom Pokegear is an opaque boundary")
gear:draw()
eq(calls.gearDraws, 1, "custom screen delegates ordinary uiCanvas draw")
eq(calls.lastGear.sheet.loaded.name, "gold:gear",
  "Pokegear TileSheet receives in-memory gear Image")
eq(calls.lastGear.arrow.loaded.name, "gold:sprites",
  "Pokegear arrow TileSheet receives in-memory sprite Image")
eq(calls.lastGear.arrow.paletteFor(), on.controller.markerColors.MORN,
  "mode/map cursor uses exact MORN PAL_OW_RED")
eq(calls.lastGear.opts.save.pokegearFlags.map, true, "Kanto map card unlocked")
eq(calls.lastGear.opts.save.pokegearFlags.phone, nil, "Phone card stays absent")
eq(calls.lastGear.opts.save.pokegearFlags.radio, nil, "Radio card stays absent")
eq(calls.lastGear.opts.currentLandmark, "CERULEAN_CITY",
  "Red town-map location resolves an indoor map to its Gold landmark")
eq(calls.lastGear.opts.sprites.SPRITE_CHRIS.palette, "PAL_OW_RED",
  "Pokegear receives exact imported Chris metadata")
eq(calls.lastGear.opts.palettes.objects.MORN[1],
  on.controller.markerColors.MORN,
  "Pokegear receives imported time-of-day OBJ palettes")
eq(calls.lastGear._scottsTweaksPlayerMarker, "pokemon_gold_sprite_chris",
  "Pokegear identifies the authentic Gold Chris marker")

calls.lastGear.iconTimer = 0
eq(calls.lastGear:drawPlayerIcon(40, 30), true,
  "authentic marker suppresses the generated-square fallback")
local stand = calls.spriteDraws[#calls.spriteDraws]
eq(stand.image.name, "gold:chris", "marker draws the imported Chris Image")
eq(stand.quad.y, 0, "RED_WALK first beat uses standing-down frame")
eq(stand.x, 32, "standing marker is centered on landmark X")
eq(stand.y, 22, "standing marker is centered on landmark Y")
eq(calls.paletteUses[#calls.paletteUses], on.controller.markerColors.MORN,
  "morning beat uses exact MORN PAL_OW_RED through palette shader")
eq(calls.activePalette, nil,
  "marker draw restores the prior palette-shader state")

calls.lastGear.iconTimer = 8
calls.lastGear:drawPlayerIcon(40, 30)
local walk = calls.spriteDraws[#calls.spriteDraws]
eq(walk.quad.y, 48, "RED_WALK second beat uses down-walk frame")
eq(walk.sx, nil, "first walking beat is not mirrored")

calls.lastGear.iconTimer = 16
calls.lastGear:drawPlayerIcon(40, 30)
eq(calls.spriteDraws[#calls.spriteDraws].quad.y, 0,
  "RED_WALK third beat returns to standing-down")

calls.lastGear.iconTimer = 24
calls.lastGear:drawPlayerIcon(40, 30)
local flipped = calls.spriteDraws[#calls.spriteDraws]
eq(flipped.quad.y, 48, "RED_WALK fourth beat uses down-walk frame")
eq(flipped.x, 48, "mirrored walk shifts by one frame width")
eq(flipped.sx, -1, "RED_WALK fourth beat flips horizontally")

on.game.world = { daytime = "DARK" }
calls.lastGear:drawPlayerIcon(40, 30)
eq(calls.paletteUses[#calls.paletteUses], on.controller.markerColors.DARK,
  "world DARK override uses exact DARK PAL_OW_RED")
eq(calls.lastGear.arrow.paletteFor(), on.controller.markerColors.DARK,
  "mode/map cursor follows exact DARK PAL_OW_RED live")
on.game.world.daytime = "nite"
calls.lastGear:drawPlayerIcon(40, 30)
eq(calls.paletteUses[#calls.paletteUses], on.controller.markerColors.NITE,
  "lowercase world daytime normalizes to exact NITE PAL_OW_RED")
on.game.world = nil
on.game.overworld.map.id = "CUSTOM_INTERIOR"
gear:draw()
eq(calls.lastGear.currentLandmark, "CERULEAN_CITY",
  "unmapped interior holds the last real landmark instead of Pallet")
gear:update(0.25)
eq(calls.gearUpdates, 1, "Pokegear controller receives input update")
eq(calls.lastGear.lastDt, 0.25, "Pokegear update delta preserved")
calls.lastGear.opts.onClose()
eq(on.game.stack:top().screenId, nil,
  "closing Pokegear reopens native Start screen")
eq(calls.pushes[#calls.pushes], "StartMenu", "Pokegear returns through registry")

local status = on.api.getStatus()
eq(status.active, true, "status reports active after load")
eq(status.controller, "red_native_callbacks", "status names Red controller")
eq(status.modernUi, "coexists_fail_open", "status documents Modern coexistence")
eq(status.presenter, "ui_canvas_only", "status documents Thor-safe UI canvas")
eq(status.playerMarker, "pokemon_gold_sprite_chris",
  "status identifies the marker as the imported Gold sprite")
eq(status.assets.ready, true, "asset controller status exported")

-- Turning the option off is live: already decorated instances immediately use
-- their preserved Red draw rather than requiring another ZIP or restart.
on.values.gen2_menus = false
start:draw()
eq(calls.baseStartDraws, 1, "live option-off restores Red Start draw")
bag:draw()
eq(calls.baseBagDraws, 1, "live option-off restores Red Bag draw")

-- Real Loader F5 creates a fresh mod facade and content registry.  The engine
-- Screens table is the stable handoff: it retires the old GPU owner, installs
-- wrappers on the fresh facade, and refreshes already-open old-facade states.
local oldImages = {}
for index, value in ipairs(calls.images) do oldImages[index] = value end
local oldMarkerQuads = {}
for index, value in ipairs(calls.quads) do oldMarkerQuads[index] = value end
local f5 = fixture({ enabled = true, tag = "two", keepStable = true })
check(f5.screens ~= on.screens, "F5 fixture uses a fresh content facade")
eq(f5.screens.overrides, 2,
  "fresh F5 facade receives one Start and one Bag override")
eq(on.controller.releases, 1, "F5 releases prior asset controller once")
for index = 1, 5 do
  eq(oldImages[index].releases, 1,
    "F5 releases old GPU image #" .. index)
end
for index, quad in ipairs(oldMarkerQuads) do
  eq(quad.releases, 1, "F5 releases old Chris quad #" .. index)
end
start:draw()
eq(f5.controller.loads, 1, "already-open Start adopts fresh generation")
bag:draw()
eq(calls.pack[#calls.pack].menu.name, "two:packMenu",
  "already-open Bag adopts fresh PackGfx generation")
gear:draw()
eq(calls.lastGear.sheet.loaded.name, "two:gear",
  "already-open Gear adopts fresh TileSheet generation")
eq(f5.api.getStatus().generation, 2, "fresh-facade F5 generation increments")
local freshStart = f5.screens:get("StartMenu").new(f5.game)
check(type(rawget(freshStart, "_scottsTweaksGoldStartDraw")) == "table",
  "fresh facade builds a decorated Start")

f5.api.release()
eq(f5.controller.releases, 1, "public release frees current controller")
f5.api.release()
eq(f5.controller.releases, 1, "public release is idempotent")

-- Missing/unsupported Gold import is fail-open: no row and native Red drawing,
-- with the actionable engine reason reflected in status.
local missing = fixture({ enabled = true, fail = "gen2_import_api_unavailable" })
local missingRows = invokeStartHook(missing, stock)
eq(missingRows, stock, "missing Gold API keeps exact hook output")
missing.game.startItems = stock
local missingStart = missing.screens:get("StartMenu").new(missing.game)
eq(missingStart:draw(), "base-start", "missing Gold API falls back to Red draw")
eq(missingStart.draw, missingStart.expectedDraw,
  "unavailable Gold returns the exact prior/Modern-compatible Start draw")
eq(rawget(missingStart, "_scottsTweaksGoldStartDraw"), nil,
  "unavailable Gold does not claim Start draw ownership")
local missingBag = missing.screens:get("BagMenu").new(missing.game)
eq(missingBag.draw, missingBag.expectedDraw,
  "unavailable Gold returns the exact prior/Modern-compatible Bag draw")
eq(rawget(missingBag, "_scottsTweaksGoldPackDraw"), nil,
  "unavailable Gold does not claim Bag draw ownership")
check(missing.api.getStatus().lastError:find("0.1.96", 1, true) ~= nil,
  "missing API status says 0.1.96 is required")

-- A screen reopened after the live option is turned off must be pristine too.
-- Existing decorated instances delegate to their base draw; newly constructed
-- ones never carry the marker that tells Modern UI to fail open.
local toggled = fixture({ enabled = true, tag = "toggle" })
invokeStartHook(toggled, stock)
local toggledStart = toggled.screens:get("StartMenu").new(toggled.game)
check(rawget(toggledStart, "_scottsTweaksGoldStartDraw") ~= nil,
  "enabled+ready Start is decorated")
toggled.values.gen2_menus = false
local reopenedStart = toggled.screens:get("StartMenu").new(toggled.game)
eq(reopenedStart.draw, reopenedStart.expectedDraw,
  "reopened option-off Start returns exact prior draw")
eq(rawget(reopenedStart, "_scottsTweaksGoldStartDraw"), nil,
  "reopened option-off Start has no Gold marker")
local reopenedBag = toggled.screens:get("BagMenu").new(toggled.game)
eq(reopenedBag.draw, reopenedBag.expectedDraw,
  "reopened option-off Bag returns exact prior draw")
eq(rawget(reopenedBag, "_scottsTweaksGoldPackDraw"), nil,
  "reopened option-off Bag has no Gold marker")

-- A payload without Chris remains usable but never invents replacement art.
local noChris = fixture({ enabled = true, tag = "no-chris", noChris = true })
local noChrisRows = invokeStartHook(noChris, stock)
eq(#calls.images, 4, "partial payload loads the four required UI images")
noChrisRows[4].onSelect()
local noChrisGear = noChris.game.stack:top()
noChrisGear:draw()
eq(calls.lastGear._scottsTweaksPlayerMarker,
  "omitted_without_authentic_rom_sprite",
  "missing Chris payload explicitly omits the marker")
local beforeOmittedDraw = #calls.spriteDraws
eq(calls.lastGear:drawPlayerIcon(40, 30), true,
  "omitted marker suppresses the generated-square fallback")
eq(#calls.spriteDraws, beforeOmittedDraw,
  "omitted marker draws no recreated art")
eq(noChris.api.getStatus().playerMarker,
  "omitted_without_authentic_rom_sprite",
  "status reports the safe authentic-art omission")

print(("gen2_ui: %d checks passed"):format(checks))
