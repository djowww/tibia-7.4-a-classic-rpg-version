#!/usr/bin/env python3
"""Build the minimap marks every player starts with (data/minimap-markers.txt).

Positions come from the server data, so the file follows the map:

  stairs, ladders and rope spots that lead up   -> up arrow
  holes, stairs and grates that lead down       -> down arrow
  NPCs trading runes, wands or blank runes      -> bag
  NPCs trading weapons, armor or shields        -> sword
  NPCs trading bows, arrows, bolts or spears    -> spear
  NPCs with a bank account service              -> dollar sign
  town temples                                  -> cross
  quest chests                                  -> exclamation mark

Each line of the output is `x,y,z,icon,description`. The client reads it in
modules/gamelib/ui/uiminimap.lua and shows the marks without saving them, so
the marks a player creates stay in that player's own settings.

    python3 tools/generate-minimap-markers.py
"""
import argparse
import importlib.util
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Icon numbers of the client images /images/game/minimap/flagN.png.
ICON_QUEST, ICON_TEMPLE, ICON_AMMO, ICON_MELEE = 2, 5, 7, 8
ICON_MAGIC, ICON_BANK, ICON_UP, ICON_DOWN = 11, 13, 14, 15

# A tile holds one mark; when two things share a tile the first of these wins.
PRIORITY = [ICON_TEMPLE, ICON_BANK, ICON_MAGIC, ICON_MELEE, ICON_AMMO, ICON_QUEST, ICON_UP, ICON_DOWN]

BLANK_RUNE = 3147
MIN_MELEE_GOODS = 3
OTBM_ITEM, OTBM_TOWN = 6, 13
OTBM_ATTR_CHEST_QUEST = 28
# Sizes of the OTBM item attributes that come before the chest quest number.
OTBM_ATTR_SIZES = {3: 4, 4: 2, 5: 2, 8: 5, 9: 2, 10: 2, 12: 1, 14: 1, 15: 1, 16: 4, 17: 1,
                   18: 4, 20: 4, 21: 4, 22: 2, 23: 2, 24: 2, 25: 2, 26: 2, 27: 2, 28: 2,
                   33: 4, 34: 4, 35: 4, 36: 4, 37: 1, 38: 1}
OTBM_ATTR_STRINGS = {1, 2, 6, 7, 11, 13, 19, 30, 31, 32}


def lua_id_list(text, name):
    body = re.search(r"local\s+%s\s*=\s*\{(.*?)\}" % name, text, re.S)
    return {int(number) for number in re.findall(r"\d+", body.group(1))} if body else set()


def floor_change_items(root):
    """Item ids that take a player up or down, read from the scripts that do it."""
    up, down = set(), set()
    step = (root / "data/movements/scripts/others/floorchange.lua").read_text(encoding="latin-1")
    for item_id, z in re.findall(r"\[(\d+)\]\s*=\s*\{[^}]*z\s*=\s*(-?\d+)", step):
        (down if int(z) > 0 else up).add(int(item_id))
    use = (root / "data/actions/scripts/others/teleporters.lua").read_text(encoding="latin-1")
    up |= lua_id_list(use, "upstairs")
    down |= lua_id_list(use, "downstairs")
    rope = (root / "data/actions/scripts/others/rope.lua").read_text(encoding="latin-1")
    up |= lua_id_list(rope, "ropeSpots")
    return up, down - up


def item_flags(root):
    flags = {}
    text = (root / "data/items/items.srv").read_text(encoding="latin-1")
    for block in re.split(r"\n\s*\n", text):
        type_id = re.search(r"^TypeID\s*=\s*(\d+)", block, re.M)
        found = re.search(r"^Flags\s*=\s*\{([^}]*)\}", block, re.M)
        if type_id and found:
            flags[int(type_id.group(1))] = set(found.group(1).split(","))
    return flags


def npc_text(root, path, seen=None):
    """An NPC file with the generic files it includes."""
    seen = seen or set()
    if path in seen or not path.exists():
        return ""
    seen.add(path)
    text = path.read_text(encoding="latin-1")
    for include in re.findall(r'^\s*@"([^"]+)"', text, re.M):
        text += "\n" + npc_text(root, root / "data/npc" / include, seen)
    return text


def npc_marks(root, flags):
    marks = []
    for path in sorted((root / "data/npc").glob("*.npc")):
        own = path.read_text(encoding="latin-1")
        name = re.search(r'^Name\s*=\s*"([^"]+)"', own, re.M)
        home = re.search(r"^Home\s*=\s*\[(\d+),(\d+),(\d+)\]", own, re.M)
        if not name or not home:
            continue
        pos = tuple(int(part) for part in home.groups())
        if re.search(r'^\s*@"gen-bank\.ndb"', own, re.M):
            marks.append((pos, ICON_BANK, "Banco: " + name.group(1)))
        counts = {ICON_MAGIC: 0, ICON_MELEE: 0, ICON_AMMO: 0}
        for line in npc_text(root, path).splitlines():
            line = line.strip()
            # Trade lines, whether the NPC sells the item or buys it.
            if line.startswith("#") or "Price=" not in line:
                continue
            sold = re.search(r"\bType=(\d+)", line)
            if not sold:
                continue
            item = int(sold.group(1))
            kinds = flags.get(item, set())
            if item == BLANK_RUNE or kinds & {"Rune", "Wand"}:
                counts[ICON_MAGIC] += 1
            elif kinds & {"Distance", "Ammo"}:
                counts[ICON_AMMO] += 1
            elif kinds & {"Weapon", "Armor", "Shield"}:
                counts[ICON_MELEE] += 1
        labels = {ICON_MAGIC: "Loja de magia", ICON_MELEE: "Armas e armaduras", ICON_AMMO: "Arcos e flechas"}
        if counts[ICON_MELEE] < MIN_MELEE_GOODS:  # a general store with a knife is not a weapon shop
            counts[ICON_MELEE] = 0
        if any(counts.values()):
            # The kind of goods the NPC sells the most of decides the mark.
            icon = max(counts, key=lambda kind: (counts[kind], -PRIORITY.index(kind)))
            marks.append((pos, icon, "%s: %s" % (labels[icon], name.group(1))))
    return marks


def chest_quest(props):
    """Quest number of a map item, or None when it is not a quest chest."""
    offset = 2
    while offset < len(props):
        attr = props[offset]
        offset += 1
        if attr == 0:
            return None
        if attr in OTBM_ATTR_STRINGS:
            offset += 2 + struct.unpack_from("<H", props, offset)[0]
            continue
        if attr == OTBM_ATTR_CHEST_QUEST:
            return struct.unpack_from("<H", props, offset)[0]
        if attr not in OTBM_ATTR_SIZES:
            raise ValueError(f"unknown OTBM item attribute {attr}")
        offset += OTBM_ATTR_SIZES[attr]
    return None


def map_marks(root, up, down):
    """Stairs, holes, quest chests and temples of the map."""
    spec = importlib.util.spec_from_file_location("generate_minimap", ROOT / "tools/generate-minimap.py")
    minimap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(minimap)
    map_path = root / "data/world/map.otbm"
    marks, temples = [], {}
    # First pass for what read_map does not report: item attributes and towns.
    raw = map_path.read_bytes()
    stack, pos = [], 4
    while pos < len(raw):
        byte = raw[pos]
        pos += 1
        if byte == 0xFE:
            if stack:
                minimap.finish(stack[-1])
            parent = stack[-1] if stack else None
            node = {"kind": raw[pos], "props": bytearray(), "items": None, "tile": None,
                    "area": parent["area"] if parent else None,
                    "where": parent.get("where") if parent else None}
            stack.append(node)
            pos += 1
        elif byte == 0xFF:
            node = stack.pop()
            minimap.finish(node)
            props = bytes(node["props"])
            if node["kind"] in (5, 14):
                pass
            elif node["kind"] == OTBM_ITEM and node["where"] and chest_quest(props) is not None:
                marks.append((node["where"], ICON_QUEST, "Quest"))
            elif node["kind"] == OTBM_TOWN:
                size = struct.unpack_from("<H", props, 4)[0]
                town = props[6:6 + size].decode("latin-1")
                temples[struct.unpack_from("<HHB", props, 6 + size)] = "Templo de " + town
        else:
            if byte == 0xFD:
                byte = raw[pos]
                pos += 1
            stack[-1]["props"].append(byte)
            node = stack[-1]
            # A tile knows its position once its two offset bytes are read.
            if node["kind"] in (5, 14) and len(node["props"]) == 2 and node["area"]:
                node["where"] = (node["area"][0] + node["props"][0], node["area"][1] + node["props"][1], node["area"][2])

    for x, y, z, items in minimap.read_map(map_path):
        ids = set(items)
        # Towns left in the map without a temple tile get no mark.
        if (x, y, z) in temples:
            marks.append(((x, y, z), ICON_TEMPLE, temples[(x, y, z)]))
        if ids & up:
            marks.append(((x, y, z), ICON_UP, "Subida"))
        elif ids & down:
            marks.append(((x, y, z), ICON_DOWN, "Descida"))
    return marks


def build(root, out_path):
    up, down = floor_change_items(root)
    marks = map_marks(root, up, down) + npc_marks(root, item_flags(root))
    by_tile = {}
    for pos, icon, description in marks:
        current = by_tile.get(pos)
        if current is None or PRIORITY.index(icon) < PRIORITY.index(current[0]):
            by_tile[pos] = (icon, description)
    lines = ["# x,y,z,icon,description - generated by tools/generate-minimap-markers.py"]
    counts = {}
    for (x, y, z), (icon, description) in sorted(by_tile.items(), key=lambda entry: (entry[0][2], entry[0][1], entry[0][0])):
        lines.append("%d,%d,%d,%d,%s" % (x, y, z, icon, description))
        counts[icon] = counts.get(icon, 0) + 1
    Path(out_path).write_text("\n".join(lines) + "\n", encoding="ascii")
    return counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--out", type=Path, default=ROOT / "client/data/minimap-markers.txt")
    args = parser.parse_args()
    names = {ICON_UP: "subidas", ICON_DOWN: "descidas", ICON_MAGIC: "lojas de magia", ICON_MELEE: "armas e armaduras",
             ICON_AMMO: "arcos e flechas", ICON_BANK: "bancos", ICON_TEMPLE: "templos", ICON_QUEST: "quests"}
    result = build(args.root, args.out)
    for icon in PRIORITY:
        print("%-18s %d" % (names[icon], result.get(icon, 0)))
    print("total", sum(result.values()), "->", args.out)
