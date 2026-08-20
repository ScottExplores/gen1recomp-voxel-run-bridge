-- One of this mod's own settings: a ladder of values, where it persists,
-- and the row the player cycles it on.
--
-- The engine gives a render pipeline all of this for free -- ladder,
-- options row, hotkey, persistence -- but only to something that OWNS a
-- pass of the frame. The voxel wireframe and the world curve do not: they
-- parameterise the voxel pass, so they have nothing to put in drawWorld or
-- present and the registry rightly rejects them. What is left is a plain
-- mod setting, and this is the boilerplate two of them would otherwise
-- each carry a copy of:
--
--   options:define   a home in options.modOptions.BATTLE_ART_VOXEL_FORK.
--   SettingsMenu     the same setting inside its categorized OptionRows
--                    screen, reached from OPTIONS, Start, or Mod Manager.
--
-- Every route reads and writes the one stored value, so they cannot disagree.
-- Writing mirrors what the manager's stock page does (ManagerState:setOption):
-- the live save's options table, the loader's copy that mod.options:get
-- reads, and then the file.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = {}
ModSetting.__index = ModSetting

local function modId()
  local mod = V.mod
  return (mod and mod.id) or "BATTLE_ART_VOXEL_FORK"
end

local function snapshotBucket(root, id)
  if type(root) ~= "table" then return nil end
  local all = rawget(root, "modOptions")
  local original = type(all) == "table" and rawget(all, id) or nil
  local snapshot = {
    root = root,
    all = all,
    allWasTable = type(all) == "table",
    original = original,
    bucketWasTable = type(original) == "table",
    values = {},
  }
  if snapshot.bucketWasTable then
    for key, value in pairs(original) do snapshot.values[key] = value end
  end
  return snapshot
end

local function restoreBucket(snapshot, id)
  if not snapshot then return end
  if not snapshot.allWasTable then
    snapshot.root.modOptions = snapshot.all
    return
  end
  local all = snapshot.all
  snapshot.root.modOptions = all
  if snapshot.bucketWasTable then
    local original = snapshot.original
    for key in pairs(original) do original[key] = nil end
    for key, value in pairs(snapshot.values) do original[key] = value end
    all[id] = original
  else
    all[id] = snapshot.original
  end
end

local function optionRoots(game)
  local opts = game and game.save and game.save.options
  local loader = game and game.mods
  return opts, loader
end

local function persist(game)
  if not (game and game.writeOptions) then return true end
  local ok, result, detail = pcall(game.writeOptions, game)
  if ok and result ~= false then return true end
  return false, not ok and tostring(result)
    or tostring(detail or "game.writeOptions returned false")
end

-- `values` are the stored values in ladder order and `labels` what the row
-- shows for each. The optional defaultIndex is also the fallback for an
-- unreadable or unrecognised stored value; otherwise values[1] is used.
function ModSetting.new(key, label, values, labels, defaultIndex)
  return setmetatable({
    key = key, label = label, values = values, labels = labels,
    defaultIndex = defaultIndex or 1,
    index = nil,          -- nil = not yet read back from the persisted options
  }, ModSetting)
end

local function indexOf(self, value)
  for i, v in ipairs(self.values) do
    if v == value then return i end
  end
  return self.defaultIndex or 1
end

-- What the player left it at last session. Read lazily rather than at load
-- time: the loader fills modOptions before a mod runs, but reading through
-- the API keeps this honest about where the value lives.
function ModSetting:read()
  if self.index then return self.index end
  local mod = V.mod
  local value
  if mod and mod.options then
    local ok, got = pcall(mod.options.get, mod.options, self.key)
    if ok then value = got end
  end
  self.index = indexOf(self, value)
  return self.index
end

function ModSetting:get()
  return self.values[self:read()]
end

function ModSetting:level()
  return self:read() - 1
end

function ModSetting:setIndex(i, game, shouldPersist)
  local n = #self.values
  i = ((i - 1) % n + n) % n + 1
  local value, id = self.values[i], modId()
  local opts, loader = optionRoots(game)
  local savedSnapshot = snapshotBucket(opts, id)
  local liveSnapshot = snapshotBucket(loader, id)
  local oldIndex = self.index

  self.index = i
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[id] = opts.modOptions[id] or {}
    opts.modOptions[id][self.key] = value
  end
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id][self.key] = value
  end
  if shouldPersist ~= false then
    local ok, err = persist(game)
    if not ok then
      restoreBucket(liveSnapshot, id)
      restoreBucket(savedSnapshot, id)
      self.index = oldIndex
      return nil, err
    end
  end
  return value
end

-- Stage a group without writing it yet. SpriteMenu uses this to include the
-- provider's top-level Crystal preferences in the same durable transaction as
-- Battle Art's ownership keys. The returned token must be persisted or rolled
-- back by the caller.
function ModSetting.stage(changes, game)
  if type(changes) ~= "table" then return nil, "changes are required" end
  local id = modId()
  local opts, loader = optionRoots(game)
  local savedSnapshot = snapshotBucket(opts, id)
  local liveSnapshot = snapshotBucket(loader, id)
  local oldIndexes, values = {}, {}

  for i, change in ipairs(changes) do
    local setting = change and change.setting
    local index = change and tonumber(change.index)
    if type(setting) ~= "table" or type(setting.values) ~= "table"
        or not index or index % 1 ~= 0 or index < 1
        or index > #setting.values then
      return nil, "invalid setting transaction at index " .. tostring(i)
    end
    oldIndexes[i] = { setting = setting, value = setting.index }
  end

  local active = true
  local token = { values = values }
  function token:rollback()
    if not active then return false end
    restoreBucket(liveSnapshot, id)
    restoreBucket(savedSnapshot, id)
    for _, prior in ipairs(oldIndexes) do prior.setting.index = prior.value end
    active = false
    return true
  end
  function token:finish()
    if not active then return false end
    active = false
    return true
  end
  function token:persist()
    if not active then return false, "setting transaction is closed" end
    local ok, err = persist(game)
    if not ok then
      self:rollback()
      return false, err
    end
    self:finish()
    return true, values
  end

  for i, change in ipairs(changes) do
    local ok, value, err = pcall(change.setting.setIndex, change.setting,
      change.index, game, false)
    if not ok or value == nil then
      token:rollback()
      return nil, not ok and tostring(value) or err
    end
    values[i] = value
  end
  return token, values
end

-- Apply a logical ownership/profile edit with one durable write. Every entry
-- is `{ setting = ModSetting, index = number }`; validation happens before
-- mutation, and a failed write restores both option buckets and every cached
-- setting index so callers cannot observe a half-applied profile.
function ModSetting.transaction(changes, game)
  local token, err = ModSetting.stage(changes, game)
  if not token then return false, err end
  return token:persist()
end

function ModSetting:cycle(game, dir)
  return self:setIndex(self:read() + (dir or 1), game)
end

-- Adopt a value set from somewhere else (the mod manager's settings page,
-- which writes and persists on its own). Nothing to store: just move the
-- cached index so the next read agrees with it.
function ModSetting:sync(value)
  self.index = indexOf(self, value)
end

-- A descriptor src/ui/OptionRows.lua can render. SettingsMenu normally builds
-- equivalent rows from the schema so all settings share one generic writer;
-- this method remains useful to compatibility surfaces and local callers.
function ModSetting:row()
  local self_ = self
  return {
    id = modId() .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      local value = self_:cycle(game, dir)
      return value ~= nil
    end,
  }
end

-- The row the mod manager's own settings page builds for this mod.
function ModSetting:schema(help)
  local choices = {}
  for i, v in ipairs(self.values) do choices[i] = { self.labels[i], v } end
  if #self.values == 2 and self.values[1] == false then
    return { key = self.key, type = "toggle", label = self.label,
             default = self.values[1], help = help }
  end
  return { key = self.key, type = "choice", label = self.label,
             choices = choices, default = self.values[self.defaultIndex or 1],
             help = help }
end

return ModSetting
