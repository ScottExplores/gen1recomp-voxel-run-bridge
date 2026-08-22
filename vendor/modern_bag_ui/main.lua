-- Modern Bag UI retains the built-in BagMenu controller and replaces its
-- presentation plus the small amount of navigation needed for pocket tabs.
-- Every item effect, target picker, battle turn, toss prompt and callback
-- continues to run through src/ui/BagMenu.lua.
return function(mod)
  -- VENDORED CHANGE (Scott's Tweaks): the requested backpack presentation is
  -- the bundled default. The responsive modern skin remains available.
  local SKINS = {
    { label = "POCKET", value = "classic_pocket" },
    { label = "MODERN", value = "modern" },
  }

  mod.options:define({
    { key = "skin", label = "BAG SKIN", type = "choice",
      default = "classic_pocket",
      choices = {
        { SKINS[1].label, SKINS[1].value },
        { SKINS[2].label, SKINS[2].value },
      } },
  })

  local function skinIndex()
    local current = mod.options:get("skin") or "classic_pocket"
    for index, skin in ipairs(SKINS) do
      if skin.value == current then return index end
    end
    return 1
  end

  local function setSkin(game, value)
    -- VENDORED CHANGE (Scott's Tweaks): the bundled host provides a
    -- namespaced writer. Prefer it so the host bucket, live cache and disk
    -- stay in sync; standalone API-2 installs retain the original fallback.
    if type(mod.options.write) == "function" then
      return mod.options:write(game, "skin", value)
    end
    local options = game and game.save and game.save.options
    if options then
      options.modOptions = options.modOptions or {}
      options.modOptions[mod.id] = options.modOptions[mod.id] or {}
      options.modOptions[mod.id].skin = value
    end
    local loader = game and game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
      loader.modOptions[mod.id].skin = value
      if loader.events then
        loader.events:emit("mod.options_changed",
          { mod = mod.id, key = "skin", value = value })
      end
    end
  end

  -- Keep the skin beside the game's other display choices instead of hiding
  -- it one level deeper in the mod manager. Left, Right and A all cycle it.
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    out[#out + 1] = {
      id = "modern_bag_ui_skin",
      label = "BAG SKIN",
      value = function() return SKINS[skinIndex()].label end,
      step = function(g, dir)
        local index = (skinIndex() - 1 + (dir or 1)) % #SKINS + 1
        setSkin(g, SKINS[index].value)
        return true
      end,
    }
    return out
  end)

  local function loadFactory(filename)
    local source, readErr = mod:read(filename)
    if not source then
      mod.log:error("%s is missing (%s); reinstall the mod", filename,
        tostring(readErr or "unknown read error"))
      return nil
    end

    -- VENDORED CHANGE (Scott's Tweaks): PUC Lua 5.1 has loadstring rather
    -- than the string-compiling form of load used by LuaJIT/Lua 5.2+.
    local compile = loadstring or load
    local chunk, compileErr = compile(source,
      "@" .. mod.path .. "/" .. filename)
    if not chunk then
      mod.log:error("%s did not compile: %s", filename, tostring(compileErr))
      return nil
    end

    local ok, factory = pcall(chunk)
    if not ok or type(factory) ~= "function" then
      mod.log:error("%s must return a factory function: %s", filename,
        tostring(factory))
      return nil
    end
    return factory
  end

  -- Compile both parts before installing either one so a damaged archive
  -- cannot leave half of the mod active.
  local makeScreen = loadFactory("screen.lua")
  local makeInventory = loadFactory("inventory.lua")
  if not makeScreen or not makeInventory then return end

  -- VENDORED CHANGE (Scott's Tweaks): compose the screen records already in
  -- the registry. This preserves native controllers and every lower-priority
  -- owner. On a repeated install, unwrap our own prior record instead of
  -- nesting another copy of this presentation around itself.
  local function capturedFactory(id, marker)
    local prior = mod.content.screens:get(id)
    if type(prior) == "table" and prior[marker] == true
        and prior.__modernBagOwner == mod.id then
      return prior.__modernBagPrior
    end
    return prior
  end
  local priorBag = capturedFactory("BagMenu", "__modernBagUIFactory")
  local priorPlayerPC = capturedFactory("PlayerPC", "__modernBagPCFactory")

  local screenOK, bagScreen = pcall(makeScreen, mod, priorBag)
  if not screenOK or type(bagScreen) ~= "table"
      or type(bagScreen.new) ~= "function" then
    mod.log:error("bag screen factory failed: %s", tostring(bagScreen))
    return
  end

  local inventoryOK, inventory = pcall(makeInventory, mod, bagScreen,
    priorPlayerPC)
  if not inventoryOK or type(inventory) ~= "table"
      or type(inventory.playerPC) ~= "table"
      or type(inventory.playerPC.new) ~= "function" then
    mod.log:error("inventory extension factory failed: %s", tostring(inventory))
    return
  end

  bagScreen.__modernBagUIFactory = true
  bagScreen.__modernBagOwner = mod.id
  bagScreen.__modernBagPrior = priorBag
  inventory.playerPC.__modernBagPCFactory = true
  inventory.playerPC.__modernBagOwner = mod.id
  inventory.playerPC.__modernBagPrior = priorPlayerPC

  -- VENDORED CHANGE (Scott's Tweaks): BagMenu and PlayerPC already exist in
  -- the base game, so API-2 record registries require an explicit override.
  mod.content.screens:override("BagMenu", bagScreen)
  mod.content.screens:override("PlayerPC", inventory.playerPC)
  mod.exports.inventoryLimits = inventory.limits
  mod.exports.skins = SKINS
  mod.exports.activeSkin = function() return SKINS[skinIndex()].value end
  mod.exports.bagUI = {
    apiVersion = 1,
    upstreamVersion = "0.4.1",
    nativeLimits = true,
  }
  mod.log:info("modern pocket bag enabled (native inventory limits)")
end
