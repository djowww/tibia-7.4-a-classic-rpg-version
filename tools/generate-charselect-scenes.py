#!/usr/bin/env python3
"""Build the character screen sceneries of the client.

For every town of the map, draws the temple and its surroundings exactly as
the client would (same sprites, same floor rules) and writes one picture per
town to client/data/images/charselect/<town>.png. The temple tile is always
at tile (20, 11) of the 40x22 tile picture; characterlist.lua relies on that.

Needs the client's Tibia.dat and Tibia.spr (7.72 format), which are not part
of this repository:

    python3 tools/generate-charselect-scenes.py --things path/to/client/data/things/772

Run it again after the map around a temple changes. Requires Pillow.
"""
import argparse
import re
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT = 40, 22  # tiles
# Water variants that only exist on the server; the client draws plain water.
SERVER_ONLY_WATER = range(4615, 4621)
PLAIN_WATER = 4608

ATTR_GROUND, ATTR_BORDER, ATTR_BOTTOM, ATTR_TOP = 0, 1, 2, 3
ATTR_U16 = (0, 8, 9, 25, 28, 29, 32)  # ground speed, writable, elevation, minimap, lens help, cloth
ATTR_LIGHT, ATTR_DISPLACEMENT, ATTR_ELEVATION = 21, 24, 25


class Thing:
    __slots__ = ('attrs', 'disp', 'elevation', 'w', 'h', 'layers', 'px', 'py', 'pz', 'phases', 'sprites')


def load_items(path):
    data = path.read_bytes()
    item_count = struct.unpack_from('<H', data, 4)[0]
    offset = 12
    items = {}
    for item_id in range(100, item_count + 1):
        thing = Thing()
        thing.attrs, thing.disp, thing.elevation = set(), (0, 0), 0
        while True:
            attr = data[offset]
            offset += 1
            if attr == 0xFF:
                break
            thing.attrs.add(attr)
            if attr in ATTR_U16:
                if attr == ATTR_ELEVATION:
                    thing.elevation = struct.unpack_from('<H', data, offset)[0]
                offset += 2
            elif attr == ATTR_LIGHT:
                offset += 4
            elif attr == ATTR_DISPLACEMENT:
                thing.disp = struct.unpack_from('<2H', data, offset)
                offset += 4
            elif attr > 40:
                raise ValueError('unknown attribute %d in item %d' % (attr, item_id))
        thing.w, thing.h = data[offset], data[offset + 1]
        offset += 2
        if thing.w > 1 or thing.h > 1:
            offset += 1
        thing.layers, thing.px, thing.py, thing.pz, thing.phases = data[offset:offset + 5]
        offset += 5
        count = thing.w * thing.h * thing.layers * thing.px * thing.py * thing.pz * thing.phases
        thing.sprites = struct.unpack_from('<%dH' % count, data, offset)
        offset += 2 * count
        items[item_id] = thing
    for item_id in SERVER_ONLY_WATER:
        items[item_id] = items[PLAIN_WATER]
    return items


class Sprites:
    def __init__(self, path):
        self.data = path.read_bytes()
        self.count = struct.unpack_from('<H', self.data, 4)[0]
        self.cache = {}

    def get(self, sprite_id):
        image = self.cache.get(sprite_id)
        if image is not None:
            return image
        pixels = bytearray(32 * 32 * 4)
        if 0 < sprite_id <= self.count:
            address = struct.unpack_from('<I', self.data, 6 + (sprite_id - 1) * 4)[0]
            if address:
                offset = address + 3
                end = offset + 2 + struct.unpack_from('<H', self.data, offset)[0]
                offset += 2
                pos = 0
                while offset < end:
                    transparent, colored = struct.unpack_from('<2H', self.data, offset)
                    offset += 4
                    pos += transparent
                    for _ in range(colored):
                        pixels[pos * 4:pos * 4 + 3] = self.data[offset:offset + 3]
                        pixels[pos * 4 + 3] = 255
                        offset += 3
                        pos += 1
        image = Image.frombytes('RGBA', (32, 32), bytes(pixels))
        self.cache[sprite_id] = image
        return image


def load_map(path):
    """Returns ({(x, y, z): [item ids]}, [(town id, name, x, y, z)])."""
    data = path.read_bytes()
    tiles, towns = {}, []
    stack = []
    size = len(data)
    i = 4

    def finish(node, parent):
        kind, props = node[0], bytes(node[1])
        if kind in (5, 14):  # tile, house tile
            ax, ay, az = struct.unpack_from('<HHB', bytes(parent[1]), 0)
            offset = 6 if kind == 14 else 2
            ids = []
            while offset < len(props):
                attr = props[offset]
                offset += 1
                if attr == 3:
                    offset += 4
                elif attr == 9:
                    ids.append(struct.unpack_from('<H', props, offset)[0])
                    offset += 2
                else:
                    break
            tiles[(ax + props[0], ay + props[1], az)] = ids + node[2]
        elif kind == 6 and parent and parent[0] in (5, 14):  # item on a tile
            parent[2].append(struct.unpack_from('<H', props, 0)[0])
        elif kind == 13:  # town
            town_id, length = struct.unpack_from('<IH', props, 0)
            name = props[6:6 + length].decode('latin-1')
            towns.append((town_id, name) + struct.unpack_from('<HHB', props, 6 + length))

    while i < size:
        byte = data[i]
        if byte == 0xFE:
            stack.append([data[i + 1], bytearray(), []])
            i += 2
        elif byte == 0xFF:
            node = stack.pop()
            finish(node, stack[-1] if stack else None)
            i += 1
        elif byte == 0xFD:
            stack[-1][1].append(data[i + 1])
            i += 2
        else:
            j = i
            while j < size and data[j] < 0xFD:
                j += 1
            stack[-1][1] += data[i:j]
            i = j
    return tiles, towns


def draw_priority(thing):
    for priority, attr in enumerate((ATTR_GROUND, ATTR_BORDER, ATTR_BOTTOM)):
        if attr in thing.attrs:
            return priority
    return 4 if ATTR_TOP in thing.attrs else 3


def has_ground(tiles, items, pos):
    return any(i in items and ATTR_GROUND in items[i].attrs for i in tiles.get(pos, ()))


def first_visible_floor(tiles, items, x, y, z):
    """Same idea as the client: floors that cover the character are hidden."""
    lowest = 0 if z <= 7 else max(z - 2, 8)
    first = lowest
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for up in range(1, z - lowest + 1):
                if has_ground(tiles, items, (x + dx, y + dy, z - up)) or \
                        has_ground(tiles, items, (x + dx + up, y + dy + up, z - up)):
                    first = max(first, z - up + 1)
                    break
    return first


def render(tiles, items, sprites, x, y, z):
    first = first_visible_floor(tiles, items, x, y, z)
    base = 7 if z <= 7 else z  # above ground the client also draws the floors below
    cx, cy = x - (base - z), y - (base - z)
    x0, y0 = cx - WIDTH // 2, cy - HEIGHT // 2
    image = Image.new('RGBA', (WIDTH * 32, HEIGHT * 32), (0, 0, 0, 255))
    for floor in range(base, first - 1, -1):
        shift = base - floor
        for ty in range(y0 + shift - 1, y0 + HEIGHT + shift + 3):
            for tx in range(x0 + shift - 1, x0 + WIDTH + shift + 3):
                things = sorted((items[i] for i in tiles.get((tx, ty, floor), ()) if i in items), key=draw_priority)
                elevation = 0
                for thing in things:
                    for layer in range(thing.layers):
                        for h in range(thing.h):
                            for w in range(thing.w):
                                index = ((((tz_index(thing, tx, ty, floor)) * thing.layers + layer) * thing.h + h) * thing.w + w)
                                sprite = sprites.get(thing.sprites[index])
                                sx = (tx - shift - x0 - w) * 32 - thing.disp[0] - elevation
                                sy = (ty - shift - y0 - h) * 32 - thing.disp[1] - elevation
                                paste(image, sprite, sx, sy)
                    elevation = min(24, elevation + thing.elevation)
    return image.convert('RGB')


def tz_index(thing, x, y, z):
    return ((z % thing.pz) * thing.py + y % thing.py) * thing.px + x % thing.px


def paste(image, sprite, sx, sy):
    left, top = max(0, -sx), max(0, -sy)
    right, bottom = min(32, image.width - sx), min(32, image.height - sy)
    if right > left and bottom > top:
        image.alpha_composite(sprite.crop((left, top, right, bottom)), (sx + left, sy + top))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--things', required=True, type=Path, help='folder with Tibia.dat and Tibia.spr (7.72)')
    parser.add_argument('--map', type=Path, default=ROOT / 'data/world/map.otbm')
    parser.add_argument('--out', type=Path, default=ROOT / 'client/data/images/charselect')
    args = parser.parse_args()

    items = load_items(args.things / 'Tibia.dat')
    sprites = Sprites(args.things / 'Tibia.spr')
    tiles, towns = load_map(args.map)
    args.out.mkdir(parents=True, exist_ok=True)
    for _town_id, name, x, y, z in towns:
        slug = re.sub('[^a-z]', '', name.lower())
        render(tiles, items, sprites, x, y, z).save(args.out / (slug + '.png'), optimize=True)
        print(name, (x, y, z), '->', slug + '.png')


if __name__ == '__main__':
    main()
