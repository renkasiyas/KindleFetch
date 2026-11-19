#!/bin/sh

set -eu
root="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SCRIPT_DIR="$root/kindlefetch/bin"
BASE_DIR="${KINDLEFETCH_BASE_DIR:-/mnt/us}"
install_root="$BASE_DIR/extensions/kindlefetch"
RK_HARDENING_DIR="$BASE_DIR/extensions/kindlefetch-rk-hardening"
export PATH="$install_root/bin/curl:$PATH"

if [ ! -x "$BASE_DIR/koreader/luajit" ]; then
    echo 'KOReader’s Lua runtime is required for release updates.' >&2
    exit 1
fi
. "$SCRIPT_DIR/update.sh"
release="$(rk_release_info)"
read -r tag digest <<EOF
$release
EOF
rk_install_release "$tag" "$digest" "$install_root"
