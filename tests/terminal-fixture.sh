#!/bin/sh
set -e
BASE_DIR="$KINDLEFETCH_BASE_DIR"
SCRIPT_DIR="$BASE_DIR/extensions/kindlefetch/bin"
TMP_DIR="$BASE_DIR/terminal"
mkdir -p "$TMP_DIR"
export TMP_DIR
. "$SCRIPT_DIR/app_env.sh"
. "$SCRIPT_DIR/misc.sh"
. "$SCRIPT_DIR/catalog.sh"
. "$SCRIPT_DIR/lgli_search.sh"
. "$SCRIPT_DIR/search.sh"
. "$SCRIPT_DIR/downloads/lgli_download.sh"
load_config
refresh_lgli_config
catalog_search 'Pride & Prejudice?' 1
catalog_lua reply "$TMP_DIR" 0 > "$BASE_DIR/terminal-result.json"
TERM=xterm display_books 1 false true 2 "$(cat "$TMP_DIR/last_search_source")" > "$BASE_DIR/terminal-display.txt"
if [ "$KF_FIXTURE" = primary ]; then
    printf '\n' | lgli_download 1 > "$BASE_DIR/terminal-download.log"
fi
