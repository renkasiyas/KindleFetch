#!/bin/sh

KINDLEFETCH_RELEASE_REPO=renkasiyas/KindleFetch

rk_release_info() {
    local metadata
    metadata="$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 12 \
        "https://api.github.com/repos/$KINDLEFETCH_RELEASE_REPO/releases/latest")" || return 1
    printf '%s\n' "$metadata" | LUA_PATH="$BASE_DIR/koreader/common/?.lua;;" \
        "$BASE_DIR/koreader/luajit" "$SCRIPT_DIR/release_metadata.lua"
}

rk_release_is_newer() {
    awk -v old="$1" -v new="$2" '
        BEGIN {
            if (old !~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) exit 0
            split(substr(old, 2), installed, ".")
            split(substr(new, 2), available, ".")
            for (i = 1; i <= 3; i++) {
                if (available[i] + 0 != installed[i] + 0) exit !(available[i] + 0 > installed[i] + 0)
            }
            exit 1
        }'
}

check_for_updates() {
    local release
    UPDATE_AVAILABLE=false
    release="$(rk_release_info)" || return 1
    read -r RK_RELEASE_TAG RK_RELEASE_DIGEST <<EOF
$release
EOF
    if rk_release_is_newer "$(load_version)" "$RK_RELEASE_TAG"; then
        UPDATE_AVAILABLE=true
    fi
}

rk_install_release() (
    set -eu
    tag="$1"
    digest="$2"
    install_root="${3:-$(dirname "$SCRIPT_DIR")}"
    parent="$(dirname "$install_root")"
    mkdir -p "$parent"
    lock="$parent/.kindlefetch-update.lock"
    if ! mkdir "$lock"; then
        echo 'Another KindleFetch update has the install lock' >&2
        exit 1
    fi

    stage=''
    backup=''
    cleanup_release() {
        if [ -n "$backup" ] && [ ! -e "$install_root" ] && [ -d "$backup/kindlefetch" ]; then
            mv "$backup/kindlefetch" "$install_root" || true
        fi
        [ -z "$stage" ] || rm -rf "$stage"
        rmdir "$lock"
    }
    trap cleanup_release EXIT
    trap 'exit 1' HUP INT TERM

    stage="$(mktemp -d "$parent/.kindlefetch-update.XXXXXX")"
    zip="$stage/kindlefetch.zip"
    curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 120 \
        -o "$zip" "https://github.com/$KINDLEFETCH_RELEASE_REPO/releases/download/$tag/kindlefetch.zip"
    printf '%s  %s\n' "$digest" "$zip" | sha256sum -c -
    unzip -q "$zip" -d "$stage"
    next="$stage/kindlefetch"
    [ "$(cat "$next/bin/.version")" = "$tag" ] &&
        [ -f "$next/run.sh" ] && [ -f "$next/bin/kindlefetch.sh" ] &&
        [ -f "$next/bin/update.sh" ] && [ -f "$next/bin/release_metadata.lua" ] || exit 1
    sh -n "$next/bin/kindlefetch.sh"
    sh -n "$next/bin/update.sh"

    if [ -d "$install_root" ]; then
        # Keep device-specific state out of the release archive.
        for file in kindlefetch_config zlib_cookies.txt; do
            if [ -f "$install_root/bin/$file" ]; then
                cp -p "$install_root/bin/$file" "$next/bin/$file"
            fi
        done
        if [ -f "$install_root/bin/tmp/current_filter_params" ]; then
            mkdir -p "$next/bin/tmp"
            cp -p "$install_root/bin/tmp/current_filter_params" "$next/bin/tmp/current_filter_params"
        fi
        if [ -d "$install_root/bin/curl" ] && [ ! -d "$next/bin/curl" ]; then
            cp -Rp "$install_root/bin/curl" "$next/bin/curl"
        fi
        mkdir -p "$RK_HARDENING_DIR"
        backup="$(mktemp -d "$RK_HARDENING_DIR/release-backup.XXXXXX")"
        mv "$install_root" "$backup/kindlefetch"
    fi
    mv "$next" "$install_root"
    if [ -f "$install_root/register-gui.sh" ] && ! sh "$install_root/register-gui.sh"; then
        mv "$install_root" "$stage/failed-install"
        echo 'Could not register KindleFetch in KOReader' >&2
        exit 1
    fi
    printf 'Installed KindleFetch %s\n' "$tag"
    if [ -n "$backup" ]; then printf 'Previous installation: %s/kindlefetch\n' "$backup"; fi
)

update() {
    if [ "$UPDATE_AVAILABLE" != true ]; then
        echo "You're up-to-date!"
        return
    fi
    printf 'Install KindleFetch %s? [Y/n]: ' "$RK_RELEASE_TAG"
    read -r confirm
    case "$confirm" in
        ''|y|Y)
            if rk_install_release "$RK_RELEASE_TAG" "$RK_RELEASE_DIGEST"; then
                echo 'Reopen KindleFetch to use the updated version.'
                exit 0
            fi
            echo 'Update failed. The current installation is available.' >&2
            return 1
            ;;
    esac
}
