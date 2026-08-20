-- Runs the bundled community mods inside Scott's Tweaks.
--
-- Each one keeps its upstream source verbatim under vendor/<dir>/ so it stays
-- diffable against its own repository and a new upstream release is a copy,
-- not a re-port. Nothing in their code was edited to make this work: they are
-- handed a proxy mod handle whose `path` and `read` are rooted at their own
-- vendor directory, so `mod.path .. "/assets"` and `mod:read("lib/x.lua")`
-- resolve exactly where they did when the mod shipped alone.
--
-- `find` is shimmed too. These mods probe for each other by id -- Wilds looks
-- for BATTLE_ART_VOXEL_FORK to install its variable-geometry adapter, Scott's
-- Tweaks looks for running_shoes before touching FreeMove -- and once fused
-- the engine no longer knows those ids. The shim answers for every bundled mod
-- and falls through to the real loader for anything genuinely installed
-- separately.

local VendorHost = {}

-- Load order follows the priority each mod declared when it shipped
-- standalone, lowest first, which is the order the engine's loader would have
-- used. Battle Art is not listed: it is vendored at the mod root and is
-- already running by the time this is called.
VendorHost.MODS = {
  { dir = "wilds",             id = "overworld_wild_spawns",  priority = 80 },
  { dir = "free_fly",          id = "free_fly",               priority = 100 },
  { dir = "choose_lead",       id = "choose_lead",            priority = 100 },
  { dir = "catchable151",      id = "all_pokemon_catchable_151_mod", priority = 100 },
  { dir = "unique_menu_icons", id = "unique_menu_icons",      priority = 100 },
  { dir = "dynamic_scaling",   id = "Dynamic_Scaling",        priority = 120 },
  -- Running Shoes is deliberately NOT installed from the bundle. Scott's
  -- Tweaks already provides B-running through the engine's movement.speed
  -- hook, which applies in 2D, third person and first person alike, and adds
  -- the camera bob Running Shoes has no equivalent for. Running both put the
  -- speed behind Running Shoes' own trigger and left B doing nothing outside
  -- first person. The source stays in vendor/running_shoes for reference, and
  -- a separately installed copy still takes over -- see running.lua.
  { dir = "crystal",           id = "crystal_animated_sprites_with_shiny_visuals", priority = 980,
    siblings = { "species_map", "animation_data", "dimensions", "options_screen" } },
}

VendorHost.HOST_ID = "BATTLE_ART_VOXEL_FORK"

local function traceback(err)
  local ok, tb = pcall(function() return debug.traceback(tostring(err), 2) end)
  return ok and tb or tostring(err)
end

-- The engine's own api.find accepts both find(id) and find(self, id); the
-- bundled mods use both spellings, so the shim has to as well.
local function resolveId(first, second)
  if second == nil then return first end
  return second
end

function VendorHost.new(mod)
  local host = {
    mod = mod,
    loaded = {},   -- id -> { id, version, exports }
    failures = {},
    order = {},
    schemas = {},  -- vendorId -> its options schema, collected at define time
  }
  return setmetatable(host, { __index = VendorHost })
end

-- Whether a standalone copy of `id` is installed AND enabled, read from the
-- loader's own tables rather than mod.find. find() answers nil for a mod that
-- simply has not RUN yet, and Crystal's standalone priority is 980 against
-- this mod's 200 -- so a find()-based check always concluded "absent" at load
-- time and installed the bundled copy on top of a standalone that started two
-- seconds later. The loader's mods/disabled tables are complete before any
-- entry chunk runs, so they answer the real question: will it run this boot?
function VendorHost:_standaloneWillRun(id)
  local ok, Game = pcall(require, "src.core.Game")
  local loader = ok and Game and Game.mods or nil
  if type(loader) == "table" and type(loader.mods) == "table" then
    local entry = loader.mods[id]
    if entry == nil then return false end
    -- Loader:_fail and Loader:_skip deliberately leave an enabled-but-broken
    -- entry in loader.mods for the Manager to report. Runtime ownership uses
    -- Loader's isActive shape instead: enabled and not failed. A failed
    -- standalone has rolled its registrations back, so the bundled copy is
    -- the only provider that can still run this boot.
    if entry.failed == true or entry.enabled == false then return false end
    if type(loader.disabled) == "table" and loader.disabled[id] then
      return false
    end
    return true
  end
  -- No loader visible (bare harness): fall back to find, which can only
  -- see mods that already ran -- better than nothing, never worse.
  local realFind = self.mod.find
  if type(realFind) == "function" then
    local okFind, found = pcall(realFind, id)
    return okFind and found ~= nil
  end
  return false
end

function VendorHost:_find(first, second)
  local wanted = resolveId(first, second)
  if wanted == nil then return nil end
  -- A separately installed copy always wins, so the real loader is asked
  -- first. The synthetic answers below must never mask a mod the player
  -- actually chose to install -- doing so hid a standalone renderer from the
  -- stand-down check and started a second copy on top of it.
  local realFind = self.mod.find
  if type(realFind) == "function" and wanted ~= self.mod.id then
    local ok, found = pcall(realFind, wanted)
    if ok and found then return found end
  end
  local hit = self.loaded[wanted]
  if hit then return hit end
  if wanted == VendorHost.HOST_ID or wanted == self.mod.id then
    -- Battle Art publishes onto the host mod's exports.
    return { id = wanted, version = self.mod.exports and self.mod.exports.version,
             exports = self.mod.exports }
  end
  return nil
end

function VendorHost:handleFor(entry)
  local mod = self.mod
  local base = "vendor/" .. entry.dir
  local host = self
  -- list/info accept nil or "" to address a mod's root.  Keep that API shape
  -- for bundled handles while making their root the vendor directory.  Asset
  -- path/image deliberately continue to require a concrete relative path,
  -- just like the engine facade they delegate to.
  local function vendorRooted(relative)
    if relative == nil or relative == "" then return base end
    return base .. "/" .. relative
  end
  local function vendorAsset(relative)
    return base .. "/" .. relative
  end
  local proxy = setmetatable({}, { __index = mod })
  proxy.id = entry.id
  proxy.path = mod.path .. "/" .. base
  proxy.exports = {}
  proxy.read = function(_, relative)
    return mod:read(base .. "/" .. relative)
  end
  proxy.find = function(first, second) return host:_find(first, second) end
  -- mod.assets, mod:list and mod:info must be re-rooted exactly like read and
  -- path. The engine builds them as closures over the HOST's mod.path, so the
  -- inherited assets:path sent every image a bundled mod registered to
  -- mods/voxel_run_bridge/<rel> -- which does not exist -- and image callers
  -- rendered blanks. Delegating with the vendor prefix keeps the engine's own
  -- SafePath checks and image cache.
  proxy.assets = setmetatable({
    path = function(_, relative)
      return mod.assets:path(vendorAsset(relative))
    end,
    image = function(_, relative)
      return mod.assets:image(vendorAsset(relative))
    end,
    list = function(_, relative)
      return mod.assets:list(vendorRooted(relative))
    end,
    info = function(_, relative)
      return mod.assets:info(vendorRooted(relative))
    end,
  }, { __index = mod.assets })
  proxy.list = function(_, relative)
    return mod:list(vendorRooted(relative))
  end
  proxy.info = function(_, relative)
    return mod:info(vendorRooted(relative))
  end
  -- Options get their own namespace. The engine keys both option values and
  -- the schema by mod id, and every proxy inherits the HOST id -- so bundled
  -- mods that both define an "enabled" key read each other's value, and each
  -- options:define() REPLACED the host's whole schema (last definer won; only
  -- Scott's Tweaks' own rows survived in the Mod Manager). Values live in the
  -- host bucket under "<vendorId>:<key>", so the ordinary save path persists
  -- them, and schemas are collected for one merged define() after every
  -- bundled mod has loaded -- see mergedSchema().
  proxy.options = {
    -- Explicit storage seam for vendor code that has to distinguish a schema
    -- default from a value actually present in a save. Standalone mods have no
    -- such metadata and keep using [mod.id][key]; bundled code stores under
    -- [hostId][prefix .. key].
    hosted = {
      hostId = mod.id,
      vendorId = entry.id,
      prefix = entry.id .. ":",
    },
    define = function(_, schema)
      assert(type(schema) == "table", "options schema must be a table of rows")
      host.schemas[entry.id] = schema
      return schema
    end,
    get = function(_, key)
      local stored = mod.options:get(entry.id .. ":" .. tostring(key))
      if stored ~= nil then return stored end
      for _, row in ipairs(host.schemas[entry.id] or {}) do
        if row.key == key then return row.default end
      end
      return nil
    end,
    -- Non-Mod-Manager vendor UIs cannot call options:set in API 2. Route them
    -- through the host's canonical writer so save and live Loader cache remain
    -- in lockstep. Vendor Config.setOption owns its direct live callback, so
    -- this seam deliberately suppresses engine events (avoiding double apply).
    write = function(_, game, key, value)
      return host:writeOption(game, entry.id, key, value, { emit = false })
    end,
  }
  -- The unified MOD SETTINGS screen presents every bundled mod's settings, so
  -- their own row injections into the stock OPTIONS page are dropped here --
  -- otherwise Crystal, Wilds and Dynamic Scaling each add a second copy of
  -- their rows beside the unified ones. Gameplay hooks (ui.party.submenu,
  -- ui.start_menu.items, battle hooks) pass through untouched, and a
  -- STANDALONE install of any of these mods keeps its own UI because this
  -- facade exists only on bundled handles.
  proxy.hooks = setmetatable({
    wrap = function(_, name, fn, priority)
      if name == "ui.options.rows" then
        host.suppressedRows = host.suppressedRows or {}
        host.suppressedRows[#host.suppressedRows + 1] = entry.id
        return
      end
      return mod.hooks:wrap(name, fn, priority)
    end,
  }, { __index = function(_, k)
    local v = mod.hooks and mod.hooks[k]
    if type(v) == "function" then
      -- Re-target self so an inherited method runs against the REAL hooks
      -- table, not this facade.
      return function(_, ...) return v(mod.hooks, ...) end
    end
    return v
  end })
  return proxy
end

-- One schema covering every bundled mod, keys prefixed "<vendorId>:<key>" so
-- nothing collides, labels kept. The host appends its own rows and calls the
-- engine's options:define exactly once with the result, which is what makes
-- every bundled setting visible to the Mod Manager and persistent across
-- restarts.
function VendorHost:mergedSchema()
  local out = {}
  for _, entry in ipairs(VendorHost.MODS) do
    for _, row in ipairs(self.schemas[entry.id] or {}) do
      local clone = {}
      for k, v in pairs(row) do clone[k] = v end
      clone.key = entry.id .. ":" .. row.key
      clone.vendor = entry.id
      clone.vendorKey = row.key
      out[#out + 1] = clone
    end
  end
  return out
end

-- Some bundled mods reach for their own siblings through package.path with
-- `require("mods.<id>.<file>")`, which resolves against the engine's real mods
-- directory -- a path that does not exist once the mod is vendored. Rather than
-- edit upstream source, the chunk is given an environment whose `require`
-- answers those names from the bundle and delegates everything else.
function VendorHost:_preloadSiblings(entry, handle)
  if type(package) ~= "table" or type(package.preload) ~= "table" then return end
  local mod = self.mod
  local base = "vendor/" .. entry.dir
  local prefix = "mods." .. entry.id .. "."
  for _, leaf in ipairs(entry.siblings or {}) do
    local key = prefix .. leaf
    self.preloaded = self.preloaded or {}
    self.preloaded[#self.preloaded + 1] = key
    if package.loaded[key] == nil then
      package.preload[key] = function()
        local okRead, src = pcall(mod.read, mod, base .. "/" .. leaf .. ".lua")
        if not okRead or type(src) ~= "string" then
          error(("%s: %s.lua is missing from the bundle"):format(entry.id, leaf), 0)
        end
        local compile = loadstring or load
        local chunk, err = compile(src,
          "@" .. tostring(mod.path) .. "/" .. base .. "/" .. leaf .. ".lua")
        if not chunk then
          error(("%s: %s.lua did not compile: %s"):format(entry.id, leaf, tostring(err)), 0)
        end
        return chunk(handle)
      end
    end
  end
end

function VendorHost:_envFor(entry, handle)
  local mod = self.mod
  local base = "vendor/" .. entry.dir
  local prefix = "mods." .. entry.id .. "."
  local cache = {}
  local realRequire = require
  local env
  local function shimRequire(name)
    local key = tostring(name)
    if cache[key] ~= nil then return cache[key] end
    if key:sub(1, #prefix) == prefix then
      local leaf = key:sub(#prefix + 1):gsub("%%.", "/")
      local okRead, src = pcall(mod.read, mod, base .. "/" .. leaf .. ".lua")
      if okRead and type(src) == "string" then
        local compile = loadstring or load
        local chunk, err = compile(src,
          "@" .. tostring(mod.path) .. "/" .. base .. "/" .. leaf .. ".lua")
        if not chunk then
          error(("%s: %s.lua did not compile: %s"):format(entry.id, leaf, tostring(err)), 0)
        end
        if setfenv then setfenv(chunk, env) end
        local value = chunk(handle)
        if value == nil then value = true end
        cache[key] = value
        return value
      end
    end
    return realRequire(name)
  end
  env = setmetatable({ require = shimRequire }, { __index = _G })
  return env
end

function VendorHost:install(entry)
  local mod = self.mod
  local base = "vendor/" .. entry.dir
  local relative = base .. "/main.lua"

  local okRead, source = pcall(mod.read, mod, relative)
  if not okRead or type(source) ~= "string" then
    self.failures[entry.id] = "entry missing"
    return false
  end

  local compile = loadstring or load
  local chunk, err = compile(source, "@" .. tostring(mod.path) .. "/" .. relative)
  if not chunk then
    self.failures[entry.id] = "compile: " .. tostring(err)
    return false
  end

  local handle = self:handleFor(entry)
  self:_preloadSiblings(entry, handle)
  local okRun, result = xpcall(function() return chunk(handle) end, traceback)
  if not okRun then
    self.failures[entry.id] = tostring(result)
    return false
  end

  -- A mod whose entry returns a function expects the loader to call it with
  -- the handle, the same shape Scott's Tweaks itself uses.
  if type(result) == "function" then
    local okCall, callErr = xpcall(function() return result(handle) end, traceback)
    if not okCall then
      self.failures[entry.id] = tostring(callErr)
      return false
    end
  end

  self.loaded[entry.id] = {
    id = entry.id,
    version = entry.version,
    exports = handle.exports,
  }
  self.order[#self.order + 1] = entry.id
  return true
end

function VendorHost:installAll()
  -- When another voxel renderer owns the map -- the fused Battle Art stood
  -- down -- the bundled Crystal must stand down with it. Crystal wraps the
  -- renderer's sprite pipeline, and an EXTERNAL renderer cannot see a bundled
  -- Crystal through the engine's find, so installing it anyway recreates the
  -- exact ownership clash that blanked every sprite: two coordinators, no
  -- drawing. A standalone Crystal beside a standalone renderer pairs through
  -- the engine as before.
  local fused = self.mod.exports and self.mod.exports.fusedRenderer
  local externalRenderer = type(fused) == "table" and fused.installed == false
    and fused.reason == "external_voxel"
  for _, entry in ipairs(VendorHost.MODS) do
    -- A separately installed, enabled copy always wins: the player chose it,
    -- and two copies of one mod must never both run.
    if self:_standaloneWillRun(entry.id) then
      self.failures[entry.id] = "standalone copy is installed"
    elseif externalRenderer
        and entry.id == "crystal_animated_sprites_with_shiny_visuals" then
      self.failures[entry.id] = "external voxel renderer active; bundled sprite pack stands down"
    else
      self:install(entry)
    end
  end
  return self
end

-- Write one bundled mod's option through the ordinary save path and announce
-- the change under BOTH ids: listeners inside the bundle filter on their own
-- vendor id, while the engine and Scott's Tweaks filter on the host id. This
-- is the only sanctioned writer for "<vendorId>:<key>" values -- menus go
-- through here so a bundled mod reacts live exactly as it did standalone.
function VendorHost:writeOption(game, vendorId, key, value, opts)
  local mod = self.mod
  if type(game) ~= "table" then return false end
  opts = opts or {}
  local storedKey = vendorId .. ":" .. tostring(key)
  game.save = game.save or {}
  game.save.options = game.save.options or {}
  local options = game.save.options
  options.modOptions = options.modOptions or {}
  options.modOptions[mod.id] = options.modOptions[mod.id] or {}
  options.modOptions[mod.id][storedKey] = value

  local loaders = {}
  local function addLoader(candidate)
    if type(candidate) ~= "table" then return end
    for _, existing in ipairs(loaders) do
      if existing == candidate then return end
    end
    loaders[#loaders + 1] = candidate
  end
  addLoader(game.mods)
  addLoader(game.mods and game.mods.loader)
  for _, loader in ipairs(loaders) do
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
    loader.modOptions[mod.id][storedKey] = value
  end
  if opts.persist ~= false and game.writeOptions then
    pcall(game.writeOptions, game)
  end
  local events = game.mods and (game.mods.events
    or (game.mods.loader and game.mods.loader.events))
  if opts.emit ~= false and events then
    events:emit("mod.options_changed",
      { mod = mod.id, key = storedKey, value = value })
    events:emit("mod.options_changed",
      { mod = vendorId, key = key, value = value })
  end
  return true
end

function VendorHost:readOption(vendorId, key)
  local stored = self.mod.options:get(vendorId .. ":" .. tostring(key))
  if stored ~= nil then return stored end
  for _, row in ipairs(self.schemas[vendorId] or {}) do
    if row.key == key then return row.default end
  end
  return nil
end

function VendorHost:status()
  local out = { loaded = {}, failed = {},
    env = { setfenv = (setfenv ~= nil), package = (package ~= nil),
            preload = (package ~= nil and package.preload ~= nil),
            preloaded = self.preloaded } }
  for _, id in ipairs(self.order) do out.loaded[#out.loaded + 1] = id end
  for id, why in pairs(self.failures) do out.failed[id] = why end
  return out
end

return VendorHost
