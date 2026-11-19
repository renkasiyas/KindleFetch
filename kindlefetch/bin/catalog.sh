#!/bin/sh

catalog_lua() {
    LUA_PATH="$BASE_DIR/koreader/common/?.lua;;" \
        "$BASE_DIR/koreader/luajit" "$SCRIPT_DIR/catalog_protocol.lua" "$@"
}

catalog_book_field() {
    catalog_lua field "$TMP_DIR/search_results.json" "$1" "$2"
}

catalog_search() (
    local query="$1" page="${2:-1}" source="${3:-$SEARCH_SOURCE}"
    local cache_root="$RK_HARDENING_DIR/catalog-cache"
    local filters="$SCRIPT_DIR/tmp/current_filter_params"
    local key snapshot lock staged='' waited=0 result=0
    if ! mkdir -p "$cache_root"; then
        catalog_query "$query" "$page" "$source"
        return $?
    fi
    key="$({
        printf '%s\0' "$query" "$page" "$source" "$RESULTS_PER_PAGE" "$ANNAS_URL" "$PROXY_URL"
        if [ -f "$filters" ]; then cat "$filters"; fi
    } | sha256sum)" || return 1
    snapshot="$cache_root/${key%% *}.json"
    lock="$snapshot.lock"
    while ! mkdir "$lock" 2>/dev/null; do
        if catalog_lua restore "$snapshot" "$TMP_DIR"; then return 0; fi
        waited=$((waited + 1))
        if [ "$waited" -ge 75 ]; then
            catalog_query "$query" "$page" "$source"
            return $?
        fi
        sleep 1
    done
    trap 'rmdir "$lock"; [ -z "$staged" ] || rm -f "$staged"' EXIT
    trap 'exit 1' HUP INT TERM
    if catalog_lua restore "$snapshot" "$TMP_DIR"; then return 0; fi

    catalog_query "$query" "$page" "$source" || result=$?
    if [ "$result" -eq 0 ] && staged="$(mktemp "$cache_root/.result.XXXXXX")"; then
        if catalog_lua snapshot "$TMP_DIR" > "$staged"; then
            mv "$staged" "$snapshot" && staged=''
        fi
        # Bound the cache without depending on a service or a running UI.
        ls -1t "$cache_root"/*.json 2>/dev/null | tail -n +41 |
            while IFS= read -r old; do rm -f "$old"; done
    fi
    return "$result"
)

catalog_query() {
    local query="$1" page="${2:-1}" source="${3:-$SEARCH_SOURCE}"
    [ -n "$query" ] || return 1
    rm -f "$TMP_DIR"/search_results.json "$TMP_DIR"/last_search_*
    # RK patch 2026-08-12: LibGen-first search dispatch.
    # SEARCH_SOURCE=auto (default): LibGen first, Anna's as fallback.
    # SEARCH_SOURCE=lgli: LibGen only. SEARCH_SOURCE=annas: Anna's only.
    local used_lgli=false lgli_status=1
    if [ "$source" != "annas" ] && [ "$page" -eq 1 ]; then
        if lgli_search_fetch "$query"; then
            used_lgli=true
        else
            lgli_status=$?
            if [ "$source" = "lgli" ]; then
                return "$lgli_status"
            fi
        fi
    fi

    [ "$used_lgli" = true ] && return 0
    if [ -z "$ANNAS_URL" ]; then
        ANNAS_URL="$(find_working_url $ANNAS_MIRROR_URLS)" || return "$lgli_status"
    fi
    local filters=""
    if [ -f "$SCRIPT_DIR"/tmp/current_filter_params ]; then
        filters=$(cat "$SCRIPT_DIR/tmp/current_filter_params")
    fi

    local search_url="$ANNAS_URL/search?${filters#&}"
    local html_content
    html_content="$(curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --connect-timeout 5 --max-time 20 \
        --get --data-urlencode "q=$query" --data-urlencode "page=$page" "$search_url")" || html_content=""
    if [ -z "$html_content" ] && [ -n "$PROXY_URL" ]; then
        html_content="$(curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --connect-timeout 5 --max-time 20 \
            -x "$PROXY_URL" --get --data-urlencode "q=$query" --data-urlencode "page=$page" "$search_url")" || html_content=""
    fi
    if [ -z "$html_content" ]; then
        printf '%s\n' "Anna's Archive: connection failed" >> "$TMP_DIR/last_search_diagnostic"
        return 1
    fi

    local last_page="$(echo "$html_content" | grep -oE 'page=[0-9]+"' | sort -t= -k2 -nr | head -1 | cut -d= -f2 | tr -d '"')"
    [ -z "$last_page" ] && last_page=1

    local has_prev=false
    [ "$page" -gt 1 ] && has_prev=true

    local has_next=false
    [ "$page" -lt "$last_page" ] && has_next=true

    echo "$query" > "$TMP_DIR"/last_search_query
    echo "$page" > "$TMP_DIR"/last_search_page
    echo "$last_page" > "$TMP_DIR"/last_search_last_page
    echo "$has_next" > "$TMP_DIR"/last_search_has_next
    echo "$has_prev" > "$TMP_DIR"/last_search_has_prev

    printf '%s' "$html_content" > "$TMP_DIR/anna-response.html"
    catalog_lua anna "$TMP_DIR/anna-response.html" "$ANNAS_URL" > "$TMP_DIR/search_results.json" || return 1
    echo "Anna's Archive ($ANNAS_URL)" > "$TMP_DIR"/last_search_source

    local book_count
    book_count="$(catalog_lua count "$TMP_DIR/search_results.json")" || return 1
    [ "$book_count" -gt 0 ] && return 0
    # A blocked or unexpected page is a provider error, not an empty catalog.
    if ! printf '%s' "$html_content" | grep -qiE 'no (results|search results)|0 results'; then
        printf '%s\n' "Anna's Archive: unexpected search response" >> "$TMP_DIR/last_search_diagnostic"
        return 1
    fi
    return 3
}
