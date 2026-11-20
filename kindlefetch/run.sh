#!/bin/sh

root="$(dirname "$(readlink -f "$0")")"
base="${KINDLEFETCH_BASE_DIR:-/mnt/us}"
if pidof reader.lua >/dev/null 2>&1; then
    echo "In KOReader, open Search → Kindle Fetch → Open KindleFetch."
    exit 0
fi
sh "$root/register-gui.sh" || exit 1
KINDLEFETCH_OPEN_REQUEST="$(mktemp /var/tmp/kindlefetch-open.XXXXXX)" || exit 1
export KINDLEFETCH_OPEN_REQUEST
trap 'rm -f "$KINDLEFETCH_OPEN_REQUEST"' EXIT
library="$base/Books"
[ -d "$library" ] || library="$base"
"$base/koreader/koreader.sh" --kual --asap "$library"
