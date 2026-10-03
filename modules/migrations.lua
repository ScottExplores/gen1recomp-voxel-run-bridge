-- One-time, per-save imports from the former standalone Scott mods. Imports
-- are deliberately additive: legacy namespaces are never removed or edited.

local MIGRATION_KEY = "legacy_import_v2"

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do
    out[copy(key, seen)] = copy(child, seen)
  end
  return out
end

local function optionBucket(save, id)
  local options = save and save.options
  local all = options and options.modOptions
  return type(all) == "table" and all[id] or nil
end

local function snapshotFields(value)
  if type(value) ~= "table" then return nil end
  local fields = {}
  for key, child in pairs(value) do fields[key] = child end
  return fields
end

local function restoreFields(value, fields)
  if not fields then return end
  for key in pairs(value) do value[key] = nil end
  for key, child in pairs(fields) do value[key] = child end
end

-- Settings:set(..., false) deliberately batches these imports into one
-- options write. Keep both option mirrors and the one-time bookkeeping
-- reversible until that write succeeds, including references held by other
-- modules. Replacing a bucket with a copy would leave those references stale.
local function snapshotOptions(root, id)
  local all, own
  if type(root) == "table" then all = rawget(root, "modOptions") end
  if type(all) == "table" then own = rawget(all, id) end
  return { root = root, all = all, own = own, fields = snapshotFields(own) }
end

local function restoreOptions(snapshot, id)
  if type(snapshot.root) ~= "table" then return end
  snapshot.root.modOptions = snapshot.all
  if type(snapshot.all) == "table" then
    restoreFields(snapshot.own, snapshot.fields)
    snapshot.all[id] = snapshot.own
  end
end

return function(mod, context)
  local api = { installed = true, version = 2, imported = false }
  mod.exports.migrations = api

  local function migrate(game)
    local save = game and game.save
    if type(save) ~= "table" then return false end
    local originalOptions = save.options
    local savedSnapshot = snapshotOptions(originalOptions, mod.id)
    local liveSnapshot = snapshotOptions(game.mods, mod.id)
    local originalModData = save.modData
    local originalOwn, originalCompleted, originalImported
    if type(originalModData) == "table" then
      originalOwn = originalModData[mod.id]
    end
    local ownFields = snapshotFields(originalOwn)
    if type(originalOwn) == "table" then
      originalCompleted = originalOwn[MIGRATION_KEY]
      originalImported = originalOwn.legacy_imported_keys
    end
    local completedFields = snapshotFields(originalCompleted)
    local importedFields = snapshotFields(originalImported)
    api.lastError = nil

    if type(save.modData) ~= "table" then save.modData = {} end
    local own = save.modData[mod.id]
    if type(own) ~= "table" then
      own = {}
      save.modData[mod.id] = own
    end
    local completed = own[MIGRATION_KEY]
    if type(completed) ~= "table" then
      completed = {}
      own[MIGRATION_KEY] = completed
    end

    local changedOptions = false
    local imported = {}
    local didWork = false
    local function savedOption(key)
      local bucket = optionBucket(save, mod.id)
      return type(bucket) == "table" and bucket[key] ~= nil
    end
    local function importOption(key, value)
      if value == nil or savedOption(key) then return end
      local ok = context.settings:set(game, key, value, false)
      if ok then
        changedOptions = true
        imported[#imported + 1] = key
      end
    end

    local function activeProvider(ids)
      if not (context and type(context.findMod) == "function") then return nil end
      for _, id in ipairs(ids) do
        local ok, found = pcall(context.findMod, id)
        if ok and found then return id end
      end
    end
    api.deferred = {}
    local function feature(name, providers, importer)
      if completed[name] == true then return end
      local provider = activeProvider(providers)
      if provider then
        api.deferred[name] = provider
        return
      end
      importer()
      completed[name] = true
      didWork = true
    end

    -- 0.12.3 stored four EXP values. Runtime behavior can normalize them on
    -- read, but Gen1Recomp's stock Mod Manager matches schema choices against
    -- the raw Loader value and would display OFF for a legacy `lead`, `party`,
    -- or `share` save. Canonicalize both durable and live mirrors once so the
    -- stock page, organized page, and battle hook all report the same choice.
    feature("experience_modes_v3", {}, function()
      local ownOptions = optionBucket(save, mod.id)
      local raw = type(ownOptions) == "table"
        and ownOptions.experience_mode or nil
      local canonical
      if raw == "lead" then
        canonical = "buddy"
      elseif raw == "party" or raw == "share" then
        canonical = "all"
      end
      if canonical then
        local ok = context.settings:set(
          game, "experience_mode", canonical, false)
        if ok then
          changedOptions = true
          imported[#imported + 1] = "experience_mode"
        end
      end
    end)

    feature("trainer", { "trainer_forfeit" }, function()
      local trainerData = save.modData.trainer_forfeit
      if own.trainer_memory == nil and type(trainerData) == "table"
          and type(trainerData.memory) == "table" then
        own.trainer_memory = copy(trainerData.memory)
        imported[#imported + 1] = "trainer_memory"
      end
      local trainerOptions = optionBucket(save, "trainer_forfeit")
      if type(trainerOptions) == "table" then
        importOption("trainer_rematches", trainerOptions.rematches)
        importOption("trainer_adaptive_dialogue",
          trainerOptions.adaptive_dialogue)
        importOption("trainer_growth", trainerOptions.trainer_growth)
      end
    end)

    feature("oak", { "oak_spare_starter" }, function()
      if own.oak_spare_starter_claimed == nil then
        local oak = save.modData.oak_spare_starter
        local combined = save.modData.scott_mod
        if (type(oak) == "table" and oak.claimed == true)
            or (type(combined) == "table"
              and combined.oak_spare_starter_claimed == true) then
          own.oak_spare_starter_claimed = true
          imported[#imported + 1] = "oak_spare_starter_claimed"
        end
      end
    end)

    -- thorkdev's unlicensed 0.x mod is not copied. Only its narrow save
    -- values are recognized, and only when the distinctive bob fields prove
    -- this is that series rather than the unrelated MIT 1.x mod sharing the
    -- same running_shoes id.
    feature("running", { "running_shoes", "scott_mod" }, function()
      local shoes = save.modData.running_shoes
      if type(shoes) == "table"
          and (shoes.viewBob ~= nil or shoes.bobIntensity ~= nil) then
        importOption("running_enabled", shoes.enabled)
        importOption("running_speed", shoes.speed)
        importOption("running_view_bob", shoes.viewBob)
        importOption("running_bob_intensity", shoes.bobIntensity)
      end
      local scottOptions = optionBucket(save, "scott_mod")
      if type(scottOptions) == "table" then
        importOption("running_enabled", scottOptions.run_enabled)
        importOption("running_speed", scottOptions.run_speed)
      end
    end)

    feature("dual", { "gen1recomp_ds" }, function()
      local oldDual = save.modData.gen1recomp_ds
      if type(oldDual) == "table" then
        importOption("dual_screen", oldDual.enabled)
      end
    end)

    local allImported = type(own.legacy_imported_keys) == "table"
      and own.legacy_imported_keys or {}
    local known = {}
    for _, key in ipairs(allImported) do known[key] = true end
    for _, key in ipairs(imported) do
      if not known[key] then allImported[#allImported + 1] = key end
    end
    own.legacy_imported_keys = allImported
    if changedOptions and type(game.writeOptions) == "function" then
      local ok, result, detail = pcall(game.writeOptions, game)
      if not ok or result == false then
        local err = not ok and tostring(result)
          or tostring(detail or "game.writeOptions returned false")
        restoreOptions(liveSnapshot, mod.id)
        restoreOptions(savedSnapshot, mod.id)
        save.options = originalOptions
        restoreFields(originalCompleted, completedFields)
        restoreFields(originalImported, importedFields)
        restoreFields(originalOwn, ownFields)
        save.modData = originalModData
        if type(originalModData) == "table" then
          originalModData[mod.id] = originalOwn
        end
        api.imported = false
        api.importedKeys = {}
        api.lastError = err
        if mod.log and mod.log.warn then
          mod.log:warn("legacy option import could not be persisted: %s",
            err)
        end
        return false, err
      end
    end
    api.imported = #imported > 0
    api.importedKeys = copy(imported)
    return didWork or #imported > 0
  end

  api.run = migrate
  local function lifecycle(payload)
    local game = type(payload) == "table" and payload.game or nil
    if not game then
      local ok, Game = pcall(require, "src.core.Game")
      if ok then game = Game end
    end
    local migrated, err = migrate(game)
    if not err and context and context.settings
        and type(context.settings.sync) == "function" then
      context.settings:sync(game)
    end
    return migrated, err
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("game.ready", lifecycle)
    mod.events:on("save.created", lifecycle)
    mod.events:on("save.loaded", lifecycle)
  end

  -- Covers API builds that install a hot-reloaded content mod after a save
  -- is already active. The marker keeps every later lifecycle call cheap.
  lifecycle()
  return api
end
