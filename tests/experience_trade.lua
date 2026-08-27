-- Focused ROM-free contracts for Scott's Tweaks 0.13.0.
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
  local awards = {}
  local applyShare = function(mon, split, announce)
    awards[#awards + 1] = {
      mon = mon,
      split = split,
      announce = announce,
    }
  end
  return {
    battle = { game = setGame(save), player = { mon = lead } },
    participants = 4,
    alive = alive or {},
    applyShare = applyShare,
    compatibilitySentinel = "kept",
  }, applyShare, awards
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

test("EXP.SHARE schema is one simple OFF/BUDDY/ALL choice", function()
  local row = schemaRow("experience_mode")
  check(type(row) == "table", "EXP. SHARE option is registered")
  eq(row.type, "choice", "EXP. SHARE option type")
  eq(row.label, "EXP. SHARE", "EXP. SHARE option label")
  eq(row.default, "vanilla", "EXP. SHARE defaults off")
  eq(#row.choices, 3, "EXP. SHARE choice count")
  local seen = {}
  for _, choice in ipairs(row.choices) do seen[choice[2]] = choice[1] end
  eq(seen.vanilla, "OFF", "off choice")
  eq(seen.buddy, "BUDDY", "buddy choice")
  eq(seen.all, "ALL", "all choice")
  eq(seen.lead, nil, "legacy lead is not a duplicate visible choice")
  eq(seen.party, nil, "legacy party is not a duplicate visible choice")
  eq(seen.share, nil, "legacy share is not a duplicate visible choice")
end)

test("caught-species marker enables the engine-owned battle glyph", function()
  local downstream = 0
  local visible = hooks["battle.caught_marker_visible"](function()
    downstream = downstream + 1
    return false
  end, { kind = "wild" })
  eq(downstream, 1, "caught marker composes with the existing hook chain")
  eq(visible, true, "Scott's Tweaks enables the native caught marker")
  eq(mod.exports.caughtMarker.nativeHook, true,
    "caught marker publishes its native-hook ownership")
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
  optionValues.experience_mode = "all"
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
  optionValues.experience_mode = "buddy"
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

test("Buddy splits one award between the active Pokemon and its next eligible mate", function()
  optionValues.experience_mode = "buddy"
  local wrap = { species = "PIDGEY", hp = 9 }
  local fainted = { species = "RATTATA", hp = 0 }
  local active = { species = "PIKACHU", hp = 12 }
  local egg = { species = "TOGEPI", hp = 1, isEgg = true }
  local buddy = { species = "BULBASAUR", hp = 15 }
  local save = newSave({
    inventory = { EXP_ALL = 7 },
    party = { wrap, fainted, active, egg, buddy },
    flags = { EVENT_BEAT_LT_SURGE = true },
  })
  local ctx, _, awards = battleCtx(save, active, { wrap, active, buddy })
  ctx.participants = 9
  local downstream = 0
  hooks["battle.exp_award"](function()
    downstream = downstream + 1
  end, ctx)
  eq(downstream, 0, "Buddy replaces the vanilla distribution")
  eq(#awards, 2, "Buddy has exactly two recipients")
  eq(awards[1].mon, active, "active Pokemon receives the first share")
  eq(awards[2].mon, buddy, "next eligible slot receives the buddy share")
  eq(awards[1].split, 2, "active gets half of one award")
  eq(awards[2].split, 2, "buddy gets half of one award")
  eq(awards[1].announce, true, "active gain uses the native message")
  eq(awards[2].announce, true, "buddy gain uses the native message")
  eq(ctx.participants, 9, "historical participant count is not mutated")
  eq(#ctx.alive, 3, "historical participant list is not mutated")
  eq(save.inventory.EXP_ALL, 7, "real EXP.ALL count is never edited")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "Buddy does not forge story state")
  eq(save.inventory.SCOTTS_EXP_SHARE, 1,
    "Buddy mode owns the visible EXP.SHARE item")
end)

test("Buddy honors the Gen 2 battle.exp_award context shape", function()
  optionValues.experience_mode = "buddy"
  local first = { species = "CHIKORITA", hp = 16 }
  local active = { species = "PIDGEY", hp = 12 }
  local buddy = { species = "WOOPER", hp = 14 }
  local save = newSave({ party = { first, active, buddy }, flags = {} })
  local ctx, _, awards = battleCtx(save, first, { first })
  ctx.battle = {
    -- Gen 2 Battle intentionally has no .game and stores these directly.
    save = save,
    data = Game.data,
    party = save.party,
    player = active,
  }
  local downstream = 0
  hooks["battle.exp_award"](function() downstream = downstream + 1 end, ctx)
  eq(downstream, 0, "Gen 2 Buddy replaces vanilla distribution")
  eq(#awards, 2, "Gen 2 Buddy has exactly two recipients")
  eq(awards[1].mon, active, "Gen 2 direct player record is the active recipient")
  eq(awards[2].mon, buddy, "Gen 2 Buddy uses the next eligible party slot")
  eq(awards[1].split, 2, "Gen 2 active receives half of one award")
  eq(awards[2].split, 2, "Gen 2 buddy receives half of one award")
  eq(save.inventory.SCOTTS_EXP_SHARE, 1,
    "Gen 2 direct save/data shape still owns the indicator item")
end)

test("Buddy handles one eligible Pokemon, a fainted active, and party wrap", function()
  optionValues.experience_mode = "buddy"
  local only = { species = "PIKACHU", hp = 12 }
  local fainted = { species = "RATTATA", hp = 0 }
  local egg = { species = "TOGEPI", hp = 1, isEgg = true }
  local singleSave = newSave({ party = { only, fainted, egg }, flags = {} })
  local singleCtx, _, singleAwards = battleCtx(singleSave, only, { only })
  hooks["battle.exp_award"](function() error("must not delegate") end,
    singleCtx)
  eq(#singleAwards, 1, "single healthy party has one recipient")
  eq(singleAwards[1].mon, only, "single healthy Pokemon receives EXP")
  eq(singleAwards[1].split, 1, "single healthy Pokemon gets the full award")

  local first = { species = "BULBASAUR", hp = 15 }
  local lastActive = { species = "CHARMANDER", hp = 17 }
  local wrapSave = newSave({ party = { first, fainted, lastActive }, flags = {} })
  local wrapCtx, _, wrapAwards = battleCtx(wrapSave, lastActive, { lastActive })
  hooks["battle.exp_award"](function() error("must not delegate") end,
    wrapCtx)
  eq(#wrapAwards, 2, "last active slot still has two Buddy recipients")
  eq(wrapAwards[1].mon, lastActive, "last active slot remains first recipient")
  eq(wrapAwards[2].mon, first, "Buddy wraps to the first eligible slot")

  local faintActive = { species = "SQUIRTLE", hp = 0 }
  local survivor = { species = "PIDGEY", hp = 8 }
  local faintSave = newSave({ party = { faintActive, survivor }, flags = {} })
  local faintCtx, _, faintAwards = battleCtx(
    faintSave, faintActive, { faintActive })
  hooks["battle.exp_award"](function() error("must not delegate") end,
    faintCtx)
  eq(#faintAwards, 1, "fainted active is excluded")
  eq(faintAwards[1].mon, survivor, "next healthy Pokemon receives the award")
  eq(faintAwards[1].split, 1, "sole survivor gets a full award")
end)

test("All splits one award evenly across every eligible party Pokemon", function()
  optionValues.experience_mode = "all"
  local lead = { species = "PIKACHU", hp = 12 }
  local fainted = { species = "RATTATA", hp = 0 }
  local egg = { species = "TOGEPI", hp = 1, isEgg = true }
  local bench = { species = "PIDGEY", hp = 9 }
  local third = { species = "BULBASAUR", hp = 14 }
  local save = newSave({
    inventory = { EXP_ALL = 5 },
    party = { lead, fainted, egg, bench, third },
    flags = {},
  })
  local ctx, _, awards = battleCtx(save, lead, { lead })
  ctx.participants = 6
  local downstream = 0
  hooks["battle.exp_award"](function() downstream = downstream + 1 end, ctx)
  eq(downstream, 0, "All replaces the vanilla distribution")
  eq(#awards, 3, "All excludes fainted Pokemon and eggs")
  eq(awards[1].mon, lead, "All preserves first eligible party order")
  eq(awards[2].mon, bench, "All preserves second eligible party order")
  eq(awards[3].mon, third, "All preserves third eligible party order")
  for index, award in ipairs(awards) do
    eq(award.split, 3, "All recipient " .. index .. " gets one-third")
    eq(award.announce, true,
      "All recipient " .. index .. " uses the native message")
  end
  eq(save.inventory.EXP_ALL, 5, "All never edits the real EXP.ALL count")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "All does not forge story state")
  eq(save.inventory.SCOTTS_EXP_SHARE, 1,
    "All mode owns the visible EXP.SHARE item")
end)

test("legacy saved EXP choices migrate behavior without duplicate menu choices", function()
  local lead = { species = "PIKACHU", hp = 12 }
  local buddy = { species = "PIDGEY", hp = 9 }
  local third = { species = "BULBASAUR", hp = 14 }
  for _, legacy in ipairs({ "lead", "party", "share" }) do
    optionValues.experience_mode = legacy
    local save = newSave({ party = { lead, buddy, third }, flags = {} })
    local ctx, _, awards = battleCtx(save, lead, { lead })
    hooks["battle.exp_award"](function() error("must not delegate") end, ctx)
    local expectedMode = legacy == "lead" and "buddy" or "all"
    local expectedCount = legacy == "lead" and 2 or 3
    eq(mod.exports.experience.mode, expectedMode,
      legacy .. " save reports its canonical mode")
    eq(#awards, expectedCount,
      legacy .. " save keeps an intentional recipient mapping")
    eq(save.inventory.SCOTTS_EXP_SHARE, 1,
      legacy .. " save unlocks the indicator item")
  end
end)

test("sharing errors propagate without touching EXP.ALL or story state", function()
  optionValues.experience_mode = "all"
  local lead = { species = "PIKACHU", hp = 12 }
  local bench = { species = "PIDGEY", hp = 9 }
  local flags = { EVENT_BEAT_SABRINA = true }
  local save = newSave({
    inventory = { EXP_ALL = 9 }, party = { lead, bench }, flags = flags,
  })
  local ctx = battleCtx(save, lead, { lead })
  local calls = 0
  ctx.applyShare = function()
    calls = calls + 1
    if calls == 2 then error("award exploded") end
  end
  local ok, err = pcall(function()
    hooks["battle.exp_award"](function() error("must not delegate") end, ctx)
  end)
  eq(ok, false, "applyShare error is rethrown")
  check(tostring(err):find("award exploded", 1, true),
    "applyShare error text is preserved")
  eq(calls, 2, "sharing stops at the failing recipient")
  eq(save.inventory.EXP_ALL, 9, "error path never edits real EXP.ALL")
  eq(save.flags, flags, "error path preserves story table identity")
  eq(save.flags.EVENT_GOT_EXP_ALL, nil, "error path forges no story state")
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
