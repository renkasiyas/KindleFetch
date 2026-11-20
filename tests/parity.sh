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
