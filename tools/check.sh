#!/usr/bin/env bash
# Verification tool. Prints only relevant lines; exit 2 if Godot is missing.
#   tools/check.sh       -> import, menu, 3 offline smoke matches (all maps, both modes)
#   tools/check.sh net   -> also LAN test on 127.0.0.1: host + client + rejected 3rd human
# Runs real scenes so autoloads exist. Don't use `godot --check-only --script`: no autoloads
# there => false "Identifier not found: Game".
GODOT="${GODOT:-/c/Users/ROX/Desktop/Godot.exe}"
[ -x "$GODOT" ] || { echo "ERROR: Godot not found at $GODOT (set GODOT=...)"; exit 2; }
cd "$(dirname "$0")/.." || exit 1
filter() { grep -E "ERROR|Parse Error|SCRIPT|WARNING|at: |\[match\]" | head -n "${MAX:-40}"; }
run() { "$GODOT" --headless --path . $([ -n "$RT" ] && echo --max-fps 60 || echo --fixed-fps 60) --quit-after "$1" "${@:2}" 2>&1 | filter; }
summ() { grep -v "eliminó" ; }  # kill lines are counted, not printed
"$GODOT" --headless --path . --import 2>&1 | filter
echo "== menu"; run 30
for A in "--map=0 --bots=2" "--map=1 --ffa --bots=4" "--map=2 --bots=3"; do
  out=$(run 900 res://match/match.tscn -- $A); echo "== match $A | kills: $(grep -c eliminó <<<"$out")"; summ <<<"$out"
done
if [ "$1" = net ]; then
  RT=1 run 1500 -- --host --map=1 >/tmp/sf_host.log & sleep 3
  RT=1 run 1200 -- --join=127.0.0.1 >/tmp/sf_c1.log & sleep 3
  RT=1 run 300 -- --join=127.0.0.1 >/tmp/sf_c2.log; wait
  grep -qF "[match]" /tmp/sf_c2.log && echo "ERROR: 3rd human was admitted"
  for f in host c1 c2; do echo "== net $f | kills: $(grep -c eliminó /tmp/sf_$f.log)"; summ </tmp/sf_$f.log; done
fi
echo "== done"
