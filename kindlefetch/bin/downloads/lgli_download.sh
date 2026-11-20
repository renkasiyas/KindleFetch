#!/bin/sh

lgli_read_response() {
    LUA_PATH="$BASE_DIR/koreader/common/?.lua;;" \
        "$BASE_DIR/koreader/luajit" "$SCRIPT_DIR/lgli_spa_json.lua" "$@"
}

lgli_download_hash() {
    local id="$1" manifest="$2"
    local catalog hash
    for catalog in $LGLI_CATALOG_URLS; do
        if curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 15 -o "$manifest" "$catalog/api/download/links-by-id?id=$id" &&
            hash="$(lgli_read_response download-hash "$manifest")"; then
            printf '%s\n' "$hash"
            return 0
        fi
    done
    return 1
}

lgli_check_book_file() {
    local partial="$1" format="$2" hash="$3" actual_hash
    if ! validate_downloaded_book "$partial" "$format"; then
        echo 'Received an invalid book file' >&2
        return 1
    fi
    actual_hash="$(md5sum "$partial")" || return 1
    if [ "${actual_hash%% *}" != "$hash" ]; then
        echo 'The file did not match the catalog checksum' >&2
        return 1
    fi
    if [ "$format" = epub ] && ! unzip -t "$partial" >/dev/null 2>&1; then
        echo 'EPUB archive failed validation' >&2
        return 1
    fi
}

lgli_torrent_cleanup() {
    if [ -n "${lgli_torrent_pid:-}" ]; then
        kill -TERM "$lgli_torrent_pid" 2>/dev/null || :
        wait "$lgli_torrent_pid" 2>/dev/null || :
        lgli_torrent_pid=''
    fi
    if [ -n "${lgli_torrent_dir:-}" ]; then
        rm -rf "$lgli_torrent_dir"
        lgli_torrent_dir=''
    fi
}

lgli_download_torrent() {
    local hash="$1" format="$2" response="$3" partial="$4"
    local client="$RK_HARDENING_DIR/aria2c"
    local mirror link selection status links='' seen=''
    [ -s "$client" ] || return 1

    for mirror in https://libgen.li https://libgen.vg https://libgen.bz; do
        if curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 12 --max-filesize 1048576 \
            -o "$response" "$mirror/file.php?md5=$hash"; then
            links="$(lgli_read_response torrent-links "$response")" || continue
            [ -n "$links" ] && break
        fi
    done
    [ -n "$links" ] || return 1
    lgli_torrent_dir="$(mktemp -d "$partial.torrent.XXXXXX")" || return 1

    for link in $links; do
        case " $seen " in *" $link "*) continue;; esac
        seen="$seen $link"
        if ! curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 20 --max-filesize 4194304 \
            -o "$lgli_torrent_dir/book.torrent" "$mirror$link"; then
            continue
        fi
        selection="$(LC_ALL=C "$client" --no-conf --show-files "$lgli_torrent_dir/book.torrent" |
            awk -F '|' -v hash="$hash" -v format="$format" '
                $1 ~ /^[0-9]+$/ && $2 ~ /^\.\/[a-zA-Z0-9_\/.\-]+$/ {
                    path = substr($2, 3)
                    count = split(path, components, "/")
                    if (path ~ /(^|\/)\.\.?($|\/)/ || path ~ /\/\//) next
                    file = tolower(components[count])
                    if (file == hash || file == hash "." format) { print $1 "|" path; exit }
                }')"
        [ -n "$selection" ] || continue

        printf '\nDownloading the matching file by torrent\n'
        "$client" --no-conf --dir="$lgli_torrent_dir" --select-file="${selection%%|*}" \
            --seed-time=0 --bt-stop-timeout=120 --bt-max-peers=24 --file-allocation=none \
            --bt-remove-unselected-file=true --dht-file-path="$RK_HARDENING_DIR/aria2-dht.dat" \
            --dht-file-path6="$RK_HARDENING_DIR/aria2-dht6.dat" --summary-interval=0 \
            --show-console-readout=false \
            "$lgli_torrent_dir/book.torrent" &
        lgli_torrent_pid=$!
        status=0
        wait "$lgli_torrent_pid" || status=$?
        lgli_torrent_pid=''
        if [ "$status" -eq 0 ] && lgli_check_book_file "$lgli_torrent_dir/${selection#*|}" "$format" "$hash" &&
            mv -f "$lgli_torrent_dir/${selection#*|}" "$partial"; then
            lgli_torrent_cleanup
            return 0
        fi
    done
    lgli_torrent_cleanup
    return 1
}

lgli_download_from_mirrors() {
    local hash="$1" format="$2" response="$3" partial="$4"
    local mirror link status tried='' missing=false
    for mirror in $LGLI_URL $LGLI_MIRROR_URLS https://libgen.li https://libgen.vg https://libgen.la; do
        mirror="${mirror%/}"
        is_valid_lgli_url "$mirror" || continue
        case "$mirror" in https://libgen.pw|https://libgen.me|https://libgen.xyz) continue;; esac
        case " $tried " in *" $mirror "*) continue;; esac
        tried="$tried $mirror"
        printf '\nTrying %s\n' "$mirror"
        if ! curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 15 -o "$response" "$mirror/ads.php?md5=$hash" ||
            ! link="$(lgli_read_response mirror-link "$response")"; then
            continue
        fi
        : > "$partial" || return 1
        status=0
        curl -A "$KINDLEFETCH_USER_AGENT" --fail-with-body -S -# -L --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 90 --speed-limit 1 --speed-time 12 \
            -o "$partial" "$mirror/$link" || status=$?
        if [ "$status" -ne 0 ]; then
            if [ "$status" -eq 22 ] && head -c 512 "$partial" | grep -Fqi 'File not found'; then
                missing=true
            fi
            continue
        fi
        lgli_check_book_file "$partial" "$format" "$hash" || continue
        remember_working_lgli_url "$mirror" || true
        return 0
    done
    if [ "$missing" = true ]; then return 41; fi
    return 1
}

lgli_fetch_book() {
    local id="$1" hash="$2" format="$3" partial="$4"
    local response="$TMP_DIR/download-response" status=0
    hash="$(printf '%s' "$hash" | tr '[:upper:]' '[:lower:]')"
    case "$format" in epub|azw3|mobi|pdf) :;; *) return 1;; esac
    if ! printf '%s\n' "$hash" | grep -qE '^[0-9a-f]{32}$'; then
        case "$id" in ''|*[!0-9]*) return 1;; esac
        if ! hash="$(lgli_download_hash "$id" "$response")"; then
            echo 'The catalog did not provide a checksum for this book' >&2
            return 40
        fi
    fi
    lgli_download_from_mirrors "$hash" "$format" "$response" "$partial" || status=$?
    if [ "$status" -ne 0 ] && lgli_download_torrent "$hash" "$format" "$response" "$partial"; then
        return 0
    fi
    case "$status" in
        0) return 0;;
        41) echo 'A Library Genesis mirror reported this edition missing. No mirror delivered it.' >&2;;
        *) echo 'None of the Library Genesis mirrors returned the verified book' >&2;;
    esac
    return "$status"
}

lgli_download() {
    local index="$1"
    [ -f "$TMP_DIR/search_results.json" ] || { echo 'No search results found' >&2; return 1; }
    local id hash title format clean_title final_location book_folder
    id="$(catalog_book_field "$index" id)"
    hash="$(catalog_book_field "$index" md5)"
    title="$(catalog_book_field "$index" title)"
    format="$(catalog_book_field "$index" format | tr '[:upper:]' '[:lower:]')"
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

    local partial
    partial="$(mktemp "$final_location.part.XXXXXX")" || return 1
    if ! lgli_fetch_book "$id" "$hash" "$format" "$partial"; then
        rm -f "$partial"
        return 1
    fi
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
