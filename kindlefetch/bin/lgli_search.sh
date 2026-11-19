#!/bin/sh

# LibGen's table-based index now returns a placeholder page. Query its live
# JSON catalog and keep KindleFetch's existing search-results contract.
lgli_search_fetch() {
    local query="$1"
    [ -n "$query" ] || return 1

    local endpoint="https://libgen.pw/api/search/by-params"
    local raw="$TMP_DIR/kindlefetch-lgli-response.$$"
    local books="$TMP_DIR/kindlefetch-lgli-books.$$"
    : > "$TMP_DIR/last_search_diagnostic"

    if ! curl -A "$KINDLEFETCH_USER_AGENT" -f -sS -L -G \
        --connect-timeout 5 --max-time 20 \
        --data-urlencode "query=$query" \
        --data-urlencode 'collection=fiction' \
        --data-urlencode 'from=0' \
        -o "$raw" "$endpoint"; then
        echo "$endpoint: connection failed" > "$TMP_DIR/last_search_diagnostic"
        rm -f "$raw" "$books"
        return 1
    fi

    if ! LUA_PATH='/mnt/us/koreader/common/?.lua;;' \
        /mnt/us/koreader/luajit "$SCRIPT_DIR/lgli_spa_json.lua" search "$raw" > "$books"; then
        echo "$endpoint: invalid response or no supported books" > \
            "$TMP_DIR/last_search_diagnostic"
        rm -f "$raw" "$books"
        return 1
    fi
    rm -f "$raw"

    local count
    count="$(grep -c '"title":' "$books")"
    if [ "$count" -le 0 ]; then
        rm -f "$books"
        return 1
    fi
    local last_page=$(( (count + RESULTS_PER_PAGE - 1) / RESULTS_PER_PAGE ))
    echo "$query" > "$TMP_DIR/last_search_query"
    echo 1 > "$TMP_DIR/last_search_page"
    echo "$last_page" > "$TMP_DIR/last_search_last_page"
    if [ "$last_page" -gt 1 ]; then
        echo true > "$TMP_DIR/last_search_has_next"
    else
        echo false > "$TMP_DIR/last_search_has_next"
    fi
    echo false > "$TMP_DIR/last_search_has_prev"
    echo 'LibGen (libgen.pw API)' > "$TMP_DIR/last_search_source"
    mv "$books" "$TMP_DIR/search_results.json"
    : > "$TMP_DIR/last_search_diagnostic"
    return 0
}
