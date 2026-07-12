#!/usr/bin/env bash
# ~/.config/sway/scripts/spotlight.sh
#
# Alt+Space launcher: searches installed apps and everything under $HOME by
# name. Typing a bare extension like ".md" surfaces every matching file for
# free — no special-casing needed, it's just a substring match against a
# candidate list that already contains full filenames.
#
# Deliberately indexes $HOME, not the whole filesystem: that's both what
# "spotlight" behavior actually means in practice (your files, not every
# library file under /usr) and what keeps the candidate list small enough for
# wofi to filter instantly as you type instead of choking on a
# whole-disk index.
#
# Requires: plocate, wofi, xdg-utils (already in packages.x86_64)

set -euo pipefail

CACHE_DIR="$HOME/.cache/marcus-spotlight"
DB="$CACHE_DIR/home.db"
mkdir -p "$CACHE_DIR"

if ! command -v plocate >/dev/null 2>&1 && ! command -v locate >/dev/null 2>&1; then
    notify-send "Marcus Mix" "spotlight.sh needs 'plocate' — add it to packages.x86_64" 2>/dev/null || true
    exit 1
fi

# Rebuild the home-directory index in the background if it's stale (>30 min)
# or missing. The search itself always runs against whatever index already
# exists, so a rebuild in progress never blocks a keystroke.
if [[ ! -f "$DB" ]] || [[ -n "$(find "$DB" -mmin +30 -print -quit 2>/dev/null)" ]]; then
    (
        updatedb \
            --database-root "$HOME" \
            --output "$DB" \
            --require-visibility 0 \
            --prunepaths "$HOME/.cache $HOME/.local/share/Trash" \
            --prunenames "node_modules .git .venv venv __pycache__ target dist build .next .nuxt" \
            2>/dev/null
    ) &
fi

TMP_MAP="$(mktemp)"
trap 'rm -f "$TMP_MAP"' EXIT

# --- Applications ---
for dir in /usr/share/applications "$HOME/.local/share/applications"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' f; do
        name=$(sed -n 's/^Name=//p' "$f" | head -n1)
        [[ "$(sed -n 's/^NoDisplay=//p' "$f" | head -n1)" == "true" ]] && continue
        exec_raw=$(sed -n 's/^Exec=//p' "$f" | head -n1 | sed 's/%[a-zA-Z]//g')
        [[ -z "$name" || -z "$exec_raw" ]] && continue
        printf ' %s\trun\t%s\n' "$name" "$exec_raw" >> "$TMP_MAP"
    done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
done

# --- Files (home-directory index) ---
if [[ -f "$DB" ]]; then
    locate_bin=$(command -v plocate || command -v locate)
    while IFS= read -r path; do
        [[ -e "$path" ]] || continue
        display="${path/#$HOME/~}"
        printf ' %s — %s\topen\t%s\n' "$(basename "$path")" "$display" "$path" >> "$TMP_MAP"
    done < <("$locate_bin" -d "$DB" -i '*' 2>/dev/null | head -n 8000)
fi

[[ -s "$TMP_MAP" ]] || { notify-send "Marcus Mix" "Nothing indexed yet — try again in a moment" 2>/dev/null || true; exit 0; }

choice=$(cut -f1 "$TMP_MAP" | wofi --dmenu \
    --matching fuzzy \
    --insensitive \
    --cache-file "$CACHE_DIR/wofi-frequency-cache" \
    --prompt "Spotlight" \
    --width 700 --height 460 \
    --allow-images)

[[ -z "$choice" ]] && exit 0

kind=$(awk -F'\t' -v c="$choice" '$1==c {print $2; exit}' "$TMP_MAP")
target=$(awk -F'\t' -v c="$choice" '$1==c {print $3; exit}' "$TMP_MAP")
[[ -z "$kind" ]] && exit 0

if [[ "$kind" == "open" ]]; then
    xdg-open "$target" >/dev/null 2>&1 &
else
    setsid bash -c "$target" >/dev/null 2>&1 &
fi
