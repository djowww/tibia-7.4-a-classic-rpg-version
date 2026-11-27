#!/usr/bin/env python3
"""Build the pictures of the Achievements trophy hall of the client.

The hall is a small room put together from the same tiles as the Annihilator
reward room: black marble, brick walls, a red carpet and twelve sandstone
pedestals. The client draws the room once and lays the achievement items and
their light on top (client/modules/game_achievements).

Writes to client/data/images/achievements/:
    hall.png         the unlit room, 600x320, with the torch light baked in
    hall_light.png   lit patch of each pedestal: 12 rows (pedestals) x 5 columns (tiers) of 128x128
    hall_statue.png  lit patch of the statue: 6 columns (ranks) of 160x160
    hall_items.png   12 rows (tracks) x 10 columns (5 tiers lit, then 5 as silhouettes) of 32x32
    hall_ranks.png   6 columns (ranks) x 2 rows (earned, silhouette) of 64x32
    hall_glow.png    golden glow of a mastered pedestal, 56x56
    hall_icons.png   bonus icons, 4 columns of 32x32: speed, damage, PvP damage, death loss

Needs the client's Tibia.dat and Tibia.spr (7.72 format), which are not part
of this repository:

    python3 tools/generate-achievement-hall.py --things path/to/client/data/things/772

The layout numbers below are mirrored in achievements.lua. Requires Pillow and numpy.
"""
import argparse
import importlib.util
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location('scenes', Path(__file__).with_name('generate-charselect-scenes.py'))
scenes = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scenes)

FLOOR, WALL_V, WALL_H, WALL_CORNER = 410, 1270, 1271, 1272
CARPET_TOP, CARPET = (2572, 2573, 2574), (2575, 2576, 2577)
TORCH_NORTH, TORCH_WEST, STATUE, PEDESTAL = 2929, 2931, 2031, 477
INNER_W, INNER_H = 15, 6                      # floor tiles inside the walls
PEDESTAL_COLS, PEDESTAL_ROWS = (2, 4, 6, 10, 12, 14), (2, 5)
RANK_COLS = (3, 5, 7, 9, 11, 13)
TORCHES = ((1, 0), (8, 0), (15, 0), (0, 2), (0, 5))
ORIGIN_X, ORIGIN_Y = 40, 48                   # pixel of tile (0, 0) inside the picture
WIDTH, HEIGHT = 600, 320
BONUS_ICONS = (3079, 3280, 3114, 3057)
DARKNESS, DARK_COLOR = 0.6, (4, 3, 8)

# One row per pedestal, left to right, top row first; five items per track.
TRACKS = (
    ('steps', (3552, 3549, 3554, 3079, 3555)),
    ('level', (3031, 3035, 3043, 3365, 3011)),
    ('monsterKills', (2671, 2673, 2679, 2681, 2669)),
    ('pvpKills', (3355, 3375, 3369, 3391, 3387)),
    ('deaths', (3115, 3116, 3114, 3207, 5019)),
    ('magic', (3147, 3059, 3076, 3060, 3101)),
    ('fist', (3050, 3050, 3050, 3050, 3050)),
    ('club', (3270, 3286, 3282, 3279, 3309)),
    ('sword', (3264, 3285, 3265, 3281, 3288)),
    ('axe', (3274, 3266, 3275, 3318, 3303)),
    ('distance', (3277, 3350, 3349, 3449, 3450)),
    ('shield', (3412, 3409, 3416, 3420, 3414)),
)
RANK_TROPHIES = (2677, 2671, 2673, 2679, 2681, 2669)  # deer, wolf, orc, cyclops, dragon lord, demon


def build_room():
    tiles = {}

    def put(x, y, *ids):
        tiles.setdefault((1000 + x, 1000 + y, 7), []).extend(ids)

    for y in range(1, INNER_H + 1):
        for x in range(1, INNER_W + 1):
            put(x, y, FLOOR)
    put(0, 0, WALL_CORNER)
    for x in range(1, INNER_W + 2):
        put(x, 0, WALL_H)
    for y in range(1, INNER_H + 2):
        put(0, y, WALL_V)
    for y in range(1, INNER_H + 1):
        put(INNER_W + 1, y, WALL_V)
    for x in range(1, INNER_W + 2):                 # bottom wall with the doorway
        if x == 6:
            put(x, INNER_H + 1, FLOOR)
        if x not in (7, 8, 9):
            put(x, INNER_H + 1, WALL_CORNER if x == 10 else WALL_H)
    for y in range(2, INNER_H + 3):
        for x, carpet in zip((7, 8, 9), CARPET):
            if y > INNER_H:
                put(x, y, FLOOR)
            put(x, y, carpet)
    for x, carpet in zip((7, 8, 9), CARPET_TOP):
        put(x, 1, carpet)
    for x, y in TORCHES:
        put(x, y, TORCH_NORTH if y == 0 else TORCH_WEST)
    put(8, 2, STATUE)
    for row in PEDESTAL_ROWS:
        for col in PEDESTAL_COLS:
            put(col, row, PEDESTAL)
    return tiles


def item_image(items, sprites, item_id):
    thing = items[item_id]
    image = Image.new('RGBA', (thing.w * 32, thing.h * 32), (0, 0, 0, 0))
    for layer in range(thing.layers):
        for h in range(thing.h):
            for w in range(thing.w):
                index = (layer * thing.h + h) * thing.w + w
                image.alpha_composite(sprites.get(thing.sprites[index]), ((thing.w - 1 - w) * 32, (thing.h - 1 - h) * 32))
    return image


def cell_32(image):
    """Centers an item that spans more than one tile inside a 32x32 cell."""
    if image.size == (32, 32):
        return image
    content = image.crop(image.getbbox())
    if content.width > 32 or content.height > 32:
        content.thumbnail((32, 32), Image.NEAREST)
    cell = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    cell.alpha_composite(content, ((32 - content.width) // 2, (32 - content.height) // 2))
    return cell


def silhouette(image, level, alpha):
    data = np.asarray(image).astype(np.float32)
    gray = data[..., :3].mean(axis=2, keepdims=True) * level
    out = np.concatenate([np.repeat(gray, 3, axis=2), data[..., 3:] * alpha], axis=2)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), 'RGBA')


def falloff(size, cx, cy, radius, strength):
    """Light that is `strength` at the center, 70% of it at 55% of the radius and gone at the edge."""
    ys, xs = np.mgrid[0:size[1], 0:size[0]]
    t = np.hypot(xs - cx, ys - cy) / radius
    return np.where(t < 0.55, strength * (1 - 0.3 * t / 0.55), np.where(t < 1, strength * 0.7 * (1 - t) / 0.45, 0.0))


def patch(bright, cx, cy, radius, strength, cell):
    half = cell // 2
    canvas = Image.new('RGB', (cell, cell))
    canvas.paste(bright.crop((cx - half, cy - half, cx + half, cy + half)))
    alpha = falloff((cell, cell), half, half, radius, strength)
    out = np.dstack([np.asarray(canvas), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(out, 'RGBA')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--things', required=True, type=Path, help='folder with Tibia.dat and Tibia.spr (7.72)')
    parser.add_argument('--out', type=Path, default=ROOT / 'client/data/images/achievements')
    args = parser.parse_args()
    items = scenes.load_items(args.things / 'Tibia.dat')
    sprites = scenes.Sprites(args.things / 'Tibia.spr')
    args.out.mkdir(parents=True, exist_ok=True)

    scene = scenes.render(build_room(), items, sprites, 1007, 1004, 7)
    left, top = (20 - 7) * 32 - ORIGIN_X, (11 - 4) * 32 - ORIGIN_Y   # render() centers its tile at (20, 11)
    bright = scene.crop((left, top, left + WIDTH, top + HEIGHT)).convert('RGB')

    light = np.zeros((HEIGHT, WIDTH))
    warm = np.zeros((HEIGHT, WIDTH))
    for x, y in TORCHES:
        cx, cy = ORIGIN_X + x * 32 + 8, ORIGIN_Y + y * 32 + 16
        light = np.maximum(light, falloff((WIDTH, HEIGHT), cx, cy, 44, 0.85))
        warm = np.maximum(warm, falloff((WIDTH, HEIGHT), cx, cy, 40, 0.16))
    warm = warm * (np.asarray(bright).sum(axis=2) > 0)   # no glow on the void outside the walls
    shade = (DARKNESS * (1 - light))[..., None]
    base = np.asarray(bright).astype(np.float32) * (1 - shade) + np.array(DARK_COLOR) * shade
    base = base * (1 - warm[..., None]) + np.array((255, 150, 40)) * warm[..., None]
    Image.fromarray(base.clip(0, 255).astype(np.uint8), 'RGB').save(args.out / 'hall.png', optimize=True)

    sheet = Image.new('RGBA', (5 * 128, 12 * 128), (0, 0, 0, 0))
    pedestals = [(col, row) for row in PEDESTAL_ROWS for col in PEDESTAL_COLS]
    for index, (col, row) in enumerate(pedestals):
        cx, cy = ORIGIN_X + col * 32 + 8, ORIGIN_Y + row * 32 + 10
        for tier in range(1, 6):
            sheet.paste(patch(bright, cx, cy, 22 + tier * 7, min(1, 0.55 + tier * 0.09), 128), ((tier - 1) * 128, index * 128))
    sheet.save(args.out / 'hall_light.png', optimize=True)

    statue = Image.new('RGBA', (6 * 160, 160), (0, 0, 0, 0))
    for rank in range(6):
        statue.paste(patch(bright, WIDTH // 2 - 4, 84, 34 + rank * 7, 0.8, 160), (rank * 160, 0))
    statue.save(args.out / 'hall_statue.png', optimize=True)

    sheet = Image.new('RGBA', (10 * 32, 12 * 32), (0, 0, 0, 0))
    for row, (_name, ids) in enumerate(TRACKS):
        for tier, item_id in enumerate(ids):
            cell = cell_32(item_image(items, sprites, item_id))
            sheet.paste(cell, (tier * 32, row * 32))
            sheet.paste(silhouette(cell, 0.5, 0.75), ((tier + 5) * 32, row * 32))
    sheet.save(args.out / 'hall_items.png', optimize=True)

    sheet = Image.new('RGBA', (6 * 64, 2 * 32), (0, 0, 0, 0))
    for rank, item_id in enumerate(RANK_TROPHIES):
        trophy = item_image(items, sprites, item_id)
        sheet.paste(trophy, (rank * 64, 0))
        sheet.paste(silhouette(trophy, 0, 0.55), (rank * 64, 32))
    sheet.save(args.out / 'hall_ranks.png', optimize=True)

    # Boots of haste, fire sword, a skull tinted like the red PvP skull, amulet of loss.
    sheet = Image.new('RGBA', (4 * 32, 32), (0, 0, 0, 0))
    for column, item_id in enumerate(BONUS_ICONS):
        cell = cell_32(item_image(items, sprites, item_id))
        if column == 2:
            pixels = np.asarray(cell).astype(np.float32)
            pixels[..., 1:3] *= 0.28
            cell = Image.fromarray(pixels.astype(np.uint8), 'RGBA')
        sheet.paste(cell, (column * 32, 0))
    sheet.save(args.out / 'hall_icons.png', optimize=True)

    glow = falloff((56, 56), 28, 28, 28, 0.55)
    out = np.dstack([np.full((56, 56), 255), np.full((56, 56), 208), np.full((56, 56), 100), glow * 255]).astype(np.uint8)
    Image.fromarray(out, 'RGBA').save(args.out / 'hall_glow.png', optimize=True)
    print('wrote', ', '.join(sorted(p.name for p in args.out.glob('hall*.png'))))


if __name__ == '__main__':
    main()
