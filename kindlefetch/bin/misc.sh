#!/bin/sh

change_dns () {
    RESOLV_FILE="/var/run/resolv.conf"
    
    if [ ! -f "$RESOLV_FILE" ]; then
        exit 1
    fi

    sed -i '/^nameserver/d' "$RESOLV_FILE"

    echo "nameserver 1.1.1.1" >> "$RESOLV_FILE"
    echo "nameserver 1.0.0.1" >> "$RESOLV_FILE"
}

is_valid_lgli_url() {
    echo "$1" | grep -Eq '^https://libgen\.[A-Za-z0-9.-]+/?$'
}

append_unique_lgli_url() {
    local candidate="${1%/}"
    is_valid_lgli_url "$candidate" || return 1
    case " $LGLI_REFRESHED_URLS " in
        *" $candidate "*) return 0 ;;
    esac
    LGLI_REFRESHED_URLS="$LGLI_REFRESHED_URLS $candidate"
}

refresh_lgli_config() {
    local bundled_urls="$LGLI_MIRROR_URLS"
    local config_payload=""
    local config_version=""
    local config_urls=""
    local cached_version=""
    local cached_urls=""
    local last_working=""
    local url

    LGLI_REFRESHED_URLS=""
    LGLI_CONFIG_STATUS="bundled"

    config_payload="$(curl -A "$KINDLEFETCH_USER_AGENT" -f -s -L \
        --connect-timeout 5 --max-time 10 "$MIRROR_CONFIG_URL")" || config_payload=""

    if [ -n "$config_payload" ]; then
        config_version="$(echo "$config_payload" | \
            grep -o -m 1 '"latest_version"[[:space:]]*:[[:space:]]*"[0-9.]*"' | \
            sed 's/.*"\([0-9][0-9.]*\)"/\1/')"
        config_urls="$(echo "$config_payload" | \
            grep -o '"src"[[:space:]]*:[[:space:]]*"https://libgen\.[A-Za-z0-9.-]*/\?"' | \
            sed 's/.*"\(https:[^"]*\)"/\1/')"

        if [ -n "$config_version" ] && [ -n "$config_urls" ]; then
            mkdir -p "$RK_HARDENING_DIR"
            {
                echo "version=$config_version"
                echo "$config_urls"
            } > "$MIRROR_CONFIG_CACHE.tmp.$$" && \
                mv "$MIRROR_CONFIG_CACHE.tmp.$$" "$MIRROR_CONFIG_CACHE"
            KINDLEFETCH_USER_AGENT="libgen-downloader/$config_version"
            LGLI_CONFIG_STATUS="live"
        else
            config_urls=""
        fi
    fi

    if [ -z "$config_urls" ] && [ -f "$MIRROR_CONFIG_CACHE" ]; then
        cached_version="$(sed -n 's/^version=\([0-9][0-9.]*\)$/\1/p' \
            "$MIRROR_CONFIG_CACHE" | head -1)"
        cached_urls="$(grep -E '^https://libgen\.[A-Za-z0-9.-]+/?$' \
            "$MIRROR_CONFIG_CACHE" 2>/dev/null)"
        if [ -n "$cached_version" ] && [ -n "$cached_urls" ]; then
            KINDLEFETCH_USER_AGENT="libgen-downloader/$cached_version"
            config_urls="$cached_urls"
            LGLI_CONFIG_STATUS="cache"
        fi
    fi

    if [ -f "$LAST_WORKING_LGLI_FILE" ]; then
        last_working="$(head -1 "$LAST_WORKING_LGLI_FILE")"
        append_unique_lgli_url "$last_working" || true
    fi
    for url in $config_urls $bundled_urls; do
        append_unique_lgli_url "$url" || true
    done

    LGLI_MIRROR_URLS="$(echo "$LGLI_REFRESHED_URLS" | sed 's/^ *//')"
}

first_lgli_mirror() {
    local url
    for url in $LGLI_MIRROR_URLS; do
        echo "$url"
        return 0
    done
    return 1
}

remember_working_lgli_url() {
    local url="${1%/}"
    is_valid_lgli_url "$url" || return 1
    mkdir -p "$RK_HARDENING_DIR"
    echo "$url" > "$LAST_WORKING_LGLI_FILE.tmp.$$" && \
        mv "$LAST_WORKING_LGLI_FILE.tmp.$$" "$LAST_WORKING_LGLI_FILE"
    LGLI_URL="$url"
}

load_config() {
    eval "$(base64 -d < "$LINK_CONFIG_FILE")"
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        first_time_setup
    fi
}

load_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "unknown"
    fi
}

sanitize_filename() {
    echo "$1" | sed -e 's/[^[:alnum:]\._-]/_/g' -e 's/ /_/g'
}

validate_downloaded_book() {
    local downloaded_file="$1"
    local downloaded_format="$(echo "$2" | tr '[:upper:]' '[:lower:]')"

    [ -s "$downloaded_file" ] || return 1

    # Mirrors sometimes return a successful HTTP response containing an HTML
    # or JSON error page. Never keep that response under a book extension.
    if head -c 512 "$downloaded_file" 2>/dev/null | \
        LC_ALL=C tr '[:upper:]' '[:lower:]' | \
        grep -Eq '<(!doctype[[:space:]]+html|html|head|body|div)([[:space:]>])|max_user_connections|alert-danger|"error"[[:space:]]*:'; then
        return 1
    fi

    case "$downloaded_format" in
        epub|cbz)
            [ "$(head -c 2 "$downloaded_file" 2>/dev/null)" = "PK" ]
            ;;
        cbr)
            [ "$(head -c 4 "$downloaded_file" 2>/dev/null)" = "Rar!" ]
            ;;
        azw|azw3|mobi)
            dd if="$downloaded_file" bs=1 skip=60 count=8 2>/dev/null | grep -q '^BOOKMOBI$'
            ;;
        pdf)
            [ "$(head -c 5 "$downloaded_file" 2>/dev/null)" = "%PDF-" ]
            ;;
        djvu|djv)
            [ "$(head -c 8 "$downloaded_file" 2>/dev/null)" = "AT&TFORM" ]
            ;;
        fb2|txt)
            return 0
            ;;
        *)
            # Unknown formats still have to be more than a tiny error payload.
            [ "$(wc -c < "$downloaded_file")" -gt 1024 ]
            ;;
    esac
}

get_json_value() {
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/" || \
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[^,}]*" | sed "s/\"$2\"[[:space:]]*:[[:space:]]*\([^,}]*\)/\1/"
}

ensure_config_dir() {
    local config_dir="$(dirname "$CONFIG_FILE")"
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi
}

cleanup() {
    rm -f "$TMP_DIR"/kindle_books.list \
          "$TMP_DIR"/kindle_folders.list \
          "$TMP_DIR"/search_results.json \
          "$TMP_DIR"/last_search_*
}

config_line() {
    local escaped
    escaped="$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
    printf "%s='%s'\n" "$1" "$escaped"
}

save_config() {
    local temp
    temp="$(mktemp "$CONFIG_FILE.XXXXXX")" || return 1
    {
        config_line KINDLE_DOCUMENTS "$KINDLE_DOCUMENTS"
        config_line CREATE_SUBFOLDERS "$CREATE_SUBFOLDERS"
        config_line DEBUG_MODE "$DEBUG_MODE"
        config_line COMPACT_OUTPUT "$COMPACT_OUTPUT"
        config_line ENFORCE_DNS "$ENFORCE_DNS"
        config_line ZLIB_AUTH "$ZLIB_AUTH"
        config_line ZLIB_USERNAME "$ZLIB_USERNAME"
        config_line RESULTS_PER_PAGE "$RESULTS_PER_PAGE"
        config_line SEARCH_SOURCE "$SEARCH_SOURCE"
        config_line ANNAS_URL "$ANNAS_URL"
        config_line LGLI_URL "$LGLI_URL"
        config_line ZLIB_URL "$ZLIB_URL"
    } > "$temp" && mv "$temp" "$CONFIG_FILE" || {
        rm -f "$temp"
        return 1
    }
}

zlib_login() {
    local zlib_login="$1"
    local zlib_password="$2"

    printf '\nLogging in to Z-Library...'

    local response="$(curl -s -c "$ZLIB_COOKIES_FILE" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: application/json" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -X POST -d "email=$zlib_login&password=$zlib_password" \
        "$ZLIB_URL/eapi/user/login")"

    local zlib_username="$(get_json_value "$response" "name" | tr -d '\r\n')"

    if [ -n "$zlib_username" ]; then
        printf "\nSuccessfully logged in as $zlib_username!"
        ZLIB_USERNAME="$zlib_username"
        sleep 2
    else
        printf "\nLogin failed." >&2
        printf "\n$response" | head -n1
        sleep 2
        return 1
    fi
}

find_working_url() {
    for url in "$@"; do
        code=$(curl -A "$KINDLEFETCH_USER_AGENT" -s -o /dev/null -w '%{http_code}' \
               --max-time 2 -L "$url")

        [ "$code" = "000" ] && continue
        [ "$code" -ge 400 ] && continue

        echo "$url"
        return 0
    done
    return 1
}

find_working_lgli_url() {
    local url
    local html_content
    for url in "$@"; do
        url="${url%/}"
        is_valid_lgli_url "$url" || continue
        html_content="$(curl -A "$KINDLEFETCH_USER_AGENT" -f -s -L \
            --connect-timeout 5 --max-time 15 \
            "$url/index.php?req=pride+and+prejudice&res=1&curtab=f")" || \
            html_content=""
        echo "$html_content" | grep -q 'tablelibgen' || continue
        echo "$url"
        return 0
    done
    return 1
}
