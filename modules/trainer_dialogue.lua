-- Offline journey-aware dialogue and rematch memory for Trainer Forfeit.
-- Incorporated from Trainer Forfeit 0.3.0 (MIT) and adapted to the Scott's
-- Tweaks namespace. See THIRD_PARTY_NOTICES.md.
--
-- This deliberately is not a network or generative-AI client.  It derives a
-- small, deterministic context from the current save and selects authored
-- templates.  The same save state always produces the same line, it works on
-- Android with no connection, and no player data leaves the game.

local FORMAT = 1
local MEMORY_KEY = "trainer_memory"
local RECENT_LIMIT = 8
local RECENT_WINDOW = 12
local NEAR_DISTANCE = 12

local FALLBACK_BADGES = {
  "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
  "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
}

local okStrings, Strings = pcall(require, "src.core.Strings")

local function S(source, ...)
  if okStrings and Strings then
    local ok, value = pcall(Strings, source, ...)
    if ok and type(value) == "string" then return value end
  end
  local ok, value = pcall(string.format, source, ...)
  return ok and value or source
end

local function integer(value, fallback, minimum, maximum)
  value = math.floor(tonumber(value) or fallback or 0)
  if minimum and value < minimum then value = minimum end
  if maximum and value > maximum then value = maximum end
  return value
end

local function ascii(value, fallback)
  value = tostring(value or fallback or "TRAINER")
  value = value:gsub("[^\032-\126]", "?")
  value = value:gsub("[%c]", " "):gsub("%s+", " ")
  value = value:match("^%s*(.-)%s*$") or ""
  if value == "" then value = fallback or "TRAINER" end
  return value
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
  return out
end

local function position(npc)
  local def = type(npc) == "table" and npc.def or nil
  local x = tonumber(type(npc) == "table" and npc.cellX) or tonumber(def and def.x)
  local y = tonumber(type(npc) == "table" and npc.cellY) or tonumber(def and def.y)
  if not x or not y then return nil, nil end
  return math.floor(x), math.floor(y)
end

local function mapIdOf(game, npc)
  if type(npc) == "table" and type(npc.id) == "string" then
    local fromId = npc.id:match("^(.-)_obj_%d+$")
    if fromId and fromId ~= "" then return fromId end
  end
  if type(npc) == "table" and type(npc.mapId) == "string" then
    return npc.mapId
  end
  local world = game and game.overworld
  local map = world and world.map
  return (map and (map.id or (map.def and map.def.id))) or "UNKNOWN_MAP"
end

local function trainerKey(game, npc, trainerClass, partyIndex)
  if type(npc) == "table" and type(npc.id) == "string" and npc.id ~= "" then
    return npc.id
  end
  local x, y = position(npc)
  return table.concat({
    mapIdOf(game, npc), ascii(trainerClass, "OPP_TRAINER"),
    tostring(integer(partyIndex, 1, 1)), tostring(x or "?"), tostring(y or "?"),
  }, "|")
end

local function newMemory()
  return { format = FORMAT, sequence = 0, trainers = {}, recentWins = {} }
end

local function normalizeMemory(value)
  if type(value) ~= "table" then value = newMemory() end
  value.format = FORMAT
  value.sequence = integer(value.sequence, 0, 0)
  if type(value.trainers) ~= "table" then value.trainers = {} end
  if type(value.recentWins) ~= "table" then value.recentWins = {} end
  return value
end

local function badgeCount(game)
  local save = game and game.save or {}
  local inventory = type(save.inventory) == "table" and save.inventory or {}
  local rows = game and game.data and game.data.constants
    and game.data.constants.badges
  if type(rows) ~= "table" or #rows == 0 then rows = FALLBACK_BADGES end
  local count = 0
  for _, row in ipairs(rows) do
    local id = type(row) == "table" and (row.item or row.id) or row
    if id and inventory[id] then count = count + 1 end
  end
  return count
end

local function partySummary(game)
  local party = game and game.save and game.save.party or {}
  local sum, count, strongestLevel, strongestSpecies = 0, 0, -1, nil
  for _, mon in ipairs(type(party) == "table" and party or {}) do
    if type(mon) == "table" and type(mon.species) == "string" then
      local level = integer(mon.level, 1, 1, 100)
      sum, count = sum + level, count + 1
      if level > strongestLevel then
        strongestLevel, strongestSpecies = level, mon.species
      end
    end
  end
  local average = count > 0 and math.floor(sum / count + 0.5) or 0
  local name = strongestSpecies
  local def = game and game.data and game.data.pokemon
    and strongestSpecies and game.data.pokemon[strongestSpecies]
  if type(def) == "table" and type(def.name) == "string" then name = def.name end
  return {
    count = count, average = average,
    strongestSpecies = strongestSpecies,
    strongestName = ascii(name, "POKEMON"),
    strongestLevel = math.max(0, strongestLevel),
  }
end

local function className(game, trainerClass)
  local def = game and game.data and game.data.trainers
    and game.data.trainers[trainerClass]
  if type(def) == "table" and type(def.name) == "string" then
    return ascii(def.name, "TRAINER")
  end
  local name = tostring(trainerClass or "TRAINER")
    :gsub("^OPP_", ""):gsub("_", " ")
  return ascii(name, "TRAINER")
end

return function(mod, context)
  local api = { installed = true, format = FORMAT }

  local function option(key, fallback)
    if context and context.settings then
      return context.settings:get(key, fallback)
    end
    if mod.options and type(mod.options.get) == "function" then
      local ok, value = pcall(mod.options.get, mod.options, key)
      if ok and value ~= nil then return value end
    end
    return fallback
  end

  local function memory()
    local value
    if mod.save and type(mod.save.get) == "function" then
      value = mod.save:get(MEMORY_KEY)
    end
    local normalized = normalizeMemory(value)
    if normalized ~= value and mod.save and type(mod.save.set) == "function" then
      mod.save:set(MEMORY_KEY, normalized)
    end
    return normalized
  end

  local function nearbyWin(mem, mapId, key, x, y)
    if not x or not y then return nil end
    local rows = mem.recentWins[mapId]
    if type(rows) ~= "table" then return nil end
    for index = #rows, 1, -1 do
      local row = rows[index]
      if type(row) == "table" and row.trainerKey ~= key
          and type(row.x) == "number" and type(row.y) == "number"
          and mem.sequence - integer(row.sequence, 0, 0) <= RECENT_WINDOW
          and math.abs(row.x - x) + math.abs(row.y - y) <= NEAR_DISTANCE then
        return copy(row)
      end
    end
    return nil
  end

  local function selectText(ctx)
    if not ctx.adaptive then
      return S("I've been training\nsince our last battle!")
    end
    if ctx.badges > ctx.badgesAtLast then
      local gained = ctx.badges - ctx.badgesAtLast
      if gained == 1 then
        return S("You earned a new\nBADGE! I trained, too!")
      end
      return S("You earned %d more\nBADGES! I trained, too!", gained)
    end
    if ctx.lastResult == "forfeit" then
      return S("No backing out now!\nI've been training.")
    end
    if ctx.recentNearbyWin then
      local who = className(ctx.game, ctx.recentNearbyWin.trainerClass)
      return S("That %s nearby\nlost to you, too!", who)
        .. "\f" .. S("I've trained for\nour next battle!")
    end
    if ctx.strongestLevel >= ctx.strongestAtLast + 3
        and ctx.strongestSpecies then
      return S("Your %s is L%d now!", ctx.strongestName, ctx.strongestLevel)
        .. "\f" .. S("My POKEMON trained, too!")
    end
    if ctx.rematches > 0 and ctx.lastResult == "win" then
      return S("You beat me before,\nbut I trained harder!")
    end
    if ctx.rematches > 0 and ctx.lastResult == "lose" then
      return S("You're back! I kept\nmy POKEMON sharp.")
    end
    if ctx.badges == 1 then
      return S("You have a BADGE now!\nI've been training!")
    end
    if ctx.badges > 1 then
      return S("You have %d BADGES!\nI trained harder!", ctx.badges)
    end
    if ctx.strongestLevel >= 10 and ctx.strongestSpecies then
      return S("Your %s looks strong!", ctx.strongestName)
        .. "\f" .. S("I've been training, too!")
    end
    return S("I've been training\nsince our last battle!")
  end

  function api.trainerKey(_, game, npc, trainerClass, partyIndex)
    return trainerKey(game, npc, trainerClass, partyIndex)
  end

  function api.context(_, game, npc, trainerClass, partyIndex)
    local mem = memory()
    local key = trainerKey(game, npc, trainerClass, partyIndex)
    local record = type(mem.trainers[key]) == "table" and mem.trainers[key] or {}
    local x, y = position(npc)
    local party = partySummary(game)
    local ctx = {
      game = game, trainerKey = key, mapId = mapIdOf(game, npc),
      trainerClass = trainerClass, partyIndex = integer(partyIndex, 1, 1),
      x = x, y = y, badges = badgeCount(game),
      partyAverage = party.average, strongestSpecies = party.strongestSpecies,
      strongestName = party.strongestName, strongestLevel = party.strongestLevel,
      rematches = integer(record.rematches, 0, 0),
      wins = integer(record.wins, 0, 0), losses = integer(record.losses, 0, 0),
      forfeits = integer(record.forfeits, 0, 0),
      lastResult = record.lastResult,
      badgesAtLast = integer(record.badgesAtLast, badgeCount(game), 0),
      strongestAtLast = integer(record.strongestAtLast,
                                party.strongestLevel, 0, 100),
      adaptive = option("trainer_adaptive_dialogue", true) ~= false,
    }
    ctx.recentNearbyWin = nearbyWin(mem, ctx.mapId, key, x, y)
    ctx.text = selectText(ctx)
    ctx.game = nil
    return ctx
  end

  function api.beforeRematch(self, game, npc, trainerClass, partyIndex)
    local ctx = self:context(game, npc, trainerClass, partyIndex)
    return ctx.text, ctx
  end

  function api.recordBattle(_, game, npc, trainerClass, partyIndex, result, opts)
    opts = type(opts) == "table" and opts or {}
    local mem = memory()
    mem.sequence = mem.sequence + 1
    local key = trainerKey(game, npc, trainerClass, partyIndex)
    local record = type(mem.trainers[key]) == "table" and mem.trainers[key] or {}
    mem.trainers[key] = record
    local x, y = position(npc)
    local mapId = mapIdOf(game, npc)
    local party = partySummary(game)
    local paidForfeit = opts.paidForfeit == true
    local outcome = paidForfeit and "forfeit" or tostring(result or "run")

    record.trainerClass = ascii(trainerClass, "OPP_TRAINER")
    record.partyIndex = integer(partyIndex, 1, 1)
    record.mapId, record.x, record.y = mapId, x, y
    record.battles = integer(record.battles, 0, 0) + 1
    if opts.isRematch then
      record.rematches = integer(record.rematches, 0, 0) + 1
    else
      record.rematches = integer(record.rematches, 0, 0)
    end
    if outcome == "win" then
      record.wins = integer(record.wins, 0, 0) + 1
    elseif outcome == "lose" then
      record.losses = integer(record.losses, 0, 0) + 1
    elseif outcome == "forfeit" then
      record.forfeits = integer(record.forfeits, 0, 0) + 1
    end
    record.lastResult = outcome
    record.lastSequence = mem.sequence
    record.badgesAtLast = badgeCount(game)
    record.partyAverageAtLast = party.average
    record.strongestAtLast = party.strongestLevel
    record.strongestSpeciesAtLast = party.strongestSpecies

    if outcome == "win" and x and y then
      local rows = mem.recentWins[mapId]
      if type(rows) ~= "table" then rows = {}; mem.recentWins[mapId] = rows end
      rows[#rows + 1] = {
        trainerKey = key, trainerClass = record.trainerClass,
        partyIndex = record.partyIndex, x = x, y = y,
        sequence = mem.sequence,
      }
      while #rows > RECENT_LIMIT do table.remove(rows, 1) end
    end

    if mod.save and type(mod.save.set) == "function" then
      mod.save:set(MEMORY_KEY, mem)
    end
    return copy(record)
  end

  function api.boostDescriptor(self, game, npc, trainerClass, partyIndex, partyDef)
    local ctx = self:context(game, npc, trainerClass, partyIndex)
    local rematchNumber = ctx.rematches + 1
    local boost = option("trainer_rematches", true) == false
      and 0 or math.min(10, rematchNumber * 2)
    local originalLevels, levels = {}, {}
    for _, slot in ipairs(type(partyDef) == "table" and partyDef or {}) do
      local level = integer(type(slot) == "table" and slot.level, 1, 1, 100)
      originalLevels[#originalLevels + 1] = level
      levels[#levels + 1] = math.min(100, level + boost)
    end
    return {
      rematchNumber = rematchNumber, completedRematches = ctx.rematches,
      boost = boost, cap = 100, originalLevels = originalLevels,
      levels = levels, partyAverage = ctx.partyAverage,
      reason = boost == 0 and "disabled" or "completed_rematches",
    }
  end

  -- Main owns the shared trainer.party hook and deep-clones its source roster
  -- before applying this descriptor.  Keeping mutation out of this module is
  -- important: vanilla trainer data is shared by every later encounter.
  function api.rematchBoost(self, game, npc, trainerClass, partyIndex, partyDef)
    return self:boostDescriptor(game, npc, trainerClass, partyIndex, partyDef)
  end

  function api.cleanup()
    api.installed = false
  end

  return api
end
