# Incorporated MIT components

Scott's Tweaks 0.7.0 incorporates and adapts the following independently
released MIT components. Their original mod identities remain supported as
delegated providers; these notices do not imply that a legacy mod must be
installed beside Scott's Tweaks.

- **Trainer Forfeit & Rematches 0.3.0** (`trainer_forfeit`): trainer paid
  forfeits, ordinary/Gym Leader rematches, and authored offline journey
  dialogue. Copyright (c) 2026 Trainer Forfeit contributors.
- **Oak's Spare Starter 0.1.1** (`oak_spare_starter`): Oak's Lab spare-ball
  interaction. Copyright (c) 2026 Scott.
- **Scott Mod running module** (`scott_mod`): the renderer-neutral
  `movement.speed` B-button running producer used as the clean starting point
  for Scott's Tweaks' running feature. Copyright (c) 2026 Scott Mod
  contributors. Scott's Tweaks' distance-based camera-bob implementation is
  new work and does not copy the unlicensed `running_shoes` implementation.
- **Scott's Sprite Menu OptionScreen** (`scotts_sprite_hub`): the small
  semantic OptionRows screen reused by the categorized Tweaks menu.
  Copyright (c) 2026 Scott and contributors.
The following MIT terms apply to each work and copyright notice listed above:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to
> deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
> sell copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
> FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
> IN THE SOFTWARE.

Scott's Tweaks itself remains licensed under the repository's root
[`LICENSE`](LICENSE).

---

## Built-in Scott's Battle Art Kanto renderer

From 0.8.0 the Battle Art Kanto renderer is bundled inside this mod.
Its upstream notices follow verbatim.

# Third-party notices

The categorized `OptionRows` navigation and sprite-provider coordination in
`lib/OptionScreen.lua`, `lib/SpriteMenu.lua`, and `lib/SettingsMenu.lua` adapt
Scott's Sprite Menu 0.2.2. Those adapter sources are licensed as follows:

MIT License

Copyright (c) 2026 Scott and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

No Pokemon, trainer, menu-icon, font, or other art from a provider is copied
by this adaptation. Crystal Animated Sprites, FireRed sprites, Battle Art
assets, and every separately installed provider retain their own provenance
and terms.

---

## Bundled community mods (0.9.0)

Each mod below is included under `vendor/<dir>/` with its upstream source
unmodified except where a `VENDORED CHANGE` comment marks an edit. Copyright
remains with its author; inclusion here is not a relicensing.

| Mod | Version | Upstream | Licence |
| --- | --- | --- | --- |
| Wilds of Kanto | 2.1.7 | YoDrehDenSwagAuf/overworld-spawn-mod | MIT (code and original assets only) |
| Running Shoes | 1.7.0 | MadeinTaly/gen1recomp-running-shoes | MIT |
| All Pokemon Catchable 151 | 0.3.3-beta | Wowabox (Darklinkduck) | MIT |
| Free Fly | 1.8.0 | shanehudson-gen1recomp-mods/free_fly | no licence file |
| Modern Bag UI | 0.4.1 | piftee/gen1recomp-modern-bag-ui | MIT |
| Trainers Let You Choose Lead Pokemon | 2.0.1 | ZyranCZ/Trainers-Let-You-Choose-Lead-Pokemon | no licence file |
| Unique Menu Icons | 1.5.0 | menyas/unique-menu-icons | no licence file |
| Crystal Animated Sprites with Shiny Visuals | 2.0.1 | distilledorion-sketch/crystal_animated_sprites_with_shiny_visuals | no licence file |
| Dynamic Scaling | 1.0.4 | (no public repository found) | no licence file |

### Modern Bag UI 0.4.1

Scott's Tweaks adapts the responsive Bag and PC presentation code from
[Modern Bag UI](https://github.com/piftee/gen1recomp-modern-bag-ui), release
0.4.1, commit `2b6082a62fda29a161458a541562dc816b155c57`. The upstream raster
backpack is deliberately not included; Scott's Tweaks draws its own generic
five-compartment backpack from original geometric primitives. The complete
upstream license also ships beside the adapted source at
`vendor/modern_bag_ui/LICENSE`:

MIT License

Copyright (c) 2026 ish hodaszi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

**Wilds of Kanto asset carve-out.** Its MIT licence covers the original source
and original project assets only. The follow-sprite and overworld art under
`vendor/wilds/assets/enhanced_overworld/`, including the built-in Poke Followers
/ GSC sheets and the generated runtime sheets derived from them, remains under
the licences of its original authors — the Followers EX / PokePC /
ShockSlayer (Pokemon Crystal Clear) lineage — and is not relicensed here. See
`vendor/wilds/THIRD_PARTY_NOTICES.md`.

**Mods with no licence file** are included at the request of this repository's
owner, who states he has the authors' permission. Absent a licence file the
default position is all rights reserved, so anyone forking this repository
should obtain their own permission rather than relying on its presence here.

### Vendored changes

- `vendor/crystal/main.lua` — three `require("mods.<id>.<file>")` calls replaced
  with a `loadSibling` helper. The mod sandbox removes `setfenv` and resolves
  `package.path` against the engine's real mods directory, neither of which
  exists for a bundled copy. Behaviour is identical.
- `vendor/wilds/lib/config.lua`, `vendor/wilds/options.lua` — the default for
  `pokemon_grass_render_mode` changed from `immersed` to `above`. Immersed
  returns a downward tuck that relies on Dramatic Shape's native grass mesh;
  under the bundled Battle Art voxel renderer the grass is real geometry and a
  tucked sprite is hidden outright. Both values remain selectable in the menu.
