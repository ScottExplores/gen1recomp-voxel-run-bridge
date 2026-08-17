-- Focused, ROM-free contract test for Scott's Tweaks' Gen 1 bag pockets and
-- shop-owned-count adapters.  The two fixtures model the ListMenu shape used
-- by Gen1Recomp v0.1.75 and v0.1.83.
--
-- Run from the mod root with a Lua 5.1-compatible runtime:
--   lua tests/inventory_ui.lua
--   luajit tests/inventory_ui.lua

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

local function copySequence(source)
  local result = {}
  for index, value in ipairs(source or {}) do result[index] = value end
  return result
end

local function copyMap(source)
  local result = {}
  for key, value in pairs(source or {}) do result[key] = value end
  return result
end

local function sequenceEq(actual, expected, label)
  eq(#actual, #expected, label .. " length")
  for index = 1, #expected do
    eq(actual[index], expected[index], label .. " #" .. index)
  end
end

local function mapEq(actual, expected, label)
  for key, value in pairs(expected) do
    eq(actual[key], value, label .. " " .. tostring(key))
  end
  for key, value in pairs(actual) do
    eq(value, expected[key], label .. " unexpected " .. tostring(key))
  end
end

local function rowIds(list)
  local result = {}
  for index, row in ipairs(list.items or {}) do result[index] = row.value end
  return result
end

local function countId(list, wanted)
  local count = 0
  for _, value in ipairs(list or {}) do
    if value == wanted then count = count + 1 end
  end
  return count
end

local Runtime = {}
function Runtime.wantsHook() return false end
function Runtime.call(_, vanilla, value, ctx) return vanilla(value, ctx) end

local Game = {
  save = { inventory = {}, party = {} },
  input = {},
  mods = { modOptions = {}, optionSchemas = {} },
}

local Map = {}
function Map.isOutside() return false end

local FieldDefaults = {}
function FieldDefaults.field() return {} end

local activeFixture

local ItemEffects = {}
function ItemEffects.isBall(id)
  return id == "POKE_BALL" or id == "GREAT_BALL"
      or id == "ULTRA_BALL" or id == "MASTER_BALL"
      or id == "SAFARI_BALL"
end

local Bag = {}
function Bag.order(save)
  save.bagOrder = save.bagOrder or {}
  return save.bagOrder
end
function Bag.add(save, id, qty)
  save.inventory[id] = (save.inventory[id] or 0) + (qty or 1)
  local found = false
  for _, current in ipairs(Bag.order(save)) do
    if current == id then found = true break end
  end
  if not found then save.bagOrder[#save.bagOrder + 1] = id end
  return true
end
function Bag.remove(save, id, qty)
  local left = (save.inventory[id] or 0) - (qty or 1)
  if left > 0 then
    save.inventory[id] = left
    return
  end
  save.inventory[id] = nil
  local order = Bag.order(save)
  for index, current in ipairs(order) do
    if current == id then table.remove(order, index) break end
  end
end

local BuiltinBag = {}
function BuiltinBag.new()
  error("inventory_ui fixture expected the preserved BagMenu factory")
end

local BuiltinShop = {}
function BuiltinShop.new()
  error("inventory_ui fixture expected the preserved ShopMenu factory")
end

local Sound = {}
function Sound.play(_, name)
  if activeFixture then
    activeFixture.sounds[#activeFixture.sounds + 1] = name
  end
end

package.preload["src.mods.Runtime"] = function() return Runtime end
package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.Map"] = function() return Map end
package.preload["src.world.FieldDefaults"] = function() return FieldDefaults end
package.preload["src.inventory.ItemEffects"] = function() return ItemEffects end
package.preload["src.inventory.Bag"] = function() return Bag end
package.preload["src.ui.BagMenu"] = function() return BuiltinBag end
package.preload["src.ui.ShopMenu"] = function() return BuiltinShop end
package.preload["src.core.Sound"] = function() return Sound end

local scriptSource = debug.getinfo(1, "S").source
local scriptPath = scriptSource:sub(1, 1) == "@" and scriptSource:sub(2)
  or "tests/inventory_ui.lua"
local testDirectory = scriptPath:match("^(.*[\\/])") or ""
local modRoot = testDirectory:gsub("tests[\\/]$", "")
local entry = assert(loadfile(modRoot .. "main.lua"))()
local TRADE_STONE = "SCOTTS_TRADE_STONE"

local function registry(initial)
  local values = initial or {}
  local result = { values = values }
  function result:get(id) return self.values[id] end
  function result:register(id, value)
    if self.values[id] ~= nil then error("duplicate registration: " .. id) end
    self.values[id] = value
    return value
  end
  function result:override(id, value)
    self.values[id] = value
    return value
  end
  return result
end

local function newInput()
  local input = { pressed = {} }
  function input:press(key) self.pressed[key] = true end
  function input:wasPressed(key)
    local result = self.pressed[key] == true
    self.pressed[key] = nil
    return result
  end
  function input:isDown() return false end
  return input
end

local function newStack()
  local stack = { entries = {} }
  function stack:push(value)
    self.entries[#self.entries + 1] = value
    return value
  end
  function stack:pop()
    return table.remove(self.entries)
  end
  function stack:top()
    return self.entries[#self.entries]
  end
  return stack
end

local function makeBaseBagList(game, version)
  local list = {
    game = game,
    title = "BAG",
    items = {},
    index = 1,
    scroll = 0,
    rows = 7,
    baseUpdates = 0,
    baseDraws = 0,
    baseChoices = {},
  }
  if version == "0.1.83" then list.kind = "bag" end

  for _, id in ipairs(Bag.order(game.save)) do
    local def = game.data.items[id]
    list.items[#list.items + 1] = {
      value = id,
      label = def and def.name or id,
      right = "x" .. tostring(game.save.inventory[id]),
    }
  end

  list.onChoose = function(item)
    list.baseChoices[#list.baseChoices + 1] = item and item.value
    return "base-choice", item and item.value
  end
  list.update = function(self)
    self.baseUpdates = self.baseUpdates + 1
    local input = self.game.input
    if input:wasPressed("up") then
      self.index = self.index > 1 and self.index - 1 or #self.items
    elseif input:wasPressed("down") then
      self.index = self.index < #self.items and self.index + 1 or 1
    elseif self.onSelectKey and input:wasPressed("select") then
      self.onSelectKey(self.items[self.index], self)
    elseif input:wasPressed("a") then
      return self.onChoose(self.items[self.index])
    end
    return "base-update", self.index
  end
  list.draw = function(self)
    self.baseDraws = self.baseDraws + 1
    self.lastBaseTitle = self.title
    return "base-draw", self.baseDraws
  end
  return list
end

local function fixture(version, config)
  config = config or {}
  local ctx = {
    version = version,
    sounds = {},
    bagCalls = {},
    shopCalls = {},
    buyDrawTitles = {},
  }
  activeFixture = ctx

  local order = {
    "POTION",
    "POKE_BALL",
    "CUSTOM_BALL",
    "TM_THUNDERBOLT",
    "HM_FLY",
    "BICYCLE",
    "CUSTOM_KEY",
    "MYSTERY",
  }
  local inventory = {
    POTION = 2,
    POKE_BALL = 4,
    CUSTOM_BALL = 3,
    TM_THUNDERBOLT = 1,
    HM_FLY = 1,
    BICYCLE = 1,
    CUSTOM_KEY = 1,
    MYSTERY = 6,
  }
  local data = {
    items = {
      POTION = { id = "POTION", name = "POTION", price = 300 },
      POKE_BALL = { id = "POKE_BALL", name = "POKE BALL", price = 200 },
      CUSTOM_BALL = {
        id = "CUSTOM_BALL", name = "CUSTOM BALL", price = 250,
        ball = "CUSTOM_BALL_EFFECT",
      },
      TM_THUNDERBOLT = {
        id = "TM_THUNDERBOLT", name = "TM24", price = 2000,
        machine = { kind = "TM", move = "THUNDERBOLT", number = 24 },
      },
      HM_FLY = { id = "HM_FLY", name = "HM02", price = 0 },
      BICYCLE = {
        id = "BICYCLE", name = "BICYCLE", price = 0, keyItem = true,
      },
      CUSTOM_KEY = {
        id = "CUSTOM_KEY", name = "CUSTOM KEY", price = 0,
        tossable = false,
      },
      -- MYSTERY deliberately has no definition: unknown/custom save ids must
      -- remain visible in the ordinary Items pocket.
    },
    pokemon = {},
    text = {},
  }
  local save = {
    inventory = inventory,
    bagOrder = order,
    party = {},
    pcItems = {},
    money = 1000,
  }
  local game = {
    data = data,
    save = save,
    input = newInput(),
    stack = newStack(),
  }
  ctx.game = game

  local lowerBag = {}
  function lowerBag.new(receivedGame, opts)
    local list = makeBaseBagList(receivedGame, version)
    ctx.bagCalls[#ctx.bagCalls + 1] = {
      game = receivedGame,
      opts = opts,
      list = list,
    }
    return list
  end

  local lowerShop = {}
  function lowerShop.new(receivedGame, stock, onQuit)
    local captured = copySequence(stock)
    local menu = {
      game = receivedGame,
      stock = stock,
      opened = false,
    }
    ctx.shopCalls[#ctx.shopCalls + 1] = {
      game = receivedGame,
      stock = stock,
      captured = captured,
      onQuit = onQuit,
      menu = menu,
    }
    menu.update = function(self)
      if self.opened then return "shop-already-open" end
      self.opened = true
      local rows = {}
      for _, id in ipairs(stock) do
        local def = receivedGame.data.items[id]
        rows[#rows + 1] = {
          value = id,
          label = def and def.name or id,
          right = def and ("Y%d"):format(def.price or 0) or "Y0",
        }
      end
      local buy = {
        game = receivedGame,
        title = "BUY",
        items = rows,
        index = 1,
      }
      if version == "0.1.83" then buy.kind = "BUY" end
      buy.draw = function(self)
        ctx.buyDrawTitles[#ctx.buyDrawTitles + 1] = self.title
        return "buy-draw", 83
      end
      self.buy = buy
      receivedGame.stack:push(buy)
      return "shop-opened", #rows
    end
    return menu
  end

  local screens = registry({ BagMenu = lowerBag, ShopMenu = lowerShop })
  local items = registry()
  local originalItemRegister = items.register
  function items:register(id, value)
    local result = originalItemRegister(self, id, value)
    data.items[id] = value
    return result
  end
  local itemEffects = registry()
  local optionValues = {
    bag_pockets = config.bagPockets,
    gen2_menus = config.gen2Menus,
  }
  local optionSchema = {}
  local options = {}
  function options:define(rows)
    optionSchema = rows
    for _, row in ipairs(rows) do
      if optionValues[row.key] == nil then optionValues[row.key] = row.default end
    end
  end
  function options:get(key) return optionValues[key] end

  local hooks = { values = {} }
  function hooks:wrap(name, callback)
    self.values[name] = callback
    return function()
      if self.values[name] == callback then self.values[name] = nil end
    end
  end
  local events = { values = {} }
  function events:on(name, callback)
    self.values[name] = self.values[name] or {}
    self.values[name][#self.values[name] + 1] = callback
  end

  local mod = {
    id = "voxel_run_bridge",
    exports = {},
    content = {
      screens = screens,
      items = items,
      item_effects = itemEffects,
    },
    options = options,
    hooks = hooks,
    events = events,
    log = {
      info = function() end,
      warn = function() end,
    },
    find = function() return nil end,
  }
  ctx.mod = mod
  ctx.screens = screens
  ctx.items = items
  ctx.itemEffects = itemEffects
  ctx.optionValues = optionValues
  ctx.optionSchema = function() return optionSchema end

  Game.save = save
  Game.data = data
  Game.input = game.input
  Game.stack = game.stack
  Game.mods = { modOptions = {}, optionSchemas = {} }

  entry(mod)
  return ctx
end

local function openBag(ctx)
  local factory = ctx.screens:get("BagMenu")
  check(type(factory) == "table" and type(factory.new) == "function",
    ctx.version .. " BagMenu screen override is installed")
  local opts = { battle = false, fixture = ctx.version }
  local list = factory.new(ctx.game, opts)
  eq(#ctx.bagCalls, 1, ctx.version .. " preserved BagMenu factory call count")
  eq(ctx.bagCalls[1].game, ctx.game,
    ctx.version .. " preserved BagMenu receives game")
  eq(ctx.bagCalls[1].opts, opts,
    ctx.version .. " preserved BagMenu receives options")
  return list, ctx.bagCalls[1].list
end

local function pressAndUpdate(ctx, list, key)
  ctx.game.input:press(key)
  return list:update(0)
end

local function testEnabledBag(version)
  local ctx = fixture(version, { bagPockets = true })
  local inventoryBefore = copyMap(ctx.game.save.inventory)
  local orderBefore = copySequence(ctx.game.save.bagOrder)
  local list = openBag(ctx)

  check(type(rawget(list, "_scottsTweaksPocketLayer")) == "table",
    version .. " pocket decorator marker")
  eq(list.title, "< ITEMS >", version .. " initial Items title")
  sequenceEq(rowIds(list), { "POTION", "MYSTERY" },
    version .. " Items classification and order")

  list.index = 2
  list:update(0)
  pressAndUpdate(ctx, list, "right")
  eq(list.title, "< BALLS >", version .. " Right opens Balls")
  sequenceEq(rowIds(list), { "POKE_BALL", "CUSTOM_BALL" },
    version .. " native and registered Ball classification")

  list.index = 2
  list:update(0)
  pressAndUpdate(ctx, list, "right")
  eq(list.title, "< KEY ITEMS >", version .. " Right opens Key Items")
  sequenceEq(rowIds(list), { "BICYCLE", "CUSTOM_KEY" },
    version .. " keyItem and non-tossable classification")

  pressAndUpdate(ctx, list, "right")
  eq(list.title, "< TM/HM >", version .. " Right opens TM/HM")
  sequenceEq(rowIds(list), { "TM_THUNDERBOLT", "HM_FLY" },
    version .. " machine metadata and id-prefix classification")

  pressAndUpdate(ctx, list, "right")
  eq(list.title, "< ITEMS >", version .. " Right wraps to Items")
  eq(list.index, 2, version .. " Items cursor is restored")
  pressAndUpdate(ctx, list, "right")
  eq(list.index, 2, version .. " Balls cursor is restored")
  pressAndUpdate(ctx, list, "left")
  eq(list.title, "< ITEMS >", version .. " Left returns to Items")
  eq(list.index, 2, version .. " Left preserves Items cursor")

  mapEq(ctx.game.save.inventory, inventoryBefore,
    version .. " bag browsing does not mutate inventory")
  sequenceEq(ctx.game.save.bagOrder, orderBefore,
    version .. " tabs do not mutate global order")

  list.index = 1
  list.onSelectKey(list.items[1], list)
  eq(list.swapIndex, 1, version .. " first SELECT marks pocket row")
  list.index = 2
  local choicesBefore = #list.baseChoices
  list.onChoose(list.items[2])
  eq(#list.baseChoices, choicesBefore,
    version .. " swap does not invoke native item use")
  sequenceEq(ctx.game.save.bagOrder, {
    "MYSTERY",
    "POKE_BALL",
    "CUSTOM_BALL",
    "TM_THUNDERBOLT",
    "HM_FLY",
    "BICYCLE",
    "CUSTOM_KEY",
    "POTION",
  }, version .. " pocket rows reorder authoritative IDs")
  sequenceEq(rowIds(list), { "MYSTERY", "POTION" },
    version .. " reordered pocket follows authoritative order")
  mapEq(ctx.game.save.inventory, inventoryBefore,
    version .. " reordering does not mutate quantities")

  list.index = 1
  local first, second = list.onChoose(list.items[1])
  eq(first, "base-choice", version .. " ordinary choose return #1")
  eq(second, "MYSTERY", version .. " ordinary choose delegates selected ID")
  eq(list.baseChoices[#list.baseChoices], "MYSTERY",
    version .. " ordinary choose reaches lower BagMenu")
end

local function testDisabledBag(version)
  local ctx = fixture(version, { bagPockets = false })
  local list, lowerList = openBag(ctx)
  eq(list, lowerList, version .. " option-off returns lower BagMenu instance")
  eq(rawget(list, "_scottsTweaksPocketLayer"), nil,
    version .. " option-off has no decorator marker")
  eq(list.title, "BAG", version .. " option-off keeps native title")
  sequenceEq(rowIds(list), ctx.game.save.bagOrder,
    version .. " option-off keeps native full list")
  local orderBefore = copySequence(ctx.game.save.bagOrder)
  local inventoryBefore = copyMap(ctx.game.save.inventory)
  pressAndUpdate(ctx, list, "right")
  eq(list.title, "BAG", version .. " option-off Right is passthrough")
  sequenceEq(ctx.game.save.bagOrder, orderBefore,
    version .. " option-off leaves order untouched")
  mapEq(ctx.game.save.inventory, inventoryBefore,
    version .. " option-off leaves save untouched")
end

local function testGoldForcesProjection(version)
  local ctx = fixture(version, { bagPockets = false, gen2Menus = true })
  local list, lowerList = openBag(ctx)
  check(list == lowerList,
    version .. " Gold projection decorates the preserved Red Bag instance")
  check(type(rawget(list, "_scottsTweaksPocketLayer")) == "table",
    version .. " Gold keeps the required pocket projection with classic off")
  eq(list.title, "< ITEMS >",
    version .. " Gold-forced projection opens in Items")
  pressAndUpdate(ctx, list, "right")
  eq(list.title, "< BALLS >",
    version .. " Gold-forced projection follows exact Gold order")
end

local function testShop(version)
  local ctx = fixture(version, { bagPockets = true })
  local factory = ctx.screens:get("ShopMenu")
  check(type(factory) == "table" and type(factory.new) == "function",
    version .. " ShopMenu screen override is installed")

  local stock = { "POTION", "POKE_BALL" }
  local stockBefore = copySequence(stock)
  local saveBefore = copyMap(ctx.game.save.inventory)
  local onQuit = function() return "quit" end
  local menu = factory.new(ctx.game, stock, onQuit)
  eq(#ctx.shopCalls, 1, version .. " preserved ShopMenu factory call count")
  local call = ctx.shopCalls[1]
  eq(call.game, ctx.game, version .. " preserved ShopMenu receives game")
  eq(call.onQuit, onQuit, version .. " preserved ShopMenu receives callback")
  check(call.stock ~= stock, version .. " ShopMenu receives a copied stock")
  sequenceEq(stock, stockBefore, version .. " caller stock is not mutated")
  eq(countId(call.captured, TRADE_STONE), 1,
    version .. " copied stock contains one Trade Stone")
  sequenceEq(call.captured, { "POTION", "POKE_BALL", TRADE_STONE },
    version .. " Trade Stone appends after native stock")
  mapEq(ctx.game.save.inventory, saveBefore,
    version .. " opening ShopMenu does not mutate inventory")

  ctx.game.stack:push(menu)
  local updateFirst, updateSecond = menu:update(0)
  eq(updateFirst, "shop-opened", version .. " decorated shop return #1")
  eq(updateSecond, 3, version .. " decorated shop return #2")
  local buy = ctx.game.stack:top()
  check(buy ~= menu, version .. " lower ShopMenu pushes BUY list")
  check(type(rawget(buy, "_scottsTweaksOwnedCount")) == "table",
    version .. " BUY list receives owned-count marker")

  local drawFirst, drawSecond = buy:draw()
  eq(drawFirst, "buy-draw", version .. " BUY draw return #1")
  eq(drawSecond, 83, version .. " BUY draw return #2")
  eq(ctx.buyDrawTitles[#ctx.buyDrawTitles], "BUY BAG:2",
    version .. " BUY title shows selected live quantity")
  eq(buy.title, "BUY", version .. " BUY title is restored after draw")
  mapEq(ctx.game.save.inventory, saveBefore,
    version .. " BUY display does not mutate inventory")

  buy.index = 3
  buy:draw()
  eq(ctx.buyDrawTitles[#ctx.buyDrawTitles], "BUY BAG:0",
    version .. " unowned Trade Stone displays zero")
  ctx.game.save.inventory[TRADE_STONE] = 4 -- simulate a completed native buy
  buy:draw()
  eq(ctx.buyDrawTitles[#ctx.buyDrawTitles], "BUY BAG:4",
    version .. " BUY display reads quantity live after purchase")
  eq(buy.title, "BUY", version .. " live redraw restores BUY title")

  local existing = { "POKE_BALL", TRADE_STONE, "POTION" }
  local existingBefore = copySequence(existing)
  factory.new(ctx.game, existing, onQuit)
  eq(#ctx.shopCalls, 2, version .. " second lower ShopMenu call count")
  eq(countId(ctx.shopCalls[2].captured, TRADE_STONE), 1,
    version .. " existing Trade Stone is not duplicated")
  sequenceEq(existing, existingBefore,
    version .. " existing-Trade-Stone stock remains unchanged")
end

for _, version in ipairs({ "0.1.75", "0.1.83" }) do
  testEnabledBag(version)
  testDisabledBag(version)
  testGoldForcesProjection(version)
  testShop(version)
end

print(("inventory UI: %d checks passed (v0.1.75 + v0.1.83 doubles)")
  :format(checks))
