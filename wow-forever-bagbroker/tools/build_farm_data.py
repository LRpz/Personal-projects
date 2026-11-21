#!/usr/bin/env python3
"""Builds BagBroker/FarmData.lua from public databases (offline, data only).

Sources
  * CMaNGOS Classic-DB (GPLv3): creature loot, reference loot, skinning loot, gathering node loot,
    money drops, item vendor prices and qualities (vanilla 1.12 data).
  * QuestieDB, Forever flavour (GPLv3): creature names, levels, ranks, hostility and spawn
    coordinates on Forever maps, gathering node spawns, areaID -> uiMapID mapping and dungeon
    areas. Its correction layers are applied in QuestieDB's order: raw data, generated
    delta-base (Wowhead Forever snapshot), player traces, authored fixes.

Nothing downloaded is executed: SQL dumps and Lua data files are parsed as text.

Usage
  python3 tools/build_farm_data.py --cache tools/.cache --out BagBroker/FarmData.lua
"""
import argparse
import collections
import datetime
import gzip
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lua_data  # noqa: E402

CLASSICDB_URL = "https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
QDB = "https://raw.githubusercontent.com/Questie/QuestieDB/master/"
QDB_FILES = {
    "foreverNpcDB.lua": "data/Forever/foreverNpcDB.lua",
    "foreverObjectDB.lua": "data/Forever/foreverObjectDB.lua",
    "foreverBaseNpc.lua": "src/corrections/Forever/generated/foreverBaseNpc.lua",
    "foreverNpcTraces.lua": "src/corrections/Forever/traces/foreverNpcTraces.lua",
    "foreverNPCFixes.lua": "src/corrections/Forever/foreverNPCFixes.lua",
    "foreverBaseObject.lua": "src/corrections/Forever/generated/foreverBaseObject.lua",
    "foreverObjectTraces.lua": "src/corrections/Forever/traces/foreverObjectTraces.lua",
    "foreverObjectFixes.lua": "src/corrections/Forever/foreverObjectFixes.lua",
    "areaIdToUiMapId.lua": "support/Forever/Zones/areaIdToUiMapId.lua",
    "dungeons.lua": "support/Forever/Zones/dungeons.lua",
    "zones_enum.lua": "src/corrections/enum/zones.lua",
    "npcs_enum.lua": "src/corrections/enum/npcs.lua",
}
GRID_W, GRID_H = 60, 40

# Required gathering skill per node name (vanilla values).
NODE_SKILLS = {
    "Copper Vein": ("mining", 1), "Tin Vein": ("mining", 65), "Incendicite Mineral Vein": ("mining", 65),
    "Silver Vein": ("mining", 75), "Ooze Covered Silver Vein": ("mining", 75),
    "Lesser Bloodstone Deposit": ("mining", 75), "Iron Deposit": ("mining", 125),
    "Indurium Mineral Vein": ("mining", 150), "Gold Vein": ("mining", 155), "Ooze Covered Gold Vein": ("mining", 155),
    "Mithril Deposit": ("mining", 175), "Ooze Covered Mithril Deposit": ("mining", 175),
    "Truesilver Deposit": ("mining", 230), "Ooze Covered Truesilver Deposit": ("mining", 230),
    "Dark Iron Deposit": ("mining", 230), "Small Thorium Vein": ("mining", 245),
    "Ooze Covered Thorium Vein": ("mining", 245), "Rich Thorium Vein": ("mining", 275),
    "Ooze Covered Rich Thorium Vein": ("mining", 275), "Hakkari Thorium Vein": ("mining", 275),
    "Peacebloom": ("herbalism", 1), "Silverleaf": ("herbalism", 1), "Earthroot": ("herbalism", 15),
    "Mageroyal": ("herbalism", 50), "Briarthorn": ("herbalism", 70), "Stranglekelp": ("herbalism", 85),
    "Bruiseweed": ("herbalism", 100), "Wild Steelbloom": ("herbalism", 115), "Grave Moss": ("herbalism", 120),
    "Kingsblood": ("herbalism", 125), "Liferoot": ("herbalism", 150), "Fadeleaf": ("herbalism", 160),
    "Goldthorn": ("herbalism", 170), "Khadgar's Whisker": ("herbalism", 185), "Wintersbite": ("herbalism", 195),
    "Firebloom": ("herbalism", 205), "Purple Lotus": ("herbalism", 210), "Arthas' Tears": ("herbalism", 220),
    "Sungrass": ("herbalism", 230), "Blindweed": ("herbalism", 235), "Ghost Mushroom": ("herbalism", 245),
    "Gromsblood": ("herbalism", 250), "Golden Sansam": ("herbalism", 260), "Dreamfoil": ("herbalism", 270),
    "Mountain Silversage": ("herbalism", 280), "Plaguebloom": ("herbalism", 285), "Icecap": ("herbalism", 290),
    "Black Lotus": ("herbalism", 300),
}

PLACEHOLDER = re.compile(r"\(Only GM|\[DNT\]|\[PH\]|^Waypoint\b|^Trigger\b|Invisible|\bDND\b", re.I)
MIN_DIRECT_QTY = 0.001   # direct drops below 0.1% per kill are folded into a vendor-value remainder
MIN_REF_QTY = 0.00002
NAME_MIN_CHANCE = 0.005  # item names are shipped for drops of at least 0.5%


def log(msg):
    print(msg, file=sys.stderr)


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    log("downloading " + url)
    subprocess.run(["curl", "-sSfL", "--max-time", "600", "-o", path, url], check=True)


# ---------------------------------------------------------------------------
# SQL (CMaNGOS)
# ---------------------------------------------------------------------------
_SQL_TOKEN = re.compile(r"'(?:[^'\\]|\\.|'')*'|NULL|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[(),;]")


def _sql_value(tok):
    if tok == "NULL":
        return None
    if tok[0] == "'":
        return re.sub(r"\\(.)", r"\1", tok[1:-1].replace("''", "'"))
    return float(tok) if any(c in tok for c in ".eE") else int(tok)


def sql_rows(sql, table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\)" % table, sql, re.S)
    cols = re.findall(r"^\s*`(\w+)`", m.group(1), re.M)
    rows = []
    for ins in re.finditer(r"INSERT INTO `%s` VALUES\s*" % table, sql):
        row, depth = None, 0
        for tm in _SQL_TOKEN.finditer(sql, ins.end()):
            tok = tm.group(0)
            if tok == "(":
                depth += 1
                row = []
            elif tok == ")":
                depth -= 1
                rows.append(dict(zip(cols, row)))
            elif tok == ",":
                continue
            elif tok == ";":
                if depth == 0:
                    break
            else:
                row.append(_sql_value(tok))
    return rows


def expand_loot(rows):
    """Expected loot of one template: ({item: [chance, qty]}, {refId: rolls})."""
    items = collections.defaultdict(lambda: [0.0, 0.0])
    refs = collections.defaultdict(float)
    groups = collections.defaultdict(list)

    def process(r, p):
        if p <= 0:
            return
        if r["mincountOrRef"] < 0:
            refs[-r["mincountOrRef"]] += p * max(1, r["maxcount"])
        else:
            avg = (max(1, r["mincountOrRef"]) + max(1, r["maxcount"])) / 2.0
            e = items[r["item"]]
            e[0] = min(1.0, e[0] + p)
            e[1] += p * avg

    for r in rows:
        chance = r["ChanceOrQuestChance"]
        if chance < 0:
            continue  # quest-only drops
        if r["groupid"] == 0:
            process(r, chance / 100.0)
        else:
            groups[r["groupid"]].append(r)
    for group in groups.values():
        explicit = [r for r in group if r["ChanceOrQuestChance"] > 0]
        equal = [r for r in group if r["ChanceOrQuestChance"] == 0]
        total = sum(r["ChanceOrQuestChance"] for r in explicit)
        scale = 100.0 / total if total > 100 else 1.0
        for r in explicit:
            process(r, r["ChanceOrQuestChance"] * scale / 100.0)
        rest = max(0.0, 100.0 - total) / 100.0
        for r in equal:
            process(r, rest / len(equal))
    return items, refs


def flatten_ref(ref_id, ref_rows, memo, depth=0):
    """Expected items per roll of a reference template, nested references flattened."""
    if ref_id in memo:
        return memo[ref_id]
    memo[ref_id] = {}
    items, refs = expand_loot(ref_rows.get(ref_id, []))
    flat = collections.defaultdict(float)
    for item, (_, qty) in items.items():
        flat[item] += qty
    if depth < 4:
        for sub, rolls in refs.items():
            for item, qty in flatten_ref(sub, ref_rows, memo, depth + 1).items():
                flat[item] += rolls * qty
    memo[ref_id] = dict(flat)
    return memo[ref_id]


# ---------------------------------------------------------------------------
# QuestieDB (Forever)
# ---------------------------------------------------------------------------
def load_questiedb(cache):
    def read(name):
        with open(os.path.join(cache, name), encoding="utf-8") as f:
            return f.read()

    zones = lua_data.find_assigned_table(read("zones_enum.lua"), r"constants\.zoneIDs\s*=")
    ranks = lua_data.find_assigned_table(read("npcs_enum.lua"), r"constants\.npcRanks\s*=")
    npc_src = read("foreverNpcDB.lua")
    obj_src = read("foreverObjectDB.lua")
    npc_keys = lua_data.find_assigned_table(npc_src, r"QuestieDB\.npcKeys\s*=")
    obj_keys = lua_data.find_assigned_table(obj_src, r"QuestieDB\.objectKeys\s*=")
    npcs = lua_data.parse_return_table(dict(lua_data.long_strings_assigned(npc_src, r"QuestieDB\.npcData"))["QuestieDB.npcData"])
    objects = lua_data.parse_return_table(dict(lua_data.long_strings_assigned(obj_src, r"QuestieDB\.objectData"))["QuestieDB.objectData"])
    log("questiedb: %d npcs, %d objects (raw)" % (len(npcs), len(objects)))

    symbols = {"npcKeys": npc_keys, "objectKeys": obj_keys, "zoneIDs": zones, "npcRanks": ranks,
               "QuestieDB": {"npcKeys": npc_keys, "objectKeys": obj_keys, "npcRanks": ranks},
               "ZoneDB": {"zoneIDs": zones}}

    def apply(data, name):
        src = read(name)
        m = re.search(r":Load\(\)", src)
        if not m:
            log("no Load() in " + name)
            return
        r = re.compile(r"\breturn\s*\{").search(src, m.end())
        corrections = lua_data.parse_table_at(src, r.end() - 1, symbols)
        count = 0
        for entity_id, fields in corrections.items():
            if not isinstance(entity_id, int) or not isinstance(fields, dict):
                continue
            entry = data.setdefault(entity_id, {})
            for key, value in fields.items():
                if isinstance(key, int) and key < 100:
                    entry[key] = value
            count += 1
        log("applied %d corrections from %s" % (count, name))

    for name in ("foreverBaseNpc.lua", "foreverNpcTraces.lua", "foreverNPCFixes.lua"):
        apply(npcs, name)
    for name in ("foreverBaseObject.lua", "foreverObjectTraces.lua", "foreverObjectFixes.lua"):
        apply(objects, name)

    area_src = read("areaIdToUiMapId.lua")
    area_map = {}
    strings = list(lua_data.long_strings_assigned(area_src, r"ZoneDB\.private\.\w+"))
    for name, body in sorted(strings, key=lambda s: "Override" in s[0]):
        if "areaIdToUiMapId" in name:
            for area, ui in lua_data.parse_return_table(body).items():
                area_map[area] = ui
    dungeons = lua_data.find_assigned_table(read("dungeons.lua"), r"local\s+dungeons\s*=")
    dungeon_areas = set()
    for area, info in dungeons.items():
        dungeon_areas.add(area)
        if isinstance(info, dict) and isinstance(info.get(2), dict):
            dungeon_areas.update(v for v in info[2].values() if isinstance(v, int))
    return npcs, objects, npc_keys, obj_keys, area_map, dungeon_areas


def cells_for(spawns, area_map, dungeon_areas):
    """{uiMapID: {cell: count}} from QuestieDB spawns {areaID: {1: {1: x, 2: y}, ...}}."""
    out = collections.defaultdict(lambda: collections.defaultdict(int))
    if not isinstance(spawns, dict):
        return out
    for area, coords in spawns.items():
        if not isinstance(area, int) or area in dungeon_areas:
            continue
        ui = area_map.get(area)
        if not ui:
            continue
        for c in (coords or {}).values():
            if not isinstance(c, dict):
                continue
            x, y = c.get(1), c.get(2)
            if not isinstance(x, (int, float)) or not isinstance(y, (int, float)) or x < 0 or y < 0 or x > 100 or y > 100:
                continue
            cx = min(GRID_W - 1, int(x / 100.0 * GRID_W))
            cy = min(GRID_H - 1, int(y / 100.0 * GRID_H))
            out[ui][cy * GRID_W + cx] += 1
    return out


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def num(v, digits=4):
    if isinstance(v, int) or float(v).is_integer():
        return str(int(v))
    return ("%.*f" % (digits, v)).rstrip("0").rstrip(".")


def cells_lua(cells):
    parts = []
    for ui in sorted(cells):
        flat = []
        for cell in sorted(cells[ui]):
            flat.append(str(cell))
            flat.append(str(cells[ui][cell]))
        parts.append("[%d]={%s}" % (ui, ",".join(flat)))
    return "{" + ",".join(parts) + "}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "BagBroker", "FarmData.lua"))
    args = ap.parse_args()

    fetch(CLASSICDB_URL, os.path.join(args.cache, "classicdb.sql.gz"))
    for name, path in QDB_FILES.items():
        fetch(QDB + path, os.path.join(args.cache, "qdb", name))

    with gzip.open(os.path.join(args.cache, "classicdb.sql.gz"), "rt", encoding="latin-1") as f:
        sql = f.read()
    templates = {r["Entry"]: r for r in sql_rows(sql, "creature_template")}
    item_rows = {r["entry"]: r for r in sql_rows(sql, "item_template")}

    def by_entry(table):
        d = collections.defaultdict(list)
        for r in sql_rows(sql, table):
            d[r["entry"]].append(r)
        return d

    creature_loot = by_entry("creature_loot_template")
    ref_loot = by_entry("reference_loot_template")
    skin_loot = by_entry("skinning_loot_template")
    go_loot = by_entry("gameobject_loot_template")
    go_templates = sql_rows(sql, "gameobject_template")
    del sql
    log("classicdb: %d creatures, %d items" % (len(templates), len(item_rows)))

    npcs, objects, nk, ok_, area_map, dungeon_areas = load_questiedb(os.path.join(args.cache, "qdb"))

    used_items, named_items = set(), set()
    ref_memo, used_refs, used_skins = {}, set(), set()
    mobs_out = []
    stats = collections.Counter()
    for npc_id in sorted(set(npcs) | set(templates)):
        q = npcs.get(npc_id) or {}
        t = templates.get(npc_id)
        name = q.get(nk["name"]) or (t and t["Name"])
        if not name or PLACEHOLDER.search(name):
            continue
        friendly = q.get(nk["friendlyToFaction"])
        min_level = q.get(nk["minLevel"]) or (t and t["MinLevel"]) or 0
        max_level = q.get(nk["maxLevel"]) or (t and t["MaxLevel"]) or min_level
        rank = q.get(nk["rank"])
        if rank is None:
            rank = t["Rank"] if t else 0
        cells = cells_for(q.get(nk["spawns"]), area_map, dungeon_areas) if not friendly else {}

        has_db = t is not None
        gold = ((t["MinLootGold"] or 0) + (t["MaxLootGold"] or 0)) / 2.0 if t else 0
        direct, misc, refs_out = [], 0.0, []
        if t and t["LootId"]:
            items, refs = expand_loot(creature_loot.get(t["LootId"], []))
            for item, (chance, qty) in sorted(items.items(), key=lambda kv: -kv[1][1]):
                it = item_rows.get(item)
                if not it or it["SellPrice"] is None:
                    continue
                if qty < MIN_DIRECT_QTY:
                    misc += qty * (it["SellPrice"] or 0)
                    continue
                count = qty / chance if chance > 0 else 1
                direct.append((item, chance, count))
                used_items.add(item)
                if chance >= NAME_MIN_CHANCE:
                    named_items.add(item)
            for ref, rolls in refs.items():
                if flatten_ref(ref, ref_loot, ref_memo):
                    refs_out.append((ref, rolls))
                    used_refs.add(ref)
        skin = t["SkinningLootId"] if t and t["SkinningLootId"] else 0
        if skin:
            used_skins.add(skin)
        useful = direct or refs_out or gold > 0 or skin or misc > 0
        if not useful and not (cells and not has_db):
            continue  # nothing to value and not a Forever-only spawn
        if friendly and not useful:
            continue
        stats["mobs"] += 1
        stats["with_spawns"] += 1 if cells else 0
        stats["forever_only"] += 0 if has_db else 1
        loot_flat = ",".join("%d,%s,%s" % (i, num(c), num(n, 2)) for i, c, n in direct)
        refs_flat = ",".join("%d,%s" % (r, num(rolls)) for r, rolls in refs_out)
        mobs_out.append("[%d]={%s,%d,%d,%d,%s,%d,{%s},{%s},%s,%s,%s}" % (
            npc_id, lua_str(name), min_level, max_level, rank, num(gold, 1), skin, loot_flat, refs_flat,
            cells_lua(cells), num(misc, 1), "true" if has_db else "false"))

    refs_lines = []
    for ref in sorted(used_refs):
        flat = [(i, qty) for i, qty in ref_memo[ref].items() if qty >= MIN_REF_QTY and i in item_rows]
        for i, _ in flat:
            used_items.add(i)
        refs_lines.append("[%d]={%s}" % (ref, ",".join("%d,%s" % (i, num(qty, 5)) for i, qty in sorted(flat))))

    skins_lines = []
    for entry in sorted(used_skins):
        items, _ = expand_loot(skin_loot.get(entry, []))
        flat = [(i, qty) for i, (_, qty) in items.items() if i in item_rows]
        for i, _ in flat:
            used_items.add(i)
            named_items.add(i)
        skins_lines.append("[%d]={%s}" % (entry, ",".join("%d,%s" % (i, num(qty)) for i, qty in sorted(flat))))

    # Gathering nodes: yields per node (loot per use x average uses) and Forever spawns by name.
    node_yield = {}
    for g in go_templates:
        name = g["name"]
        if name in NODE_SKILLS and g["type"] == 3 and g["data1"] and name not in node_yield:
            items, _ = expand_loot(go_loot.get(g["data1"], []))
            uses = (max(1, g["data4"] or 1) + max(1, g["data5"] or 1)) / 2.0
            node_yield[name] = {i: qty * uses for i, (_, qty) in items.items() if i in item_rows}
    node_cells = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(int)))
    for obj in objects.values():
        name = obj.get(ok_["name"]) if isinstance(obj, dict) else None
        if name in NODE_SKILLS:
            for ui, cells in cells_for(obj.get(ok_["spawns"]), area_map, dungeon_areas).items():
                for cell, n in cells.items():
                    node_cells[name][ui][cell] += n
    nodes_lines = []
    for name in sorted(NODE_SKILLS):
        if name not in node_yield or name not in node_cells:
            continue
        prof, skill = NODE_SKILLS[name]
        for i in node_yield[name]:
            used_items.add(i)
            named_items.add(i)
        loot = ",".join("%d,%s" % (i, num(q, 3)) for i, q in sorted(node_yield[name].items()))
        nodes_lines.append("{%s,%s,%d,{%s},%s}" % (lua_str(name), lua_str(prof), skill, loot, cells_lua(node_cells[name])))

    item_lines = []
    for i in sorted(used_items):
        it = item_rows[i]
        fields = [str(it["SellPrice"] or 0), str(it["Quality"] or 0)]
        if i in named_items:
            fields.append(lua_str(it["name"]))
        item_lines.append("[%d]={%s}" % (i, ",".join(fields)))

    today = datetime.date.today().isoformat()
    out = [
        "-- AUTO GENERATED by tools/build_farm_data.py on %s. Do not edit." % today,
        "-- Data derived from CMaNGOS Classic-DB (GPLv3, https://github.com/cmangos/classic-db) and",
        "-- QuestieDB Forever data (GPLv3, https://github.com/Questie/QuestieDB). See licenses/.",
        "-- mobs[npcID] = { name, minLevel, maxLevel, rank, avgCopper, skinLootID, {itemID, chance, avgCount, ...},",
        "--                 {refID, rolls, ...}, {[uiMapID] = {cell, spawns, ...}}, smallDropVendorCopper, hasLootData }",
        "local _, ns = ...",
        "ns.FarmDB = {",
        'built = "%s",' % today,
        "grid = {%d, %d}," % (GRID_W, GRID_H),
        "items = {" + ",".join(item_lines) + "},",
        "refs = {" + ",".join(refs_lines) + "},",
        "skins = {" + ",".join(skins_lines) + "},",
        "nodes = {" + ",".join(nodes_lines) + "},",
        "mobs = {" + ",\n".join(mobs_out) + "},",
        "}",
        "",
    ]
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    log("wrote %s: %d mobs (%d with open-world spawns, %d Forever-only), %d refs, %d skins, %d node types, %d items, %.1f MB" % (
        args.out, stats["mobs"], stats["with_spawns"], stats["forever_only"], len(refs_lines), len(skins_lines),
        len(nodes_lines), len(item_lines), os.path.getsize(args.out) / 1e6))


if __name__ == "__main__":
    main()
