#!/bin/sh

# KindleFetch
# Made by justrals
# https://github.com/justrals/KindleFetch

# Variables
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Use bundled modern curl (system curl fails TLS with current mirrors)
export PATH="$SCRIPT_DIR/curl:$PATH"
CONFIG_FILE="$SCRIPT_DIR/kindlefetch_config"
LINK_CONFIG_FILE="$SCRIPT_DIR/link_config"
VERSION_FILE="$SCRIPT_DIR/.version"
ZLIB_COOKIES_FILE="$SCRIPT_DIR/zlib_cookies.txt"
TMP_DIR="/tmp"
BASE_DIR="/mnt/us"

UPDATE_AVAILABLE=false
CREATE_SUBFOLDERS=false
COMPACT_OUTPUT=false
RESULTS_PER_PAGE=10

# LibGen's front end currently serves a placeholder page to unknown/default
# curl identities. Keep the working client identity in one place so search and
# download requests reach the real application.
KINDLEFETCH_USER_AGENT="${KINDLEFETCH_USER_AGENT:-libgen-downloader/3.3.5}"
MIRROR_CONFIG_URL="${MIRROR_CONFIG_URL:-https://raw.githubusercontent.com/obsfx/libgen-downloader/configuration/config.v3.json}"
RK_HARDENING_DIR="${RK_HARDENING_DIR:-$BASE_DIR/extensions/kindlefetch-rk-hardening}"
MIRROR_CONFIG_CACHE="$RK_HARDENING_DIR/mirror-config.cache"
LAST_WORKING_LGLI_FILE="$RK_HARDENING_DIR/last-working-lgli"

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

# Script imports
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
        read -r choice
        
        case "$choice" in
            1)
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

trap cleanup EXIT
main_menu
