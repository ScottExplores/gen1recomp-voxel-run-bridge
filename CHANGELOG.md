# Changelog

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
