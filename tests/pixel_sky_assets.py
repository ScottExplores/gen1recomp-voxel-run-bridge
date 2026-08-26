#!/usr/bin/env python3
"""Validate Scott's shipped astrophotography as strict block-pixel sprites."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

from PIL import Image


EXPECTED = {
    "m42_orion_nebula.png": (192, 129),
    "b33_horsehead_flame.png": (192, 114),
    "m31_andromeda_galaxy.png": (192, 96),
    "m27_dumbbell_nebula.png": (144, 144),
    "cygnus_loop_veil.png": (132, 192),
    "ic1396a_elephants_trunk.png": (192, 135),
}
BLOCK = 3


def validate(path: Path, dimensions: tuple[int, int]) -> list[str]:
    errors: list[str] = []
    image = Image.open(path)
    if image.size != dimensions:
        errors.append(f"size {image.size}, wanted {dimensions}")
    if image.mode != "P":
        errors.append(f"mode {image.mode}, wanted indexed P")
    if image.info.get("transparency") != 0:
        errors.append("palette index 0 is not the transparent index")
    colors = image.getcolors(maxcolors=256) or []
    if len(colors) > 24:
        errors.append(f"uses {len(colors)} palette entries, wanted <=24")
    rgba = image.convert("RGBA")
    alpha_values = set(rgba.getchannel("A").get_flattened_data())
    if alpha_values != {0, 255}:
        errors.append(f"alpha is not binary: {sorted(alpha_values)}")
    bbox = rgba.getchannel("A").getbbox()
    if not bbox:
        errors.append("has no visible pixels")
    elif (bbox[0] < BLOCK or bbox[1] < BLOCK
          or bbox[2] > image.width - BLOCK
          or bbox[3] > image.height - BLOCK):
        errors.append(f"foreground lacks a one-block transparent margin: {bbox}")
    if image.width % BLOCK or image.height % BLOCK:
        errors.append("dimensions are not divisible by the block size")
    else:
        pixels = rgba.load()
        for y in range(0, image.height, BLOCK):
            for x in range(0, image.width, BLOCK):
                reference = pixels[x, y]
                if any(pixels[x + dx, y + dy] != reference
                       for dy in range(BLOCK) for dx in range(BLOCK)):
                    errors.append(f"nonuniform {BLOCK}x{BLOCK} block at {x},{y}")
                    return errors
    if path.stat().st_size >= 50_000:
        errors.append(f"asset is unexpectedly large: {path.stat().st_size} bytes")
    return errors


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    asset_root = root / "assets" / "sky" / "astrophotography"
    failures = 0
    for name, dimensions in EXPECTED.items():
        path = asset_root / name
        if not path.is_file():
            print(f"FAIL {name}: missing")
            failures += 1
            continue
        errors = validate(path, dimensions)
        if errors:
            for error in errors:
                print(f"FAIL {name}: {error}")
            failures += len(errors)
        else:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            print(f"PASS {name}: {path.stat().st_size} bytes sha256:{digest}")
    if failures:
        print(f"Pixel sky: {failures} checks failed")
        return 1
    print(f"Pixel sky: {len(EXPECTED)} strict {BLOCK}x{BLOCK}-block assets passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
