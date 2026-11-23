#!/usr/bin/env python3
"""Build a fully explored OTClient minimap (.otmm) from the server map.

The client loads data/minimap.otmm before the player's own minimap, so shipping
this file makes every character start with the whole map revealed.

Each tile gets the colour, walkability and ground speed the client itself would
store after seeing it, using the item attributes of the client's Tibia.dat.

    python3 tools/generate-minimap.py --dat path/to/Tibia.dat --out minimap.otmm
"""
import argparse
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BLOCK = 64
TILE_SEEN, TILE_NOT_PATHABLE, TILE_NOT_WALKABLE = 1, 2, 4
NO_COLOR = 255
OTMM_SIGNATURE = 0x4D4D544F
# Speed byte the client stores for a tile with no ground item or a ground
# that has no speed of its own.
NO_GROUND_SPEED = 15

# Tibia.dat attributes for clients 7.55 to 7.72.
ATTR_GROUND, ATTR_BORDER, ATTR_BOTTOM, ATTR_TOP = 0, 1, 2, 3
ATTR_NOT_WALKABLE, ATTR_NOT_PATHABLE, ATTR_MINIMAP_COLOR = 12, 15, 28
ATTR_PAYLOAD = {0: 2, 8: 2, 9: 2, 21: 4, 24: 4, 25: 2, 28: 2, 29: 2}
ATTR_LAST = 31


class Item:
    __slots__ = ("order", "speed", "color", "not_walkable", "not_pathable")

    def __init__(self):
        self.order = None  # 0 ground, 1 border, 2 bottom, 3 top, None otherwise
        self.speed = 0
        self.color = 0
        self.not_walkable = False
        self.not_pathable = False


def load_dat(path):
    """Read the item attributes the minimap depends on. Client ids start at 100."""
    data = Path(path).read_bytes()
    count = struct.unpack_from("<H", data, 4)[0]
    offset, items = 12, {}
    for client_id in range(100, count + 1):
        item = Item()
        while True:
            attr = data[offset]
            offset += 1
            if attr == 0xFF:
                break
            if attr > ATTR_LAST:
                raise ValueError(f"unknown attribute {attr} on item {client_id}; this reader supports the 7.55-7.72 Tibia.dat")
            size = ATTR_PAYLOAD.get(attr, 0)
            if attr == ATTR_GROUND:
                item.order, item.speed = 0, struct.unpack_from("<H", data, offset)[0]
            elif attr == ATTR_BORDER and item.order is None:
                item.order = 1
            elif attr == ATTR_BOTTOM and item.order is None:
                item.order = 2
            elif attr == ATTR_TOP and item.order is None:
                item.order = 3
            elif attr == ATTR_NOT_WALKABLE:
                item.not_walkable = True
            elif attr == ATTR_NOT_PATHABLE:
                item.not_pathable = True
            elif attr == ATTR_MINIMAP_COLOR:
                item.color = struct.unpack_from("<H", data, offset)[0] & 0xFF
            offset += size
        width, height = data[offset], data[offset + 1]
        offset += 2
        if width > 1 or height > 1:
            offset += 1
        layers, pattern_x, pattern_y, pattern_z, phases = data[offset:offset + 5]
        offset += 5 + 2 * width * height * layers * pattern_x * pattern_y * pattern_z * phases
        items[client_id] = item
    return items


def load_disguises(path):
    """Server ids the client never sees: items sent as their DisguiseTarget."""
    text = Path(path).read_text(encoding="latin-1")
    disguises = {}
    for block in re.split(r"\n\s*\n", text):
        type_id = re.search(r"^TypeID\s*=\s*(\d+)", block, re.M)
        target = re.search(r"DisguiseTarget=(\d+)", block)
        if type_id and target and re.search(r"^Flags\s*=\s*\{[^}]*\bDisguise\b", block, re.M):
            disguises[int(type_id.group(1))] = int(target.group(1))
    return disguises


def read_map(path):
    """Yield (x, y, z, [item ids bottom to top]) for every tile of an OTBM map."""
    raw = Path(path).read_bytes()
    # Node stream: 0xFE opens a node, 0xFF closes it, 0xFD escapes the next byte.
    stack, pos, size = [], 4, len(raw)
    while pos < size:
        byte = raw[pos]
        pos += 1
        if byte == 0xFE:
            node = {"kind": raw[pos], "props": bytearray(), "area": None, "tile": None, "items": None}
            if stack:
                parent = stack[-1]
                finish(parent)
                node["area"] = parent["area"]
                node["tile"] = parent["tile"] if parent["kind"] in (5, 14) else None
                node["depth"] = parent.get("depth", 0) + (1 if parent["kind"] == 6 else 0)
            stack.append(node)
            pos += 1
        elif byte == 0xFF:
            node = stack.pop()
            finish(node)
            if node["kind"] in (5, 14):
                yield node["x"], node["y"], node["z"], node["items"]
            elif node["kind"] == 6 and node["tile"] is not None and node.get("depth", 0) == 0:
                node["tile"].append(struct.unpack_from("<H", node["props"])[0])
        else:
            if byte == 0xFD:
                byte = raw[pos]
                pos += 1
            stack[-1]["props"].append(byte)
    if stack:
        raise ValueError("truncated OTBM map")


def finish(node):
    """Decode a node's own properties once, before its children are read."""
    if "done" in node:
        return
    node["done"] = True
    props, kind = node["props"], node["kind"]
    if kind == 4:  # tile area: base position
        node["area"] = struct.unpack_from("<HHB", props)
    elif kind in (5, 14):  # tile / house tile
        base_x, base_y, node["z"] = node["area"]
        node["x"], node["y"] = base_x + props[0], base_y + props[1]
        node["items"] = node["tile"] = []
        offset = 6 if kind == 14 else 2  # house tiles carry a house id
        while offset < len(props):
            attr = props[offset]
            offset += 1
            if attr == 3:  # tile flags
                offset += 4
            elif attr == 9:  # ground item stored inline
                node["items"].append(struct.unpack_from("<H", props, offset)[0])
                offset += 2
            else:
                raise ValueError(f"unknown OTBM tile attribute {attr}")


def minimap_tile(item_ids, items):
    """Mirror the client: colour of the topmost ground-layer item, walk flags, speed."""
    flags, color, speed, has_ground, layers = TILE_SEEN, NO_COLOR, NO_GROUND_SPEED, False, []
    for item_id in item_ids:
        item = items.get(item_id)
        if item is None:
            continue
        if item.not_walkable:
            flags |= TILE_NOT_WALKABLE
        if item.not_pathable:
            flags |= TILE_NOT_PATHABLE
        if item.order == 0 and not has_ground:
            has_ground = True
            if item.speed:  # grounds without a speed (mountains, walls) keep the default
                speed = min(-(-item.speed // 10), 255)
        if item.order is not None and item.color:
            layers.append((item.order, item.color))
    if layers:
        # Stable sort: among items of the same layer the later one is on top.
        color = sorted(layers, key=lambda layer: layer[0])[-1][1]
    if not has_ground:
        flags |= TILE_NOT_WALKABLE
    return flags, color, speed


def build(map_path, dat_path, srv_path, out_path):
    items = load_dat(dat_path)
    disguises = load_disguises(srv_path)
    blocks, tiles = {}, 0
    empty = bytes((0, NO_COLOR, 10)) * (BLOCK * BLOCK)
    for x, y, z, item_ids in read_map(map_path):
        key = (x - x % BLOCK, y - y % BLOCK, z)
        block = blocks.get(key)
        if block is None:
            block = blocks[key] = bytearray(empty)
        index = ((y % BLOCK) * BLOCK + (x % BLOCK)) * 3
        block[index:index + 3] = bytes(minimap_tile([disguises.get(i, i) for i in item_ids], items))
        tiles += 1
    description = b"OTMM 1.0"
    start = 12 + 2 + len(description)  # blocks begin right after the header
    out = bytearray(struct.pack("<IHHI", OTMM_SIGNATURE, start, 1, 0))
    out += struct.pack("<H", len(description)) + description
    for (x, y, z), block in sorted(blocks.items(), key=lambda entry: (entry[0][2], entry[0][1], entry[0][0])):
        packed = zlib.compress(bytes(block))
        out += struct.pack("<HHBH", x, y, z, len(packed)) + packed
    out += struct.pack("<HHB", 65535, 65535, 255)
    Path(out_path).write_bytes(out)
    return tiles, len(blocks), len(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--map", type=Path, default=ROOT / "data/world/map.otbm")
    parser.add_argument("--dat", type=Path, required=True, help="Tibia.dat of the 7.72 client (data/things/772/Tibia.dat)")
    parser.add_argument("--items", type=Path, default=ROOT / "data/items/items.srv")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    tiles, blocks, size = build(args.map, args.dat, args.items, args.out)
    print(f"{tiles} tiles in {blocks} blocks, {size} bytes -> {args.out}")
