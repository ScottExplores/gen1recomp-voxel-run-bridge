# Changelog

## 2.0.0

- Fixed a load crash ("main function has more than 200 local variables")
  that stopped the mod from starting: main.lua had grown past the engine's
  200-local limit, so a batch of sprite/color helpers were moved out of
  the module's local scope (into the mod's own sandbox globals, which
  each mod is isolated with) to bring it back under the limit with room
  to spare.
- New OPTIONS > ANIMATIONS row: LOOP keeps the Crystal sprites cycling
  (the default, and the previous behavior); PLAY ONCE runs each animation
  through its frames a single time and holds the final frame.  It applies
  everywhere the sprites animate -- battle front/back pics, the dex,
  status, evolution, PC and party screens, the Oak speech demo, the boot
  intro and the Hall of Fame.
- Gold's PC storage list (Bill's PC) now shows the mod's animated Crystal
  sprites with their real colors.  The box list resolved the selected mon's
  front pic through the patched spriteFront and colored it with the GBC
  palette pass -- which buckets full-color art by red channel and flattens
  it -- so the pic sat static and off-color.  It now serves the same
  time-indexed Crystal frames the dex/status pages use and draws them raw,
  with the DMG / CLASSIC bake applied like every other Gen 2 surface.
- Loading a save on Gold now clears the baked-image caches before
  re-applying the overworld skins, so a freshly loaded save can't briefly
  show a grayscale bake a previous session's COLOR mode left behind.
- The fallback trainer back sprite is no longer mirrored when CUSTOM
  SPRITES / REPLACE SPRITES is enabled but the custom art file is missing.
  The `*_flip.png` auto-mirror only fires while the mod's own portrait is
  actually in the battle back slot (Gen 1 already tracked this with the
  `__crystalCustomBack` provenance flag; Gen 2's flip now gates on the
  resolved art path too), so a vanilla back pic that falls back in is
  left exactly as the engine draws it.
- The party pokeball row no longer renders as solid white or as a
  green/yellow/white blob.  In a colorized battle the engine's zone pass
  remaps every HUD pixel by red channel onto the HP-bar palette, so the
  grayscale balls came out recolored; the row is now baked to the classic
  red/white ball (full and status tiles) and drawn in the battle.overlay
  pass, on top of the finished frame, where the zone pass cannot reach it.
  Fainted and empty slots keep their native grayscale, mono COLOR modes
  keep the DMG ramp, and the voxel mod's snapped path keeps the direct
  in-HUD draw.
- A thrown pokeball that catches a Pokemon now takes on that Pokemon's
  colors once it settles on screen for the "caught" text (top = the mon's
  dark shade, bottom = its light shade, outline = its darkest shade),
  instead of the black/white OBJ look.  The recolor rides the existing
  animSpriteColors hook and the AnimPlayer shade shader, so the voxel
  battle's projected placement is preserved; mono COLOR modes keep the
  grayscale ball.
- Gold's Oak speech Marill (the demo_mon beat) is now the mod's animated
  Crystal Marill instead of the static generated frontpic.  The frames are
  handed to the speech in `OakSpeech.new` and advanced from `drawPic`
  (draw runs every frame the speech is visible, while update is gated
  behind the reveal/shrink timelines), and a crystal frame skips the
  GbcPalette pass -- which buckets full-color art by red channel and
  flattens it -- so the Marill keeps its own colors.  The DMG / CLASSIC
  bake is applied at draw time (GbcPalette.mode is not yet the player's
  COLOR choice when the speech is constructed), so the Marill desaturates
  in DMG instead of staying full color.
- A brand-new Gold game now defaults to the Gold trainer portrait
  (`gold_flip.png`) instead of `red.png`.  The New Game reset in
  `save.created` and the no-saved-preference fallback now pick the
  generation's own hero (Red on Gen 1, Gold on Gen 2), so starting Gold
  no longer reverts to Red after the Oak speech.
- Gold's DMG / CLASSIC COLOR modes now desaturate the mod's art instead of
  leaving it full color.  The mod's Gen 2 art is always the full-color set
  and is drawn raw (the GBC palette pass buckets a full-color pic by its
  red channel), so DMG -- which has no whole-frame present pass -- showed
  the battle sprites, the player's back pic, the trainer-card / Hall of
  Fame portraits and the overworld sheets in full color; CLASSIC only
  looked green because its present pass flattened them by red channel.
  Every one of those surfaces now luminance-bakes its art onto the 4-shade
  DMG ramp in a non-GBC mode (cached per image), so DMG shows the hardware
  grays and CLASSIC's present pass maps the ramp to pea green with the
  sprite's real shading -- the same path the vanilla 2bpp art rides.  The
  dex/status/evolution screens use the same bake, and GBC keeps the raw
  full-color art.
- The Pokémon Tower ghost now uses the mod's art with the same
  luminance-baked shading as every other battler.  The ghost ships only as
  full-color art (`assets/front/normal/ghost.png`), but the sprite hook and
  the battle animation reset asked for a `grayscale/ghost.png` that never
  exists, so the ghost fell through to the engine's vanilla sprite
  (red-channel-bucketed) instead of being baked onto the mode's palette.
- The player trainer's back pic is now luminance-baked in forced-mono 3D
  battles too.  The staged-battle mono bake (`bakeStagedPic`) deliberately
  skips the mod's own art, but the back pic is loaded raw full-color and
  had no earlier bake, so it stayed full-color there while the colorized
  and 2D mono paths already baked it.
- Fixed a LuaJIT load error ("function at line ... has more than 60
  upvalues").  `gen1Require` now returns a single value (nil on failure)
  instead of an `(ok, module)` pair, so the install closure no longer
  captures a redundant flag per loaded module and stays under LuaJIT's
  60-upvalue ceiling.
- Trainer back sprites (`assets/trainers/back/**`) now draw at their native
  56px instead of the vanilla 64px, so they render at a clean 1:1 scale.
- Reverted the OPTIONS > GOLD ANIMATIONS bridge (attack animations played
  through Gold's battle-animation runtime).  The Gen 1 subanimation player
  is back as the only move-animation path, and the 565 KB Gold script data
  plus the 41 GFX sheets it needed are gone, so a battle no longer loads or
  steps them.
- Move animations are now colored by move type instead: the vanilla Gen 1
  animation sprites (which the battle used to draw white-on-black) are
  recolored with a light/mid/dark ramp keyed on the move's type -- Fire
  moves burn orange, Water moves run blue, Electric moves flash yellow,
  and so on -- matching the colored look the Gen 2 scripts gave the same
  moves.  Ball tosses, send-outs and status shakes keep their native
  coloring, and the forced-mono COLORS modes stay mono.  The ramp is
  resolved once per animation and drawn allocation-free, so the per-frame
  cost is a table lookup.
- The same type-colored move animations now run on Gen 2 (Gold).  The
  native battle-animation runtime draws each move sprite through
  `BattleAnimView:objPalette` with one of the fixed `battleObjects`
  palettes; the mod wraps that seam to TINT each palette toward the
  current move's type (paper stays, and each shade blends with the type
  ramp's light/mid/dark), so a move reads the same fire-orange /
  water-blue on Gold as on Red while keeping its native multi-palette
  shading.  The battlers' own `PAL_BATTLE_OB_*` colors and every non-move
  animation (ball toss, send-out, status) stay vanilla, the tinted
  palettes are cached per type + palette name, and Gold's DMG / CLASSIC
  modes flatten them downstream exactly like vanilla.
- Gold's evolution screen now shows the mod's colored, animated Crystal
  sprites instead of the static vanilla frontpics.  `EvolutionAnim:pic`
  hands the screen the time-indexed frame (in the evolving mon's own shiny
  variant), and `drawPic` draws a crystal frame raw -- the GBC palette pass
  buckets a full-color pic by its red channel and flattens it, the same
  reason the dex/status pages skip it.  The blackout flash keeps its
  silhouette as a dark tint, and the balls of light keep the vanilla mon
  palette; species without mod art fall back to the vanilla pic.
- Enemy-side move animations (the player's move playing over the foe) no
  longer cover the player's name/HP box.  Gen 1 authored those sprites for
  the vanilla layout, where the field below the foe was empty ground; the
  engine's classic HUD draws the player's stats there, so flames, beams
  and stars landed on the name text.  The anim layer for a move is lifted
  just enough that its lowest sprite clears that box (up to 32px; the side
  is detected once per animation from the compiled sprites).  Tall effects
  (SURF, THUNDERBOLT) that already reach the top of the screen are lifted
  less, so their top edge never crosses y = 0, while ball tosses, send-outs,
  status anims and the foe's own moves keep their vanilla placement.
- OPTIONS > PLAYER SPRITE no longer lists removed portraits.  The row now
  cycles only the portraits that still ship in `assets/trainers/player/`
  (blue, gold, james, jessie, kris, leaf, red, silver) plus DEFAULT.
- Trainer sprites (the opponent's battle portrait and the player's back
  pic) now skip the staged-battle paper seal the same way the mon sprites
  do, so their transparency is kept in 3D voxel battles instead of being
  filled onto the paper.
- Custom trainer portraits and the dedicated back sprites now use the
  luminance-baked shading in every non-ADVANCED COLORS mode, instead of
  raw full color or the engine's red-channel quantize (which collapsed a
  vivid portrait into the paper shade).  The player's portrait / back
  sprite is served trueColor so the engine never quantizes it, then the
  battle back pic is luminance-baked onto the mode's MEWMON colors per
  (image, mode) and cached; the opponent portraits get the same bake at
  load.  ADVANCED keeps the raw full-color art, Gen 2 is unchanged (its
  native pipeline shows full color), and the trainer card / Hall of Fame
  now ride the unshaded re-blit instead of being flattened.

- Custom player portraits (and the new dedicated back sprites) no longer
  render huge in battle.  The battle back slot draws at 2x by default, so
  the mod's 56px art reached 112px instead of the vanilla 64px.  The mod
  now wraps `BattleState.resolveBattleScale` (and Gold's `imageScale`) to
  size every `assets/trainers/**` back-slot pic to the vanilla width from
  its PNG header.  This also covers `*_flip` portraits, whose auto-mirror
  rebuilds the image without an engine path record and previously hid the
  path from the scale lookup.
- New OPTIONS > BATTLE PIC row: FRONT keeps the battle back slot on the
  chosen front portrait (as before); BACK uses a dedicated back sprite
  from `assets/trainers/back/{name}.png`, keyed by the portrait stem
  (`gold_flip.png` -> `gold.png`).  A missing back file falls back to
  the front portrait.  Back sprites get the same 64px battle sizing.

- Gold's trainer card portrait is scaled to ~6 tiles (48px), left-aligned
  to the box and lifted a few px so it clears the MONEY column (a little
  of the right frame is overlapped instead): larger than the fit-to-box
  40px that read too small, but smaller than the native 56px that spilled
  too far past the box sides.
- The player's own overworld walk/bike sheet now follows REPLACE SPRITES:
  only OVERWORLD / ALL skin the on-foot and bicycle sprites (the other
  modes keep the vanilla character), matching the NPC sheets.  Changing
  REPLACE SPRITES re-skins the live player immediately.
- PLAYER SPRITE gains a DEFAULT option, which keeps the game's own player
  portrait and overworld sprite instead of the mod's art.

- Gen 2 trainer card, Hall of Fame front portrait, and battle back pic now
  honour the chosen portrait.  Gold's trainer card and Hall of Fame draw
  their portrait straight out of the ROM's `ChrisPicAndTrainerCardGFX`
  tile sheet (no `player.sprite` hook), so the chosen portrait is now
  drawn over them -- scaled to the card's 5x7 box, native size in the Hall
  of Fame's 7x7 box, unflipped in both.  The battle back pic applies the
  `*_flip.png` auto-mirror suffix exactly like Gen 1 (the tutorial's DUDE
  back pic is never flipped).

- OG YELLOW now luminance-bakes the overworld sheets like SGB instead of
  staying raw full color.  The earlier 1.8.14 exclusion of the `ogred` mode
  was too broad: Red/Blue's OG RED / OG BLUE bake a boot-ROM object palette
  plus a post-zone redraw (so they stay full color), but Yellow keeps the
  map-zone path, so its OG YELLOW mode bakes exactly like SGB.

- Fixed SGB (and any other baked COLORS mode) showing the overworld sheets
  full color when the sprite's def was built before the mode switch: the
  skinned sheets now re-sync their true-color flag at draw time from the
  CURRENT mode, so the baked path is always taken outside ADVANCED / OG RED
  / Gen 2 no matter when the sprite was constructed (the player object
  survives a mode-switch map reload).  The generated fishing pose row
  follows the same rule.

- The overworld skins (player on-foot, bicycle, and trainer NPC sheets, plus
  the generated fishing pose) now follow the COLORS mode instead of staying
  raw full color.  Outside ADVANCED (and OG RED, which keeps the full-color
  look) the sheets are luminance-baked onto the engine's 3-shade DMG ramp
  and ride the map zone shader exactly like vanilla 2bpp art, so SGB / OG /
  OG INV / SGB INV / CLASSIC all recolor them properly.  The fishing pose's
  character row bakes to the same shades as the sheet while its rod half is
  pasted raw, keeping the rod seamless with the far half the overworld
  draws.  Gen 2 is unchanged (no PaletteFX modes).

- Updated for the launcher's mod sandbox, which no longer exposes
  `love.filesystem` to mod code.  File existence probes and byte reads
  now go through `mod:read` (scoped to the mod's own directory), the
  intro placeholder check decodes the frame instead of stat-ing it, and
  OPTIONS > PLAYER SPRITE cycles the shipped
  `assets/trainers/player/` set directly (the engine no longer offers a
  directory listing to mods).

- The overworld fishing pose (Gen 1) is now GENERATED from the custom
  on-foot sheet at runtime, so the vanilla rod pose stays intact for any
  `assets/overworld/player/{name}.png` pick without shipping per-character
  fishing sprites.  Each pose tile is the sheet's own bottom tile row
  (the character stays fully visible) with the NEAR half of the rod
  pasted in from the engine's `fishing_rod.png`, copied pixel-for-pixel
  so it continues seamlessly into the far half the overworld draws
  (down = rod tile 0, up = rod tile 0, sides = rod tile 1, right
  mirrors).  `SpriteRenderer:drawTile` now accepts an in-memory Image so
  the generated tiles draw through the vanilla pose path; a pick with no
  matching sheet keeps Red's fishing pose unchanged.

- OPTIONS > PLAYER SPRITE no longer resets to `red.png` at boot.  The
  "fresh profile starts as Red" rule now fires only on a genuine NEW GAME
  (`save.created` after `game.ready`); the boot-skeleton `save.created`
  keeps the persisted choice, so a CONTINUE no longer builds the overworld
  player with Red until the option is re-toggled.
- The player's overworld bicycle now uses a matching
  `assets/overworld/player/{name}_bike.png` sheet (`red_bike.png`,
  `brock_bike.png`, ...) instead of always keeping the vanilla bike sheet.
  The on-foot and bike sheets are re-applied when a save loads and when
  PLAYER SPRITE changes.  Surfing is unchanged.
- A CONTINUE now re-applies the overworld player and NPC skins after the
  save's options are read (`save.loaded`), instead of only when the option
  is cycled in the OPTION screen.

- Overworld trainer sheets now key off the NPC's TRAINER CLASS first
  (`OPP_BROCK` -> `brock.png`), then the sprite record (`SPRITE_BROCK.png`,
  `sprite_brock.png`, or `brock.png`).  Gen 1 gym leaders reuse generic
  sprite records (Brock's map object is `SPRITE_SUPER_NERD`), so the class
  is the only name that can match the sheets -- the mid-game leaders
  (Brock, Misty, Lt. Surge, Erika, Koga, Sabrina, Blaine) now actually
  get replaced instead of silently staying vanilla.  The sprite id stays
  as the fallback, which is what reaches the rival (`SPRITE_BLUE` ->
  `blue.png`) and the Elite Four.
- The NPC re-skin only ADOPTS an NPC whose sprite is still the vanilla
  registry record, and only once a matching sheet exists.  A sprite that
  another mod rebuilt -- Yellow's follower or overworld-wilds
  followers/ambient Pokemon (which construct with a `SPRITE_PIKACHU`
  placeholder and swap in real art right after) -- is never adopted, so
  cycling REPLACE SPRITES can no longer clobber those NPCs into a single
  wrong sprite.  Both generations get the same guard.
- Fixed the Gen 2 NPC require path (`src.world.gen2.Npc`, not `NPC`), so
  Gold's NPC replacement no longer depends on a case-insensitive
  filesystem to engage.

- REPLACE SPRITES now cycles through six modes -- NONE, PLAYER, TRAINER,
  PLAYER + TRAINER, OVERWORLD, ALL -- and the last two replace the
  overworld NPC walking sheets from `assets/overworld/trainers/`, named
  after the sprite record (`SPRITE_BROCK.png`, `sprite_brock.png`, or
  `brock.png`).  The sheets are full-color 16x96 PNGs with transparency
  (the vanilla six-frame layout); the substituted record marks trueColor
  and copies every other field, like the player overworld skin.  The swap
  happens where the engine builds each NPC -- Gen 1's `src.world.NPC.new`
  and Gen 2's `src.world.gen2.NPC` constructor and `setSpriteDef` (so a
  variable sprite repainting mid-map stays skinned) -- leaving the player
  and everything else untouched.  OVERWORLD replaces only the overworld
  sheets (the battle portraits are left alone, exactly like NONE), and
  ALL adds the overworld sheets on top of the PLAYER + TRAINER portraits.
  Cycling the option re-skins the NPCs already on screen, and NONE or
  OVERWORLD restore the vanilla sheets.  Older saves keep working: a
  legacy value (or a pre-1.6 boolean) reads as PLAYER + TRAINER.

- OPTIONS > PLAYER SPRITE now also skins the player's overworld character:
  when a sheet named after the chosen portrait exists in
  `assets/overworld/player/`, the player's on-foot sprite uses it (the
  walk sheet only; surfing and biking keep their own sheets).  A
  `*_flip.png` pick reads the sheet by its base name (`red_flip.png` ->
  `red.png`), so the mirrored and unmirrored portraits share one sheet.  The sheets
  follow the vanilla layout -- a 16x96 PNG with six 16x16 frames (stand
  down/up/left, walk down/up/left) -- and are full color with real alpha,
  like the mod's battle art: the substituted record marks trueColor so the
  engine's DMG-shade palette bakes are skipped, and every other field is
  copied from the record it replaces, so a custom frame size still grounds
  correctly.  The swap happens where the player is built (Gen 1's
  `src.world.Player.new` and Gen 2's `src.world.gen2.Player` constructor
  and `setSprite`, the latter gated to the on-foot SPRITE_CHRIS record),
  so an NPC's sheet is never touched.  Cycling the option in the OPTION
  screen re-skins the live player immediately (on both generations), and
  a chosen portrait with no matching sheet leaves the vanilla overworld
  sprite untouched -- or restores it after a pick that had one.

- Red/Blue/Yellow: with FRONT SPRITES on, the player's front sprite in a
  2D battle is now grounded on the text box at the same size as the
  enemy's front sprite.  Crystal front frames are centred in a 56px
  square with transparent padding on every side, while the back art the
  slot normally shows is bottom-aligned, so the front art floated above
  the text box in an empty gap.  The player's frames are now cropped of
  their bottom rows, which stands the mon on the text box while keeping
  the art at its native size -- the same 56px art the enemy draws
  uncropped in the front slot, so both sides match.  Only the bottom is
  cropped: trimming the left padding per frame would pull each frame's
  body to a different x (the frames' varying left pixels sit in front of
  a body that stays put), making the sprite jitter side to side as the
  animation plays.  Each baked frame is cached (weak-keyed) and every
  failure path falls back to the unmodified frame; the enemy slot, the
  default back art, 3D voxel battles and Gen 2 are untouched.

- Red/Blue/Yellow: with FRONT SPRITES on, the player's own Pokémon in its
  2D battle back slot now faces the opponent.  The front art is drawn
  for the enemy slot (top right, facing down-left toward the player), so
  in the player's slot it previously faced away.  The player's slot now
  mirrors the animated front frames horizontally at runtime -- the same
  mirror the Gen 2 battle already applies -- flipping each frame image
  once (cached per source image, CPU ImageData work on an RGBA copy, no
  duplicate asset files) and falling back to the original frame on any
  failure.  3D voxel battles are untouched (their mod keeps its own
  back-sprite handling), as are the enemy slot and the default back art.

- Red/Blue/Yellow: the dex entry page and status screen no longer draw a
  white box behind the mon.  The frames were baked onto the species'
  final palette and then marked true-color, so the unshaded re-blit drew
  the sprite's white canvas background raw over the mon-palette zone.
  Outside ADVANCED the frames are now baked onto the 4-shade DMG ramp
  instead, so the screen's own SGB zone recolors them like vanilla 2bpp
  art (255/170/85/0 -> c0/c1/c2/c3) and no true-color re-blit is needed.
  The Hall of Fame sweep and the Oak speech follow the same grayscale
  bake, and their true-color flags now follow the COLORS mode.
- Gold: the player's own Pokémon is visible again in battle.  The
  runtime mirror for the back slot reads the frame back through a 1:1
  canvas, but the readback ran while the widescreen translate/scale was
  still on the transform stack, so the image was drawn out of the
  canvas and read back empty.  The readback now resets to the origin
  before blitting, so the flipped frame has its pixels.

- Gold: the boot log no longer warns that `src.battle.BattleState.newWild`
  / `newTrainer` have no Gen 2 backing.  The generation gate now probes
  `BattleState.new` (present on Gold's battle screen class, absent on the
  Gen 1 battle state) instead of reading the adapter's deliberately absent
  members, and the Gen 1 battle factories are captured inside the Gen
  1-only patch block where they are used.
- Red/Blue/Yellow: the dex entry page and the status screen now re-bake
  their animated sprite onto the active COLORS mode and restart the
  animation when the mode changes, matching the battle screen.  Before,
  the frames were baked once when the page opened and kept the old
  palette until the screen was reopened.

- Gold: the dex entry page and status screen no longer flatten the
  animated mon to a near-silhouette.  Those screens draw every pic
  through their own GBC palette pass, which buckets a full-color image
  by its red channel and collapses it (a full-color mon lost its body
  colour).  The Gen 2 `picFor` wraps now hand back the full-color frame
  images marked as the mod's own art, and the screens' draw methods are
  wrapped to skip the GBC palette for those images -- the pic is drawn
  raw, exactly like the battle pics already were.
- Gold: a shiny mon's back pic now uses its own shiny variant (the back
  slot previously always served the normal back art on Gen 2).

- Removed GIF front-sprite support; the front art is now the PNG frame
  folders exclusively (`assets/front/<variant>/<dex>/NNN.png` with the
  per-frame durations from animation_data).  The hand-rolled GIF decoder,
  the GIF path routing, the `Assets.imageData` .gif shim, and the
  `decodeGif` / `gifPath` exports are gone.  Animations are unchanged:
  the battle, dex entry page, status screen, Hall of Fame sweep,
  evolution movie, title, Oak speech, and boot intro all animate the PNG
  frames now, and the luminance baking (full-color frames remapped onto
  the mode's palette by luminance) is preserved via the new
  `lumaFrames` / `framesFront` path.

- Gold: with FRONT SPRITES on, the player's own Pokémon in its battle
  back slot now faces the opponent.  The front art is drawn for the
  enemy slot (top right, facing down-left toward the player), so in the
  player's slot it previously faced away.  The player's slot now
  mirrors the animated front frames horizontally at runtime: a
  `BattleState:pic` wrap on the native Gold module flips each frame
  image once (cached per frame path, CPU ImageData work on an RGBA
  copy -- no duplicate asset files), and on any failure falls back to
  the original frame, so the battle keeps animating.  The enemy slot,
  the default back art, the dex/summary screens, and Gen 1 are all
  untouched.

- The battle animation, shiny reveal and delayed enemy cry, and the
  opponents side of CUSTOM SPRITES now run on Gen 2 (Gold):
  - Battle sprites animate on Gold.  Gold's battle screen re-resolves
    its pics through `pokemon.sprite` every frame, so the hook now
    serves the PNG frame set time-indexed (frame counts are probed and
    cached per species/variant) instead of the static frame 1.  FRONT
    SPRITES works on Gold too -- the player's back slot serves the
    animated front frames.  Gen 2 art is served with `trueColor` set
    (the mod's art there is always the full-color set; the grayscale
    folders are empty), so Gold's GBC palette pass leaves it alone.
  - Shiny reveal + delayed enemy cry on Gold: the mod now wraps the
    native `src.ui.gen2.BattleState` module.  A shiny enemy's send-out
    cry is deferred through a `playCry` wrap until the sparkle reveal
    finishes, driven by an `update` wrap (shared `revealAudioFinished`
    clock), with the sparkles drawn through the shared `battle.overlay`
    hook (whose Gen 2 payload carries the battle as `.battle`).
    Shininess reads Gold's own `mon.shiny` flag (added as a fast path
    in `isShiny`), and the `battle.started` / `battler_switched` /
    `battle.ended` handlers now accept Gen 2's `battle`-keyed payloads.
  - CUSTOM SPRITES opponents side on Gold: `BattleState.new` is wrapped
    to swap the mod's portrait into `enemyTrainerImage` /
    `enemyTrainerPath` (the path resolver was extracted from
    `modTrainerPic` as `trainerArtPath`), queuing the intro
    trainer-slide event when the engine cache had no vanilla pic.
  - The dex entry page and the status screen animate on Gold too.  Both
    resolve their pic once per draw into a per-path cache and redraw it
    every frame, so the `picFor` methods of `src.ui.gen2.PokedexMenu`
    (entry view only -- the listing keeps its static box, like Gen 1)
    and `src.ui.gen2.SummaryMenu` now return the time-indexed frame
    image, cached per path for the session; the status screen animates
    in the mon's own shiny variant.  These screens draw through their
    own GBC palette passes, so the raw full-color frames go through the
    same rendering the static art already had.
  - Everything else stays Gen 1-only on Gold as before (title/intro/
    evolution screen animations, PaletteFX pipeline, Transform/
    move-effect patches, staged-battle mono bakes, voxel interop).

## 1.7.0

- Gen 2 (Gold) support: the manifest now declares `"games": ["gen1",
  "gen2"]`, so a Gold boot loads the mod instead of skipping it.  The
  mod is a content/engine-internals mod, so on Gen 2 it degrades
  gracefully rather than porting every Gen 1 engine patch:
  - Still works on Gold: the `content.pokemon` registrations (static
    Crystal front/back art and scales), the `pokemon.sprite` /
    `player.sprite` hooks (PNG frames are served first there, since
    Gold's loader cannot decode .gif and the `Assets.imageData` shim is
    Gen 1-only), the `battle_sprite_scales` registrations, the shared
    events, and the three options rows.  FRONT SPRITES, CUSTOM SPRITES
    and PLAYER SPRITE now appear directly in Gold's OPTION screen (the
    same `ui.options.rows` hook, inserted before CANCEL) and are saved
    per profile in the Gold options block -- Gold's OPTION screen
    answers the Gen 1 `step`/`value` row vocabulary
    (src/ui/gen2/OptionsMenu.lua), so the same descriptors serve both
    generations.  On Gold, PLAYER SPRITE and the player side of CUSTOM
    SPRITES take effect immediately (they drive the `player.sprite`
    hook); FRONT SPRITES persists its setting but its battle feature
    stays gated until the battle animation port lands.
  - Gated to Gen 1 on a Gold boot: the battle animation loop, shiny
    reveal and delayed cry (`BattleState.newWild` / `newTrainer` /
    `update` and `Sound.playCry` patches -- `newWild` reads nil on the
    Gen 2 adapter, as documented), the dex/status/title/intro/Oak/
    evolution/Hall-of-Fame/trainer-card screen patches, the
    `PaletteFX` recolor pipeline (raw art loads and the engine's own
    palette passes handle it), the Transform / move-effect patches, the
    mono-mode staged-battle bakes, the voxel-mod interop, the
    `Assets.imageData` GIF shim, and the dedicated CRYSTAL SPRITES
    submenu screen (built on Gen 1's `OptionRows`; Gold gets the three
    rows inline instead).
  - Gen 2 shininess is detected directly from the mon's DVs (the Gen 2
    formula) when `src.pokemon.Stats` is unavailable, so shiny artwork
    selection keeps working wherever the mon struct carries DVs.
  - Requires a Gen 2 boot test (headless `T.sdk.loadMod(..., {
    generation = 2 })` and a real Gold run) to confirm the shared hooks
    and events are raised under the same names.

## 1.6.0

- `trimGround` (transparent-padding removal that grounds sprites on the
  3D battle platform) is now gated behind `voxelContext`.  In 2D battles
  the sprites are left at their authored dimensions so they don't rise up
  and cover the name labels.
- The sprite hook now serves the art format that fits who is asking:
  when the DexNav or Gen1 Modern UI mods are installed (detected via
  `mod.find`, the same API those mods use on each other), the
  `pokemon.sprite` path resolves to the PNG frame folder first so their
  `love.graphics.newImage` loads succeed; otherwise the animated .gif
  stays the preferred path, exactly as before.  This removes the need
  for the DexNav and Modern UI to carry their own PNG fallbacks, while
  every renderer this mod animates itself (battle, menus, evolution,
  title, Oak speech, Hall of Fame) still decodes the GIF directly and
  is unaffected either way.
- New OPTIONS > CRYSTAL SPRITES > REPLACE SPRITES row (default BOTH,
  saved per profile): a 4-way choice of which trainer portraits use the
  custom art folders, cycling NONE -> PLAYER ONLY -> TRAINERS -> BOTH.  BOTH loads the player portrait from
  `assets/trainers/player/` (`red.png` for the front pic / trainer card
  / Hall of Fame, a `redb.png` in the same folder wins for the battle
  back slot) and the opponent portraits from
  `assets/trainers/opponents/{class}.png`; PLAYER ONLY and TRAINERS
  restrict the custom folders to one side; NONE replaces nothing at all
  -- both sides keep the engine's own sprites, skipping even the mod's
  shipped fallback art.  The opponent folder may be spelled `opponents`
  or `opponent`, and a file named after the class id (`OPP_AGATHA.png`)
  is accepted too.  A side with no custom file falls back to the
  ENGINE's own sprite: the mod only ever hands the engine a portrait
  path that is confirmed on disk, so a missing or skipped custom file
  can never break battle construction (the engine crashes on a missing
  pic path, and the mod ships no redb.png at all).  The Oak speech's
  Oak/rival portraits and the 2D back-pic scaling registration follow
  the same custom folders.  The setting is stored as a string so an
  older engine's options round-trip never has to survive a mod-added
  boolean.
- Fixed a latent crash in the staged-battle mono bake: the baked-image
  cache was only initialized on a COLORS-mode reload, so a battle that
  reached the mono bake before any colours change read a nil global
  ("attempt to index global 'monoBaked'").  It is now initialized at
  module scope and still reset on a colours reload.
- New OPTIONS > CRYSTAL SPRITES submenu: instead of individual rows in
  the main options, the three mod options (FRONT SPRITES, REPLACE
  SPRITES, PLAYER SPRITE) live in a dedicated screen opened by
  selecting CRYSTAL SPRITES.  B/CANCEL returns to the main options.
- New PLAYER SPRITE option (default `red.png`, saved per profile): the
  row lists the .png files in `assets/trainers/player/` and cycles
  through them, showing each name in caps (RED, BROCK, ...).  The
  chosen portrait drives the trainer card, Hall of Fame, and battle
  back pic; a non-`red` pick fills the back slot with itself, while the
  dedicated `redb.png` still wins for the default `red.png`.
- A brand-new game always starts with the classic Red player portrait:
  the engine's options are global and survive New Game, so without this
  a fresh profile would inherit the sprite last picked on another
  profile.  (The other options still carry over as usual.)
- Auto-flip by filename replaces the FLIP SPRITE toggle (which is
  removed from the options): a player portrait named `*_flip.png`
  (e.g. `red_flip.png`) is mirrored horizontally for the battle back
  pic automatically.  It only applies while REPLACE SPRITES is BOTH or
  PLAYER ONLY and never touches the opponent portraits.  The flip is
  applied when the battle ENTERS, once the engine has loaded the back
  pic (BattleState:enter -- newTrainer runs before the back pic
  exists, which is why earlier builds never flipped).  The mirrored
  copy is deliberately not marked as the mod's own art, so the
  mono-mode luminance bake treats it exactly like the unflipped
  portrait (a marked copy skipped the bake and rendered flat).  The
  mirror reads the portrait's pixels through Image:getData (cloned)
  instead of a canvas readback, which can silently crop or fail under
  a scaled/DPI transform at battle construction.  The demo battles are
  excluded: the catch tutorial's back pic is the OLD MAN's and Yellow's
  Pallet intro is Prof. Oak's, so mirroring them would flip those
  characters the wrong way.

## 1.5.6

- Future-proofed for Kanto mods that add Gen 2 mons: the species map now
  covers the full Johto set (Chikorita through Celebi, dex 152-251), so
  Crystal-style art dropped into the mod's asset folders
  (`assets/front/normal/152.gif`, ...) animates everywhere the Kanto mons
  do -- battle, the stats screen, the dex entry page, the evolution movie,
  the title cycle and the Hall of Fame.  Species with no art in the mod's
  folders pass through untouched: the sprite hook leaves their own
  registration (path and true-color flag) alone, and the content patch
  only ever points spriteFront/spriteBack at files that exist, so a Kanto
  mod's Johto mons can't be broken by half-applied routes.
- The Hall of Fame's party sweep now shows each member's ANIMATED Crystal
  front pic -- the engine loaded the mod's .gif path with
  love.graphics.newImage, which cannot read GIFs, so the mons were blank.
  They get the same decoded-frame treatment as the dex page and status
  screen (raw art riding the engine's recolor passes, true-color under
  ADVANCED only) and animate on the same 1X real-time clock.

## 1.5.5

- Fixed the Ditto Transform revert: the copied species' purple shape
  showed for one frame and then snapped back to Ditto's own sprite. The
  mod recorded the transform on the battler by wrapping
  MoveEffects.TRANSFORM_EFFECT, but the engine dispatches every move
  effect through BattleState:effectRecord — and the records it hands
  out are deep copies of the module's RECORDS table (the loader
  deep-copies each registered record), so none of the module-table
  wraps ever ran in battle. The animation loop kept playing Ditto's
  pic, and the engine's purple swap was overwritten the next frame.
  The switch is now driven from the SE_TRANSFORM_MON animation event
  (the moment the transform square hits the mon): the battler records
  the copied species there, so the purple transformed mon takes over
  and animates for the rest of the battle — after Ditto has played its
  own shrink/square animation, instead of changing on the very first
  frame of the move. With battle animations off, no animation plays
  and the event never fires, so the record wrap records the copy at
  effect time instead and the purple swap still sticks.
- Shiny mons outside the ADVANCED (REDPP) COLORS mode now always use
  the same art as their normal form: the grayscale set, falling back
  to the normal full-color art — never the full-color shiny variant.
  A grayscaled shiny looks identical to its normal form anyway, so the
  shiny art was only ever pulled in by the fallback paths (missing
  grayscale GIFs/PNGs on the front and back slots), where it showed
  off-palette.
- The player's own trainer art can be replaced too: a portrait at
  `assets/trainers/normal/red.png` (with a grayscale variant at
  `assets/trainers/grayscale/red.png`) takes the place of the vanilla
  red pic on the trainer card and in the Hall of Fame, and the same
  portrait serves as the redb battle back pic when a battle starts (a
  dedicated `assets/trainers/{mode}/redb.png` wins for the back slot
  if present). Full color under ADVANCED, grayscale otherwise; the
  catch-tutorial demo and Yellow's Oak demo keep their own pics. The
  trainer card shows the portrait mirrored horizontally (the pic art
  faces the battle back slot's way, while the card portrait
  traditionally faces the other way) — the mirror is baked into an
  in-memory copy, so the shipped file can stay oriented for the battle
  back pic. The Hall of Fame entry screen mirrors the portrait the same
  way. And in 2D battles the back pic no longer renders huge: the
  portrait is scaled to the vanilla back pic's on-screen size (the
  vanilla redb is a 32x32 pic drawn at 2x, so any portrait is sized to
  that 64px width from its PNG header), which the 3D battle never
  needed since it sizes its own billboard.

## 1.5.4

- Fixed the evolution movie showing the evolved mon as a flat
  black-and-white silhouette under the ADVANCED (REDPP) COLORS mode. The
  engine's own pic load tries love.graphics.newImage on the mod's .gif
  path, fails, and leaves the sprite's true-color flag false — so the
  SGB zone pass bucketed the vivid full-color frames by red channel and
  collapsed the red/orange/white body into the paper shade. The hook now
  repairs the true-color flags under REDPP (the same repair the title,
  Oak speech and menu screens already did), so the vivid art rides raw
  and un-recolored. Grayscale modes are untouched — the zone pass still
  recolors them as designed.

## 1.5.3

- The evolution movie now ANIMATES the Crystal GIF frames again (it
  animated back when the mod shipped PNG frame folders). The engine's
  EvolutionState decodes its pics with love.graphics.newImage, which
  cannot read GIFs, so the movie could only ever show a single static
  frame. It now receives the decoded Crystal frames (ground-trimmed to
  sit on the movie's baseline; vivid under ADVANCED, grayscale
  otherwise) and animates them from draw time — like the Oak speech,
  because the movie's update stops being called once the congratulations
  text box is pushed on top, so an update-driven loop would freeze the
  settled form. The old form animates through the back-and-forth flash
  and the new form keeps animating on the settled screen.

## 1.5.2

- Fixed a fatal load error: the mod's installer closure had grown past
  Lua 5.1's 60-upvalue limit ("function ... has more than 60 upvalues"),
  which stopped the whole mod from loading. The installer is now split
  into small module-scope steps, each capturing only the helpers it
  touches, so no function is anywhere near the cap.
- The evolution movie no longer shows a white screen on GIF-only
  installs: it decoded its pics with love.graphics.newImage directly,
  which cannot read GIFs, so the evolving mon was invisible (cry still
  played). It now uses the decoded Crystal frames — ground-trimmed so
  the mon sits on the movie's baseline like the vanilla art did — vivid
  under ADVANCED, grayscale in the other COLORS modes.

## 1.5.1

- Battle sprites no longer float above the ground. The engine pins pics
  to their slot by measuring each loaded image's transparent ground
  padding — a measurement the mod's own frames skip, so any art with
  empty rows under the feet was drawn noticeably high. Battle frames are
  now trimmed of that padding (fronts: bottom rows; backs: bottom rows
  and left columns), so feet land exactly where the vanilla art's did.
- The new-game Oak speech's portraits now use the replacement trainer
  art too: prof.oak and rival1 are swapped in via the speech's override
  fields — full color under ADVANCED (kept true-color so the zone pass
  can't flatten them), grayscale otherwise.

## 1.5.0

- Ditto's Transform now actually works: the battle shows the copied
  species' shape instead of Ditto's own — animated, and tinted to
  Ditto's purple palette on both sides (front sprites and the
  player-side back pic), whether or not FRONT SPRITES is on.
- New grayscale art set: `assets/front/grayscale/*.gif` and
  `assets/back/grayscale/*.png` are used in every COLORS mode except
  ADVANCED. The art is authored as DMG-style 4-shade art, so the
  engine's own recolor passes (SGB zones, forced mono) handle it like
  vanilla art instead of flattening full-color shading. Battle,
  title, dex/status menus and the Oak speech all follow the mode.
- Trainer replacement sprites: `assets/trainers/normal/*.png` (full
  color) and `assets/trainers/grayscale/*.png` are used for opponent
  trainer portraits in battle, picked by the active COLORS mode and
  named after the engine's generated pics (agatha, brock, giovanni,
  jessie_james, rival1-3, ...).
- Fixed a latent crash in the luminance GIF baker (a stale cache
  variable left over from a rename) that would fire when a GIF was
  missing.

## 1.4.2

- Switching COLORS modes no longer ruins the title screen. The cycling
  mon is now luminance-tinted onto the active mode's palette in every
  non-ADVANCED mode (raw true color under ADVANCED), so it keeps its
  shading instead of being flattened by the zone pass; the trainer's
  recolor is restored to the raw art the moment you leave ADVANCED so
  the zone pass can't mangle the baked colors. The Oak speech's Nidorino
  show-off and the boot-intro fight get the same per-mode tinting.
- The Oak speech's Nidorino show-off now animates: the demo pic is
  advanced from draw time, because the speech's update isn't called
  while its dialogue box sits on top — Nidorino keeps moving through
  the whole speech.

## 1.4.1

- New-game Oak speech: the NIDORINO show-off (the mon Oak introduces
  with "This world is inhabited by creatures called POKéMON!", right
  before he asks your name) went invisible on GIF-only installs — the
  speech decodes its pic with love.graphics.newImage, which cannot read
  GIFs, so the field stayed white while the cry played. It now uses the
  mod's animated Crystal Nidorino on all three games — vivid under
  ADVANCED, and luminance-tinted onto the MEWMON palette in the other
  COLORS modes so the shading survives the recolor pass.
- Title screen: under REDPP the trainer is no longer raw gray — his DMG
  art is baked to his iconic red/white/blue outfit (luminance-mapped),
  and the strip stays true-color so no MEWMON purple smears over the
  vivid mon. Every other COLORS mode keeps the zone pass's authentic
  palette colors for him.
- Boot intro: the Gengar/Nidorino fight's substitution now tints the
  Crystal frames onto the intro's PURPLEMON palette by luminance, so the
  shading survives the SGB pass instead of being bucketed by red
  channel.

## 1.4.0

- GIF front sprites: drop an animated GIF89a at `assets/front/normal/<dex>.gif`
  (or `assets/front/shiny/<dex>.gif` for the shiny variant) and the battle
  uses it as the animated front art, with the GIF's own per-frame timing.
  The mod decodes GIFs itself (LÖVE can't load them), handling transparency,
  partial frames, disposal and interlacing, and falls back to the PNG frame
  folders when no GIF is present.
- The dex entry page and the status screen animate the GIF too — the dex
  shows the normal variant, the status screen follows your mon's shininess
  (shiny mons get the shiny animation).

## 1.2.0

- Added OPTIONS > FRONT SPRITES: shows your own Pokémon's animated Crystal
  front sprite in battle instead of the static back art. Saved per profile
  like every other options row; applies on the next battle.

## 1.1.0

- Battle sprite animations and the shiny reveal now always play at 1X real
  time, regardless of the game speed multiplier. Fast-forward previously
  played the Crystal animations N times faster and made the reveal race
  ahead of its audio; timing now follows the real clock like the engine's
  audio does, so visuals stay in sync at every speed.

## 1.0.0

- Combined Crystal Animated Pokémon Sprites v4.1.
- Combined Gen 2 Shiny Visuals v2.0.
- Unified BattleState update handling to avoid wrapper conflicts.
- Added Crystal normal/shiny animation selection.
- Added sparkle sound followed by the Pokémon cry.
- Added wild, trainer, and trainer switch-in support.
