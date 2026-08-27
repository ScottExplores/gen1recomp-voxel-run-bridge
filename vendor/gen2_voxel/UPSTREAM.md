# Gen-2 voxel terrain provenance

The terrain/camera files in this directory were adapted from
[`randyadr/Gen2-3D-Sprites`](https://github.com/randyadr/Gen2-3D-Sprites)
at commit `a13895aa15ffab4683276cfadf7f9a3d523a5755` (upstream version 0.4.33,
retrieved 2026-08-26).

Only the Gold/Silver/Crystal voxel terrain, original 2D sprite-card renderer,
diorama/first-person/third-person cameras, terrain-height/ledge data, and their
procedural sky/water support are included. Scott's Tweaks intentionally blocks
all Stadium Pokemon/player models, Stadium battle and UI modules, ROM importers,
VR modules, and the optional Pokemon Yellow Kanto excursion.

`LICENSE-UPSTREAM.txt` preserves the upstream license and attribution notice.
The small `Battle*` and `Pokedex` files are explicit inert compatibility stubs
written for this terrain-only integration.
