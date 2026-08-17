# Changelog

## 0.7.0 - 2026-08-16

- Replaced the Gold-ROM import with a built-in, ROM-free **PACK + POKéGEAR**
  feature. Existing `gen2_menus` saves migrate automatically.
- The Red ITEM/ITEMS row is presented as **PACK** without changing its bag
  callback. The existing four-pocket projection remains the inventory owner.
- Added a separate root **POKéGEAR** row with a live, preference-aware clock
  and Red's native Kanto Map. No imported file, decoded art, or new APK picker
  is required, and Gen 1 Modern UI can remain enabled.
- Removed the optional Pokemon Gold import declaration and all runtime asset
  extraction. Historical 0.6.x behavior remains documented below only.

## 0.6.1 - 2026-08-16

- Gold Start now presents either native `ITEM` or `ITEMS` rows as **PACK** and
  places the separate **POKéGEAR** row immediately after `ITEM`, `ITEMS`, or an
  existing `PACK` row. The original descriptor and Red bag callback remain
  unchanged.
- Changed the Red pocket projection and Gold Pack presentation to the exact
  Gold cycle: **ITEMS -> BALLS -> KEY ITEMS -> TM/HM**. Item use, SELECT
  reorder, quantities, capacity, and the underlying Red inventory are still
  authoritative.
- Renamed the central option to **CLASSIC BAG POCKETS** with explicit D-pad and
  Gold dependency help. The organized Scott's Tweaks menu hides that redundant
  row while **GEN 2 INTERFACE** is enabled; Gold Pack continues to keep the
  required projection active without overwriting the saved classic preference.

## 0.6.0 - 2026-08-16

- Added the optional **GEN 2 INTERFACE**. It uses the player's privately
  imported, exact USA/Europe Pokemon Gold ROM to draw authentic Gold Start,
  Pack/backpack/pocket and Pokegear Clock/Kanto Map presentation. No ROM or
  extracted image is included in the mod or its GitHub release.
- Kept Red's live controllers and data authoritative underneath the new look:
  item use/toss/reorder, battle items, Trade Stone, EXP.SHARE, mod-added Start
  rows and Scott's four pocket backend continue to work.
- Gen 1 Modern UI can remain enabled. Gold presentation owns only the Start,
  Pack and Pokegear surfaces; Modern UI continues to present Party, Pokedex,
  Options, Mod Manager, PC, Shop and the other supported screens.
- Scott's existing Thor presenter automatically sends the Gold menu canvas to
  the lower screen. The Gold interface remains controller-operated and does
  not add a second display owner.
- Added a stable optional Gold ROM import that survives same-ID in-app updates.
  Missing imports fail open: every other Scott's Tweaks feature still loads.
- The Kanto Map marker uses Gold's authentic animated Chris overworld frames
  and exact PAL_OW_RED morning/day/night/dark palettes from the imported ROM;
  no replacement marker art is generated or shipped.

## 0.5.0 - 2026-08-16

- Added one categorized **START > MOD MENUS > SCOTT'S TWEAKS** surface with
  Bag & Experience, Trainers & Oak, Running, Field Moves, and Display & Thor
  pages. All 16 values remain in one Mod Manager schema and both menus write
  the same live/save option buckets.
- Incorporated the MIT Trainer Forfeit & Rematches 0.3.0 implementation under
  the namespaced `trainerForfeit` export: ¥200 ordinary-trainer forfeits,
  reward-safe ordinary and eight-Gym-Leader rematches, offline authored
  journey dialogue, and optional gentle repeat-battle growth. Paid RUN and
  rematches are independent toggles; disabling one does not disable the other.
- Incorporated the MIT Oak's Spare Starter 0.1.1 implementation under the
  namespaced `oakSpareStarter` export. Red/Blue can claim the one remaining
  lab starter once after the rival battle; Yellow remains unchanged.
- Added Scott's always-available held-B running producer, defaulting to 1.5X,
  without a story unlock. Bikes, surfing, scripted movement, and input locks
  remain on their native paths.
- Added an original, very light distance-based first-person running bob,
  defaulting on at 0.5X. It samples actual movement and changes only a camera
  proxy for that frame; player lift, collision, and world state are untouched.
- Made the bob and voxel-speed wrappers persistent owned dispatchers. A second
  real Loader entry refreshes generation-local callbacks without growing the
  wrapper chain or applying the 1.5X multiplier twice.
- Delegated only the corresponding integrated feature when an enabled
  `trainer_forfeit`, `oak_spare_starter`, or `running_shoes` provider is
  present. `random_starters` disables only Oak's lab feature; every unrelated
  Scott's Tweaks feature remains available. Hot-reload transitions suspend
  Tweaks' retained Trainer/Running dispatchers and resume them without stacking
  when the standalone provider is removed.
- Added a one-time, per-save, per-feature, non-destructive import for legacy trainer
  settings/memory, Oak's claim, distinctive 0.x running settings, Scott Mod
  run settings, and `gen1recomp_ds.enabled`. Explicit new choices win and no
  legacy namespace is erased. A feature stays pending while its old provider
  remains active, then imports its final legacy state after removal.
- Added the default-off **THOR SECOND SCREEN** authority for the new original
  physical-Thor presenter. It stays single-screen when no real lower display
  is attached and includes no private upstream-derived Dual Screen or Battle
  Art implementation.
- Preserved the stable `voxel_run_bridge` ID and
  `ScottExplores/gen1recomp-voxel-run-bridge` updater address.
- Added `THIRD_PARTY_NOTICES.md` with the retained MIT copyrights and terms
  for incorporated Scott-owned releases.
- Expanded ROM-free unit, migration, real API-2 Loader, and four-entry hot
  reload coverage across Gen1Recomp 0.1.88 and 0.1.96 fixtures.

## 0.4.3 - 2026-08-16

- Renamed the player-facing download to `SCOTTS_TWEAKS-0.4.3.zip` so the ZIP
  name now matches the **Scott's Tweaks** name shown in Gen1Recomp.
- Preserved the internal `voxel_run_bridge` mod ID and GitHub updater address.
  Existing installations, saved settings, compatibility hooks, and automatic
  updates therefore continue in place without creating a duplicate mod.
- This is a packaging-and-labeling release; gameplay behavior is unchanged
  from 0.4.2.

## 0.4.2 - 2026-08-16

- Added **FLY COCKPIT**, defaulting to OFF, for players who want Free Fly
  1.6.2's extra first-person mount picture hidden. The adapter uses Free Fly's
  public flight-state export and the voxel provider's published FirstPerson
  visibility query, and changes that query only inside the downstream HUD
  call. The world-space mount, third-person view, flight movement, collision,
  encounters, and landing are unchanged.
- Scoped the cockpit adapter to the exact verified Free Fly 1.6.2 HUD contract.
  Missing providers, missing APIs, and later Free Fly versions remain
  untouched instead of receiving a speculative compatibility patch.
- Documented that the bundled thorkdev Running Shoes 0.3.0 already owns the
  requested running-only view bob. **VIEW BOB: ON** plus **BOB INTENSITY:
  0.5X** is its lightest setting, so Scott's Tweaks adds no duplicate bob.

## 0.4.1 - 2026-08-15

- Added Battle Art Voxel Fork to the capability-tested **GAPPED LAND**
  providers. Battle Art already exposed the same `VoxelScene`, `Voxel3D`,
  `VoxelState`, `DayNight`, and `Mat4` adapter surface used by the existing
  providers; the visual apron remains Scott-owned and presentation-only.
- Verified the provider path without changing Battle Art terrain, collision,
  map connections, live mesh streaming, or any disk/session cache input.
- Verified the existing Free Fly adapter with current Free Fly 1.6.2 and the
  full mod loader on Gen1Recomp 0.1.88 and 0.1.96.

## 0.4.0 - 2026-08-13

- Added the default-on **BAG POCKETS** view. Left/Right switches between
  ITEMS, BALLS, TM/HM, and KEY ITEMS while the original inventory, capacity,
  quantities, item-use flows, and global SELECT order remain authoritative.
- Added a live **BAG:N** quantity indicator to the mart BUY screen without
  replacing prices, money, purchase rules, or another mod's existing stock.
- Added **EXP. MODE** with VANILLA, LEAD ONLY, PARTY ALL, and EXP.SHARE.
  VANILLA remains the update-safe default. Custom modes reuse the engine's
  award path, preserve event/stat/move/evolution hooks, and restore the real
  EXP.ALL inventory value after every award, including on errors.
- Added the passive **EXP.SHARE** key item. It is granted once when that mode
  is first selected, stays unlocked when another mode is chosen, and retries
  safely when the bag is full or the item was restored to the PC.
- Added the ₽500 **TRADE STONE** to Gen 1 shops. It evolves Kadabra, Machoke,
  Graveler, and Haunter through the normal item-evolution sequence while
  leaving native link-trade evolution definitions unchanged.
- Added a narrowly namespaced compatibility adapter for Gen1Recomp 0.1.75,
  whose content registry predates custom-item effect dispatch. Every other
  item delegates to the engine unchanged; newer engines receive the same
  registered effect result.
- Declared `affects_link: false`: the added inventory/UI content does not
  alter battle or trade rules, and the evolved results are native species.

## 0.3.0 - 2026-08-13

- Added the default-on **GAPPED LAND** presentation option for Pokemon Final
  and compatible Dramatic Shape renderers. In outdoor/open-air **1ST** and
  **3RD** views, an independently generated visual land plane covers otherwise
  exposed space beneath the distant horizon while leaving the real maps,
  collision, connections, warps, and player movement unchanged.
- Feature-detected the provider's exported renderer capabilities and kept the
  plane out of interiors, canopy scenes, and sea maps. Unsupported or
  unfamiliar providers fail safely without changing their renderer. No
  third-party renderer source or art is included in this public mod.
- Kept the feature independent of Pokemon Final's voxel disk cache. Switching
  it does not delete, start, or rebuild the disk cache or invalidate the
  provider's cached terrain meshes.
- Added unit and production-loader coverage for the new settings row,
  capability detection, live enable/disable behavior, gameplay-state
  isolation, and the no-compatible-renderer fallback.

## 0.2.3 - 2026-08-13

- Added a behavior-probed compatibility fix for the false **COULD NOT START**
  result in early Pokemon Final disk-cache screens. A confirmed running build
  now clears only that fallback; real cache errors remain visible.
- Kept the fix ownership-marked, idempotent, and reversible. It declines an
  unknown module shape or a wrapper owned by another mod.
- Verified that Pokemon Final `1.8.1-scott.2` receives the fix while the exact
  corrected `1.8.1-scott.3` package is detected as already safe and remains
  untouched under Gen1Recomp 0.1.75 and 0.1.80.
- Kept all Pokemon Final source and assets out of this public package; the
  adapter uses only the private mod's deliberately exported module seam.

## 0.2.2 - 2026-08-13

- Added `POKEMON_FINAL` as a supported voxel provider, so Running Shoes speed
  now reaches Pokemon Final's first- and third-person FreeMove path.
- Detect Running Shoes 1.7's native `FreeMove` ownership markers and stay idle
  when it already owns a voxel provider, preventing a doubled speed boost.
- Replaced the Dramatic Sky Ride-only adapter with the default-on **FREE FLY
  NOW** option, tested with Free Fly 1.5.0 and 1.6.1. It feature-detects Free
  Fly's public flight state and registered `badges` toggle before applying the
  live override.
- Free Fly's exact prior **BADGE CHECKS** value is preserved and restored when
  Scott's override is disabled. FLY eligibility, story gates, map rules, and
  save data remain unchanged. Free Fly uses the same toggle for Thunder Badge
  takeoff and Soul Badge water landing, so both badge checks are relaxed.
- Removed Dramatic Sky Ride from the active compatibility dependency list.
- Documented Free Fly 1.6.1+ as the recommended version for Pokemon Final;
  its capability-based voxel lookup recognizes the renamed private provider.

## 0.2.1 - 2026-08-13

- Added the default-on **SKY RIDE NOW** option. It feature-detects Dramatic
  Sky Ride 0.1.6+'s flight-rules interface and disables that mod's own
  Thunder Badge takeoff check at runtime.
- Kept Dramatic Sky Ride's **REQUIRE FLY**, **STORY GATES**, and
  **DISCOVERY GATES** rules intact. No badge or story flag is written.
- Preserved and restored the player's exact Dramatic Sky Ride **BADGE CHECKS**
  preference when Scott's override is disabled.
- Added unit and production-loader coverage for badge-less takeoff, option
  isolation, save integrity, missing/incompatible Sky Ride versions, and
  preference restoration.

## 0.2.0 - 2026-08-13

- Renamed the visible mod from Voxel Run Bridge to Scott's Tweaks while
  retaining the internal `voxel_run_bridge` ID for seamless updates.
- Added the default-on **BADGE-FREE HMS** option for Cut, Fly, Surf, Strength,
  and Flash. Pokemon must still know the move, and normal context checks stay
  intact.
- Added party-menu actions for known HMs hidden only by a missing badge,
  without writing badge flags or teaching moves.
- Documented the supported **BADGE CHECKS = OFF** setting required by
  Dramatic Sky Ride and Free Fly, which perform an additional private check.
- Raised the tested Gen1Recomp floor to 0.1.75 for the field-move and party UI
  hook contracts.

## 0.1.1 - 2026-08-13

- Added the public GitHub repository metadata used by Gen1Recomp's built-in
  release update checker.
- No gameplay behavior changed from 0.1.0.

## 0.1.0 - 2026-08-11

- Bridge the engine's `movement.speed` hook into voxel `FreeMove` walking.
- Support Dramatic Shape, Battle Art Voxel Fork, Dramaless Shape, and
  PotatoVoxel manifest IDs.
- Defer to Running Shoes releases that already own their voxel integration.
- Skip hook evaluation during scripted or input-locked movement.
- Restore voxel speed constants even if a wrapped tick fails.
