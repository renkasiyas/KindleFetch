#!/bin/sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
. "$SCRIPT_DIR/app_env.sh"
. "$SCRIPT_DIR/misc.sh"
. "$SCRIPT_DIR/catalog.sh"
. "$SCRIPT_DIR/lgli_search.sh"
. "$SCRIPT_DIR/downloads/lgli_download.sh"
. "$SCRIPT_DIR/update.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kindlefetch-backend.XXXXXX")" || exit 1
partial=''
cleanup_command() {
    rm -rf "$TMP_DIR"
    [ -z "$partial" ] || rm -f "$partial"
}
trap cleanup_command EXIT
trap 'exit 1' HUP INT TERM
eval "$(base64 -d < "$LINK_CONFIG_FILE")"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

case "$1" in
    search)
        case "$3" in ''|*[!0-9]*|0) exit 2;; esac
        refresh_lgli_config
        status=0
        catalog_search "$2" "$3" || status=$?
        catalog_lua reply "$TMP_DIR" "$status"
        ;;
    download)
        case "$5" in /*.part) ;; *) exit 2;; esac
        refresh_lgli_config
        partial="$(mktemp "$5.kf.XXXXXX")" || exit 1
        lgli_fetch_book "$2" "$3" "$4" "$partial" || exit 1
        mv "$partial" "$5"
        ;;
    update-check)
        check_for_updates || exit 1
        if [ "$UPDATE_AVAILABLE" = true ]; then printf '%s\n' "$RK_RELEASE_TAG"; else echo current; fi
        ;;
    update)
        check_for_updates || exit 1
        [ "$UPDATE_AVAILABLE" = true ] && [ "$2" = "$RK_RELEASE_TAG" ] || exit 1
        rk_install_release "$RK_RELEASE_TAG" "$RK_RELEASE_DIGEST"
        ;;
    download-dir)
        printf '%s\n' "$KINDLE_DOCUMENTS"
        ;;
    set-download-dir)
        case "$2" in "$BASE_DIR"/*) ;; *) exit 2;; esac
        [ -d "$2" ] && [ -w "$2" ] || exit 1
        KINDLE_DOCUMENTS="$2"
        save_config
        ;;
    *)
        exit 2
        ;;
esac
