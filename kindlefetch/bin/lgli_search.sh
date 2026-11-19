#!/bin/sh

# LibGen's table-based index now returns a placeholder page. Query its live
# JSON catalog and keep KindleFetch's existing search-results contract.
lgli_search_fetch() {
    local query="$1"
    [ -n "$query" ] || return 1

    local endpoint status=1
    local raw="$TMP_DIR/catalog-response.json"
    local books="$TMP_DIR/catalog-books.json"
    : > "$TMP_DIR/last_search_diagnostic"
    for endpoint in https://libgen.pw https://randombook.org https://libgen.me https://libgen.xyz; do
        if ! curl -A "$KINDLEFETCH_USER_AGENT" -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 5 --max-time 15 --get --data-urlencode "query=$query" \
            --data-urlencode 'collection=fiction' --data-urlencode 'from=0' \
            -o "$raw" "$endpoint/api/search/by-params"; then
            printf '%s\n' "$endpoint: connection failed" >> "$TMP_DIR/last_search_diagnostic"
            continue
        fi
        if lgli_read_response search "$raw" > "$books"; then
            status=0
            break
        else
            status=$?
        fi
        [ "$status" -eq 3 ] && return 3
        printf '%s\n' "$endpoint: invalid search response" >> "$TMP_DIR/last_search_diagnostic"
    done
    [ "$status" -eq 0 ] || return 1
    rm -f "$raw"

    local count
    count="$(catalog_lua count "$books")" || return 1
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
    printf 'LibGen (%s)\n' "$endpoint" > "$TMP_DIR/last_search_source"
    mv "$books" "$TMP_DIR/search_results.json"
    : > "$TMP_DIR/last_search_diagnostic"
    return 0
}
