# Changelog

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
