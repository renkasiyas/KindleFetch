#!/bin/sh

lgli_read_response() {
    LUA_PATH='/mnt/us/koreader/common/?.lua;;' \
        /mnt/us/koreader/luajit "$SCRIPT_DIR/lgli_spa_json.lua" "$@"
}

lgli_download_hash() {
    local id="$1" manifest="$2"
    local catalog hash
    for catalog in https://libgen.pw https://randombook.org; do
        if curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 15 -o "$manifest" "$catalog/api/download/links-by-id?id=$id" &&
            hash="$(lgli_read_response download-hash "$manifest")"; then
            printf '%s\n' "$hash"
            return 0
        fi
    done
    return 1
}

lgli_download_from_mirrors() {
    local hash="$1" format="$2" response="$3" partial="$4"
    local mirror link actual_hash tried=''
    for mirror in $LGLI_URL $LGLI_MIRROR_URLS https://libgen.li https://libgen.vg https://libgen.la; do
        mirror="${mirror%/}"
        is_valid_lgli_url "$mirror" || continue
        case " $tried " in *" $mirror "*) continue;; esac
        tried="$tried $mirror"
        printf '\nTrying %s\n' "$mirror"
        if ! curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 15 -o "$response" "$mirror/ads.php?md5=$hash" ||
            ! link="$(lgli_read_response mirror-link "$response")"; then
            continue
        fi
        if ! curl -A "$KINDLEFETCH_USER_AGENT" -fS -# -L --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 90 -o "$partial" "$mirror/$link"; then
            continue
        fi
        if ! validate_downloaded_book "$partial" "$format"; then
            echo 'The mirror returned an invalid book file' >&2
            continue
        fi
        actual_hash="$(md5sum "$partial")"
        if [ "${actual_hash%% *}" != "$hash" ]; then
            echo 'The file did not match the catalog checksum' >&2
            continue
        fi
        if [ "$format" = epub ] && ! unzip -t "$partial" >/dev/null 2>&1; then
            echo 'EPUB archive failed validation' >&2
            continue
        fi
        remember_working_lgli_url "$mirror" || true
        return 0
    done
    return 1
}

lgli_download() {
    local index="$1"
    [ -f "$TMP_DIR/search_results.json" ] || { echo 'No search results found' >&2; return 1; }
    local book_info
    book_info="$(awk -v i="$index" 'BEGIN{RS="\\{"; FS="\\}"} NR==i+1{print $1}' "$TMP_DIR/search_results.json")"
    [ -n "$book_info" ] || { echo 'Invalid book selection' >&2; return 1; }
    local id hash title format clean_title final_location book_folder
    id="$(get_json_value "$book_info" id)"
    hash="$(get_json_value "$book_info" md5 | tr '[:upper:]' '[:lower:]')"
    title="$(get_json_value "$book_info" title)"
    format="$(get_json_value "$book_info" format)"
    if ! printf '%s\n' "$hash" | grep -qE '^[0-9a-f]{32}$'; then
        hash=''
        case "$id" in ''|*[!0-9]*) echo 'Invalid book ID' >&2; return 1;; esac
    fi
    case "$format" in epub|azw3|mobi|pdf) :;; *) echo 'Unsupported book format' >&2; return 1;; esac
    [ -n "$title" ] || return 1

    printf '\nDownloading: %s\n' "$title"
    clean_title="$(sanitize_filename "$title" | tr -d ' ')"
    printf 'Do you want to change filename? [y/N]: '
    read -r confirm
    if [ "$confirm" = y ] || [ "$confirm" = Y ]; then
        printf 'Enter your custom filename: '
        read -r custom_filename
        [ -n "$custom_filename" ] && clean_title="$(sanitize_filename "$custom_filename" | tr -d ' ')"
    fi
    [ -n "$clean_title" ] || return 1
    [ -w "$KINDLE_DOCUMENTS" ] || { echo 'Books directory is not writable' >&2; return 1; }
    if [ "$CREATE_SUBFOLDERS" = true ]; then
        book_folder="$KINDLE_DOCUMENTS/$clean_title"
        mkdir -p "$book_folder" || return 1
        final_location="$book_folder/$clean_title.$format"
    else
        final_location="$KINDLE_DOCUMENTS/$clean_title.$format"
    fi
    if [ -e "$final_location" ]; then
        echo "Book already exists: $final_location" >&2
        return 1
    fi

    local response partial
    response="$(mktemp "$TMP_DIR/kindlefetch-lgli.XXXXXX")" || return 1
    if [ -z "$hash" ] && ! hash="$(lgli_download_hash "$id" "$response")"; then
        echo 'The catalog did not provide a checksum for this book' >&2
        rm -f "$response"
        return 1
    fi
    if ! partial="$(mktemp "$final_location.part.XXXXXX")"; then
        rm -f "$response"
        return 1
    fi
    if ! lgli_download_from_mirrors "$hash" "$format" "$response" "$partial"; then
        rm -f "$response" "$partial"
        echo 'None of the Library Genesis mirrors returned the verified book' >&2
        return 1
    fi
    rm -f "$response"
    if ! mv -n "$partial" "$final_location"; then
        rm -f "$partial"
        return 1
    fi
    if [ -e "$partial" ]; then
        rm -f "$partial"
        echo "Book already exists: $final_location" >&2
        return 1
    fi
    printf '\nDownload successful!\nSaved to: %s\n' "$final_location"
}
