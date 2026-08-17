-- ROM-free contracts for Scott's Tweaks' built-in PACK + POKeGEAR feature.

local root = arg and arg[1] or "."
local checks = 0

local function check(value, message)
  checks = checks + 1
  if not value then error(message or ("check " .. checks .. " failed"), 2) end
end

local function eq(actual, expected, message)
  checks = checks + 1
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local pushed = {}
local fakeMenu = {}
function fakeMenu.new(game, items, opts)
  local menu = {
    game = game,
    items = items,
    opts = opts or {},
    index = 1,
    updates = 0,
  }
  function menu:update(_dt) self.updates = self.updates + 1 end
  function menu:draw() return "native-menu" end
  return menu
end

package.loaded["src.ui.Menu"] = nil
package.preload["src.ui.Menu"] = function() return fakeMenu end

local function newHarness(initial)
  local values = { gen2_menus = initial == true }
  local registered = {}
  local hooks = {}
  local mod = {
    id = "voxel_run_bridge",
    exports = {},
    datetime = {
      time = function(_, _game, _stamp) return "5:07 PM" end,
    },
    ui = {
      push = function(game, id)
        pushed[#pushed + 1] = { game = game, id = id }
        return true
      end,
    },
    content = {
      screens = {
        get = function(_, id) return registered[id] end,
        register = function(_, id, factory)
          check(registered[id] == nil, "screen registered only once")
          registered[id] = factory
        end,
        override = function(_, id, factory)
          check(registered[id] ~= nil, "screen override has prior factory")
          registered[id] = factory
        end,
      },
    },
    hooks = {
      wrap = function(_, name, callback, priority)
        hooks[#hooks + 1] = {
          name = name, callback = callback, priority = priority,
        }
      end,
    },
  }
  local context = {
    settings = {
      get = function(_, key) return values[key] end,
    },
  }
  return mod, context, values, registered, hooks
end

local installer = assert(dofile(root .. "/modules/gen2_ui.lua"))
local mod, context, values, registered, hooks = newHarness(false)
local api = installer(mod, context)

eq(api.apiVersion, 2, "Pokegear API version")
eq(api.optionKey, "gen2_menus", "legacy option key is retained")
eq(api.getEnabled(), false, "option defaults off")
eq(api.getStatus().romImport, false, "feature has no ROM import")
eq(api.getStatus().ready, true, "built-in feature is always ready")
eq(#hooks, 1, "one Start-menu hook")
eq(hooks[1].name, "ui.start_menu.items", "Start hook name")
eq(hooks[1].priority, 100, "Pokegear stays outside Modern grouping")
check(registered.ScottsPokegear ~= nil, "Pokegear screen registered")

local itemCallback = function() return "bag" end
local base = {
  { label = "POKéMON" },
  { label = "ITEM", onSelect = itemCallback, custom = "preserved" },
  { label = "MODS" },
}
local nextCalls = 0
local function nextFn(_game, rows)
  nextCalls = nextCalls + 1
  return rows
end
local game = { id = "red" }

local off = hooks[1].callback(nextFn, game, base)
eq(off, base, "option-off preserves exact prior list")
eq(base[2].label, "ITEM", "option-off does not rename ITEM")
eq(nextCalls, 1, "downstream hook called once")

values.gen2_menus = true
local on = hooks[1].callback(nextFn, game, base)
eq(#on, 4, "one Pokegear row added")
eq(on[2].label, "PACK", "ITEM is presented as PACK")
eq(on[2].onSelect, itemCallback, "PACK keeps exact Red bag callback")
eq(on[2].custom, "preserved", "PACK keeps custom descriptor fields")
eq(on[3].id, "scotts_tweaks.pokegear", "stable Pokegear row id")
eq(on[3].label, "POKéGEAR", "Pokegear follows PACK")
eq(base[2].label, "ITEM", "source descriptor is never mutated")
on[3].onSelect()
eq(pushed[#pushed].id, "ScottsPokegear", "Pokegear row opens screen")

for _, alias in ipairs({ "ITEMS", "PACK" }) do
  local aliasRows = hooks[1].callback(nextFn, game,
    { { label = alias, onSelect = itemCallback } })
  eq(aliasRows[1].label, "PACK", alias .. " presents as PACK")
  eq(aliasRows[1].onSelect, itemCallback, alias .. " callback preserved")
  eq(aliasRows[2].label, "POKéGEAR", alias .. " gets Pokegear after it")
end

local idRows = hooks[1].callback(nextFn, game,
  { { id = "items", label = "BAG", onSelect = itemCallback } })
eq(idRows[1].label, "PACK", "items id is recognized independent of label")
eq(idRows[2].label, "POKéGEAR", "id-based PACK gets Pokegear after it")

local existing = hooks[1].callback(nextFn, game, {
  { label = "ITEM" },
  { id = "scotts_tweaks.pokegear", label = "POKéGEAR" },
})
eq(#existing, 2, "existing Pokegear row is not duplicated")

local gear = registered.ScottsPokegear.new(game)
eq(gear.screenId, "ScottsPokegear", "screen identity is stable")
eq(#gear.items, 2, "Pokegear has Clock and Kanto Map")
eq(gear.items[1].label, "CLOCK 5:07 PM", "clock follows engine preference")
eq(gear.items[1].keepOpen, true, "clock row stays open")
eq(gear.items[2].label, "KANTO MAP", "Kanto Map row")
eq(gear.items[2].keepOpen, true, "map opens over Pokegear")
gear.items[2].onSelect()
eq(pushed[#pushed].id, "TownMap", "Pokegear uses Red's native TownMap")
gear.opts.onCancel()
eq(pushed[#pushed].id, "StartMenu", "B from Pokegear reopens Start")
gear:update(0.1)
eq(gear.updates, 1, "native Menu update remains authoritative")
eq(gear.items[1].label, "CLOCK 5:07 PM", "clock refreshes live")

-- A second real entry updates the registered factory rather than failing or
-- adding any process-global image/resource owner.
local api2 = installer(mod, context)
eq(api2.apiVersion, 2, "second entry stays valid")
eq(#hooks, 2, "fresh Loader facade receives one fresh hook")
eq(registered.ScottsPokegear.new(game).screenId, "ScottsPokegear",
  "second entry replaces the screen factory safely")

local manifestFile = assert(io.open(root .. "/manifest.json", "rb"))
local manifest = manifestFile:read("*a")
manifestFile:close()
check(not manifest:find("optional_imports", 1, true),
  "manifest has no imported-ROM contract")
check(not manifest:lower():find("pokemon gold rom", 1, true),
  "manifest does not ask for Pokemon Gold")

io.write(("gen2_ui: %d checks passed\n"):format(checks))
