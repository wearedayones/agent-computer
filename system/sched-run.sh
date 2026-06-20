#!/bin/bash
# sched-run.sh — wrapper executed by sched cron jobs; records run history
# Usage: bash ~/system/sched-run.sh <name> <command...>
# Called automatically by sched-managed cron entries — do not invoke directly.

name="$1"; shift
cmd="$*"
LOG="$HOME/system/sched-log.jsonl"
SCHED="$HOME/system/sched.json"

[ -z "$name" ] && exit 1

start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
start_ts=$(date +%s)

bash -c "$cmd"
exit_code=$?

end_ts=$(date +%s)
duration=$((end_ts - start_ts))

python3 - "$LOG" "$SCHED" "$name" "$start" "$exit_code" "$duration" <<'EOF'
import json, sys
from pathlib import Path
from datetime import datetime, timezone

log_file, sched_file, name, start, exit_code, duration = sys.argv[1:7]
exit_code, duration = int(exit_code), int(duration)

entry = {
    "ts": start,
    "name": name,
    "exit_code": exit_code,
    "duration_s": duration,
    "ok": exit_code == 0,
}
with open(log_file, "a") as f:
    f.write(json.dumps(entry) + "\n")

# Update last_run + last_exit in sched.json
try:
    d = json.loads(Path(sched_file).read_text())
    for job in d.get("jobs", []):
        if job["name"] == name:
            job["last_run"] = start
            job["last_exit"] = exit_code
            break
    Path(sched_file).write_text(json.dumps(d, indent=2))
except:
    pass
EOF
