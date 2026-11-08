"""Rasterize the temporary Build 6 moon discs in Minecraft phase order."""

from math import cos, pi, sin, sqrt
from pathlib import Path

from PIL import Image


CELL_SIZE = 64
RADIUS = 30
TEXTURES = Path(__file__).resolve().parents[1] / "shaders" / "textures"
PALETTES = {
    "guofeng": ((255, 245, 213), (49, 59, 64)),
    "xianxia": ((230, 249, 255), (41, 56, 76)),
}


def make_atlas(light, shadow):
    atlas = Image.new("RGBA", (4 * CELL_SIZE, 2 * CELL_SIZE))
    for phase in range(8):
        angle = phase * pi / 4
        offset_x = (phase % 4) * CELL_SIZE
        offset_y = (phase // 4) * CELL_SIZE
        for y in range(CELL_SIZE):
            for x in range(CELL_SIZE):
                nx = (x + 0.5 - CELL_SIZE / 2) / RADIUS
                ny = (y + 0.5 - CELL_SIZE / 2) / RADIUS
                radius_squared = nx * nx + ny * ny
                if radius_squared >= 1:
                    continue
                nz = sqrt(1 - radius_squared)
                lit = phase == 0 or (phase != 4 and -nx * sin(angle) + nz * cos(angle) > 0)
                atlas.putpixel((offset_x + x, offset_y + y), (*(light if lit else shadow), 255))
    return atlas


if __name__ == "__main__":
    for theme, (light, shadow) in PALETTES.items():
        target = TEXTURES / f"{theme}_moon_phases.png"
        make_atlas(light, shadow).save(target)
        target.with_suffix(".png.mcmeta").write_text(
            '{"texture":{"blur":false,"clamp":true}}\n', encoding="utf-8"
        )
