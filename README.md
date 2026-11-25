# Spiritech Modern UI

A dark, minimal, flat UI addon set for the Spiritech (Project Rubi-Ka) client.

## Install

From a release: download `modern-ui-<version>.zip` from the GitHub releases page and
unzip it into `~/.local/share/ProjectRubiKa/ui-packages/`.

From source: packages live in `packages/`. Run

    ./install.sh                         # all packages
    ./install.sh spiritech.modern-trade  # just one

to copy them into `~/.local/share/ProjectRubiKa/ui-packages/` (override with
`SPIRITECH_UI_PACKAGES`). `tools/` folders are not copied. Then pick the packages
in **Options → Interface & HUD → UI packages**.

Edit files here, never in `ui-packages/`: the next install overwrites them.

## Packages

| Package | Replaces role | Notes |
|---|---|---|
| `spiritech.modern-common` | — | Shared library: flat window frame, theme, centre snap, screen-fit fix, item requirement / implant data, NCU list |
| `spiritech.modern-stats` | `prk.stats` | Compact bottom-centre strip (name, level, AR, ACs) |
| `spiritech.modern-status-bars` | `prk.status-bars` | Horizontal status bars |
| `spiritech.player-bars` | — | Movable combined Player Bars panel |
| `spiritech.hide-status-bars` | `prk.status-bars` | Hides the built-in status bars |
| `spiritech.modern-compass` | `prk.compass` | Flat, resizable compass strip |
| `spiritech.modern-map` | `prk.playfield-map` | Square local map with info strip |
| `spiritech.modern-world-map` | `prk.planet-map` | Flat world map with toolbar |
| `spiritech.modern-timer-bars` | `prk.timer-bars` | Timer bars |
| `spiritech.modern-target-panels` | `prk.target-panels` | Friendly / hostile target panels |
| `spiritech.modern-control-center` | `prk.control-center`, `prk.hotbar` | Slim control bar, NCU / credits, hotbars, Cooldowns window |
| `spiritech.modern-hotbar` | `prk.hotbar` | Standalone hotbar (fallback) |
| `spiritech.modern-inventory` | `prk.inventory` | Inventory with organizer tabs, requirements, pop-out panels |
| `spiritech.modern-wear` | `prk.wear` | Equipment window |
| `spiritech.modern-trade` | `prk.trade` | Flat trade / shop lists |
| `spiritech.modern-missions` | `prk.missions` | Mission list with deadline bars |
| `spiritech.modern-mission-terminal` | `prk.mission-terminal` | Mission terminal: offer list with rewards / requirements, offer map, resizable |
| `spiritech.modern-info` | `prk.info` | Info window: flat, ◄ ► in the title bar, item names beside icons |
| `spiritech.modern-team` | `prk.team` | Unit-frame style team window |
| `spiritech.modern-pets` | `prk.pets` | Unit-frame style pet window with commands |
| `spiritech.modern-skills` | `prk.skills` | Skills window: favorites, views, IP priorities |
| `spiritech.modern-nanos` | `prk.nano-programs` | Nano programs: search, nanoline groups, details |
| `spiritech.modern-ncu` | `prk.ncu` | Slim NCU list |
| `spiritech.modern-target-ncu` | `prk.target-ncu` | Nano / fight target NCU windows in the same style |
| `spiritech.ncu-strip` | — | NCU icon strip |
| `spiritech.modern-actions` | `prk.actions` | Actions list |
| `spiritech.modern-chat-frame` | `prk.chat-frame` | Flat chat frame |
| `spiritech.modern-chat` | `prk.chat` | Flat chat log / input |
| `spiritech.combat-log` | — | Standalone structured combat log |

## Tools

Run with the client closed.

- `packages/spiritech.modern-common/tools/gen_itemreqs.py`, `gen_itemmods.py` —
  regenerate `lua/itemreqs_*.lua` / `lua/itemmods.lua` from the client's `rdb.db`.
- `packages/spiritech.modern-common/tools/copy_ui.py FROM TO` — copy UI layout between characters.
- `packages/spiritech.modern-control-center/tools/migrate_hotbar_labels.py` — migrate hotbar labels.

## Releasing

`./release.sh 1.2.0` stamps `version="1.2.0"` and `apiVersion="0.2.0"` (override with
`API_VERSION=`; keep it matching the client's `addon-api.version.txt`) into every
`package.xml`, checks that each package folder matches its id and that every required
package is bundled, and builds `dist/modern-ui-1.2.0.zip` (one top-level folder per
package, LICENSE inside each). Commit the manifests, tag the commit `v1.2.0`, and upload
the zip. Published versions cannot be replaced, so the script refuses a version that is
already tagged; always bump.

## Limits

A package VM may register at most 64 UI modules, and every `.lua` under a
library's `lua/` counts for every package that requires it. Check the count
before adding files to `modern-common/lua/`.

## License

MIT, see [LICENSE](LICENSE). The generated item data in
`packages/spiritech.modern-common/lua/itemreqs_*.lua` and `itemmods.lua` is
derived from the game client's database and is not covered by this license.
