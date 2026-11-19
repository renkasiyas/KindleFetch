#!/bin/sh

# Use bundled modern curl (system curl fails TLS with current mirrors)
export PATH="$SCRIPT_DIR/curl:$PATH"
CONFIG_FILE="$SCRIPT_DIR/kindlefetch_config"
LINK_CONFIG_FILE="$SCRIPT_DIR/link_config"
VERSION_FILE="$SCRIPT_DIR/.version"
ZLIB_COOKIES_FILE="$SCRIPT_DIR/zlib_cookies.txt"
BASE_DIR="${KINDLEFETCH_BASE_DIR:-/mnt/us}"
KINDLE_DOCUMENTS="$BASE_DIR/Books"
SEARCH_SOURCE=auto

UPDATE_AVAILABLE=false
CREATE_SUBFOLDERS=false
COMPACT_OUTPUT=false
RESULTS_PER_PAGE=10

# LibGen's front end currently serves a placeholder page to unknown/default
# curl identities. Keep the working client identity in one place so search and
# download requests reach the real application.
KINDLEFETCH_USER_AGENT="${KINDLEFETCH_USER_AGENT:-libgen-downloader/3.3.5}"
MIRROR_CONFIG_URL="${MIRROR_CONFIG_URL:-https://raw.githubusercontent.com/obsfx/libgen-downloader/configuration/config.v3.json}"
RK_HARDENING_DIR="${RK_HARDENING_DIR:-$BASE_DIR/extensions/kindlefetch-rk-hardening}"
MIRROR_CONFIG_CACHE="$RK_HARDENING_DIR/mirror-config.cache"
LAST_WORKING_LGLI_FILE="$RK_HARDENING_DIR/last-working-lgli"
