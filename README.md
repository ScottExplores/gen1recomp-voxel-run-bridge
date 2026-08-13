# Scott's Tweaks

Scott's Tweaks is the next version of **Voxel Run Bridge**. The display name
is broader, but its internal mod ID remains `voxel_run_bridge`. Existing
installations therefore update in place, keep their settings, and do not
become a duplicate mod.

Version 0.2.0 contains two independent tweaks:

- **Badge-free HMs:** use Cut, Fly, Surf, Strength, and Flash without their
  badge. A party Pokemon must still actually know the move. Normal map,
  terrain, and story restrictions remain in effect.
- **Voxel Run Bridge:** movement-speed mods work while a supported voxel mod
  is driving the player in **1ST** or **3RD** person.

Neither feature grants badges, teaches moves, changes story flags, or edits a
save's badge inventory.

## Dramatic Sky Ride / Free Fly

Flying mods perform their own badge check outside Gen1Recomp's normal HM
hook. Both **Dramatic Sky Ride** and **Free Fly** already provide a supported
setting for this:

1. Open the flying mod's options.
2. Set **BADGE CHECKS** to **OFF**.
3. Leave **STORY GATES** on unless you deliberately want to bypass those too.
4. If the mount does not know Fly and you want that requirement removed, set
   **REQUIRE FLY** to **OFF** as well.

In current Dramatic Sky Ride releases, first set **SETTINGS VIEW** to
**ADVANCED** to reveal those rows. Scott's Tweaks does not secretly rewrite
another mod's private settings; the one-time change above is the mod author's
intended path. Dramatic Sky Ride's settings persist after you change them.

## Voxel running

The original bridge makes Gen1Recomp movement-speed mods work while a
supported voxel mod is driving the player in **1ST** or **3RD** person. That
includes Running Shoes mods that use the engine's public `movement.speed`
hook.

It does not grant shoes, add a quest, or choose a speed. It carries the speed
already selected by another mod from the normal grid walker into the voxel
mod's continuous `FreeMove` walker. Step out of first/third person and the
ordinary engine path takes over unchanged.

**The bridge has no effect by itself.** Enable one movement-speed producer as
well, such as [MadeinTaly's Running Shoes](https://github.com/MadeinTaly/gen1recomp-running-shoes)
or [Run Mode](https://github.com/masterwebx/gen1recomp-run-mode). Those two
are the main reason this adapter exists: their normal run hook does not enter
voxel free movement on its own.

### Do you need the run bridge?

- **[thorkdev Running Shoes v0.2.2 or newer](https://github.com/thorkdev/gen1recomp-running-shoes/releases/tag/0.2.2)
  + Dramatic Shape/Battle Art Voxel Fork:** probably not. That Running Shoes
  release already contains a dedicated
  integration, and this bridge detects it and stays idle to prevent doubling
  the speed.
- **An older/different `movement.speed` mod:** yes, this is the generic bridge.
- **Dramaless Shape or PotatoVoxel:** this bridge supports their exported
  `FreeMove` module too, including Running Shoes versions that do not know
  those mod IDs.

MadeinTaly's and thorkdev's projects both use the manifest ID
`running_shoes`, so Gen1Recomp treats them as alternative implementations;
do not install both at once.

Supported voxel manifest IDs:

- `DRAMATIC_SHAPE`
- `BATTLE_ART_VOXEL_FORK`
- `DRAMALESS_SHAPE`
- `potato_voxel`

Only one of those is expected to be active; the voxel projects conflict with
one another in their own manifests. PotatoVoxel's default low-power profile
currently hides the 1ST/3RD rungs, so its bridge support matters only when its
full camera ladder is enabled.

## Install or update

If `voxel_run_bridge` 0.1.1 is already installed, open Gen1Recomp's puzzle
piece / **MODS** panel and install the offered 0.2.0 update. It will appear as
**Scott's Tweaks** afterward, without creating a second entry.

For a first installation:

1. Open **MODS -> Import mod .zip** and choose
   `voxel_run_bridge-0.2.0.zip`.
2. Enable **Scott's Tweaks**, then restart the game if the manager asks.
3. Its **BADGE-FREE HMS** option defaults to **ON**.
4. For voxel running, also enable one supported voxel provider and a
   movement-speed mod such as Running Shoes.

The manager will ask for the `engine_internals` permission. Scott's Tweaks
uses Gen1Recomp's official field-move and party-menu hooks, plus the existing
voxel companion export. It requests no network or filesystem permission.

Restart after enabling, disabling, or updating this bridge. Its small
inter-mod wrapper is installed into the voxel provider's exported table and
cannot be safely swapped by the developer F5 hot-reload path.

## How badge-free HMs work

Gen1Recomp exposes `fieldmove.eligibility` for field-move eligibility and
`ui.party.submenu` for party actions. Scott's Tweaks calls the rest of each
hook chain first, then supplies only a missing action for a party Pokemon that
already knows the corresponding HM. Fly remains outdoor-only, Flash remains
dark-map-only, and Cut/Surf keep their normal facing-tile checks.

The implementation never sets a badge flag, so gym progression, obedience,
story gates, and other mods continue to see the real journey state.

## How voxel running works

The regular grid walker measures movement as frames per 16-pixel step and
calls `movement.speed` before each step. Voxel first/third person replaces
that path with `FreeMove.tick`, measured in pixels per frame, so the hook is
otherwise bypassed.

For each free-movement tick, this mod:

1. asks the normal `movement.speed` chain for the effective frame count using
   the same context as the grid player;
2. converts that result into a ratio (`base frames / effective frames`);
3. applies the ratio to the active voxel `WALK` or `BIKE` speed for one tick;
4. restores the original constants immediately, including on errors.

Unlike the grid walker, free movement samples `movement.speed` continuously.
That keeps held-button and terrain effects correct as the player crosses
cells. It also means a custom speed hook used with this bridge should behave
as a transformation of the supplied frame count rather than counting how
many times the hook itself was called. The context includes
`freeMove = true` and `continuous = true` so a hook can distinguish this path.

The bridge does not consult movement hooks while the player is already moving
under a script or has input locked. It therefore stays out of cutscenes and
NPC-controlled movement. A bug inside the underlying Running Shoes mod's
normal grid behavior is outside this adapter's scope.

## Develop and verify

Use the `dev` branch of
[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) as the SDK:

```powershell
python tools/modkit.py validate C:\path\to\voxel_run_bridge --strict --base fixture
python tools/modkit.py lint C:\path\to\voxel_run_bridge
python tools/modkit.py pack C:\path\to\voxel_run_bridge -o C:\path\to\dist\voxel_run_bridge-0.2.0.zip --base fixture
```

The archive is intentionally flat: `manifest.json` and `main.lua` are at its
root, which Gen1Recomp's importer accepts directly.

Version 0.2.0 is configured for Gen1Recomp's built-in GitHub update checks via
`ScottExplores/gen1recomp-voxel-run-bridge`.

## Provenance

This implementation was written against Gen1Recomp's documented movement
contract and the voxel mods' exported `FreeMove` interface. It does not copy
the existing
`thorkdev/gen1recomp-running-shoes` implementation, whose repository currently
does not declare a software license. That project is credited for publicly
demonstrating and documenting the first-person movement gap.

No ROM, extracted graphics, save data, or other game content is included.
