#!/bin/sh

set -eu
root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
json_module="${1:?Usage: tests/parity.sh /path/to/KOReader/common/dkjson.lua [lua-or-luajit]}"
lua_bin="$(command -v "${2:-lua}")"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
export KINDLEFETCH_BASE_DIR="$test_root"
mkdir -p "$test_root/extensions" "$test_root/koreader/common" "$test_root/Books"
cp -R "$root/kindlefetch" "$test_root/extensions/kindlefetch"
app="$test_root/extensions/kindlefetch"
ln -s "$lua_bin" "$test_root/koreader/luajit"
cp "$json_module" "$test_root/koreader/common/dkjson.lua"
mkdir -p "$app/bin/curl"
cp "$root/tests/catalog-curl.py" "$app/bin/curl/curl"
chmod +x "$app/bin/curl/curl"
printf '%s\n' 'SEARCH_SOURCE=auto' 'ANNAS_URL=https://annas-archive.example' > "$app/bin/kindlefetch_config"
python3 - "$test_root/fixture.epub" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("mimetype", "application/epub+zip")
    archive.writestr("META-INF/container.xml", "<container/>")
PY
for scenario in primary fallback; do
    rm -rf "$test_root/extensions/kindlefetch-rk-hardening/catalog-cache"
    KF_FIXTURE="$scenario" sh "$root/tests/terminal-fixture.sh"
    KF_FIXTURE="$scenario" "$lua_bin" "$root/tests/parity.lua"
    if [ "$scenario" = primary ]; then
        KF_FIXTURE=fallback sh "$app/bin/command.sh" search 'Pride & Prejudice?' 1 > "$test_root/session-result.json"
        python3 - "$test_root/terminal-result.json" "$test_root/session-result.json" <<'PYTHON'
from pathlib import Path
import json
import sys
terminal, gui = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
assert terminal == gui
PYTHON
        echo 'A changed provider response leaves the shared result snapshot intact.'
    fi
done

status=0
KF_FIXTURE=missing sh "$app/bin/command.sh" download 50 '' epub "$test_root/missing.epub.part" > "$test_root/missing.log" 2>&1 ||
    status=$?
test "$status" -eq 41
test ! -e "$test_root/missing.epub.part"
test -z "$(find "$test_root" -name 'missing.epub.part.kf.*' -print)"
echo 'Missing mirror files report a distinct error and leave no partial book.'

state="$test_root/extensions/kindlefetch-rk-hardening"
cat > "$state/aria2c" <<'SH'
#!/bin/sh
set -eu
hash="$(md5sum "$KINDLEFETCH_BASE_DIR/fixture.epub")"
hash="${hash%% *}"
for arg in "$@"; do
    case "$arg" in
        --show-files) printf '1|./batch/unrelated.epub\n2|./batch/%s\n' "$hash"; exit 0;;
        --dir=*) dir="${arg#--dir=}";;
        --select-file=*) selection="${arg#--select-file=}";;
    esac
done
test "$selection" = 2
mkdir -p "$dir/batch"
if [ "$KF_FIXTURE" = torrent-corrupt ]; then
    printf 'Not an EPUB\n' > "$dir/batch/$hash"
else
    cp "$KINDLEFETCH_BASE_DIR/fixture.epub" "$dir/batch/$hash"
fi
SH
chmod +x "$state/aria2c"
KF_FIXTURE=torrent sh "$app/bin/command.sh" download 50 '' epub "$test_root/torrent.epub.part" > "$test_root/torrent.log"
cmp "$test_root/torrent.epub.part" "$test_root/fixture.epub"
status=0
KF_FIXTURE=torrent-corrupt sh "$app/bin/command.sh" download 50 '' epub "$test_root/corrupt.epub.part" > "$test_root/corrupt.log" 2>&1 ||
    status=$?
test "$status" -eq 41
test ! -e "$test_root/corrupt.epub.part"
test -z "$(find "$test_root" -name '*.torrent.*' -type d -print)"
echo 'Torrent fallback selects only the matching file and rejects corrupt content.'

mkdir -p "$test_root/koreader/plugins/kindlefetch.koplugin"
printf '%s\n' 'return "old"' > "$test_root/koreader/plugins/kindlefetch.koplugin/main.lua"
sh "$app/register-gui.sh"
sh "$app/register-gui.sh"
cmp "$test_root/koreader/plugins/kindlefetch.koplugin/main.lua" "$app/bridge/main.lua"
test "$(find "$test_root/extensions/kindlefetch-rk-hardening" -name main.lua | wc -l | tr -d '[:space:]')" = 1
destination="$test_root/Books/Ren's books"
mkdir -p "$destination"
sh "$app/bin/command.sh" set-download-dir "$destination"
test "$(sh "$app/bin/command.sh" download-dir)" = "$destination"
echo 'GUI registration, rollback and shared library settings verified.'
