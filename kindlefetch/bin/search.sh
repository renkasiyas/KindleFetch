#!/bin/sh

display_books() {
    clear
    echo -e "
  _____                     _     
 / ____|                   | |    
| (___   ___  __ _ _ __ ___| |__  
 \___ \ / _ \/ _\` | '__/ __| '_ \\ 
 ____) |  __/ (_| | | | (__| | | |
|_____/ \___|\__,_|_|  \___|_| |_|
"
    echo "--------------------------------"
    echo "Source: $(cat "$TMP_DIR"/last_search_source 2>/dev/null)"
    echo ""

    local page="$1" has_prev="$2" has_next="$3" last_page="$4" source="$5"
    local start=0
    case "$source" in LibGen*) start=$(( (page - 1) * RESULTS_PER_PAGE ));; esac
    catalog_lua render "$TMP_DIR/search_results.json" "$start" "$RESULTS_PER_PAGE" "$COMPACT_OUTPUT"

    echo "--------------------------------"
    echo ""
    echo "Page $page of $last_page"
    echo ""

    [ "$has_prev" = true ] && echo -n "p: Previous page | "
    echo -n "t[1-$last_page]: Select page | "
    [ "$has_next" = true ] && echo -n "n: Next page | "
    echo "1-$items_on_page: Select book | q: Quit"
    echo ""
}

search_books() {
    local query="$1"
    local page="${2:-1}"
    
    if [ -z "$query" ]; then
        echo -n "Enter search query: "
        read -r query
        [ -z "$query" ] && {
            echo "Search query cannot be empty"
            return 1
        }
    fi
    
    echo "Searching for '$query' (page $page)..."

    if ! catalog_search "$query" "$page"; then
        echo "No results were returned. Mirror diagnostics:"
        sed 's/^/  /' "$TMP_DIR/last_search_diagnostic" 2>/dev/null
        return 1
    fi

    while true; do
        local query="$(cat "$TMP_DIR"/last_search_query 2>/dev/null)"
        local current_page="$(cat "$TMP_DIR"/last_search_page 2>/dev/null || echo 1)"
        local last_page="$(cat "$TMP_DIR"/last_search_last_page 2>/dev/null || echo 1)"
        local has_next="$(cat "$TMP_DIR"/last_search_has_next 2>/dev/null || echo "false")"
        local has_prev="$(cat "$TMP_DIR"/last_search_has_prev 2>/dev/null || echo "false")"
        local catalog_source count
        catalog_source="$(cat "$TMP_DIR/last_search_source")"
        count="$(catalog_lua count "$TMP_DIR/search_results.json")" || return 1

        display_books "$current_page" "$has_prev" "$has_next" "$last_page" "$catalog_source"
        
        echo -n "Enter choice: "
        read -r choice
        
        case "$choice" in
            [qQ])
                return 0
                ;;
            [pP])
                if [ "$has_prev" = true ]; then
                    new_page=$((current_page - 1))
                    case "$catalog_source" in Anna*) catalog_search "$query" "$new_page" annas || return 1;; esac
                    echo "$new_page" > "$TMP_DIR"/last_search_page
                    has_prev="$([ "$new_page" -gt 1 ] && echo "true" || echo "false")"
                    has_next="$([ "$new_page" -lt "$last_page" ] && echo "true" || echo "false")"
                    echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
                    echo "$has_next" > "$TMP_DIR"/last_search_has_next
                    continue
                else
                    echo "Already on first page"
                    sleep 2
                fi
                ;;
            [nN])
                if [ "$has_next" = true ]; then
                    new_page=$((current_page + 1))
                    case "$catalog_source" in Anna*) catalog_search "$query" "$new_page" annas || return 1;; esac
                    echo "$new_page" > "$TMP_DIR"/last_search_page
                    has_prev="$([ "$new_page" -gt 1 ] && echo "true" || echo "false")"
                    has_next="$([ "$new_page" -lt "$last_page" ] && echo "true" || echo "false")"
                    echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
                    echo "$has_next" > "$TMP_DIR"/last_search_has_next
                    continue
                else
                    echo "Already on last page"
                    sleep 2
                fi
                ;;
            t[0-9]*)
                page_number="${choice#t}"
                if echo "$page_number" | grep -qE '^[0-9]+$'; then
                    if [ "$page_number" -ge 1 ] && [ "$page_number" -le "$last_page" ]; then
                        if [ "$page_number" -ne "$current_page" ]; then
                            case "$catalog_source" in Anna*) catalog_search "$query" "$page_number" annas || return 1;; esac
                            echo "$page_number" > "$TMP_DIR"/last_search_page
                            has_prev="$([ "$page_number" -gt 1 ] && echo "true" || echo "false")"
                            has_next="$([ "$page_number" -lt "$last_page" ] && echo "true" || echo "false")"
                            echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
                            echo "$has_next" > "$TMP_DIR"/last_search_has_next
                            continue
                        else
                            echo "You are already on page $current_page"
                            sleep 2
                        fi
                    else
                        echo "Page number out of range (1-$last_page)"
                        sleep 2
                    fi
                else
                    echo "Invalid input"
                    sleep 2
                fi
                ;;
            *)  
                if echo "$choice" | grep -qE '^[0-9]+$'; then
                    local start=0
                    case "$catalog_source" in LibGen*) start=$(( (current_page - 1) * RESULTS_PER_PAGE ));; esac
                    local end=$(( start + RESULTS_PER_PAGE - 1 ))
                    [ "$end" -ge "$count" ] && end=$((count - 1))
                    local items_on_page=$(( end - start + 1 ))

                    if [ "$choice" -ge 1 ] && [ "$choice" -le "$items_on_page" ]; then
                        absolute_index=$(( start + choice - 1 ))

                        local result_index=$((absolute_index + 1))
                        local description lgli_available=false zlib_available=false
                        description="$(catalog_book_field "$result_index" description)"
                        case "$(catalog_book_field "$result_index" id)" in
                            ''|*[!0-9]*) ;;
                            *) lgli_available=true;;
                        esac
                        case "$description" in *lgli*) lgli_available=true;; esac
                        case "$description" in *zlib*) zlib_available=true;; esac

                        while true; do
                            if [ "$lgli_available" = false ] && [ "$zlib_available" = false ]; then
                                echo "There are no available sources for this book right now."
                            fi

                            if [ "$lgli_available" = true ]; then
                                echo "1. lgli"
                            fi
                            if [ "$zlib_available" = true ]; then
                                if [ "$ZLIB_AUTH" = true ]; then
                                    echo "2. zlib"
                                else
                                    echo "2. zlib (Authentication required)"
                                fi
                            fi
                            echo "3. Cancel download"

                            echo -n "Choose source to proceed with: "
                            read -r source_choice

                            case "$source_choice" in
                                1)
                                    if [ "$lgli_available" = true ]; then
                                        echo "Proceeding with lgli..."
                                        if ! lgli_download "$((absolute_index + 1))"; then
                                            echo "Download from lgli failed."
                                            sleep 2
                                        else
                                            break
                                        fi
                                    else
                                        echo "Invalid choice."
                                    fi
                                    ;;
                                2)
                                    if [ "$zlib_available" = true ]; then
                                        if [ "$ZLIB_AUTH" = true ]; then
                                            echo "Proceeding with zlib..."
                                            if ! zlib_download "$((absolute_index + 1))"; then
                                                echo "Download from zlib failed."
                                                sleep 2
                                            else
                                                break
                                            fi
                                        else
                                            echo
                                            echo -n "Do you want to sign into your zlib account? [Y/n]: "
                                            read -r zlib_login_choice
                                            echo

                                            if [ "$zlib_login_choice" = "n" ] || [ "$zlib_login_choice" = "N" ]; then
                                                ZLIB_AUTH=false
                                                save_config
                                            else
                                                while true; do
                                                    echo -n "Zlib email: "
                                                    read -r zlib_email
                                                    echo -n "Zlib password: "
                                                    read -r zlib_password
                                                    echo

                                                    if zlib_login "$zlib_email" "$zlib_password"; then
                                                        ZLIB_AUTH=true
                                                        save_config

                                                        printf "\n\nProceeding with zlib..."
                                                        if ! zlib_download "$((absolute_index + 1))"; then
                                                            echo "Download from zlib failed."
                                                            sleep 2
                                                        else
                                                            break 2
                                                        fi
                                                    else
                                                        echo -n "Zlib login failed. Do you want to try again? [Y/n]: "
                                                        read -r zlib_login_retry_choice
                                                        echo
                                                        
                                                        if [ "$zlib_login_retry_choice" = "n" ] || [ "$zlib_login_retry_choice" = "N" ]; then
                                                            ZLIB_AUTH=false
                                                            save_config
                                                            break
                                                        fi
                                                    fi
                                                done
                                            fi
                                        fi
                                    else
                                        echo "Invalid choice."
                                    fi
                                    ;;
                                3)
                                    break
                                    ;;
                                *)
                                    echo "Invalid choice."
                                    ;;
                            esac
                        done

                        printf "\nPress any key to continue..."
                        read -n 1 -s
                    else
                        echo "Invalid selection (must be between 1 and $items_on_page)"
                        sleep 2
                    fi
                else
                    echo "Invalid input"
                    sleep 2
                fi
                ;;
        esac
    done
}
