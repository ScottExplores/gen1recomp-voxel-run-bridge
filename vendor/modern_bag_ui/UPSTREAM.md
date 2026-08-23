# Modern Bag UI provenance

This directory is adapted from **Modern Bag UI 0.4.1**:

- Repository: `https://github.com/piftee/gen1recomp-modern-bag-ui`
- Tag: `v0.4.1`
- Commit: `2b6082a62fda29a161458a541562dc816b155c57`
- Copyright: Copyright (c) 2026 ish hodaszi
- License: MIT; see [`LICENSE`](LICENSE)

Vendored source files are `main.lua`, `screen.lua`, and `inventory.lua`.
Every behavioral adaptation is marked `VENDORED CHANGE (Scott's Tweaks)` in
the source.

Scott's Tweaks adaptations:

- make the Pocket/backpack skin the default while retaining Modern;
- compile sibling source under PUC Lua 5.1 as well as LuaJIT;
- compose previously registered BagMenu and PlayerPC factories;
- retain native inventory, PC, and quantity limits;
- load Scott's original generated six-state five-compartment backpack and
  two-colour blue dither tile at native logical-pixel resolution, with the
  prior LOVE primitives retained only as a decode/missing-asset fallback;
  neither image uses upstream raster artwork;
- preserve Scott-compatible item-category fallbacks and lower-controller
  return values;
- use a Bag-only 200x144 UI surface on an attached physical AYN Thor lower
  display so full pocket headers and item names remain readable at exact 2x;
- make screen registration and decoration safe to repeat.

The upstream PNG, manifest, tests, documentation, and automation are not part
of this vendored component. Generation details for Scott's two original image
assets are recorded in [`ASSET_PROVENANCE.md`](ASSET_PROVENANCE.md).
