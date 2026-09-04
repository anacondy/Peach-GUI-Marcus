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
#
# ---------------------------------------------------------------------------
# PERFORMANCE
# ---------------------------------------------------------------------------
# Building the candidate list means parsing every .desktop file in
# /usr/share/applications plus enumerating up to 8000 indexed paths. On a home
# directory with tens of thousands of files that is 100-300ms of work, which is
# far too slow for something whose entire purpose is to feel instant. So the
# assembled list is cached for five minutes and, once a cache exists, rebuilt in
# the BACKGROUND — the launcher always opens against whatever list is already
# there and never blocks on a keystroke. Only the very first invocation after
# boot has to wait.
#
# ---------------------------------------------------------------------------
# PRIVACY
# ---------------------------------------------------------------------------
# The index is built with --require-visibility 0, which indexes your files
# regardless of the permission bits on the directories containing them. That is
# what makes searching your own home work, but it also means the database is a
# complete map of every filename you own — worth having, worth not leaking. The
# database file is therefore created with umask 077 (mode 600) rather than the
# default 644. On a live ISO running as root this is mostly moot; on an
# installed system with more than one account it is not.
#
# ---------------------------------------------------------------------------
# TRUST ASSUMPTION
# ---------------------------------------------------------------------------
# Application entries are executed by taking the Exec= line out of a .desktop
# file and running it through `bash -c`. Those files live in
# /usr/share/applications and ~/.local/share/applications; writing to either
# already means you can run code as this user, so this is not an escalation
# path. It IS worth knowing that a hand-edited Exec= line containing a literal
# '%' can survive field-code stripping imperfectly — field codes are stripped by
# a bounded pattern rather than a blanket '%[a-zA-Z]' replacement, which used to
# corrupt any Exec line that contained a real percent sign.
set -euo pipefail

CACHE_DIR="$HOME/.cache/marcus-spotlight"
DB="$CACHE_DIR/home.db"
MAP="$CACHE_DIR/entries.tsv"
mkdir -p "$CACHE_DIR"

# Where to look for .desktop files. Unquoted on purpose: this is a word list.
APP_DIRS="${MARCUS_APP_DIRS:-/usr/share/applications
$HOME/.local/share/applications
/var/lib/flatpak/exports/share/applications}"

if ! command -v plocate >/dev/null 2>&1 && ! command -v locate >/dev/null 2>&1; then
    notify-send "Marcus Mix" "spotlight.sh needs 'plocate' — add it to packages.x86_64" 2>/dev/null || true
    exit 1
fi

# Rebuild the home-directory index in the background if it's stale (>30 min)
# or missing. The search itself always runs against whatever index already
# exists, so a rebuild in progress never blocks a keystroke.
if [[ ! -f "$DB" ]] || [[ -n "$(find "$DB" -mmin +30 -print -quit 2>/dev/null)" ]]; then
    (
        # umask here is what makes the database 600 — see PRIVACY above.
        umask 077
        updatedb \
            --database-root "$HOME" \
            --output "$DB" \
            --require-visibility 0 \
            --prunepaths "$HOME/.cache $HOME/.local/share/Trash $HOME/.mozilla $HOME/.local/share/flatpak" \
            --prunenames "node_modules .git .venv venv __pycache__ target dist build .next .nuxt .cargo .rustup" \
            2>/dev/null
    ) &
fi

build_map() {
    # --- Applications ---
    # Overridable so the launcher can be tested against a fixture directory, and
    # so a Flatpak-heavy install can add /var/lib/flatpak/exports/share/applications
    # without editing the script - that directory is already in the default list
    # set above, which is the kind of thing that gets missed when the paths are
    # buried in a for-loop literal.
    local dir f name exec_raw
    for dir in $APP_DIRS; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' f; do
            name=$(sed -n 's/^Name=//p' "$f" | head -n1)
            [[ "$(sed -n 's/^NoDisplay=//p' "$f" | head -n1)" == "true" ]] && continue
            # Strip only the real .desktop field codes (%f %F %u %U %i %c %k),
            # as whole tokens. A blanket 's/%[a-zA-Z]//g' also ate things like
            # `sh -c "sleep 0.5%"`.
            exec_raw=$(sed -n 's/^Exec=//p' "$f" | head -n1 \
                       | sed -E 's/%[fFuUick]( |$)/ /g')
            [[ -z "$name" || -z "$exec_raw" ]] && continue
            printf ' %s\trun\t%s\n' "$name" "$exec_raw"
        done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
    done

    # --- Files (home-directory index) ---
    local locate_bin path display
    if [[ -s "$DB" ]]; then
        locate_bin=$(command -v plocate || command -v locate)
        while IFS= read -r path; do
            [[ -e "$path" ]] || continue
            display="${path/#$HOME/~}"
            printf ' %s — %s\topen\t%s\n' "$(basename "$path")" "$display" "$path"
        done < <("$locate_bin" -d "$DB" -i '*' 2>/dev/null | head -n 8000)
    fi
}

map_is_stale() {
    [[ ! -s "$MAP" ]] && return 0
    [[ -n "$(find "$MAP" -mmin +5 -print -quit 2>/dev/null)" ]]
}

if map_is_stale; then
    if [[ -s "$MAP" ]]; then
        # Refresh out of band; open against the list we already have.
        ( build_map > "$MAP.tmp" && mv -f "$MAP.tmp" "$MAP" ) &
    else
        # First run after boot: there is nothing to open with, so wait once.
        build_map > "$MAP.tmp" && mv -f "$MAP.tmp" "$MAP"
    fi
fi

[[ -s "$MAP" ]] || { notify-send "Marcus Mix" "Nothing indexed yet — try again in a moment" 2>/dev/null || true; exit 0; }

# wofi exits non-zero when dismissed with Escape. Without `|| true`, `set -e`
# would tear the script down here rather than falling through to the empty-check.
choice=$(cut -f1 "$MAP" | wofi --dmenu \
    --matching fuzzy \
    --insensitive \
    --cache-file "$CACHE_DIR/wofi-frequency-cache" \
    --prompt "Spotlight" \
    --width 700 --height 460 \
    --allow-images) || true

[[ -z "${choice:-}" ]] && exit 0

kind=$(awk -F'\t' -v c="$choice" '$1==c {print $2; exit}' "$MAP")
target=$(awk -F'\t' -v c="$choice" '$1==c {print $3; exit}' "$MAP")
[[ -z "$kind" ]] && exit 0

if [[ "$kind" == "open" ]]; then
    xdg-open "$target" >/dev/null 2>&1 &
else
    setsid bash -c "$target" >/dev/null 2>&1 &
fi
