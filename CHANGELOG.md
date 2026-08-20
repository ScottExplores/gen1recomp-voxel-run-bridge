# Changelog

## 0.12.2 - 2026-08-20

- **Added a Crystal-style Pack without importing ROM art.** PACK now uses the
  original four-pocket order, five visible two-line item rows, quantities,
  TM/HM move names, a persistent description box, scroll arrows, and separate
  cursor/scroll memory for each pocket. Red's real inventory, item callbacks,
  battle use, GIVE-compatible actions, shops, and saved item order remain the
  authority.
- **Expanded the built-in Pokégear to four useful cards.** CLOCK shows live
  time, MAP opens Red's native Kanto map, PHONE summarizes Scott's existing
  trainer/rematch history without inventing Gen II scripts, and RADIO plays
  only songs present in the active Red data before restoring map music.
  Everything is rendered from original primitives and needs no Gold/Crystal
  ROM or separate mod.
- **Moved Free Fly's first-person rider and mount to the Thor's upper screen.**
  The physical lower display no longer captures or duplicates Pidgeot while
  the flight world remains above. Third-person and ordinary single-screen
  Free Fly behavior are unchanged.
- **Made PACK + POKéGEAR the new-install default.** An existing explicitly
  saved OFF choice remains respected.

## 0.12.1 - 2026-08-20

- **Restored the complete settings surface.** Left/Right and A now switch
  **OPTIONS SHOWN** between BASIC and ALL through the real in-game input path.
  ALL again exposes every first-person/camera control, every Battle Art source
  selector, Crystal's provider options, and the detailed advanced rows without
  changing values merely because they are hidden in BASIC. Crystal's
  **ANIMATIONS** choice is retained, and **CLASSIC POCKETS** stays editable
  even while PACK temporarily owns the active pocket presentation.
- **Made organized settings transactional.** Scott, Battle Art, Wilds, and
  cross-provider Crystal ownership rows now change save/live state only after
  one successful device write. A rejected Android write restores table
  identity, cached values, and legacy mirrors without a false confirmation or
  partial sprite-owner profile.
- **Added independent Pokémon orientation controls.** Player front, player
  back, and opponent cards can each retain authored direction or be mirrored;
  trainer portraits are never flipped by these rows.
- **Fixed Crystal white seams after a reload.** Crystal now refreshes its
  authored-transparency predicate by provider ID, so transparent gaps between
  arms and other sprite details do not get reconstructed as white paper after
  F5 or a provider refresh.
- **Fixed Thor staged-battle duplication.** Battle Stage v3 gives the physical
  dual-screen presenter a UI-only lower canvas: wording and HUD stay below,
  while Pokémon, trainers, and move-effect sprites appear only in the upper
  arena. Hot unplug, replug, disable, and reload restore normal composition.
- **Made visible Wild encounters authoritative and live.** Encounter Mode is
  now one persisted transaction that clears conflicting legacy standalone
  values, installs the correct classic-encounter hooks, and rebuilds the
  current map once. Choosing VISIBLE suppresses classic grass rolls and keeps
  hidden, sprite-less markers off.
- **Fixed logical-only grass Pokémon.** Wilds reasserts its AI pipeline after
  settings apply, completes delayed spawn effects, and reconciles revealed
  entities into the actual Gen 1 draw list. Selected Wilds 2.1.8 runtime fixes
  for live behavior and follower map seams are backported onto the bundled
  2.1.7 baseline; unrelated catching art/HUD changes are not claimed.
- **Fixed bundled Free Fly ownership.** FREE FLY NOW now controls the hosted
  namespaced badge option as its label promises, and flying mounts/followers
  can borrow the bundled Wilds provider's exact species art without a separate
  Wilds Loader entry. FLY COCKPIT now recognizes the bundled Free Fly 1.8.0
  HUD contract instead of silently standing aside.
- **Hardened follower map handoffs.** Gen 1 lifecycle reloads now fail closed
  instead of retaining stale follower objects. Gen 2 connection rows resolve
  through their id-only neighbor shape, translate live goals, and rebind the
  destination map id so a later world rebuild cannot drop the follower.
- **Made handheld sprite canvases pixel-accurate.** Wild and follower card
  canvases use `dpiscale=1` plus nearest sampling, preventing Android/AYN DPI
  scaling from enlarging, blurring, or corrupting nominal 16×16 art. Removed
  two legacy UTF-8 byte-order marks so the same renderer files also load under
  the supported plain Lua 5.1 runtime.
- **Recalibrated run bob.** The historical raw 0.25 effect is now labeled 1X,
  gentler values are available below it, and new installs default to 0.5X.
  Existing saved raw values retain their exact motion strength.
- **Reduced handheld render churn.** Wild behavior ticking now reuses its
  per-frame context and calls handlers without allocating closures for every
  visible Pokemon. Stable battle HUD rendering likewise caches its two quads
  until the source texture or band geometry changes.

## 0.12.0 - 2026-08-19

- **Fixed missing Pokemon art in consolidated installs, especially on AYN
  Android devices.** Bundled mods now resolve their asset helpers from their
  own `vendor/` roots instead of Scott's Tweaks' top-level folder. This
  restores visible Wilds of Kanto encounters, followers, runtime sprite
  sheets, and Unique Menu Icons in the party and Pokemon screens without
  needing separately installed copies to mask the bad path.
- **Added a partial-install warning.** The fused package contains tens of
  thousands of sprite files, so an interrupted handheld install can leave a
  mod that loads while entire art folders are absent. Scott's Tweaks now
  checks representative files and reports `PARTIAL INSTALL` in its menu and
  log when a clean reinstall is required.
- **Fixed B-button running in 2D and every grid-based voxel view.** The speed
  hook no longer rejects the normal walker after the engine marks a step as
  moving, and its temporary step timing is restored before scripted movement
  so cutscenes and NPC-driven steps keep vanilla timing. First- and
  third-person free movement continue to use the same selected run speed.
- **Consolidated the settings UI for the consolidated mod.** Start and the Mod
  Manager now reach one Scott's Tweaks menu with one BASIC/ALL preference,
  clear category names, shorter values, and no duplicate player-art rows.
  Movement, world, Pokemon art, battles, wild/follower behavior, and
  device/menu settings are grouped by what they affect. Wilds' own
  FOLLOW/DISMISS actions and migrations now write that same canonical option
  storage, so follower controls cannot disagree with MOD SETTINGS after a
  restart. Menu icon color changes save safely and say that a restart is
  required instead of trying to mutate the engine's frozen icon registry.
- **Wild encounters now have one plain-language encounter mode.** New installs
  default to visible overworld encounters: classic random battles and hidden
  encounter markers are off. `VISIBLE`, `BOTH`, `CLASSIC`, and `OFF` map to
  the existing Wilds options, while existing saved choices remain intact.

## 0.11.0 - 2026-08-19

- **Fixed: Scott's Tweaks would not load at all** for anyone who still had the
  standalone Scott's Battle Art Kanto installed. 0.9.0 declared a manifest
  conflict with `BATTLE_ART_VOXEL_FORK`, and `Loader:_enforceConflicts` fails
  the **declaring** mod -- so Scott's Tweaks disabled itself and none of the
  bundled mods, menus or fixes ran. The conflict is removed; coexistence was
  already handled at runtime, where the bundled renderer stands down and the
  vendor host skips any mod with a standalone copy. New
  `tests/coexist_standalone.lua` loads it beside a standalone renderer and
  asserts both.
- **Fixed: the bundled renderer started on top of a standalone one.** The
  handle given to the renderer answered for `BATTLE_ART_VOXEL_FORK` before
  consulting the real loader, hiding an installed copy from the stand-down
  check. The real loader is asked first now -- a separately installed mod
  always wins.
- **The SCOTT'S TWEAKS menu is reorganised.** This is the screen reached from
  START, and the 0.10.0 reorganisation only touched Battle Art's separate
  settings screen, so nothing appeared to change. It now opens on **MODS**,
  BAG & EXPERIENCE, TRAINERS & OAK, RUNNING and PACK + POKéGEAR, with
  FIELD MOVES and DISPLAY & THOR behind a **SETTINGS: SIMPLE / ALL** row.
- **New MODS page** links straight to Battle Art, Wilds of Kanto, Followers and
  Crystal Sprites, so every bundled mod's settings are reachable from one
  place instead of hunting through START.
- `RUN SPEED` and `BOB INTENSITY` show their new ranges here too. The menu
  keeps its own copies of those lists and they had not been updated, so 0.10.1's
  wider ranges were invisible on this screen.

## 0.10.1 - 2026-08-19

- **Fixed: no Pokemon sprites anywhere, including the party menu.** The renderer
  asks the engine for companion mods by id, and the engine cannot see a bundled
  one, so `SpriteMenu` concluded Crystal Animated Sprites was absent while
  Crystal was in fact running and had already taken sprite ownership -- leaving
  nothing drawn. The renderer is now given a mod handle whose `find` sees the
  bundled mods, the same one they already had. `PACK` reports `CRYSTAL 2.0`
  again. Followers depended on the same handshake.
- **Fixed: running only worked in first person.** Running Shoes 1.7.0 carries
  its own `RUN SPEED` option and its own trigger, so once it was bundled it
  owned the speed and the B button only reached Scott's Tweaks' first-person
  bridge -- bob but no speed anywhere else. Scott's Tweaks owns B-running again
  through the engine's `movement.speed` hook, which applies in 2D, third person
  and first person alike. Running Shoes is no longer installed from the bundle;
  its source stays under `vendor/running_shoes` and a **separately installed**
  copy still takes over.
- `RUN SPEED` gains **2.5X**, **3X** and **4X**.
- `BOB INTENSITY` gains **0.1X** and **0.15X** below the old 0.25X floor.

## 0.10.0 - 2026-08-19

- **Settings are reorganised and default to SIMPLE.** The main screen is now
  QUICK, OPEN WORLD, PLAYER, SPRITES and BATTLES. `VIEWS & CAMERA` and
  `ADVANCED` -- the renderer tuning pages -- are hidden until the new
  **SETTINGS: SIMPLE / ALL** row at the bottom is switched to ALL. Hiding a row
  never changes its value, so switching back finds everything as it was left.
- **New PLAYER screen** collects everything that answers "how do I appear":
  `PLAYER POKEMON` (front or back), `MY POKEMON FLIP`, `TRAINER ART`, the
  player art and animated sets, `CRYSTAL OPTIONS`, plus head bob, third-person
  and first-person FOV. These were previously spread across the sprite and
  camera pages. No setting is duplicated -- the menu's own coverage check
  asserts zero duplicates.
- `WORLD` is renamed **OPEN WORLD** and `SPRITES & TRAINERS` to **SPRITES**,
  now that the trainer and player rows have their own home.
- **Day/night can take a full hour.** `DAYTIME` gains **1 HOUR** beside the
  existing cycle, which is now labelled **20 MIN**. `SYNC`, `DAY`, `NIGHT`,
  `DUSK` and `DAWN` are unchanged. The dial itself is untouched: only the rate
  the clock advances differs, so the sky, shadows and light keep exactly the
  same shape, stretched over three times as long.

## 0.9.1 - 2026-08-19

- **Fixed: no head bob while running in first person.** Bundling Running Shoes
  in 0.9.0 caused it. `modules/running.lua` stood down entirely whenever it
  found `running_shoes` -- correct when that was a separate install, since the
  run multiplier must not be applied twice, but it took the camera bob down
  with it and Running Shoes ships no bob of its own. Speed and bob are now
  separate concerns: Running Shoes keeps the multiplier, Scott's Tweaks keeps
  the bob. `RUN HEAD BOB` and `BOB INTENSITY` work again.
- **Fixed: bundled mods were invisible to feature detection.** `findMod` now
  answers for the fused Battle Art renderer and every bundled mod, so anything
  that used to locate a companion by id keeps working. This is what left the
  bob reporting `no_supported_voxel_mod` even with the renderer running.
- `mod.exports.running` reports `speedDelegated` and `speedProvider` in place
  of the old all-or-nothing `delegated` / `provider`.

## 0.9.0 - 2026-08-19

**Eight community mods are now bundled.** Each runs from `vendor/<dir>/` with
its upstream source intact, so one Scott's Tweaks update carries the whole
stack and every setting lives in one place.

| Mod | Version |
| --- | --- |
| Wilds of Kanto | 2.1.7 |
| Free Fly | 1.8.0 |
| Trainers Let You Choose Lead Pokemon | 2.0.1 |
| All Pokemon Catchable 151 | 0.3.3-beta |
| Unique Menu Icons | 1.5.0 |
| Dynamic Scaling | 1.0.4 |
| Running Shoes | 1.7.0 |
| Crystal Animated Sprites with Shiny Visuals | 2.0.1 |

- **Fixed: wild Pokemon were invisible in grass.** Wilds' `Grass View` defaulted
  to `immersed`, which returns a downward tuck and depends on Dramatic Shape's
  native grass mesh redrawing over the sprite's feet. Under the bundled Battle
  Art voxel renderer the grass is real geometry, so a tucked sprite was occluded
  outright — while town and ambient Pokemon, standing on no grass mesh, stayed
  visible. The default is now `above`, which applies a lift instead. Both values
  remain selectable under Wilds' settings.
- New `modules/vendor_host.lua` runs the bundled mods. Each is handed a proxy
  mod handle whose `path` and `read` are rooted at its own vendor directory, so
  upstream code resolves its assets and libraries exactly as it did standalone.
  `find` is shimmed so the mods still discover one another by id after fusing.
- A separately installed copy of any bundled mod always wins: the player chose
  it, and two copies must never both run. Status is readable at
  `mod.exports.vendored`.
- `affects_link` is now **true**. All Pokemon Catchable 151 repatches encounter
  tables and Dynamic Scaling rewrites stats, so a link partner has to be told.

## 0.8.0 - 2026-08-19

- **Scott's Battle Art Kanto is now built in.** The renderer that previously
  had to be installed and updated as a separate mod ships inside Scott's
  Tweaks, so one launcher update carries both. Battle Art's own module loader
  reads `lib/` and `data/` relative to the mod root and runs unmodified; only
  its mod handle changed.
- The fused renderer **stands down automatically** when another voxel provider
  (Pokemon Final, Dramatic Shape, Dramaless, Potato, or a standalone Battle
  Art) is already active. Scott's Tweaks then behaves exactly as it did in
  0.7.0, compat layers included. Its state is readable at
  `mod.exports.fusedRenderer`.
- Gapped Land and the movement-speed bridge now recognise the built-in
  renderer through the same public `exports.lib` seam they used for external
  providers, so no feature had to be special-cased.
- Declares a conflict with a standalone `BATTLE_ART_VOXEL_FORK` install: two
  copies of the same renderer must never drive one map. Disable the separate
  Scott's Battle Art Kanto mod after updating.
- New `tests/fused_renderer_load.lua` loads the real vendored tree through the
  production API-2 loader and asserts the renderer actually initialises; the
  existing memfs fixtures deliberately omit it and exercise the stand-down
  path instead.

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
