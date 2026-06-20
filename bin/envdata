#!/bin/bash
# env — machine mission context (any agent reads this to orient in 3 seconds)
# Usage: env show
#        env set <key> <value>
#        env get <key>
#        env del <key>
#        env check

STORE="$HOME/system/env.json"
[ -f "$STORE" ] || echo '{}' > "$STORE"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

cmd="${1:-show}"

case "$cmd" in
  show)
    python3 - "$STORE" <<'EOF'
import json, sys
BOLD, GREEN, YELLOW, NC = "\033[1m", "\033[0;32m", "\033[1;33m", "\033[0m"
with open(sys.argv[1]) as f: d = json.load(f)
if not d:
    print("  (no context set — start with: env set mission \"...\")")
    sys.exit(0)
print(f"\n  {BOLD}Machine Context{NC}\n")
# Priority fields shown first
priority = ["mission", "owner", "risk", "tags"]
shown = set()
for k in priority:
    if k in d:
        print(f"  {YELLOW}{k:<15}{NC} {d[k]}")
        shown.add(k)
# Constraints as a block
constraints = {k: v for k, v in d.items() if k.startswith("constraint") and k not in shown}
other = {k: v for k, v in d.items() if k not in shown and not k.startswith("constraint")}
for k, v in other.items():
    print(f"  {YELLOW}{k:<15}{NC} {v}")
if constraints:
    print(f"\n  {BOLD}Constraints:{NC}")
    for k, v in constraints.items():
        label = k.replace("constraint.", "").replace("constraint_", "")
        print(f"    • {v}")
print("")
EOF
    ;;

  set)
    [ -z "$2" ] && { echo "Usage: env set <key> <value>"; exit 1; }
    [ -z "$3" ] && { echo "Usage: env set <key> <value>"; exit 1; }
    key="$2"; shift 2; value="$*"
    python3 - "$STORE" "$key" "$value" <<'EOF'
import json, sys
store, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(store) as f: d = json.load(f)
d[key] = value
with open(store, "w") as f: json.dump(d, f, indent=2)
print(f"  \033[32m✓\033[0m  {key} = {value}")
EOF
    ;;

  get)
    [ -z "$2" ] && { echo "Usage: env get <key>"; exit 1; }
    python3 - "$STORE" "$2" <<'EOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
key = sys.argv[2]
if key not in d:
    print(f"  (not set: {key})"); sys.exit(1)
print(d[key])
EOF
    ;;

  del|delete|rm)
    [ -z "$2" ] && { echo "Usage: env del <key>"; exit 1; }
    python3 - "$STORE" "$2" <<'EOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
key = sys.argv[2]
if key not in d:
    print(f"  (not found: {key})"); sys.exit(1)
del d[key]
with open(sys.argv[1], "w") as f: json.dump(d, f, indent=2)
print(f"  \033[32m✓\033[0m  {key} removed")
EOF
    ;;

  check)
    python3 - "$STORE" <<'EOF'
import json, sys
GREEN, RED, YELLOW, BOLD, NC = "\033[0;32m", "\033[0;31m", "\033[1;33m", "\033[1m", "\033[0m"
with open(sys.argv[1]) as f: d = json.load(f)
required = ["mission", "owner", "risk"]
ok_count = 0
warn_count = 0
print(f"\n  {BOLD}Context Health Check{NC}\n")
for k in required:
    if k in d and d[k]:
        print(f"  {GREEN}✓{NC}  {k}: {d[k][:60]}")
        ok_count += 1
    else:
        print(f"  {RED}✗{NC}  {k} not set  →  env set {k} \"...\"")
        warn_count += 1
print("")
if warn_count == 0:
    print(f"  {GREEN}All critical fields set.{NC}\n")
else:
    print(f"  {RED}{warn_count} field(s) missing — agents may not have full context.{NC}\n")
sys.exit(0 if warn_count == 0 else 1)
EOF
    ;;

  list)
    python3 - "$STORE" <<'EOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
if not d:
    print("  (empty — use: env set <key> <value>)"); sys.exit(0)
YELLOW, NC = "\033[1;33m", "\033[0m"
for k, v in d.items():
    print(f"  {YELLOW}{k:<20}{NC} {v}")
EOF
    ;;

  *)
    echo "Usage: env show|set|get|del|check|list [args]"
    exit 1
    ;;
esac
