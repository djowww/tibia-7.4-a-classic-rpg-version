#!/usr/bin/env python3
"""Build the data of the in-game Game Wiki (client module game_wiki).

Everything comes from the server files, so the wiki follows the game:

  data/monster/*.xml      -> health, experience, summon cost, look and loot
  data/world/spawns.xml   -> where each monster lives and the hunting places
  data/world/map.otbm     -> town temples, used to name the places
  data/items/items.srv    -> item attributes
  data/npc/*.npc          -> which NPC sells or buys each item
  data/spells/spells.xml  -> names, charges and magic level of the runes

It writes monsters.lua, items.lua and hunts.lua into the client module and
keeps CATALOG_SIZE of data/lib/custom/antigasBestiary.lua equal to the number
of Bestiary entries.

    python3 tools/generate-game-wiki.py
"""
import argparse
import json
import math
import re
import struct
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CELL = 96            # size, in tiles, of the squares that group spawns into places
HUNT_CELL = 72       # hunting places are grouped per floor in smaller squares
SMALL_TOWN_REACH = 100  # towns without a region of their own only name what is next to them
SMALL_TOWNS = {"Isle of Solitude"}
BLANK_RUNE = 3147
MAX_SPOTS = 14       # places listed for one monster
MIN_HUNT_CREATURES = 8
GROUND_FLOOR = 7
FLUIDS = {10: "Mana Fluid", 11: "Life Fluid"}
VIAL = 2874
COMPASS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
TRAPS = {"flamethrower", "magicthrower", "plaguethrower", "shredderthrower", "deathslicer", "mimic", "illusion"}


def lua(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, dict):
        parts = ["%s = %s" % (key, lua(item, indent + 1)) for key, item in value.items() if item is not None]
        return "{" + ", ".join(parts) + "}"
    flat = all(not isinstance(item, (dict, list)) for item in value)
    if flat:
        return "{" + ", ".join(lua(item) for item in value) + "}"
    return "{\n" + "".join("%s\t%s,\n" % (pad, lua(item, indent + 1)) for item in value) + pad + "}"


def title(name):
    name = re.sub(r"^(an?|the) ", "", name.strip(), flags=re.I) if not name.startswith("The ") else name.strip()
    return " ".join(word if word in ("of", "the") and index else word[:1].upper() + word[1:]
                    for index, word in enumerate(name.split()))


def read_towns(root):
    raw = (root / "data/world/map.otbm").read_bytes()
    towns, start = [], 0
    while True:
        start = raw.find(b"\xfe\x0d", start)
        if start < 0:
            return towns
        chunk = raw[start + 2:start + 90]
        start += 2
        if len(chunk) < 12:
            continue
        size = struct.unpack_from("<H", chunk, 4)[0]
        name = chunk[6:6 + size]
        if 2 < size < 30 and len(chunk) >= 11 + size and all(32 <= char < 127 for char in name):
            x, y, z = struct.unpack_from("<HHB", chunk, 6 + size)
            towns.append((name.decode("ascii"), x, y, z))


class Places:
    def __init__(self, towns):
        self.towns = towns

    def town(self, x, y):
        near = [town for town in self.towns
                if town[0] not in SMALL_TOWNS or math.hypot(town[1] - x, town[2] - y) < SMALL_TOWN_REACH]
        return min(near, key=lambda town: (town[1] - x) ** 2 + (town[2] - y) ** 2)

    def region(self, x, y):
        town = self.town(x, y)
        dx, dy = x - town[1], y - town[2]
        if math.hypot(dx, dy) < 70:
            return town[0]
        return "%s of %s" % (COMPASS[int(((math.degrees(math.atan2(dy, dx)) + 382.5) % 360) // 45)].capitalize(), town[0])

    def name(self, x, y, z):
        area = self.region(x, y)
        if z < GROUND_FLOOR:
            area += ", floor +%d" % (GROUND_FLOOR - z)
        elif z > GROUND_FLOOR:
            area += ", floor -%d" % (z - GROUND_FLOOR)
        return area


def read_monsters(root):
    monsters = {}
    for path in sorted((root / "data/monster").glob("*.xml")):
        if path.name == "monsters.xml":
            continue
        node = ET.parse(path).getroot()
        if node.tag != "monster":
            continue
        flags = {key: value for flag in node.iter("flag") for key, value in flag.attrib.items()}
        look = node.find("look")
        health = node.find("health")
        ranged = 0
        for attack in node.iter("attack"):
            if attack.get("name") != "melee" and attack.get("max"):
                ranged = max(ranged, abs(int(attack.get("max"))))
        loot = []
        for item in node.iter("item"):
            loot.append((int(item.get("id")), int(item.get("chance", 0)), int(item.get("countmax", 1))))
        description = node.get("nameDescription", "")
        monsters[node.get("name").lower()] = {
            "name": title(node.get("name")),
            "unique": not re.match(r"an? ", description),
            "exp": int(node.get("experience", 0)),
            "manacost": int(node.get("manacost", 0)),
            "health": int(health.get("max", 0)) if health is not None else 0,
            "summonable": flags.get("summonable") == "1",
            "convinceable": flags.get("convinceable") == "1",
            "attackable": flags.get("attackable", "1") == "1",
            "hostile": flags.get("hostile", "1") == "1",
            "ranged": ranged,
            "look": {key: int(look.get(key, 0)) for key in ("type", "head", "body", "legs", "feet")} if look is not None else None,
            "loot": loot,
        }
    return monsters


def read_spawns(root):
    monsters, npcs = defaultdict(list), {}
    for spawn in ET.parse(root / "data/world/spawns.xml").getroot():
        cx, cy = int(spawn.get("centerx")), int(spawn.get("centery"))
        for child in spawn:
            pos = (cx + int(child.get("x")), cy + int(child.get("y")), int(child.get("z")))
            if child.tag == "monster":
                monsters[child.get("name").lower()].append(pos)
            elif child.tag == "npc":
                npcs[child.get("name").lower()] = pos
    return monsters, npcs


def read_items(root):
    items = {}
    text = (root / "data/items/items.srv").read_text(encoding="latin-1")
    for block in re.split(r"\n\s*\n", text):
        type_id = re.search(r"^TypeID\s*=\s*(\d+)", block, re.M)
        name = re.search(r'^Name\s*=\s*"([^"]*)"', block, re.M)
        if not type_id or not name:
            continue
        flags = re.search(r"^Flags\s*=\s*\{([^}]*)\}", block, re.M)
        attributes = re.search(r"^Attributes\s*=\s*\{([^}]*)\}", block, re.M)
        description = re.search(r'^Description\s*=\s*"([^"]*)"', block, re.M)
        attrs = {}
        for pair in (attributes.group(1).split(",") if attributes else []):
            if "=" in pair:
                key, value = pair.split("=", 1)
                attrs[key.strip()] = value.strip()
        items[int(type_id.group(1))] = {
            "name": name.group(1),
            "flags": set(part.strip() for part in flags.group(1).split(",")) if flags else set(),
            "attrs": attrs,
            "description": description.group(1) if description else None,
        }
    return items


def read_runes(root):
    runes = {}
    for rune in ET.parse(root / "data/spells/spells.xml").getroot().iter("rune"):
        runes[int(rune.get("id"))] = (rune.get("name"), rune.get("charges"), rune.get("maglv") or rune.get("lvl"))
    return runes


def npc_text(root, path, seen):
    if path in seen or not path.exists():
        return ""
    seen.add(path)
    text = path.read_text(encoding="latin-1")
    for include in re.findall(r'^\s*@"([^"]+)"', text, re.M):
        text += "\n" + npc_text(root, root / "data/npc" / include, seen)
    return text


def read_trades(root, spawned, places):
    """(item id, fluid) -> list of (kind, npc, town, price, amount)."""
    trades = defaultdict(set)
    for path in sorted((root / "data/npc").glob("*.npc")):
        own = path.read_text(encoding="latin-1")
        name = re.search(r'^Name\s*=\s*"([^"]+)"', own, re.M)
        if not name or name.group(1).lower() not in spawned:
            continue
        x, y, _ = spawned[name.group(1).lower()]
        town = places.town(x, y)[0]
        for line in npc_text(root, path, set()).splitlines():
            line = line.strip()
            if line.startswith("#") or "->" not in line:
                continue
            keys, action = line.split("->", 1)
            item = re.search(r"\bType=(\d+)", action)
            price = re.search(r"\bPrice=(\d+)\s*,", action)
            amount = re.search(r"\bAmount=(\d+)\s*,", action)
            if not item or not price or "%" in keys or "BUSY" in keys:
                continue
            fluid = re.search(r"\bData=(\d+)", action)
            kind = "buys" if '"sell"' in keys.lower() else "sells"
            key = (int(item.group(1)), int(fluid.group(1)) if fluid else 0)
            trades[key].add((kind, name.group(1), town, int(price.group(1)), int(amount.group(1)) if amount else 1))
    return trades


def rarity(chance):
    # Loot chances are out of 1000.
    if chance >= 200:
        return 4
    if chance >= 50:
        return 3
    if chance >= 10:
        return 2
    return 1


def category(item):
    flags, attrs = item["flags"], item["attrs"]
    slot = attrs.get("SlotType")
    if "Rune" in flags:
        return "Runes"
    if "Wand" in flags:
        return "Wands"
    if flags & {"Distance", "Ammo"}:
        return "Distance"
    if "Weapon" in flags:
        return "Weapons"
    if "Shield" in flags:
        return "Shields"
    if slot in ("RING", "NECKLACE"):
        return "Jewelry"
    if slot in ("HEAD", "BODY", "LEGS", "FEET") or "Armor" in flags:
        return "Armor"
    if "Nutrition" in attrs:
        return "Food"
    if "Container" in flags:
        return "Containers"
    return "Other"


SLOTS = {"HEAD": "Helmet", "BODY": "Armor", "LEGS": "Legs", "FEET": "Boots", "RING": "Ring",
         "NECKLACE": "Amulet", "BACKPACK": "Container"}
BOOSTS = [("SpeedBoost", "Speed"), ("SwordBoost", "Sword fighting"), ("AxeBoost", "Axe fighting"),
          ("ClubBoost", "Club fighting"), ("FistBoost", "Fist fighting"), ("DistanceBoost", "Distance fighting"),
          ("ShieldBoost", "Shielding"), ("MagicBoost", "Magic level")]
ABSORBS = [("AbsorbPhysical", "physical"), ("AbsorbFire", "fire"), ("Absorbfire", "fire"), ("AbsorbMagic", "magic"),
           ("AbsorbPoison", "poison"), ("AbsorbEnergy", "energy"), ("AbsorbManaDrain", "mana drain"),
           ("AbsorbLifeDrain", "life drain")]


def item_lines(item, items):
    """Attribute lines shown on an item page, as (label, value)."""
    attrs = dict(item["attrs"])
    worn = items.get(int(attrs["EquipTarget"])) if attrs.get("EquipTarget", "").isdigit() else None
    if worn:
        attrs.update({key: value for key, value in worn["attrs"].items() if key != "Weight"})
    lines = []
    kind = attrs.get("WeaponType")
    if kind:
        lines.append(("Type", kind.capitalize() + (", two-handed" if attrs.get("SlotType") == "TWOHANDED" else ", one-handed")))
    elif attrs.get("SlotType") in SLOTS:
        lines.append(("Type", SLOTS[attrs["SlotType"]]))
    elif attrs.get("SlotType") == "TWOHANDED":
        lines.append(("Type", "Two-handed"))
    for key, label in (("Attack", "Attack"), ("Defense", "Defense"), ("ArmorValue", "Armor"), ("Range", "Range")):
        if attrs.get(key, "0") not in ("0", ""):
            lines.append((label, attrs[key]))
    if "AmmoType" in attrs:
        lines.append(("Ammunition", attrs["AmmoType"].capitalize()))
    if "Hitchance" in attrs:
        lines.append(("Hit chance", attrs["Hitchance"] + "%"))
    for key, label in BOOSTS:
        if key in attrs:
            lines.append((label, "+" + attrs[key]))
    protection = ["%s %s%%" % (label, attrs[key]) for key, label in ABSORBS if key in attrs]
    if protection:
        lines.append(("Protection", ", ".join(dict.fromkeys(protection))))
    if "HealthGain" in attrs or "ManaGain" in attrs:
        lines.append(("Effect", "Faster regeneration"))
    if "Invisible" in attrs:
        lines.append(("Effect", "Invisibility"))
    if "ManaShield" in attrs:
        lines.append(("Effect", "Magic shield"))
    if "SuppressDrunk" in attrs:
        lines.append(("Effect", "Prevents drunkenness"))
    if attrs.get("TotalExpireTime", "").isdigit() and (worn or "Expire" in item["flags"]):
        seconds = int(attrs["TotalExpireTime"])
        lines.append(("Duration", "%d min" % (seconds // 60) if seconds >= 60 else "%d s" % seconds))
    if "TotalUses" in attrs:
        lines.append(("Charges", attrs["TotalUses"]))
    if "Nutrition" in attrs:
        lines.append(("Nutrition", attrs["Nutrition"]))
    if "Capacity" in attrs:
        lines.append(("Slots", attrs["Capacity"]))
    if attrs.get("Weight", "").isdigit():
        lines.append(("Weight", "%.2f oz" % (int(attrs["Weight"]) / 100)))
    return lines


def cell_of(pos):
    return (pos[0] // CELL, pos[1] // CELL, pos[2] > GROUND_FLOOR)


def center(positions):
    """A real spawn position close to the middle of the busiest floor."""
    floor = Counter(pos[2] for pos in positions).most_common(1)[0][0]
    same = [pos for pos in positions if pos[2] == floor]
    mx = sum(pos[0] for pos in same) / len(same)
    my = sum(pos[1] for pos in same) / len(same)
    return min(same, key=lambda pos: (pos[0] - mx) ** 2 + (pos[1] - my) ** 2)


def level_bands(monster, rook):
    if rook:
        return {"K": [1, 8], "P": [1, 8], "S": [1, 8], "D": [1, 8]}, None
    exp = monster["exp"]
    base = max(8, round(1.65 * math.sqrt(exp) - 2))
    top = round(base * 1.7 + 12)
    knight = base
    if monster["ranged"] >= 60 and exp > 250:
        knight = base + (20 if exp >= 1500 else 12)
    bands = {"K": [knight, top + (knight - base)], "P": [base, top], "S": [base, top], "D": [base, top]}
    party = [max(8, round(base * 0.75)), round(top * 1.3)] if exp >= 150 else None
    return bands, party


def build(root):
    towns = read_towns(root)
    places = Places(towns)
    monsters = read_monsters(root)
    spawns, npcs = read_spawns(root)
    items = read_items(root)
    retired_path = root / "data/items/retired-items.json"
    retired = {entry["id"] for entry in json.loads(retired_path.read_text(encoding="utf-8"))["ids"]} if retired_path.exists() else set()
    trades = read_trades(root, npcs, places)
    runes = read_runes(root)

    # --- Bestiary: every monster that has a spawn on the map.
    bestiary = []
    drops = defaultdict(dict)
    for key in sorted(spawns):
        monster = monsters.get(key)
        if not monster or key in TRAPS or not monster["attackable"] or not monster["look"] or monster["unique"]:
            continue
        cells = defaultdict(list)
        for pos in spawns[key]:
            cells[cell_of(pos)].append(pos)
        spots = []
        for positions in sorted(cells.values(), key=len, reverse=True)[:MAX_SPOTS]:
            x, y, z = center(positions)
            spots.append({"x": x, "y": y, "z": z, "n": len(positions), "area": places.name(x, y, z)})
        loot, seen = [], {}
        for item_id, chance, count in monster["loot"]:
            if item_id not in items:
                continue
            if item_id in seen:  # the same item listed twice (gold): keep the best chance, add the amounts
                seen[item_id]["max"] += count
                seen[item_id]["r"] = max(seen[item_id]["r"], rarity(chance))
                continue
            seen[item_id] = {"id": item_id, "name": title(items[item_id]["name"]), "r": rarity(chance), "max": count}
            loot.append(seen[item_id])
        for entry in loot:
            drops[entry["id"]][monster["name"]] = entry["r"]
        loot.sort(key=lambda entry: (-entry["r"], entry["name"]))
        bestiary.append({
            "name": monster["name"], "health": monster["health"], "experience": monster["exp"],
            "manacost": monster["manacost"] if monster["summonable"] or monster["convinceable"] else 0,
            "summon": monster["summonable"], "convince": monster["convinceable"],
            "look": monster["look"], "total": len(spawns[key]), "places": len(cells), "spots": spots, "loot": loot,
        })
    bestiary.sort(key=lambda entry: entry["name"])
    listed = {entry["name"].lower() for entry in bestiary}

    # --- Bosstiary (work in progress): the unique creatures, which nobody hunts a thousand times.
    bosses = [{"name": monster["name"], "health": monster["health"], "experience": monster["exp"], "look": monster["look"]}
              for key, monster in sorted(monsters.items())
              if monster["unique"] and monster["look"] and monster["exp"] >= 100
              and key not in TRAPS and "gamemaster" not in key]

    # --- Itempedia.
    by_name = {}
    for item_id in sorted(items):
        item = items[item_id]
        if "Take" not in item["flags"] or item_id in retired or "DeEquipTarget" in item["attrs"]:
            continue
        kind = category(item)
        if "Rune" in item["flags"] and item_id not in runes and item_id != BLANK_RUNE:
            continue  # a rune id no spell uses
        variants = [(item_id, 0)] if item_id != VIAL else [(VIAL, fluid) for fluid in FLUIDS]
        for key in variants:
            sources = trades.get(key, set())
            dropped = drops.get(item_id, {}) if not key[1] else {}
            if not sources and not dropped and kind in ("Other", "Containers", "Food"):
                continue
            name = FLUIDS[key[1]] if key[1] else title(item["name"])
            lines = item_lines(item, items)
            if item_id == BLANK_RUNE:
                name, kind = "Blank Rune", "Runes"
            elif item_id in runes:
                spell, charges, magic = runes[item_id]
                name = spell + " Rune"
                lines = [pair for pair in (("Charges", charges), ("Magic level", magic)) if pair[1]] + lines
            entry = by_name.get(name)
            if not entry:
                entry = by_name[name] = {"id": item_id, "fluid": key[1] or None, "name": name, "cat": kind,
                                         "desc": item["description"], "lines": lines,
                                         "drops": {}, "npc": set()}
            entry["drops"].update(dropped)
            entry["npc"] |= sources
    itempedia = []
    for name in sorted(by_name):
        entry = by_name[name]
        entry["lines"] = [[label, value] for label, value in entry["lines"]]
        entry["drops"] = [[monster, rare] for monster, rare in sorted(entry["drops"].items(), key=lambda pair: (-pair[1], pair[0]))]
        entry["npc"] = [list(trade) for trade in sorted(entry["npc"], key=lambda trade: (trade[0] != "sells", trade[3] if trade[0] == "sells" else -trade[3], trade[1]))]
        itempedia.append(entry)

    # --- Hunting Guide: squares of the map with enough hostile creatures.
    cells = defaultdict(lambda: defaultdict(list))
    for key, positions in spawns.items():
        monster = monsters.get(key)
        if monster and key in listed and monster["hostile"] and monster["exp"] >= 5:
            for pos in positions:
                cells[(pos[0] // HUNT_CELL, pos[1] // HUNT_CELL, pos[2])][key].append(pos)
    merged = {}
    for cell, found in cells.items():
        total = sum(len(positions) for positions in found.values())
        if total < MIN_HUNT_CREATURES:
            continue
        common = [key for key, positions in found.items() if len(positions) >= max(2, total * 0.12)]
        common = common or [max(found, key=lambda key: len(found[key]))]
        main = max(common, key=lambda key: monsters[key]["exp"])
        everything = [pos for positions in found.values() for pos in positions]
        x, y, z = center(found[main])
        # Floors of the same dungeon, and neighbouring squares, become one place.
        hunt = merged.setdefault((main, places.region(x, y), z > GROUND_FLOOR), {"main": main, "found": defaultdict(list), "best": 0})
        for key, positions in found.items():
            hunt["found"][key] += positions
        if len(found[main]) > hunt["best"]:
            hunt.update({"x": x, "y": y, "z": z, "best": len(found[main])})
    hunts = []
    for hunt in merged.values():
        monster = monsters[hunt["main"]]
        rook = places.town(hunt["x"], hunt["y"])[0] == "Rookgaard"
        bands, party = level_bands(monster, rook)
        ordered = sorted(hunt["found"].items(), key=lambda pair: -len(pair[1]))
        danger = [monsters[key]["name"] for key, positions in ordered
                  if monsters[key]["exp"] >= max(100, monster["exp"] * 2.5)]
        hunts.append({
            "name": monster["name"], "area": places.name(hunt["x"], hunt["y"], hunt["z"]), "x": hunt["x"], "y": hunt["y"], "z": hunt["z"],
            "exp": monster["exp"], "rook": rook or None, "K": bands["K"], "P": bands["P"], "S": bands["S"], "D": bands["D"],
            "party": party, "mon": [[monsters[key]["name"], len(positions)] for key, positions in ordered[:5]],
            "danger": danger[:3] or None,
        })
    hunts.sort(key=lambda hunt: (hunt["exp"], hunt["area"]))
    return bestiary, bosses, itempedia, hunts


def write(path, header, value):
    path.write_text("-- %s\n-- Generated by tools/generate-game-wiki.py. Do not edit by hand.\nreturn %s\n" % (header, lua(value)), encoding="ascii")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    bestiary, bosses, itempedia, hunts = build(args.root)
    out = args.root / "deploy/client-current/modules/game_wiki/data"
    out.mkdir(parents=True, exist_ok=True)
    write(out / "monsters.lua", "Bestiary and Bosstiary entries.", {"monsters": bestiary, "bosses": bosses})
    write(out / "items.lua", "Itempedia entries.", itempedia)
    write(out / "hunts.lua", "Hunting Guide places.", hunts)
    lib = args.root / "data/lib/custom/antigasBestiary.lua"
    text = lib.read_text(encoding="latin-1")
    lib.write_text(re.sub(r"CATALOG_SIZE = \d+", "CATALOG_SIZE = %d" % len(bestiary), text), encoding="latin-1", newline="")
    print("bestiary %d, bosses %d, items %d, hunts %d" % (len(bestiary), len(bosses), len(itempedia), len(hunts)))
