#!/bin/bash
# disk-cleanup.sh — weekly automated disk hygiene
# Run via: axis sched (every Sunday 03:00 UTC)
# Safe to run anytime. Never deletes anything irreplaceable.

HOME_DIR="$HOME"
LOG="$HOME_DIR/system/disk-cleanup.log"
FREED=0
REPORT=()

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG"; }
freed_mb() {
  local path="$1" label="$2"
  local before after delta
  before=$(du -sm "$path" 2>/dev/null | awk '{print $1}' || echo 0)
  eval "$3"  # run the cleanup command
  after=$(du -sm "$path" 2>/dev/null | awk '{print $1}' || echo 0)
  delta=$((before - after))
  if [ "$delta" -gt 0 ]; then
    FREED=$((FREED + delta))
    REPORT+=("  ✓  $label: freed ${delta}MB")
  fi
}

log "=== disk-cleanup start ==="

# 1. Downloads: remove files older than 7 days (not dirs — dirs may have active plugins/skills)
log "Cleaning ~/downloads/ files older than 7 days..."
find "$HOME_DIR/downloads/" -maxdepth 1 -type f -mtime +7 -exec rm -f {} \; 2>/dev/null
REPORT+=("  ✓  downloads/: old files removed")

# 2. Bybit backtest results: keep last 30 JSON files, compress the rest
RESULTS_DIR="$HOME_DIR/apps/bybit-bot/backtest/results"
if [ -d "$RESULTS_DIR" ]; then
  log "Rotating bybit backtest results..."
  COUNT=$(ls "$RESULTS_DIR"/*.json 2>/dev/null | wc -l)
  if [ "$COUNT" -gt 30 ]; then
    # Archive older ones to a compressed bundle
    ARCHIVE="$HOME_DIR/archive/bybit-results-$(date -u +%Y%m).tar.gz"
    ls -t "$RESULTS_DIR"/*.json 2>/dev/null | tail -n +31 | xargs tar -czf "$ARCHIVE" 2>/dev/null && \
    ls -t "$RESULTS_DIR"/*.json 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null
    REPORT+=("  ✓  bybit results: compressed $((COUNT - 30)) old files → archive/")
  else
    REPORT+=("  ✓  bybit results: $COUNT files (under limit, no action)")
  fi
fi

# 3. Social-factory channel logs: keep last 14 days, compress older runs
log "Rotating social-factory logs..."
for ch_dir in "$HOME_DIR/apps/social-factory/channels"/*/logs/; do
  ch=$(basename "$(dirname "$ch_dir")")
  OLD=$(find "$ch_dir" -maxdepth 1 -name "*.log" -mtime +14 2>/dev/null | wc -l)
  if [ "$OLD" -gt 0 ]; then
    ARCHIVE="$HOME_DIR/archive/sf-logs-${ch}-$(date -u +%Y%m).tar.gz"
    find "$ch_dir" -maxdepth 1 -name "*.log" -mtime +14 -exec tar -czf "$ARCHIVE" {} + 2>/dev/null && \
    find "$ch_dir" -maxdepth 1 -name "*.log" -mtime +14 -delete 2>/dev/null
    REPORT+=("  ✓  $ch logs: archived $OLD old log files")
  fi
done

# 4. Inbox session briefs: keep last 14, delete older ones
BRIEF_COUNT=$(ls "$HOME_DIR/inbox/session-"*-brief.md 2>/dev/null | wc -l)
if [ "$BRIEF_COUNT" -gt 14 ]; then
  TO_DEL=$((BRIEF_COUNT - 14))
  ls -t "$HOME_DIR/inbox/session-"*-brief.md 2>/dev/null | tail -n "$TO_DEL" | xargs rm -f 2>/dev/null
  REPORT+=("  ✓  session briefs: removed $TO_DEL old briefs (kept 14)")
fi

# 5. Disk state report
DISK_PCT=$(df "$HOME_DIR" | awk 'NR==2{print $5}' | tr -d '%')
DISK_FREE=$(df -h "$HOME_DIR" | awk 'NR==2{print $4}')
DISK_FREE_GB=$(df -BG "$HOME_DIR" | awk 'NR==2{gsub("G","",$4); print $4}')

log "=== disk-cleanup done — freed ~${FREED}MB ==="
log "Disk now: $DISK_FREE free ($DISK_PCT% used)"

# Print report
echo ""
echo "  Disk Cleanup — $(date -u '+%Y-%m-%d')"
echo "  ─────────────────────────────────────"
for line in "${REPORT[@]}"; do echo "$line"; done
echo ""
echo "  Freed:  ~${FREED}MB"
echo "  Disk:   $DISK_FREE free ($DISK_PCT% used)"
echo ""

# Alert if still critical after cleanup
if [ "${DISK_FREE_GB:-99}" -lt 3 ] 2>/dev/null; then
  note "⚠ Disk still low after cleanup: $DISK_FREE free ($DISK_PCT%). Manual review needed — check ~/.hermes/ and apps/envs/ for unused venvs."
fi
