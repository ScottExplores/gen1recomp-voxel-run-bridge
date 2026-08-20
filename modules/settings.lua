-- Shared option access for Scott's Tweaks. The Mod Manager owns the schema;
-- this helper keeps the live loader cache and the save copy in lockstep when
-- the in-game Scott's Tweaks menu changes a value.

local Settings = {}
Settings.__index = Settings

local function bucket(root, id, create)
  if type(root) ~= "table" then return nil end
  if create and type(root.modOptions) ~= "table" then root.modOptions = {} end
  local all = root.modOptions
  if type(all) ~= "table" then return nil end
  if create and type(all[id]) ~= "table" then all[id] = {} end
  return all[id]
end

-- A menu edit touches both the durable save mirror and the Loader's live
-- cache before game:writeOptions serializes them.  Keep the original table
-- identities as well as their contents so a failed Android/filesystem write
-- can put the complete in-memory state back exactly as it was.
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

function Settings.new(mod, defaults)
  return setmetatable({ mod = mod, defaults = defaults or {} }, Settings)
end

function Settings:get(key, fallback)
  if fallback == nil then fallback = self.defaults[key] end
  local options = self.mod and self.mod.options
  if options and type(options.get) == "function" then
    local ok, value = pcall(options.get, options, key)
    if ok and value ~= nil then return value end
  end
  return fallback
end

function Settings:stored(game, key)
  local saveOptions = game and game.save and game.save.options
  local saved = bucket(saveOptions, self.mod.id, false)
  if saved and saved[key] ~= nil then return true, saved[key] end
  local live = game and game.mods
  local loaded = bucket(live, self.mod.id, false)
  if loaded and loaded[key] ~= nil then return true, loaded[key] end
  return false, nil
end

function Settings:set(game, key, value, persist)
  if type(game) ~= "table" then return false, "game unavailable" end

  local originalSave = game.save
  local saveWasTable = type(originalSave) == "table"
  if not saveWasTable then game.save = {} end
  local originalOptions = game.save.options
  local optionsWasTable = type(originalOptions) == "table"
  if not optionsWasTable then game.save.options = {} end

  local savedSnapshot = snapshotBucket(game.save.options, self.mod.id)
  local liveSnapshot = snapshotBucket(game.mods, self.mod.id)
  local saved = bucket(game.save.options, self.mod.id, true)
  saved[key] = value

  if type(game.mods) == "table" then
    local live = bucket(game.mods, self.mod.id, true)
    live[key] = value
  end

  local persistError
  if persist ~= false and type(game.writeOptions) == "function" then
    local ok, result, detail = pcall(game.writeOptions, game)
    if not ok or result == false then
      persistError = not ok and tostring(result)
        or tostring(detail or "game.writeOptions returned false")
    end
  end
  if persistError ~= nil then
    restoreBucket(liveSnapshot, self.mod.id)
    restoreBucket(savedSnapshot, self.mod.id)
    if not optionsWasTable then game.save.options = originalOptions end
    if not saveWasTable then game.save = originalSave end
    return false, persistError
  end
  -- Match ManagerState:setOption: feature modules listening for live option
  -- changes must see edits made through the organized in-game menu too.
  if persist ~= false then
    local events = type(game.mods) == "table" and game.mods.events or nil
    if events and type(events.emit) == "function" then
      pcall(events.emit, events, "mod.options_changed", {
        mod = self.mod.id, key = key, value = value,
      })
    end
  end
  return true
end

-- During developer F5, entry chunks run before Game.mods is replaced by the
-- fresh Loader. A migration may therefore reach the save first. Reconcile
-- that authoritative save bucket into the now-live Loader on game.ready and
-- emit the same event as ManagerState for values that actually changed.
function Settings:sync(game)
  local saved = bucket(game and game.save and game.save.options,
    self.mod.id, false)
  if type(saved) ~= "table" or type(game and game.mods) ~= "table" then
    return 0
  end
  local live = bucket(game.mods, self.mod.id, true)
  local events = game.mods.events
  local changed = 0
  for key, value in pairs(saved) do
    if live[key] ~= value then
      live[key] = value
      changed = changed + 1
      if events and type(events.emit) == "function" then
        pcall(events.emit, events, "mod.options_changed", {
          mod = self.mod.id, key = key, value = value,
        })
      end
    end
  end
  return changed
end

return Settings
