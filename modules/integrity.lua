-- Partial-install detection.
--
-- The engine's mod installer deletes the old tree and then copies the new one
-- file by file on the main thread. Interrupted on a handheld -- power, OOM,
-- the OS killing a backgrounded app -- it leaves a tree that still LOADS
-- (manifest.json and modules/ copy early) with entire vendor/ subtrees
-- missing, which presents as "the mod runs but sprites are gone" and gives
-- the player nothing to go on. This cannot repair anything; it exists so the
-- failure names itself: MOD SETTINGS shows a PARTIAL INSTALL banner and the
-- log says which subtree is gone.
--
-- A small fixed set of sentinel files covers code plus the sprite families
-- whose absence otherwise looks like a gameplay/configuration bug.  It is
-- checked once at load through the mod's own reader; there is no tree walk.

local SENTINELS = {
  { path = "battle_art_main.lua", what = "Battle Art renderer entry" },
  { path = "lib/SettingsMenu.lua", what = "Battle Art lib/" },
  { path = "data/voxel_heights.lua", what = "Battle Art data/" },
  { path = "assets/battle/front-static/README.md", what = "Battle Art battle art" },
  { path = "modules/vendor_host.lua", what = "bundled-mod host" },
  { path = "vendor/wilds/main.lua", what = "Wilds of Kanto" },
  { path = "vendor/wilds/lib/spawn_logic.lua", what = "Wilds of Kanto lib/" },
  { path = "vendor/wilds/assets/generated/followsprites_runtime/001-normal.png",
    what = "Wilds follower and overworld sprite art" },
  { path = "vendor/wilds/assets/enhanced_overworld/followsprites_mapping/followsprites_mapping.json",
    what = "Wilds follower sprite mapping" },
  { path = "vendor/crystal/main.lua", what = "Crystal Animated Sprites" },
  { path = "vendor/crystal/species_map.lua", what = "Crystal species map" },
  { path = "vendor/crystal/assets/back/normal/1.png", what = "Crystal sprite art" },
  { path = "vendor/crystal/assets/front/normal/1/001.png",
    what = "Crystal front sprite art" },
  { path = "vendor/crystal/assets/overworld/player/red.png",
    what = "Crystal overworld sprite art" },
  { path = "vendor/unique_menu_icons/main.lua", what = "Unique Menu Icons" },
  { path = "vendor/unique_menu_icons/assets/icon_original/BULBASAUR.png",
    what = "Unique Menu Icons sprite art" },
  { path = "vendor/free_fly/main.lua", what = "Free Fly" },
  { path = "vendor/choose_lead/main.lua", what = "Choose Lead" },
  { path = "vendor/dynamic_scaling/main.lua", what = "Dynamic Scaling" },
  { path = "vendor/catchable151/main.lua", what = "All Pokemon Catchable 151" },
}

return function(mod)
  local missing = {}
  for _, sentinel in ipairs(SENTINELS) do
    local present = false
    if type(mod.info) == "function" then
      local ok, info = pcall(mod.info, mod, sentinel.path)
      present = ok and info ~= nil
    end
    if not present then
      -- info can be unavailable in bare harnesses; read() is authoritative.
      local ok, body = pcall(mod.read, mod, sentinel.path)
      present = ok and type(body) == "string"
    end
    if not present then
      missing[#missing + 1] = sentinel
    end
  end

  local report = {
    ok = #missing == 0,
    missingCount = #missing,
    checked = #SENTINELS,
    missing = missing,
  }
  mod.exports.integrity = report

  if #missing > 0 then
    for _, sentinel in ipairs(missing) do
      mod.log:warn(
        "PARTIAL INSTALL: %s is missing (%s). Delete and reinstall Scott's Tweaks.",
        sentinel.path, sentinel.what)
    end
  end
  return report
end
