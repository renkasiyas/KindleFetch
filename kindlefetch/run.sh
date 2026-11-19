#!/bin/sh

root="$(dirname "$(readlink -f "$0")")"
sh "$root/register-gui.sh" || echo "Could not register KindleFetch in KOReader" >&2

exec /mnt/us/extensions/kterm/bin/kterm -e "bash /mnt/us/extensions/kindlefetch/bin/kindlefetch.sh" -k 1 -o U -s 7
