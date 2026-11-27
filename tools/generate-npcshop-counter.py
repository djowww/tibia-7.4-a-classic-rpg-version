#!/usr/bin/env python3
"""Build the shop counter picture of the NPC trade window of the client.

The window shows a small shop: a brick wall with blackboards and torches, the
merchant standing behind a wooden counter and the chosen item lying on it. The
client draws this picture once and lays the merchant, the item and the coins
on top (client/modules/game_npcshop).

Writes client/data/images/npcshop/counter.png, 512x208 (the scene at 2x).

Needs the client's Tibia.dat and Tibia.spr (7.72 format), which are not part
of this repository:

    python3 tools/generate-npcshop-counter.py --things path/to/client/data/things/772

The layout numbers below are mirrored in npcshop.otui. Requires Pillow.
"""
import argparse
import importlib.util
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location('scenes', Path(__file__).with_name('generate-charselect-scenes.py'))
scenes = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scenes)

FLOOR, WALL, COUNTER = 429, 1271, 2323
BLACKBOARD, TORCH, BARREL, CRATE, SACK = 2597, 2910, 2523, 2472, 2853
ORIGIN_X, ORIGIN_Y, FLOOR_Z = 1000, 1000, 7
# The merchant stands on tile (5, 1); the counter is the row below.
CROP = (16 * 32 + 16, 316, 24 * 32 + 16, 420)  # 256x104 inside the 40x22 tile render
ZOOM = 2


def build_shop():
    tiles = {}

    def put(x, y, *ids):
        tiles.setdefault((ORIGIN_X + x, ORIGIN_Y + y, FLOOR_Z), []).extend(ids)

    for x in range(-2, 13):
        put(x, 0, FLOOR, WALL)
        for y in (1, 2, 3):
            put(x, y, FLOOR)
        put(x, 2, COUNTER)
    for x in (2, 8):
        put(x, 0, BLACKBOARD)
    for x in (0, 5, 10):
        put(x, 0, TORCH)
    put(1, 1, BARREL)
    put(9, 1, CRATE)
    put(10, 1, SACK)
    return tiles


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--things', type=Path, required=True, help='folder with Tibia.dat and Tibia.spr (7.72)')
    parser.add_argument('--out', type=Path, default=ROOT / 'client/data/images/npcshop')
    args = parser.parse_args()

    items = scenes.load_items(args.things / 'Tibia.dat')
    sprites = scenes.Sprites(args.things / 'Tibia.spr')
    picture = scenes.render(build_shop(), items, sprites, ORIGIN_X + 5, ORIGIN_Y + 1, FLOOR_Z).crop(CROP)
    picture = picture.resize((picture.width * ZOOM, picture.height * ZOOM), Image.NEAREST)
    args.out.mkdir(parents=True, exist_ok=True)
    picture.save(args.out / 'counter.png', optimize=True)
    print('wrote', args.out / 'counter.png', picture.size)


if __name__ == '__main__':
    main()
