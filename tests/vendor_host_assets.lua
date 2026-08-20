-- Focused regression for bundled-mod facade rooting.
--
-- Android's filesystem is case-sensitive, so this uses a string-keyed memfs
-- and only accepts exact paths.  A vendor handle must never fall back to the
-- host root for assets, directory queries, or file metadata.
--
--   luajit tests/vendor_host_assets.lua <mod-root>

local argv = rawget(_G, "arg") or {}
local sourceRoot = (argv[1] or "."):gsub("\\", "/"):gsub("/$", "")
local VendorHost = assert(loadfile(sourceRoot .. "/modules/vendor_host.lua"))()

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function eq(actual, expected, message)
  checks = checks + 1
  assert(actual == expected, ("%s: expected %s, got %s")
    :format(message, tostring(expected), tostring(actual)))
end

local HOST_ROOT = "mods/voxel_run_bridge"
local WILD_SPRITE = "assets/generated/followsprites_runtime/001-normal.png"
local ICON_SPRITE = "assets/icon_original/BULBASAUR.png"

-- Keys are intentionally case-sensitive.  In particular, no alternate entry
-- exists for 001-NORMAL.png or icon_original/bulbasaur.png.
local fsInfo = {
  ["vendor/wilds"] = { type = "directory" },
  ["vendor/wilds/assets"] = { type = "directory" },
  ["vendor/wilds/assets/generated/followsprites_runtime"] = { type = "directory" },
  ["vendor/wilds/" .. WILD_SPRITE] = { type = "file", size = 101 },
  ["vendor/wilds/main.lua"] = { type = "file", size = 202 },
  ["vendor/unique_menu_icons"] = { type = "directory" },
  ["vendor/unique_menu_icons/assets"] = { type = "directory" },
  ["vendor/unique_menu_icons/assets/icon_original"] = { type = "directory" },
  ["vendor/unique_menu_icons/" .. ICON_SPRITE] = { type = "file", size = 303 },
}
local fsLists = {
  ["vendor/wilds"] = { "assets", "main.lua" },
  ["vendor/wilds/assets"] = { "generated" },
  ["vendor/wilds/assets/generated/followsprites_runtime"] = { "001-normal.png" },
  ["vendor/unique_menu_icons"] = { "assets" },
  ["vendor/unique_menu_icons/assets/icon_original"] = { "BULBASAUR.png" },
}
local fileBodies = {
  ["vendor/wilds/main.lua"] = "return function() end",
}
local seen = {}
local optionValues = { enabled = "host value must not leak" }
local contentAlias = {}

local function copyList(items)
  local out = {}
  for i = 1, #(items or {}) do out[i] = items[i] end
  return out
end
local function full(relative)
  return HOST_ROOT .. "/" .. relative
end

local hostMod = {
  id = "voxel_run_bridge",
  path = HOST_ROOT,
  exports = {},
  find = function() return nil end,
  options = {
    get = function(_, key)
      seen.optionKey = key
      return optionValues[key]
    end,
  },
  hooks = {
    wrap = function() end,
  },
}
hostMod.read = function(_, relative)
  seen.read = relative
  local body = fileBodies[relative]
  assert(body ~= nil, "case-sensitive read missed " .. tostring(relative))
  return body
end
hostMod.list = function(_, relative)
  seen.modList = relative
  return copyList(fsLists[relative])
end
hostMod.info = function(_, relative)
  seen.modInfo = relative
  return fsInfo[relative]
end
hostMod.assets = {
  pokemon = contentAlias,
  path = function(_, relative)
    seen.assetPath = relative
    return full(relative)
  end,
  image = function(_, relative)
    seen.assetImage = relative
    local info = fsInfo[relative]
    assert(info and info.type == "file",
      "case-sensitive image load missed " .. tostring(relative))
    return { path = full(relative) }
  end,
  list = function(_, relative)
    seen.assetList = relative
    return copyList(fsLists[relative])
  end,
  info = function(_, relative)
    seen.assetInfo = relative
    return fsInfo[relative]
  end,
}

local function entry(id)
  for _, candidate in ipairs(VendorHost.MODS) do
    if candidate.id == id then return candidate end
  end
  error("missing vendor entry " .. id)
end

local host = VendorHost.new(hostMod)
local wildEntry = entry("overworld_wild_spawns")
local iconsEntry = entry("unique_menu_icons")
local wild = host:handleFor(wildEntry)
local icons = host:handleFor(iconsEntry)

eq(host:_find("BATTLE_ART_VOXEL_FORK"), nil,
  "renderer alias is absent before the fused renderer installs")
hostMod.exports.fusedRenderer = {
  installed = false, reason = "external_voxel",
}
hostMod.exports.lib = { require = function() return {} end }
eq(host:_find("BATTLE_ART_VOXEL_FORK"), nil,
  "renderer alias is absent when the fused renderer stands down")
hostMod.exports.fusedRenderer = { installed = true }
hostMod.exports.lib = {}
eq(host:_find("BATTLE_ART_VOXEL_FORK"), nil,
  "renderer alias requires the fused module loader capability")
hostMod.exports.lib.require = function() return {} end
local fusedRendererHandle = host:_find("BATTLE_ART_VOXEL_FORK")
eq(fusedRendererHandle and fusedRendererHandle.exports, hostMod.exports,
  "installed renderer alias resolves the host root exports")

eq(wild.path, HOST_ROOT .. "/vendor/wilds", "vendor mod.path is rooted")
eq(wild:read("main.lua"), fileBodies["vendor/wilds/main.lua"],
  "vendor read reaches its own file")
eq(seen.read, "vendor/wilds/main.lua", "vendor read delegates exact path")

eq(wild.assets:path(WILD_SPRITE),
  HOST_ROOT .. "/vendor/wilds/" .. WILD_SPRITE,
  "Wilds asset path includes vendor root")
eq(seen.assetPath, "vendor/wilds/" .. WILD_SPRITE,
  "Wilds asset path delegates exact relative path")
local wildImage = wild.assets:image(WILD_SPRITE)
eq(wildImage.path, HOST_ROOT .. "/vendor/wilds/" .. WILD_SPRITE,
  "Wilds image loads from vendor root")
eq(seen.assetImage, "vendor/wilds/" .. WILD_SPRITE,
  "Wilds image delegates exact relative path")

local assetItems = wild.assets:list("assets/generated/followsprites_runtime")
eq(assetItems[1], "001-normal.png", "assets:list sees Wilds sprite directory")
eq(seen.assetList, "vendor/wilds/assets/generated/followsprites_runtime",
  "assets:list delegates exact vendor directory")
eq(wild.assets:info(WILD_SPRITE).size, 101,
  "assets:info sees Wilds sprite")
eq(seen.assetInfo, "vendor/wilds/" .. WILD_SPRITE,
  "assets:info delegates exact vendor file")

local modItems = wild:list("assets")
eq(modItems[1], "generated", "mod:list sees Wilds assets")
eq(seen.modList, "vendor/wilds/assets", "mod:list delegates exact vendor directory")
eq(wild:info(WILD_SPRITE).size, 101, "mod:info sees Wilds sprite")
eq(seen.modInfo, "vendor/wilds/" .. WILD_SPRITE,
  "mod:info delegates exact vendor file")

-- list/info permit an omitted relative path in the engine API.  For a proxy,
-- that means the vendor root, never Scott's Tweaks' root.
eq(wild.assets:list()[1], "assets", "assets:list() lists vendor root")
eq(seen.assetList, "vendor/wilds", "assets:list() delegates vendor root")
eq(wild.assets:info().type, "directory", "assets:info() describes vendor root")
eq(seen.assetInfo, "vendor/wilds", "assets:info() delegates vendor root")
eq(wild:list("")[1], "assets", "mod:list(empty) lists vendor root")
eq(seen.modList, "vendor/wilds", "mod:list(empty) delegates vendor root")
eq(wild:info().type, "directory", "mod:info() describes vendor root")
eq(seen.modInfo, "vendor/wilds", "mod:info() delegates vendor root")
eq(wild.assets.pokemon, contentAlias, "assets content aliases remain inherited")

eq(wild.assets:info("assets/generated/followsprites_runtime/001-NORMAL.png"), nil,
  "wrong-case Wilds asset is absent on Android-like memfs")
eq(icons.assets:info("assets/icon_original/bulbasaur.png"), nil,
  "wrong-case menu icon is absent on Android-like memfs")
eq(icons.assets:path(ICON_SPRITE),
  HOST_ROOT .. "/vendor/unique_menu_icons/" .. ICON_SPRITE,
  "menu icon path includes its own vendor root")
eq(icons.assets:image(ICON_SPRITE).path,
  HOST_ROOT .. "/vendor/unique_menu_icons/" .. ICON_SPRITE,
  "menu icon image loads with exact Android casing")

-- Two bundled mods may both define `enabled`; their defaults and saved values
-- must remain independent inside the one host options bucket.
local wildSchema = { { key = "enabled", type = "boolean", default = true } }
local iconSchema = { { key = "enabled", type = "boolean", default = false } }
wild.options:define(wildSchema)
icons.options:define(iconSchema)
eq(wild.options:get("enabled"), true, "Wilds receives its own default")
eq(seen.optionKey, "overworld_wild_spawns:enabled",
  "Wilds reads its namespaced key")
eq(icons.options:get("enabled"), false, "menu icons receive their own default")
eq(seen.optionKey, "unique_menu_icons:enabled",
  "menu icons read their namespaced key")

optionValues["overworld_wild_spawns:enabled"] = false
optionValues["unique_menu_icons:enabled"] = true
eq(wild.options:get("enabled"), false, "Wilds saved value stays isolated")
eq(icons.options:get("enabled"), true, "menu icon saved value stays isolated")

-- Programmatic vendor UIs receive an explicit canonical storage/writer seam.
-- This is the path Wilds' FOLLOW/DISMISS and migrations use when bundled.
eq(wild.options.hosted.hostId, "voxel_run_bridge",
  "hosted option metadata identifies the canonical bucket")
eq(wild.options.hosted.vendorId, "overworld_wild_spawns",
  "hosted option metadata retains the vendor identity")
eq(wild.options.hosted.prefix, "overworld_wild_spawns:",
  "hosted option metadata exposes the canonical prefix")
local emitted, optionWrites = {}, 0
local events = { emit = function(_, name, payload)
  emitted[#emitted + 1] = { name = name, payload = payload }
end }
local optionGame = {
  save = { options = {} },
  mods = { loader = { events = events } },
  writeOptions = function() optionWrites = optionWrites + 1 end,
}
eq(wild.options:write(optionGame, "follower_count", 0), true,
  "hosted option writer accepts a Wilds logical key")
local canonical = optionGame.save.options.modOptions.voxel_run_bridge
eq(canonical["overworld_wild_spawns:follower_count"], 0,
  "hosted writer persists the canonical save key")
eq(optionGame.save.options.modOptions.overworld_wild_spawns, nil,
  "hosted writer creates no stray vendor save bucket")
eq(optionGame.mods.modOptions.voxel_run_bridge[
    "overworld_wild_spawns:follower_count"], 0,
  "hosted writer mirrors the direct Loader facade")
eq(optionGame.mods.loader.modOptions.voxel_run_bridge[
    "overworld_wild_spawns:follower_count"], 0,
  "hosted writer mirrors a nested Loader")
eq(optionWrites, 1, "hosted writer persists once")
eq(#emitted, 0,
  "vendor Config writer leaves live notification to its direct callback")

canonical["overworld_wild_spawns:grass_encounters"] = "both"
optionGame.mods.modOptions.voxel_run_bridge[
  "overworld_wild_spawns:grass_encounters"] = "both"
optionGame.mods.loader.modOptions.voxel_run_bridge[
  "overworld_wild_spawns:grass_encounters"] = "both"
eq(wild.options:writeMany(optionGame, {
  { key = "enable_hidden", value = false },
  { key = "random_encounters", value = false },
  { key = "enabled", value = true },
  { key = "grass_encounters", value = nil },
}), true, "hosted multi-writer accepts an atomic encounter snapshot")
eq(canonical["overworld_wild_spawns:enable_hidden"], false,
  "multi-writer stores hidden OFF")
eq(canonical["overworld_wild_spawns:random_encounters"], false,
  "multi-writer stores random encounters OFF")
eq(canonical["overworld_wild_spawns:enabled"], true,
  "multi-writer stores visible encounters ON")
for _, bucket in ipairs({
  canonical,
  optionGame.mods.modOptions.voxel_run_bridge,
  optionGame.mods.loader.modOptions.voxel_run_bridge,
}) do
  eq(bucket["overworld_wild_spawns:grass_encounters"], nil,
    "multi-writer removes an obsolete key in every mirror")
end
eq(optionWrites, 2, "multi-writer adds exactly one persisted transaction")
eq(#emitted, 0, "multi-writer leaves one live callback to vendor Config")

-- A failed options.lua write must restore the exact save/direct/nested Loader
-- state, including legacy aliases scheduled for deletion. Config will only
-- announce Encounter Mode after this writer returns true.
local roots = {
  optionGame.save.options.modOptions,
  optionGame.mods.modOptions,
  optionGame.mods.loader.modOptions,
}
for _, root in ipairs(roots) do
  root.voxel_run_bridge["overworld_wild_spawns:enabled"] = false
  root.voxel_run_bridge["overworld_wild_spawns:random_encounters"] = true
  root.voxel_run_bridge["overworld_wild_spawns:enable_hidden"] = true
  root.overworld_wild_spawns = {
    enabled = false,
    random_encounters = true,
    enable_hidden = true,
    grass_encounters = "both",
    unrelated = "keep",
  }
end
local oldWriteOptions = optionGame.writeOptions
local failedWrites = 0
optionGame.writeOptions = function()
  failedWrites = failedWrites + 1
  error("simulated storage failure")
end
local failed, failureReason = wild.options:writeMany(optionGame, {
  { key = "enable_hidden", value = false },
  { key = "random_encounters", value = false },
  { key = "enabled", value = true },
  { key = "grass_encounters", value = nil },
}, {
  legacyKeys = {
    "enabled", "random_encounters", "enable_hidden", "grass_encounters",
  },
})
eq(failed, false, "failed multi-write propagates persistence failure")
check(type(failureReason) == "string"
    and failureReason:find("simulated storage failure", 1, true) ~= nil,
  "failed multi-write returns the storage error")
eq(failedWrites, 1, "failed multi-write attempts persistence exactly once")
for _, root in ipairs(roots) do
  eq(root.voxel_run_bridge["overworld_wild_spawns:enabled"], false,
    "rollback restores canonical enabled in every mirror")
  eq(root.voxel_run_bridge["overworld_wild_spawns:random_encounters"], true,
    "rollback restores canonical random mode in every mirror")
  eq(root.voxel_run_bridge["overworld_wild_spawns:enable_hidden"], true,
    "rollback restores canonical hidden mode in every mirror")
  eq(root.overworld_wild_spawns.enabled, false,
    "rollback retains legacy enabled in every mirror")
  eq(root.overworld_wild_spawns.random_encounters, true,
    "rollback retains legacy random mode in every mirror")
  eq(root.overworld_wild_spawns.enable_hidden, true,
    "rollback retains legacy hidden mode in every mirror")
  eq(root.overworld_wild_spawns.grass_encounters, "both",
    "rollback retains legacy grass mode in every mirror")
  eq(root.overworld_wild_spawns.unrelated, "keep",
    "rollback retains unrelated legacy data in every mirror")
end
optionGame.writeOptions = function()
  failedWrites = failedWrites + 1
  return false, "storage rejected write"
end
local rejected, rejectedReason = wild.options:writeMany(optionGame, {
  { key = "enabled", value = true },
}, { legacyKeys = { "enabled" } })
eq(rejected, false, "explicit false persistence result propagates")
check(type(rejectedReason) == "string"
    and rejectedReason:find("storage rejected write", 1, true) ~= nil,
  "explicit false persistence result retains its detail")
eq(failedWrites, 2,
  "throwing and false-returning failures each attempt one transaction")
for _, root in ipairs(roots) do
  eq(root.voxel_run_bridge["overworld_wild_spawns:enabled"], false,
    "false-result rollback restores canonical enabled")
  eq(root.overworld_wild_spawns.enabled, false,
    "false-result rollback retains the legacy alias")
end
optionGame.writeOptions = oldWriteOptions

-- The unified menu calls VendorHost directly and still announces both ids.
eq(host:writeOption(optionGame, "overworld_wild_spawns",
    "follower_count", 2), true,
  "public host writer accepts a unified-menu change")
eq(#emitted, 2, "public host writer announces host and vendor identities")
eq(emitted[1].payload.mod, "voxel_run_bridge",
  "public writer emits the canonical host event")
eq(emitted[1].payload.key, "overworld_wild_spawns:follower_count",
  "host event uses the namespaced key")
eq(emitted[2].payload.mod, "overworld_wild_spawns",
  "public writer emits the live vendor event")
eq(emitted[2].payload.key, "follower_count",
  "vendor event uses the logical key")

local mergedByKey = {}
local merged = host:mergedSchema()
for _, row in ipairs(merged) do mergedByKey[row.key] = row end
eq(#merged, 2, "merged schema includes both vendor rows")
check(mergedByKey["overworld_wild_spawns:enabled"] ~= nil,
  "merged schema namespaces Wilds")
check(mergedByKey["unique_menu_icons:enabled"] ~= nil,
  "merged schema namespaces menu icons")
eq(wildSchema[1].key, "enabled", "merging does not mutate Wilds schema")
eq(iconSchema[1].key, "enabled", "merging does not mutate icon schema")

-- Loader keeps enabled-but-broken entries in loader.mods so the Manager can
-- explain their failure. They are not runtime providers: registrations were
-- rolled back, and the bundled fallback must remain eligible.
local oldGameLoaded = package.loaded["src.core.Game"]
local oldGamePreload = package.preload["src.core.Game"]
local loaderShape = {
  mods = {
    pending = { enabled = true, state = "pending" },
    loaded = { enabled = true, state = "loaded" },
    failed = { enabled = true, failed = true, state = "failed" },
    skipped = { enabled = true, failed = true, state = "wrong_generation" },
    disabled = { enabled = false, state = "disabled" },
  },
  disabled = { disabled = true },
}
package.loaded["src.core.Game"] = nil
package.preload["src.core.Game"] = function()
  return { mods = loaderShape }
end
local ownershipHost = VendorHost.new({ find = function() return nil end })
check(ownershipHost:_standaloneWillRun("pending"),
  "an enabled pending standalone retains ownership")
check(ownershipHost:_standaloneWillRun("loaded"),
  "a loaded standalone retains ownership")
check(not ownershipHost:_standaloneWillRun("failed"),
  "a failed standalone does not suppress the bundled fallback")
check(not ownershipHost:_standaloneWillRun("skipped"),
  "a Loader-skipped standalone does not suppress the bundled fallback")
check(not ownershipHost:_standaloneWillRun("disabled"),
  "a disabled standalone does not suppress the bundled fallback")
check(not ownershipHost:_standaloneWillRun("absent"),
  "an absent standalone does not suppress the bundled fallback")
package.loaded["src.core.Game"] = oldGameLoaded
package.preload["src.core.Game"] = oldGamePreload

io.stdout:write(("vendor host asset facade: %d checks passed\n"):format(checks))
