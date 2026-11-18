#!/usr/bin/env python3
"""Copy hotbar labels from spiritech.modern-hotbar's storage into this package's storage.

The shortcut bars now run inside the Modern Control Center package (so they can relay
cooldowns to the Perk Actions window), and addon storage is per package. Run this ONCE with
the game client closed; it only adds "<character>/bar@x,y" keys that aren't there yet.

    python3 migrate_hotbar_labels.py
"""
import glob, json, os, sys

DATA = os.path.expanduser("~/.local/share/ProjectRubiKa/addon-data")
src = glob.glob(os.path.join(DATA, "spiritech_modern-hotbar-*.json"))
dst = glob.glob(os.path.join(DATA, "spiritech_modern-control-center-*.json"))
if not src or not dst:
    sys.exit(f"storage files not found in {DATA} (hotbar: {src}, control center: {dst})")
with open(src[0]) as f: labels = json.load(f)
with open(dst[0]) as f: target = json.load(f)
added = 0
for key, value in labels.items():
    if "/bar@" in key and key not in target:
        target[key] = value
        added += 1
with open(dst[0], "w") as f: json.dump(target, f, indent=2)
print(f"copied {added} hotbar label(s) into {os.path.basename(dst[0])}")
