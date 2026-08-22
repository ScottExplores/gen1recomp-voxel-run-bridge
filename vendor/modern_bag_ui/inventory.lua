-- Matching pocket presentation for the native Player PC item lists.
--
-- VENDORED CHANGE (Scott's Tweaks): upstream 0.4.1 also expanded the Bag and
-- PC to 255 distinct stacks and x999 quantities by patching Bag.add,
-- QuantityBox.new and the bagSize constant. The bundled edition is visual
-- only: it leaves all acquisition, storage and quantity limits with the
-- engine (or a lower-priority inventory owner) and composes its presentation
-- over the previously registered PlayerPC factory.

return function(mod, bagScreen, priorPlayerPC)
  local Bag = require("src.inventory.Bag")
  local PlayerPC = require("src.ui.PlayerPC")
  local Strings = require("src.core.Strings")
  local unpackValues = table.unpack or unpack

  local function pack(...)
    return { n = select("#", ...), ... }
  end

  local function construct(factory, builtin, ...)
    if type(factory) == "function" then return factory(...) end
    if type(factory) == "table" and type(factory.new) == "function" then
      return factory.new(...)
    end
    return builtin.new(...)
  end

  local function stackCount(store)
    local count = 0
    for _ in pairs(store or {}) do count = count + 1 end
    return count
  end

  local function sortedIds(_, store)
    local ids = {}
    for id in pairs(store or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
  end

  local playerPC = {
    new = function(game, ...)
      -- VENDORED CHANGE (Scott's Tweaks): never bypass a previously
      -- registered PlayerPC implementation. Extra arguments are retained for
      -- newer engines and are harmless to the original Lua 5.1 controller.
      local menu = construct(priorPlayerPC, PlayerPC, game, ...)
      if type(menu) ~= "table" then return menu end
      if type(rawget(menu, "__modernBagPCMenu")) == "table" then
        return menu
      end

      local actions = {
        {
          index = 1, label = "WITHDRAW ITEM", short = "WITHDRAW",
          store = function() return game.save.pcItems or {} end,
          detailStatus = function() return Strings("STORED") end,
        },
        {
          index = 2, label = "DEPOSIT ITEM", short = "DEPOSIT",
          store = function() return game.save.inventory or {} end,
          filter = function(_, id) return not Bag.isBadge(id) end,
          detailStatus = function() return Strings("CARRIED") end,
        },
        {
          index = 3, label = "TOSS ITEM", short = "TOSS",
          store = function() return game.save.pcItems or {} end,
          detailStatus = function() return Strings("STORED") end,
        },
      }

      for _, action in ipairs(actions) do
        local row = menu.items and menu.items[action.index]
        if row and type(row.onSelect) == "function" then
          local openList = row.onSelect
          row.onSelect = function(...)
            local previousTop = game.stack:top()
            local result = pack(openList(...))
            local list = game.stack:top()
            if list == previousTop or not list
                or type(list.onChoose) ~= "function" then
              return unpackValues(result, 1, result.n)
            end

            if bagScreen and type(bagScreen.decorateList) == "function" then
              bagScreen.decorateList(list, {
                header = "PC",
                label = action.label,
                short = action.short,
                store = action.store,
                order = sortedIds,
                filter = action.filter,
                capacity = function()
                  local field = game.data and game.data.field or {}
                  return ("%d/%d"):format(
                    stackCount(game.save.pcItems),
                    tonumber(field.pcItemCap) or 50)
                end,
                detailStatus = action.detailStatus,
              })
            end
            return unpackValues(result, 1, result.n)
          end
        end
      end

      rawset(menu, "__modernBagPCMenu", {
        owner = mod.id,
        upstreamVersion = "0.4.1",
        nativeLimits = true,
      })
      return menu
    end,
  }

  return {
    playerPC = playerPC,
    limits = {
      expanded = false,
      mode = "native",
      stack = 99,
      capacity = function(data, pocket)
        return Bag.capacity(data, pocket)
      end,
    },
  }
end
