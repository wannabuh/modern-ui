#!/usr/bin/env bash
# Every role a package provides must define every callback the client documents for that
# role's built-in window: the game calls them by name, and a missing one shuts the package
# down ("The requested script entry is not a function"). Client updates add new ones.
# Usage: tools/check_callbacks.sh [client dir]   (default ~/Games/spiritech/client)
set -euo pipefail
cd "$(dirname "$0")/.."
client="${1:-${SPIRITECH_CLIENT:-$HOME/Games/spiritech/client}}"
docs="$client/docs/lua-api"
[[ -d $docs ]] || { echo "no client docs at $docs; skipping callback check" >&2; exit 0; }
declare -A dir=(
  [prk.actions]=Actions [prk.chat]=Chat [prk.chat-frame]=ChatFrame [prk.compass]=Compass
  [prk.control-center]=ControlCenter [prk.hotbar]=Hotbar [prk.info]=Info [prk.inventory]=Inventory
  [prk.playfield-map]=PlayfieldMap [prk.planet-map]=PlanetMap [prk.missions]=Missions
  [prk.mission-terminal]=MissionTerminal [prk.ncu]=Ncu [prk.stats]=Stats [prk.status-bars]=StatusBars
  [prk.target-panels]=TargetPanels [prk.target-ncu]=TargetNcu [prk.team]=Team
  [prk.timer-bars]=TimerBars [prk.trade]=Trade [prk.wear]=Wear
)
callbacks=$(for f in "$docs"/*.md; do
  awk '/^### /{n=$2} /^Built-in component callback in `/{match($0,/`[^`]+`/); print substr($0,RSTART+1,RLENGTH-2), n}' "$f"
done | sort -u || true)
fail=0
for manifest in packages/*/package.xml; do
  pkg=$(dirname "$manifest")
  for role in $(grep -oP 'Provides role="\K[^"]+' "$manifest"); do
    stock=${dir[$role]:-}
    [[ -n $stock ]] || { echo "$pkg: role $role has no stock window mapping in $0" >&2; fail=1; continue; }
    defined=$(cat "$pkg"/*.lua 2>/dev/null | grep -oP '^\s*function \K[A-Za-z_]+(?=\()' | sort -u || true)
    for name in $(grep "^$stock/" <<<"$callbacks" | awk '{print $2}' | sort -u || true); do
      grep -qx "$name" <<<"$defined" || { echo "$pkg ($role): missing callback $name" >&2; fail=1; }
    done
  done
done
(( fail == 0 )) && echo "callbacks ok"
exit $fail
