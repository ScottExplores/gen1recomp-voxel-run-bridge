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
  { dir = "running_shoes",     id = "running_shoes",          priority = 150 },
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
  }
  return setmetatable(host, { __index = VendorHost })
end

function VendorHost:_find(first, second)
  local wanted = resolveId(first, second)
  if wanted == nil then return nil end
  if wanted == VendorHost.HOST_ID or wanted == self.mod.id then
    -- Battle Art publishes onto the host mod's exports.
    return { id = wanted, version = self.mod.exports and self.mod.exports.version,
             exports = self.mod.exports }
  end
  local hit = self.loaded[wanted]
  if hit then return hit end
  local realFind = self.mod.find
  if type(realFind) == "function" then
    local ok, found = pcall(realFind, wanted)
    if ok and found then return found end
  end
  return nil
end

function VendorHost:handleFor(entry)
  local mod = self.mod
  local base = "vendor/" .. entry.dir
  local host = self
  local proxy = setmetatable({}, { __index = mod })
  proxy.id = entry.id
  proxy.path = mod.path .. "/" .. base
  proxy.exports = {}
  proxy.read = function(_, relative)
    return mod:read(base .. "/" .. relative)
  end
  proxy.find = function(first, second) return host:_find(first, second) end
  return proxy
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
  for _, entry in ipairs(VendorHost.MODS) do
    -- A separately installed copy always wins: the player chose it, and two
    -- copies of one mod must never both run.
    local external = nil
    local realFind = self.mod.find
    if type(realFind) == "function" then
      local ok, found = pcall(realFind, entry.id)
      if ok then external = found end
    end
    if external then
      self.failures[entry.id] = "standalone copy is installed"
    else
      self:install(entry)
    end
  end
  return self
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
