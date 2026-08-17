-- Scott's Tweaks: a small, ROM-free PACK + POKeGEAR navigation feature.
--
-- Red remains authoritative.  The native ITEM/ITEMS row keeps its original
-- callback and is presented as PACK; Scott's existing Red inventory pocket
-- projection supplies the four pockets.  POKeGEAR is a separate Start-menu
-- row with a live clock and Red's native Kanto Town Map.  No Pokemon Gold ROM,
-- extracted image, custom renderer, or second-screen presenter is involved.

local OPTION_KEY = "gen2_menus"
local POKEGEAR_SCREEN = "ScottsPokegear"
local POKEGEAR_ITEM_ID = "scotts_tweaks.pokegear"
local API_VERSION = 2

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
  if mod and mod.options and type(mod.options.get) == "function" then
    local ok, value = pcall(mod.options.get, mod.options, OPTION_KEY)
    if ok then return enabledValue(value) end
  end
  return false
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

local function clockLabel(mod, game)
  local stamp = os.time()
  local formatter = mod and mod.datetime
  if formatter and type(formatter.time) == "function" then
    local ok, value = pcall(formatter.time, formatter, game, stamp)
    if ok and type(value) == "string" and value ~= "" then
      return "CLOCK " .. value
    end
  end
  return "CLOCK " .. os.date("%H:%M", stamp)
end

local function reopenStart(mod, game)
  if mod and mod.ui and type(mod.ui.push) == "function" then
    return mod.ui.push(game, "StartMenu")
  end
end

local function makePokegear(mod, game, Menu)
  local items = {
    { label = clockLabel(mod, game), keepOpen = true },
    {
      label = "KANTO MAP",
      keepOpen = true,
      onSelect = function()
        return mod.ui.push(game, "TownMap")
      end,
    },
  }
  local menu = Menu.new(game, items, {
    tx = 4,
    ty = 5,
    tw = 12,
    onCancel = function() reopenStart(mod, game) end,
  })
  menu.screenId = POKEGEAR_SCREEN

  -- Refresh only the text row.  Menu behavior and the native Kanto map remain
  -- untouched, and the user's global 12/24-hour preference is respected.
  local baseUpdate = menu.update
  menu.update = function(self, dt)
    self.items[1].label = clockLabel(mod, game)
    return baseUpdate(self, dt)
  end
  return menu
end

local function decorateStartItems(items, game, mod)
  local out = {}
  local packAt
  local hasPokegear = false

  for _, original in ipairs(items or {}) do
    local item = copyItem(original)
    if isPackRow(item) and not packAt then
      -- Presentation-only rename: the exact original callback and all other
      -- descriptor fields survive on the shallow copy.
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
      desc = { "Clock and", "Kanto map" },
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

  local okMenu, Menu = pcall(require, "src.ui.Menu")
  if not okMenu or type(Menu) ~= "table" or type(Menu.new) ~= "function" then
    error("Pokegear needs Gen1Recomp's native Menu: " .. tostring(Menu), 0)
  end

  local screens = mod.content.screens
  local factory = {
    new = function(game) return makePokegear(mod, game, Menu) end,
  }
  if screens:get(POKEGEAR_SCREEN) ~= nil then
    screens:override(POKEGEAR_SCREEN, factory)
  else
    screens:register(POKEGEAR_SCREEN, factory)
  end

  -- Run outside Modern UI's Start grouping wrapper.  PACK and POKeGEAR stay
  -- on the normal root menu, while Modern UI can continue owning every screen
  -- it already supports, including the native Bag and Town Map.
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
    getStatus = function()
      local enabled = optionEnabled(mod, context)
      return {
        apiVersion = API_VERSION,
        installed = true,
        enabled = enabled,
        active = enabled,
        ready = true,
        optionKey = OPTION_KEY,
        style = "red_native_pack_pokegear",
        controller = "red_native_callbacks",
        modernUi = "coexists",
        presenter = "ui_canvas_only",
        romImport = false,
        screenIds = { pokegear = POKEGEAR_SCREEN },
      }
    end,
  }
  mod.exports = type(mod.exports) == "table" and mod.exports or {}
  mod.exports.gen2Ui = api
  return api
end
