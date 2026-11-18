#!/usr/bin/env python3
"""Copy one character's UI layout to another. Run with the game CLOSED (it rewrites its
prefs on logout and would undo the copy).

    python3 copy_ui.py FROM TO            e.g.  python3 copy_ui.py Wannama Wannatrade

Character ids are looked up by name: the Modern Inventory records "who/<key> = <name>" each
time a character logs in, and every lookup is remembered in copy-ui-characters.json. A
character that has never logged in with the inventory loaded can be given by hand:
COPY_UI_IDS=FROMID:TOID (the number after _50000_ in addon storage keys).

Copies:
  * prefs/<server>/<FROM>/Prefs.xml -> <TO>: window positions/sizes, open windows, chat
    windows, list settings, Modern package options. The target keeps its own bank and
    inventory item order (bank_item_positionsConfig, item_position_map).
  * addon storage keys that belong to FROM's character id (hotbar labels, inventory pop-out
    panels and tags, inventory window positions) to TO's id. "seen" (new-item tracking) is
    left alone.
Not copied: hotbar contents (Containers/ShortcutBar_*.xml - skills differ per character)
and text macros.

Everything overwritten is backed up first under ~/.local/share/ProjectRubiKa/ui-backups/.
"""
import json, os, re, shutil, subprocess, sys, time

ROOT = os.environ.get("COPY_UI_ROOT") or os.path.expanduser("~/.local/share/ProjectRubiKa")
PREFS = os.path.join(ROOT, "prefs")
DATA = os.path.join(ROOT, "addon-data")
CACHE = os.path.join(ROOT, "copy-ui-characters.json")
KEEP_ARCHIVES = ("bank_item_positionsConfig", "item_position_map")
SKIP_SUFFIXES = ("/seen",)


def die(message):
    print("error: " + message)
    sys.exit(1)


def game_running():
    try:
        out = subprocess.run(["pgrep", "-fl", "PRK.Client|AnarchyOnline|anarchyonline"],
                             capture_output=True, text=True).stdout
    except FileNotFoundError:
        return False
    return any("copy_ui.py" not in line for line in out.splitlines() if line.strip())


def character_dir(name):
    for server in sorted(os.listdir(PREFS)):
        folder = os.path.join(PREFS, server)
        if not os.path.isdir(folder):
            continue
        for entry in sorted(os.listdir(folder)):
            path = os.path.join(folder, entry)
            if entry.lower() == name.lower() and os.path.isdir(path):
                return server, path
    die("no prefs folder for character %r (look in %s)" % (name, PREFS))


def top_level_archive(text, name):
    """(start, end) of a top-level <Archive name="name" ...>...</Archive> block, or None."""
    match = re.search(r'^(    )<Archive name="%s"[^>]*?(/>|>)' % re.escape(name), text, re.M)
    if not match:
        return None
    if match.group(2) == "/>":
        end = text.index("\n", match.end()) + 1
        return match.start(), end
    close = re.compile(r"^    </Archive>\n?", re.M).search(text, match.end())
    return match.start(), close.end()


def copy_prefs(src_xml, dst_xml):
    source = open(src_xml, encoding="utf-8").read()
    target = open(dst_xml, encoding="utf-8").read() if os.path.exists(dst_xml) else ""
    result = source
    for name in KEEP_ARCHIVES:
        mine = top_level_archive(target, name)
        theirs = top_level_archive(result, name)
        if theirs:
            keep = target[mine[0]:mine[1]] if mine else ""
            result = result[:theirs[0]] + keep + result[theirs[1]:]
        elif mine:
            result = result.replace("</Root>", target[mine[0]:mine[1]] + "</Root>")
    open(dst_xml, "w", encoding="utf-8").write(result)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    src_name, dst_name = sys.argv[1], sys.argv[2]
    if not os.environ.get("COPY_UI_ROOT") and game_running():
        die("the game is running - close it first (it saves prefs on logout)")
    server, src_dir = character_dir(src_name)
    _, dst_dir = character_dir(dst_name)
    src_name, dst_name = os.path.basename(src_dir), os.path.basename(dst_dir)

    ids = ask_ids(src_name, dst_name)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = base = os.path.join(ROOT, "ui-backups", "%s-%s-to-%s" % (stamp, src_name, dst_name))
    number = 1
    while os.path.exists(backup):
        number += 1
        backup = "%s-%d" % (base, number)
    os.makedirs(backup)
    shutil.copy2(os.path.join(dst_dir, "Prefs.xml"), os.path.join(backup, dst_name + "-Prefs.xml"))
    shutil.copytree(DATA, os.path.join(backup, "addon-data"))

    copy_prefs(os.path.join(src_dir, "Prefs.xml"), os.path.join(dst_dir, "Prefs.xml"))
    print("Prefs.xml: %s -> %s" % (src_name, dst_name))

    if ids:
        src_id, dst_id = ids
        pattern = re.compile(r"(_\d+_)%s/" % re.escape(src_id))
        for file in sorted(os.listdir(DATA)):
            if not file.endswith(".json"):
                continue
            path = os.path.join(DATA, file)
            data = json.load(open(path, encoding="utf-8"))
            copied = 0
            for key in list(data):
                if not pattern.search(key) or key.endswith(SKIP_SUFFIXES):
                    continue
                data[pattern.sub(lambda m: m.group(1) + dst_id + "/", key)] = data[key]
                copied += 1
            if copied:
                json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
                print("%s: %d keys" % (file, copied))
    print("Backup: " + backup)


def known_ids():
    """{lowercase name: id} from the cache plus every addon's "who/<key>" entries."""
    names = {}
    if os.path.exists(CACHE):
        names.update(json.load(open(CACHE, encoding="utf-8")))
    for file in sorted(os.listdir(DATA)) if os.path.isdir(DATA) else []:
        if not file.endswith(".json"):
            continue
        try:
            data = json.load(open(os.path.join(DATA, file), encoding="utf-8"))
        except ValueError:
            continue
        for key, value in data.items():
            match = re.search(r"(?:^|/)who/.*_(\d+)$", key)
            if match and isinstance(value, str) and value.strip():
                names[value.strip().lower()] = match.group(1)
    return names


def ask_ids(src_name, dst_name):
    """(FROMID, TOID) for the two names; stops when one is unknown."""
    value = os.environ.get("COPY_UI_IDS", "")
    names = known_ids()
    if ":" in value:
        ids = tuple(value.split(":", 1))
    else:
        ids = (names.get(src_name.lower()), names.get(dst_name.lower()))
        missing = [n for n, i in zip((src_name, dst_name), ids) if not i]
        if missing:
            die("no character id known for %s yet - log in on it once (with the Modern "
                "Inventory loaded), quit, and run this again. Nothing was copied."
                % " and ".join(missing))
    names[src_name.lower()], names[dst_name.lower()] = ids
    json.dump(names, open(CACHE, "w", encoding="utf-8"), indent=2, sort_keys=True)
    print("ids: %s=%s, %s=%s" % (src_name, ids[0], dst_name, ids[1]))
    return ids


if __name__ == "__main__":
    main()
