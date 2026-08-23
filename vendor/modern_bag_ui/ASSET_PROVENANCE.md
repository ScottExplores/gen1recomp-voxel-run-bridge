# Scott's Pocket Bag asset provenance

The two PNGs in `assets/` are original project assets made for Scott's Tweaks
on 2026-08-22 with OpenAI's built-in image-generation tool. The supplied Bag
screenshot was used only as a visual reference for low-resolution geometry,
palette, and layout. No upstream raster, ROM image, text, logo, or exact
artwork is copied into these files.

The first generated draft was too detailed. The shipping assets were therefore
regenerated to match the much simpler early-handheld appearance and then
mechanically reduced to their actual logical-pixel sizes. The mechanical pass
only removed generator presentation pixels, quantized the requested palette,
and packed/repeated the generated art; it did not introduce replacement art.

## `scotts_pocket_bag_sheet.png`

Final contributing generation prompt:

> Use case: stylized-concept. Asset type: replacement production sprite sheet
> for a retro handheld RPG Pocket menu. Image 1 is the user's original visual
> reference; Image 2 is the current overly detailed 3x2 backpack sheet to
> replace. Redraw the six backpack frames so they look much closer to the very
> simple green backpack in Image 1. Preserve only Image 2's exact 3-column by
> 2-row sheet organization and six selection states; remove its modern detail,
> lighting, glow, and texture. Show one small front-facing five-compartment
> backpack in six identical poses: neutral/all, main items selected, medicine
> selected, capture balls selected, machines selected, and key items selected.
> Use authentic early Game Boy Color UI art on an approximately 28x24 logical-
> pixel grid, enlarged with nearest-neighbor square pixels. Use transparent,
> near-black/dark green, medium green, and pale mint/white. Selected states
> change only one compartment. Use a strong one-logical-pixel outline, blocky
> stair-step corners, exact equal cells, fixed scale/position, generous
> padding, hard alpha, flat fills, and no antialiasing, gradients, glow,
> shadows, texture, text, symbols, frame, checkerboard, or watermark.

Palette/state cleanup prompt:

> Change only the generated sheet's color treatment and background. Preserve
> the 3x2 layout, six equal cells, backpack geometry, coarse grid, positions,
> scale, and five selectable compartment locations. Remove every outside
> checkerboard pixel. Remove gradients, glow, blur, highlights, and bright
> accent colors. Use only opaque white, medium leaf green, and near-black dark
> green; selected frames fill only the selected compartment with flat dark
> green. Use hard binary alpha, flat fills, and no antialiasing, soft edges,
> semitransparent pixels, shading, shadow, texture, text, or watermark.

Production cleanup reduced the generated work to real logical pixels,
flood-filled only the connected outside background to alpha, and quantized the
remaining pixels to white plus two greens. One generated pose became the
canonical 34x21 silhouette. Its alpha mask, outline, straps, and base fills are
copied byte-for-byte to all six frames; the five selected states then replace
only white pixels inside five nonoverlapping compartment interiors with flat
dark green. This prevents pose flicker and makes Items (left), Medicine
(upper), Balls (middle), TMs/HMs (lower), and Key Items (right) visibly
distinct. The six frames are packed into one 102x42 RGBA sheet. The renderer
draws them at integer scale and lets the normal `GREENMON` palette zone supply
the final cartridge-era color.

## `pocket_blue_weave.png`

Final contributing generation prompt:

> Use case: stylized-concept. Asset type: replacement seamless Pocket-menu
> background texture. Image 1 is the user's original visual reference; Image 2
> is the current overly detailed diamond weave to replace. Replace Image 2 with
> the much simpler blue pixel dither behind the backpack in Image 1. Use an
> authentic early Game Boy Color UI background with exactly two flat blue
> colors arranged as one tiny repeating checker/dither tile. Use crisp square
> pixels enlarged with nearest-neighbor scaling. The pattern must read as a
> simple blue speckle/checker, not woven fabric. Make it seamless, uniform, and
> edge-to-edge, with no gradients, lighting, shadows, diamonds, plus signs,
> circles, fabric detail, irregularity, antialiasing, blur, text, icons, border,
> or watermark.

Production cleanup sampled the generated cobalt and pale-blue pair and stored
one exact 4x4 opaque RGB checker tile. The final colors are `#9DB6EA` and
`#3B6BCB`: their red channels deliberately map to shade 1 and shade 2 in the
engine's four-shade SGB palette classifier, so neither blue becomes black on
the real render pass. The renderer repeats that tile one-to-one instead of
shrinking or cropping a large texture, matching the supplied reference's dense
pixel dither without distortion.
