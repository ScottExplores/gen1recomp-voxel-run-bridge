# Scott's Pocket Bag asset provenance

The two PNGs in `assets/` are original project assets generated for Scott's
Tweaks on 2026-08-22 with OpenAI's built-in image-generation tool. The prior
Modern Bag UI screenshot was supplied only as a broad style/composition
reference. No upstream raster, ROM image, logo, text, or exact artwork was
copied into these files.

## `scotts_pocket_bag_sheet.png`

Generation prompt:

> Use case: stylized-concept. Asset type: production game UI sprite sheet for
> a retro monster-catching RPG Bag menu. Input image is a style/composition
> reference only; do not copy its UI, text, logos, or exact artwork. Create one
> original pixel-art sprite sheet showing the same generic five-compartment
> travel backpack in six consistent states: neutral/all, main items selected,
> medicine selected, capture balls selected, machines selected, and key items
> selected. Use a compact front-facing green canvas backpack with dark green
> side pockets, top flap, straps, and five clearly distinguishable
> compartments. Every frame must use exactly the same backpack silhouette,
> scale, position, and pixel grid; only the selected compartment changes
> highlight. Authentic crisp 8-bit/16-bit handheld pixel art, hard pixel edges,
> limited four-shade green base palette plus one restrained highlight color per
> selected state. Exact 3 columns by 2 rows with six equal square cells,
> centered sprites, transparent padding, and no drawn dividers. Reading order:
> neutral/all; items with warm red main-body highlight; medicine with emerald
> upper-pocket highlight; capture balls with red-orange left-side highlight;
> machines with violet right-side highlight; key items with cyan lower-front
> highlight. Genuine transparency; no text, letters, numbers, UI frame,
> checkerboard, outside shadow, trademarks, ball symbols, creatures, or
> watermark.

Transparency cleanup prompt used on that generated sheet:

> Remove only the pale gray-and-white checkerboard background and replace it
> with genuine transparent alpha. Preserve all six backpack sprites exactly:
> their pixel geometry, positions, colors, scale, 3-column-by-2-row layout,
> highlight states, and hard pixel edges. Do not redraw, restyle, recolor,
> resize, move, crop, smooth, add outlines, add shadows, or add text. Keep the
> full canvas and equal cell layout unchanged. No background pixels,
> checkerboard, halo, or watermark.

The renderer applies a hard alpha threshold when shaders are available to
remove the generator's remaining low-opacity presentation glow while leaving
the source PNG unchanged. A shaderless renderer still draws the PNG with its
authored alpha; image-decode or Quad failure uses the former primitive
backpack as a compatibility fallback.

## `pocket_blue_weave.png`

Generation prompt:

> Use case: stylized-concept. Asset type: seamless game UI background texture
> for a retro handheld Bag menu. The input image is a style and palette
> reference only; use its blue woven/stippled sidebar feeling, not any exact
> UI, text, logo, or artwork. Create one original seamless square pixel-art
> textile texture in rich medium cobalt blue with darker navy and lighter-blue
> interwoven pixels. Use authentic crisp 8-bit/16-bit handheld pixel art, hard
> square pixels, a tiny repeating woven/check pattern, and a restrained
> three-to-four-color palette. Edge-to-edge tileable square texture with
> uniform density and no focal point. No text, letters, numbers, icons,
> backpack, border, vignette, gradients, logos, trademarked imagery, or
> watermark; readable when reduced to a 16x16 or 32x32 tile.
