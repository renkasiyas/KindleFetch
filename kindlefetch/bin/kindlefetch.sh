#!/bin/bash

# KindleFetch
# Made by justrals
# https://github.com/justrals/KindleFetch

# Variables
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

. "$SCRIPT_DIR/app_env.sh"

# Check if running on a Kindle
if ! { [ -f "/etc/prettyversion.txt" ] || [ -d "/mnt/us" ] || pgrep "lipc-daemon" >/dev/null; }; then
    echo -n "This script must run on a Kindle device. Do you want to run it anyway? [y/N]: "
    read -r kindle_override_choice
    if [ "$kindle_override_choice" = "y" ] || [ "$kindle_override_choice" = "Y" ]; then
        :
    else
        exit 1
    fi
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kindlefetch-terminal.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT

# Script imports
. "$SCRIPT_DIR/catalog.sh"
. "$SCRIPT_DIR/downloads/zlib_download.sh"
. "$SCRIPT_DIR/downloads/lgli_download.sh"
. "$SCRIPT_DIR/filters.sh"
. "$SCRIPT_DIR/search.sh"
. "$SCRIPT_DIR/lgli_search.sh"
. "$SCRIPT_DIR/misc.sh"
. "$SCRIPT_DIR/local_books.sh"
. "$SCRIPT_DIR/update.sh"
. "$SCRIPT_DIR/setup.sh"
. "$SCRIPT_DIR/settings.sh"
trap 'lgli_torrent_cleanup; rm -rf "$TMP_DIR"' EXIT

echo "Starting KindleFetch…"
check_for_updates
load_config
refresh_lgli_config

[ -z "$ANNAS_URL" ] && ANNAS_URL=$(find_working_url $ANNAS_MIRROR_URLS)
[ -z "$LGLI_URL" ] && LGLI_URL=$(first_lgli_mirror)
[ -z "$ZLIB_URL" ] && ZLIB_URL=$(find_working_url $ZLIB_MIRROR_URLS)
[ -z "$SEARCH_SOURCE" ] && SEARCH_SOURCE="auto"

save_config

main_menu() {
    if [ "${ENFORCE_DNS}" = true ];
    	then change_dns
    fi
    
    while true; do
        clear
        echo -e "
 _  ___           _ _      ______   _       _     
| |/ (_)         | | |    |  ____| | |     | |    
| ' / _ _ __   __| | | ___| |__ ___| |_ ___| |__  
|  < | | '_ \ / _\` | |/ _ \  __/ _ \ __/ __| '_ \\ 
| . \| | | | | (_| | |  __/ | |  __/ || (__| | | |
|_|\_\_|_| |_|\__,_|_|\___|_|  \___|\__\___|_| |_|
                                                
$(load_version) | https://github.com/renkasiyas/KindleFetch
"
        if $UPDATE_AVAILABLE; then
            echo "Update available! Select option 6 to install."
            echo ""
        fi
        echo "1. Search and download books"
        echo "2. Filter search results"
        echo "3. List my books"
        echo "4. Settings"
        echo "q. Exit"
        if $UPDATE_AVAILABLE; then
            echo ""
            echo "6. Install update"
        fi
        echo ""
        echo -n "Choose option: "
        read -r choice || exit 0
        
        case "$choice" in
            1)
                [ ! -f "$CONFIG_FILE" ] || . "$CONFIG_FILE"
                search_books
                ;;
            2)
                filters_menu
                ;;
            3)
                list_local_books
                ;;
            4)
                settings_menu
                ;;
            [qQ])
                cleanup
                exit 0
                ;;
            6)  
                if $UPDATE_AVAILABLE; then
                    update
                fi
                ;;
            *)
                echo "Invalid option"
                sleep 2
                ;;
        esac
    done
}

main_menu
