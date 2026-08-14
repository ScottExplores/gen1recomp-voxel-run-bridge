# Gen1Recomp modding field guide

Research snapshot: 2026-08-13

This is the working map used to build Voxel Run Bridge. It records the parts
of Gen1Recomp's mod system and current voxel ecosystem that matter for future
mods, without copying or redistributing any third-party game code.

## What a Gen1Recomp mod is

A mod is a folder or ZIP with `manifest.json` and its entry Lua file at the
archive root. Gen1Recomp also accepts one enclosing top-level folder, but a
flat release ZIP is the community convention.

The manifest supplies the stable mod ID, display name, semantic version, mod
API, engine version range, load priority, dependencies/conflicts, supported
games, permissions, and entry file. API 2 is current. A player installs a
release through **MODS -> Import mod .zip**, enables it, and restarts when the
manager requests it.

The main extension surfaces are:

- hooks, which wrap an engine operation and must call the next function once;
- events, which observe something that happened;
- registries, which add or patch declarative game content;
- options and per-mod storage;
- inter-mod exports, reached with `mod.find(id).exports`;
- declared internal access for the few integrations that need an engine
  module not exposed by the ordinary API.

Hooks compose by priority. A speed mod should transform the frame count
returned by the rest of the `movement.speed` chain instead of blindly
replacing it, so terrain, bikes, surf, and other movement mods still compose.

## The normal movement path

The public `movement.speed` hook is evaluated when `Player:tryMove` begins a
grid step. Its input is normally 16 frames on foot or 8 on a bicycle. The
context contains `onBike`, `surfing`, `player`, `input`, and `save`; the final
engine duration is floored and clamped to at least one frame.

The hook first shipped in engine v0.1.29. The current voxel providers require
v0.1.37 or newer, so v0.1.37 is the bridge's practical release floor.
Relevant primary references:

- [hook reference](https://github.com/bryanthaboi/gen1recomp/wiki/Reference-Hooks#world)
- [current Player call site](https://github.com/bryanthaboi/gen1recomp/blob/ae6cac89e12ea7a844bcf7e11be9d079abbd9365/src/world/Player.lua#L148-L163)
- [Gen1Recomp repository](https://github.com/bryanthaboi/gen1recomp)

## Why voxel first person is different

Dramatic-style voxel mods provide the camera themselves. In their **1ST** and
**3RD** rungs they replace the grid input path with continuous
`FreeMove.tick` movement. That module measures speed in pixels per fixed tick
(`WALK = 1`, `BIKE = 2`), so `Player:tryMove` and therefore
`movement.speed` are bypassed.

The current implementations export a small module namespace as
`mod.exports.lib`. `lib.require("FreeMove")` returns the shared module table.
The safe integration seam is to temporarily scale its active speed for one
tick and restore it immediately. Never vendor a voxel project's source.

Verified providers using this seam:

| Manifest ID | Project | Notes |
| --- | --- | --- |
| `POKEMON_FINAL` | Pokemon Final private build | Uses the same exported `lib.require("FreeMove")` seam under its own manifest ID. |
| `DRAMATIC_SHAPE` | [current 1.8.2 mirror](https://github.com/scottcandy34/DramaticShapeVoxelMod-latest) | Original upstream URL is currently deleted/404. |
| `BATTLE_ART_VOXEL_FORK` | [Battle Art fork](https://github.com/absol89/DramaticShapeVoxelMod) | Current active fork line. |
| `DRAMALESS_SHAPE` | [Dramaless Shape](https://github.com/artyrambles/DRAMALESS_SHAPE) | Used by current Kanto in First Person. |
| `potato_voxel` | [PotatoVoxel](https://github.com/ShaneMcGovernIE/potato_voxel) | Free camera is normally removed by its default low-power profile. |

### Gapped-land rendering is presentation, not map expansion

Gen1Recomp's built-in **VOID FILL** and Kanto in First Person's **WORLD
APRON** are useful precedents, but they are separate from Scott's Tweaks
0.3.0. The engine fill chooses a border block around an overworld map, while
the Kanto apron extends a provider-owned mesh. Neither turns the space into
walkable map cells.

Scott's Tweaks generates its own small land plane and installs it only after
feature-detecting a compatible voxel provider's exported `VoxelScene`,
`Voxel3D`, `VoxelState`, `DayNight`, and `Mat4` modules. The verified contracts
are Pokemon Final and Dramatic Shape 1.8.0-1.8.2. Manifest or internal version
strings are not enough by themselves: the required module tables and
functions must be present before any shared table is wrapped.

The plane is active only in outdoor/open-air **1ST** and **3RD** views. It
stays out of interiors, canopy scenes, and sea maps, and it never changes map
definitions, collision, connections, warps, encounters, or player position.
It is runtime geometry rather than cached terrain, so toggling the option
does not start, delete, or rebuild Pokemon Final's voxel disk cache.

The public Kanto in First Person and Dramatic Shape mirror repositories do
not currently declare software licenses. Their world-apron implementation is
therefore a compatibility precedent, not source for this MIT package. The
0.3.0 plane is independently implemented and carries no third-party code,
textures, panoramas, ROM content, or other assets.

### Narrow Pokemon Final cache-screen compatibility

Pokemon Final also deliberately exports its cached module loader as
`mod.exports.lib`. Scott's Tweaks 0.3.0 retains a narrow use of that seam for
a UI-result compatibility check on the locally verified `1.8.1-scott.2` and
`.3` package contracts. It calls `ScottPrecacheScreen._start` on an inert fake
instance whose cache service cannot touch storage. A wrapper is installed
only when a successful fake start exhibits the known false fallback message.

The wrapper delegates exactly once and preserves all return values and
errors. It clears only `could not start`, only when the screen's own precache
service reports `state == "building"`. An ownership marker prevents nested or
foreign wrappers, and restoration checks both marker identity and the current
function before changing the table. The corrected `.3` implementation passes
the behavior probe and receives no wrapper. No Pokemon Final source, assets,
or cache data belong in this public repository.

These providers have the same constants, tick entry, active-speed selection,
and cell-crossing behavior. Feature-detect the export rather than trusting a
version number because the forks' displayed, manifest, and internal versions
can drift.

## Existing running mods

- [thorkdev Running Shoes v0.3.0](https://github.com/thorkdev/gen1recomp-running-shoes/releases/tag/0.3.0)
  already supports first/third person for `DRAMATIC_SHAPE` and
  `BATTLE_ART_VOXEL_FORK`. Its repository currently has no software license,
  so it is a compatibility precedent, not source to copy.
- [MadeinTaly Running Shoes](https://github.com/MadeinTaly/gen1recomp-running-shoes)
  is MIT licensed. Version 1.7.0 added a native FreeMove wrapper for
  `DRAMATIC_SHAPE`; Scott's Tweaks detects its ownership markers to avoid a
  double boost and still supplies the bridge for `POKEMON_FINAL`.
- [Run Mode](https://github.com/masterwebx/gen1recomp-run-mode) is another
  MIT-licensed public-hook implementation with the same free-roam gap.

MadeinTaly and thorkdev both use the manifest ID `running_shoes`; the loader
treats them as alternate versions of one mod, so they cannot coexist.

Voxel Run Bridge is deliberately only an adapter. It leaves thorkdev's native
wrapper alone and carries other `movement.speed` producers into compatible
FreeMove providers. It does not grant shoes or choose a run multiplier.

## Community observations

The BOI'S CLUB GAMES Discord `pkmn-mods` forum is the practical discovery and
support layer. Authors typically publish a forum post containing a GitHub
repository or release ZIP, screenshots, compatibility notes, and tags such as
Gen 1/Gen 2 and content/balance/other. GitHub remains the durable source and
release host.

The server's current AI policy allows AI-assisted coding, while expecting the
contributor to understand, test, and support what they publish. That makes a
small, documented adapter with tests a much better community contribution
than a large opaque fork.

A current support warning says some running-shoes behavior can softlock when
a run input is held while Oak or another NPC takes control. This bridge never
evaluates the speed hook while `player.moving` or `player.inputLocked`, which
keeps its FreeMove adapter out of those scripted paths. It cannot repair a bug
inside a separate running mod's ordinary grid behavior.

## Build, validate, and publish

Use the `dev` branch of Gen1Recomp as the SDK and run its official modkit:

```powershell
python tools/modkit.py validate C:\path\to\mod --strict --base fixture
python tools/modkit.py lint C:\path\to\mod
python tools/modkit.py pack C:\path\to\mod -o C:\path\to\mod-0.1.1.zip --base fixture
```

`validate` loads the mod against ROM-free fixture data through LuaJIT. `lint`
rejects ROMs, patches, and derived game assets. `pack` reruns strict checks
and creates the player-facing archive.

Before publishing:

1. create a public GitHub repository and add its `owner/repository` value to
   the manifest with `modkit set-github`;
2. generate the official tagged-release workflow with
   `modkit add-release-workflow`;
3. test the actual ZIP through the in-game importer;
4. make a GitHub release and submit it through the
   [community mod index](https://github.com/bryanthaboi/gen1recomp-mod-index).

Useful guides:

- [Getting Started](https://github.com/bryanthaboi/gen1recomp/wiki/Getting-Started)
- [Manifest reference](https://github.com/bryanthaboi/gen1recomp/wiki/Reference-Manifest)
- [Modkit guide](https://github.com/bryanthaboi/gen1recomp/wiki/Guide-Modkit)
- [Publishing guide](https://github.com/bryanthaboi/gen1recomp/wiki/Guide-Publishing)

## Release hygiene

- Keep ROMs, extracted graphics/audio, save files, and ROM patches out.
- Do not copy code or assets from a repository with no compatible license.
- Declare every permission and explain why it is needed.
- Give the mod a unique ID and specify conflicts/optional dependencies.
- Validate and lint the exact directory, then inspect the exact ZIP.
- Test enable, disable, update, controller input, bike/surf states, scripted
  movement, first/third person, and interaction with other speed mods.
- Direct wrappers on another mod's exported table are not hot-reload safe;
  require a restart after enable, disable, or update.
