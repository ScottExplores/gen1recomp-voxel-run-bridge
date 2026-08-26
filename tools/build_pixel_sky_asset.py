#!/usr/bin/env python3
"""Build a strict block-pixel, indexed, transparent deep-sky texture.

The creative restyle happens before this tool.  This final deterministic pass
removes the generated backdrop, limits the palette, and guarantees that every
logical texel becomes one identical 3x3 block in the shipped PNG.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


def background_mask(image: Image.Image, mode: str) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] < 250 and mode != "checker":
        return alpha

    pixels = rgba.load()
    mask = Image.new("L", rgba.size, 0)
    target = mask.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _ = pixels[x, y]
            hi, lo = max(r, g, b), min(r, g, b)
            saturation = hi - lo
            if mode == "white":
                distance = ((255 - r) ** 2 + (255 - g) ** 2
                            + (255 - b) ** 2) ** 0.5
                value = int(max(0, min(255, (distance - 12) * 7)))
            elif mode == "checker":
                # The generator occasionally paints a transparency checker.
                # Its tiles are bright and neutral; the Veil is red/cyan.
                value = 0 if hi >= 214 and saturation <= 24 else 255
            elif mode == "dark-cloud":
                # Build the silhouette from emission, then fill its enclosed
                # dark dust lanes after the logical-size reduction.
                red_signal = r - max(g, b) * 0.92
                value = 255 if r >= 28 and red_signal >= 5 else 0
            else:  # black
                value = int(max(0, min(255, (hi - 8) * 10)))
            target[x, y] = value
    return mask


def fill_enclosed_holes(mask: Image.Image) -> Image.Image:
    """Fill transparent regions that cannot reach the logical canvas edge."""
    data = mask.load()
    width, height = mask.size
    outside = set()
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))
    while queue:
        x, y = queue.popleft()
        if (x, y) in outside or data[x, y] != 0:
            continue
        outside.add((x, y))
        if x: queue.append((x - 1, y))
        if x + 1 < width: queue.append((x + 1, y))
        if y: queue.append((x, y - 1))
        if y + 1 < height: queue.append((x, y + 1))
    out = mask.copy()
    out_data = out.load()
    for y in range(height):
        for x in range(width):
            if data[x, y] == 0 and (x, y) not in outside:
                out_data[x, y] = 255
    return out


def build(args: argparse.Namespace) -> None:
    source = Image.open(args.input).convert("RGBA")
    mask = background_mask(source, args.background)
    bbox = mask.point(lambda value: 255 if value >= args.source_threshold else 0).getbbox()
    if not bbox:
        raise SystemExit("no foreground survived background removal")

    source = source.crop(bbox)
    mask = mask.crop(bbox)
    inner_w = args.logical_width - 2 * args.padding
    inner_h = args.logical_height - 2 * args.padding
    scale = min(inner_w / source.width, inner_h / source.height)
    size = (max(1, round(source.width * scale)),
            max(1, round(source.height * scale)))
    source = source.resize(size, Image.Resampling.BOX)
    mask = mask.resize(size, Image.Resampling.BOX)

    rgba = Image.new("RGBA", (args.logical_width, args.logical_height))
    logical_mask = Image.new("L", rgba.size, 0)
    left = (args.logical_width - size[0]) // 2
    top = (args.logical_height - size[1]) // 2
    rgba.paste(source, (left, top))
    logical_mask.paste(mask, (left, top))
    logical_mask = logical_mask.point(
        lambda value: 255 if value >= args.alpha_threshold else 0)
    if args.close > 1:
        logical_mask = logical_mask.filter(ImageFilter.MaxFilter(args.close))
        logical_mask = logical_mask.filter(ImageFilter.MinFilter(args.close))
    if args.fill_holes:
        logical_mask = fill_enclosed_holes(logical_mask)

    rgb = Image.new("RGB", rgba.size, (0, 0, 0))
    rgb.paste(rgba.convert("RGB"), mask=logical_mask)
    quantized = rgb.quantize(
        colors=args.colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    palette = quantized.getpalette()[: args.colors * 3]
    palette = [0, 0, 0] + palette
    palette.extend([0] * (768 - len(palette)))
    indices = list(quantized.get_flattened_data())
    coverage = list(logical_mask.get_flattened_data())
    indexed = Image.new("P", rgba.size, 0)
    indexed.putpalette(palette)
    indexed.putdata([index + 1 if alpha else 0
                     for index, alpha in zip(indices, coverage)])
    indexed.info["transparency"] = 0
    final = indexed.resize(
        (args.logical_width * args.block, args.logical_height * args.block),
        Image.Resampling.NEAREST,
    )
    final.info["transparency"] = 0
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    final.save(output, optimize=True, transparency=0)


def parser() -> argparse.ArgumentParser:
    out = argparse.ArgumentParser()
    out.add_argument("input")
    out.add_argument("output")
    out.add_argument("--logical-width", type=int, required=True)
    out.add_argument("--logical-height", type=int, required=True)
    out.add_argument("--background",
                     choices=("white", "black", "checker", "dark-cloud"),
                     required=True)
    out.add_argument("--block", type=int, default=3)
    out.add_argument("--colors", type=int, default=23)
    out.add_argument("--padding", type=int, default=2)
    out.add_argument("--source-threshold", type=int, default=24)
    out.add_argument("--alpha-threshold", type=int, default=24)
    out.add_argument("--close", type=int, default=1,
                     help="odd logical-pixel morphology kernel")
    out.add_argument("--fill-holes", action="store_true")
    return out


if __name__ == "__main__":
    build(parser().parse_args())
