#!/bin/bash
# relocator.sh — auto-move misplaced files/dirs to the correct zone
# Runs every 15 min via cron. Logs all moves to ~/documents/changelog.md.

HOME_DIR="/home/ubuntu"
CHANGELOG="$HOME_DIR/documents/changelog.md"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

ALLOWED="AGENT.md CLAUDE.md README.md apps archive bin documents downloads inbox keys legal media projects renderer scripts snap system tg-agent-env venv yt-upload-venv antigravity-bot-venv"

moved=0

log_move() {
  local from="$1" to="$2"
  echo "- [$NOW] Auto-relocated: $from → $to" >> "$CHANGELOG"
  echo "[relocator] moved: $from → $to"
}

# ── file extension rules ──────────────────────────────────────────────────────
move_file() {
  local path="$1"
  local name="$2"
  local ext="${name##*.}"
  local dest=""

  case "${ext,,}" in
    jpg|jpeg|png|gif|webp|svg|ico|bmp|tiff)
      dest="$HOME_DIR/media/images" ;;
    mp4|mov|avi|mkv|webm|m4v|flv)
      dest="$HOME_DIR/media/videos" ;;
    mp3|wav|ogg|flac|aac|m4a|opus)
      dest="$HOME_DIR/media/audio" ;;
    pdf|doc|docx|odt|epub)
      dest="$HOME_DIR/documents" ;;
    zip|tar|gz|bz2|xz|rar|7z)
      dest="$HOME_DIR/downloads" ;;
    sh)
      dest="$HOME_DIR/scripts" ;;
    log)
      mkdir -p "$HOME_DIR/documents/logs"
      dest="$HOME_DIR/documents/logs" ;;
    md|txt)
      if [[ "$name" != "AGENT.md" && "$name" != "CLAUDE.md" && "$name" != "README.md" ]]; then
        dest="$HOME_DIR/documents"
      fi ;;
    json|py|js|ts|yaml|yml|toml|env|cfg|conf)
      dest="$HOME_DIR/downloads" ;;
    *)
      dest="$HOME_DIR/downloads" ;;
  esac

  if [ -n "$dest" ]; then
    mkdir -p "$dest"
    mv "$path" "$dest/$name" 2>/dev/null && log_move "~/$name" "${dest#$HOME_DIR/}/$name" && moved=$((moved+1))
  fi
}

# ── directory type detection ──────────────────────────────────────────────────
move_dir() {
  local path="$1"
  local name="$2"
  local dest=""

  if [ -f "$path/package.json" ] || [ -f "$path/tsconfig.json" ] || [ -f "$path/next.config.js" ] || [ -f "$path/next.config.ts" ]; then
    if ls "$path" | grep -qiE "bot|agent|daemon|server" 2>/dev/null || [[ "$name" =~ bot|agent|daemon ]]; then
      dest="$HOME_DIR/apps"
    else
      dest="$HOME_DIR/projects"
    fi
  elif [ -f "$path/main.py" ] || [ -f "$path/bot.py" ] || [ -f "$path/agent.py" ] || [ -f "$path/app.py" ]; then
    dest="$HOME_DIR/apps"
  elif [ -f "$path/.git" ] || [ -d "$path/.git" ]; then
    dest="$HOME_DIR/projects"
  elif ls "$path" | grep -qiE "\.sh$" 2>/dev/null; then
    dest="$HOME_DIR/scripts"
  else
    dest="$HOME_DIR/downloads"
  fi

  mkdir -p "$dest"
  mv "$path" "$dest/$name" 2>/dev/null && log_move "~/$name/" "${dest#$HOME_DIR/}/$name/" && moved=$((moved+1))
}

# ── scan root ─────────────────────────────────────────────────────────────────
for item in "$HOME_DIR"/* "$HOME_DIR"/.[!.]*; do
  [ -e "$item" ] || continue
  name=$(basename "$item")

  [[ "$name" == .* ]] && continue
  echo "$ALLOWED" | grep -qw "$name" && continue

  if [ -L "$item" ]; then
    echo "- [$NOW] WARNING: unknown symlink at root: ~/$name" >> "$CHANGELOG"
    continue
  fi

  if [ -f "$item" ]; then
    move_file "$item" "$name"
  elif [ -d "$item" ]; then
    move_dir "$item" "$name"
  fi
done

# ── scan wrong locations (media dropped into documents/downloads) ──────────────
while IFS= read -r f; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  src_dir=$(dirname "$f")
  ext="${name##*.}"
  case "${ext,,}" in
    jpg|jpeg|png|gif|webp|svg|ico)
      mkdir -p "$HOME_DIR/media/images"
      mv "$f" "$HOME_DIR/media/images/$name" && log_move "${src_dir#$HOME_DIR/}/$name" "~/media/images/$name" && moved=$((moved+1)) ;;
    mp4|mov|avi|mkv|webm)
      mkdir -p "$HOME_DIR/media/videos"
      mv "$f" "$HOME_DIR/media/videos/$name" && log_move "${src_dir#$HOME_DIR/}/$name" "~/media/videos/$name" && moved=$((moved+1)) ;;
    mp3|wav|ogg|flac|aac)
      mkdir -p "$HOME_DIR/media/audio"
      mv "$f" "$HOME_DIR/media/audio/$name" && log_move "${src_dir#$HOME_DIR/}/$name" "~/media/audio/$name" && moved=$((moved+1)) ;;
  esac
done < <(find "$HOME_DIR/documents" "$HOME_DIR/downloads" -maxdepth 1 -type f 2>/dev/null)

[ "$moved" -gt 0 ] && echo "[relocator] $moved item(s) relocated" || true
