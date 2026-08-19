# Crystal Animated Sprites with Shiny Visuals

A combined standalone mod for Gen1Recomp (Red / Blue / Yellow, and
Gold via Gen 2 support).

## Gen 2 (Gold) support

The manifest declares `"games": ["gen1", "gen2"]`.  On a Gold boot the
mod provides the Crystal artwork and the battle features:

- **Animated battle sprites.**  Gold's battle screen re-resolves its
  pics through the `pokemon.sprite` hook every frame, so the mod serves
  the PNG frame set there directly (time-indexed) instead of the static
  frame 1 -- the enemy always animates, and OPTIONS > FRONT SPRITES now
  works on Gold too (the player's back slot serves the animated front
  art, mirrored horizontally at runtime so the player's own mon faces
  the opponent -- each frame image is flipped once and cached, no
  duplicate asset files).  This is the Gen 2 counterpart of the Gen 1
  `BattleState` animation loop, which Gold does not run.
- **Shiny reveal and delayed enemy cry.**  A shiny enemy's send-out cry
  is deferred until its Gen 2-style sparkle reveal finishes, via the
  native `src.ui.gen2.BattleState` `playCry` / `update` wraps and the
  shared `battle.overlay` hook.  Shininess is read off Gold's own
  `mon.shiny` flag.
- **CUSTOM SPRITES opponent portraits.**  The opponents side of the
  option now takes effect on Gold: the mod's portraits replace the
  enemy trainer's intro pic (wrapping `BattleState.new`, which resolves
  `enemyTrainerImage` / `enemyTrainerPath`), and the player side was
  already live through the `player.sprite` hook.
- **Chosen player portrait on the trainer card, Hall of Fame, and back
  pic.**  Gold's trainer card and Hall of Fame draw their portrait
  straight out of the ROM's card tile sheet (no `player.sprite` hook),
  so the chosen portrait is drawn over them -- scaled to the card's 5x7
  box, native size in the Hall of Fame's 7x7 box, unflipped in both.
  The battle back pic honours the `*_flip.png` auto-mirror suffix
  exactly like Gen 1; the tutorial's DUDE back pic is never flipped.
- **Animated dex entry page and status screen.**  Gold's dex entry page
  and party status screen resolve their pic once per draw and redraw it
  every frame, so the mod's `picFor` wraps hand back the time-indexed
  animation frame (the status screen in the mon's shiny variant).  The
  dex listing keeps its static box.
- **Animated, colored evolution screen.**  Gold's evolution movie now
  shows the mod's Crystal front frames (in the evolving mon's shiny
  variant) instead of the vanilla static frontpics, drawn raw so the
  GBC palette pass cannot flatten them; the blackout flash keeps its
  silhouette and the balls of light stay vanilla.
- **COLOR modes reach the mod's art.**  In Gold's DMG / CLASSIC modes the
  battle sprites, the player's back pic, the trainer-card and Hall of
  Fame portraits, the overworld sheets, and the dex/status/evolution
  screens are luminance-baked onto the 4-shade DMG ramp (cached per
  image), so DMG shows the hardware grays and CLASSIC's present pass maps
  them to pea green with the sprite's real shading -- exactly how the
  vanilla 2bpp art is recolored.  GBC keeps the raw full-color art.
- The three options rows appear directly in Gold's OPTION screen and
  persist per profile.

Still Gen 1-only on a Gold boot: the title/intro screen
animations, the PaletteFX recolor pipeline, the Transform/move-effect
patches, the mono-mode staged-battle bakes, and the voxel-mod interop.
Gen 2 behavior should be verified with a real Gold boot before shipping.

## Included features

- Pokémon Crystal animated enemy front sprites
- Crystal normal and shiny player back sprites
- OPTIONS > FRONT SPRITES: show your own Pokémon's animated front sprite
  in battle instead of the static back art, mirrored horizontally so it
  faces the opponent (saved per profile)
- OPTIONS > CRYSTAL SPRITES: opens a submenu with five options:
  FRONT SPRITES (show your own mon's animated front sprite in battle),
  REPLACE SPRITES (replace player/opponent portraits with custom art
  from `assets/trainers/player/` and `assets/trainers/opponent(s)/`,
  overworld NPC sheets from `assets/overworld/trainers/`, or NONE for
  fully vanilla sprites), PLAYER SPRITE (pick which file
  in `assets/trainers/player/` is the player portrait, default
  `red.png`), BATTLE PIC (FRONT shows the chosen portrait in the
  battle back slot; BACK shows a dedicated back sprite from
  `assets/trainers/back/`), and ANIMATIONS (LOOP keeps every sprite
  animation cycling; PLAY ONCE runs each animation through its frames a
  single time and holds the last frame).  All five are saved per profile.
  A portrait named `*_flip.png` is mirrored automatically for the battle
  back pic (no toggle — the name is the switch).  The chosen sprite also
  skins the player's overworld character (see below).
- Automatic shiny artwork selection using the Pokémon's DVs
- Gen 2-style sparkle sprite animation
- Included shiny sparkle sound
- Enemy cry plays only after the sparkle sound finishes
- Trainer switch-in support
- Pixel-perfect, tile-aligned Crystal artwork

## Installation

Extract this ZIP into the `mods` folder and confirm:

```text
mods/crystal_animated_sprites_with_shiny_visuals/manifest.json
```

Fully restart Gen1Recomp.

## Custom trainer sprites

OPTIONS > CRYSTAL SPRITES > REPLACE SPRITES cycles through six modes
in the order NONE, PLAYER, TRAINER, PLAYER + TRAINER, OVERWORLD, ALL
(default PLAYER + TRAINER):

- NONE — nothing is replaced; portraits and overworld sprites stay vanilla
- PLAYER — custom player portrait only
- TRAINER — custom opponent portraits only
- PLAYER + TRAINER — custom player portrait AND opponent portraits
- OVERWORLD — overworld sheets only (player walk/bike + NPC sheets;
  no battle portraits)
- ALL — custom portraits AND overworld sheets (player + NPCs)

A side with no custom file falls back to the engine's own sprite — the
mod never substitutes a path that is not on disk, so nothing breaks when
a custom folder is missing or a portrait was skipped. Custom art lives
in these folders:

- `assets/trainers/player/red.png` — the player's portrait (trainer card,
  Hall of Fame, and battle back pic; a `redb.png` in the same folder wins
  for the battle back slot when present)
- `assets/trainers/back/{name}.png` — an optional dedicated back sprite
  for the battle back slot, keyed by the portrait stem (`gold_flip.png`
  -> `gold.png`).  Shown only when BATTLE PIC is BACK; missing files fall
  back to the front portrait.
- `assets/trainers/opponents/{name}.png` — an opponent's portrait, named
  after the trainer class the game uses (`agatha.png`, `brock.png`,
  `giovanni.png`, `jessie_james.png`, `rival1.png`, ...).  The folder may
  be spelled `opponents` or `opponent`, and the class id (`OPP_AGATHA`)
  is accepted as a file name too.
- `assets/overworld/trainers/{name}.png` — an overworld NPC's walking
  sheet, keyed by the trainer class first (`OPP_BROCK` -> `brock.png` --
  Gen 1 gym leaders reuse generic sprite records, so the class is the
  only name that matches), then by the sprite record (`SPRITE_BROCK.png`,
  `sprite_brock.png`, or `brock.png`).  Sheets follow the vanilla
  16x96 six-frame layout and are full color with transparency.
  NPCs whose sprite another mod rebuilt (followers, overworld wild
  spawns) are never replaced.

PLAYER SPRITE picks which file in `assets/trainers/player/` is the
player's portrait (default `red.png`).  The row cycles through the
shipped .png set in order (the launcher no longer lets mods list a
directory at runtime), showing each name in caps
(`RED`, `SILVER`, ...) with the `_flip` suffix hidden (`red_flip.png`
shows as `RED`); the chosen portrait is used for the trainer card,
Hall of Fame, and battle back pic, and a non-`red` pick fills the back
slot with itself (`redb.png` still wins for the default `red.png`).
`DEFAULT` (the first entry) keeps the game's own portrait instead of
the mod's art.

BATTLE PIC picks which view of the chosen sprite fills the battle back
slot: FRONT uses the portrait from `assets/trainers/player/` (mirrored
per the `*_flip` suffix), BACK uses a dedicated back sprite from
`assets/trainers/back/{name}.png` (the portrait's stem, without `.png`
or `_flip`).  It only affects battle — the trainer card and Hall of Fame
keep the front portrait — and a missing back file falls back to the
front portrait.

A player portrait named `*_flip.png` (for example `red_flip.png`) is
mirrored horizontally for the battle back pic automatically — there is
no toggle.  It only takes effect while REPLACE SPRITES is BOTH or
PLAYER ONLY (while the player's portrait is actually being replaced),
and it never touches the opponent portraits.  The mirror follows the
name: rename the file to drop `_flip` and it stops mirroring.

The chosen portrait also skins the player's overworld character when
REPLACE SPRITES is OVERWORLD or ALL (the other modes keep the vanilla
character): when a sheet named after it exists at
`assets/overworld/player/` (for example `assets/overworld/player/red.png`),
the player's on-foot sprite uses it, and a matching `{name}_bike.png`
(`assets/overworld/player/red_bike.png`) skins the bicycle sheet.
A `*_flip.png` portrait uses its base name
(`red_flip.png` reads `red.png`), so the mirrored and unmirrored picks
share one sheet.  The sheets follow the vanilla layout — a 16x96 PNG with
six 16x16 frames (stand down/up/left, then walk down/up/left) — and are
full color with transparency, like the mod's battle art.  Surfing keeps
its own sheet, and fishing works out of the box too: the fishing pose is
GENERATED from the walk sheet at runtime (the character's own bottom
row with the near half of the rod pasted in from the engine's rod art),
so the vanilla rod pose stays intact without per-character fishing
sprites.  Outside ADVANCED, OG RED / OG BLUE, and Gen 2 the overworld
sheets (player, bike, and NPC) are luminance-baked onto the engine's DMG
shades so they follow the COLORS mode exactly like the mod's battle art
instead of staying raw full color (OG YELLOW bakes too).  A pick with no matching sheet leaves the vanilla
overworld sprite untouched, and cycling the option in the OPTION screen
swaps the character on screen immediately (works on both Red/Blue/Yellow
and Gold).

Changes apply on the next battle.

## Notes

This mod does not make Pokémon shiny. It displays shiny Crystal artwork and
the shiny reveal only when the Pokémon already has Gen 2 shiny-compatible DVs.

Use it alongside an encounter mod such as All Shiny Encounters when desired.
