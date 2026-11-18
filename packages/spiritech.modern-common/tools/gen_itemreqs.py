#!/usr/bin/env python3
"""Generate item requirement tables for the Modern Inventory from the client's item database.

Reads cd_image/rdb.db (table rdb_1000020 = items), decodes each item's wear / wield / use
requirements and writes lua/itemreqs_<letter>.lua into spiritech.modern-common:

    return { ["Item Name"] = { {ql, "stat:value,stat:value", "Doctor/Adventurer", "min:max:crit:type"}, ... } }

value is the minimum needed (AO stores "stat > value-1"). The 4th field is weapon damage
(attributes 286 min, 285 max, 284 crit bonus, 436 damage type), or "" for non-weapons.
Several QL points per name let the addon interpolate for the item's actual QL. Re-run after
game updates:

    python3 gen_itemreqs.py ~/Games/spiritech/client/cd_image/rdb.db
"""
import os, sqlite3, struct, sys, collections

DB = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Games/spiritech/client/cd_image/rdb.db")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lua")
PROFESSIONS = {1: "Soldier", 2: "Martial Artist", 3: "Engineer", 4: "Fixer", 5: "Agent", 6: "Adventurer",
               7: "Trader", 8: "Bureaucrat", 9: "Enforcer", 10: "Doctor", 11: "Nano-Technician",
               12: "Meta-Physicist", 14: "Keeper", 15: "Shade"}
ACTION_PRIORITY = [6, 8, 3]  # wear, wield, use
OP_EQUAL, OP_GREATER, OP_OR, OP_AND = 0, 2, 3, 4
PROFESSION_STATS = (60, 368)  # profession, visual profession

def attributes(b):
    count = struct.unpack_from("<i", b, 16)[0] // 1009 - 1  # 1009-encoded attribute count
    attrs, p = {}, 20
    for _ in range(count):
        k, v = struct.unpack_from("<ii", b, p); p += 8
        attrs[k] = v
    return attrs, p

def name_of(b, p):
    """(21, ?) marker, int16 name length, int16 description length, name, description.
    Returns the name and the offset just past the description (where the chunks start)."""
    key = struct.unpack_from("<i", b, p)[0]
    if key != 21: return None, None
    name_len, desc_len = struct.unpack_from("<HH", b, p + 8)
    name = b[p + 12:p + 12 + name_len].split(b"\0")[0].decode("latin-1").strip()
    return name, p + 12 + name_len + desc_len

def actions(b, start):
    # Chunks follow the description, 4-byte aligned relative to it (not to the record).
    for o in range(start, len(b) - 12, 4):
        k, a, cnt = struct.unpack_from("<iii", b, o)
        if k == 22 and a == 36 and cnt % 1009 == 0 and 0 < cnt // 1009 - 1 < 12:
            p, out = o + 12, {}
            for _ in range(cnt // 1009 - 1):
                if p + 8 > len(b): return {}
                act, cc = struct.unpack_from("<ii", b, p); p += 8
                if cc % 1009: return {}
                n = cc // 1009 - 1
                if p + 12 * n > len(b): return {}
                out[act] = [struct.unpack_from("<iii", b, p + 12 * j) for j in range(n)]
                p += 12 * n
            return out
    return {}

def evaluate(criteria):
    """Postfix criteria -> ({stat: minimum}, [profession names])."""
    stack = []
    for stat, value, op in criteria:
        if op == OP_GREATER and stat:
            stack.append(("num", stat, value + 1))
        elif op == OP_EQUAL and stat in PROFESSION_STATS:
            stack.append(("prof", PROFESSIONS.get(value)))
        elif op == OP_OR and stack and len(stack) >= 2:
            b_, a_ = stack.pop(), stack.pop()
            if a_ and b_ and a_[0] == "prof" and b_[0] == "prof":
                stack.append(("prof", "/".join(x for x in (a_[1], b_[1]) if x)))
            else:
                stack.append(a_ or b_)  # keep something readable; OR of skills is rare
        elif op == OP_AND and not stat:
            pass  # AND just joins terms; both stay on the stack
        else:
            stack.append(None)  # unhandled condition (flags, states...)
    nums, profs = {}, []
    for term in stack:
        if not term: continue
        if term[0] == "num": nums[term[1]] = max(nums.get(term[1], 0), term[2])
        elif term[0] == "prof" and term[1]: profs.append(term[1])
    return nums, profs

def main():
    db = sqlite3.connect(DB)
    # 1) every item with requirements: id -> (ql, name, icon, nums, profs)
    items = {}
    for item_id, b in db.execute("select id, data from rdb_1000020"):
        if not b or len(b) < 40: continue
        try:
            attrs, p = attributes(b)
            name, chunks = name_of(b, p)
        except struct.error:
            continue
        if not name: continue
        acts = actions(b, chunks)
        crit = next((acts[a] for a in ACTION_PRIORITY if a in acts), None)
        nums, profs = evaluate(crit) if crit else ({}, [])
        damage = None
        if attrs.get(285) and attrs.get(286) is not None:
            damage = (attrs.get(286, 0), attrs.get(285, 0), attrs.get(284, 0), attrs.get(436, 0))
        if not nums and not profs and not damage: continue
        items[item_id] = (attrs.get(54, 1), name, attrs.get(79), nums, profs, damage)

    # 2) AO stores each item as a low-QL and a high-QL template with adjacent IDs (either
    #    order) and often different names ("Treatment Laboratory" QL 1 / "HQ Health
    #    Laboratory" QL 200). An in-between QL is interpolated between the two. Pair them by
    #    adjacent ID + same requirement stats rising with QL + different QL, and file both points
    #    under both names (the game shows either name depending on the QL).
    def partner(item_id):
        ql, _, _icon, nums, _, damage = items[item_id]
        for other_id in (item_id + 1, item_id - 1):
            other = items.get(other_id)
            if not other or other[0] == ql or set(other[3]) != set(nums):
                continue
            if (damage is None) != (other[5] is None):
                continue
            low, high = (nums, other[3]) if ql < other[0] else (other[3], nums)
            # a real low/high pair: every requirement grows (or stays) with QL
            if all(high[stat] >= low[stat] for stat in low):
                return other_id
        return None

    table = collections.defaultdict(dict)  # name -> ql -> (nums, profs, damage)
    for item_id, (ql, name, _icon, nums, profs, damage) in items.items():
        table[name][ql] = (nums, profs, damage)
        other_id = partner(item_id)
        if other_id:
            oql, _, _, onums, oprofs, odamage = items[other_id]
            table[name].setdefault(oql, (onums, oprofs, odamage))

    os.makedirs(OUT, exist_ok=True)
    buckets = collections.defaultdict(list)
    for name, points in table.items():
        first = name[0].lower()
        bucket = first if "a" <= first <= "z" else "other"
        rows = []
        for ql in sorted(points):
            nums, profs, damage = points[ql]
            req = ",".join(f"{s}:{v}" for s, v in sorted(nums.items()))
            dmg = ":".join(str(x) for x in damage) if damage else ""
            rows.append('{%d,"%s","%s","%s"}' % (ql, req, "/".join(profs), dmg))
        esc = name.replace("\\", "\\\\").replace('"', '\\"')
        buckets[bucket].append('["%s"]={%s}' % (esc, ",".join(rows)))
    total = 0
    for bucket, lines in buckets.items():
        path = os.path.join(OUT, f"itemreqs_{bucket}.lua")
        with open(path, "w", encoding="latin-1") as f:
            f.write("-- Generated by tools/gen_itemreqs.py from the client's item database. Do not edit.\n")
            f.write("return {\n" + ",\n".join(sorted(lines)) + "\n}\n")
        total += len(lines)
    print(f"{total} item names with requirements in {len(buckets)} files")

if __name__ == "__main__":
    main()
