#!/usr/bin/env python3
"""Build the images of the loading screen (client_entergame, "Nightfall Passage").

Writes to client/data/images/charselect/fx/:
  night.png     dark blue night with a stepped round hole (shown at 2x the window, centred on the hero)
  glow.png      warm stepped torch glow around the hero (shown at the window size)
  iris.png      black square with a stepped round hole (the iris that closes and opens)
  teleport.png  the teleport magic effect of the client, 8 frames of 32x32 side by side

Needs the client's Tibia.dat and Tibia.spr (7.72) for the teleport effect:

    python3 tools/generate-loading-images.py --things path/to/client/data/things/772

With --paths it also prints the walk of each town for characterlist.lua
(WALK_PATHS): up to 7 steps out of the temple on walkable tiles, preferring
to walk towards the bottom of the screen.

Requires Pillow. Uses the readers of tools/generate-charselect-scenes.py.
"""
import argparse
import collections
import importlib.util
import math
import re
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TELEPORT_EFFECT = 11


def scenes_module():
    spec = importlib.util.spec_from_file_location('scenes', ROOT / 'tools/generate-charselect-scenes.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def radial(w, h, rgb, r0, r1, amax, steps, invert=False, canvas=None):
    """Stepped radial alpha, like the light of the game. Drawn small and shown
    pixelated. With canvas=(cw, ch) the picture is centred on a bigger canvas
    and the outside keeps the edge value."""
    cw, ch = canvas or (w, h)
    image = Image.new('RGBA', (cw, ch))
    pixels = image.load()
    for y in range(ch):
        for x in range(cw):
            r = math.hypot(x + .5 - cw / 2, y + .5 - ch / 2)
            k = min(1, max(0, (r - r0) / (r1 - r0)))
            k = k * k * (3 - 2 * k)
            if invert:
                k = 1 - k
            k = round(k * steps) / steps
            pixels[x, y] = rgb + (int(255 * amax * k),)
    return image


def iris(n=320):
    image = Image.new('RGBA', (n, n))
    pixels = image.load()
    for y in range(n):
        for x in range(n):
            r = math.hypot(x + .5 - n / 2, y + .5 - n / 2) / (n / 2)
            pixels[x, y] = (0, 0, 0, 0 if r < .80 else (90 if r < .86 else (170 if r < .92 else 255)))
    return image


def teleport(things):
    scenes = scenes_module()
    data = (things / 'Tibia.dat').read_bytes()
    sprites = scenes.Sprites(things / 'Tibia.spr')
    item_count, outfit_count, effect_count, missile_count = struct.unpack_from('<4H', data, 4)
    offset = 12
    for index in range((item_count - 99) + outfit_count + TELEPORT_EFFECT):
        while True:
            attr = data[offset]
            offset += 1
            if attr == 0xFF:
                break
            if attr in scenes.ATTR_U16:
                offset += 2
            elif attr in (scenes.ATTR_LIGHT, scenes.ATTR_DISPLACEMENT):
                offset += 4
        w, h = data[offset], data[offset + 1]
        offset += 2
        if w > 1 or h > 1:
            offset += 1
        layers, px, py, pz, phases = data[offset:offset + 5]
        offset += 5
        count = w * h * layers * px * py * pz * phases
        ids = struct.unpack_from('<%dH' % count, data, offset)
        offset += 2 * count
    # the last thing read is the teleport effect (1x1, one layer)
    strip = Image.new('RGBA', (32 * phases, 32))
    for phase in range(phases):
        strip.alpha_composite(sprites.get(ids[phase * px * py * pz * layers]), (phase * 32, 0))
    return strip


STEPS = {'N': (0, -1), 'E': (1, 0), 'S': (0, 1), 'W': (-1, 0)}
ATTR_NOT_WALKABLE, ATTR_FLOOR_CHANGE = 12, 23


def walk_paths(things, map_path, max_steps=7):
    scenes = scenes_module()
    items = scenes.load_items(things / 'Tibia.dat')
    tiles, towns = scenes.load_map(map_path)

    def walkable(pos):
        found = [items[i] for i in tiles.get(pos, ()) if i in items]
        return any(scenes.ATTR_GROUND in t.attrs for t in found) and \
            not any(ATTR_NOT_WALKABLE in t.attrs or ATTR_FLOOR_CHANGE in t.attrs for t in found)

    def distances(start, x, y, limit):
        dist, queue = {start: 0}, collections.deque([start])
        while queue:
            pos = queue.popleft()
            if dist[pos] >= limit:
                continue
            for dx, dy in STEPS.values():
                nxt = (pos[0] + dx, pos[1] + dy, pos[2])
                # stay where the 40x22 scenery has room for the camera
                if nxt not in dist and abs(nxt[0] - x) <= 12 and abs(nxt[1] - y) <= 5 and walkable(nxt):
                    dist[nxt] = dist[pos] + 1
                    queue.append(nxt)
        return dist

    paths = {}
    for _town_id, name, x, y, z in towns:
        slug = re.sub('[^a-z]', '', name.lower())
        dist = distances((x, y, z), x, y, max_steps)
        goal = max(dist, key=lambda p: (dist[p], math.hypot(p[0] - x, p[1] - y) + 1.2 * (p[1] - y)))
        back = distances(goal, x, y, 99)
        pos, path, last = (x, y, z), '', None
        while pos != goal:
            options = [(key, (pos[0] + dx, pos[1] + dy, z)) for key, (dx, dy) in STEPS.items()]
            options = [o for o in options if back.get(o[1]) == back[pos] - 1]
            options.sort(key=lambda o: o[0] != last)  # keep going straight when possible
            last, pos = options[0]
            path += last
        paths[slug] = path
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--things', required=True, type=Path, help='folder with Tibia.dat and Tibia.spr (7.72)')
    parser.add_argument('--out', type=Path, default=ROOT / 'client/data/images/charselect/fx')
    parser.add_argument('--map', type=Path, default=ROOT / 'data/world/map.otbm')
    parser.add_argument('--paths', action='store_true', help='also print WALK_PATHS for characterlist.lua')
    args = parser.parse_args()
    if args.paths:
        paths = walk_paths(args.things, args.map)
        print('local WALK_PATHS = {')
        for slug in sorted(paths):
            print("  %s = '%s'," % (slug, paths[slug]))
        print('}')
    args.out.mkdir(parents=True, exist_ok=True)
    radial(320, 200, (6, 8, 26), 24, 112, 0.80, 9, canvas=(640, 400)).save(args.out / 'night.png', optimize=True)
    radial(320, 200, (255, 168, 72), 6, 58, 0.17, 5, invert=True).save(args.out / 'glow.png', optimize=True)
    iris().save(args.out / 'iris.png', optimize=True)
    teleport(args.things).save(args.out / 'teleport.png', optimize=True)
    print('written to', args.out)


if __name__ == '__main__':
    main()
