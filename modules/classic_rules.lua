-- A reversible rules profile, not a save converter. The player's individual
-- preferences remain stored exactly as chosen; consumers ask for an effective
-- value at the point of use. Turning this profile off reveals those preferences
-- again on the next reload. No Pokemon, item, badge, story flag or claimed-gift
-- marker is changed.

local OWN_OVERRIDES = {
  hm_without_badges = false,
  free_fly_without_badges = false,
  experience_mode = "vanilla",
  trainer_forfeit_enabled = false,
  trainer_rematches = false,
  trainer_adaptive_dialogue = false,
  trainer_growth = "off",
  oak_spare_starter = false,
}

local VENDOR_OVERRIDES = {
  free_fly = {
    quickstart = false,
    badges = true,
    gates = true,
    scotts_classic = true,
  },
  Dynamic_Scaling = {
    randomize = "off",
    difficulty = "off",
    trainer_difficulty = "off",
    boss_difficulty = "off",
    wild_difficulty = "off",
  },
  overworld_wild_spawns = {
    enabled = false,
    random_encounters = true,
    enable_hidden = false,
  },
}

local SKIP_VENDORS = { all_pokemon_catchable_151_mod = true }

local function copy(source)
  local result = {}
  for key, value in pairs(source) do
    result[key] = type(value) == "table" and copy(value) or value
  end
  return result
end

return function(mod)
  local api = { installed = true, key = "classic_rules" }

  -- This intentionally reads the raw host preference, not context.settings:
  -- settings may itself consult this profile to resolve effective values.
  function api:requested()
    local options = mod and mod.options
    if not (options and type(options.get) == "function") then return false end
    local ok, value = pcall(options.get, options, self.key)
    return ok and value == true
  end

  local bootEnabled = api:requested()

  -- Vendor mods cache some option values and register content during load.
  -- All consumers use one coherent boot snapshot until the next reload;
  -- changing the preference never creates a partly classic, partly custom run.
  function api:enabled()
    return bootEnabled
  end

  function api:ownsOverride(key)
    return OWN_OVERRIDES[key] ~= nil
  end

  function api:vendorOverride(vendorId, key)
    local values = VENDOR_OVERRIDES[vendorId]
    return type(values) == "table" and values[key] ~= nil
  end

  function api:own(key, requested)
    if self:enabled() and OWN_OVERRIDES[key] ~= nil then
      return OWN_OVERRIDES[key]
    end
    return requested
  end

  function api:vendor(vendorId, key, requested)
    local values = VENDOR_OVERRIDES[vendorId]
    if self:enabled() and type(values) == "table" and values[key] ~= nil then
      return values[key]
    end
    return requested
  end

  -- Content registrations are consumed at boot. Toggling a runtime profile
  -- cannot safely roll back Pokemon evolutions or patched encounter tables.
  -- Hold the boot selection until the next actual mod/game reload and make
  -- that distinction visible rather than pretending content changed live.
  function api:skipVendor(vendorId)
    return bootEnabled and SKIP_VENDORS[vendorId] == true
  end

  function api:status()
    local enabled = self:enabled()
    local requested = self:requested()
    return {
      enabled = enabled,
      requested = requested,
      bootEnabled = bootEnabled,
      restartRequired = requested ~= bootEnabled,
      contentRules = bootEnabled and "classic" or "custom",
      reason = requested ~= bootEnabled and "rules_reload_required" or "ready",
      changesSaveProgression = false,
    }
  end

  -- The map is useful to integrations that need to refresh cached values or
  -- expose why a setting is locked. Copies cannot modify the effective rules.
  api.ownOverrides = copy(OWN_OVERRIDES)
  api.vendorOverrides = copy(VENDOR_OVERRIDES)
  api.skippedVendors = copy(SKIP_VENDORS)
  mod.exports = mod.exports or {}
  mod.exports.classicRules = api
  return api
end
