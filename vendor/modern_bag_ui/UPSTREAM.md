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
- draw an original generic five-compartment backpack procedurally with LOVE
  rectangle primitives instead of distributing or loading upstream raster
  artwork;
- preserve Scott-compatible item-category fallbacks and lower-controller
  return values;
- use a 160x144 UI surface on an attached physical AYN Thor lower display;
- make screen registration and decoration safe to repeat.

The upstream PNG, manifest, tests, documentation, and automation are not part
of this vendored component.
