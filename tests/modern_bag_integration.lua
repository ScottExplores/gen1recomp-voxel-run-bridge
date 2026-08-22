-- Focused integration contract for the bundled Modern Bag UI provider.
--
-- This is intentionally ROM-free. It loads the real vendor host and bundled
-- provider against small engine doubles, then exercises the public screen
-- records exactly as Scott's Tweaks will see them.
--
--   lua tests/modern_bag_integration.lua <mod-root>
--   luajit tests/modern_bag_integration.lua <mod-root>

local argv = rawget(_G, "arg") or {}
local sourceRoot = (argv[1] or "."):gsub("\\", "/"):gsub("/$", "")

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function eq(actual, expected, message)
  checks = checks + 1
  assert(actual == expected, ("%s: expected %s, got %s")
    :format(message, tostring(expected), tostring(actual)))
end
local function sequence(actual, expected, message)
  eq(#actual, #expected, message .. " length")
  for index, value in ipairs(expected) do
    eq(actual[index], value, message .. " #" .. tostring(index))
  end
end
local function contains(values, wanted)
  for _, value in ipairs(values or {}) do
    if value == wanted then return true end
  end
  return false
end
local function ids(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do out[#out + 1] = row.value end
  return out
end

local drawCalls = { rectangles = 0, raster = 0, text = {} }
local displayWidth, displayHeight = 1280, 720
love = {
  graphics = {
    getPixelDimensions = function() return displayWidth, displayHeight end,
    getDimensions = function() return displayWidth, displayHeight end,
    setColor = function() end,
    rectangle = function() drawCalls.rectangles = drawCalls.rectangles + 1 end,
    polygon = function() end,
    circle = function() end,
    line = function() end,
    push = function() end,
    pop = function() end,
    translate = function() end,
    print = function(text)
      drawCalls.text[#drawCalls.text + 1] = tostring(text)
    end,
    draw = function()
      drawCalls.raster = drawCalls.raster + 1
      error("the bundled backpack must not draw a raster asset")
    end,
  },
  image = {
    newImageData = function()
      error("the bundled backpack must not load a raster asset")
    end,
  },
}

local Strings = {}
function Strings.source(text) return text end
setmetatable(Strings, {
  __call = function(_, text, ...)
    text = tostring(text or "")
    if select("#", ...) > 0 then return string.format(text, ...) end
    return text
  end,
})

local Font = {
  PLAINPIXEL = "unused-procedural-test-font.ttf",
}
function Font.width(text) return #tostring(text or "") * 8 end
function Font.split(text)
  local out = {}
  text = tostring(text or "")
  for index = 1, #text do out[index] = { to = index } end
  return out
end
function Font.spansFitting(spans, width)
  return math.min(#spans, math.max(0, math.floor((width or 0) / 8)))
end
function Font.draw(text)
  drawCalls.text[#drawCalls.text + 1] = tostring(text)
end
function Font.drawCode(code)
  drawCalls.text[#drawCalls.text + 1] = tostring(code)
end
function Font.drawBox() drawCalls.rectangles = drawCalls.rectangles + 1 end

local Bag = {}
local BAG_CAPACITY = { ITEM = 20, BALL = 12, KEY_ITEM = 25, TM_HM = 64 }
function Bag.order(save)
  save.bagOrder = save.bagOrder or {}
  return save.bagOrder
end
function Bag.pocketOf(id, data)
  local def = data and data.items and data.items[id]
  return def and def.pocket or "ITEM"
end
function Bag.slots(save, data, pocket)
  local count = 0
  for id, amount in pairs(save.inventory or {}) do
    if tonumber(amount) and amount > 0 and not Bag.isBadge(id)
        and (not pocket or Bag.pocketOf(id, data) == pocket) then
      count = count + 1
    end
  end
  return count
end
function Bag.capacity(data, pocket)
  if pocket and pocket ~= "ITEM" then return BAG_CAPACITY[pocket] or 20 end
  return data and data.constants and data.constants.bagSize or 20
end
function Bag.isBadge(id) return tostring(id):match("BADGE$") ~= nil end
function Bag.add(save, id, qty, data)
  qty = qty or 1
  save.inventory = save.inventory or {}
  local before = save.inventory[id] or 0
  if before + qty > 99 then return false end
  local pocket = Bag.pocketOf(id, data)
  if before == 0
      and Bag.slots(save, data, pocket) >= Bag.capacity(data, pocket) then
    return false
  end
  save.inventory[id] = before + qty
  if before == 0 then Bag.order(save)[#Bag.order(save) + 1] = id end
  return true
end
local nativeBagAdd = Bag.add

local QuantityBox = {}
function QuantityBox.new(_, opts)
  return { max = opts and opts.max or 1, qty = 1, nativeQuantity = true }
end
local nativeQuantityNew = QuantityBox.new

local input = { pressed = {} }
function input:wasPressed(key) return self.pressed[key] == true end
function input:isDown() return false end

local nativeChoices, expShareMessages, baseRightUpdates = {}, 0, 0
local bagConstructs = 0
local function rowsFor(game, store)
  local rows = {}
  for _, id in ipairs(Bag.order(game.save)) do
    if store[id] then
      local def = game.data.items[id] or {}
      rows[#rows + 1] = {
        value = id, label = def.name or id, right = "x" .. tostring(store[id]),
      }
    end
  end
  return rows
end
local lowerBagRecord = {
  new = function(game, opts)
    bagConstructs = bagConstructs + 1
    local menu = {
      game = game, opts = opts, title = "BAG", rows = 7,
      index = 1, scroll = 0, items = rowsFor(game, game.save.inventory),
      lowerBagController = true,
    }
    menu.onChoose = function(item)
      if item and item.value == "SCOTTS_EXP_SHARE" then
        expShareMessages = expShareMessages + 1
        return "scott-exp-share", item.value
      end
      nativeChoices[#nativeChoices + 1] = item and item.value
      return "native-choice", item and item.value
    end
    menu.update = function(self)
      if self.game.input:wasPressed("right") then
        baseRightUpdates = baseRightUpdates + 1
      elseif self.game.input:wasPressed("down") and #self.items > 0 then
        self.index = math.min(#self.items, self.index + 1)
      elseif self.game.input:wasPressed("up") and #self.items > 0 then
        self.index = math.max(1, self.index - 1)
      elseif self.game.input:wasPressed("select") and self.onSelectKey then
        return self.onSelectKey(self.items[self.index], self)
      elseif self.game.input:wasPressed("a") and self.onChoose then
        return self.onChoose(self.items[self.index], self)
      end
      return "native-update"
    end
    menu.draw = function(self)
      self.nativeDraws = (self.nativeDraws or 0) + 1
      return "native-draw"
    end
    return menu
  end,
}

local pcConstructs = 0
local pcChoices = {}
local function newPCList(game, action, store, filter)
  local list = {
    game = game, action = action, index = 1, scroll = 0, rows = 7,
    items = {}, footer = nil,
  }
  local ordered = {}
  for id in pairs(store or {}) do ordered[#ordered + 1] = id end
  table.sort(ordered)
  for _, id in ipairs(ordered) do
    if not filter or filter(id) then
      local def = game.data.items[id] or {}
      list.items[#list.items + 1] = {
        value = id, label = def.name or id, right = "x" .. tostring(store[id]),
      }
    end
  end
  list.onChoose = function(item)
    pcChoices[#pcChoices + 1] = action .. ":" .. tostring(item and item.value)
    return "native-pc-choice", action, item and item.value
  end
  list.update = function() return "native-pc-update" end
  list.draw = function() return "native-pc-draw" end
  return list
end
local lowerPCRecord = {
  new = function(game)
    pcConstructs = pcConstructs + 1
    local menu = { game = game, items = {} }
    local actions = {
      { name = "withdraw", store = function() return game.save.pcItems end },
      { name = "deposit", store = function() return game.save.inventory end,
        filter = function(id) return not Bag.isBadge(id) end },
      { name = "toss", store = function() return game.save.pcItems end },
    }
    for index, action in ipairs(actions) do
      menu.items[index] = {
        label = action.name:upper(),
        onSelect = function()
          local list = newPCList(game, action.name, action.store(), action.filter)
          game.stack:push(list)
          return "native-pc-open", action.name
        end,
      }
    end
    return menu
  end,
}

package.preload["src.core.Strings"] = function() return Strings end
package.preload["src.render.Font"] = function() return Font end
package.preload["src.inventory.Bag"] = function() return Bag end
package.preload["src.ui.QuantityBox"] = function() return QuantityBox end
package.preload["src.inventory.ItemEffects"] = function()
  return { isBall = function(id) return id == "POKE_BALL" end }
end
package.preload["src.render.Assets"] = function()
  return {
    imageData = function() error("procedural backpack must not request image data") end,
    image = function() error("procedural backpack must not request an image") end,
  }
end
package.preload["src.render.PaletteFX"] = function()
  return {
    pal = function(data, name)
      return data and data.palettes and data.palettes.palettes
        and data.palettes.palettes[name]
    end,
  }
end
package.preload["src.ui.Theme"] = function()
  return { cursor = ">", cursorHollow = ")", moreArrow = "v" }
end
package.preload["src.core.Sound"] = function()
  return { play = function() end }
end
package.preload["src.ui.BagMenu"] = function() return lowerBagRecord end
package.preload["src.ui.PlayerPC"] = function() return lowerPCRecord end
package.preload["src.core.Game"] = function() return { mods = nil } end

local records = { BagMenu = lowerBagRecord, PlayerPC = lowerPCRecord }
local overrideCounts = { BagMenu = 0, PlayerPC = 0 }
local screens = {}
function screens:get(id) return records[id] end
function screens:override(id, record)
  records[id] = record
  overrideCounts[id] = (overrideCounts[id] or 0) + 1
  return record
end
-- Kept only to produce a precise failure if the unadapted upstream entry is
-- accidentally restored; the fused provider must preserve lower ownership.
function screens:register(id, record)
  error("bundled Modern Bag must override preserved " .. tostring(id)
    .. ", not register over it")
end

local optionValues = {}
local constantPatchCalls = 0
local logMessages = {}
local thorEnabled, thorAttached = false, false
local hostMod
hostMod = {
  id = "voxel_run_bridge",
  path = sourceRoot,
  exports = {
    thorDualScreen = {
      getEnabled = function() return thorEnabled end,
      secondDisplayAttached = function() return thorAttached end,
    },
  },
  -- The hosted handle resolves Scott's public exports through mod.find just
  -- as it does in the real VendorHost facade. Thor is installed after vendor
  -- mods, so these closures deliberately read live toggles at layout time.
  find = function(first, second)
    local id = second == nil and first or second
    if id == "voxel_run_bridge" or id == "BATTLE_ART_VOXEL_FORK" then
      return { id = id, exports = hostMod.exports }
    end
  end,
  options = {
    get = function(_, key) return optionValues[key] end,
  },
  hooks = { wrap = function() end },
  content = {
    screens = screens,
    constants = {
      get = function(_, key)
        if key == "bagSize" then return 20 end
      end,
      patch = function()
        constantPatchCalls = constantPatchCalls + 1
        error("Modern Bag UI must retain native inventory limits")
      end,
    },
  },
  log = {
    info = function(_, message) logMessages[#logMessages + 1] = tostring(message) end,
    warn = function(_, message) logMessages[#logMessages + 1] = tostring(message) end,
    error = function(_, message) logMessages[#logMessages + 1] = tostring(message) end,
  },
  assets = {
    path = function(_, relative) return sourceRoot .. "/" .. relative end,
    image = function() error("procedural backpack must not request host image") end,
    list = function() return {} end,
    info = function() return nil end,
  },
  list = function() return {} end,
  info = function() return nil end,
}
function hostMod:read(relative)
  local file, err = io.open(sourceRoot .. "/" .. relative, "rb")
  if not file then error(err or ("missing " .. tostring(relative))) end
  local body = file:read("*a")
  file:close()
  return body
end

local VendorHost = assert(loadfile(sourceRoot .. "/modules/vendor_host.lua"))()
local modernEntry, modernEntries
modernEntries = 0
for _, entry in ipairs(VendorHost.MODS) do
  if entry.id == "modern_bag_ui" then
    modernEntries = modernEntries + 1
    modernEntry = entry
  end
end
eq(modernEntries, 1, "vendor host contains Modern Bag exactly once")
eq(modernEntry and modernEntry.dir, "modern_bag_ui",
  "hosted Modern Bag uses its own rooted vendor directory")

local host = VendorHost.new(hostMod)
check(host:install(modernEntry), "hosted Modern Bag installs")
local firstBagRecord, firstPCRecord = records.BagMenu, records.PlayerPC
check(firstBagRecord.__modernBagUIFactory == true,
  "Bag registry publishes a Modern Bag factory marker")
eq(firstBagRecord.__modernBagOwner, "modern_bag_ui",
  "Bag registry has one vendor owner")
eq(firstBagRecord.__modernBagPrior, lowerBagRecord,
  "Bag registry preserves the lower Scott/native controller")
check(firstPCRecord.__modernBagPCFactory == true,
  "PC registry publishes a Modern Bag factory marker")
eq(firstPCRecord.__modernBagPrior, lowerPCRecord,
  "PC registry preserves its lower controller")

-- A development reload may execute the provider twice. It must unwrap its own
-- prior record rather than constructing Modern Bag on top of Modern Bag.
check(host:install(modernEntry), "repeat hosted installation succeeds")
eq(records.BagMenu.__modernBagPrior, lowerBagRecord,
  "repeat install does not nest Bag factories")
eq(records.PlayerPC.__modernBagPrior, lowerPCRecord,
  "repeat install does not nest PC factories")

local schema = host:mergedSchema()
local skinRow
for _, row in ipairs(schema) do
  if row.key == "modern_bag_ui:skin" then skinRow = row break end
end
check(type(skinRow) == "table", "host exposes one namespaced Bag Skin option")
eq(skinRow.default, "classic_pocket", "Pocket is the hosted default skin")
eq(skinRow.choices[1][1], "POCKET", "Pocket is the first visible skin")
eq(skinRow.choices[1][2], "classic_pocket", "Pocket choice has a stable value")
eq(skinRow.choices[2][1], "MODERN", "Modern remains selectable")
eq(skinRow.choices[2][2], "modern", "Modern choice has a stable value")

local exports = host.loaded.modern_bag_ui.exports
check(type(exports) == "table", "host publishes Modern Bag exports")
eq(exports.activeSkin(), "classic_pocket", "active skin uses hosted default")
optionValues["modern_bag_ui:skin"] = "modern"
eq(exports.activeSkin(), "modern", "Modern skin is selectable through host options")
optionValues["modern_bag_ui:skin"] = nil
eq(exports.inventoryLimits.expanded, false, "inventory expansion is disabled")
eq(exports.inventoryLimits.mode, "native", "inventory limit mode is native")
eq(exports.inventoryLimits.stack, 99, "native stack maximum is reported")
eq(exports.inventoryLimits.capacity({ constants = { bagSize = 20 } }), 20,
  "native Bag capacity function is exported")
eq(exports.bagUI.apiVersion, 1, "bundled Bag API is versioned")
eq(exports.bagUI.upstreamVersion, "0.4.1", "upstream source version is reported")
eq(exports.bagUI.nativeLimits, true, "Bag API reports native inventory limits")

local palettes = {}
for _, name in ipairs({ "BLUEMON", "BROWNMON", "GREENMON", "REDMON",
    "PURPLEMON", "CYANMON", "MEWMON" }) do
  palettes[name] = { { 255, 255, 255 }, { 170, 170, 170 },
    { 85, 85, 85 }, { 0, 0, 0 } }
end
local order = {
  "PLAIN_ITEM", "BATTLE_EXPLICIT", "POTION", "MED_EXPLICIT",
  "POKE_BALL", "TM_META", "TM_PREFIX", "HM_PREFIX",
  "KEY_META", "NON_TOSS", "SCOTTS_EXP_SHARE", "BOULDERBADGE",
}
local inventory = {}
for _, id in ipairs(order) do inventory[id] = 1 end
local data = {
  constants = { bagSize = 20 }, field = { pcItemCap = 50 },
  palettes = { palettes = palettes }, moves = {},
  items = {
    PLAIN_ITEM = { name = "PLAIN ITEM" },
    BATTLE_EXPLICIT = { name = "X TEST", bagPocket = "battle",
      pocket = "ITEM" },
    POTION = { name = "POTION" },
    MED_EXPLICIT = { name = "MED TEST", bagPocket = "Medicine" },
    POKE_BALL = { name = "POKé BALL", ball = true },
    TM_META = { name = "TM01", machine = { move = "TEST_MOVE" } },
    TM_PREFIX = { name = "TM PREFIX" },
    HM_PREFIX = { name = "HM PREFIX" },
    KEY_META = { name = "KEY META", keyItem = true },
    NON_TOSS = { name = "NON TOSS", tossable = false },
    SCOTTS_EXP_SHARE = { name = "EXP.SHARE", keyItem = true,
      tossable = false, pocket = "KEY_ITEM" },
    BOULDERBADGE = { name = "BOULDERBADGE", keyItem = true },
  },
}
data.moves.TEST_MOVE = { name = "TEST MOVE", description = "TEST DESCRIPTION" }
local stack = { states = {} }
function stack:push(state) self.states[#self.states + 1] = state end
function stack:pop() return table.remove(self.states) end
function stack:top() return self.states[#self.states] end
local game = {
  data = data, input = input, stack = stack,
  save = {
    inventory = inventory, bagOrder = order,
    pcItems = { POTION = 2, TM_PREFIX = 1, NON_TOSS = 1 },
    money = 4321, options = {},
  },
  mods = {},
}

bagConstructs = 0
local bag = records.BagMenu.new(game, { battle = false })
eq(bagConstructs, 1, "one lower Bag controller is constructed")
check(bag.lowerBagController == true, "lower controller identity is retained")
check(bag.modernBagUI == true, "Modern Bag decorates the retained controller")
eq(bag.modernBagProvider, "modern_bag_ui", "screen reports one navigation provider")
eq(bag.modernBagUpstreamVersion, "0.4.1", "screen reports upstream version")
eq(bag.modernBagLayout, "pockets", "Bag uses pocket layout")
local pocketKeys = {}
for _, pocket in ipairs(bag.modernBagPockets or {}) do
  pocketKeys[#pocketKeys + 1] = pocket.key
end
sequence(pocketKeys, { "all", "items", "medicine", "balls", "machines", "key" },
  "All plus five pockets use the promised order")
sequence(ids(bag.items), order, "All preserves acquisition order")

eq(bag:modernBagCategoryFor("BATTLE_EXPLICIT"), "items",
  "explicit battle pocket folds into Items")
eq(bag:modernBagCategoryFor("TM_PREFIX"), "machines",
  "TM_ prefix falls back to TMs/HMs")
eq(bag:modernBagCategoryFor("HM_PREFIX"), "machines",
  "HM_ prefix falls back to TMs/HMs")
eq(bag:modernBagCategoryFor("NON_TOSS"), "key",
  "non-tossable item falls back to Key Items")

bag:modernBagSwitchPocket(1)
check(contains(ids(bag.items), "PLAIN_ITEM"), "Items contains ordinary items")
check(contains(ids(bag.items), "BATTLE_EXPLICIT"),
  "Items contains explicit battle items")
bag:modernBagSwitchPocket(1)
check(contains(ids(bag.items), "POTION"), "Medicine contains known medicine")
check(contains(ids(bag.items), "MED_EXPLICIT"),
  "Medicine honors explicit metadata")
bag:modernBagSwitchPocket(1)
sequence(ids(bag.items), { "POKE_BALL" }, "Balls filters catching devices")
bag:modernBagSwitchPocket(1)
sequence(ids(bag.items), { "TM_META", "TM_PREFIX", "HM_PREFIX" },
  "TMs/HMs combines metadata and prefix fallbacks")
bag:modernBagSwitchPocket(1)
sequence(ids(bag.items), { "KEY_META", "NON_TOSS", "SCOTTS_EXP_SHARE",
    "BOULDERBADGE" }, "Key Items combines native and compatibility fallbacks")

local ordinaryResult, ordinaryId
bag:modernBagSwitchPocket(1) -- wrap to All
bag.index = 1
ordinaryResult, ordinaryId = bag.onChoose(bag.items[bag.index], bag)
eq(ordinaryResult, "native-choice", "ordinary choice reaches native callback")
eq(ordinaryId, "PLAIN_ITEM", "ordinary callback receives exact selected id")
eq(nativeChoices[#nativeChoices], "PLAIN_ITEM", "native callback runs once")
bag:modernBagSwitchPocket(-1) -- Key Items
for index, row in ipairs(bag.items) do
  if row.value == "SCOTTS_EXP_SHARE" then bag.index = index break end
end
local expResult, expId = bag.onChoose(bag.items[bag.index], bag)
eq(expResult, "scott-exp-share", "Scott EXP.SHARE wrapper remains authoritative")
eq(expId, "SCOTTS_EXP_SHARE", "EXP.SHARE wrapper receives exact id")
eq(expShareMessages, 1, "EXP.SHARE narrow wrapper runs exactly once")

-- A single Right press must be consumed by exactly one pocket owner.
bag.modernBagPocket = 1
bag:modernBagRefresh()
baseRightUpdates = 0
input.pressed.right = true
bag:update(0)
input.pressed.right = nil
eq(bag.modernBagPocket, 2, "one Right press advances exactly one pocket")
eq(baseRightUpdates, 0, "pocket input does not reach a second lower owner")

-- Pocket skin draws entirely from primitives at landscape and portrait sizes.
optionValues["modern_bag_ui:skin"] = nil
displayWidth, displayHeight = 1280, 720
local landscapeW, landscapeH = bag:uiSize()
eq(landscapeW, 256, "landscape UI uses responsive width")
eq(landscapeH, 144, "landscape UI retains native height")
eq(bag:modernBagLayoutInfo().rows, 5, "landscape Pocket skin shows five rows")
local beforeRectangles = drawCalls.rectangles
local beforeLandscapeText = #drawCalls.text
bag:draw()
check(drawCalls.rectangles > beforeRectangles,
  "procedural backpack contributes primitive drawing")
eq(drawCalls.raster, 0, "Pocket skin uses no raster backpack")
eq(bag.modernBagClassicPocketArt, "items", "draw reports active backpack state")
eq(bag.modernBagClassicPocketRegion, "items",
  "draw reports the highlighted procedural compartment")
local landscapeText = {}
for index = beforeLandscapeText + 1, #drawCalls.text do
  landscapeText[#landscapeText + 1] = drawCalls.text[index]
end
check(contains(landscapeText, "10/20"),
  "Items view reports its shared native Gen1 ITEM-pocket capacity")

bag.modernBagPocket = 1
bag:modernBagRefresh()
local beforeAllText = #drawCalls.text
bag:draw()
local allText = {}
for index = beforeAllText + 1, #drawCalls.text do
  allText[#allText + 1] = drawCalls.text[index]
end
check(contains(allText, "11"), "All view reports the total occupied stacks")
check(not contains(allText, "11/20"),
  "All view never compares mixed native pockets to the ITEM-only capacity")

bag.modernBagPocket = 4
bag:modernBagRefresh()
local beforeBallsText = #drawCalls.text
bag:draw()
local ballsText = {}
for index = beforeBallsText + 1, #drawCalls.text do
  ballsText[#ballsText + 1] = drawCalls.text[index]
end
check(contains(ballsText, "10/20"),
  "Gen1 Balls view derives the real shared ITEM-pocket capacity")
check(not contains(ballsText, "0/12"),
  "Gen1 Balls view never assumes Gen2 BALL metadata")

bag.modernBagPocket = 6
bag:modernBagRefresh()
local beforeKeyText = #drawCalls.text
bag:draw()
local keyText = {}
for index = beforeKeyText + 1, #drawCalls.text do
  keyText[#keyText + 1] = drawCalls.text[index]
end
check(contains(keyText, "3"),
  "mixed native pockets report the visual category's occupied stacks")
check(not contains(keyText, "1/25"),
  "mixed native pockets never claim one misleading capacity")

local savedPocketOf = Bag.pocketOf
Bag.pocketOf = nil
bag.modernBagPocket = 4
bag:modernBagRefresh()
local beforeLegacyBallsText = #drawCalls.text
bag:draw()
local legacyBallsText = {}
for index = beforeLegacyBallsText + 1, #drawCalls.text do
  legacyBallsText[#legacyBallsText + 1] = drawCalls.text[index]
end
check(contains(legacyBallsText, "1"),
  "older single-bag engines receive a count-only Balls header")
check(not contains(legacyBallsText, "0/12"),
  "older single-bag engines never receive an invented pocket capacity")
Bag.pocketOf = savedPocketOf
bag.modernBagPocket = 2
bag:modernBagRefresh()

displayWidth, displayHeight = 998, 1980
local portraitW, portraitH = bag:uiSize()
eq(portraitW, 160, "portrait UI retains readable native width")
eq(portraitH, 330, "portrait UI uses available integer-scaled height")
local portrait = bag:modernBagLayoutInfo()
check(portrait.stacked == true, "portrait Pocket skin uses stacked layout")
eq(portrait.rows, 10, "portrait layout exposes ten rows")
bag:draw()
eq(drawCalls.raster, 0, "portrait Pocket skin remains procedural")

optionValues["modern_bag_ui:skin"] = "modern"
check(bag:modernBagLayoutInfo().skin ~= "classic_pocket",
  "Modern layout is selected live")
bag:draw()
eq(drawCalls.raster, 0, "Modern layout does not introduce backpack raster art")
optionValues["modern_bag_ui:skin"] = nil
displayWidth, displayHeight = 1280, 720

-- Every native PC operation must keep its callback and receive the same six
-- pocket decorator. Opening the wrapper must not alter native PC capacity.
pcConstructs = 0
local pcMenu = records.PlayerPC.new(game)
eq(pcConstructs, 1, "one lower PlayerPC controller is constructed")
eq(game.data.field.pcItemCap, 50, "native PC capacity remains unchanged")
local decoratedPCList
for actionIndex, actionName in ipairs({ "withdraw", "deposit", "toss" }) do
  local result, opened = pcMenu.items[actionIndex].onSelect()
  eq(result, "native-pc-open", actionName .. " retains native open return")
  eq(opened, actionName, actionName .. " retains native operation identity")
  local list = stack:top()
  if not decoratedPCList then decoratedPCList = list end
  check(list.modernPCUI == true, actionName .. " list receives modern PC UI")
  eq(list.modernBagLayout, "pc-pockets", actionName .. " uses PC pocket layout")
  eq(list.modernBagProvider, "modern_bag_ui", actionName .. " has one provider")
  eq(#list.modernBagPockets, 6, actionName .. " receives all six views")
  if #list.items > 0 then
    local choose, operation, chosen = list.onChoose(list.items[1], list)
    eq(choose, "native-pc-choice", actionName .. " retains native choose callback")
    eq(operation, actionName, actionName .. " callback receives its operation")
    eq(chosen, list.items[1].value, actionName .. " callback receives selected id")
  end
  if actionName == "deposit" then
    check(not contains(ids(list.items), "BOULDERBADGE"),
      "deposit keeps native badge filtering")
  end
  stack:pop()
end

-- The physical Thor lower display is a fixed 400x360 logical surface. A
-- canonical 160x144 menu scales there at a crisp integer 2x; the ordinary
-- responsive 256px landscape surface must return as soon as either half of
-- the physical-display contract is false.
displayWidth, displayHeight = 1280, 720
local ordinaryPCW, ordinaryPCH = decoratedPCList:uiSize()
eq(ordinaryPCW, 256, "ordinary landscape PC list keeps responsive width")
eq(ordinaryPCH, 144, "ordinary landscape PC list keeps native height")

thorEnabled, thorAttached = true, true
local thorBagW, thorBagH = bag:uiSize()
eq(thorBagW, 160, "enabled attached Thor fixes Bag width")
eq(thorBagH, 144, "enabled attached Thor fixes Bag height")
local thorPCW, thorPCH = decoratedPCList:uiSize()
eq(thorPCW, 160, "enabled attached Thor fixes PC list width")
eq(thorPCH, 144, "enabled attached Thor fixes PC list height")

thorEnabled, thorAttached = false, true
local disabledBagW, disabledBagH = bag:uiSize()
eq(disabledBagW, 256, "disabled Thor restores responsive Bag width")
eq(disabledBagH, 144, "disabled Thor restores Bag height")
local disabledPCW, disabledPCH = decoratedPCList:uiSize()
eq(disabledPCW, 256, "disabled Thor restores responsive PC width")
eq(disabledPCH, 144, "disabled Thor restores PC height")

thorEnabled, thorAttached = true, false
local detachedBagW, detachedBagH = bag:uiSize()
eq(detachedBagW, 256, "detached Thor restores responsive Bag width")
eq(detachedBagH, 144, "detached Thor restores Bag height")
local detachedPCW, detachedPCH = decoratedPCList:uiSize()
eq(detachedPCW, 256, "detached Thor restores responsive PC width")
eq(detachedPCH, 144, "detached Thor restores PC height")
thorEnabled, thorAttached = false, false

eq(constantPatchCalls, 0, "provider never patches bagSize")
eq(Bag.add, nativeBagAdd, "provider never replaces Bag.add")
eq(QuantityBox.new, nativeQuantityNew, "provider never replaces QuantityBox.new")
local limitSave = { inventory = { PLAIN_ITEM = 99 }, bagOrder = { "PLAIN_ITEM" } }
check(not Bag.add(limitSave, "PLAIN_ITEM", 1, data), "native x99 stack limit remains")
for index = 2, 20 do
  check(Bag.add(limitSave, "LIMIT_" .. tostring(index), 1, data),
    "native Bag accepts slot " .. tostring(index))
end
check(not Bag.add(limitSave, "LIMIT_21", 1, data),
  "native 20-stack Bag limit remains")

-- If the loader says a standalone Modern Bag will run, the bundled provider
-- must stand down before registering a second controller.
local standaloneRecords = { BagMenu = lowerBagRecord, PlayerPC = lowerPCRecord }
local standaloneMod = {}
for key, value in pairs(hostMod) do standaloneMod[key] = value end
standaloneMod.content = {
  screens = {
    get = function(_, id) return standaloneRecords[id] end,
    override = function() error("bundled provider must stand down") end,
    register = function() error("bundled provider must stand down") end,
  },
  constants = hostMod.content.constants,
}
standaloneMod.find = function(first, second)
  local id = second == nil and first or second
  if id == "modern_bag_ui" then
    return { id = id, exports = { bagUI = { apiVersion = 1 } } }
  end
end
local standaloneHost = VendorHost.new(standaloneMod)
local savedMods = VendorHost.MODS
VendorHost.MODS = { modernEntry }
standaloneHost:installAll()
VendorHost.MODS = savedMods
eq(standaloneHost.loaded.modern_bag_ui, nil,
  "standalone Modern Bag suppresses bundled copy")
eq(standaloneHost.failures.modern_bag_ui, "standalone copy is installed",
  "standalone ownership decision is explicit")
eq(standaloneRecords.BagMenu, lowerBagRecord,
  "standalone ownership leaves Bag registry untouched")

print(("modern bag integration: %d checks passed"):format(checks))
