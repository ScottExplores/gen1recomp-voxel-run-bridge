# Changelog

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
