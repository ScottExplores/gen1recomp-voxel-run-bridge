-- ROM-free contract tests for the reversible original-rules profile.
local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end
local function eq(actual, expected, message)
  check(actual == expected, message .. " (expected " .. tostring(expected)
    .. ", got " .. tostring(actual) .. ")")
end

local install = assert(loadfile("modules/classic_rules.lua"))()
local preferences = {
  classic_rules = false,
  hm_without_badges = true,
  free_fly_without_badges = true,
  experience_mode = "all",
  running_enabled = true,
  running_speed = 1.5,
  camera_mode = "first",
}
local save = {
  inventory = { THUNDERBADGE = 1, HM02 = 1 },
  flags = { EVENT_GOT_STARTER = true },
  party = { { species = "PIDGEOT", freeFlyGift = true,
    moves = { { id = "FLY", pp = 15 } } } },
  modData = { free_fly = { giftTaken = true } },
}
local mod = { id = "voxel_run_bridge", exports = {},
  options = { get = function(_, key) return preferences[key] end } }
local profile = install(mod)
eq(mod.exports.classicRules, profile, "profile publishes its narrow API")
eq(profile:enabled(), false, "custom settings remain the default")
eq(profile:own("experience_mode", "all"), "all", "disabled profile passes preferences through")
eq(profile:vendor("free_fly", "quickstart", true), true, "disabled profile leaves gift preference alone")
eq(profile:skipVendor("all_pokemon_catchable_151_mod"), false, "custom boot retains catchable content")
eq(profile:status().restartRequired, false, "unchanged custom boot needs no reload")

local originalInventory = save.inventory
local originalFlags = save.flags
local originalParty = save.party
local originalMon = save.party[1]
local originalMoves = originalMon.moves
preferences.classic_rules = true
eq(profile:enabled(), false, "live preference cannot create a hybrid runtime profile")
eq(profile:requested(), true, "requested rules selection is visible")
eq(profile:status().restartRequired, true, "live selection announces required rules reload")
eq(profile:status().contentRules, "custom", "status honestly reports the current boot")
eq(profile:own("experience_mode", "all"), "all", "rules remain coherent before reload")
eq(profile:skipVendor("all_pokemon_catchable_151_mod"), false, "boot-only content selection cannot masquerade as live rollback")
local classicBoot = install(mod)
eq(classicBoot:enabled(), true, "new boot applies the requested classic rules")
eq(classicBoot:requested(), true, "new boot retains the requested choice")
for key, wanted in pairs(profile.ownOverrides) do
  eq(classicBoot:own(key, "custom"), wanted, "classic resolves owned option " .. key)
  check(classicBoot:ownsOverride(key), "owned key is declared " .. key)
end
for vendorId, values in pairs(profile.vendorOverrides) do
  for key, wanted in pairs(values) do
    eq(classicBoot:vendor(vendorId, key, "custom"), wanted,
      "classic resolves vendor option " .. vendorId .. ":" .. key)
    check(classicBoot:vendorOverride(vendorId, key), "vendor key is declared " .. vendorId .. ":" .. key)
  end
end
eq(classicBoot:own("running_enabled", true), true, "running remains an independent quality-of-life setting")
eq(classicBoot:own("running_speed", 1.5), 1.5, "running speed is not forced")
eq(classicBoot:own("early_flight", true), true, "earned early flight remains an explicit travel exception")
eq(classicBoot:own("camera_mode", "first"), "first", "first-person presentation is not forced")
eq(classicBoot:vendor("free_fly", "motion", true), true, "flight presentation is not forced")
eq(classicBoot:vendor("other_mod", "enabled", nil), nil, "unknown vendor values stay untouched")
eq(classicBoot:ownsOverride("camera_mode"), false, "unknown own setting is not a rule override")
eq(classicBoot:vendorOverride("other_mod", "enabled"), false, "unknown vendor has no rule override")
eq(preferences.hm_without_badges, true, "saved HM preference remains intact")
eq(preferences.experience_mode, "all", "saved EXP preference remains intact")
eq(save.inventory, originalInventory, "inventory table identity remains intact")
eq(save.flags, originalFlags, "story flag table identity remains intact")
eq(save.party, originalParty, "party table identity remains intact")
eq(save.party[1], originalMon, "owned Pokemon identity remains intact")
eq(originalMon.moves, originalMoves, "known moves remain intact")
eq(originalMon.freeFlyGift, true, "existing gift marker is never deleted")
eq(save.modData.free_fly.giftTaken, true, "one-time gift record is never reset")
eq(save.inventory.THUNDERBADGE, 1, "badge ownership remains intact")
eq(save.inventory.HM02, 1, "machine ownership remains intact")
eq(save.flags.EVENT_GOT_STARTER, true, "story progress remains intact")

preferences.classic_rules = false
eq(profile:own("hm_without_badges", preferences.hm_without_badges), true, "turning profile off restores prior HM preference")
eq(profile:own("experience_mode", preferences.experience_mode), "all", "turning profile off restores prior EXP preference")
eq(profile:status().restartRequired, false, "returning to boot content rules clears reload notice")
eq(classicBoot:own("hm_without_badges", true), false, "classic rules stay coherent until next reload")
eq(classicBoot:status().restartRequired, true, "turning classic rules off announces required reload")
local restored = install(mod)
eq(restored:own("experience_mode", preferences.experience_mode), "all", "next custom boot restores preserved preference")

preferences.classic_rules = true
eq(classicBoot:skipVendor("all_pokemon_catchable_151_mod"), true, "classic boot skips catchable encounter/evolution content")
eq(classicBoot:skipVendor("free_fly"), false, "normal Free Fly remains available under ordinary eligibility")
eq(classicBoot:status().contentRules, "classic", "classic boot content status is accurate")
eq(classicBoot:status().restartRequired, false, "classic boot is fully applied")
classicBoot.vendorOverrides.free_fly.quickstart = true
classicBoot.ownOverrides.hm_without_badges = true
classicBoot.skippedVendors.all_pokemon_catchable_151_mod = false
eq(classicBoot:vendor("free_fly", "quickstart", true), false, "exported map cannot change the gift rule")
eq(classicBoot:own("hm_without_badges", true), false, "exported map cannot change the HM rule")
eq(classicBoot:skipVendor("all_pokemon_catchable_151_mod"), true, "exported map cannot change boot content policy")
preferences.classic_rules = false
eq(classicBoot:status().restartRequired, true, "restoring custom content also announces a reload")
eq(classicBoot:skipVendor("all_pokemon_catchable_151_mod"), true, "boot selection stays stable until actual reload")

local noOptions = install({ exports = {} })
eq(noOptions:enabled(), false, "missing option API fails safely to existing behavior")
local throwing = install({ exports = {}, options = {
  get = function() error("simulated stale option API") end,
} })
eq(throwing:enabled(), false, "broken option API cannot break boot")
local invalid = install({ exports = {}, options = {
  get = function() return "true" end,
} })
eq(invalid:enabled(), false, "non-boolean preference cannot silently enable a profile")

if failures > 0 then error(tostring(failures) .. " classic rules checks failed") end
print("Scott's Tweaks classic rules: " .. checks .. " checks passed")
