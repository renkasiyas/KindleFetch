#!/bin/sh

set -eu
base="${KINDLEFETCH_BASE_DIR:-/mnt/us}"
root="$(dirname "$(readlink -f "$0")")"
plugins="$base/koreader/plugins"
target="$plugins/kindlefetch.koplugin"
[ -x "$base/koreader/luajit" ] && [ -f "$root/gui/main.lua" ] || exit 1
mkdir -p "$plugins"
if cmp -s "$root/bridge/main.lua" "$target/main.lua" &&
   cmp -s "$root/bridge/_meta.lua" "$target/_meta.lua"; then
    exit 0
fi
stage="$(mktemp -d "$plugins/.kindlefetch-bridge.XXXXXX")"
backup=''
cleanup() {
    if [ -n "$backup" ] && [ ! -e "$target" ] && [ -d "$backup/kindlefetch.koplugin" ]; then
        mv "$backup/kindlefetch.koplugin" "$target" || true
    fi
    rm -rf "$stage"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$stage/kindlefetch.koplugin"
cp "$root/bridge/main.lua" "$root/bridge/_meta.lua" "$stage/kindlefetch.koplugin/"
if [ -e "$target" ]; then
    state="$base/extensions/kindlefetch-rk-hardening"
    mkdir -p "$state"
    backup="$(mktemp -d "$state/gui-backup.XXXXXX")"
    mv "$target" "$backup/kindlefetch.koplugin"
fi
mv "$stage/kindlefetch.koplugin" "$target"
