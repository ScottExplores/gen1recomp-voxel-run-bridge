-- Focused ROM-free contracts for Scott's Tweaks 0.9.1.
-- Run from the mod root with Lua 5.1 or LuaJIT:
--   lua5.1 tests/experience_trade.lua
--   luajit tests/experience_trade.lua

local checks, failures = 0, {}

local function fail(message)
  error(message, 2)
end

local function check(value, label)
  checks = checks + 1
  if not value then fail(label) end
end

local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    fail(("%s: expected %s, got %s"):format(
      label, tostring(expected), tostring(actual)))
  end
end

local function pack(...)
  return { n = select("#", ...), ... }
end

local tests = {}
local function test(name, body)
  tests[#tests + 1] = { name = name, body = body }
end

local Runtime = {}
function Runtime.wantsHook() return false end
function Runtime.call(_, vanilla, ...) return vanilla(...) end

local Game = {
  save = { inventory = {}, party = {} },
  data = { items = {}, item_effects = {}, pokemon = {} },
  mods = {},
}

local FieldDefaults = {}
function FieldDefaults.field() return {} end

local Map = {}
function Map.isOutside() return false end
function Map.isOutdoor() return false end

local Bag = {}
function Bag.add(save, id, count)
  if save._rejectAdds then return false end
  local inventory = save.inventory
  if inventory[id] then
    inventory[id] = inventory[id] + count
    return true
  end
  inventory[id] = count
  save._order = save._order or {}
  save._order[#save._order + 1] = id
  -- v0.1.75 could append a newly-added id twice before Bag.order repaired it.
  if save._simulateV75Add then save._order[#save._order + 1] = id end
  return true
end

function Bag.remove(save, id, count)
  local left = (save.inventory[id] or 0) - count
  save.inventory[id] = left > 0 and left or nil
  return true
end

function Bag.order(save)
  save._order = save._order or {}
  local out, seen = {}, {}
  for _, id in ipairs(save._order) do
    if save.inventory[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  for id, count in pairs(save.inventory or {}) do
    if count and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  save._order = out
  return out
end

local ItemEffects = { dispatches = 0 }
function ItemEffects.isBall(id)
  return id == "POKE_BALL" or id == "GREAT_BALL"
end
function ItemEffects.needsTarget() return false end
function ItemEffects.healsHP() return false end

-- A small v0.1.83-style registered-effect dispatcher. The v0.1.75 fallback
-- tests below deliberately bypass this function and enter through BagMenu.
function ItemEffects.use(data, save, id, target, battle)
  ItemEffects.dispatches = ItemEffects.dispatches + 1
  local item = data.items[id]
  local effect = item and data.item_effects[item.effect]
  if not effect then return "failed" end
  if battle and effect.battle == false then return "failed" end
  if not battle and effect.field == false then return "failed" end
  return effect.use({
    data = data,
    save = save,
    itemId = id,
    item = item,
    target = target,
    battle = battle,
  })
end

local ui = {}
local function resetUi()
  ui.menu = nil
  ui.partyOpts = nil
  ui.evolutions = {}
  ui.text = nil
  ui.baseChoices = 0
  ui.lastShopStock = nil
end
resetUi()

local BagMenu = {}
function BagMenu.new(game, opts)
  opts = opts or {}
  local list = {
    items = {}, index = 1, scroll = 0, rows = 7,
    update = function() return "base-update" end,
    draw = function() return "base-draw" end,
  }
  function list:close() self.closed = true end

  -- The relevant slice of v0.1.75 BagMenu: target detection and result
  -- handling existed there even though ItemEffects itself did not yet
  -- dispatch registered content effects.
  local function useOn(id, target)
    local result, payload, extra = ItemEffects.use(
      game.data, game.save, id, target, opts.battle)
    if result == "consumed" then
      Bag.remove(game.save, id, 1)
      if extra and extra.evolveTo then
        list:close()
        require("src.pokemon.Evolution").evolve(
          game, target, extra.evolveTo, nil, "ITEM")
      end
      return
    end
    local message = type(payload) == "table" and payload[1] or "No effect."
    game.stack:push(require("src.render.TextBox").new(game, message))
  end

  local function useItem(id)
    local def = game.data.items[id]
    if ItemEffects.needsTarget(id, def, game.data)
        and not ItemEffects.isBall(id) then
      require("src.ui.Screens").push(game, "PartyMenu", {
        pickOnly = true,
        onSwitch = function(mon) useOn(id, mon) end,
      })
    else
      useOn(id, nil)
    end
  end

  list.onChoose = function(item)
    ui.baseChoices = ui.baseChoices + 1
    local id = item.value
    if opts.battle then return useItem(id) end
    game.stack:push(require("src.ui.Menu").new(game, {
      { label = "USE", onSelect = function() useItem(id) end },
      { label = "TOSS", onSelect = function() end },
    }))
  end
  return list
end

local ShopMenu = {}
function ShopMenu.new(_, stock)
  ui.lastShopStock = stock
  return { update = function() return "shop-update" end }
end

package.preload["src.mods.Runtime"] = function() return Runtime end
package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.FieldDefaults"] = function() return FieldDefaults end
package.preload["src.world.Map"] = function() return Map end
package.preload["src.inventory.Bag"] = function() return Bag end
package.preload["src.inventory.ItemEffects"] = function() return ItemEffects end
package.preload["src.ui.BagMenu"] = function() return BagMenu end
package.preload["src.ui.ShopMenu"] = function() return ShopMenu end
package.preload["src.core.Sound"] = function()
  return { play = function() end }
end
package.preload["src.render.TextBox"] = function()
  return {
    new = function(_, message, onDone)
      local box = { kind = "text", message = message, onDone = onDone }
      ui.text = box
      return box
    end,
  }
end
package.preload["src.ui.Menu"] = function()
  return {
    new = function(_, items, opts)
      local menu = { kind = "menu", items = items, opts = opts }
      ui.menu = menu
      return menu
    end,
  }
end
package.preload["src.ui.Screens"] = function()
  return {
    push = function(_, name, opts)
      eq(name, "PartyMenu", "Trade Stone opens the party picker")
      ui.partyOpts = opts
      return opts
    end,
  }
end
package.preload["src.pokemon.Evolution"] = function()
  return {
    evolve = function(game, mon, target, callback, via)
      ui.evolutions[#ui.evolutions + 1] = {
        game = game, mon = mon, target = target,
        callback = callback, via = via,
      }
    end,
  }
end
package.preload["src.ui.QuantityBox"] = function()
  return { new = function(_, opts) return { kind = "quantity", opts = opts } end }
end
package.preload["src.ui.ChoiceBox"] = function()
  return { new = function(_, done) return { kind = "choice", done = done } end }
end

local schema, optionValues = {}, {}
local listeners, hooks = {}, {}
local registrations = { items = {}, item_effects = {}, screens = {} }

local options = {}
function options:define(rows)
  schema = rows
  return rows
end
function options:get(key)
  if optionValues[key] ~= nil then return optionValues[key] end
  for _, row in ipairs(schema) do
    if row.key == key then return row.default end
  end
end

local events = {}
function events:on(name, callback)
  listeners[name] = listeners[name] or {}
  listeners[name][#listeners[name] + 1] = callback
end
function events:emit(name, payload)
  for _, callback in ipairs(listeners[name] or {}) do callback(payload) end
end

local hookApi = {}
function hookApi:wrap(name, callback)
  hooks[name] = callback
  return function()
    if hooks[name] == callback then hooks[name] = nil end
  end
end

local function recordRegistry(target, live)
  return {
    register = function(_, id, value)
      target[id] = value
      if live then live[id] = value end
      return value
    end,
  }
end

local screenRegistry = {}
function screenRegistry:get() return nil end
function screenRegistry:override(id, value)
  registrations.screens[id] = value
  return value
end

local mod = {
  id = "voxel_run_bridge",
  exports = {},
  hooks = hookApi,
  events = events,
  options = options,
  content = {
    items = recordRegistry(registrations.items, Game.data.items),
    item_effects = recordRegistry(
      registrations.item_effects, Game.data.item_effects),
    screens = screenRegistry,
  },
  log = {
    info = function() end,
    warn = function() end,
  },
  find = function() return nil end,
}

local entry = assert(loadfile("main.lua"))()
entry(mod)

local function schemaRow(key)
  for _, row in ipairs(schema) do
    if row.key == key then return row end
  end
end

local function newSave(fields)
  fields = fields or {}
  fields.inventory = fields.inventory or {}
  fields.pcItems = fields.pcItems or {}
  fields.party = fields.party or {}
  return fields
end

local function setGame(save)
  Game.save = save
  Game.data.items = Game.data.items or {}
  Game.data.item_effects = Game.data.item_effects or {}
  return Game
end

local function battleCtx(save, lead, alive)
  local applyShare = function() end
  return {
    battle = { game = setGame(save), player = { mon = lead } },
    participants = 4,
    alive = alive or {},
    applyShare = applyShare,
    compatibilitySentinel = "kept",
  }, applyShare
end

local function stackFixture()
  local stack = { values = {} }
  function stack:push(value)
    self.values[#self.values + 1] = value
    return value
  end
  function stack:top() return self.values[#self.values] end
  return stack
end

local function fieldGame(save)
  return {
    save = save,
    data = Game.data,
    stack = stackFixture(),
    input = { wasPressed = function() return false end },
  }
end

local function menuAction(label)
  for _, row in ipairs((ui.menu and ui.menu.items) or {}) do
    if row.label == label then return row.onSelect end
  end
  return nil
end

test("EXP schema has four explicit modes and defaults to vanilla", function()
  local row = schemaRow("experience_mode")
  check(type(row) == "table", "EXP. MODE option is registered")
  eq(row.type, "choice", "EXP. MODE option type")
  eq(row.default, "vanilla", "EXP. MODE default")
  eq(#row.choices, 4, "EXP. MODE choice count")
  local seen = {}
  for _, choice in ipairs(row.choices) do seen[choice[2]] = choice[1] end
  eq(seen.vanilla, "VANILLA", "vanilla choice")
  eq(seen.lead, "LEAD ONLY", "lead choice")
  eq(seen.party, "PARTY ALL", "party choice")
  eq(seen.share, "EXP.SHARE", "share choice")
end)

test("custom item registrations keep stable references and shop price", function()
  local stone = registrations.items.SCOTTS_TRADE_STONE
  local share = registrations.items.SCOTTS_EXP_SHARE
  local effect = registrations.item_effects.SCOTTS_TRADE_STONE_EFFECT
  check(type(stone) == "table", "Trade Stone item is registered")
  check(type(share) == "table", "EXP.SHARE item is registered")
  check(type(effect) == "table", "Trade Stone effect is registered")
  eq(stone.effect, "SCOTTS_TRADE_STONE_EFFECT", "Trade Stone effect reference")
  eq(stone.price, 500, "Trade Stone shop price")
  eq(stone.needsTarget, true, "Trade Stone targets a party Pokemon")
  eq(effect.needsTarget, true, "Trade Stone effect targets a party Pokemon")
  eq(effect.field, true, "Trade Stone is usable in the field")
  eq(effect.battle, false, "Trade Stone is refused in battle")
  eq(share.keyItem, true, "EXP.SHARE is persistent key-item content")
  eq(share.tossable, false, "EXP.SHARE cannot be thrown away")

  resetUi()
  local shop = registrations.screens.ShopMenu
  check(type(shop) == "table" and type(shop.new) == "function",
    "ShopMenu override is installed")
  shop.new(fieldGame(newSave()), { "POTION" })
  eq(ui.lastShopStock[1], "POTION", "existing shop stock is preserved")
  eq(ui.lastShopStock[2], "SCOTTS_TRADE_STONE",
    "Trade Stone is appended to shop stock")
  shop.new(fieldGame(newSave()), { "SCOTTS_TRADE_STONE" })
  eq(#ui.lastShopStock, 1, "Trade Stone is not duplicated in shop stock")
end)

test("registered Trade Stone effect maps all four trades and refuses bad targets", function()
  local targets = {
    KADABRA = "ALAKAZAM",
    MACHOKE = "MACHAMP",
    GRAVELER = "GOLEM",
    HAUNTER = "GENGAR",
  }
  for source, target in pairs(targets) do
    Game.data.pokemon[source] = { name = source, evolutions = {} }
    Game.data.pokemon[target] = { name = target, evolutions = {} }
    local result = pack(ItemEffects.use(Game.data, newSave(),
      "SCOTTS_TRADE_STONE", { species = source }, nil))
    eq(result.n, 3, source .. " effect result arity")
    eq(result[1], "consumed", source .. " consumes Trade Stone")
    eq(result[2], nil, source .. " has no pre-evolution message")
    eq(result[3] and result[3].evolveTo, target,
      source .. " evolves to " .. target)
  end

  Game.data.pokemon.RATTATA = { name = "RATTATA", evolutions = {} }
  local result, messages = ItemEffects.use(Game.data, newSave(),
    "SCOTTS_TRADE_STONE", { species = "RATTATA" }, nil)
  eq(result, "failed", "invalid Trade Stone target is refused")
  check(type(messages) == "table" and messages[1]:find("won't", 1, true),
    "invalid target has a no-effect message")

  local battleResult = ItemEffects.use(Game.data, newSave(),
    "SCOTTS_TRADE_STONE", { species = "KADABRA" }, {})
  eq(battleResult, "failed", "registered dispatch refuses Trade Stone in battle")
end)

test("v0.1.75 compatibility wrapper is namespaced and delegates other mods exactly", function()
  local marker = rawget(ItemEffects, "_scottsTweaksTradeStoneHook")
  check(type(marker) == "table", "v0.1.75 compatibility marker is installed")
  eq(marker.owner, "voxel_run_bridge", "compatibility marker has one owner")
  eq(ItemEffects.needsTarget("SCOTTS_TRADE_STONE",
    Game.data.items.SCOTTS_TRADE_STONE, Game.data), true,
    "v0.1.75 compatibility marks Trade Stone as targeted")

  Game.data.items.COMPAT_ITEM = {
    id = "COMPAT_ITEM", name = "COMPAT ITEM", effect = "COMPAT_EFFECT",
  }
  Game.data.item_effects.COMPAT_EFFECT = {
    field = true,
    use = function() return "kept", nil, 77 end,
  }
  ItemEffects.dispatches = 0
  local result = pack(ItemEffects.use(
    Game.data, newSave(), "COMPAT_ITEM", nil, nil))
  eq(ItemEffects.dispatches, 1, "unrelated custom item delegates to prior ItemEffects")
  eq(result.n, 3, "delegated custom item preserves return arity")
  eq(result[1], "kept", "delegated custom item preserves first result")
  eq(result[2], nil, "delegated custom item preserves nil result")
  eq(result[3], 77, "delegated custom item preserves trailing result")
  eq(ItemEffects.needsTarget("COMPAT_ITEM",
    Game.data.items.COMPAT_ITEM, Game.data), false,
    "unrelated target query delegates to prior ItemEffects")

  local stone = Game.data.items.SCOTTS_TRADE_STONE
  local priorEffect = stone.effect
  stone.effect = "COMPAT_EFFECT"
  ItemEffects.dispatches = 0
  local foreign = ItemEffects.use(
    Game.data, newSave(), "SCOTTS_TRADE_STONE", nil, nil)
  eq(foreign, "kept",
    "same item id with a foreign effect is not claimed by compatibility wrapper")
  eq(ItemEffects.dispatches, 1,
    "foreign override of Trade Stone delegates to prior ItemEffects")
  stone.effect = priorEffect
end)

test("EXP.SHARE grant is idempotent, repairs v0.1.75 order, and never sets story flags", function()
  optionValues.experience_mode = "share"
  local flags = { EVENT_BEAT_BROCK = true }
  local save = newSave({ flags = flags, _simulateV75Add = true })
  setGame(save)
  events:emit("game.ready", { game = Game })
  eq(save.inventory.SCOTTS_EXP_SHARE, 1, "EXP.SHARE is granted once")
  eq(#save._order, 1, "v0.1.75 duplicate item-order rows are normalized")
  eq(save._order[1], "SCOTTS_EXP_SHARE", "EXP.SHARE keeps one order row")
  events:emit("save.loaded", { game = Game, save = save })
  events:emit("map.entered", { game = Game, save = save })
  eq(save.inventory.SCOTTS_EXP_SHARE, 1, "repeated lifecycle events are idempotent")
  eq(save.flags, flags, "story flag table identity is untouched")
  eq(save.flags.EVENT_BEAT_BROCK, true, "existing story flag is untouched")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "vanilla EXP.ALL story event is not forged")
  eq(mod.exports.experience.itemUnlocked, true, "grant state reports unlocked")
  eq(mod.exports.experience.pending, false, "grant state is not pending")
end)

test("full bag defers EXP.SHARE and retries without losing or forging progression", function()
  optionValues.experience_mode = "share"
  local flags = { EVENT_GOT_POKEDEX = true }
  local save = newSave({ flags = flags, _rejectAdds = true })
  setGame(save)
  events:emit("game.ready", { game = Game })
  eq(save.inventory.SCOTTS_EXP_SHARE, nil, "full bag does not overwrite inventory")
  eq(mod.exports.experience.pending, true, "full bag leaves grant pending")
  eq(mod.exports.experience.reason, "bag_full", "full-bag reason is published")
  save._rejectAdds = nil
  events:emit("map.entered", { game = Game, save = save })
  eq(save.inventory.SCOTTS_EXP_SHARE, 1, "later lifecycle event retries grant")
  eq(mod.exports.experience.pending, false, "successful retry clears pending state")
  eq(save.flags, flags, "full-bag retry preserves the story flag table")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "full-bag retry does not forge EXP.ALL event")

  local pcSave = newSave({ pcItems = { SCOTTS_EXP_SHARE = 1 } })
  setGame(pcSave)
  events:emit("save.loaded", { game = Game, save = pcSave })
  eq(pcSave.inventory.SCOTTS_EXP_SHARE, 1,
    "an EXP.SHARE recovered from the PC moves into the bag")
  eq(pcSave.pcItems.SCOTTS_EXP_SHARE, nil,
    "successful PC recovery removes the old PC copy")
  eq((pcSave.inventory.SCOTTS_EXP_SHARE or 0)
      + (pcSave.pcItems.SCOTTS_EXP_SHARE or 0), 1,
    "PC recovery preserves exactly one total copy")
  eq(mod.exports.experience.reason, "moved_from_pc", "PC recovery is reported")

  local fullPcSave = newSave({
    pcItems = { SCOTTS_EXP_SHARE = 1 },
    _rejectAdds = true,
  })
  setGame(fullPcSave)
  events:emit("save.loaded", { game = Game, save = fullPcSave })
  eq(fullPcSave.inventory.SCOTTS_EXP_SHARE, nil,
    "full bag does not create a second PC-recovery copy")
  eq(fullPcSave.pcItems.SCOTTS_EXP_SHARE, 1,
    "full bag retains the recoverable PC copy")
  eq(mod.exports.experience.reason, "in_pc_bag_full",
    "deferred PC recovery publishes its reason")
end)

test("vanilla EXP mode is an exact one-call passthrough", function()
  optionValues.experience_mode = "vanilla"
  local flags = { EVENT_BEAT_MISTY = true }
  local save = newSave({ inventory = { EXP_ALL = 4 }, flags = flags })
  local lead = { species = "PIKACHU", hp = 12 }
  local ctx = battleCtx(save, lead, { lead })
  local calls, passed = 0
  local result = pack(hooks["battle.exp_award"](function(received)
    calls = calls + 1
    passed = received
    return "vanilla", nil, 17, false
  end, ctx))
  eq(calls, 1, "vanilla downstream call count")
  eq(passed, ctx, "vanilla preserves ctx identity")
  eq(result.n, 4, "vanilla preserves result arity")
  eq(result[1], "vanilla", "vanilla preserves first result")
  eq(result[2], nil, "vanilla preserves nil result")
  eq(result[3], 17, "vanilla preserves numeric result")
  eq(result[4], false, "vanilla preserves false result")
  eq(save.inventory.EXP_ALL, 4, "vanilla preserves real EXP.ALL count")
  eq(save.flags, flags, "vanilla preserves story state")
end)

test("lead-only EXP supplies one active recipient and restores a real EXP.ALL count", function()
  optionValues.experience_mode = "lead"
  local lead = { species = "PIKACHU", hp = 12 }
  local bench = { species = "PIDGEY", hp = 9 }
  local save = newSave({
    inventory = { EXP_ALL = 7 },
    party = { lead, bench },
    flags = { EVENT_BEAT_LT_SURGE = true },
  })
  local ctx, applyShare = battleCtx(save, lead, { lead, bench })
  local calls = 0
  local result = pack(hooks["battle.exp_award"](function(received)
    calls = calls + 1
    check(received ~= ctx, "lead mode copies ctx")
    eq(received.battle, ctx.battle, "lead ctx keeps battle")
    eq(received.applyShare, applyShare, "lead ctx keeps applyShare")
    eq(received.compatibilitySentinel, "kept", "lead ctx keeps extension fields")
    eq(received.participants, 1, "lead divisor is one")
    eq(#received.alive, 1, "lead has one recipient")
    eq(received.alive[1], lead, "active Pokemon is lead recipient")
    eq(save.inventory.EXP_ALL, nil, "lead temporarily suppresses EXP.ALL")
    return "lead", nil, 23
  end, ctx))
  eq(calls, 1, "lead downstream call count")
  eq(result.n, 3, "lead preserves result arity")
  eq(result[2], nil, "lead preserves nil return")
  eq(save.inventory.EXP_ALL, 7, "lead restores real EXP.ALL count")
  eq(ctx.participants, 4, "lead leaves original ctx unchanged")
  eq(#ctx.alive, 2, "lead leaves original recipient list unchanged")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "lead mode does not forge story state")
end)

test("party EXP supplies every healthy party member at a full-share divisor", function()
  optionValues.experience_mode = "party"
  local lead = { species = "PIKACHU", hp = 12 }
  local bench = { species = "PIDGEY", hp = 9 }
  local fainted = { species = "RATTATA", hp = 0 }
  local save = newSave({ party = { lead, fainted, bench }, flags = {} })
  local ctx, applyShare = battleCtx(save, lead, { lead })
  local calls = 0
  hooks["battle.exp_award"](function(received)
    calls = calls + 1
    eq(received.participants, 1, "party full-share divisor is one")
    eq(received.applyShare, applyShare, "party ctx keeps applyShare")
    eq(#received.alive, 2, "party excludes fainted Pokemon")
    eq(received.alive[1], lead, "party keeps first healthy Pokemon")
    eq(received.alive[2], bench, "party keeps second healthy Pokemon")
    eq(save.inventory.EXP_ALL, nil, "party keeps absent EXP.ALL absent")
  end, ctx)
  eq(calls, 1, "party downstream call count")
  eq(save.inventory.EXP_ALL, nil, "party restores absent EXP.ALL as nil")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "party mode does not forge story state")
end)

test("share EXP uses vanilla ctx with temporary EXP.ALL and restores on success or error", function()
  optionValues.experience_mode = "share"
  local lead = { species = "PIKACHU", hp = 12 }
  local save = newSave({ party = { lead }, flags = {} })
  local ctx = battleCtx(save, lead, { lead })
  local calls = 0
  local result = pack(hooks["battle.exp_award"](function(received)
    calls = calls + 1
    eq(received, ctx, "share keeps vanilla ctx identity")
    eq(save.inventory.EXP_ALL, 1, "share presents temporary EXP.ALL to vanilla")
    return "share", nil, 31
  end, ctx))
  eq(calls, 1, "share downstream call count")
  eq(result.n, 3, "share preserves result arity")
  eq(result[2], nil, "share preserves nil return")
  eq(save.inventory.EXP_ALL, nil, "share removes temporary absent EXP.ALL")
  eq(save.inventory.SCOTTS_EXP_SHARE, 1, "share mode also owns its visible item")

  save.inventory.EXP_ALL = 9
  local ok, err = pcall(function()
    hooks["battle.exp_award"](function()
      eq(save.inventory.EXP_ALL, 1, "share error path sees temporary EXP.ALL")
      error("award exploded")
    end, ctx)
  end)
  eq(ok, false, "downstream EXP error is rethrown")
  check(tostring(err):find("award exploded", 1, true),
    "downstream EXP error text is preserved")
  eq(save.inventory.EXP_ALL, 9, "share error restores real EXP.ALL count")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "share mode does not forge story state")
end)

test("v0.1.75 BagMenu fallback consumes Trade Stone and evolves via ITEM", function()
  optionValues.bag_pockets = true
  resetUi()
  ItemEffects.dispatches = 0
  local mon = { species = "KADABRA", hp = 20 }
  local save = newSave({ inventory = { SCOTTS_TRADE_STONE = 1 } })
  local game = fieldGame(save)
  local screen = registrations.screens.BagMenu.new(game, {})
  screen.onChoose({ value = "SCOTTS_TRADE_STONE" })
  check(type(menuAction("USE")) == "function", "field fallback exposes USE")
  menuAction("USE")()
  check(type(ui.partyOpts) == "table", "field fallback requests a target")
  ui.partyOpts.onSwitch(mon)
  eq(save.inventory.SCOTTS_TRADE_STONE, nil,
    "successful v0.1.75 fallback consumes one Trade Stone")
  eq(screen.closed, true, "successful v0.1.75 fallback closes the bag")
  eq(#ui.evolutions, 1, "successful v0.1.75 fallback starts evolution")
  eq(ui.evolutions[1].mon, mon, "fallback evolves selected Pokemon")
  eq(ui.evolutions[1].target, "ALAKAZAM", "fallback chooses trade target")
  eq(ui.evolutions[1].via, "ITEM", "fallback evolution is non-cancelable ITEM use")
  eq(ItemEffects.dispatches, 0,
    "v0.1.75 fallback does not depend on registered-effect dispatch")
end)

test("Trade Stone fallback refuses invalid targets and battle use without consumption", function()
  optionValues.bag_pockets = true
  resetUi()
  local invalid = { species = "RATTATA", hp = 20 }
  local fieldSave = newSave({ inventory = { SCOTTS_TRADE_STONE = 2 } })
  local field = fieldGame(fieldSave)
  local fieldScreen = registrations.screens.BagMenu.new(field, {})
  fieldScreen.onChoose({ value = "SCOTTS_TRADE_STONE" })
  menuAction("USE")()
  ui.partyOpts.onSwitch(invalid)
  eq(fieldSave.inventory.SCOTTS_TRADE_STONE, 2,
    "invalid target does not consume Trade Stone")
  eq(#ui.evolutions, 0, "invalid target does not evolve")
  check(ui.text and ui.text.message:find("won't", 1, true),
    "invalid fallback target reports no effect")

  resetUi()
  local battleSave = newSave({ inventory = { SCOTTS_TRADE_STONE = 1 } })
  local battle = fieldGame(battleSave)
  local battleScreen = registrations.screens.BagMenu.new(battle, { battle = true })
  battleScreen.onChoose({ value = "SCOTTS_TRADE_STONE" })
  check(type(ui.partyOpts) == "table",
    "v0.1.75 battle flow asks for a target before effect refusal")
  ui.partyOpts.onSwitch({ species = "KADABRA", hp = 20 })
  eq(battleSave.inventory.SCOTTS_TRADE_STONE, 1,
    "battle refusal does not consume Trade Stone")
  eq(#ui.evolutions, 0, "battle refusal does not evolve")
  check(ui.text and type(ui.text.message) == "string"
      and #ui.text.message > 0,
    "battle fallback reports that the item cannot be used")
end)

test("v0.1.75 Trade Stone fallback remains available when bag pockets are off", function()
  optionValues.bag_pockets = false
  resetUi()
  local save = newSave({ inventory = { SCOTTS_TRADE_STONE = 1 } })
  local screen = registrations.screens.BagMenu.new(fieldGame(save), {})
  screen.onChoose({ value = "SCOTTS_TRADE_STONE" })
  check(type(menuAction("USE")) == "function",
    "disabling pocket tabs must not disable v0.1.75 Trade Stone use")
  eq(ui.baseChoices, 1,
    "pockets-off behavior delegates through the native v0.1.75 bag")
  menuAction("USE")()
  check(type(ui.partyOpts) == "table",
    "narrow ItemEffects fallback still marks Trade Stone as targeted")
end)

for _, row in ipairs(tests) do
  local ok, err = xpcall(row.body, function(value)
    if debug and debug.traceback then return debug.traceback(tostring(value), 2) end
    return tostring(value)
  end)
  if ok then
    io.write("ok - ", row.name, "\n")
  else
    failures[#failures + 1] = row.name .. "\n" .. tostring(err)
    io.write("not ok - ", row.name, "\n")
  end
end

if #failures > 0 then
  io.stderr:write(table.concat(failures, "\n\n"), "\n")
  error(("%d of %d focused tests failed (%d checks)"):format(
    #failures, #tests, checks), 0)
end

print(("experience/trade: %d checks passed across %d cases")
  :format(checks, #tests))
