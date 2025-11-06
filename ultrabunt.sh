#!/bin/bash
# ==============================================================================
# ULTRABUNT ULTIMATE BUNTSTALLER v4.2.0
# Professional Ubuntu/Mint setup & buntage manager
# - Full system scan (APT, Snap, Flatpak, binaries)
# - Granular per-buntage control with visual status indicators
# - Safe uninstall with multiple confirmation layers
# - Stock-compatible Python (system python3 only, no custom builds)
# - Comprehensive logging and error handling
# - Repository management for third-party software
# ==============================================================================

# Check for bash version 4.0+ (required for associative arrays)
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "Error: This script requires Bash 4.0 or higher for associative arrays."
    echo "Current version: $BASH_VERSION"
    echo "Please run with: bash $0"
    exit 1
fi

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Configuration
LOGFILE="/var/log/ultrabunt.log"
BACKUP_DIR="/var/backups/ultrabunt"
PHP_VER="8.3"
NODE_LTS="20"

# Dialog box size configuration
DIALOG_HEIGHT=24
DIALOG_WIDTH=80
DIALOG_MENU_HEIGHT=14

# Dialog size presets
declare -A DIALOG_PRESETS
DIALOG_PRESETS[compact]="20 70 12"
DIALOG_PRESETS[standard]="24 80 14"
DIALOG_PRESETS[large]="30 100 18"
DIALOG_PRESETS[wide]="24 120 14"
DIALOG_PRESETS[tall]="35 80 20"
DIALOG_PRESETS[huge]="40 140 25"

# Current dialog preset
CURRENT_DIALOG_PRESET="standard"

# Cache for installed buntages - populated once at startup
declare -A INSTALLED_CACHE

# Session variables for database authentication

# ============================================================================== 
# TTS (Text-to-Speech) Integration for Accessibility
# ==============================================================================

# TTS function to speak text if accessibility mode is enabled
speak_if_enabled() {
    local text="$1"
    local priority="${2:-text}"
    
    # Only speak if TTS is enabled and spd-say is available
    if [[ "${ULTRABUNT_TTS_ENABLED:-false}" == "true" ]] && command -v spd-say >/dev/null 2>&1; then
        # Clean the text of ANSI color codes for speech
        local clean_text=$(echo "$text" | sed 's/\x1b\[[0-9;]*m//g')
        
        # Use the settings exported from the accessible script
        spd-say \
            --voice-type "${ULTRABUNT_TTS_VOICE:-female1}" \
            --rate "${ULTRABUNT_TTS_RATE:--20}" \
            --pitch "${ULTRABUNT_TTS_PITCH:-0}" \
            --volume "${ULTRABUNT_TTS_VOLUME:-10}" \
            --punctuation-mode "${ULTRABUNT_TTS_PUNCTUATION:-some}" \
            --priority "$priority" \
            --wait \
            "$clean_text" 2>/dev/null &
    fi
}

# Enhanced UI message function with TTS support
ui_msg_accessible() {
    local title="$1"
    local message="$2"
    local height="${3:-10}"
    local width="${4:-60}"
    
    # Speak the title and message
    speak_if_enabled "$title" "important"
    speak_if_enabled "$message"
    
    # Show the visual dialog
    dialog --title "$title" --msgbox "$message" "$height" "$width"
}

# Enhanced input function with TTS support
ui_input_accessible() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    local height="${4:-10}"
    local width="${5:-60}"
    
    # Speak the title and prompt
    speak_if_enabled "$title" "important"
    speak_if_enabled "$prompt"
    
    # Show the visual input dialog
    dialog --title "$title" --inputbox "$prompt" "$height" "$width" "$default"
}

# Enhanced menu function with TTS support
ui_menu_accessible() {
    local title="$1"
    local prompt="$2"
    local height="$3"
    local width="$4"
    local menu_height="$5"
    shift 5
    local options=("$@")
    
    # Speak the title and prompt
    speak_if_enabled "$title" "important"
    speak_if_enabled "$prompt"
    
    # Speak the available options
    if [[ "${ULTRABUNT_TTS_ENABLED:-false}" == "true" ]]; then
        speak_if_enabled "Available options:"
        local i=0
        while [ $i -lt ${#options[@]} ]; do
            local option_key="${options[$i]}"
            local option_text="${options[$((i+1))]}"
            speak_if_enabled "Option $option_key: $option_text"
            i=$((i+2))
            sleep 0.2  # Small pause between options
        done
        speak_if_enabled "Please make your selection"
    fi
    
    # Show the visual menu dialog
    dialog --title "$title" --menu "$prompt" "$height" "$width" "$menu_height" "${options[@]}"
}
MARIADB_SESSION_PASSWORD=""
MARIADB_SESSION_ACTIVE=false

# Selective loading configuration - categories to exclude
declare -A EXCLUDED_CATEGORIES
EXCLUDED_CATEGORIES=()

# Show ASCII art splash screen
show_ascii_splash() {
    # Clear screen
    clear
    
    # Get terminal dimensions
    local term_width=$(tput cols 2>/dev/null || echo "80")
    local term_height=$(tput lines 2>/dev/null || echo "24")
    
    # ASCII art width is 81 characters
    local ascii_width=81
    
    if [[ $ascii_width -gt $term_width ]]; then
        log "WARNING: ASCII art width ($ascii_width) exceeds terminal width ($term_width)"
        echo -e "${YELLOW}⚠️  Terminal too narrow for optimal display. Recommended width: ${ascii_width} columns${NC}"
        echo -e "${BLUE}💡 Try maximizing your terminal or reducing font size${NC}"
        echo ""
        sleep 2
    fi
    
    # Display ASCII art with scrolling effect
    echo -e "${GREEN}"
    
    # Embedded ASCII art (cleaner version - 81 characters wide)
    local ascii_lines=(
        "                                                                                 "
        "                  ...                                                            "
        "                :==-:.               -                                     "
        "              .=**+-.       :-.-#%%#*#%%%%%%%=                                  "
        "              -=*=+-.    :*%%#%#************#@+.                                 "
        "             .::=:-:...=%%#####****************#%=..                             "
        "             ..:::----#########****************####+.      .-:.                  "
        "             .::::----==++####****************#####*#=    .=*+-..                "
        "        -######**++==-==++*####***#%%#********###***+*+. .-#*+-.                 "
        "       .*%#####**++++*==++*##*****%@@@%*******####***+*+--==+*+.                 "
        "       :%#####***+++++%++*####***#@@%%@********##%@@%++*---==++                  "
        "       -%######*****+==%#####*#**#@@@@%*+++****#%@%*%*+*=-=++#-..              "
        "       *%######*****+==%%####****#%%%%#*++++***#%@@@@*+*###########+.            "
        "      +%#######****#++%######**********++++++***#%@@@*+****##########-           "
        "    .#%%########**#*##%######*#***#@@%#*+++++***##****++*#*##########=           "
        "   .#@%####%######%%%#########***#@@@@%**+++****#%%%*+++%**#########*.           "
        "    *%%###%%######%%%########****#@@@@@********##@@@%+++:###%#######=            "
        "  =*+*#%%#######*%#%%##########**#@@%%%********#%@@@@*+=..##########=            "
        " =*==-*#*#######: =%##########***#%%%%#********#%@%%@*+=.%**#######*:            "
        ":#++=*#*######### =%%%#######********####*****###%@@%++=#***######*:             "
        "+*===#################%#####***#**#%%*-*+:-+=+*###***+++****######*=:--..        "
        "=*--++-*%##########**+%#####*#****%%#*##***+=-=-.=#*++++****#####*+=:-*+=.       "
        " *=-=*-=#%%#%#*****+++*%######*####%%#*-+*-:+=-=--*%++++****#####=:..:**-.       "
        ":%%=-+*=+#%#*+*######%%%###########**########+-=-*%*++++****##+=*--:.:**=--:.    "
        "**%%%###*+==+#-   *%%%%#%#+=-----------==+*#######**+++*#%**#==-*+=:..+-.:*+=.   "
        "*--=*#%%%%%%%#-   *%%+:.......:.::::::::::::::::=##*+*%%%@%%=.+%#**-.....:+*=.   "
        ".*==++====--==    +=....:=###**++++*#%%#*+-::......:**+%*####++#*..:.:+=-.+*=.   "
        " *=**+++++*#+    .+..+#++***=#==****#+*#%##*#+:....=:*+**#%+###%##*****=-:=#=.   "
        ".+**##*++*+*-    .+-+=*%:==::#--++++#++#***#*#+:...--.:=++*=++##*+=*=   .:=#=.   "
        " .+=*##+=-+##=.. .+=+*=%:=+::#::++==#*+##*##*#-::. ...:-  :*+==+###**=   .=#=.   "
        "- .*####**=+#+**#+=:*#+#**+=======---=====+*+-:::.. -===:  .+==+***++%:   -*=.   "
        "=-. =++##**#=+#*++=....:::::::::::::::-++====-::::.+:+::-=-:-===+*#*=+*          "
        "#=::-+#%%*+*#*.:-+=..===+=+=::::::::=+=+=+*+++=:::=:*===::*-++=+++**#**          "
        "+*=:-=+-..+##*=++:=-*=*:::-*-::::::-*+*-:-=-:**:::+-+:--+-===+=+*+*+-#-          "
        "-+*-.:-....==+::-=--++----=%=::::::=*+=---==+#*:::-=+=*##-==+++=+##*=*           "
        ".=+*-..:=:..-+=++*--++--=++#-:::::::**=--=+++%-:::=#######+++++**++*#            "
        " :=++--+*+:..::::-=.-*+-==*+::::::::-*+-===+#+:::*##*===+###*++**+=-#.           "
        "  .....-+*=...--:-=..:-**+-:::::::::.:=***+=:....-#*==-::=#**+*+=-=+.            "
        "       .=+*=:=+++-=.....:::::::::::.................-=*+=+++*+--=#=              "
        "        .:--- :++*+......::...:::::.............=*+:..--+*=+*-==+*              "
        "                =+*......:......::..............-+=...++--=*..::==               "
        "                 .*=. ...........:................ ..:*++#==--:-+               "
        "                 .=*:..................... .....=#%#==--*===++*.                 "
        "                   :+:...::..::::.............-=*#+=#=     ::                    "
        "                  .:=*:...::::::::......  ...=%#+----:.                          "
        "                .:--::+*:..::::::............+#*-::::.:-.                        "
        "               :----:...+*:...:::.............:+*:..:....:                       "
        "                -:....    -##-:::::.:......:+#=     ......                       "
        " ██████   ██████   █████   █████   ████  ██████   █████████ ███████ ████████  "
        "░░██████ ██████  ███░░░███░░████ ░░██  ███░░░███░█░░░██░░█░░██░░░█░░███░░███ "
        " ░███░█████░███ ███   ░░███░██░██ ░██ ░███  ░░░ ░   ░██ ░  ░██ █   ░███ ░███ "
        " ░███░░███ ░███░███    ░███░██ ░██░██ ░░███████     ░██    ░████   ░██████  "
        " ░███ ░░░  ░███░███    ░███░██  ░████    ░░░░███    ░██    ░██░█   ░███░░███ "
        " ░███      ░███░░███  ███ ░███   ░███  ███  ░███    ░██    ░██   █ ░███ ░███ "
        " █████     █████░░░█████░  ████  ░████░░███████   █████   ███████ ████  ████"
        "░░░░░     ░░░░░   ░░░░░░   ░░░░░   ░░░  ░░░░░░░    ░░░░   ░░░░░░  ░░░░  ░░░░ "
        " ███████████     ███████   ███████████     ███████    ███████████           "
        "░░███░░░░░███  ███░░░░░███░░███░░░░░███  ███░░░░░███ ░█░░░███░░░█           "
        " ░███    ░███ ███     ░░███░███    ░███ ███     ░░███░   ░███  ░            "
        " ░██████████ ░███      ░███░██████████ ░███      ░███    ░███               "
        " ░███░░░░░███░███      ░███░███░░░░░███░███      ░███    ░███               "
        " ░███    ░███░░███     ███ ░███    ░███░░███     ███     ░███               "
        " █████   █████░░░███████░  ███████████  ░░░███████░      █████              "
        "░░░░░   ░░░░░   ░░░░░░░   ░░░░░░░░░░░     ░░░░░░░       ░░░░░               "
        "  █████████     ███████   ███████████ ███████████                           "
        " ███░░░░░███  ███░░░░░███░░███░░░░░░█░█░░░███░░░█                           "
        "░███    ░░░  ███     ░░███░███   █ ░ ░   ░███  ░                            "
        "░░█████████ ░███      ░███░███████       ░███                               "
        " ░░░░░░░░███░███      ░███░███░░░█       ░███                               "
        " ███    ░███░░███     ███ ░███  ░        ░███                               "
        "░░█████████  ░░░███████░  █████          █████                              "
    )
    
    # Display each line with scrolling effect
    for line in "${ascii_lines[@]}"; do
        echo "$line"
        sleep 0.05  # Small delay for scrolling effect
    done
    
    echo -e "${NC}"
    
    # Add some spacing and info
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     ULTRABUNT ULTIMATE BUNTSTALLER v4.2.0             ║${NC}"
    echo -e "${BLUE}║     Professional Ubuntu/Mint Setup & Package Manager  ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Brief pause before continuing
    sleep 1.5
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -dev|--no-dev)
                EXCLUDED_CATEGORIES["dev"]=1
                log "Excluding development category"
                ;;
            -wp|--no-wordpress)
                EXCLUDED_CATEGORIES["wordpress"]=1
                log "Excluding WordPress category"
                ;;
            -gaming|--no-gaming)
                EXCLUDED_CATEGORIES["gaming-platforms"]=1
                EXCLUDED_CATEGORIES["gaming-emulators"]=1
                log "Excluding gaming categories"
                ;;
            -ai|--no-ai)
                EXCLUDED_CATEGORIES["ai"]=1
                log "Excluding AI category"
                ;;
            -media|--no-media)
                EXCLUDED_CATEGORIES["multimedia"]=1
                EXCLUDED_CATEGORIES["music"]=1
                log "Excluding media categories"
                ;;
            -web|--no-web)
                EXCLUDED_CATEGORIES["web-browsers"]=1
                log "Excluding web browsers category"
                ;;
            -comm|--no-communication)
                EXCLUDED_CATEGORIES["communication"]=1
                log "Excluding communication category"
                ;;
            -office|--no-office)
                EXCLUDED_CATEGORIES["office"]=1
                log "Excluding office category"
                ;;
            -graphics|--no-graphics)
                EXCLUDED_CATEGORIES["graphics"]=1
                log "Excluding graphics category"
                ;;
            -security|--no-security)
                EXCLUDED_CATEGORIES["security"]=1
                log "Excluding security category"
                ;;
            -network|--no-network)
                EXCLUDED_CATEGORIES["network"]=1
                log "Excluding network category"
                ;;
            -system|--no-system)
                EXCLUDED_CATEGORIES["system"]=1
                log "Excluding system category"
                ;;
            -education|--no-education)
                EXCLUDED_CATEGORIES["education"]=1
                log "Excluding education category"
                ;;
            -science|--no-science)
                EXCLUDED_CATEGORIES["science"]=1
                log "Excluding science category"
                ;;
            -finance|--no-finance)
                EXCLUDED_CATEGORIES["finance"]=1
                log "Excluding finance category"
                ;;
            -virtualization|--no-virtualization)
                EXCLUDED_CATEGORIES["virtualization"]=1
                log "Excluding virtualization category"
                ;;
            -cloud|--no-cloud)
                EXCLUDED_CATEGORIES["cloud"]=1
                log "Excluding cloud category"
                ;;
            -minimal|--minimal)
                # Exclude most categories, keep only core and system
                for cat in dev wordpress gaming-platforms gaming-emulators ai multimedia music web-browsers communication office graphics security network education science finance virtualization cloud; do
                    EXCLUDED_CATEGORIES["$cat"]=1
                done
                log "Minimal mode: excluding most categories"
                ;;
            -core|--core-only)
                # Exclude everything except core
                for cat in dev wordpress gaming-platforms gaming-emulators ai multimedia music web-browsers communication office graphics security network system education science finance virtualization cloud; do
                    EXCLUDED_CATEGORIES["$cat"]=1
                done
                log "Core-only mode: excluding all except core category"
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
        shift
    done
}

# Show help information
show_help() {
    cat << EOF
ULTRABUNT ULTIMATE BUNTSTALLER v4.2.0
Professional Ubuntu/Mint setup & package manager

USAGE:
    ./ultrabunt.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    
SELECTIVE LOADING (exclude categories to speed up startup):
    -dev, --no-dev          Exclude development tools
    -wp, --no-wordpress     Exclude WordPress tools
    -gaming, --no-gaming    Exclude gaming platforms and emulators
    -ai, --no-ai            Exclude AI/ML tools
    -media, --no-media      Exclude multimedia and music tools
    -web, --no-web          Exclude web browsers
    -comm, --no-communication  Exclude communication tools
    -office, --no-office    Exclude office applications
    -graphics, --no-graphics  Exclude graphics tools
    -security, --no-security  Exclude security tools
    -network, --no-network  Exclude network tools
    -system, --no-system    Exclude system utilities
    -education, --no-education  Exclude educational software
    -science, --no-science  Exclude scientific applications
    -finance, --no-finance  Exclude financial software
    -virtualization, --no-virtualization  Exclude virtualization tools
    -cloud, --no-cloud      Exclude cloud tools
    
PRESET MODES:
    -minimal, --minimal     Load only core and system categories
    -core, --core-only      Load only core category

EXAMPLES:
    ./ultrabunt.sh                    # Load all categories (default)
    ./ultrabunt.sh -dev -gaming       # Exclude development and gaming
    ./ultrabunt.sh --minimal          # Minimal installation (fastest)
    ./ultrabunt.sh --core-only        # Core packages only
    ./ultrabunt.sh -wp -ai -media     # Exclude WordPress, AI, and media

NOTES:
    - Excluding categories significantly speeds up startup time
    - Categories can still be accessed if needed (they just won't be scanned)
    - Log file: /var/log/ultrabunt.log
    - Backups: /var/backups/ultrabunt

EOF
}

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize logging and buntage cache
init_logging() {
    sudo mkdir -p "$(dirname "$LOGFILE")" "$BACKUP_DIR" 2>/dev/null || true
    sudo touch "$LOGFILE" 2>/dev/null || true
    sudo chown "$USER:$USER" "$LOGFILE" "$BACKUP_DIR" 2>/dev/null || true
}

# Build cache of all installed buntages for fast lookups
build_package_cache() {
    log "Building buntage installation cache..."
    
    # Clear existing cache
    INSTALLED_CACHE=()
    
    # If selective loading is enabled, only cache packages from non-excluded categories
    local selective_mode=false
    if [[ ${#EXCLUDED_CATEGORIES[@]} -gt 0 ]]; then
        selective_mode=true
        log "Selective loading enabled - optimizing cache for included categories only"
    fi
    
    # Cache APT buntages
    log "Caching APT buntages..."
    if [[ "$selective_mode" == "true" ]]; then
        # Only cache packages from included categories
        for name in "${!PACKAGES[@]}"; do
            local pkg_category="${PKG_CATEGORY[$name]:-}"
            local method="${PKG_METHOD[$name]:-}"
            
            # Skip if category is excluded
            if [[ -n "${EXCLUDED_CATEGORIES[$pkg_category]:-}" ]]; then
                continue
            fi
            
            # Only check APT packages in this section
            if [[ "$method" == "apt" ]]; then
                local pkg="${PACKAGES[$name]}"
                if dpkg-query -W "$pkg" &>/dev/null; then
                    INSTALLED_CACHE["apt:$pkg"]=1
                fi
            fi
        done
    else
        # Cache all APT packages (original behavior)
        while IFS= read -r pkg; do
            INSTALLED_CACHE["apt:$pkg"]=1
        done < <(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)
    fi
    
    # Cache Snap buntages
    if command -v snap &>/dev/null; then
        log "Caching Snap buntages..."
        if [[ "$selective_mode" == "true" ]]; then
            # Only cache packages from included categories
            for name in "${!PACKAGES[@]}"; do
                local pkg_category="${PKG_CATEGORY[$name]:-}"
                local method="${PKG_METHOD[$name]:-}"
                
                # Skip if category is excluded
                if [[ -n "${EXCLUDED_CATEGORIES[$pkg_category]:-}" ]]; then
                    continue
                fi
                
                # Only check Snap packages in this section
                if [[ "$method" == "snap" ]]; then
                    local pkg="${PACKAGES[$name]}"
                    if snap list "$pkg" &>/dev/null; then
                        INSTALLED_CACHE["snap:$pkg"]=1
                    fi
                fi
            done
        else
            # Cache all Snap packages (original behavior)
            while IFS= read -r pkg; do
                INSTALLED_CACHE["snap:$pkg"]=1
            done < <(snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort)
        fi
    fi
    
    # Cache Flatpak buntages
    if command -v flatpak &>/dev/null; then
        log "Caching Flatpak buntages..."
        if [[ "$selective_mode" == "true" ]]; then
            # Only cache packages from included categories
            for name in "${!PACKAGES[@]}"; do
                local pkg_category="${PKG_CATEGORY[$name]:-}"
                local method="${PKG_METHOD[$name]:-}"
                
                # Skip if category is excluded
                if [[ -n "${EXCLUDED_CATEGORIES[$pkg_category]:-}" ]]; then
                    continue
                fi
                
                # Only check Flatpak packages in this section
                if [[ "$method" == "flatpak" ]]; then
                    local pkg="${PACKAGES[$name]}"
                    if flatpak list --app | grep -q "$pkg"; then
                        INSTALLED_CACHE["flatpak:$pkg"]=1
                    fi
                fi
            done
        else
            # Cache all Flatpak packages (original behavior)
            while IFS= read -r pkg; do
                INSTALLED_CACHE["flatpak:$pkg"]=1
            done < <(flatpak list --app --columns=application 2>/dev/null | sort)
        fi
    fi
    
    local total_cached=${#INSTALLED_CACHE[@]}
    log "Buntage cache built with $total_cached entries (selective mode: $selective_mode)"
}

# Function to update cache for a specific buntage
update_package_cache() {
    local name="$1"
    local silent="${2:-false}"  # Add silent mode parameter
    
    if [[ -z "$name" ]]; then
        [[ "$silent" != "true" ]] && log "ERROR: No buntage name provided to update_package_cache"
        return 1
    fi
    
    if [[ -z "${PACKAGES[$name]:-}" ]]; then
        [[ "$silent" != "true" ]] && log "WARNING: Buntage '$name' not found in PACKAGES array"
        return 1
    fi
    
    local pkg="${PACKAGES[$name]}"
    local method="${PKG_METHOD[$name]:-}"
    
    [[ "$silent" != "true" ]] && log "Updating cache for buntage: $name (method: $method, pkg: $pkg)"
    
    # Update the specific buntage in the cache
    case "$method" in
        apt)
            if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                INSTALLED_CACHE["apt:$pkg"]="1"
                [[ "$silent" != "true" ]] && log "Cache updated: $name is installed (APT)"
            else
                unset INSTALLED_CACHE["apt:$pkg"]
                # Removed verbose logging for not installed packages
            fi
            ;;
        snap)
            if snap list "$pkg" &>/dev/null; then
                INSTALLED_CACHE["snap:$pkg"]="1"
                [[ "$silent" != "true" ]] && log "Cache updated: $name is installed (Snap)"
            else
                unset INSTALLED_CACHE["snap:$pkg"]
                # Removed verbose logging for not installed packages
            fi
            ;;
        flatpak)
            if flatpak list --app 2>/dev/null | grep -q "$pkg"; then
                INSTALLED_CACHE["flatpak:$pkg"]="1"
                [[ "$silent" != "true" ]] && log "Cache updated: $name is installed (Flatpak)"
            else
                unset INSTALLED_CACHE["flatpak:$pkg"]
                # Removed verbose logging for not installed packages
            fi
            ;;
        custom)
            # For custom buntages, we can't easily cache them, so we'll just log
            [[ "$silent" != "true" ]] && log "Cache update skipped for custom buntage: $name"
            ;;
        *)
            [[ "$silent" != "true" ]] && log "WARNING: Unknown method '$method' for buntage '$name'"
            return 1
            ;;
    esac
    
    return 0
}

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOGFILE" >&2
}

log_error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" | tee -a "$LOGFILE" >&2
}

log_warning() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*"
    echo "$msg" | tee -a "$LOGFILE" >&2
}

# Ensure whiptail is available
ensure_deps() {
    log "Checking dependencies..."
    if ! command -v whiptail &>/dev/null; then
        log "Installing whiptail..."
        if sudo apt-get update -qq 2>&1 | tee -a "$LOGFILE"; then
            log "APT cache updated for whiptail installation"
        else
            log "WARNING: APT update failed during whiptail installation"
        fi
        
        if sudo apt-get install -y whiptail 2>&1 | tee -a "$LOGFILE"; then
            log "Successfully installed whiptail"
        else
            log "ERROR: Failed to install whiptail - UI may not work properly"
            exit 1
        fi
    else
        log "whiptail is already available"
    fi
}

# Whiptail wrapper functions
ui_msg() {
    whiptail --title "$1" --msgbox "$2" 15 70
}

ui_info() {
    whiptail --title "$1" --msgbox "$2" 30 100 --scrolltext
}

ui_yesno() {
    whiptail --title "$1" --yesno "$2" 12 70
}

ui_input() {
    whiptail --title "$1" --inputbox "$2" 10 70 "${3:-}" 3>&1 1>&2 2>&3
}

ui_password() {
    whiptail --title "$1" --passwordbox "$2" 10 70 3>&1 1>&2 2>&3
}

# UI Functions
ui_menu() {
    local title="$1"
    local text="$2"
    local height="$3"
    local width="$4"
    local menu_height="$5"
    shift 5
    
    if ! command -v whiptail &>/dev/null; then
        log "ERROR: whiptail not available for ui_menu"
        return 1
    fi
    
    # Execute whiptail and capture the result properly
    local choice
    choice=$(whiptail --title "$title" --menu "$text" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3)
    local exit_code=$?
    
    # Handle ESC key (exit code 255) as back navigation in nested menus
    if [[ $exit_code -eq 255 ]]; then
        log "ESC key pressed - treating as back navigation"
        echo "back"
        return 0
    fi
    
    # Only log if there's an error (but not for ESC)
    if [[ $exit_code -ne 0 ]]; then
        log "ui_menu failed with exit code: $exit_code"
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        echo "$choice"
    fi
    
    return $exit_code
}

ui_checklist() {
    local title="$1"
    local text="$2"
    local height="$3"
    local width="$4"
    local menu_height="$5"
    shift 5
    whiptail --title "$title" --checklist "$text" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3
}

# ==============================================================================
# INSTALLATION METHOD SELECTION
# ==============================================================================

# Function to get all available installation methods for a base app name
get_available_methods() {
    local base_name="$1"
    local methods=()
    
    # Check if base package exists
    if [[ -n "${PACKAGES[$base_name]:-}" ]]; then
        local method="${PKG_METHOD[$base_name]}"
        local desc="${PKG_DESC[$base_name]}"
        methods+=("$base_name" "$desc")
    fi
    
    # Check for alternative methods in preferred order: APT → Snap → Flatpak → Deb
    # Prefer repository-backed installs (APT/Snap) before Flatpak and standalone Deb
    for variant in "${base_name}-snap" "${base_name}-flatpak" "${base_name}-deb"; do
        if [[ -n "${PACKAGES[$variant]:-}" ]]; then
            local desc="${PKG_DESC[$variant]}"
            # Annotate snap variants if they require classic confinement
            if [[ "$variant" == "${base_name}-snap" ]]; then
                local snap_pkg="${PACKAGES[$variant]}"
                if [[ -n "$snap_pkg" ]] && requires_classic_snap "$snap_pkg"; then
                    desc+=" [classic confinement]"
                fi
            fi
            methods+=("$variant" "$desc")
        fi
    done
    
    # Special cases for apps with different naming patterns (avoid duplicates)
    case "$base_name" in
        "vscode")
            if [[ -n "${PACKAGES[vscode-snap]:-}" ]]; then
                local found=0
                for ((i=0; i<${#methods[@]}; i+=2)); do
                    [[ "${methods[i]}" == "vscode-snap" ]] && found=1 && break
                done
                if [[ $found -eq 0 ]]; then
                    local desc="${PKG_DESC[vscode-snap]}"
                    local snap_pkg="${PACKAGES[vscode-snap]}"
                    if [[ -n "$snap_pkg" ]] && requires_classic_snap "$snap_pkg"; then
                        desc+=" [classic confinement]"
                    fi
                    methods+=("vscode-snap" "$desc")
                fi
            fi
            if [[ -n "${PACKAGES[vscode-flatpak]:-}" ]]; then
                local found=0
                for ((i=0; i<${#methods[@]}; i+=2)); do
                    [[ "${methods[i]}" == "vscode-flatpak" ]] && found=1 && break
                done
                if [[ $found -eq 0 ]]; then
                    methods+=("vscode-flatpak" "${PKG_DESC[vscode-flatpak]}")
                fi
            fi
            ;;
        "discord")
            if [[ -n "${PACKAGES[discord-flatpak]:-}" ]]; then
                local found=0
                for ((i=0; i<${#methods[@]}; i+=2)); do
                    [[ "${methods[i]}" == "discord-flatpak" ]] && found=1 && break
                done
                if [[ $found -eq 0 ]]; then
                    methods+=("discord-flatpak" "${PKG_DESC[discord-flatpak]}")
                fi
            fi
            if [[ -n "${PACKAGES[discord-deb]:-}" ]]; then
                local found=0
                for ((i=0; i<${#methods[@]}; i+=2)); do
                    [[ "${methods[i]}" == "discord-deb" ]] && found=1 && break
                done
                if [[ $found -eq 0 ]]; then
                    methods+=("discord-deb" "${PKG_DESC[discord-deb]}")
                fi
            fi
            ;;
    esac
    
    printf '%s\n' "${methods[@]}"
}

# Function to offer installation method choice
choose_installation_method() {
    local base_name="$1"
    local available_methods
    
    # Get available methods as array
    mapfile -t available_methods < <(get_available_methods "$base_name")
    
    # If only one method available, return it
    if [[ ${#available_methods[@]} -eq 2 ]]; then
        echo "${available_methods[0]}"
        return 0
    fi
    
    # If multiple methods available, show selection menu
    if [[ ${#available_methods[@]} -gt 2 ]]; then
        local choice
        choice=$(ui_menu "Installation Method" "Multiple installation methods available for $base_name.\nChoose your preferred method:" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${available_methods[@]}")
        
        # Handle user cancellation gracefully - don't exit script
        if [[ -n "$choice" && "$choice" != "back" ]]; then
            echo "$choice"
            return 0
        else
            log "User cancelled installation method selection for $base_name"
            return 1
        fi
    fi
    
    # No methods found
    return 1
}

# Enhanced install function that checks for multiple methods
install_package_with_choice() {
    local name="$1"
    
    # First check if this is already a specific variant (e.g., vscode-snap)
    if [[ -n "${PACKAGES[$name]:-}" ]]; then
        install_package "$name"
        return $?
    fi
    
    # Check for multiple installation methods
    local chosen_method
    chosen_method=$(choose_installation_method "$name")
    
    if [[ -n "$chosen_method" ]]; then
        install_package "$chosen_method"
        return $?
    else
        ui_msg "Installation Cancelled" "No installation method selected for $name."
        return 1
    fi
}

# ==============================================================================
# BUNTAGE DETECTION FUNCTIONS
# ==============================================================================

is_apt_installed() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        return 1
    fi
    
    # Use cache for fast lookup first
    if [[ -n "${INSTALLED_CACHE["apt:$pkg"]:-}" ]]; then
        return 0
    fi

    # Fallback to direct dpkg check when cache is missing
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        INSTALLED_CACHE["apt:$pkg"]=1
        return 0
    fi

    return 1
}

is_snap_installed() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        return 1
    fi
    
    if ! command -v snap &>/dev/null; then
        return 1
    fi
    
    # Use cache for fast lookup
    if [[ -n "${INSTALLED_CACHE["snap:$pkg"]:-}" ]]; then
        return 0
    else
        return 1
    fi
}

is_flatpak_installed() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        return 1
    fi
    
    if ! command -v flatpak &>/dev/null; then
        return 1
    fi
    
    # Use cache for fast lookup
    if [[ -n "${INSTALLED_CACHE["flatpak:$pkg"]:-}" ]]; then
        return 0
    else
        return 1
    fi
}

is_binary_available() {
    command -v "$1" &>/dev/null
}

# Check if buntage exists in repos
apt_package_exists() {
    apt-cache show "$1" &>/dev/null
}

# Get buntage status with icon
get_status() {
    local pkg="$1"
    local method="${2:-apt}" # apt, snap, flatpak, binary
    
    case "$method" in
        apt)
            if is_apt_installed "$pkg"; then
                echo "✓"
            else
                echo "✗"
            fi
            ;;
        snap)
            if is_snap_installed "$pkg"; then
                echo "✓"
            else
                echo "✗"
            fi
            ;;
        flatpak)
            if is_flatpak_installed "$pkg"; then
                echo "✓"
            else
                echo "✗"
            fi
            ;;
        binary)
            if is_binary_available "$pkg"; then
                echo "✓"
            else
                echo "✗"
            fi
            ;;
    esac
}

# ==============================================================================
# BUNTAGE DEFINITIONS
# Each buntage has: name, description, install method, dependencies
# ==============================================================================

declare -A PACKAGES
declare -A PKG_DESC
declare -A PKG_METHOD
declare -A PKG_CATEGORY
declare -A PKG_DEPS

# CORE UTILITIES
PACKAGES[git]="git"
PKG_DESC[git]="Version control system [APT]"
PKG_METHOD[git]="apt"
PKG_CATEGORY[git]="core"

PACKAGES[curl]="curl"
PKG_DESC[curl]="Command line tool for transferring data [APT]"
PKG_METHOD[curl]="apt"
PKG_CATEGORY[curl]="core"

PACKAGES[wget]="wget"
PKG_DESC[wget]="Network downloader [APT]"
PKG_METHOD[wget]="apt"
PKG_CATEGORY[wget]="core"

PACKAGES[build-essential]="build-essential"
PKG_DESC[build-essential]="Compilation tools (gcc, make, etc) [APT]"
PKG_METHOD[build-essential]="apt"
PKG_CATEGORY[build-essential]="core"

PACKAGES[tree]="tree"
PKG_DESC[tree]="Directory listing in tree format [APT]"
PKG_METHOD[tree]="apt"
PKG_CATEGORY[tree]="core"

PACKAGES[ncdu]="ncdu"
PKG_DESC[ncdu]="NCurses Disk Usage analyzer [APT]"
PKG_METHOD[ncdu]="apt"
PKG_CATEGORY[ncdu]="core"

PACKAGES[jq]="jq"
PKG_DESC[jq]="JSON processor [APT]"
PKG_METHOD[jq]="apt"
PKG_CATEGORY[jq]="core"

PACKAGES[tmux]="tmux"
PKG_DESC[tmux]="Terminal multiplexer [APT]"
PKG_METHOD[tmux]="apt"
PKG_CATEGORY[tmux]="core"

PACKAGES[fzf]="fzf"
PKG_DESC[fzf]="Fuzzy finder [APT]"
PKG_METHOD[fzf]="apt"
PKG_CATEGORY[fzf]="core"

PACKAGES[ripgrep]="ripgrep"
PKG_DESC[ripgrep]="Fast grep alternative (rg) [APT]"
PKG_METHOD[ripgrep]="apt"
PKG_CATEGORY[ripgrep]="core"

PACKAGES[bat]="bat"
PKG_DESC[bat]="Cat clone with syntax highlighting [APT]"
PKG_METHOD[bat]="apt"
PKG_CATEGORY[bat]="core"

PACKAGES[eza]="eza"
PKG_DESC[eza]="Modern ls replacement [APT]"
PKG_METHOD[eza]="apt"
PKG_CATEGORY[eza]="core"

PACKAGES[tldr]="tldr"
PKG_DESC[tldr]="Simplified man pages [APT]"
PKG_METHOD[tldr]="apt"
PKG_CATEGORY[tldr]="core"

# DEVELOPMENT TOOLS
PACKAGES[neovim]="neovim"
PKG_DESC[neovim]="Modern Vim-based editor [APT]"
PKG_METHOD[neovim]="apt"
PKG_CATEGORY[neovim]="dev"

PACKAGES[python3-pip]="python3-pip"
PKG_DESC[python3-pip]="Python buntage installer [APT]"
PKG_METHOD[python3-pip]="apt"
PKG_CATEGORY[python3-pip]="dev"

PACKAGES[python3-venv]="python3-venv"
PKG_DESC[python3-venv]="Python virtual environments [APT]"
PKG_METHOD[python3-venv]="apt"
PKG_CATEGORY[python3-venv]="dev"

PACKAGES[default-jdk]="default-jdk"
PKG_DESC[default-jdk]="Java Development Kit [APT]"
PKG_METHOD[default-jdk]="apt"
PKG_CATEGORY[default-jdk]="dev"

PACKAGES[golang]="golang-go"
PKG_DESC[golang]="Go programming language [APT]"
PKG_METHOD[golang]="apt"
PKG_CATEGORY[golang]="dev"

PACKAGES[rustup]="rustup"
PKG_DESC[rustup]="Rust toolchain installer [CURL]"
PKG_METHOD[rustup]="custom"
PKG_CATEGORY[rustup]="dev"

PACKAGES[poetry]="python3-poetry"
PKG_DESC[poetry]="Modern Python dependency manager [APT]"
PKG_METHOD[poetry]="apt"
PKG_CATEGORY[poetry]="dev"

PACKAGES[pipx]="pipx"
PKG_DESC[pipx]="Install Python CLIs in isolated environments [APT]"
PKG_METHOD[pipx]="apt"
PKG_CATEGORY[pipx]="dev"

PACKAGES[deno]="deno"
PKG_DESC[deno]="Secure JS/TS runtime (Node's calmer cousin) [DEB]"
PKG_METHOD[deno]="custom"
PKG_CATEGORY[deno]="dev"

PACKAGES[bun]="bun"
PKG_DESC[bun]="Insanely fast JS runtime + package manager + bundler [SH]"
PKG_METHOD[bun]="custom"
PKG_CATEGORY[bun]="dev"

PACKAGES[mkdocs]="mkdocs"
PKG_DESC[mkdocs]="Static site generator for docs (dev favorite) [APT]"
PKG_METHOD[mkdocs]="apt"
PKG_CATEGORY[mkdocs]="dev"

PACKAGES[insomnia]="insomnia"
PKG_DESC[insomnia]="Gorgeous API testing tool [DEB]"
PKG_METHOD[insomnia]="custom"
PKG_CATEGORY[insomnia]="dev"

PACKAGES[zed]="zed"
PKG_DESC[zed]="Ultra-fast modern code editor (from Atom devs) [DEB]"
PKG_METHOD[zed]="custom"
PKG_CATEGORY[zed]="dev"

# CONTAINERS
PACKAGES[docker]="docker-ce"
PKG_DESC[docker]="Docker container platform [DEB]"
PKG_METHOD[docker]="custom"
PKG_CATEGORY[docker]="containers"

PACKAGES[docker-compose]="docker-compose-plugin"
PKG_DESC[docker-compose]="Docker Compose plugin [APT]"
PKG_METHOD[docker-compose]="apt"
PKG_CATEGORY[docker-compose]="containers"
PKG_DEPS[docker-compose]="docker"

PACKAGES[podman]="podman"
PKG_DESC[podman]="Daemonless container engine [APT]"
PKG_METHOD[podman]="apt"
PKG_CATEGORY[podman]="containers"

PACKAGES[minikube]="minikube"
PKG_DESC[minikube]="Local Kubernetes cluster [DEB]"
PKG_METHOD[minikube]="custom"
PKG_CATEGORY[minikube]="containers"

PACKAGES[kind]="kind"
PKG_DESC[kind]="Kubernetes in Docker [BIN]"
PKG_METHOD[kind]="custom"
PKG_CATEGORY[kind]="containers"

PACKAGES[ctop]="ctop"
PKG_DESC[ctop]="Top-like interface for containers [BIN]"
PKG_METHOD[ctop]="custom"
PKG_CATEGORY[ctop]="containers"

PACKAGES[lazydocker]="lazydocker"
PKG_DESC[lazydocker]="Terminal UI for Docker and Docker Compose [BIN]"
PKG_METHOD[lazydocker]="custom"
PKG_CATEGORY[lazydocker]="containers"

# WEB STACK
PACKAGES[nginx]="nginx"
PKG_DESC[nginx]="High-performance web server [APT]"
PKG_METHOD[nginx]="apt"
PKG_CATEGORY[nginx]="web"

PACKAGES[apache2]="apache2"
PKG_DESC[apache2]="Apache HTTP Server [APT]"
PKG_METHOD[apache2]="apt"
PKG_CATEGORY[apache2]="web"

PACKAGES[php-fpm]="php${PHP_VER}-fpm"
PKG_DESC[php-fpm]="PHP FastCGI Process Manager"
PKG_METHOD[php-fpm]="apt"
PKG_CATEGORY[php-fpm]="web"

PACKAGES[libapache2-mod-php]="libapache2-mod-php${PHP_VER}"
PKG_DESC[libapache2-mod-php]="PHP module for Apache [APT]"
PKG_METHOD[libapache2-mod-php]="apt"
PKG_CATEGORY[libapache2-mod-php]="web"

PACKAGES[php-mysql]="php${PHP_VER}-mysql"
PKG_DESC[php-mysql]="PHP MySQL extension [APT]"
PKG_METHOD[php-mysql]="apt"
PKG_CATEGORY[php-mysql]="web"

PACKAGES[php-curl]="php${PHP_VER}-curl"
PKG_DESC[php-curl]="PHP cURL extension [APT]"
PKG_METHOD[php-curl]="apt"
PKG_CATEGORY[php-curl]="web"

PACKAGES[php-gd]="php${PHP_VER}-gd"
PKG_DESC[php-gd]="PHP GD graphics extension [APT]"
PKG_METHOD[php-gd]="apt"
PKG_CATEGORY[php-gd]="web"

PACKAGES[php-xml]="php${PHP_VER}-xml"
PKG_DESC[php-xml]="PHP XML extension [APT]"
PKG_METHOD[php-xml]="apt"
PKG_CATEGORY[php-xml]="web"

PACKAGES[php-mbstring]="php${PHP_VER}-mbstring"
PKG_DESC[php-mbstring]="PHP multibyte string extension [APT]"
PKG_METHOD[php-mbstring]="apt"
PKG_CATEGORY[php-mbstring]="web"

PACKAGES[php-zip]="php${PHP_VER}-zip"
PKG_DESC[php-zip]="PHP ZIP extension [APT]"
PKG_METHOD[php-zip]="apt"
PKG_CATEGORY[php-zip]="web"

PACKAGES[mariadb]="mariadb-server"
PKG_DESC[mariadb]="MariaDB database server [APT]"
PKG_METHOD[mariadb]="apt"
PKG_CATEGORY[mariadb]="web"

PACKAGES[certbot]="certbot"
PKG_DESC[certbot]="Let's Encrypt SSL certificate tool [APT]"
PKG_METHOD[certbot]="apt"
PKG_CATEGORY[certbot]="web"

PACKAGES[python3-certbot-nginx]="python3-certbot-nginx"
PKG_DESC[python3-certbot-nginx]="Certbot Nginx plugin [APT]"
PKG_METHOD[python3-certbot-nginx]="apt"
PKG_CATEGORY[python3-certbot-nginx]="web"

PACKAGES[python3-certbot-apache]="python3-certbot-apache"
PKG_DESC[python3-certbot-apache]="Certbot Apache plugin [APT]"
PKG_METHOD[python3-certbot-apache]="apt"
PKG_CATEGORY[python3-certbot-apache]="web"

PACKAGES[redis]="redis-server"
PKG_DESC[redis]="Redis in-memory data store [APT]"
PKG_METHOD[redis]="apt"
PKG_CATEGORY[redis]="web"

PACKAGES[caddy]="caddy"
PKG_DESC[caddy]="Fast web server with automatic HTTPS [DEB]"
PKG_METHOD[caddy]="custom"
PKG_CATEGORY[caddy]="web"

PACKAGES[pm2]="pm2"
PKG_DESC[pm2]="Production process manager for Node.js [NPM]"
PKG_METHOD[pm2]="npm"
PKG_CATEGORY[pm2]="web"

PACKAGES[ngrok]="ngrok"
PKG_DESC[ngrok]="Secure tunnels to localhost [BIN]"
PKG_METHOD[ngrok]="custom"
PKG_CATEGORY[ngrok]="web"

PACKAGES[mailhog]="mailhog"
PKG_DESC[mailhog]="Email testing tool [BIN]"
PKG_METHOD[mailhog]="custom"
PKG_CATEGORY[mailhog]="web"

PACKAGES[adminmongo]="adminmongo"
PKG_DESC[adminmongo]="MongoDB admin interface [NPM]"
PKG_METHOD[adminmongo]="npm"
PKG_CATEGORY[adminmongo]="web"

PACKAGES[sqlitestudio]="sqlitestudio"
PKG_DESC[sqlitestudio]="SQLite database browser [APT]"
PKG_METHOD[sqlitestudio]="apt"
PKG_CATEGORY[sqlitestudio]="web"

# CONTAINERIZED DEVELOPMENT ENVIRONMENTS
PACKAGES[localwp]="local"
PKG_DESC[localwp]="LocalWP - Local WordPress development environment [DEB]"
PKG_METHOD[localwp]="custom"
PKG_CATEGORY[localwp]="web"

PACKAGES[devkinsta]="devkinsta"
PKG_DESC[devkinsta]="DevKinsta - Kinsta's local WordPress development tool [DEB]"
PKG_METHOD[devkinsta]="custom"
PKG_CATEGORY[devkinsta]="web"

PACKAGES[lando]="lando"
PKG_DESC[lando]="Lando - Containerized local development [DEB]"
PKG_METHOD[lando]="custom"
PKG_CATEGORY[lando]="web"

PACKAGES[ddev]="ddev"
PKG_DESC[ddev]="DDEV - Docker-based local development [BIN]"
PKG_METHOD[ddev]="custom"
PKG_CATEGORY[ddev]="web"

PACKAGES[xampp]="xampp"
PKG_DESC[xampp]="XAMPP - Cross-platform web server solution stack [BIN]"
PKG_METHOD[xampp]="custom"
PKG_CATEGORY[xampp]="web"

# NODE.JS
PACKAGES[nodejs]="nodejs"
PKG_DESC[nodejs]="Node.js JavaScript runtime [DEB]"
PKG_METHOD[nodejs]="custom"
PKG_CATEGORY[nodejs]="dev"

PACKAGES[npm]="npm"
PKG_DESC[npm]="Node buntage manager [APT]"
PKG_METHOD[npm]="apt"
PKG_CATEGORY[npm]="dev"

# SHELLS & UI
PACKAGES[zsh]="zsh"
PKG_DESC[zsh]="Z shell [APT]"
PKG_METHOD[zsh]="apt"
PKG_CATEGORY[zsh]="shell"

PACKAGES[fonts-powerline]="fonts-powerline"
PKG_DESC[fonts-powerline]="Powerline fonts [APT]"
PKG_METHOD[fonts-powerline]="apt"
PKG_CATEGORY[fonts-powerline]="shell"

PACKAGES[oh-my-zsh]="oh-my-zsh"
PKG_DESC[oh-my-zsh]="Framework for managing Zsh configuration [SCRIPT]"
PKG_METHOD[oh-my-zsh]="custom"
PKG_CATEGORY[oh-my-zsh]="shell"

PACKAGES[starship]="starship"
PKG_DESC[starship]="Cross-shell prompt with customization [BINARY]"
PKG_METHOD[starship]="custom"
PKG_CATEGORY[starship]="shell"

PACKAGES[zoxide]="zoxide"
PKG_DESC[zoxide]="Smarter cd command that learns your habits [BINARY]"
PKG_METHOD[zoxide]="custom"
PKG_CATEGORY[zoxide]="shell"

PACKAGES[zsh-autosuggestions]="zsh-autosuggestions"
PKG_DESC[zsh-autosuggestions]="Fish-like autosuggestions for Zsh [APT]"
PKG_METHOD[zsh-autosuggestions]="apt"
PKG_CATEGORY[zsh-autosuggestions]="shell"

# HACKER PLAYGROUND - Fun Terminal Tools
PACKAGES[cmatrix]="cmatrix"
PKG_DESC[cmatrix]="Matrix digital rain [APT]"
PKG_METHOD[cmatrix]="apt"
PKG_CATEGORY[cmatrix]="fun"

PACKAGES[hollywood]="hollywood"
PKG_DESC[hollywood]="Turn your terminal into a fake hacking montage [APT]"
PKG_METHOD[hollywood]="apt"
PKG_CATEGORY[hollywood]="fun"

PACKAGES[sl]="sl"
PKG_DESC[sl]="Steam locomotive for when you mistype ls [APT]"
PKG_METHOD[sl]="apt"
PKG_CATEGORY[sl]="fun"

PACKAGES[lolcat]="lolcat"
PKG_DESC[lolcat]="Rainbow text output [APT]"
PKG_METHOD[lolcat]="apt"
PKG_CATEGORY[lolcat]="fun"

PACKAGES[toilet]="toilet"
PKG_DESC[toilet]="Big ASCII banners [APT]"
PKG_METHOD[toilet]="apt"
PKG_CATEGORY[toilet]="fun"

PACKAGES[figlet]="figlet"
PKG_DESC[figlet]="Classic ASCII text art generator [APT]"
PKG_METHOD[figlet]="apt"
PKG_CATEGORY[figlet]="fun"

PACKAGES[boxes]="boxes"
PKG_DESC[boxes]="ASCII box drawings around text [APT]"
PKG_METHOD[boxes]="apt"
PKG_CATEGORY[boxes]="fun"

PACKAGES[asciiquarium]="asciiquarium"
PKG_DESC[asciiquarium]="ASCII aquarium in your terminal [APT]"
PKG_METHOD[asciiquarium]="apt"
PKG_CATEGORY[asciiquarium]="fun"

PACKAGES[cowsay]="cowsay"
PKG_DESC[cowsay]="Talking ASCII cows [APT]"
PKG_METHOD[cowsay]="apt"
PKG_CATEGORY[cowsay]="fun"

PACKAGES[fortune]="fortune-mod"
PKG_DESC[fortune]="Random fortune cookies [APT]"
PKG_METHOD[fortune]="apt"
PKG_CATEGORY[fortune]="fun"

# EDITORS & IDEs
PACKAGES[vscode]="code"
PKG_DESC[vscode]="Visual Studio Code [DEB]"
PKG_METHOD[vscode]="custom"
PKG_CATEGORY[vscode]="editors"

PACKAGES[sublime-text]="sublime-text"
PKG_DESC[sublime-text]="Sublime Text editor [DEB]"
PKG_METHOD[sublime-text]="custom"
PKG_CATEGORY[sublime-text]="editors"

# BROWSERS
PACKAGES[brave]="brave-browser"
PKG_DESC[brave]="Brave web browser [DEB]"
PKG_METHOD[brave]="custom"
PKG_CATEGORY[brave]="browsers"

PACKAGES[firefox]="firefox"
PKG_DESC[firefox]="Mozilla Firefox browser [APT]"
PKG_METHOD[firefox]="apt"
PKG_CATEGORY[firefox]="browsers"

PACKAGES[chromium]="chromium"
PKG_DESC[chromium]="Chromium web browser [APT]"
PKG_METHOD[chromium]="apt"
PKG_CATEGORY[chromium]="browsers"

# MONITORING
PACKAGES[htop]="htop"
PKG_DESC[htop]="Interactive process viewer [APT]"
PKG_METHOD[htop]="apt"
PKG_CATEGORY[htop]="system-monitoring"

PACKAGES[btop]="btop"
PKG_DESC[btop]="Resource monitor with better graphs [APT]"
PKG_METHOD[btop]="apt"
PKG_CATEGORY[btop]="system-monitoring"

PACKAGES[glances]="glances"
PKG_DESC[glances]="Cross-platform system monitor [APT]"
PKG_METHOD[glances]="apt"
PKG_CATEGORY[glances]="system-monitoring"

PACKAGES[nethogs]="nethogs"
PKG_DESC[nethogs]="Network bandwidth monitor per process [APT]"
PKG_METHOD[nethogs]="apt"
PKG_CATEGORY[nethogs]="network-monitoring"

PACKAGES[iotop]="iotop"
PKG_DESC[iotop]="I/O monitor [APT]"
PKG_METHOD[iotop]="apt"
PKG_CATEGORY[iotop]="system-monitoring"

# Additional Process Monitors
PACKAGES[bpytop]="bpytop"
PKG_DESC[bpytop]="Python-based resource monitor (btop predecessor) [APT]"
PKG_METHOD[bpytop]="apt"
PKG_CATEGORY[bpytop]="system-monitoring"

PACKAGES[bashtop]="bashtop"
PKG_DESC[bashtop]="Bash-based resource monitor (original) [APT]"
PKG_METHOD[bashtop]="apt"
PKG_CATEGORY[bashtop]="system-monitoring"

PACKAGES[bottom]="bottom"
PKG_DESC[bottom]="Cross-platform graphical process monitor (btm) [APT]"
PKG_METHOD[bottom]="apt"
PKG_CATEGORY[bottom]="system-monitoring"

PACKAGES[gotop]="gotop"
PKG_DESC[gotop]="Terminal-based graphical activity monitor [SNAP]"
PKG_METHOD[gotop]="snap"
PKG_CATEGORY[gotop]="system-monitoring"

PACKAGES[vtop]="vtop"
PKG_DESC[vtop]="Visually appealing terminal monitor [NPM]"
PKG_METHOD[vtop]="npm"
PKG_CATEGORY[vtop]="system-monitoring"

PACKAGES[zenith]="zenith"
PKG_DESC[zenith]="Terminal monitor with zoomable charts [CARGO]"
PKG_METHOD[zenith]="cargo"
PKG_CATEGORY[zenith]="system-monitoring"

PACKAGES[nmon]="nmon"
PKG_DESC[nmon]="Nigel's Monitor - modular system statistics [APT]"
PKG_METHOD[nmon]="apt"
PKG_CATEGORY[nmon]="system-monitoring"

PACKAGES[atop]="atop"
PKG_DESC[atop]="Advanced system and process monitor [APT]"
PKG_METHOD[atop]="apt"
PKG_CATEGORY[atop]="system-monitoring"

# I/O, Memory, and Disk Tools
PACKAGES[iostat]="sysstat"
PKG_DESC[iostat]="CPU utilization and disk I/O statistics [APT]"
PKG_METHOD[iostat]="apt"
PKG_CATEGORY[iostat]="system-monitoring"

PACKAGES[vmstat]="procps"
PKG_DESC[vmstat]="Virtual memory, processes, I/O, and CPU activity [APT]"
PKG_METHOD[vmstat]="apt"
PKG_CATEGORY[vmstat]="system-monitoring"

PACKAGES[free]="procps"
PKG_DESC[free]="Display free and used memory [APT]"
PKG_METHOD[free]="apt"
PKG_CATEGORY[free]="system-monitoring"

# Network Monitoring Tools
PACKAGES[iftop]="iftop"
PKG_DESC[iftop]="Real-time bandwidth usage per network interface [APT]"
PKG_METHOD[iftop]="apt"
PKG_CATEGORY[iftop]="network-monitoring"

PACKAGES[nload]="nload"
PKG_DESC[nload]="Network traffic visualizer with graphical bars [APT]"
PKG_METHOD[nload]="apt"
PKG_CATEGORY[nload]="network-monitoring"

PACKAGES[bmon]="bmon"
PKG_DESC[bmon]="Interactive bandwidth monitor [APT]"
PKG_METHOD[bmon]="apt"
PKG_CATEGORY[bmon]="network-monitoring"

PACKAGES[iptraf-ng]="iptraf-ng"
PKG_DESC[iptraf-ng]="Console-based network monitoring utility [APT]"
PKG_METHOD[iptraf-ng]="apt"
PKG_CATEGORY[iptraf-ng]="network-monitoring"

PACKAGES[ss]="iproute2"
PKG_DESC[ss]="Socket investigation utility (netstat replacement) [APT]"
PKG_METHOD[ss]="apt"
PKG_CATEGORY[ss]="network-monitoring"

# Process and System Information Tools
PACKAGES[lsof]="lsof"
PKG_DESC[lsof]="List open files and processes [APT]"
PKG_METHOD[lsof]="apt"
PKG_CATEGORY[lsof]="system-monitoring"

PACKAGES[sar]="sysstat"
PKG_DESC[sar]="System Activity Reporter - historical monitoring [APT]"
PKG_METHOD[sar]="apt"
PKG_CATEGORY[sar]="system-monitoring"

PACKAGES[mpstat]="sysstat"
PKG_DESC[mpstat]="Individual or combined CPU processor statistics [APT]"
PKG_METHOD[mpstat]="apt"
PKG_CATEGORY[mpstat]="system-monitoring"

PACKAGES[pidstat]="sysstat"
PKG_DESC[pidstat]="Per-process CPU, memory, and I/O statistics [APT]"
PKG_METHOD[pidstat]="apt"
PKG_CATEGORY[pidstat]="system-monitoring"

# GPU Monitoring Tools
PACKAGES[nvtop]="nvtop"
PKG_DESC[nvtop]="htop-like utility for monitoring NVIDIA GPUs [APT]"
PKG_METHOD[nvtop]="apt"
PKG_CATEGORY[nvtop]="system-monitoring"

PACKAGES[radeontop]="radeontop"
PKG_DESC[radeontop]="TUI utility for monitoring AMD GPUs [APT]"
PKG_METHOD[radeontop]="apt"
# System Information Tools
PACKAGES[ps]="procps"
PKG_DESC[ps]="Standard process status command - reports a snapshot of current processes (non-interactive)"
PKG_METHOD[ps]="apt"
PKG_CATEGORY[ps]="system-monitoring"

PKG_CATEGORY[radeontop]="system-monitoring"

# Additional GPU Monitoring Tool
PACKAGES[qmasa]="qmasa"
PKG_DESC[qmasa]="Terminal-based tool for displaying general GPU usage stats on Linux [Cargo]"
PKG_METHOD[qmasa]="cargo"
PKG_CATEGORY[qmasa]="system-monitoring"

# Additional Process Monitoring Tool
PACKAGES[gtop]="gtop"
PKG_DESC[gtop]="System monitoring dashboard for the terminal, written in Node.js [NPM]"
PKG_METHOD[gtop]="npm"
PKG_CATEGORY[gtop]="system-monitoring"

# Additional System Utilities
PACKAGES[pv]="pv"
PKG_DESC[pv]="Pipe Viewer - monitor progress of data through a pipeline with progress bar [APT]"
PKG_METHOD[pv]="apt"
PKG_CATEGORY[pv]="utilities"

PACKAGES[duf]="duf"
PKG_DESC[duf]="Disk Usage/Free Utility - better 'df' alternative with colors [APT]"
PKG_METHOD[duf]="apt"
PKG_CATEGORY[duf]="utilities"

PACKAGES[dust]="dust"
PKG_DESC[dust]="More intuitive version of du written in Rust [Cargo]"
PKG_METHOD[dust]="cargo"
PKG_CATEGORY[dust]="utilities"

PACKAGES[fd-find]="fd-find"
PKG_DESC[fd-find]="Simple, fast and user-friendly alternative to 'find' [APT]"
PKG_METHOD[fd-find]="apt"
PKG_CATEGORY[fd-find]="utilities"

PACKAGES[exa]="exa"
PKG_DESC[exa]="Modern replacement for 'ls' with colors and Git status [APT]"
PKG_METHOD[exa]="apt"
PKG_CATEGORY[exa]="utilities"

PACKAGES[bandwhich]="bandwhich"
PKG_DESC[bandwhich]="Terminal bandwidth utilization tool by process [Cargo]"
PKG_METHOD[bandwhich]="cargo"
PKG_CATEGORY[bandwhich]="network-monitoring"

PACKAGES[procs]="procs"
PKG_DESC[procs]="Modern replacement for ps written in Rust [Cargo]"
PKG_METHOD[procs]="cargo"
PKG_CATEGORY[procs]="system-monitoring"

PACKAGES[tokei]="tokei"
PKG_DESC[tokei]="Count lines of code quickly [Cargo]"
PKG_METHOD[tokei]="cargo"
PKG_CATEGORY[tokei]="performance-tools"

PACKAGES[hyperfine]="hyperfine"
PKG_DESC[hyperfine]="Command-line benchmarking tool [APT]"
PKG_METHOD[hyperfine]="apt"
PKG_CATEGORY[hyperfine]="performance-tools"

PACKAGES[batcat]="batcat"
PKG_DESC[batcat]="Enhanced cat command with paging, syntax highlight & Git integration [APT]"
PKG_METHOD[batcat]="apt"
PKG_CATEGORY[batcat]="utilities"

PACKAGES[micro]="micro"
PKG_DESC[micro]="Terminal-based text editor that feels like Sublime [APT]"
PKG_METHOD[micro]="apt"
PKG_CATEGORY[micro]="utilities"

PACKAGES[atool]="atool"
PKG_DESC[atool]="Manage archive files (tar, zip, etc.) from terminal [APT]"
PKG_METHOD[atool]="apt"
PKG_CATEGORY[atool]="utilities"

PACKAGES[plocate]="plocate"
PKG_DESC[plocate]="Superfast locate replacement using modern indexing [APT]"
PKG_METHOD[plocate]="apt"
PKG_CATEGORY[plocate]="utilities"

PACKAGES[silversearcher-ag]="silversearcher-ag"
PKG_DESC[silversearcher-ag]="The silver searcher, crazy-fast grep alternative [APT]"
PKG_METHOD[silversearcher-ag]="apt"
PKG_CATEGORY[silversearcher-ag]="utilities"

PACKAGES[yq]="yq"
PKG_DESC[yq]="Command-line YAML processor (jq wrapper for YAML files) [Snap]"
PKG_METHOD[yq]="snap"
PKG_CATEGORY[yq]="utilities"

PACKAGES[delta]="git-delta"
PKG_DESC[delta]="Syntax-highlighting pager for git and diff output [APT]"
PKG_METHOD[delta]="apt"
PKG_CATEGORY[delta]="utilities"

PACKAGES[mirrorselect]="mirrorselect"
PKG_DESC[mirrorselect]="Tool to select the fastest Ubuntu mirror for optimal download speeds [SNAP]"
PKG_METHOD[mirrorselect]="snap"
PKG_CATEGORY[mirrorselect]="utilities"

PACKAGES[apt-mirror]="apt-mirror"
PKG_DESC[apt-mirror]="Tool to create local Ubuntu repository mirrors for offline installations [APT]"
PKG_METHOD[apt-mirror]="apt"
PKG_CATEGORY[apt-mirror]="utilities"

# DATABASE MANAGEMENT TOOLS
PACKAGES[phpmyadmin]="phpmyadmin"
PKG_DESC[phpmyadmin]="Web-based MySQL/MariaDB administration tool [CUSTOM]"
PKG_METHOD[phpmyadmin]="custom"
PKG_CATEGORY[phpmyadmin]="database"

PACKAGES[adminer]="adminer"
PKG_DESC[adminer]="Full-featured database management tool in a single PHP file [CUSTOM]"
PKG_METHOD[adminer]="custom"
PKG_CATEGORY[adminer]="database"

PACKAGES[dbeaver-ce]="dbeaver-ce"
PKG_DESC[dbeaver-ce]="Universal database tool and SQL client (Community Edition) [Snap]"
PKG_METHOD[dbeaver-ce]="snap"
PKG_CATEGORY[dbeaver-ce]="database"

PACKAGES[dbeaver-ce-flatpak]="io.dbeaver.DBeaverCommunity"
PKG_DESC[dbeaver-ce-flatpak]="Universal database tool and SQL client (Community Edition) [Flatpak]"
PKG_METHOD[dbeaver-ce-flatpak]="flatpak"
PKG_CATEGORY[dbeaver-ce-flatpak]="database"

PACKAGES[mysql-workbench-community]="mysql-workbench-community"
PKG_DESC[mysql-workbench-community]="Visual database design tool for MySQL [APT]"
PKG_METHOD[mysql-workbench-community]="apt"
PKG_CATEGORY[mysql-workbench-community]="database"

PACKAGES[pgadmin4]="pgadmin4"
PKG_DESC[pgadmin4]="Web-based PostgreSQL administration and development platform [APT]"
PKG_METHOD[pgadmin4]="apt"
PKG_CATEGORY[pgadmin4]="database"

PACKAGES[sqlitebrowser]="sqlitebrowser"
PKG_DESC[sqlitebrowser]="High quality, visual, open source tool to create, design, and edit SQLite databases [APT]"
PKG_METHOD[sqlitebrowser]="apt"
PKG_CATEGORY[sqlitebrowser]="database"

PACKAGES[mycli]="mycli"
PKG_DESC[mycli]="Command line interface for MySQL with auto-completion and syntax highlighting [APT]"
PKG_METHOD[mycli]="apt"
PKG_CATEGORY[mycli]="database"

PACKAGES[pgcli]="pgcli"
PKG_DESC[pgcli]="Command line interface for PostgreSQL with auto-completion and syntax highlighting [APT]"
PKG_METHOD[pgcli]="apt"
PKG_CATEGORY[pgcli]="database"

PACKAGES[litecli]="litecli"
PKG_DESC[litecli]="Command-line client for SQLite databases with auto-completion and syntax highlighting [APT]"
PKG_METHOD[litecli]="apt"
PKG_CATEGORY[litecli]="database"

PACKAGES[redis-tools]="redis-tools"
PKG_DESC[redis-tools]="Command-line tools for Redis key-value store [APT]"
PKG_METHOD[redis-tools]="apt"
PKG_CATEGORY[redis-tools]="database"

PACKAGES[mongodb-compass]="mongodb-compass"
PKG_DESC[mongodb-compass]="GUI for MongoDB - explore and manipulate your data [Snap]"
PKG_METHOD[mongodb-compass]="snap"
PKG_CATEGORY[mongodb-compass]="database"

PACKAGES[postbird]="postbird"
PKG_DESC[postbird]="Cross-platform PostgreSQL GUI client [Snap]"
PKG_METHOD[postbird]="snap"
PKG_CATEGORY[postbird]="database"

PACKAGES[beekeeper-studio]="beekeeper-studio"
PKG_DESC[beekeeper-studio]="Modern and easy to use SQL client for MySQL, Postgres, SQLite, SQL Server, and more [Snap]"
PKG_METHOD[beekeeper-studio]="snap"
PKG_CATEGORY[beekeeper-studio]="database"

PACKAGES[tableplus]="tableplus"
PKG_DESC[tableplus]="Modern, native tool with elegant UI for relational databases [Snap]"
PKG_METHOD[tableplus]="snap"
PKG_CATEGORY[tableplus]="database"

# SECURITY
PACKAGES[ufw]="ufw"
PKG_DESC[ufw]="Uncomplicated Firewall [APT]"
PKG_METHOD[ufw]="apt"
PKG_CATEGORY[ufw]="security"

PACKAGES[fail2ban]="fail2ban"
PKG_DESC[fail2ban]="Intrusion prevention system [APT]"
PKG_METHOD[fail2ban]="apt"
PKG_CATEGORY[fail2ban]="security"

# FLATPAK & APPS
PACKAGES[flatpak]="flatpak"
PKG_DESC[flatpak]="Flatpak buntage manager [APT]"
PKG_METHOD[flatpak]="apt"
PKG_CATEGORY[flatpak]="system"

# FILE SHARING & NETWORK
PACKAGES[samba]="samba"
PKG_DESC[samba]="SMB/CIFS file sharing server [APT]"
PKG_METHOD[samba]="apt"
PKG_CATEGORY[samba]="system"

PACKAGES[nfs-kernel-server]="nfs-kernel-server"
PKG_DESC[nfs-kernel-server]="Network File System server [APT]"
PKG_METHOD[nfs-kernel-server]="apt"
PKG_CATEGORY[nfs-kernel-server]="system"

PACKAGES[localsend]="localsend"
PKG_DESC[localsend]="LocalSend file sharing [SNP]"
PKG_METHOD[localsend]="snap"
PKG_CATEGORY[localsend]="communication"
PKG_DEPS[localsend]="snapd"

# SNAP MANAGER (dependency for snap apps)
PACKAGES[snapd]="snapd"
PKG_DESC[snapd]="Snap daemon and CLI [APT]"
PKG_METHOD[snapd]="apt"
PKG_CATEGORY[snapd]="system"

# SNAP APPS
PACKAGES[spotify]="spotify"
PKG_DESC[spotify]="Music streaming service [SNP]"
PKG_METHOD[spotify]="snap"
PKG_CATEGORY[spotify]="audio"

PACKAGES[postman]="postman"
PKG_DESC[postman]="API development platform [SNP]"
PKG_METHOD[postman]="snap"
PKG_CATEGORY[postman]="dev"

PACKAGES[bruno]="bruno"
PKG_DESC[bruno]="Open-source Postman alternative [CUSTOM]"
PKG_METHOD[bruno]="custom"
PKG_CATEGORY[bruno]="dev"

PACKAGES[bruno-snap]="bruno"
PKG_DESC[bruno-snap]="Open-source Postman alternative [SNAP]"
PKG_METHOD[bruno-snap]="snap"
PKG_CATEGORY[bruno-snap]="dev"

PACKAGES[bruno-flatpak]="com.usebruno.Bruno"
PKG_DESC[bruno-flatpak]="Open-source Postman alternative [FLATPAK]"
PKG_METHOD[bruno-flatpak]="flatpak"
PKG_CATEGORY[bruno-flatpak]="dev"
PKG_DEPS[bruno-flatpak]="flatpak"

PACKAGES[yaak]="yaak"
PKG_DESC[yaak]="Modern API client [DEB]"
PKG_METHOD[yaak]="custom"
PKG_CATEGORY[yaak]="dev"

# DESKTOP APPS
PACKAGES[obs-studio]="obs-studio"
PKG_DESC[obs-studio]="OBS Studio streaming/recording [APT]"
PKG_METHOD[obs-studio]="apt"
PKG_CATEGORY[obs-studio]="video"

PACKAGES[vlc]="vlc"
PKG_DESC[vlc]="VLC media player [APT]"
PKG_METHOD[vlc]="apt"
PKG_CATEGORY[vlc]="video"

# CLOUD & SYNC
PACKAGES[rclone]="rclone"
PKG_DESC[rclone]="Cloud storage sync tool [APT]"
PKG_METHOD[rclone]="apt"
PKG_CATEGORY[rclone]="cloud"

PACKAGES[dropbox]="dropbox"
PKG_DESC[dropbox]="File synchronization [DEB]"
PKG_METHOD[dropbox]="custom"
PKG_CATEGORY[dropbox]="cloud"

PACKAGES[nextcloud-desktop]="nextcloud-desktop"
PKG_DESC[nextcloud-desktop]="Self-hosted cloud client [APT]"
PKG_METHOD[nextcloud-desktop]="apt"
PKG_CATEGORY[nextcloud-desktop]="cloud"

PACKAGES[syncthing]="syncthing"
PKG_DESC[syncthing]="Decentralized sync [APT]"
PKG_METHOD[syncthing]="apt"
PKG_CATEGORY[syncthing]="cloud"

PACKAGES[google-drive-ocamlfuse]="google-drive-ocamlfuse"
PKG_DESC[google-drive-ocamlfuse]="Google Drive filesystem [APT]"
PKG_METHOD[google-drive-ocamlfuse]="apt"
PKG_CATEGORY[google-drive-ocamlfuse]="cloud"

PACKAGES[nextcloud-server]="nextcloud-server"
PKG_DESC[nextcloud-server]="Self-hosted cloud storage server [SNAP]"
PKG_METHOD[nextcloud-server]="snap"
PKG_CATEGORY[nextcloud-server]="cloud"

PACKAGES[seafile]="seafile"
PKG_DESC[seafile]="Lightweight cloud storage with sync [CUSTOM]"
PKG_METHOD[seafile]="custom"
PKG_CATEGORY[seafile]="cloud"

# TERMINALS
PACKAGES[warp-terminal]="warp-terminal"
PKG_DESC[warp-terminal]="Modern terminal with AI features [APT]"
PKG_METHOD[warp-terminal]="custom"
PKG_CATEGORY[warp-terminal]="terminals"

PACKAGES[alacritty]="alacritty"
PKG_DESC[alacritty]="GPU-accelerated terminal emulator [APT]"
PKG_METHOD[alacritty]="apt"
PKG_CATEGORY[alacritty]="terminals"

PACKAGES[terminator]="terminator"
PKG_DESC[terminator]="Multiple terminals in one window [APT]"
PKG_METHOD[terminator]="apt"
PKG_CATEGORY[terminator]="terminals"

PACKAGES[tilix]="tilix"
PKG_DESC[tilix]="Tiling terminal emulator [APT]"
PKG_METHOD[tilix]="apt"
PKG_CATEGORY[tilix]="terminals"

PACKAGES[ghostty]="ghostty"
PKG_DESC[ghostty]="Fast, feature-rich terminal emulator [SNP]"
PKG_METHOD[ghostty]="snap"
PKG_CATEGORY[ghostty]="terminals"

# GAMING
PACKAGES[steam]="steam"
PKG_DESC[steam]="Steam gaming platform [APT]"
PKG_METHOD[steam]="apt"
PKG_CATEGORY[steam]="gaming-platforms"

PACKAGES[heroic-launcher]="heroic"
PKG_DESC[heroic-launcher]="Open-source Epic Games/GOG launcher [SNP]"
PKG_METHOD[heroic-launcher]="snap"
PKG_CATEGORY[heroic-launcher]="gaming-platforms"
PKG_DEPS[heroic-launcher]="snapd"

PACKAGES[lutris]="lutris"
PKG_DESC[lutris]="Gaming on Linux made easy [APT]"
PKG_METHOD[lutris]="apt"
PKG_CATEGORY[lutris]="gaming-platforms"

PACKAGES[gamemode]="gamemode"
PKG_DESC[gamemode]="Optimize gaming performance [APT]"
PKG_METHOD[gamemode]="apt"
PKG_CATEGORY[gamemode]="gaming-platforms"

PACKAGES[gimp]="gimp"
PKG_DESC[gimp]="GIMP image editor [APT]"
PKG_METHOD[gimp]="apt"
PKG_CATEGORY[gimp]="graphics"

# OFFICE & PRODUCTIVITY
PACKAGES[libreoffice]="libreoffice"
PKG_DESC[libreoffice]="LibreOffice office suite [APT]"
PKG_METHOD[libreoffice]="apt"
PKG_CATEGORY[libreoffice]="office"

PACKAGES[thunderbird]="thunderbird"
PKG_DESC[thunderbird]="Thunderbird email client [APT]"
PKG_METHOD[thunderbird]="apt"
PKG_CATEGORY[thunderbird]="office"

PACKAGES[calibre]="calibre"
PKG_DESC[calibre]="E-book management [APT]"
PKG_METHOD[calibre]="apt"
PKG_CATEGORY[calibre]="office"

PACKAGES[obsidian]="obsidian"
PKG_DESC[obsidian]="Knowledge management [SNP]"
PKG_METHOD[obsidian]="snap"
PKG_CATEGORY[obsidian]="office"

# COMMUNICATION
PACKAGES[discord]="discord"
PKG_DESC[discord]="Discord voice and text chat [SNP]"
PKG_METHOD[discord]="snap"
PKG_CATEGORY[discord]="communication"

PACKAGES[telegram-desktop]="telegram-desktop"
PKG_DESC[telegram-desktop]="Telegram messaging app [APT]"
PKG_METHOD[telegram-desktop]="apt"
PKG_CATEGORY[telegram-desktop]="communication"

PACKAGES[zoom]="zoom-client"
PKG_DESC[zoom]="Zoom video conferencing [SNP]"
PKG_METHOD[zoom]="snap"
PKG_CATEGORY[zoom]="communication"

# MULTIMEDIA
PACKAGES[audacity]="audacity"
PKG_DESC[audacity]="Audacity audio editor [APT]"
PKG_METHOD[audacity]="apt"
PKG_CATEGORY[audacity]="audio"

PACKAGES[blender]="blender"
PKG_DESC[blender]="Blender 3D creation suite [SNP]"
PKG_METHOD[blender]="snap"
PKG_CATEGORY[blender]="graphics"

PACKAGES[inkscape]="inkscape"
PKG_DESC[inkscape]="Inkscape vector graphics editor [APT]"
PKG_METHOD[inkscape]="apt"
PKG_CATEGORY[inkscape]="graphics"

# AI & MODERN TOOLS
PACKAGES[ollama]="ollama"
PKG_DESC[ollama]="Local AI model runner (Llama, Mistral, etc.) [DEB]"
PKG_METHOD[ollama]="custom"
PKG_CATEGORY[ollama]="ai"

PACKAGES[gollama]="gollama"
PKG_DESC[gollama]="Advanced LLM model management and interaction tool [DEB]"
PKG_METHOD[gollama]="custom"
PKG_CATEGORY[gollama]="ai"

PACKAGES[lm-studio]="lm-studio"
PKG_DESC[lm-studio]="GUI for local LLMs (Ollama compatible) [APPIMAGE]"
PKG_METHOD[lm-studio]="custom"
PKG_CATEGORY[lm-studio]="ai"

PACKAGES[text-generation-webui]="text-generation-webui"
PKG_DESC[text-generation-webui]="Self-hosted interface for local LLMs [GIT]"
PKG_METHOD[text-generation-webui]="custom"
PKG_CATEGORY[text-generation-webui]="ai"

PACKAGES[whisper-cpp]="whisper-cpp"
PKG_DESC[whisper-cpp]="Offline speech-to-text engine [BUILD]"
PKG_METHOD[whisper-cpp]="custom"
PKG_CATEGORY[whisper-cpp]="ai"

PACKAGES[comfyui]="comfyui"
PKG_DESC[comfyui]="Visual Stable Diffusion node-based interface [GIT]"
PKG_METHOD[comfyui]="custom"
PKG_CATEGORY[comfyui]="ai"

PACKAGES[invokeai]="invokeai"
PKG_DESC[invokeai]="Stable Diffusion image generator [PYTHON]"
PKG_METHOD[invokeai]="custom"
PKG_CATEGORY[invokeai]="ai"

 

PACKAGES[koboldcpp]="koboldcpp"
PKG_DESC[koboldcpp]="LLM interface optimized for story and RP generation [BIN]"
PKG_METHOD[koboldcpp]="custom"
PKG_CATEGORY[koboldcpp]="ai"

PACKAGES[automatic1111]="automatic1111"
PKG_DESC[automatic1111]="Stable Diffusion WebUI - feature-packed interface [GIT]"
PKG_METHOD[automatic1111]="custom"
PKG_CATEGORY[automatic1111]="ai"

PACKAGES[fooocus]="fooocus"
PKG_DESC[fooocus]="Simplified Stable Diffusion frontend - zero-config [GIT]"
PKG_METHOD[fooocus]="custom"
PKG_CATEGORY[fooocus]="ai"

PACKAGES[sd-next]="sd-next"
PKG_DESC[sd-next]="Modernized fork of A1111 with optimizations [GIT]"
PKG_METHOD[sd-next]="custom"
PKG_CATEGORY[sd-next]="ai"

PACKAGES[kohya-ss-gui]="kohya-ss-gui"
PKG_DESC[kohya-ss-gui]="Fine-tune and train models with GUI [GIT]"
PKG_METHOD[kohya-ss-gui]="custom"
PKG_CATEGORY[kohya-ss-gui]="ai"



PACKAGES[ffmpeg]="ffmpeg"
PKG_DESC[ffmpeg]="Complete multimedia processing toolkit [APT]"
PKG_METHOD[ffmpeg]="apt"
PKG_CATEGORY[ffmpeg]="video"

PACKAGES[yt-dlp]="yt-dlp"
PKG_DESC[yt-dlp]="Modern YouTube/media downloader (youtube-dl fork) [APT]"
PKG_METHOD[yt-dlp]="apt"
PKG_CATEGORY[yt-dlp]="video"

PACKAGES[freetube]="freetube"
PKG_DESC[freetube]="Privacy-focused YouTube client [FLATPAK]"
PKG_METHOD[freetube]="flatpak"
PKG_CATEGORY[freetube]="video"

PACKAGES[invidious]="invidious"
PKG_DESC[invidious]="Alternative YouTube frontend [CUSTOM]"
PKG_METHOD[invidious]="custom"
PKG_CATEGORY[invidious]="video"

PACKAGES[mpv]="mpv"
PKG_DESC[mpv]="Minimalist media player [APT]"
PKG_METHOD[mpv]="apt"
PKG_CATEGORY[mpv]="video"

PACKAGES[kodi]="kodi"
PKG_DESC[kodi]="Open-source media center [APT]"
PKG_METHOD[kodi]="apt"
PKG_CATEGORY[kodi]="media-servers"

PACKAGES[stremio]="stremio"
PKG_DESC[stremio]="Modern media center with streaming [FLATPAK]"
PKG_METHOD[stremio]="flatpak"
PKG_CATEGORY[stremio]="media-servers"

# MEDIA SERVERS & STREAMING
PACKAGES[plex]="plexmediaserver"
PKG_DESC[plex]="Plex Media Server [CUSTOM]"
PKG_METHOD[plex]="custom"
PKG_CATEGORY[plex]="media-servers"

PACKAGES[jellyfin]="jellyfin"
PKG_DESC[jellyfin]="Free media server [APT]"
PKG_METHOD[jellyfin]="apt"
PKG_CATEGORY[jellyfin]="media-servers"

PACKAGES[ums]="ums"
PKG_DESC[ums]="Universal Media Server [CUSTOM]"
PKG_METHOD[ums]="custom"
PKG_CATEGORY[ums]="media-servers"

# MUSIC PRODUCTION & AUDIO
PACKAGES[ardour]="ardour"
PKG_DESC[ardour]="Professional digital audio workstation [APT]"
PKG_METHOD[ardour]="apt"
PKG_CATEGORY[ardour]="audio"

PACKAGES[lmms]="lmms"
PKG_DESC[lmms]="Free pattern-based music production suite [APT]"
PKG_METHOD[lmms]="apt"
PKG_CATEGORY[lmms]="audio"

PACKAGES[mixxx]="mixxx"
PKG_DESC[mixxx]="Open-source DJ software [APT]"
PKG_METHOD[mixxx]="apt"
PKG_CATEGORY[mixxx]="audio"

# GAMING & EMULATION
PACKAGES[retroarch]="retroarch"
PKG_DESC[retroarch]="Multi-system emulator frontend [APT]"
PKG_METHOD[retroarch]="apt"
PKG_CATEGORY[retroarch]="gaming-emulators"

PACKAGES[retroarch-snap]="retroarch"
PKG_DESC[retroarch-snap]="Multi-system emulator frontend [SNAP]"
PKG_METHOD[retroarch-snap]="snap"
PKG_CATEGORY[retroarch-snap]="gaming-emulators"

PACKAGES[retroarch-flatpak]="org.libretro.RetroArch"
PKG_DESC[retroarch-flatpak]="Multi-system emulator frontend [FLATPAK]"
PKG_METHOD[retroarch-flatpak]="flatpak"
PKG_CATEGORY[retroarch-flatpak]="gaming-emulators"

PACKAGES[mame]="mame"
PKG_DESC[mame]="Multiple Arcade Machine Emulator [APT]"
PKG_METHOD[mame]="apt"
PKG_CATEGORY[mame]="gaming-emulators"

PACKAGES[mame-flatpak]="net.mame.MAME"
PKG_DESC[mame-flatpak]="Multiple Arcade Machine Emulator [FLATPAK]"
PKG_METHOD[mame-flatpak]="flatpak"
PKG_CATEGORY[mame-flatpak]="gaming-emulators"

PACKAGES[dolphin-emu]="dolphin-emu"
PKG_DESC[dolphin-emu]="GameCube and Wii emulator [APT]"
PKG_METHOD[dolphin-emu]="apt"
PKG_CATEGORY[dolphin-emu]="gaming-emulators"

PACKAGES[dolphin-emu-flatpak]="org.DolphinEmu.dolphin-emu"
PKG_DESC[dolphin-emu-flatpak]="GameCube and Wii emulator [FLATPAK]"
PKG_METHOD[dolphin-emu-flatpak]="flatpak"
PKG_CATEGORY[dolphin-emu-flatpak]="gaming-emulators"

PACKAGES[pcsx2]="pcsx2"
PKG_DESC[pcsx2]="PlayStation 2 emulator [APT]"
PKG_METHOD[pcsx2]="apt"
PKG_CATEGORY[pcsx2]="gaming-emulators"

PACKAGES[pcsx2-flatpak]="net.pcsx2.PCSX2"
PKG_DESC[pcsx2-flatpak]="PlayStation 2 emulator [FLATPAK]"
PKG_METHOD[pcsx2-flatpak]="flatpak"
PKG_CATEGORY[pcsx2-flatpak]="gaming-emulators"

PACKAGES[rpcs3-flatpak]="net.rpcs3.RPCS3"
PKG_DESC[rpcs3-flatpak]="PlayStation 3 emulator [FLATPAK]"
PKG_METHOD[rpcs3-flatpak]="flatpak"
PKG_CATEGORY[rpcs3-flatpak]="gaming-emulators"

PACKAGES[yuzu-flatpak]="org.yuzu_emu.yuzu"
PKG_DESC[yuzu-flatpak]="Nintendo Switch emulator [FLATPAK]"
PKG_METHOD[yuzu-flatpak]="flatpak"
PKG_CATEGORY[yuzu-flatpak]="gaming-emulators"

PACKAGES[cemu-flatpak]="info.cemu.Cemu"
PKG_DESC[cemu-flatpak]="Wii U emulator [FLATPAK]"
PKG_METHOD[cemu-flatpak]="flatpak"
PKG_CATEGORY[cemu-flatpak]="gaming-emulators"

PACKAGES[mednafen]="mednafen"
PKG_DESC[mednafen]="Multi-system accurate emulator [APT]"
PKG_METHOD[mednafen]="apt"
PKG_CATEGORY[mednafen]="gaming-emulators"

PACKAGES[duckstation-flatpak]="org.duckstation.DuckStation"
PKG_DESC[duckstation-flatpak]="PlayStation 1 emulator [FLATPAK]"
PKG_METHOD[duckstation-flatpak]="flatpak"
PKG_CATEGORY[duckstation-flatpak]="gaming-emulators"

PACKAGES[bsnes]="bsnes"
PKG_DESC[bsnes]="Super Nintendo emulator [APT]"
PKG_METHOD[bsnes]="apt"
PKG_CATEGORY[bsnes]="gaming-emulators"

PACKAGES[mgba]="mgba-qt"
PKG_DESC[mgba]="Game Boy Advance emulator [APT]"
PKG_METHOD[mgba]="apt"
PKG_CATEGORY[mgba]="gaming-emulators"

PACKAGES[mgba-snap]="mgba"
PKG_DESC[mgba-snap]="Game Boy Advance emulator [SNAP]"
PKG_METHOD[mgba-snap]="snap"
PKG_CATEGORY[mgba-snap]="gaming-emulators"

PACKAGES[mgba-flatpak]="io.mgba.mGBA"
PKG_DESC[mgba-flatpak]="Game Boy Advance emulator [FLATPAK]"
PKG_METHOD[mgba-flatpak]="flatpak"
PKG_CATEGORY[mgba-flatpak]="gaming-emulators"

PACKAGES[desmume]="desmume"
PKG_DESC[desmume]="Nintendo DS emulator [APT]"
PKG_METHOD[desmume]="apt"
PKG_CATEGORY[desmume]="gaming-emulators"

PACKAGES[desmume-flatpak]="org.desmume.DeSmuME"
PKG_DESC[desmume-flatpak]="Nintendo DS emulator [FLATPAK]"
PKG_METHOD[desmume-flatpak]="flatpak"
PKG_CATEGORY[desmume-flatpak]="gaming-emulators"

PACKAGES[citra]="citra"
PKG_DESC[citra]="Nintendo 3DS emulator [APT]"
PKG_METHOD[citra]="apt"
PKG_CATEGORY[citra]="gaming-emulators"

PACKAGES[citra-flatpak]="org.citra_emu.citra"
PKG_DESC[citra-flatpak]="Nintendo 3DS emulator [FLATPAK]"
PKG_METHOD[citra-flatpak]="flatpak"
PKG_CATEGORY[citra-flatpak]="gaming-emulators"

PACKAGES[dosbox]="dosbox"
PKG_DESC[dosbox]="DOS emulator [APT]"
PKG_METHOD[dosbox]="apt"
PKG_CATEGORY[dosbox]="gaming-emulators"

PACKAGES[dosbox-snap]="dosbox"
PKG_DESC[dosbox-snap]="DOS emulator [SNAP]"
PKG_METHOD[dosbox-snap]="snap"
PKG_CATEGORY[dosbox-snap]="gaming-emulators"

PACKAGES[dosbox-flatpak]="com.dosbox.DOSBox"
PKG_DESC[dosbox-flatpak]="DOS emulator [FLATPAK]"
PKG_METHOD[dosbox-flatpak]="flatpak"
PKG_CATEGORY[dosbox-flatpak]="gaming-emulators"

PACKAGES[mupen64plus]="mupen64plus-qt"
PKG_DESC[mupen64plus]="Nintendo 64 emulator [APT]"
PKG_METHOD[mupen64plus]="apt"
PKG_CATEGORY[mupen64plus]="gaming-emulators"

PACKAGES[scummvm]="scummvm"
PKG_DESC[scummvm]="Adventure game engine [APT]"
PKG_METHOD[scummvm]="apt"
PKG_CATEGORY[scummvm]="gaming-emulators"

PACKAGES[scummvm-snap]="scummvm"
PKG_DESC[scummvm-snap]="Adventure game engine [SNAP]"
PKG_METHOD[scummvm-snap]="snap"
PKG_CATEGORY[scummvm-snap]="gaming-emulators"

PACKAGES[scummvm-flatpak]="org.scummvm.ScummVM"
PKG_DESC[scummvm-flatpak]="Adventure game engine [FLATPAK]"
PKG_METHOD[scummvm-flatpak]="flatpak"
PKG_CATEGORY[scummvm-flatpak]="gaming-emulators"

PACKAGES[qemu]="qemu-system"
PKG_DESC[qemu]="System hardware emulator [APT]"
PKG_METHOD[qemu]="apt"
PKG_CATEGORY[qemu]="gaming-emulators"

PACKAGES[wine]="wine"
PKG_DESC[wine]="Windows API compatibility layer [APT]"
PKG_METHOD[wine]="apt"
PKG_CATEGORY[wine]="gaming-platforms"

PACKAGES[wine-snap]="wine-platform-runtime"
PKG_DESC[wine-snap]="Windows API compatibility layer [SNAP]"
PKG_METHOD[wine-snap]="snap"
PKG_CATEGORY[wine-snap]="gaming-platforms"

PACKAGES[wine-flatpak]="org.winehq.Wine"
PKG_DESC[wine-flatpak]="Windows API compatibility layer [FLATPAK]"
PKG_METHOD[wine-flatpak]="flatpak"
PKG_CATEGORY[wine-flatpak]="gaming-platforms"

PACKAGES[stella]="stella"
PKG_DESC[stella]="Atari 2600 emulator [APT]"
PKG_METHOD[stella]="apt"
PKG_CATEGORY[stella]="gaming-emulators"

PACKAGES[dosbox-staging]="dosbox-staging"
PKG_DESC[dosbox-staging]="DOS emulator for retro PC games [APT]"
PKG_METHOD[dosbox-staging]="apt"
PKG_CATEGORY[dosbox-staging]="gaming-emulators"

PACKAGES[n8n]="n8n"
PKG_DESC[n8n]="Workflow automation tool (self-hosted Zapier alternative) [NPM]"
PKG_METHOD[n8n]="custom"
PKG_CATEGORY[n8n]="dev"

# ==============================================================================
# SINGLE BOARD COMPUTERS & MICROCONTROLLERS
# ==============================================================================

# Raspberry Pi Tools
PACKAGES[rpi-imager]="rpi-imager"
PKG_DESC[rpi-imager]="Official Raspberry Pi Imager for flashing OS images to SD cards [APT]"
PKG_METHOD[rpi-imager]="apt"
PKG_CATEGORY[rpi-imager]="sbc"

PACKAGES[balena-etcher]="balena-etcher-electron"
PKG_DESC[balena-etcher]="Flash OS images to SD cards and USB drives [DEB]"
PKG_METHOD[balena-etcher]="custom"
PKG_CATEGORY[balena-etcher]="sbc"

PACKAGES[rpi-config]="raspi-config"
PKG_DESC[rpi-config]="Raspberry Pi configuration tool [APT]"
PKG_METHOD[rpi-config]="apt"
PKG_CATEGORY[rpi-config]="sbc"

# Arduino Development
PACKAGES[arduino-ide]="arduino-ide"
PKG_DESC[arduino-ide]="Arduino IDE 2.0 - Modern Arduino development environment [DEB]"
PKG_METHOD[arduino-ide]="custom"
PKG_CATEGORY[arduino-ide]="sbc"

PACKAGES[arduino-cli]="arduino-cli"
PKG_DESC[arduino-cli]="Arduino command line interface [BINARY]"
PKG_METHOD[arduino-cli]="custom"
PKG_CATEGORY[arduino-cli]="sbc"

PACKAGES[platformio]="platformio"
PKG_DESC[platformio]="Professional collaborative platform for embedded development [SNP]"
PKG_METHOD[platformio]="snap"
PKG_CATEGORY[platformio]="sbc"

# ESP32/ESP8266 Tools
PACKAGES[esptool]="python3-esptool"
PKG_DESC[esptool]="ESP32/ESP8266 ROM bootloader utility [APT]"
PKG_METHOD[esptool]="apt"
PKG_CATEGORY[esptool]="sbc"

PACKAGES[esp-idf]="esp-idf"
PKG_DESC[esp-idf]="Espressif IoT Development Framework [CUSTOM]"
PKG_METHOD[esp-idf]="custom"
PKG_CATEGORY[esp-idf]="sbc"

# Cross-compilation and embedded tools
PACKAGES[gcc-arm-none-eabi]="gcc-arm-none-eabi"
PKG_DESC[gcc-arm-none-eabi]="ARM Cortex-M and Cortex-R cross-compiler [APT]"
PKG_METHOD[gcc-arm-none-eabi]="apt"
PKG_CATEGORY[gcc-arm-none-eabi]="sbc"

PACKAGES[openocd]="openocd"
PKG_DESC[openocd]="Open On-Chip Debugger for ARM and other processors [APT]"
PKG_METHOD[openocd]="apt"
PKG_CATEGORY[openocd]="sbc"

PACKAGES[gdb-multiarch]="gdb-multiarch"
PKG_DESC[gdb-multiarch]="GNU Debugger with support for multiple architectures [APT]"
PKG_METHOD[gdb-multiarch]="apt"
PKG_CATEGORY[gdb-multiarch]="sbc"

# Orange Pi and other SBC tools
PACKAGES[sunxi-tools]="sunxi-tools"
PKG_DESC[sunxi-tools]="Tools for Allwinner SoCs (Orange Pi, Banana Pi) [APT]"
PKG_METHOD[sunxi-tools]="apt"
PKG_CATEGORY[sunxi-tools]="sbc"

PACKAGES[u-boot-tools]="u-boot-tools"
PKG_DESC[u-boot-tools]="Das U-Boot bootloader utilities [APT]"
PKG_METHOD[u-boot-tools]="apt"
PKG_CATEGORY[u-boot-tools]="sbc"

# Serial communication
PACKAGES[minicom]="minicom"
PKG_DESC[minicom]="Serial communication program [APT]"
PKG_METHOD[minicom]="apt"
PKG_CATEGORY[minicom]="sbc"

PACKAGES[screen]="screen"
PKG_DESC[screen]="Terminal multiplexer with serial support [APT]"
PKG_METHOD[screen]="apt"
PKG_CATEGORY[screen]="sbc"

PACKAGES[picocom]="picocom"
PKG_DESC[picocom]="Minimal dumb-terminal emulation program [APT]"
PKG_METHOD[picocom]="apt"
PKG_CATEGORY[picocom]="sbc"

# GPIO and hardware interfacing
PACKAGES[wiringpi]="wiringpi"
PKG_DESC[wiringpi]="GPIO interface library for Raspberry Pi [APT]"
PKG_METHOD[wiringpi]="apt"
PKG_CATEGORY[wiringpi]="sbc"

PACKAGES[rpi-gpio]="python3-rpi.gpio"
PKG_DESC[rpi-gpio]="Python library for Raspberry Pi GPIO control [APT]"
PKG_METHOD[rpi-gpio]="apt"
PKG_CATEGORY[rpi-gpio]="sbc"

PACKAGES[gpiozero]="python3-gpiozero"
PKG_DESC[gpiozero]="Simple GPIO library for Raspberry Pi [APT]"
PKG_METHOD[gpiozero]="apt"
PKG_CATEGORY[gpiozero]="sbc"

# Firmware and bootloader tools
PACKAGES[dfu-util]="dfu-util"
PKG_DESC[dfu-util]="Device Firmware Upgrade utilities [APT]"
PKG_METHOD[dfu-util]="apt"
PKG_CATEGORY[dfu-util]="sbc"

PACKAGES[stlink-tools]="stlink-tools"
PKG_DESC[stlink-tools]="STMicroelectronics STLink tools [APT]"
PKG_METHOD[stlink-tools]="apt"
PKG_CATEGORY[stlink-tools]="sbc"

PACKAGES[avrdude]="avrdude"
PKG_DESC[avrdude]="AVR microcontroller programmer [APT]"
PKG_METHOD[avrdude]="apt"
PKG_CATEGORY[avrdude]="sbc"

# Circuit simulation and design
PACKAGES[kicad]="kicad"
PKG_DESC[kicad]="Electronic schematic and PCB design suite [APT]"
PKG_METHOD[kicad]="apt"
PKG_CATEGORY[kicad]="sbc"

PACKAGES[fritzing]="fritzing"
PKG_DESC[fritzing]="Electronic prototyping platform [APT]"
PKG_METHOD[fritzing]="apt"
PKG_CATEGORY[fritzing]="sbc"

# IoT and networking tools
PACKAGES[mosquitto-clients]="mosquitto-clients"
PKG_DESC[mosquitto-clients]="MQTT client tools [APT]"
PKG_METHOD[mosquitto-clients]="apt"
PKG_CATEGORY[mosquitto-clients]="sbc"

PACKAGES[node-red]="node-red"
PKG_DESC[node-red]="Flow-based programming for IoT [NPM]"
PKG_METHOD[node-red]="npm"
PKG_CATEGORY[node-red]="sbc"

# ==============================================================================
# ALTERNATIVE INSTALLATION METHODS
# ==============================================================================
# Apps that have multiple installation options - users can choose their preferred method

# VS Code alternatives
PACKAGES[vscode-snap]="code"
PKG_DESC[vscode-snap]="Visual Studio Code [SNP] - Alternative to DEB version"
PKG_METHOD[vscode-snap]="snap"
PKG_CATEGORY[vscode-snap]="editors"

PACKAGES[vscode-flatpak]="com.visualstudio.code"
PKG_DESC[vscode-flatpak]="Visual Studio Code [FLT] - Alternative to DEB version"
PKG_METHOD[vscode-flatpak]="flatpak"
PKG_CATEGORY[vscode-flatpak]="editors"
PKG_DEPS[vscode-flatpak]="flatpak"

# Firefox alternatives
PACKAGES[firefox-snap]="firefox"
PKG_DESC[firefox-snap]="Mozilla Firefox browser [SNP] - Alternative to APT version"
PKG_METHOD[firefox-snap]="snap"
PKG_CATEGORY[firefox-snap]="browsers"

PACKAGES[firefox-flatpak]="org.mozilla.firefox"
PKG_DESC[firefox-flatpak]="Mozilla Firefox browser [FLT] - Alternative to APT version"
PKG_METHOD[firefox-flatpak]="flatpak"
PKG_CATEGORY[firefox-flatpak]="browsers"
PKG_DEPS[firefox-flatpak]="flatpak"

# Chromium alternatives
PACKAGES[chromium-snap]="chromium"
PKG_DESC[chromium-snap]="Chromium web browser [SNP] - Alternative to APT version"
PKG_METHOD[chromium-snap]="snap"
PKG_CATEGORY[chromium-snap]="browsers"

PACKAGES[chromium-flatpak]="org.chromium.Chromium"
PKG_DESC[chromium-flatpak]="Chromium web browser [FLT] - Alternative to APT version"
PKG_METHOD[chromium-flatpak]="flatpak"
PKG_CATEGORY[chromium-flatpak]="browsers"
PKG_DEPS[chromium-flatpak]="flatpak"

# VLC alternatives
PACKAGES[vlc-snap]="vlc"
PKG_DESC[vlc-snap]="VLC media player [SNP] - Alternative to APT version"
PKG_METHOD[vlc-snap]="snap"
PKG_CATEGORY[vlc-snap]="video"

PACKAGES[vlc-flatpak]="org.videolan.VLC"
PKG_DESC[vlc-flatpak]="VLC media player [FLT] - Alternative to APT version"
PKG_METHOD[vlc-flatpak]="flatpak"
PKG_CATEGORY[vlc-flatpak]="video"
PKG_DEPS[vlc-flatpak]="flatpak"

# GIMP alternatives
PACKAGES[gimp-snap]="gimp"
PKG_DESC[gimp-snap]="GIMP image editor [SNP] - Alternative to APT version"
PKG_METHOD[gimp-snap]="snap"
PKG_CATEGORY[gimp-snap]="graphics"

PACKAGES[gimp-flatpak]="org.gimp.GIMP"
PKG_DESC[gimp-flatpak]="GIMP image editor [FLT] - Alternative to APT version"
PKG_METHOD[gimp-flatpak]="flatpak"
PKG_CATEGORY[gimp-flatpak]="graphics"
PKG_DEPS[gimp-flatpak]="flatpak"

# OBS Studio alternatives
PACKAGES[obs-studio-flatpak]="com.obsproject.Studio"
PKG_DESC[obs-studio-flatpak]="OBS Studio streaming/recording [FLT] - Alternative to APT version"
PKG_METHOD[obs-studio-flatpak]="flatpak"
PKG_CATEGORY[obs-studio-flatpak]="video"
PKG_DEPS[obs-studio-flatpak]="flatpak"

# Discord alternatives (APT version)
PACKAGES[discord-deb]="discord"
PKG_DESC[discord-deb]="Discord voice and text chat [DEB] - Alternative to SNP version"
PKG_METHOD[discord-deb]="custom"
PKG_CATEGORY[discord-deb]="communication"

PACKAGES[discord-flatpak]="com.discordapp.Discord"
PKG_DESC[discord-flatpak]="Discord voice and text chat [FLT] - Alternative to SNP version"
PKG_METHOD[discord-flatpak]="flatpak"
PKG_CATEGORY[discord-flatpak]="communication"
PKG_DEPS[discord-flatpak]="flatpak"

# Audacity alternatives
PACKAGES[audacity-snap]="audacity"
PKG_DESC[audacity-snap]="Audacity audio editor [SNP] - Alternative to APT version"
PKG_METHOD[audacity-snap]="snap"
PKG_CATEGORY[audacity-snap]="audio"

PACKAGES[audacity-flatpak]="org.audacityteam.Audacity"
PKG_DESC[audacity-flatpak]="Audacity audio editor [FLT] - Alternative to APT version"
PKG_METHOD[audacity-flatpak]="flatpak"
PKG_CATEGORY[audacity-flatpak]="audio"
PKG_DEPS[audacity-flatpak]="flatpak"

# Inkscape alternatives
PACKAGES[inkscape-snap]="inkscape"
PKG_DESC[inkscape-snap]="Inkscape vector graphics [SNP] - Alternative to APT version"
PKG_METHOD[inkscape-snap]="snap"
PKG_CATEGORY[inkscape-snap]="graphics"

PACKAGES[inkscape-flatpak]="org.inkscape.Inkscape"
PKG_DESC[inkscape-flatpak]="Inkscape vector graphics [FLT] - Alternative to APT version"
PKG_METHOD[inkscape-flatpak]="flatpak"
PKG_CATEGORY[inkscape-flatpak]="graphics"
PKG_DEPS[inkscape-flatpak]="flatpak"

# Drawing and Creative Tools
PACKAGES[webcamize]="webcamize"
PKG_DESC[webcamize]="Webcam effects and virtual camera tool [APT]"
PKG_METHOD[webcamize]="apt"
PKG_CATEGORY[webcamize]="graphics"


PACKAGES[pastel]="pastel"
PKG_DESC[pastel]="Command-line tool for color manipulation and palette generation [APT]"
PKG_METHOD[pastel]="apt"
PKG_CATEGORY[pastel]="graphics"

# Disk Management Tools
PACKAGES[dysk]="dysk"
PKG_DESC[dysk]="Modern disk usage analyzer with colorful output [CARGO]"
PKG_METHOD[dysk]="cargo"
PKG_CATEGORY[dysk]="system"

# STORAGE MANAGEMENT
PACKAGES[lvm2]="lvm2"
PKG_DESC[lvm2]="Logical Volume Manager for flexible disk management [APT]"
PKG_METHOD[lvm2]="apt"
PKG_CATEGORY[lvm2]="system"

PACKAGES[snapraid]="snapraid"
PKG_DESC[snapraid]="Parity protection for different sized disks [CUSTOM]"
PKG_METHOD[snapraid]="custom"
PKG_CATEGORY[snapraid]="system"

PACKAGES[greyhole]="greyhole"
PKG_DESC[greyhole]="Samba-based storage pooling with redundancy [CUSTOM]"
PKG_METHOD[greyhole]="custom"
PKG_CATEGORY[greyhole]="system"

PACKAGES[mergerfs]="mergerfs"
PKG_DESC[mergerfs]="Union filesystem for pooling drives [CUSTOM]"
PKG_METHOD[mergerfs]="custom"
PKG_CATEGORY[mergerfs]="system"

# Additional CLI tools from awesome-cli-apps
PACKAGES[nmap]="nmap"
PKG_DESC[nmap]="Network exploration tool and security scanner [APT]"
PKG_METHOD[nmap]="apt"
PKG_CATEGORY[nmap]="network-monitoring"

PACKAGES[httpie]="httpie"
PKG_DESC[httpie]="Modern command-line HTTP client [APT]"
PKG_METHOD[httpie]="apt"
PKG_CATEGORY[httpie]="dev"

PACKAGES[ranger]="ranger"
PKG_DESC[ranger]="Console file manager with VI key bindings [APT]"
PKG_METHOD[ranger]="apt"
PKG_CATEGORY[ranger]="utilities"

PACKAGES[mc]="mc"
PKG_DESC[mc]="Midnight Commander file manager [APT]"
PKG_METHOD[mc]="apt"
PKG_CATEGORY[mc]="utilities"

PACKAGES[ag]="silversearcher-ag"
PKG_DESC[ag]="The Silver Searcher - fast text search [APT]"
PKG_METHOD[ag]="apt"
PKG_CATEGORY[ag]="utilities"

PACKAGES[thefuck]="thefuck"
PKG_DESC[thefuck]="Corrects errors in previous console commands [APT]"
PKG_METHOD[thefuck]="apt"
PKG_CATEGORY[thefuck]="utilities"

PACKAGES[lazygit]="lazygit"
PKG_DESC[lazygit]="Simple terminal UI for git commands [CUSTOM]"
PKG_METHOD[lazygit]="custom"
PKG_CATEGORY[lazygit]="dev"

PACKAGES[glow]="glow"
PKG_DESC[glow]="Terminal based markdown reader [CUSTOM]"
PKG_METHOD[glow]="custom"
PKG_CATEGORY[glow]="utilities"

PACKAGES[cheat]="cheat"
PKG_DESC[cheat]="Interactive cheatsheets on the command-line [CUSTOM]"
PKG_METHOD[cheat]="custom"
PKG_CATEGORY[cheat]="utilities"

PACKAGES[broot]="broot"
PKG_DESC[broot]="A new way to see and navigate directory trees [CUSTOM]"
PKG_METHOD[broot]="custom"
PKG_CATEGORY[broot]="utilities"

PACKAGES[dog]="dog"
PKG_DESC[dog]="Command-line DNS lookup tool [CUSTOM]"
PKG_METHOD[dog]="custom"
PKG_CATEGORY[dog]="network-monitoring"

# Entertainment
PACKAGES[newsboat]="newsboat"
PKG_DESC[newsboat]="An RSS/Atom feed reader for text terminals [APT]"
PKG_METHOD[newsboat]="apt"
PKG_CATEGORY[newsboat]="fun"

PACKAGES[mal-cli]="mal-cli"
PKG_DESC[mal-cli]="MyAnimeList command line client [CUSTOM]"
PKG_METHOD[mal-cli]="custom"
PKG_CATEGORY[mal-cli]="fun"

# Music
PACKAGES[cmus]="cmus"
PKG_DESC[cmus]="Small, fast and powerful console music player [APT]"
PKG_METHOD[cmus]="apt"
PKG_CATEGORY[cmus]="audio"

PACKAGES[pianobar]="pianobar"
PKG_DESC[pianobar]="Console-based Pandora client [APT]"
PKG_METHOD[pianobar]="apt"
PKG_CATEGORY[pianobar]="audio"

PACKAGES[somafm-cli]="somafm-cli"
PKG_DESC[somafm-cli]="Listen to SomaFM in your terminal [CUSTOM]"
PKG_METHOD[somafm-cli]="custom"
PKG_CATEGORY[somafm-cli]="audio"

PACKAGES[mpd]="mpd"
PKG_DESC[mpd]="Music Player Daemon [APT]"
PKG_METHOD[mpd]="apt"
PKG_CATEGORY[mpd]="audio"

PACKAGES[ncmpcpp]="ncmpcpp"
PKG_DESC[ncmpcpp]="NCurses Music Player Client (Plus Plus) [APT]"
PKG_METHOD[ncmpcpp]="apt"
PKG_CATEGORY[ncmpcpp]="audio"

PACKAGES[moc]="moc"
PKG_DESC[moc]="Console audio player for Linux/UNIX [APT]"
PKG_METHOD[moc]="apt"
PKG_CATEGORY[moc]="audio"

PACKAGES[musikcube]="musikcube"
PKG_DESC[musikcube]="Cross-platform terminal-based music player [CUSTOM]"
PKG_METHOD[musikcube]="custom"
PKG_CATEGORY[musikcube]="audio"

PACKAGES[beets]="beets"
PKG_DESC[beets]="Music library manager and MusicBrainz tagger [APT]"
PKG_METHOD[beets]="apt"
PKG_CATEGORY[beets]="audio"

PACKAGES[spotify-tui]="spotify-tui"
PKG_DESC[spotify-tui]="Spotify for the terminal written in Rust [CUSTOM]"
PKG_METHOD[spotify-tui]="custom"
PKG_CATEGORY[spotify-tui]="audio"

PACKAGES[swaglyrics-for-spotify]="swaglyrics-for-spotify"
PKG_DESC[swaglyrics-for-spotify]="Spotify lyrics in your terminal [CUSTOM]"
PKG_METHOD[swaglyrics-for-spotify]="custom"
PKG_CATEGORY[swaglyrics-for-spotify]="audio"

PACKAGES[dzr]="dzr"
PKG_DESC[dzr]="Command line Deezer player [CUSTOM]"
PKG_METHOD[dzr]="custom"
PKG_CATEGORY[dzr]="audio"

PACKAGES[radio-active]="radio-active"
PKG_DESC[radio-active]="Internet radio player with 40k+ stations [CUSTOM]"
PKG_METHOD[radio-active]="custom"
PKG_CATEGORY[radio-active]="audio"

PACKAGES[mpvc]="mpvc"
PKG_DESC[mpvc]="Music player interfacing mpv [CUSTOM]"
PKG_METHOD[mpvc]="custom"
PKG_CATEGORY[mpvc]="audio"

# Video
PACKAGES[streamlink]="streamlink"
PKG_DESC[streamlink]="Extract streams from various websites [APT]"
PKG_METHOD[streamlink]="apt"
PKG_CATEGORY[streamlink]="video"

PACKAGES[mps-youtube]="mps-youtube"
PKG_DESC[mps-youtube]="Terminal based YouTube player and downloader [CUSTOM]"
PKG_METHOD[mps-youtube]="custom"
PKG_CATEGORY[mps-youtube]="video"

PACKAGES[editly]="editly"
PKG_DESC[editly]="Declarative command line video editing [CUSTOM]"
PKG_METHOD[editly]="custom"
PKG_CATEGORY[editly]="video"

# Movies
PACKAGES[moviemon]="moviemon"
PKG_DESC[moviemon]="Everything about your movies within the command line [CUSTOM]"
PKG_METHOD[moviemon]="custom"
PKG_CATEGORY[moviemon]="fun"

PACKAGES[movie]="movie"
PKG_DESC[movie]="Get movie info or compare movies in terminal [CUSTOM]"
PKG_METHOD[movie]="custom"
PKG_CATEGORY[movie]="fun"

# Games
PACKAGES[pokete]="pokete"
PKG_DESC[pokete]="A terminal based Pokemon like game [CUSTOM]"
PKG_METHOD[pokete]="custom"
PKG_CATEGORY[pokete]="fun"

# Books
PACKAGES[epr]="epr"
PKG_DESC[epr]="CLI Epub reader [CUSTOM]"
PKG_METHOD[epr]="custom"
PKG_CATEGORY[epr]="utilities"

PACKAGES[speedread]="speedread"
PKG_DESC[speedread]="A simple terminal-based speed reading tool [CUSTOM]"
PKG_METHOD[speedread]="custom"
PKG_CATEGORY[speedread]="utilities"

PACKAGES[medium-cli]="medium-cli"
PKG_DESC[medium-cli]="Read medium.com stories within terminal [CUSTOM]"
PKG_METHOD[medium-cli]="custom"
PKG_CATEGORY[medium-cli]="utilities"

PACKAGES[hygg]="hygg"
PKG_DESC[hygg]="Document reader for various formats [CUSTOM]"
PKG_METHOD[hygg]="custom"
PKG_CATEGORY[hygg]="utilities"

# Chat
PACKAGES[weechat]="weechat"
PKG_DESC[weechat]="Fast, light and extensible chat client [APT]"
PKG_METHOD[weechat]="apt"
PKG_CATEGORY[weechat]="communication"

PACKAGES[irssi]="irssi"
PKG_DESC[irssi]="Terminal based IRC client [APT]"
PKG_METHOD[irssi]="apt"
PKG_CATEGORY[irssi]="communication"

PACKAGES[kirc]="kirc"
PKG_DESC[kirc]="A tiny IRC client written in POSIX C99 [CUSTOM]"
PKG_METHOD[kirc]="custom"
PKG_CATEGORY[kirc]="communication"

# Development Tools
PACKAGES[legit]="legit"
PKG_DESC[legit]="Generate Open Source licenses as files or headers [CUSTOM]"
PKG_METHOD[legit]="custom"
PKG_CATEGORY[legit]="dev"

PACKAGES[mklicense]="mklicense"
PKG_DESC[mklicense]="Create a custom LICENSE file painlessly [CUSTOM]"
PKG_METHOD[mklicense]="custom"
PKG_CATEGORY[mklicense]="dev"

PACKAGES[rebound]="rebound"
PKG_DESC[rebound]="Fetch Stack Overflow results on compiler error [CUSTOM]"
PKG_METHOD[rebound]="custom"
PKG_CATEGORY[rebound]="dev"

PACKAGES[foy]="foy"
PKG_DESC[foy]="Lightweight general purpose task runner/build tool [CUSTOM]"
PKG_METHOD[foy]="custom"
PKG_CATEGORY[foy]="dev"

PACKAGES[just]="just"
PKG_DESC[just]="A handy way to save and run project-specific commands [CUSTOM]"
PKG_METHOD[just]="custom"
PKG_CATEGORY[just]="dev"

PACKAGES[bcal]="bcal"
PKG_DESC[bcal]="Byte CALculator for storage conversions and calculations [CUSTOM]"
PKG_METHOD[bcal]="custom"
PKG_CATEGORY[bcal]="dev"

PACKAGES[bitwise]="bitwise"
PKG_DESC[bitwise]="Base conversion and bit manipulation [CUSTOM]"
PKG_METHOD[bitwise]="custom"
PKG_CATEGORY[bitwise]="dev"

PACKAGES[cgasm]="cgasm"
PKG_DESC[cgasm]="x86 assembly documentation [CUSTOM]"
PKG_METHOD[cgasm]="custom"
PKG_CATEGORY[cgasm]="dev"

PACKAGES[grex]="grex"
PKG_DESC[grex]="Generate regular expressions from user-provided test cases [CUSTOM]"
PKG_METHOD[grex]="custom"
PKG_CATEGORY[grex]="dev"

PACKAGES[iola]="iola"
PKG_DESC[iola]="Socket client with REST API [CUSTOM]"
PKG_METHOD[iola]="custom"
PKG_CATEGORY[iola]="dev"

PACKAGES[add-gitignore]="add-gitignore"
PKG_DESC[add-gitignore]="Interactively generate a .gitignore for your project [CUSTOM]"
PKG_METHOD[add-gitignore]="custom"
PKG_CATEGORY[add-gitignore]="dev"

PACKAGES[is-up-cli]="is-up-cli"
PKG_DESC[is-up-cli]="Check if a domain is up [CUSTOM]"
PKG_METHOD[is-up-cli]="custom"
PKG_CATEGORY[is-up-cli]="dev"

PACKAGES[reachable]="reachable"
PKG_DESC[reachable]="Check if a domain is up [CUSTOM]"
PKG_METHOD[reachable]="custom"
PKG_CATEGORY[reachable]="dev"

PACKAGES[diff2html-cli]="diff2html-cli"
PKG_DESC[diff2html-cli]="Create pretty HTML from diffs [CUSTOM]"
PKG_METHOD[diff2html-cli]="custom"
PKG_CATEGORY[diff2html-cli]="dev"

# Text Editors
PACKAGES[vim]="vim"
PKG_DESC[vim]="Vi IMproved - enhanced vi editor [APT]"
PKG_METHOD[vim]="apt"
PKG_CATEGORY[vim]="editors"

PACKAGES[emacs]="emacs"
PKG_DESC[emacs]="GNU Emacs editor [APT]"
PKG_METHOD[emacs]="apt"
PKG_CATEGORY[emacs]="editors"

PACKAGES[kakoune]="kakoune"
PKG_DESC[kakoune]="Modal editor inspired by vim [APT]"
PKG_METHOD[kakoune]="apt"
PKG_CATEGORY[kakoune]="editors"

PACKAGES[o]="o"
PKG_DESC[o]="Configuration-free text editor and IDE [CUSTOM]"
PKG_METHOD[o]="custom"
PKG_CATEGORY[o]="editors"

PACKAGES[helix]="helix"
PKG_DESC[helix]="A post-modern modal text editor [CUSTOM]"
PKG_METHOD[helix]="custom"
PKG_CATEGORY[helix]="editors"

# Frontend Development
PACKAGES[caniuse-cmd]="caniuse-cmd"
PKG_DESC[caniuse-cmd]="Search caniuse.com about browser support [CUSTOM]"
PKG_METHOD[caniuse-cmd]="custom"
PKG_CATEGORY[caniuse-cmd]="dev"

PACKAGES[strip-css-comments-cli]="strip-css-comments-cli"
PKG_DESC[strip-css-comments-cli]="Strip comments from CSS [CUSTOM]"
PKG_METHOD[strip-css-comments-cli]="custom"
PKG_CATEGORY[strip-css-comments-cli]="dev"

PACKAGES[viewport-list-cli]="viewport-list-cli"
PKG_DESC[viewport-list-cli]="Return a list of devices and their viewports [CUSTOM]"
PKG_METHOD[viewport-list-cli]="custom"
PKG_CATEGORY[viewport-list-cli]="dev"

PACKAGES[surge]="surge"
PKG_DESC[surge]="Publish static websites for free [CUSTOM]"
PKG_METHOD[surge]="custom"
PKG_CATEGORY[surge]="dev"

# Public localhost
PACKAGES[localtunnel]="localtunnel"
PKG_DESC[localtunnel]="Expose localhost to the world for easy testing [CUSTOM]"
PKG_METHOD[localtunnel]="custom"
PKG_CATEGORY[localtunnel]="dev"

PACKAGES[tunnelmole]="tunnelmole"
PKG_DESC[tunnelmole]="Connect to localhost from anywhere [CUSTOM]"
PKG_METHOD[tunnelmole]="custom"
PKG_CATEGORY[tunnelmole]="dev"

# Mobile Development
PACKAGES[mobicon-cli]="mobicon-cli"
PKG_DESC[mobicon-cli]="Mobile app icon generator [CUSTOM]"
PKG_METHOD[mobicon-cli]="custom"
PKG_CATEGORY[mobicon-cli]="dev"

PACKAGES[mobisplash-cli]="mobisplash-cli"
PKG_DESC[mobisplash-cli]="Mobile app splash screen generator [CUSTOM]"
PKG_METHOD[mobisplash-cli]="custom"
PKG_CATEGORY[mobisplash-cli]="dev"

PACKAGES[deviceframe]="deviceframe"
PKG_DESC[deviceframe]="Put device frames around your screenshots [CUSTOM]"
PKG_METHOD[deviceframe]="custom"
PKG_CATEGORY[deviceframe]="dev"

# Database
PACKAGES[sqlline]="sqlline"
PKG_DESC[sqlline]="Shell for issuing SQL via JDBC [CUSTOM]"
PKG_METHOD[sqlline]="custom"
PKG_CATEGORY[sqlline]="database"

PACKAGES[iredis]="iredis"
PKG_DESC[iredis]="Redis client with autocompletion and syntax highlighting [CUSTOM]"
PKG_METHOD[iredis]="custom"
PKG_CATEGORY[iredis]="database"

PACKAGES[usql]="usql"
PKG_DESC[usql]="Universal SQL client with autocompletion [CUSTOM]"
PKG_METHOD[usql]="custom"
PKG_CATEGORY[usql]="database"

# DevOps
PACKAGES[htconvert]="htconvert"
PKG_DESC[htconvert]="Convert .htaccess redirects to nginx.conf redirects [CUSTOM]"
PKG_METHOD[htconvert]="custom"
PKG_CATEGORY[htconvert]="dev"

PACKAGES[saws]="saws"
PKG_DESC[saws]="Supercharged AWS CLI [CUSTOM]"
PKG_METHOD[saws]="custom"
PKG_CATEGORY[saws]="dev"

PACKAGES[s3cmd]="s3cmd"
PKG_DESC[s3cmd]="Fully-Featured S3 client [APT]"
PKG_METHOD[s3cmd]="apt"
PKG_CATEGORY[s3cmd]="dev"

PACKAGES[ops]="ops"
PKG_DESC[ops]="Unikernel compilation and orchestration tool [CUSTOM]"
PKG_METHOD[ops]="custom"
PKG_CATEGORY[ops]="dev"

PACKAGES[flog]="flog"
PKG_DESC[flog]="A fake log generator for common log formats [CUSTOM]"
PKG_METHOD[flog]="custom"
PKG_CATEGORY[flog]="dev"

PACKAGES[k9s]="k9s"
PKG_DESC[k9s]="Kubernetes CLI To Manage Your Clusters In Style [CUSTOM]"
PKG_METHOD[k9s]="custom"
PKG_CATEGORY[k9s]="containers"

PACKAGES[pingme]="pingme"
PKG_DESC[pingme]="Send messages/alerts to multiple messaging platforms [CUSTOM]"
PKG_METHOD[pingme]="custom"
PKG_CATEGORY[pingme]="dev"

PACKAGES[ipfs-deploy]="ipfs-deploy"
PKG_DESC[ipfs-deploy]="Deploy static websites to IPFS [CUSTOM]"
PKG_METHOD[ipfs-deploy]="custom"
PKG_CATEGORY[ipfs-deploy]="dev"

PACKAGES[discharge]="discharge"
PKG_DESC[discharge]="Deploy static websites to Amazon S3 [CUSTOM]"
PKG_METHOD[discharge]="custom"
PKG_CATEGORY[discharge]="dev"

PACKAGES[updatecli]="updatecli"
PKG_DESC[updatecli]="A declarative dependency management tool [CUSTOM]"
PKG_METHOD[updatecli]="custom"
PKG_CATEGORY[updatecli]="dev"

PACKAGES[telert]="telert"
PKG_DESC[telert]="Multi-channel alerts for long-running commands [CUSTOM]"
PKG_METHOD[telert]="custom"
PKG_CATEGORY[telert]="dev"

PACKAGES[logdy]="logdy"
PKG_DESC[logdy]="Supercharge terminal logs with web UI [CUSTOM]"
PKG_METHOD[logdy]="custom"
PKG_CATEGORY[logdy]="dev"

PACKAGES[s5cmd]="s5cmd"
PKG_DESC[s5cmd]="Blazing fast S3 and local filesystem execution tool [CUSTOM]"
PKG_METHOD[s5cmd]="custom"
PKG_CATEGORY[s5cmd]="dev"

# Docker
PACKAGES[lstags]="lstags"
PKG_DESC[lstags]="Synchronize images across registries [CUSTOM]"
PKG_METHOD[lstags]="custom"
PKG_CATEGORY[lstags]="containers"

PACKAGES[dockly]="dockly"
PKG_DESC[dockly]="Interactively manage containers [CUSTOM]"
PKG_METHOD[dockly]="custom"
PKG_CATEGORY[dockly]="containers"

PACKAGES[docker-pushrm]="docker-pushrm"
PKG_DESC[docker-pushrm]="Push a readme to container registries [CUSTOM]"
PKG_METHOD[docker-pushrm]="custom"
PKG_CATEGORY[docker-pushrm]="containers"

# Release
PACKAGES[release-it]="release-it"
PKG_DESC[release-it]="Automate releases for Git repositories and npm packages [CUSTOM]"
PKG_METHOD[release-it]="custom"
PKG_CATEGORY[release-it]="dev"

PACKAGES[clog]="clog"
PKG_DESC[clog]="A conventional changelog for the rest of us [CUSTOM]"
PKG_METHOD[clog]="custom"
PKG_CATEGORY[clog]="dev"

PACKAGES[np]="np"
PKG_DESC[np]="A better npm publish [CUSTOM]"
PKG_METHOD[np]="custom"
PKG_CATEGORY[np]="dev"

PACKAGES[release]="release"
PKG_DESC[release]="Generate changelogs with a single command [CUSTOM]"
PKG_METHOD[release]="custom"
PKG_CATEGORY[release]="dev"

PACKAGES[semantic-release]="semantic-release"
PKG_DESC[semantic-release]="Fully automated version management and package publishing [CUSTOM]"
PKG_METHOD[semantic-release]="custom"
PKG_CATEGORY[semantic-release]="dev"

# NPM
PACKAGES[npm-name-cli]="npm-name-cli"
PKG_DESC[npm-name-cli]="Check whether a package name is available on npm [CUSTOM]"
PKG_METHOD[npm-name-cli]="custom"
PKG_CATEGORY[npm-name-cli]="dev"

PACKAGES[npm-user-cli]="npm-user-cli"
PKG_DESC[npm-user-cli]="Get user info of a npm user [CUSTOM]"
PKG_METHOD[npm-user-cli]="custom"
PKG_CATEGORY[npm-user-cli]="dev"

PACKAGES[npm-home]="npm-home"
PKG_DESC[npm-home]="Open the npm page of the package in the current directory [CUSTOM]"
PKG_METHOD[npm-home]="custom"
PKG_CATEGORY[npm-home]="dev"

PACKAGES[pkg-dir-cli]="pkg-dir-cli"
PKG_DESC[pkg-dir-cli]="Find the root directory of a npm package [CUSTOM]"
PKG_METHOD[pkg-dir-cli]="custom"
PKG_CATEGORY[pkg-dir-cli]="dev"

PACKAGES[npm-check-updates]="npm-check-updates"
PKG_DESC[npm-check-updates]="Find newer versions of package dependencies [CUSTOM]"
PKG_METHOD[npm-check-updates]="custom"
PKG_CATEGORY[npm-check-updates]="dev"

PACKAGES[updates]="updates"
PKG_DESC[updates]="Flexible npm dependency update tool [CUSTOM]"
PKG_METHOD[updates]="custom"
PKG_CATEGORY[updates]="dev"

PACKAGES[wipe-modules]="wipe-modules"
PKG_DESC[wipe-modules]="Remove node_modules of inactive projects [CUSTOM]"
PKG_METHOD[wipe-modules]="custom"
PKG_CATEGORY[wipe-modules]="dev"

# Boilerplate Tools
PACKAGES[yo]="yo"
PKG_DESC[yo]="Scaffolding tool for running Yeoman generators [CUSTOM]"
PKG_METHOD[yo]="custom"
PKG_CATEGORY[yo]="dev"

PACKAGES[boilr]="boilr"
PKG_DESC[boilr]="Create projects from boilerplate templates [CUSTOM]"
PKG_METHOD[boilr]="custom"
PKG_CATEGORY[boilr]="dev"

PACKAGES[cookiecutter]="cookiecutter"
PKG_DESC[cookiecutter]="Create projects from templates [APT]"
PKG_METHOD[cookiecutter]="apt"
PKG_CATEGORY[cookiecutter]="dev"

PACKAGES[mevn-cli]="mevn-cli"
PKG_DESC[mevn-cli]="Light speed setup for MEVN (Mongo Express Vue Node) Apps [CUSTOM]"
PKG_METHOD[mevn-cli]="custom"
PKG_CATEGORY[mevn-cli]="dev"

PACKAGES[scaffold-static]="scaffold-static"
PKG_DESC[scaffold-static]="Scaffolding utility for vanilla JS [CUSTOM]"
PKG_METHOD[scaffold-static]="custom"
PKG_CATEGORY[scaffold-static]="dev"

# HTTP Server Tools
PACKAGES[serve]="serve"
PKG_DESC[serve]="Serve static files (https, CORS, GZIP compression, etc) [CUSTOM]"
PKG_METHOD[serve]="custom"
PKG_CATEGORY[serve]="web"

PACKAGES[simplehttp]="simplehttp"
PKG_DESC[simplehttp]="Easily serve a local directory over HTTP [CUSTOM]"
PKG_METHOD[simplehttp]="custom"
PKG_CATEGORY[simplehttp]="web"

PACKAGES[shell2http]="shell2http"
PKG_DESC[shell2http]="Shell script based HTTP server [CUSTOM]"
PKG_METHOD[shell2http]="custom"
PKG_CATEGORY[shell2http]="web"

# HTTP Client Tools
PACKAGES[http-prompt]="http-prompt"
PKG_DESC[http-prompt]="Interactive HTTP client featuring autocomplete and syntax highlighting [CUSTOM]"
PKG_METHOD[http-prompt]="custom"
PKG_CATEGORY[http-prompt]="dev"

PACKAGES[ain]="ain"
PKG_DESC[ain]="HTTP client with a simple format to organize API endpoints [CUSTOM]"
PKG_METHOD[ain]="custom"
PKG_CATEGORY[ain]="dev"

PACKAGES[curlie]="curlie"
PKG_DESC[curlie]="A curl frontend with the ease of use of HTTPie [CUSTOM]"
PKG_METHOD[curlie]="custom"
PKG_CATEGORY[curlie]="dev"

PACKAGES[atac]="atac"
PKG_DESC[atac]="A feature-full TUI API client made in Rust [CUSTOM]"
PKG_METHOD[atac]="custom"
PKG_CATEGORY[atac]="dev"

# Testing Tools
PACKAGES[shellspec]="shellspec"
PKG_DESC[shellspec]="A full-featured BDD unit-testing framework for all POSIX shells [CUSTOM]"
PKG_METHOD[shellspec]="custom"
PKG_CATEGORY[shellspec]="dev"

PACKAGES[gdb-dashboard]="gdb-dashboard"
PKG_DESC[gdb-dashboard]="Modular visual interface for GDB [CUSTOM]"
PKG_METHOD[gdb-dashboard]="custom"
PKG_CATEGORY[gdb-dashboard]="dev"

PACKAGES[loadtest]="loadtest"
PKG_DESC[loadtest]="Run load tests [CUSTOM]"
PKG_METHOD[loadtest]="custom"
PKG_CATEGORY[loadtest]="dev"

PACKAGES[step-ci]="step-ci"
PKG_DESC[step-ci]="API testing and QA framework [CUSTOM]"
PKG_METHOD[step-ci]="custom"
PKG_CATEGORY[step-ci]="dev"

# Productivity Tools
PACKAGES[doing]="doing"
PKG_DESC[doing]="Keep track of what you're doing and track what you've done [CUSTOM]"
PKG_METHOD[doing]="custom"
PKG_CATEGORY[doing]="utilities"

PACKAGES[ffscreencast]="ffscreencast"
PKG_DESC[ffscreencast]="A ffmpeg screencast with video overlay and multi monitor support [CUSTOM]"
PKG_METHOD[ffscreencast]="custom"
PKG_CATEGORY[ffscreencast]="video"

PACKAGES[meetup-cli]="meetup-cli"
PKG_DESC[meetup-cli]="Meetup.com client [CUSTOM]"
PKG_METHOD[meetup-cli]="custom"
PKG_CATEGORY[meetup-cli]="utilities"

PACKAGES[neomutt]="neomutt"
PKG_DESC[neomutt]="Email client [APT]"
PKG_METHOD[neomutt]="apt"
PKG_CATEGORY[neomutt]="communication"

PACKAGES[terjira]="terjira"
PKG_DESC[terjira]="Jira client [CUSTOM]"
PKG_METHOD[terjira]="custom"
PKG_CATEGORY[terjira]="dev"

PACKAGES[ipt]="ipt"
PKG_DESC[ipt]="Pivotal Tracker client [CUSTOM]"
PKG_METHOD[ipt]="custom"
PKG_CATEGORY[ipt]="dev"

PACKAGES[uber-cli]="uber-cli"
PKG_DESC[uber-cli]="Uber client [CUSTOM]"
PKG_METHOD[uber-cli]="custom"
PKG_CATEGORY[uber-cli]="utilities"

PACKAGES[buku]="buku"
PKG_DESC[buku]="Browser-independent bookmark manager [APT]"
PKG_METHOD[buku]="apt"
PKG_CATEGORY[buku]="utilities"

PACKAGES[fjira]="fjira"
PKG_DESC[fjira]="Fuzzy finder and TUI application for Jira [CUSTOM]"
PKG_METHOD[fjira]="custom"
PKG_CATEGORY[fjira]="dev"

PACKAGES[overtime]="overtime"
PKG_DESC[overtime]="Time-overlap tables for remote teams [CUSTOM]"
PKG_METHOD[overtime]="custom"
PKG_CATEGORY[overtime]="utilities"

# Time Tracking Tools
PACKAGES[timetrap]="timetrap"
PKG_DESC[timetrap]="Simple timetracker [CUSTOM]"
PKG_METHOD[timetrap]="custom"
PKG_CATEGORY[timetrap]="utilities"

PACKAGES[moro]="moro"
PKG_DESC[moro]="Simple tool for tracking work hours [CUSTOM]"
PKG_METHOD[moro]="custom"
PKG_CATEGORY[moro]="utilities"

PACKAGES[timewarrior]="timewarrior"
PKG_DESC[timewarrior]="Utility with simple stopwatch, calendar-based backfill and flexible reporting [APT]"
PKG_METHOD[timewarrior]="apt"
PKG_CATEGORY[timewarrior]="utilities"

PACKAGES[watson]="watson"
PKG_DESC[watson]="Generate reports for clients and manage your time [CUSTOM]"
PKG_METHOD[watson]="custom"
PKG_CATEGORY[watson]="utilities"

PACKAGES[utt]="utt"
PKG_DESC[utt]="Simple time tracking tool [CUSTOM]"
PKG_METHOD[utt]="custom"
PKG_CATEGORY[utt]="utilities"

PACKAGES[bartib]="bartib"
PKG_DESC[bartib]="Easy to use time tracking tool [CUSTOM]"
PKG_METHOD[bartib]="custom"
PKG_CATEGORY[bartib]="utilities"

PACKAGES[arttime]="arttime"
PKG_DESC[arttime]="Featureful timer with native desktop notifications and curated ASCII art [CUSTOM]"
PKG_METHOD[arttime]="custom"
PKG_CATEGORY[arttime]="utilities"

# Note Taking and Lists
PACKAGES[idea]="idea"
PKG_DESC[idea]="A lightweight tool for keeping ideas in a safe place quick and easy [CUSTOM]"
PKG_METHOD[idea]="custom"
PKG_CATEGORY[idea]="utilities"

PACKAGES[geeknote]="geeknote"
PKG_DESC[geeknote]="Evernote client [CUSTOM]"
PKG_METHOD[geeknote]="custom"
PKG_CATEGORY[geeknote]="utilities"

PACKAGES[taskwarrior]="taskwarrior"
PKG_DESC[taskwarrior]="Manage your TODO list [APT]"
PKG_METHOD[taskwarrior]="apt"
PKG_CATEGORY[taskwarrior]="utilities"

PACKAGES[terminal-velocity]="terminal-velocity"
PKG_DESC[terminal-velocity]="A fast note-taking app [CUSTOM]"
PKG_METHOD[terminal-velocity]="custom"
PKG_CATEGORY[terminal-velocity]="utilities"

PACKAGES[eureka]="eureka"
PKG_DESC[eureka]="Input and store your ideas [CUSTOM]"
PKG_METHOD[eureka]="custom"
PKG_CATEGORY[eureka]="utilities"

PACKAGES[sncli]="sncli"
PKG_DESC[sncli]="Simplenote client [CUSTOM]"
PKG_METHOD[sncli]="custom"
PKG_CATEGORY[sncli]="utilities"

PACKAGES[td-cli]="td-cli"
PKG_DESC[td-cli]="A TODO manager to organize and manage your TODO's across multiple projects [CUSTOM]"
PKG_METHOD[td-cli]="custom"
PKG_CATEGORY[td-cli]="utilities"

PACKAGES[taskbook]="taskbook"
PKG_DESC[taskbook]="Tasks, boards & notes for the command-line habitat [CUSTOM]"
PKG_METHOD[taskbook]="custom"
PKG_CATEGORY[taskbook]="utilities"

PACKAGES[dnote]="dnote"
PKG_DESC[dnote]="A interactive, multi-device notebook [CUSTOM]"
PKG_METHOD[dnote]="custom"
PKG_CATEGORY[dnote]="utilities"

PACKAGES[nb]="nb"
PKG_DESC[nb]="A note‑taking, bookmarking, archiving, and knowledge base application [CUSTOM]"
PKG_METHOD[nb]="custom"
PKG_CATEGORY[nb]="utilities"

PACKAGES[obs-cli]="obs-cli"
PKG_DESC[obs-cli]="Interact with your Obsidian vault [CUSTOM]"
PKG_METHOD[obs-cli]="custom"
PKG_CATEGORY[obs-cli]="utilities"

PACKAGES[journalot]="journalot"
PKG_DESC[journalot]="Journaling tool with git sync [CUSTOM]"
PKG_METHOD[journalot]="custom"
PKG_CATEGORY[journalot]="utilities"

# Finance Tools
PACKAGES[ledger]="ledger"
PKG_DESC[ledger]="Powerful, double-entry accounting system [APT]"
PKG_METHOD[ledger]="apt"
PKG_CATEGORY[ledger]="utilities"

PACKAGES[hledger]="hledger"
PKG_DESC[hledger]="Robust, fast, intuitive plain text accounting tool with CLI, TUI and web interfaces [APT]"
PKG_METHOD[hledger]="apt"
PKG_CATEGORY[hledger]="utilities"

PACKAGES[moeda]="moeda"
PKG_DESC[moeda]="Foreign exchange rates and currency conversion [CUSTOM]"
PKG_METHOD[moeda]="custom"
PKG_CATEGORY[moeda]="utilities"

PACKAGES[cash-cli]="cash-cli"
PKG_DESC[cash-cli]="Convert Currency Rates [CUSTOM]"
PKG_METHOD[cash-cli]="custom"
PKG_CATEGORY[cash-cli]="utilities"

PACKAGES[cointop]="cointop"
PKG_DESC[cointop]="Track cryptocurrencies [CUSTOM]"
PKG_METHOD[cointop]="custom"
PKG_CATEGORY[cointop]="utilities"

PACKAGES[ticker]="ticker"
PKG_DESC[ticker]="Stock ticker [CUSTOM]"
PKG_METHOD[ticker]="custom"
PKG_CATEGORY[ticker]="utilities"

# Presentation Tools
PACKAGES[wopr]="wopr"
PKG_DESC[wopr]="A simple markup language for creating rich terminal reports, presentations and infographics [CUSTOM]"
PKG_METHOD[wopr]="custom"
PKG_CATEGORY[wopr]="utilities"

PACKAGES[decktape]="decktape"
PKG_DESC[decktape]="PDF exporter for HTML presentations [CUSTOM]"
PKG_METHOD[decktape]="custom"
PKG_CATEGORY[decktape]="utilities"

PACKAGES[mdp]="mdp"
PKG_DESC[mdp]="A markdown presentation tool [APT]"
PKG_METHOD[mdp]="apt"
PKG_CATEGORY[mdp]="utilities"

PACKAGES[sent]="sent"
PKG_DESC[sent]="Simple plaintext presentation tool [CUSTOM]"
PKG_METHOD[sent]="custom"
PKG_CATEGORY[sent]="utilities"

PACKAGES[slides]="slides"
PKG_DESC[slides]="A markdown presentation tool [CUSTOM]"
PKG_METHOD[slides]="custom"
PKG_CATEGORY[slides]="utilities"

PACKAGES[marp]="marp"
PKG_DESC[marp]="Export Markdown to HTML/PDF/Powerpoint presentations [CUSTOM]"
PKG_METHOD[marp]="custom"
PKG_CATEGORY[marp]="utilities"

# Calendar Tools
PACKAGES[calcurse]="calcurse"
PKG_DESC[calcurse]="Calendar and scheduling [APT]"
PKG_METHOD[calcurse]="apt"
PKG_CATEGORY[calcurse]="utilities"

PACKAGES[gcalcli]="gcalcli"
PKG_DESC[gcalcli]="Google calendar client [CUSTOM]"
PKG_METHOD[gcalcli]="custom"
PKG_CATEGORY[gcalcli]="utilities"

PACKAGES[khal]="khal"
PKG_DESC[khal]="CalDAV ready CLI and TUI calendar [APT]"
PKG_METHOD[khal]="apt"
PKG_CATEGORY[khal]="utilities"

PACKAGES[vdirsyncer]="vdirsyncer"
PKG_DESC[vdirsyncer]="CalDAV sync [APT]"
PKG_METHOD[vdirsyncer]="apt"
PKG_CATEGORY[vdirsyncer]="utilities"

PACKAGES[remind]="remind"
PKG_DESC[remind]="A sophisticated calendar and alarm program [APT]"
PKG_METHOD[remind]="apt"
PKG_CATEGORY[remind]="utilities"

PACKAGES[birthday]="birthday"
PKG_DESC[birthday]="Know when a friend's birthday is coming [CUSTOM]"
PKG_METHOD[birthday]="custom"
PKG_CATEGORY[birthday]="utilities"

# Additional Utilities
PACKAGES[aria2]="aria2"
PKG_DESC[aria2]="HTTP, FTP, SFTP, BitTorrent and Metalink download utility [APT]"
PKG_METHOD[aria2]="apt"
PKG_CATEGORY[aria2]="utilities"

PACKAGES[bitly-client]="bitly-client"
PKG_DESC[bitly-client]="Bitly client [CUSTOM]"
PKG_METHOD[bitly-client]="custom"
PKG_CATEGORY[bitly-client]="utilities"

PACKAGES[deadlink]="deadlink"
PKG_DESC[deadlink]="Find dead links in files [CUSTOM]"
PKG_METHOD[deadlink]="custom"
PKG_CATEGORY[deadlink]="utilities"

PACKAGES[crawley]="crawley"
PKG_DESC[crawley]="Unix-way web crawler [CUSTOM]"
PKG_METHOD[crawley]="custom"
PKG_CATEGORY[crawley]="utilities"

PACKAGES[kill-tabs]="kill-tabs"
PKG_DESC[kill-tabs]="Kill all Chrome tabs [CUSTOM]"
PKG_METHOD[kill-tabs]="custom"
PKG_CATEGORY[kill-tabs]="utilities"

PACKAGES[alex]="alex"
PKG_DESC[alex]="Catch insensitive, inconsiderate writing [CUSTOM]"
PKG_METHOD[alex]="custom"
PKG_CATEGORY[alex]="utilities"

PACKAGES[clevercli]="clevercli"
PKG_DESC[clevercli]="Collection of ChatGPT powered utilities [CUSTOM]"
PKG_METHOD[clevercli]="custom"
PKG_CATEGORY[clevercli]="ai"

# Terminal Sharing Utilities
PACKAGES[gotty]="gotty"
PKG_DESC[gotty]="Share your terminal as a web application [CUSTOM]"
PKG_METHOD[gotty]="custom"
PKG_CATEGORY[gotty]="utilities"

PACKAGES[tmate]="tmate"
PKG_DESC[tmate]="Instant terminal (tmux) sharing [APT]"
PKG_METHOD[tmate]="apt"
PKG_CATEGORY[tmate]="utilities"

PACKAGES[warp-sharing]="warp-sharing"
PKG_DESC[warp-sharing]="Secure and simple terminal sharing [CUSTOM]"
PKG_METHOD[warp-sharing]="custom"
PKG_CATEGORY[warp-sharing]="utilities"

# SSH Tools
PACKAGES[mosh]="mosh"
PKG_DESC[mosh]="Remote SSH client that allows roaming with intermittent connectivity [APT]"
PKG_METHOD[mosh]="apt"
PKG_CATEGORY[mosh]="network-monitoring"

PACKAGES[xxh]="xxh"
PKG_DESC[xxh]="Bring your favorite shell wherever you go through SSH [CUSTOM]"
PKG_METHOD[xxh]="custom"
PKG_CATEGORY[xxh]="network-monitoring"

# Network Utilities
PACKAGES[get-port-cli]="get-port-cli"
PKG_DESC[get-port-cli]="Get an available port [CUSTOM]"
PKG_METHOD[get-port-cli]="custom"
PKG_CATEGORY[get-port-cli]="network-monitoring"

PACKAGES[is-reachable-cli]="is-reachable-cli"
PKG_DESC[is-reachable-cli]="Check if hostnames are reachable or not [CUSTOM]"
PKG_METHOD[is-reachable-cli]="custom"
PKG_CATEGORY[is-reachable-cli]="network-monitoring"

PACKAGES[acmetool]="acmetool"
PKG_DESC[acmetool]="Automatic certificate acquisition for ACME (Let's Encrypt) [CUSTOM]"
PKG_METHOD[acmetool]="custom"
PKG_CATEGORY[acmetool]="security"

PACKAGES[certificate-ripper]="certificate-ripper"
PKG_DESC[certificate-ripper]="Extract server certificates [CUSTOM]"
PKG_METHOD[certificate-ripper]="custom"
PKG_CATEGORY[certificate-ripper]="security"

PACKAGES[neoss]="neoss"
PKG_DESC[neoss]="User-friendly and detailed socket statistics [CUSTOM]"
PKG_METHOD[neoss]="custom"
PKG_CATEGORY[neoss]="network-monitoring"

PACKAGES[gg]="gg"
PKG_DESC[gg]="One-click proxy without installing v2ray or anything else [CUSTOM]"
PKG_METHOD[gg]="custom"
PKG_CATEGORY[gg]="network-monitoring"

PACKAGES[rustnet]="rustnet"
PKG_DESC[rustnet]="Network monitoring with process identification and deep packet inspection [CUSTOM]"
PKG_METHOD[rustnet]="custom"
PKG_CATEGORY[rustnet]="network-monitoring"

PACKAGES[sshuttle]="sshuttle"
PKG_DESC[sshuttle]="Transparent proxy server that works as a poor man's VPN [APT]"
PKG_METHOD[sshuttle]="apt"
PKG_CATEGORY[sshuttle]="network-monitoring"

# Theming and Customization
PACKAGES[splash-cli]="splash-cli"
PKG_DESC[splash-cli]="Beautiful wallpapers from Unsplash [CUSTOM]"
PKG_METHOD[splash-cli]="custom"
PKG_CATEGORY[splash-cli]="shell"

PACKAGES[wallpaper-cli]="wallpaper-cli"
PKG_DESC[wallpaper-cli]="Get or set the desktop wallpaper [CUSTOM]"
PKG_METHOD[wallpaper-cli]="custom"
PKG_CATEGORY[wallpaper-cli]="shell"

PACKAGES[themer]="themer"
PKG_DESC[themer]="Generate personalized themes for your editor, terminal, wallpaper, Slack, and more [CUSTOM]"
PKG_METHOD[themer]="custom"
PKG_CATEGORY[themer]="shell"

PACKAGES[jackpaper]="jackpaper"
PKG_DESC[jackpaper]="Set images from Unsplash as wallpaper [CUSTOM]"
PKG_METHOD[jackpaper]="custom"
PKG_CATEGORY[jackpaper]="shell"

PACKAGES[quickwall]="quickwall"
PKG_DESC[quickwall]="Directly set wallpapers from Unsplash [CUSTOM]"
PKG_METHOD[quickwall]="custom"
PKG_CATEGORY[quickwall]="shell"

PACKAGES[oh-my-posh]="oh-my-posh"
PKG_DESC[oh-my-posh]="Prompt theme engine [CUSTOM]"
PKG_METHOD[oh-my-posh]="custom"
PKG_CATEGORY[oh-my-posh]="shell"

# Shell Utilities
PACKAGES[has]="has"
PKG_DESC[has]="Checks for the presence of various commands and their versions on the path [CUSTOM]"
PKG_METHOD[has]="custom"
PKG_CATEGORY[has]="shell"

PACKAGES[ultimate-plumber]="ultimate-plumber"
PKG_DESC[ultimate-plumber]="Write Linux pipes with live previews [CUSTOM]"
PKG_METHOD[ultimate-plumber]="custom"
PKG_CATEGORY[ultimate-plumber]="shell"

PACKAGES[fkill-cli]="fkill-cli"
PKG_DESC[fkill-cli]="Simple cross-platform process killer [CUSTOM]"
PKG_METHOD[fkill-cli]="custom"
PKG_CATEGORY[fkill-cli]="utilities"

PACKAGES[task-spooler]="task-spooler"
PKG_DESC[task-spooler]="Queue jobs for linear execution [APT]"
PKG_METHOD[task-spooler]="apt"
PKG_CATEGORY[task-spooler]="utilities"

PACKAGES[undollar]="undollar"
PKG_DESC[undollar]="Strip the '$' preceding copy-pasted terminal commands [CUSTOM]"
PKG_METHOD[undollar]="custom"
PKG_CATEGORY[undollar]="shell"

PACKAGES[pipe-exec]="pipe-exec"
PKG_DESC[pipe-exec]="Run exes from stdin, pipes and ttys without creating a temp [CUSTOM]"
PKG_METHOD[pipe-exec]="custom"
PKG_CATEGORY[pipe-exec]="shell"

# System Interaction Utilities
PACKAGES[fastfetch]="fastfetch"
PKG_DESC[fastfetch]="System information tool [APT]"
PKG_METHOD[fastfetch]="apt"
PKG_CATEGORY[fastfetch]="utilities"

PACKAGES[battery-level-cli]="battery-level-cli"
PKG_DESC[battery-level-cli]="Get current battery level [CUSTOM]"
PKG_METHOD[battery-level-cli]="custom"
PKG_CATEGORY[battery-level-cli]="utilities"

PACKAGES[brightness-cli]="brightness-cli"
PKG_DESC[brightness-cli]="Change screen brightness [CUSTOM]"
PKG_METHOD[brightness-cli]="custom"
PKG_CATEGORY[brightness-cli]="utilities"

PACKAGES[clipboard]="clipboard"
PKG_DESC[clipboard]="Cut, copy, and paste anything, anywhere [CUSTOM]"
PKG_METHOD[clipboard]="custom"
PKG_CATEGORY[clipboard]="utilities"

PACKAGES[yank]="yank"
PKG_DESC[yank]="Yank terminal output to clipboard [CUSTOM]"
PKG_METHOD[yank]="custom"
PKG_CATEGORY[yank]="utilities"

PACKAGES[screensaver]="screensaver"
PKG_DESC[screensaver]="Start the screensaver [CUSTOM]"
PKG_METHOD[screensaver]="custom"
PKG_CATEGORY[screensaver]="utilities"

PACKAGES[google-font-installer]="google-font-installer"
PKG_DESC[google-font-installer]="Download and install Google Web Fonts [CUSTOM]"
PKG_METHOD[google-font-installer]="custom"
PKG_CATEGORY[google-font-installer]="utilities"

PACKAGES[tiptop]="tiptop"
PKG_DESC[tiptop]="System monitor [CUSTOM]"
PKG_METHOD[tiptop]="custom"
PKG_CATEGORY[tiptop]="system-monitoring"

PACKAGES[gzip-size-cli]="gzip-size-cli"
PKG_DESC[gzip-size-cli]="Get the gzipped size of a file [CUSTOM]"
PKG_METHOD[gzip-size-cli]="custom"
PKG_CATEGORY[gzip-size-cli]="utilities"

# Markdown Tools
PACKAGES[doctoc]="doctoc"
PKG_DESC[doctoc]="Generates table of contents for markdown files [CUSTOM]"
PKG_METHOD[doctoc]="custom"
PKG_CATEGORY[doctoc]="dev"

PACKAGES[grip]="grip"
PKG_DESC[grip]="Preview markdown files as GitHub would render them [CUSTOM]"
PKG_METHOD[grip]="custom"
PKG_CATEGORY[grip]="dev"

PACKAGES[mdv]="mdv"
PKG_DESC[mdv]="Styled terminal markdown viewer [CUSTOM]"
PKG_METHOD[mdv]="custom"
PKG_CATEGORY[mdv]="utilities"

PACKAGES[gtree]="gtree"
PKG_DESC[gtree]="Use markdown to generate directory trees [CUSTOM]"
PKG_METHOD[gtree]="custom"
PKG_CATEGORY[gtree]="utilities"

# Security Tools
PACKAGES[pass]="pass"
PKG_DESC[pass]="Password manager [APT]"
PKG_METHOD[pass]="apt"
PKG_CATEGORY[pass]="security"

PACKAGES[gopass]="gopass"
PKG_DESC[gopass]="Fully-featured password manager [CUSTOM]"
PKG_METHOD[gopass]="custom"
PKG_CATEGORY[gopass]="security"

PACKAGES[xiringuito]="xiringuito"
PKG_DESC[xiringuito]="SSH-based VPN [CUSTOM]"
PKG_METHOD[xiringuito]="custom"
PKG_CATEGORY[xiringuito]="security"

PACKAGES[hasha-cli]="hasha-cli"
PKG_DESC[hasha-cli]="Get the hash of text or stdin [CUSTOM]"
PKG_METHOD[hasha-cli]="custom"
PKG_CATEGORY[hasha-cli]="security"

PACKAGES[ots]="ots"
PKG_DESC[ots]="Share secrets with others via a one-time URL [CUSTOM]"
PKG_METHOD[ots]="custom"
PKG_CATEGORY[ots]="security"

# Math Tools
PACKAGES[mdlt]="mdlt"
PKG_DESC[mdlt]="Do quick math right from the command line [CUSTOM]"
PKG_METHOD[mdlt]="custom"
PKG_CATEGORY[mdlt]="utilities"

PACKAGES[qalculate]="qalculate"
PKG_DESC[qalculate]="Calculate non-trivial math expressions [APT]"
PKG_METHOD[qalculate]="apt"
PKG_CATEGORY[qalculate]="utilities"

# Academia Tools
PACKAGES[papis]="papis"
PKG_DESC[papis]="Extensible document and bibliography manager [CUSTOM]"
PKG_METHOD[papis]="custom"
PKG_CATEGORY[papis]="office"

PACKAGES[pubs]="pubs"
PKG_DESC[pubs]="Scientific bibliography manager [CUSTOM]"
PKG_METHOD[pubs]="custom"
PKG_CATEGORY[pubs]="office"

# Weather Tools
PACKAGES[wttr-in]="wttr-in"
PKG_DESC[wttr-in]="Weather information from wttr.in [CUSTOM]"
PKG_METHOD[wttr-in]="custom"
PKG_CATEGORY[wttr-in]="utilities"

PACKAGES[wego]="wego"
PKG_DESC[wego]="Weather app for the terminal [CUSTOM]"
PKG_METHOD[wego]="custom"
PKG_CATEGORY[wego]="utilities"

PACKAGES[weather-cli]="weather-cli"
PKG_DESC[weather-cli]="Get weather information from command line [CUSTOM]"
PKG_METHOD[weather-cli]="custom"
PKG_CATEGORY[weather-cli]="utilities"

# Browser Replacement Tools
PACKAGES[s]="s"
PKG_DESC[s]="Open a web search in your terminal [CUSTOM]"
PKG_METHOD[s]="custom"
PKG_CATEGORY[s]="utilities"

PACKAGES[hget]="hget"
PKG_DESC[hget]="Render websites in plain text from your terminal [CUSTOM]"
PKG_METHOD[hget]="custom"
PKG_CATEGORY[hget]="utilities"

PACKAGES[mapscii]="mapscii"
PKG_DESC[mapscii]="Terminal Map Viewer [CUSTOM]"
PKG_METHOD[mapscii]="custom"
PKG_CATEGORY[mapscii]="utilities"

PACKAGES[nasa-cli]="nasa-cli"
PKG_DESC[nasa-cli]="Download NASA Picture of the Day [CUSTOM]"
PKG_METHOD[nasa-cli]="custom"
PKG_CATEGORY[nasa-cli]="utilities"

PACKAGES[getnews-tech]="getnews-tech"
PKG_DESC[getnews-tech]="Fetch news headlines from various news outlets [CUSTOM]"
PKG_METHOD[getnews-tech]="custom"
PKG_CATEGORY[getnews-tech]="utilities"

PACKAGES[trino]="trino"
PKG_DESC[trino]="Translation of words and phrases [CUSTOM]"
PKG_METHOD[trino]="custom"
PKG_CATEGORY[trino]="utilities"

PACKAGES[translate-shell]="translate-shell"
PKG_DESC[translate-shell]="Google Translate interface [APT]"
PKG_METHOD[translate-shell]="apt"
PKG_CATEGORY[translate-shell]="utilities"

# Internet Speedtest Tools
PACKAGES[speedtest-net]="speedtest-net"
PKG_DESC[speedtest-net]="Test internet connection speed using speedtest.net [CUSTOM]"
PKG_METHOD[speedtest-net]="custom"
PKG_CATEGORY[speedtest-net]="network-monitoring"

PACKAGES[speed-test]="speed-test"
PKG_DESC[speed-test]="speedtest-net wrapper with different UI [CUSTOM]"
PKG_METHOD[speed-test]="custom"
PKG_CATEGORY[speed-test]="network-monitoring"

PACKAGES[speedtest-cli]="speedtest-cli"
PKG_DESC[speedtest-cli]="Test internet bandwidth using speedtest.net [APT]"
PKG_METHOD[speedtest-cli]="apt"
PKG_CATEGORY[speedtest-cli]="network-monitoring"

# Command Line Learning Tools
PACKAGES[cmdchallenge]="cmdchallenge"
PKG_DESC[cmdchallenge]="Presents small shell challenge with user submitted solutions [CUSTOM]"
PKG_METHOD[cmdchallenge]="custom"
PKG_CATEGORY[cmdchallenge]="dev"

PACKAGES[explainshell]="explainshell"
PKG_DESC[explainshell]="Type a snippet to see the help text for each argument [CUSTOM]"
PKG_METHOD[explainshell]="custom"
PKG_CATEGORY[explainshell]="dev"

PACKAGES[howdoi]="howdoi"
PKG_DESC[howdoi]="Instant coding answers [CUSTOM]"
PKG_METHOD[howdoi]="custom"
PKG_CATEGORY[howdoi]="dev"

PACKAGES[how2]="how2"
PKG_DESC[how2]="Node.js implementation of howdoi [CUSTOM]"
PKG_METHOD[how2]="custom"
PKG_CATEGORY[how2]="dev"

PACKAGES[wat]="wat"
PKG_DESC[wat]="Instant, central, community-built docs [CUSTOM]"
PKG_METHOD[wat]="custom"
PKG_CATEGORY[wat]="dev"

PACKAGES[teachcode]="teachcode"
PKG_DESC[teachcode]="Guide for the earliest lessons of coding [CUSTOM]"
PKG_METHOD[teachcode]="custom"
PKG_CATEGORY[teachcode]="dev"

PACKAGES[navi]="navi"
PKG_DESC[navi]="Interactive cheatsheet tool [CUSTOM]"
PKG_METHOD[navi]="custom"
PKG_CATEGORY[navi]="dev"

PACKAGES[yai]="yai"
PKG_DESC[yai]="AI powered terminal assistant [CUSTOM]"
PKG_METHOD[yai]="custom"
PKG_CATEGORY[yai]="ai"

# Data Manipulation Tools
PACKAGES[visidata]="visidata"
PKG_DESC[visidata]="Spreadsheet multitool for data discovery and arrangement [CUSTOM]"
PKG_METHOD[visidata]="custom"
PKG_CATEGORY[visidata]="utilities"

PACKAGES[jp]="jp"
PKG_DESC[jp]="JSON parser [CUSTOM]"
PKG_METHOD[jp]="custom"
PKG_CATEGORY[jp]="dev"

PACKAGES[fx]="fx"
PKG_DESC[fx]="Command-line JSON viewer [CUSTOM]"
PKG_METHOD[fx]="custom"
PKG_CATEGORY[fx]="dev"

PACKAGES[vj]="vj"
PKG_DESC[vj]="Makes JSON human readable [CUSTOM]"
PKG_METHOD[vj]="custom"
PKG_CATEGORY[vj]="dev"

PACKAGES[underscore-cli]="underscore-cli"
PKG_DESC[underscore-cli]="Utility-belt for hacking JSON and Javascript [CUSTOM]"
PKG_METHOD[underscore-cli]="custom"
PKG_CATEGORY[underscore-cli]="dev"

PACKAGES[strip-json-comments-cli]="strip-json-comments-cli"
PKG_DESC[strip-json-comments-cli]="Strip comments from JSON [CUSTOM]"
PKG_METHOD[strip-json-comments-cli]="custom"
PKG_CATEGORY[strip-json-comments-cli]="dev"

PACKAGES[groq]="groq"
PKG_DESC[groq]="JSON processor with queries and projections [CUSTOM]"
PKG_METHOD[groq]="custom"
PKG_CATEGORY[groq]="dev"

PACKAGES[gron]="gron"
PKG_DESC[gron]="Make JSON greppable [CUSTOM]"
PKG_METHOD[gron]="custom"
PKG_CATEGORY[gron]="dev"

PACKAGES[config-file-validator]="config-file-validator"
PKG_DESC[config-file-validator]="Validate configuration files [CUSTOM]"
PKG_METHOD[config-file-validator]="custom"
PKG_CATEGORY[config-file-validator]="dev"

PACKAGES[dyff]="dyff"
PKG_DESC[dyff]="YAML diff tool [CUSTOM]"
PKG_METHOD[dyff]="custom"
PKG_CATEGORY[dyff]="dev"

PACKAGES[parse-columns-cli]="parse-columns-cli"
PKG_DESC[parse-columns-cli]="Parse text columns to JSON [CUSTOM]"
PKG_METHOD[parse-columns-cli]="custom"
PKG_CATEGORY[parse-columns-cli]="dev"

PACKAGES[q]="q"
PKG_DESC[q]="Execution of SQL-like queries on CSV/TSV/tabular text file [CUSTOM]"
PKG_METHOD[q]="custom"
PKG_CATEGORY[q]="dev"

PACKAGES[stegcloak]="stegcloak"
PKG_DESC[stegcloak]="Hide secrets with invisible characters in plain text [CUSTOM]"
PKG_METHOD[stegcloak]="custom"
PKG_CATEGORY[stegcloak]="security"

# File Managers
PACKAGES[vifm]="vifm"
PKG_DESC[vifm]="VI influenced file manager [APT]"
PKG_METHOD[vifm]="apt"
PKG_CATEGORY[vifm]="utilities"

PACKAGES[nnn]="nnn"
PKG_DESC[nnn]="File browser and disk usage analyzer [APT]"
PKG_METHOD[nnn]="apt"
PKG_CATEGORY[nnn]="utilities"

PACKAGES[lf]="lf"
PKG_DESC[lf]="Fast, extensively customizable file manager [CUSTOM]"
PKG_METHOD[lf]="custom"
PKG_CATEGORY[lf]="utilities"

PACKAGES[clifm]="clifm"
PKG_DESC[clifm]="The command line file manager [CUSTOM]"
PKG_METHOD[clifm]="custom"
PKG_CATEGORY[clifm]="utilities"

PACKAGES[far2l]="far2l"
PKG_DESC[far2l]="Orthodox file manager [CUSTOM]"
PKG_METHOD[far2l]="custom"
PKG_CATEGORY[far2l]="utilities"

PACKAGES[yazi]="yazi"
PKG_DESC[yazi]="Blazing fast file manager [CUSTOM]"
PKG_METHOD[yazi]="custom"
PKG_CATEGORY[yazi]="utilities"

PACKAGES[xplr]="xplr"
PKG_DESC[xplr]="A hackable, minimal, fast TUI file explorer [CUSTOM]"
PKG_METHOD[xplr]="custom"
PKG_CATEGORY[xplr]="utilities"

# File Operations
PACKAGES[trash-cli]="trash-cli"
PKG_DESC[trash-cli]="Move files and directories to the trash [APT]"
PKG_METHOD[trash-cli]="apt"
PKG_CATEGORY[trash-cli]="utilities"

PACKAGES[empty-trash-cli]="empty-trash-cli"
PKG_DESC[empty-trash-cli]="Empty the trash [CUSTOM]"
PKG_METHOD[empty-trash-cli]="custom"
PKG_CATEGORY[empty-trash-cli]="utilities"

PACKAGES[del-cli]="del-cli"
PKG_DESC[del-cli]="Delete files and folders [CUSTOM]"
PKG_METHOD[del-cli]="custom"
PKG_CATEGORY[del-cli]="utilities"

PACKAGES[cpy-cli]="cpy-cli"
PKG_DESC[cpy-cli]="Copies files [CUSTOM]"
PKG_METHOD[cpy-cli]="custom"
PKG_CATEGORY[cpy-cli]="utilities"

PACKAGES[rename-cli]="rename-cli"
PKG_DESC[rename-cli]="Rename files quickly [CUSTOM]"
PKG_METHOD[rename-cli]="custom"
PKG_CATEGORY[rename-cli]="utilities"

PACKAGES[renameutils]="renameutils"
PKG_DESC[renameutils]="Mass renaming in your editor [APT]"
PKG_METHOD[renameutils]="apt"
PKG_CATEGORY[renameutils]="utilities"

PACKAGES[diskonaut]="diskonaut"
PKG_DESC[diskonaut]="Disk space navigator [CUSTOM]"
PKG_METHOD[diskonaut]="custom"
PKG_CATEGORY[diskonaut]="utilities"

PACKAGES[dua-cli]="dua-cli"
PKG_DESC[dua-cli]="Disk usage analyzer [CUSTOM]"
PKG_METHOD[dua-cli]="custom"
PKG_CATEGORY[dua-cli]="utilities"

PACKAGES[dutree]="dutree"
PKG_DESC[dutree]="A tool to analyze file system usage written in Rust [CUSTOM]"
PKG_METHOD[dutree]="custom"
PKG_CATEGORY[dutree]="utilities"

PACKAGES[chokidar-cli]="chokidar-cli"
PKG_DESC[chokidar-cli]="CLI to watch file system changes [CUSTOM]"
PKG_METHOD[chokidar-cli]="custom"
PKG_CATEGORY[chokidar-cli]="utilities"

PACKAGES[file-type-cli]="file-type-cli"
PKG_DESC[file-type-cli]="Detect the file type of a file or stdin [CUSTOM]"
PKG_METHOD[file-type-cli]="custom"
PKG_CATEGORY[file-type-cli]="utilities"

PACKAGES[unix-permissions]="unix-permissions"
PKG_DESC[unix-permissions]="Swiss Army knife for Unix permissions [CUSTOM]"
PKG_METHOD[unix-permissions]="custom"
PKG_CATEGORY[unix-permissions]="utilities"

PACKAGES[transmission-cli]="transmission-cli"
PKG_DESC[transmission-cli]="Torrent client for your command line [APT]"
PKG_METHOD[transmission-cli]="apt"
PKG_CATEGORY[transmission-cli]="utilities"

PACKAGES[webtorrent-cli]="webtorrent-cli"
PKG_DESC[webtorrent-cli]="Streaming torrent client [CUSTOM]"
PKG_METHOD[webtorrent-cli]="custom"
PKG_CATEGORY[webtorrent-cli]="utilities"

PACKAGES[entr]="entr"
PKG_DESC[entr]="Run an arbitrary command when files change [APT]"
PKG_METHOD[entr]="apt"
PKG_CATEGORY[entr]="utilities"

PACKAGES[organize-cli]="organize-cli"
PKG_DESC[organize-cli]="Organize your files automatically [CUSTOM]"
PKG_METHOD[organize-cli]="custom"
PKG_CATEGORY[organize-cli]="utilities"

PACKAGES[organize-rt]="organize-rt"
PKG_DESC[organize-rt]="organize-cli in Rust with more customization [CUSTOM]"
PKG_METHOD[organize-rt]="custom"
PKG_CATEGORY[organize-rt]="utilities"

PACKAGES[recoverpy]="recoverpy"
PKG_DESC[recoverpy]="Recover overwritten or deleted files [CUSTOM]"
PKG_METHOD[recoverpy]="custom"
PKG_CATEGORY[recoverpy]="utilities"

PACKAGES[f2]="f2"
PKG_DESC[f2]="A cross-platform tool for fast, safe, and flexible batch renaming [CUSTOM]"
PKG_METHOD[f2]="custom"
PKG_CATEGORY[f2]="utilities"

PACKAGES[scc]="scc"
PKG_DESC[scc]="Count lines of code, blank lines, comment lines, and physical lines [CUSTOM]"
PKG_METHOD[scc]="custom"
PKG_CATEGORY[scc]="dev"

# File Sync/Sharing
PACKAGES[ffsend]="ffsend"
PKG_DESC[ffsend]="Quick file share [CUSTOM]"
PKG_METHOD[ffsend]="custom"
PKG_CATEGORY[ffsend]="utilities"

PACKAGES[share-cli]="share-cli"
PKG_DESC[share-cli]="Share files with your local network [CUSTOM]"
PKG_METHOD[share-cli]="custom"
PKG_CATEGORY[share-cli]="utilities"

PACKAGES[google-drive-upload]="google-drive-upload"
PKG_DESC[google-drive-upload]="Upload/sync with Google Drive [CUSTOM]"
PKG_METHOD[google-drive-upload]="custom"
PKG_CATEGORY[google-drive-upload]="utilities"

PACKAGES[gdrive-downloader]="gdrive-downloader"
PKG_DESC[gdrive-downloader]="Download files/folders from Google Drive [CUSTOM]"
PKG_METHOD[gdrive-downloader]="custom"
PKG_CATEGORY[gdrive-downloader]="utilities"

PACKAGES[portal]="portal"
PKG_DESC[portal]="Send files between computers [CUSTOM]"
PKG_METHOD[portal]="custom"
PKG_CATEGORY[portal]="utilities"

PACKAGES[shbin]="shbin"
PKG_DESC[shbin]="Turn a Github repo into a pastebin [CUSTOM]"
PKG_METHOD[shbin]="custom"
PKG_CATEGORY[shbin]="utilities"

PACKAGES[sharing]="sharing"
PKG_DESC[sharing]="Send and receive files on your mobile device [CUSTOM]"
PKG_METHOD[sharing]="custom"
PKG_CATEGORY[sharing]="utilities"

PACKAGES[ncp]="ncp"
PKG_DESC[ncp]="Transfer files and folders, to and from NFS servers [CUSTOM]"
PKG_METHOD[ncp]="custom"
PKG_CATEGORY[ncp]="utilities"

# Directory Listing
PACKAGES[alder]="alder"
PKG_DESC[alder]="Minimal tree with colors [CUSTOM]"
PKG_METHOD[alder]="custom"
PKG_CATEGORY[alder]="utilities"

PACKAGES[tre]="tre"
PKG_DESC[tre]="tree with git awareness, editor aliasing, and more [CUSTOM]"
PKG_METHOD[tre]="custom"
PKG_CATEGORY[tre]="utilities"

# ==============================================================================
# CATEGORY DEFINITIONS
# ==============================================================================

CATEGORIES=(
    "core:Core Utilities"
    "dev:Development Tools"
    "ai:AI & LLM Tools"
    "containers:Containers & Orchestration"
    "web:Web Stack"
    "shell:Shells & Customization"
    "editors:Editors & IDEs"
    "browsers:Web Browsers"
    "system-monitoring:System Monitoring"
    "network-monitoring:Network Monitoring"
    "performance-tools:Performance Tools"
    "utilities:Utilities"
    "database:Database Management"
    "security:Security Tools"
    "system:System Tools"
    "office:Office & Productivity"
    "communication:Communication"
    "graphics:Graphics & Design"
    "audio:Audio & Music"
    "video:Video & Media"
    "media-servers:Media Servers & Streaming"
    "cloud:Cloud & Sync"
    "terminals:Terminals"
    "gaming-platforms:Gaming Platforms"
    "gaming-emulators:Gaming Emulators"
    "sbc:Single Board Computers & Microcontrollers"
)

# Category hotkey mappings (A-Z)
declare -A CATEGORY_HOTKEYS=(
    ["core"]="A"
    ["dev"]="B"
    ["ai"]="C"
    ["containers"]="D"
    ["web"]="E"
    ["shell"]="F"
    ["editors"]="G"
    ["browsers"]="H"
    ["system-monitoring"]="I"
    ["network-monitoring"]="J"
    ["performance-tools"]="K"
    ["utilities"]="L"
    ["database"]="M"
    ["security"]="N"
    ["system"]="O"
    ["office"]="P"
    ["communication"]="Q"
    ["graphics"]="R"
    ["audio"]="S"
    ["video"]="T"
    ["media-servers"]="U"
    ["cloud"]="V"
    ["terminals"]="W"
    ["gaming-platforms"]="X"
    ["gaming-emulators"]="Y"
    ["sbc"]="Z"
    # Note: Back navigation in submenus now uses 'B' or 'Esc'
)

# ==============================================================================
# INSTALLATION FUNCTIONS
# ==============================================================================

apt_update() {
    log "Updating APT cache..."
    if sudo apt-get update -qq 2>&1 | tee -a "$LOGFILE"; then
        log "APT cache updated successfully"
    else
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log "APT cache updated with warnings (non-critical)"
        else
            log "WARNING: APT cache update failed with exit code $exit_code"
            log "Continuing anyway - some packages may not be available"
        fi
    fi
}

install_apt_package() {
    local pkg="$1"
    log "Installing $pkg via APT..."
    if sudo apt-get install -y --no-install-recommends "$pkg" 2>&1 | tee -a "$LOGFILE"; then
        log "Successfully installed $pkg"
        return 0
    else
        log "ERROR: Failed to install $pkg"
        return 1
    fi
}

remove_apt_package() {
    local pkg="$1"
    log "Removing $pkg via APT..."
    if sudo apt-get remove --purge -y "$pkg" 2>&1 | tee -a "$LOGFILE"; then
        log "Successfully removed $pkg"
        return 0
    else
        log "ERROR: Failed to remove $pkg"
        return 1
    fi
}

# Ensure snapd service and CLI are ready before any snap installation
ensure_snapd_ready() {
    log "Ensuring snapd is installed and ready"
    if ! dpkg-query -W snapd &>/dev/null; then
        log "snapd not installed; installing via APT"
        apt_update
        if ! sudo apt-get install -y --no-install-recommends snapd 2>&1 | tee -a "$LOGFILE"; then
            log_error "Failed to install snapd"
            return 1
        fi
    fi

    # Ensure key services and socket are enabled and running
    if command -v systemctl &>/dev/null; then
        sudo systemctl enable --now snapd.socket 2>/dev/null || true
        sudo systemctl enable --now snapd 2>/dev/null || true
        # AppArmor is commonly required for snaps on Ubuntu
        sudo systemctl enable --now apparmor 2>/dev/null || true
    fi

    # Ensure /snap symlink exists on systems where it's missing
    if [[ ! -e /snap ]]; then
        sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
    fi

    # Wait briefly for snap daemon to be ready
    if command -v snap &>/dev/null; then
        sudo snap wait system seed.loaded 2>/dev/null || sleep 2
        snap version 2>/dev/null | tee -a "$LOGFILE" || true
    fi
    log "snapd is ready"
}

requires_classic_snap() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        return 1
    fi
    # Known snaps that use classic confinement (common IDEs/editors)
    case "$pkg" in
        code|code-insiders|ghostty|sublime-text|pycharm-community|pycharm-professional|intellij-idea-community|intellij-idea-ultimate|webstorm|clion|goland|rider|rubymine|datagrip|phpstorm|android-studio|flutter)
            return 0
            ;;
    esac
    # Dynamic check via snap info when available
    if command -v snap &>/dev/null; then
        if snap info "$pkg" 2>/dev/null | awk -F: '/^[[:space:]]*confinement/{print $2}' | grep -qi 'classic'; then
            return 0
        fi
    fi
    return 1
}

install_snap_package() {
    local pkg="$1"
    log "Installing $pkg via Snap..."
    
    # Check if snapd is running
    if ! systemctl is-active --quiet snapd; then
        log "Starting snapd service..."
        sudo systemctl start snapd
        sleep 2
    fi
    
    # Wait for snap to be ready
    log "Waiting for snap to be ready..."
    timeout 30 sudo snap wait system seed.loaded || {
        log "Warning: Snap system not fully ready, proceeding anyway..."
    }
    
    if requires_classic_snap "$pkg"; then
        log "Installing $pkg with classic confinement..."
        timeout 300 sudo snap install "$pkg" --classic 2>&1 | tee -a "$LOGFILE"
        local exit_code=${PIPESTATUS[0]}
    else
        log "Installing $pkg..."
        timeout 300 sudo snap install "$pkg" 2>&1 | tee -a "$LOGFILE"
        local exit_code=${PIPESTATUS[0]}
    fi
    
    # Check installation result
    if [ $exit_code -eq 124 ]; then
        log "ERROR: Snap installation timed out after 5 minutes"
        return 1
    elif [ $exit_code -ne 0 ]; then
        log "ERROR: Snap installation failed with exit code $exit_code"
        return 1
    fi
    
    log "Successfully installed $pkg via Snap"
    return 0
}

remove_snap_package() {
    local pkg="$1"
    log "Removing $pkg via Snap..."
    sudo snap remove "$pkg" 2>&1 | tee -a "$LOGFILE"
}

install_flatpak_package() {
    local pkg="$1"
    log "Installing $pkg via Flatpak..."
    flatpak install -y flathub "$pkg" 2>&1 | tee -a "$LOGFILE"
}

remove_flatpak_package() {
    local pkg="$1"
    log "Removing $pkg via Flatpak..."
    flatpak uninstall -y "$pkg" 2>&1 | tee -a "$LOGFILE"
}

install_npm_package() {
    local pkg="$1"
    log "Installing $pkg via NPM..."
    
    # Ensure Node.js and npm are installed
    if ! command -v npm >/dev/null 2>&1; then
        ui_msg "Node.js Required" "Installing Node.js and npm first...\n\n⏳ This process is automatic - please wait..."
        install_nodejs
        if [[ $? -ne 0 ]]; then
            log_error "Failed to install Node.js/npm prerequisite"
            return 1
        fi
    fi
    
    sudo npm install -g "$pkg" 2>&1 | tee -a "$LOGFILE"
}

remove_npm_package() {
    local pkg="$1"
    log "Removing $pkg via NPM..."
    sudo npm uninstall -g "$pkg" 2>&1 | tee -a "$LOGFILE"
}

install_pip_package() {
    local pkg="$1"
    log "Pip installations are disabled by policy"
    ui_msg "Pip Install Disabled" "Installing $pkg via pip is disabled. Please use APT, SNAP, FLATPAK, or a supported method."
    return 1
}

remove_pip_package() {
    local pkg="$1"
    log "Pip removals are disabled by policy"
    ui_msg "Pip Removal Disabled" "Removing $pkg via pip is disabled. Use the appropriate package manager if installed there."
    return 1
}

install_cargo_package() {
    local pkg="$1"
    log "Installing $pkg via Cargo..."
    
    # Ensure Rust and Cargo are installed
    if ! command -v cargo >/dev/null 2>&1; then
        ui_msg "Rust Required" "Installing Rust and Cargo first...\n\n⏳ This process is automatic - please wait..."
        
        # Install Rust via rustup
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1 | tee -a "$LOGFILE"
        
        # Source the cargo environment
        source "$HOME/.cargo/env" 2>/dev/null || true
        
        if ! command -v cargo >/dev/null 2>&1; then
            log_error "Failed to install Rust/Cargo prerequisite"
            return 1
        fi
    fi
    
    cargo install "$pkg" 2>&1 | tee -a "$LOGFILE"
}

remove_cargo_package() {
    local pkg="$1"
    log "Removing $pkg via Cargo..."
    cargo uninstall "$pkg" 2>&1 | tee -a "$LOGFILE"
}

# ==============================================================================
# CUSTOM INSTALLERS (for buntages requiring special setup)
# ==============================================================================

install_docker() {
    log "Installing Docker from official repository..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Neutralize duplicate sources/keys that may conflict
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'download\.docker\.com/linux/ubuntu' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Docker source list: $f"
        fi
    done
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ docker ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done

    # Add Docker repository
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt_update
    install_apt_package "docker-ce"
    install_apt_package "docker-ce-cli"
    install_apt_package "containerd.io"
    install_apt_package "docker-buildx-plugin"
    install_apt_package "docker-compose-plugin"
    
    # Add user to docker group
    sudo usermod -aG docker "$USER" || true
    
    ui_msg "Docker Installed" "Docker installed successfully. Log out and back in for group changes to take effect."
}

remove_docker() {
    ui_yesno "Remove Docker?" "This will remove Docker and optionally its data. Continue?" || return 1
    
    remove_apt_package "docker-ce"
    remove_apt_package "docker-ce-cli"
    remove_apt_package "containerd.io"
    remove_apt_package "docker-buildx-plugin"
    remove_apt_package "docker-compose-plugin"
    
    if ui_yesno "Remove Data?" "Remove Docker data directories (/var/lib/docker)?"; then
        sudo rm -rf /var/lib/docker /var/lib/containerd
        log "Docker data removed"
    fi
    
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ docker ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
}

install_minikube() {
    log "Installing Minikube..."
    
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    curl -LO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}"
    sudo install minikube-linux-${arch} /usr/local/bin/minikube
    rm -f minikube-linux-${arch}
    
    ui_msg "Minikube Installed" "Minikube installed successfully."
}

remove_minikube() {
    sudo rm -f /usr/local/bin/minikube
    rm -rf ~/.minikube 2>/dev/null || true
}

install_kind() {
    log "Installing Kind..."
    
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-${arch}"
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    
    ui_msg "Kind Installed" "Kind installed successfully."
}

remove_kind() {
    sudo rm -f /usr/local/bin/kind
}

install_ctop() {
    log "Installing ctop..."
    
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    curl -Lo ctop "https://github.com/bcicen/ctop/releases/latest/download/ctop-0.7.7-linux-${arch}"
    chmod +x ctop
    sudo mv ctop /usr/local/bin/ctop
    
    ui_msg "ctop Installed" "ctop installed successfully."
}

remove_ctop() {
    sudo rm -f /usr/local/bin/ctop
}

install_lazydocker() {
    log "Installing LazyDocker..."
    
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="x86_64" ;;
        arm64) arch="armv6" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    local version
    version=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name": "v\K[^"]*')
    
    curl -Lo lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${version}_Linux_${arch}.tar.gz"
    tar xf lazydocker.tar.gz lazydocker
    sudo mv lazydocker /usr/local/bin/
    rm -f lazydocker.tar.gz
    
    ui_msg "LazyDocker Installed" "LazyDocker installed successfully."
}

remove_lazydocker() {
    sudo rm -f /usr/local/bin/lazydocker
}

install_nodejs() {
    log "Installing Node.js ${NODE_LTS} from NodeSource..."
    
    # Neutralize duplicate sources/keys that may conflict
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'deb\.nodesource\.com' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting NodeSource source list: $f"
        fi
    done
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ nodesource ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
    sudo rm -f /usr/share/keyrings/nodesource.gpg /etc/apt/keyrings/nodesource.gpg

    curl -fsSL https://deb.nodesource.com/setup_${NODE_LTS}.x | sudo -E bash -
    apt_update
    install_apt_package "nodejs"
    
    ui_msg "Node.js Installed" "Node.js ${NODE_LTS} and npm installed successfully."
}

remove_nodejs() {
    remove_apt_package "nodejs"
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
    sudo rm -f /usr/share/keyrings/nodesource.gpg /etc/apt/keyrings/nodesource.gpg
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ nodesource ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
}

install_vscode() {
    log "Installing VS Code from Microsoft repository..."
    
    # Neutralize duplicate sources/keys that may conflict
    # Remove any vendor key in trusted.gpg.d
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ microsoft ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
    # Remove any existing sources pointing to the Microsoft Code repo
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'packages\.microsoft\.com/.*/code' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Microsoft source list: $f"
        fi
    done
    
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null
    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
    
    apt_update
    install_apt_package "code"
    
    ui_msg "VS Code Installed" "Visual Studio Code installed successfully."
}

remove_vscode() {
    remove_apt_package "code"
    sudo rm -f /etc/apt/sources.list.d/vscode.list
    sudo rm -f /usr/share/keyrings/packages.microsoft.gpg
    # Clean up any vendor key left in trusted.gpg.d
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ microsoft ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
}

install_brave() {
    log "Installing Brave browser..."
    
    # Neutralize duplicate sources/keys that may conflict
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ brave ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'brave-browser-apt-release\.s3\.brave\.com' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Brave source list: $f"
        fi
    done
    
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
    
    apt_update
    install_apt_package "brave-browser"
    
    ui_msg "Brave Installed" "Brave browser installed successfully."
}

remove_brave() {
    remove_apt_package "brave-browser"
    sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
    sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
    # Clean up any vendor key or duplicate sources
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ brave ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'brave-browser-apt-release\.s3\.brave\.com' "$f"; then
            sudo rm -f "$f"
            log "Removed Brave source list: $f"
        fi
    done
}

install_sublime() {
    log "Installing Sublime Text..."
    
    # Neutralize duplicate sources/keys that may conflict
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ sublime ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'download\.sublimetext\.com' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Sublime source list: $f"
        fi
    done
    
    wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/sublimehq-archive.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/sublimehq-archive.gpg] https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
    
    apt_update
    install_apt_package "sublime-text"
    
    ui_msg "Sublime Text Installed" "Sublime Text installed successfully."
}

remove_sublime() {
    remove_apt_package "sublime-text"
    sudo rm -f /etc/apt/sources.list.d/sublime-text.list
    sudo rm -f /usr/share/keyrings/sublimehq-archive.gpg
    # Clean up any vendor key
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ sublime ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
}

install_warp() {
    log "Installing Warp terminal..."
    
    # Normalize/clean any conflicting Warp repo entries and keys first
    # Remove vendor key that may conflict with our canonical keyring path
    if [[ -f "/etc/apt/trusted.gpg.d/warpdotdev.gpg" ]]; then
        sudo rm -f "/etc/apt/trusted.gpg.d/warpdotdev.gpg"
        log "Removed vendor key: /etc/apt/trusted.gpg.d/warpdotdev.gpg"
    fi

    # Remove any existing sources that point to releases.warp.dev to avoid duplicate Signed-By entries
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'releases\.warp\.dev/.*/deb' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Warp source list: $f"
        fi
    done

    # Add Warp's official GPG key and our canonical repository entry
    sudo mkdir -p /usr/share/keyrings
    if ! wget -qO- https://releases.warp.dev/linux/keys/warp.asc | sudo gpg --dearmor -o /usr/share/keyrings/warp-archive-keyring.gpg; then
        log_error "Failed to add Warp GPG key"
        return 1
    fi

    echo "deb [signed-by=/usr/share/keyrings/warp-archive-keyring.gpg] https://releases.warp.dev/linux/deb stable main" | sudo tee /etc/apt/sources.list.d/warp-terminal.list > /dev/null
    log "Added Warp source: /etc/apt/sources.list.d/warp-terminal.list"

    # Update package list and install
    apt_update
    if install_apt_package "warp-terminal"; then
        ui_msg "Warp Installed" "Warp terminal installed successfully."
    else
        log_error "Failed to install Warp terminal from repository"
        return 1
    fi
}

remove_warp() {
    remove_apt_package "warp-terminal"
    # Clean up both our canonical repo and any vendor leftovers
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'releases\.warp\.dev/.*/deb' "$f"; then
            sudo rm -f "$f"
            log "Removed Warp source list: $f"
        fi
    done
    sudo rm -f /usr/share/keyrings/warp-archive-keyring.gpg
    sudo rm -f /etc/apt/trusted.gpg.d/warpdotdev.gpg
}

install_ollama() {
    log "Installing Ollama..."
    
    # Download and install Ollama
    if curl -fsSL https://ollama.ai/install.sh | sh; then
        ui_msg "Ollama Installed" "Ollama AI model runner installed successfully."
    else
        log_error "Failed to install Ollama"
        return 1
    fi
}

remove_ollama() {
    log "Removing Ollama..."
    sudo systemctl stop ollama 2>/dev/null || true
    sudo systemctl disable ollama 2>/dev/null || true
    sudo rm -f /usr/local/bin/ollama
    sudo rm -rf /usr/share/ollama
    sudo rm -f /etc/systemd/system/ollama.service
    sudo systemctl daemon-reload
}

install_yt-dlp() {
    log "Installing yt-dlp via apt..."
    if sudo apt-get update && sudo apt-get install -y yt-dlp; then
        ui_msg "yt-dlp Installed" "yt-dlp YouTube downloader installed successfully via apt."
        return 0
    else
        log_error "Failed to install yt-dlp via apt"
        return 1
    fi
}

remove_yt-dlp() {
    log "Removing yt-dlp via apt..."
    if sudo apt-get remove -y yt-dlp; then
        ui_msg "yt-dlp Removed" "yt-dlp removed successfully via apt."
        return 0
    else
        log_error "Failed to remove yt-dlp via apt"
        return 1
    fi
}

install_invidious() {
    log "Installing Invidious..."
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required for Invidious. Please install Docker first."
        return 1
    fi
    
    # Create invidious directory
    mkdir -p "$HOME/invidious"
    cd "$HOME/invidious"
    
    # Download docker-compose file
    if curl -L -o docker-compose.yml https://raw.githubusercontent.com/iv-org/invidious/master/docker-compose.yml; then
        ui_msg "Invidious Installed" "Invidious Docker setup downloaded to $HOME/invidious. Run 'docker-compose up -d' to start."
    else
        log_error "Failed to download Invidious docker-compose file"
        return 1
    fi
}

remove_invidious() {
    log "Removing Invidious..."
    if [ -d "$HOME/invidious" ]; then
        cd "$HOME/invidious"
        docker-compose down 2>/dev/null || true
        cd "$HOME"
        rm -rf "$HOME/invidious"
    fi
}

install_seafile() {
    log "Installing Seafile..."
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required for Seafile. Please install Docker first."
        return 1
    fi
    
    # Create seafile directory
    mkdir -p "$HOME/seafile"
    cd "$HOME/seafile"
    
    # Download docker-compose file for Seafile
    if curl -L -o docker-compose.yml https://raw.githubusercontent.com/haiwen/seafile-docker/master/docker-compose.yml; then
        ui_msg "Seafile Installed" "Seafile Docker setup downloaded to $HOME/seafile. Run 'docker-compose up -d' to start."
    else
        log_error "Failed to download Seafile docker-compose file"
        return 1
    fi
}

remove_seafile() {
    log "Removing Seafile..."
    if [ -d "$HOME/seafile" ]; then
        cd "$HOME/seafile"
        docker-compose down 2>/dev/null || true
        cd "$HOME"
        rm -rf "$HOME/seafile"
    fi
}

install_snapraid() {
    log "Installing SnapRAID..."
    
    # Install dependencies
    sudo apt update
    sudo apt install -y build-essential
    
    # Download and compile SnapRAID
    cd /tmp
    if wget https://github.com/amadvance/snapraid/releases/download/v12.2/snapraid-12.2.tar.gz; then
        tar -xzf snapraid-12.2.tar.gz
        cd snapraid-12.2
        ./configure
        make
        sudo make install
        ui_msg "SnapRAID Installed" "SnapRAID parity protection tool installed successfully."
    else
        log_error "Failed to download SnapRAID"
        return 1
    fi
}

remove_snapraid() {
    log "Removing SnapRAID..."
    sudo rm -f /usr/local/bin/snapraid
    sudo rm -f /usr/local/share/man/man1/snapraid.1
}

install_greyhole() {
    log "Installing Greyhole..."
    
    # Check if Samba is installed
    if ! command -v smbd >/dev/null 2>&1; then
        log_error "Samba is required for Greyhole. Please install Samba first."
        return 1
    fi
    
    # Add Greyhole PPA and install
    sudo add-apt-repository -y ppa:greyhole/greyhole
    sudo apt update
    if sudo apt install -y greyhole; then
        ui_msg "Greyhole Installed" "Greyhole storage pooling installed. Configure /etc/greyhole.conf before use."
    else
        log_error "Failed to install Greyhole"
        return 1
    fi
}

remove_greyhole() {
    log "Removing Greyhole..."
    sudo apt remove -y greyhole 2>/dev/null || true
    sudo add-apt-repository -r ppa:greyhole/greyhole 2>/dev/null || true
}

install_mergerfs() {
    log "Installing MergerFS..."
    
    # Download and install MergerFS .deb package
    cd /tmp
    if wget https://github.com/trapexit/mergerfs/releases/download/2.35.1/mergerfs_2.35.1.ubuntu-jammy_amd64.deb; then
        if sudo dpkg -i mergerfs_2.35.1.ubuntu-jammy_amd64.deb; then
            ui_msg "MergerFS Installed" "MergerFS union filesystem installed successfully."
        else
            sudo apt install -f -y
            ui_msg "MergerFS Installed" "MergerFS union filesystem installed successfully."
        fi
    else
        log_error "Failed to download MergerFS"
        return 1
    fi
}

remove_mergerfs() {
    log "Removing MergerFS..."
    sudo apt remove -y mergerfs 2>/dev/null || true
}

install_n8n() {
    log "Installing n8n..."
    
    # Check if Node.js is installed
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js is required for n8n. Please install Node.js first."
        return 1
    fi
    
    # Install n8n globally via npm
    if sudo npm install -g n8n; then
        ui_msg "n8n Installed" "n8n workflow automation tool installed successfully."
    else
        log_error "Failed to install n8n"
        return 1
    fi
}

remove_n8n() {
    log "Removing n8n..."
    sudo npm uninstall -g n8n 2>/dev/null || true
}

install_discord-deb() {
    log "Installing Discord (DEB package)..."
    
    # Download Discord DEB package
    local discord_url="https://discord.com/api/download?platform=linux&format=deb"
    local temp_file="/tmp/discord.deb"
    
    if wget -O "$temp_file" "$discord_url" 2>/dev/null; then
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "Discord Installed" "Discord voice and text chat installed successfully."
        else
            log_error "Failed to install Discord DEB package"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_error "Failed to download Discord DEB package"
        return 1
    fi
}

remove_discord-deb() {
    log "Removing Discord (DEB)..."
    remove_apt_package "discord"
}

install_plex() {
    log "Installing Plex Media Server..."
    
    # Neutralize duplicate sources/keys
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'downloads\.plex\.tv/repo/deb' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Plex source list: $f"
        fi
    done
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ plex ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
    
    # Add Plex repository key
    curl https://downloads.plex.tv/plex-keys/PlexSign.key | sudo apt-key add -
    
    # Add Plex repository
    echo "deb https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
    
    # Update package list and install Plex
    if sudo apt update && sudo apt install -y plexmediaserver; then
        # Enable and start Plex service
        sudo systemctl enable plexmediaserver
        sudo systemctl start plexmediaserver
        ui_msg "Plex Installed" "Plex Media Server installed successfully. Access at http://localhost:32400/web"
    else
        log_error "Failed to install Plex Media Server"
        return 1
    fi
}

remove_plex() {
    log "Removing Plex Media Server..."
    sudo systemctl stop plexmediaserver 2>/dev/null || true
    sudo systemctl disable plexmediaserver 2>/dev/null || true
    remove_apt_package "plexmediaserver"
    sudo rm -f /etc/apt/sources.list.d/plexmediaserver.list
    sudo apt-key del 7BB9C367 2>/dev/null || true
}

install_ums() {
    log "Installing Universal Media Server (UMS)..."
    
    # Check if Java is installed
    if ! command -v java >/dev/null 2>&1; then
        log_error "Java is required for UMS. Installing OpenJDK..."
        sudo apt update && sudo apt install -y openjdk-11-jre
    fi
    
    # Download UMS DEB package
    local ums_url="https://github.com/UniversalMediaServer/UniversalMediaServer/releases/latest/download/ums.deb"
    local temp_file="/tmp/ums.deb"
    
    if wget -O "$temp_file" "$ums_url" 2>/dev/null; then
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "UMS Installed" "Universal Media Server installed successfully. Access at http://localhost:5001"
        else
            log_error "Failed to install UMS DEB package"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_error "Failed to download UMS DEB package"
        return 1
    fi
}

remove_ums() {
    log "Removing Universal Media Server..."
    remove_apt_package "ums"
}

install_gollama() {
    log "Installing Gollama..."
    
    # Download and install Gollama from GitHub releases
    local latest_url=$(curl -s https://api.github.com/repos/sammcj/gollama/releases/latest | grep "browser_download_url.*linux.*amd64" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get Gollama download URL"
        return 1
    fi
    
    local temp_file="/tmp/gollama"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        chmod +x "$temp_file"
        sudo mv "$temp_file" /usr/local/bin/gollama
        ui_msg "Gollama Installed" "Gollama LLM management tool installed successfully."
    else
        log_error "Failed to download Gollama"
        return 1
    fi
}

remove_gollama() {
    log "Removing Gollama..."
    sudo rm -f /usr/local/bin/gollama
}

install_lm-studio() {
    log "Installing LM Studio..."
    
    # Download LM Studio AppImage
    local lm_studio_url="https://releases.lmstudio.ai/linux/x86/0.3.5/LM_Studio-0.3.5.AppImage"
    local temp_file="/tmp/LM_Studio.AppImage"
    
    if wget -O "$temp_file" "$lm_studio_url" 2>/dev/null; then
        chmod +x "$temp_file"
        sudo mv "$temp_file" /usr/local/bin/lm-studio
        ui_msg "LM Studio Installed" "LM Studio GUI for local LLMs installed successfully.\n\nRun with: lm-studio"
    else
        log_error "Failed to download LM Studio"
        return 1
    fi
}

remove_lm-studio() {
    log "Removing LM Studio..."
    sudo rm -f /usr/local/bin/lm-studio
}

install_text-generation-webui() {
    log "Installing Text Generation WebUI..."
    ui_msg "Python/Pip Disabled" "Text Generation WebUI requires Python/pip which are disabled by policy. Please use a non-Python alternative."
    return 1
    
    # Clone the repository
    local install_dir="/opt/text-generation-webui"
    
    if git clone https://github.com/oobabooga/text-generation-webui.git "$install_dir" 2>/dev/null; then
        cd "$install_dir"
        # Install dependencies
        pip3 install -r requirements.txt 2>/dev/null || true
        
        # Create launcher script
        sudo tee /usr/local/bin/text-generation-webui > /dev/null << 'EOF'
#!/bin/bash
cd /opt/text-generation-webui
python3 server.py "$@"
EOF
        sudo chmod +x /usr/local/bin/text-generation-webui
        
        ui_msg "Text Generation WebUI Installed" "Text Generation WebUI installed successfully.\n\nRun with: text-generation-webui"
    else
        log_error "Failed to clone Text Generation WebUI"
        return 1
    fi
}

remove_text-generation-webui() {
    log "Removing Text Generation WebUI..."
    sudo rm -rf /opt/text-generation-webui
    sudo rm -f /usr/local/bin/text-generation-webui
}

install_whisper-cpp() {
    log "Installing Whisper.cpp..."
    
    # Install build dependencies
    install_apt_package "build-essential"
    install_apt_package "cmake"
    
    # Clone and build whisper.cpp
    local build_dir="/tmp/whisper.cpp"
    
    if git clone https://github.com/ggerganov/whisper.cpp.git "$build_dir" 2>/dev/null; then
        cd "$build_dir"
        make -j$(nproc) 2>/dev/null
        
        # Install binaries
        sudo cp main /usr/local/bin/whisper-main
        sudo cp quantize /usr/local/bin/whisper-quantize
        sudo cp server /usr/local/bin/whisper-server
        
        # Create convenience script
        sudo tee /usr/local/bin/whisper-cpp > /dev/null << 'EOF'
#!/bin/bash
whisper-main "$@"
EOF
        sudo chmod +x /usr/local/bin/whisper-cpp
        
        # Clean up
        rm -rf "$build_dir"
        
        ui_msg "Whisper.cpp Installed" "Whisper.cpp offline speech-to-text installed successfully.\n\nRun with: whisper-cpp"
    else
        log_error "Failed to clone Whisper.cpp"
        return 1
    fi
}

remove_whisper-cpp() {
    log "Removing Whisper.cpp..."
    sudo rm -f /usr/local/bin/whisper-main
    sudo rm -f /usr/local/bin/whisper-quantize
    sudo rm -f /usr/local/bin/whisper-server
    sudo rm -f /usr/local/bin/whisper-cpp
}

install_comfyui() {
    log "Installing ComfyUI..."
    ui_msg "Python/Pip Disabled" "ComfyUI requires Python/pip which are disabled by policy. Please use a non-Python alternative."
    return 1
    
    # Clone ComfyUI repository
    local install_dir="/opt/ComfyUI"
    
    if git clone https://github.com/comfyanonymous/ComfyUI.git "$install_dir" 2>/dev/null; then
        cd "$install_dir"
        
        # Install Python dependencies
        pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu 2>/dev/null || true
        pip3 install -r requirements.txt 2>/dev/null || true
        
        # Create launcher script
        sudo tee /usr/local/bin/comfyui > /dev/null << 'EOF'
#!/bin/bash
cd /opt/ComfyUI
python3 main.py "$@"
EOF
        sudo chmod +x /usr/local/bin/comfyui
        
        ui_msg "ComfyUI Installed" "ComfyUI visual Stable Diffusion interface installed successfully.\n\nRun with: comfyui"
    else
        log_error "Failed to clone ComfyUI"
        return 1
    fi
}

remove_comfyui() {
    log "Removing ComfyUI..."
    sudo rm -rf /opt/ComfyUI
    sudo rm -f /usr/local/bin/comfyui
}

install_invokeai() {
    log "Installing InvokeAI..."
    ui_msg "Python/Pip Disabled" "InvokeAI requires Python/pip which are disabled by policy. Please use a non-Python alternative."
    return 1
    
    # Install InvokeAI via pip
    if pip3 install invokeai[xformers] --upgrade 2>/dev/null; then
        ui_msg "InvokeAI Installed" "InvokeAI Stable Diffusion generator installed successfully.\n\nRun with: invokeai-web"
    else
        log_error "Failed to install InvokeAI"
        return 1
    fi
}

remove_invokeai() {
    log "Removing InvokeAI..."
    pip3 uninstall -y invokeai 2>/dev/null || true
}

install_koboldcpp() {
    log "Installing KoboldCpp..."
    
    # Download KoboldCpp binary
    local kobold_url="https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-linux-x64"
    local temp_file="/tmp/koboldcpp"
    
    if wget -O "$temp_file" "$kobold_url" 2>/dev/null; then
        chmod +x "$temp_file"
        sudo mv "$temp_file" /usr/local/bin/koboldcpp
        ui_msg "KoboldCpp Installed" "KoboldCpp LLM interface installed successfully.\n\nRun with: koboldcpp"
    else
        log_error "Failed to download KoboldCpp"
        return 1
    fi
}

remove_koboldcpp() {
    log "Removing KoboldCpp..."
    sudo rm -f /usr/local/bin/koboldcpp
}

install_phpmyadmin() {
    log "Installing phpMyAdmin with non-interactive configuration..."
    
    # Ensure MariaDB/MySQL is running and properly configured
    if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
        ui_msg "Database Required" "MariaDB/MySQL must be installed and running first.\n\nInstall MariaDB from the Web Stack category, then try phpMyAdmin again."
        return 1
    fi
    
    # FIRST: Read the MySQL root password from file if it exists
    local mysql_root_pass=""
    if sudo test -f "/root/.mysql_root_password"; then
        mysql_root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null | tr -d '\n\r')
        if [[ -n "$mysql_root_pass" ]]; then
            log "Read MySQL root password from /root/.mysql_root_password"
        else
            log "Password file exists but is empty"
        fi
    else
        log "No MySQL root password file found at /root/.mysql_root_password"
    fi
    
    # If no password file exists, check if we can connect without password
    if [[ -z "$mysql_root_pass" ]]; then
        log "No MySQL root password file found, checking if MySQL allows passwordless root access..."
        if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
            log "MySQL allows passwordless root access, will set a password"
        else
            ui_msg "MySQL Setup Required" "MySQL root password needs to be configured.\n\nPlease run the MariaDB installation from Web Stack first, or manually configure MySQL root access."
            return 1
        fi
    fi
    
    # Now handle MySQL authentication setup
    if [[ -n "$mysql_root_pass" ]]; then
        # We have a password, test if it works
        if mysql -u root -p"$mysql_root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
            log "MySQL root password verified successfully"
        else
            log "Existing MySQL root password failed verification"
            ui_msg "MySQL Authentication Error" "The stored MySQL root password is not working.\n\nPlease reset the MariaDB root password from the Database Management section first."
            return 1
        fi
    else
        # No password exists, set one up (fresh install scenario)
        log "Setting up MySQL root authentication for fresh install..."
        mysql_root_pass=$(openssl rand -base64 32)
        mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_pass';" 2>/dev/null || \
        mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$mysql_root_pass');" 2>/dev/null || \
        mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('$mysql_root_pass') WHERE User='root'; FLUSH PRIVILEGES;" 2>/dev/null
        
        # Save the password
        echo "$mysql_root_pass" | sudo tee /root/.mysql_root_password > /dev/null
        sudo chmod 600 /root/.mysql_root_password
        log "New MySQL root password set and saved"
    fi
    
    # Pre-configure phpMyAdmin with minimal debconf configuration
    # Clear any existing debconf selections first
    sudo debconf-communicate <<< "PURGE phpmyadmin" 2>/dev/null || true
    
    # Use only the essential debconf questions that actually exist
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | sudo debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect " | sudo debconf-set-selections
    
    # Set MySQL root password via debconf database directly
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password $mysql_root_pass" | sudo debconf-set-selections 2>/dev/null || true
    
    # Alternative approach: Set MySQL root password via environment and config file
    export MYSQL_ROOT_PASSWORD="$mysql_root_pass"
    
    # Install phpMyAdmin with simplified approach
    apt_update
    
    # Set environment variables for non-interactive installation
    export DEBIAN_FRONTEND=noninteractive
    
    # Create MySQL defaults file for phpMyAdmin configuration
    local mysql_defaults_file="/tmp/mysql_defaults_phpmyadmin.cnf"
    sudo tee "$mysql_defaults_file" > /dev/null <<EOF
[mysql]
user=root
password=$mysql_root_pass
host=localhost

[mysqldump]
user=root
password=$mysql_root_pass
host=localhost
EOF
    sudo chmod 600 "$mysql_defaults_file"
    
    # Pre-configure MySQL for phpMyAdmin setup
    mysql --defaults-file="$mysql_defaults_file" -e "
        CREATE DATABASE IF NOT EXISTS phpmyadmin;
        GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'root'@'localhost';
        FLUSH PRIVILEGES;
    " 2>/dev/null || true
    
    # Install phpMyAdmin with minimal interaction
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin php-mbstring php-zip php-gd php-json php-curl 2>&1 | tee -a "$LOGFILE"; then
        
        # Clean up temporary config file
        sudo rm -f "$mysql_defaults_file"
        
        # Detect web server and configure accordingly
        local web_server=""
        if systemctl is-active --quiet nginx; then
            web_server="nginx"
        elif systemctl is-active --quiet apache2; then
            web_server="apache2"
        fi
        
        case "$web_server" in
            nginx)
                # Configure phpMyAdmin for Nginx (fix variable expansion)
                local nginx_config="/etc/nginx/sites-available/phpmyadmin"
                sudo tee "$nginx_config" > /dev/null << EOF
server {
    listen 80;
    server_name phpmyadmin.localhost;
    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
                # Enable the site
                sudo ln -sf "$nginx_config" /etc/nginx/sites-enabled/
                if sudo nginx -t 2>/dev/null; then
                    sudo systemctl reload nginx
                    ui_msg "phpMyAdmin Installed" "✅ phpMyAdmin installed successfully!\n\n🌐 Access via: http://phpmyadmin.localhost\n📁 Files located at: /usr/share/phpmyadmin\n🔑 MySQL root password saved to: /root/.mysql_root_password\n\n⚠️  Note: Configure your hosts file or DNS to point phpmyadmin.localhost to this server."
                else
                    ui_msg "phpMyAdmin Installed" "✅ phpMyAdmin installed successfully!\n\n📁 Files located at: /usr/share/phpmyadmin\n🔑 MySQL root password saved to: /root/.mysql_root_password\n\n⚠️  Nginx configuration has errors. Please check manually."
                fi
                ;;
            apache2)
                # Configure phpMyAdmin for Apache
                sudo ln -sf /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
                sudo a2enconf phpmyadmin
                sudo systemctl reload apache2
                ui_msg "phpMyAdmin Installed" "✅ phpMyAdmin installed successfully!\n\n🌐 Access via: http://localhost/phpmyadmin\n📁 Files located at: /usr/share/phpmyadmin\n🔑 MySQL root password saved to: /root/.mysql_root_password\n\n🔧 Apache configuration enabled automatically."
                ;;
            *)
                ui_msg "phpMyAdmin Installed" "✅ phpMyAdmin installed successfully!\n\n📁 Files located at: /usr/share/phpmyadmin\n🔑 MySQL root password saved to: /root/.mysql_root_password\n\n⚠️  Manual web server configuration required:\n• For Nginx: Configure server block\n• For Apache: Enable phpmyadmin.conf\n• Access via your web server setup"
                ;;
        esac
        
        log "phpMyAdmin installed successfully"
        return 0
    else
        # Clean up temporary config file on failure
        sudo rm -f "$mysql_defaults_file"
        log_error "Failed to install phpMyAdmin"
        ui_msg "Installation Failed" "❌ phpMyAdmin installation failed.\n\nCheck the log file for details:\n$LOGFILE\n\nCommon issues:\n• MySQL/MariaDB not properly configured\n• Network connectivity problems\n• Package repository issues"
        return 1
    fi
}

install_adminer() {
    log "Installing Adminer with database credential integration..."
    
    # Ensure web server is available
    local web_server=""
    if systemctl is-active --quiet nginx; then
        web_server="nginx"
    elif systemctl is-active --quiet apache2; then
        web_server="apache2"
    else
        ui_msg "Web Server Required" "A web server (Nginx or Apache) must be installed and running first.\n\nInstall a web server from the Web Stack category, then try Adminer again."
        return 1
    fi
    
    # Install PHP if not already installed
    if ! command -v php >/dev/null 2>&1; then
        ui_msg "PHP Required" "PHP must be installed first.\n\nInstall PHP from the Web Stack category, then try Adminer again."
        return 1
    fi
    
    # Create adminer directory
    local adminer_dir="/var/www/adminer"
    sudo mkdir -p "$adminer_dir"
    
    # Download latest Adminer
    log "Downloading latest Adminer..."
    if sudo wget -O "$adminer_dir/index.php" "https://www.adminer.org/latest.php" 2>&1 | tee -a "$LOGFILE"; then
        sudo chown -R www-data:www-data "$adminer_dir"
        sudo chmod 644 "$adminer_dir/index.php"
        
        # Configure web server
        case "$web_server" in
            nginx)
                # Configure Adminer for Nginx
                local nginx_config="/etc/nginx/sites-available/adminer"
                sudo tee "$nginx_config" > /dev/null << EOF
server {
    listen 80;
    server_name adminer.localhost;
    root $adminer_dir;
    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
                # Enable the site
                sudo ln -sf "$nginx_config" /etc/nginx/sites-enabled/
                if sudo nginx -t 2>/dev/null; then
                    sudo systemctl reload nginx
                    show_adminer_success_message "nginx"
                else
                    ui_msg "Adminer Installed" "✅ Adminer installed successfully!\n\n📁 Files located at: $adminer_dir\n\n⚠️  Nginx configuration has errors. Please check manually."
                fi
                ;;
            apache2)
                # Configure Adminer for Apache
                local apache_config="/etc/apache2/sites-available/adminer.conf"
                sudo tee "$apache_config" > /dev/null << EOF
<VirtualHost *:80>
    ServerName adminer.localhost
    DocumentRoot $adminer_dir
    
    <Directory $adminer_dir>
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/adminer_error.log
    CustomLog \${APACHE_LOG_DIR}/adminer_access.log combined
</VirtualHost>
EOF
                sudo a2ensite adminer.conf
                sudo systemctl reload apache2
                show_adminer_success_message "apache2"
                ;;
        esac
        
        log "Adminer installed successfully"
        return 0
    else
        log_error "Failed to download Adminer"
        return 1
    fi
}

show_adminer_success_message() {
    local web_server="$1"
    local access_url=""
    local config_note=""
    
    case "$web_server" in
        nginx)
            access_url="http://adminer.localhost"
            config_note="⚠️  Note: Configure your hosts file or DNS to point adminer.localhost to this server."
            ;;
        apache2)
            access_url="http://adminer.localhost"
            config_note="🔧 Apache virtual host configured automatically."
            ;;
    esac
    
    # Get database credentials if available
    local creds_info=""
    if [[ -f "/root/.mysql_root_password" ]]; then
        local root_pass
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
        if [[ -n "$root_pass" ]]; then
            creds_info="\n🔑 Available Database Credentials:\n"
            creds_info+="• Server: localhost\n"
            creds_info+="• Username: root\n"
            creds_info+="• Password: $root_pass\n"
            creds_info+="• Database: (select from dropdown)\n\n"
            creds_info+="💡 These credentials are also available in Database Management > Show Credentials"
        fi
    elif sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        creds_info="\n🔑 Database Access Available:\n"
        creds_info+="• Server: localhost\n"
        creds_info+="• Username: root\n"
        creds_info+="• Password: (leave empty - using system auth)\n"
        creds_info+="• Database: (select from dropdown)\n\n"
        creds_info+="💡 Or set a password in Database Management > Reset Root Password"
    fi
    
    ui_msg "Adminer Installed" "✅ Adminer installed successfully!\n\n🌐 Access via: $access_url\n📁 Files located at: /var/www/adminer$creds_info\n\n$config_note"
}

remove_adminer() {
    log "Removing Adminer..."
    
    # Remove Apache configuration if exists
    if [[ -f /etc/apache2/sites-enabled/adminer.conf ]]; then
        sudo a2dissite adminer.conf
        sudo systemctl reload apache2 2>/dev/null || true
    fi
    
    # Remove Nginx configuration if exists
    if [[ -f /etc/nginx/sites-enabled/adminer ]]; then
        sudo rm -f /etc/nginx/sites-enabled/adminer
        sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
    fi
    
    # Remove the files
    if sudo rm -rf /var/www/adminer 2>&1 | tee -a "$LOGFILE"; then
        log "Successfully removed Adminer"
        return 0
    else
        log "ERROR: Failed to remove Adminer"
        return 1
    fi
}

remove_phpmyadmin() {
    log "Removing phpMyAdmin..."
    
    # Set debconf to non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    
    # Preseed debconf to handle removal prompts automatically
    log "Preseeding debconf for non-interactive removal..."
    sudo debconf-set-selections << EOF
phpmyadmin phpmyadmin/dbconfig-remove boolean true
phpmyadmin phpmyadmin/purge boolean true
phpmyadmin phpmyadmin/dbconfig-upgrade boolean true
phpmyadmin phpmyadmin/remove-error select ignore
phpmyadmin phpmyadmin/database-removal-error select ignore
phpmyadmin phpmyadmin/mysql/admin-user string root
phpmyadmin phpmyadmin/mysql/admin-pass password 
phpmyadmin phpmyadmin/internal/skip-preseed boolean true
EOF
    
    # Remove Apache configuration if exists
    if [[ -f /etc/apache2/conf-enabled/phpmyadmin.conf ]]; then
        log "Removing Apache phpMyAdmin configuration..."
        sudo a2disconf phpmyadmin 2>/dev/null || true
        sudo systemctl reload apache2 2>/dev/null || true
    fi
    
    # Remove Nginx configuration if exists
    if [[ -f /etc/nginx/sites-enabled/phpmyadmin ]]; then
        log "Removing Nginx phpMyAdmin configuration..."
        sudo rm -f /etc/nginx/sites-enabled/phpmyadmin
        sudo rm -f /etc/nginx/sites-available/phpmyadmin 2>/dev/null || true
        sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
    fi
    
    # Stop any phpMyAdmin related services
    sudo systemctl stop apache2 2>/dev/null || true
    sudo systemctl stop nginx 2>/dev/null || true
    
    # Try to stop MySQL/MariaDB to avoid database connection issues
    log "Temporarily stopping database services to avoid connection errors..."
    sudo systemctl stop mysql 2>/dev/null || true
    sudo systemctl stop mariadb 2>/dev/null || true
    
    # Force remove the package with all configurations
    log "Removing phpMyAdmin package and configurations..."
    
    # First attempt: Standard removal with ignore database errors
    if sudo apt-get remove --purge -y phpmyadmin phpmyadmin-* 2>&1 | tee -a "$LOGFILE"; then
        log "Package removal completed successfully"
    else
        log "Standard removal failed, attempting force cleanup..."
        
        # Second attempt: Force removal bypassing debconf
        sudo DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y --force-yes phpmyadmin phpmyadmin-* 2>/dev/null || true
        
        # Third attempt: Direct dpkg force removal
        sudo dpkg --remove --force-remove-reinstreq phpmyadmin 2>/dev/null || true
        sudo dpkg --purge --force-remove-reinstreq phpmyadmin 2>/dev/null || true
        
        # Fourth attempt: Manual cleanup of all phpMyAdmin files
        log "Performing manual cleanup of phpMyAdmin files..."
        sudo rm -rf /etc/phpmyadmin 2>/dev/null || true
        sudo rm -rf /usr/share/phpmyadmin 2>/dev/null || true
        sudo rm -rf /var/lib/phpmyadmin 2>/dev/null || true
        sudo rm -rf /etc/apache2/conf-available/phpmyadmin.conf 2>/dev/null || true
        sudo rm -rf /etc/apache2/conf-enabled/phpmyadmin.conf 2>/dev/null || true
        
        # Remove from dpkg status if still listed
        sudo dpkg --force-all --purge phpmyadmin 2>/dev/null || true
    fi
    
    # Clean up debconf database entries
    log "Cleaning up debconf entries..."
    sudo debconf-communicate << EOF || true
PURGE phpmyadmin
EOF
    
    # Additional debconf cleanup
    sudo debconf-show phpmyadmin 2>/dev/null | while read line; do
        key=$(echo "$line" | cut -d: -f1 | tr -d ' ')
        sudo debconf-set-selections <<< "$key PURGE" 2>/dev/null || true
    done
    
    # Remove any remaining configuration files
    sudo rm -rf /etc/phpmyadmin 2>/dev/null || true
    sudo rm -rf /usr/share/phpmyadmin 2>/dev/null || true
    sudo rm -rf /var/lib/phpmyadmin 2>/dev/null || true
    
    # Clean up package cache
    sudo apt-get autoremove -y 2>/dev/null || true
    sudo apt-get autoclean 2>/dev/null || true
    
    # Restart database services
    log "Restarting database services..."
    if systemctl is-enabled mysql 2>/dev/null; then
        sudo systemctl start mysql 2>/dev/null || true
    fi
    if systemctl is-enabled mariadb 2>/dev/null; then
        sudo systemctl start mariadb 2>/dev/null || true
    fi
    
    # Restart web servers
    if systemctl is-enabled apache2 2>/dev/null; then
        sudo systemctl start apache2 2>/dev/null || true
    fi
    if systemctl is-enabled nginx 2>/dev/null; then
        sudo systemctl start nginx 2>/dev/null || true
    fi
    
    # Reset DEBIAN_FRONTEND
    unset DEBIAN_FRONTEND
    
    log "phpMyAdmin removal completed successfully"
    return 0
}

install_bruno() {
    log "Installing Bruno API client..."
    
    # Neutralize duplicate sources/keys that may conflict
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'debian\.usebruno\.com' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Bruno source list: $f"
        fi
    done
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ bruno|usebruno ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done

    # Create keyrings directory
    sudo mkdir -p /etc/apt/keyrings
    
    # Update and install GPG and curl
    sudo apt update && sudo apt install -y gpg curl
    
    # Add the Bruno repository key
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x9FA6017ECABE0266" | gpg --dearmor | sudo tee /etc/apt/keyrings/bruno.gpg > /dev/null
    
    # Add the Bruno repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/bruno.gpg] http://debian.usebruno.com/ bruno stable" | sudo tee /etc/apt/sources.list.d/bruno.list
    
    # Update and install Bruno
    if sudo apt update && sudo apt install -y bruno; then
        ui_msg "Bruno Installed" "Bruno API client installed successfully via APT repository."
        return 0
    else
        log_error "Failed to install Bruno via APT"
        return 1
    fi
}

remove_bruno() {
    log "Removing Bruno..."
    
    # Remove the package
    sudo apt remove --purge -y bruno
    
    # Remove repository and key
    sudo rm -f /etc/apt/sources.list.d/bruno.list
    sudo rm -f /etc/apt/keyrings/bruno.gpg
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ bruno|usebruno ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
    
    # Update package list
    sudo apt update
    
    log "Bruno removed successfully"
    return 0
}

install_yaak() {
    log "Installing Yaak API client..."
    
    local yaak_url="https://github.com/mountain-loop/yaak/releases/download/v2025.7.3/yaak_2025.7.3_amd64.deb"
    local temp_file="/tmp/yaak.deb"
    
    # Download the .deb file
    if wget -O "$temp_file" "$yaak_url" 2>/dev/null; then
        # Install the .deb package
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "Yaak Installed" "Yaak API client installed successfully from GitHub release."
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to install Yaak .deb package"
            return 1
        fi
    else
        log_error "Failed to download Yaak from $yaak_url"
        return 1
    fi
}

remove_yaak() {
    log "Removing Yaak..."
    
    # Remove the package
    sudo apt remove --purge -y yaak
    
    log "Yaak removed successfully"
    return 0
}

install_caddy() {
    log "Installing Caddy web server..."
    
    # Neutralize duplicate sources/keys
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'dl\.cloudsmith\.io/public/caddy/stable' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting Caddy source list: $f"
        fi
    done
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ caddy|cloudsmith ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done

    # Install dependencies
    sudo apt update
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
    
    # Add Caddy repository key
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    
    # Add Caddy repository
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    
    # Update and install Caddy
    sudo apt update
    install_apt_package "caddy"
    
    ui_msg "Caddy Installed" "Caddy web server installed successfully."
}

remove_caddy() {
    remove_apt_package "caddy"
    sudo rm -f /etc/apt/sources.list.d/caddy-stable.list
    sudo rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    for k in /etc/apt/trusted.gpg.d/*.gpg; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ caddy|cloudsmith ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
}

install_ngrok() {
    log "Installing ngrok..."
    
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    # Neutralize duplicate sources/keys that may conflict
    for f in /etc/apt/sources.list.d/*.list; do
        if [[ -f "$f" ]] && grep -qE 'ngrok-agent\.s3\.amazonaws\.com' "$f"; then
            sudo rm -f "$f"
            log "Removed conflicting ngrok source list: $f"
        fi
    done
    for k in /etc/apt/trusted.gpg.d/*; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ ngrok ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done

    # Add canonical keyring and repository with signed-by
    sudo mkdir -p /usr/share/keyrings
    curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo gpg --dearmor -o /usr/share/keyrings/ngrok-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/ngrok-archive-keyring.gpg] https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    
    apt_update
    install_apt_package "ngrok"
    
    ui_msg "ngrok Installed" "ngrok installed successfully. Run 'ngrok config add-authtoken <token>' to authenticate."
}

remove_ngrok() {
    remove_apt_package "ngrok"
    sudo rm -f /etc/apt/sources.list.d/ngrok.list
    sudo rm -f /usr/share/keyrings/ngrok-archive-keyring.gpg
    for k in /etc/apt/trusted.gpg.d/*; do
        if [[ -f "$k" ]] && [[ "$(basename "$k")" =~ ngrok ]]; then
            sudo rm -f "$k"
            log "Removed vendor key: $k"
        fi
    done
}

install_mailhog() {
    log "Installing MailHog..."
    
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    # Download MailHog binary
    curl -Lo mailhog "https://github.com/mailhog/MailHog/releases/latest/download/MailHog_linux_${arch}"
    chmod +x mailhog
    sudo mv mailhog /usr/local/bin/mailhog
    
    # Create systemd service
    sudo tee /etc/systemd/system/mailhog.service > /dev/null << EOF
[Unit]
Description=MailHog Email Testing Tool
After=network.target

[Service]
Type=simple
User=mailhog
Group=mailhog
ExecStart=/usr/local/bin/mailhog
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Create mailhog user
    sudo useradd -r -s /bin/false mailhog 2>/dev/null || true
    
    # Enable and start service
    sudo systemctl daemon-reload
    sudo systemctl enable mailhog
    sudo systemctl start mailhog
    
    ui_msg "MailHog Installed" "MailHog installed successfully. Web UI available at http://localhost:8025"
}

remove_mailhog() {
    sudo systemctl stop mailhog 2>/dev/null || true
    sudo systemctl disable mailhog 2>/dev/null || true
    sudo rm -f /etc/systemd/system/mailhog.service
    sudo rm -f /usr/local/bin/mailhog
    sudo userdel mailhog 2>/dev/null || true
    sudo systemctl daemon-reload
}

remove_rustup() {
    log "Removing Rustup..."
    
    # Remove rustup and all Rust toolchains
    if command -v rustup >/dev/null 2>&1; then
        rustup self uninstall -y 2>/dev/null || true
    fi
    
    # Remove any remaining Rust directories
    rm -rf "$HOME/.rustup" "$HOME/.cargo" 2>/dev/null || true
    
    log "Rustup removed successfully"
    return 0
}

# AI Image Generation Tools
install_automatic1111() {
    log "Installing Automatic1111 Stable Diffusion WebUI..."
    ui_msg "Python/Pip Disabled" "Automatic1111 requires Python/pip which are disabled by policy. Please use a non-Python alternative."
    return 1
    
    local install_dir="$HOME/automatic1111"
    
    # Install dependencies
    sudo apt update && sudo apt install -y python3 python3-pip python3-venv git wget
    
    # Clone repository
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$install_dir"
    cd "$install_dir"
    
    # Make webui script executable
    chmod +x webui.sh
    
    # Create desktop entry
    cat > ~/.local/share/applications/automatic1111.desktop << EOF
[Desktop Entry]
Name=Automatic1111 WebUI
Comment=Stable Diffusion Web Interface
Exec=bash -c 'cd $install_dir && ./webui.sh'
Icon=applications-graphics
Terminal=true
Type=Application
Categories=Graphics;Photography;
EOF
    
    ui_msg "Automatic1111 Installed" "Automatic1111 WebUI installed to $install_dir. Run ./webui.sh to start."
}

remove_automatic1111() {
    rm -rf "$HOME/automatic1111"
    rm -f ~/.local/share/applications/automatic1111.desktop
}

install_fooocus() {
    log "Installing Fooocus Stable Diffusion frontend..."
    ui_msg "Python/Pip Disabled" "Fooocus requires Python/pip which are disabled by policy. Please use a non-Python alternative."
    return 1
    
    local install_dir="$HOME/fooocus"
    
    # Install dependencies
    sudo apt update && sudo apt install -y python3 python3-pip python3-venv git
    
    # Clone repository
    git clone https://github.com/lllyasviel/Fooocus.git "$install_dir"
    cd "$install_dir"
    
    # Create virtual environment and install requirements
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements_versions.txt
    
    # Create desktop entry
    cat > ~/.local/share/applications/fooocus.desktop << EOF
[Desktop Entry]
Name=Fooocus
Comment=Simplified Stable Diffusion Frontend
Exec=bash -c 'cd $install_dir && source venv/bin/activate && python entry_with_update.py'
Icon=applications-graphics
Terminal=true
Type=Application
Categories=Graphics;Photography;
EOF
    
    ui_msg "Fooocus Installed" "Fooocus installed to $install_dir. Run entry_with_update.py to start."
}

remove_fooocus() {
    rm -rf "$HOME/fooocus"
    rm -f ~/.local/share/applications/fooocus.desktop
}

install_sd-next() {
    log "Installing SD.Next (Stable Diffusion Next)..."
    ui_msg "Python/Pip Disabled" "SD.Next requires Python/pip which are disabled by policy. Please use a non-Python alternative."
    return 1
    
    local install_dir="$HOME/sd-next"
    
    # Install dependencies
    sudo apt update && sudo apt install -y python3 python3-pip python3-venv git
    
    # Clone repository
    git clone https://github.com/vladmandic/automatic.git "$install_dir"
    cd "$install_dir"
    
    # Make launch script executable
    chmod +x launch.py
    
    # Create desktop entry
    cat > ~/.local/share/applications/sd-next.desktop << EOF
[Desktop Entry]
Name=SD.Next
Comment=Modernized Stable Diffusion WebUI
Exec=bash -c 'cd $install_dir && python3 launch.py'
Icon=applications-graphics
Terminal=true
Type=Application
Categories=Graphics;Photography;
EOF
    
    ui_msg "SD.Next Installed" "SD.Next installed to $install_dir. Run launch.py to start."
}

remove_sd-next() {
    rm -rf "$HOME/sd-next"
    rm -f ~/.local/share/applications/sd-next.desktop
}

install_kohya-ss-gui() {
    log "Installing Kohya-ss GUI for model training..."
    ui_msg "Python/Pip Disabled" "Kohya-ss GUI requires Python/pip which are disabled by policy. Please use a non-Python alternative."
    return 1
    
    local install_dir="$HOME/kohya-ss"
    
    # Install dependencies
    sudo apt update && sudo apt install -y python3 python3-pip python3-venv git build-essential
    
    # Clone repository
    git clone https://github.com/bmaltais/kohya_ss.git "$install_dir"
    cd "$install_dir"
    
    # Make setup script executable
    chmod +x setup.sh
    
    # Create desktop entry
    cat > ~/.local/share/applications/kohya-ss.desktop << EOF
[Desktop Entry]
Name=Kohya-ss GUI
Comment=Model Training GUI
Exec=bash -c 'cd $install_dir && ./gui.sh'
Icon=applications-science
Terminal=true
Type=Application
Categories=Science;Education;
EOF
    
    ui_msg "Kohya-ss GUI Installed" "Kohya-ss GUI installed to $install_dir. Run setup.sh first, then gui.sh."
}

remove_kohya-ss-gui() {
    rm -rf "$HOME/kohya-ss"
    rm -f ~/.local/share/applications/kohya-ss.desktop
}



# Shell Enhancement Tools
install_oh-my-zsh() {
    log "Installing Oh My Zsh..."
    
    # Check if zsh is installed
    if ! command -v zsh >/dev/null 2>&1; then
        log_error "Zsh is required for Oh My Zsh. Install zsh first."
        return 1
    fi
    
    # Check if Oh My Zsh is already installed
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ui_msg "Already Installed" "Oh My Zsh is already installed."
        return 0
    fi
    
    # Install Oh My Zsh
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    ui_msg "Oh My Zsh Installed" "Oh My Zsh installed successfully. Restart your terminal or run 'zsh' to use it."
}

remove_oh-my-zsh() {
    log "Removing Oh My Zsh..."
    
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        # Run the uninstall script if it exists
        if [[ -f "$HOME/.oh-my-zsh/tools/uninstall.sh" ]]; then
            sh "$HOME/.oh-my-zsh/tools/uninstall.sh" --unattended 2>/dev/null || true
        fi
        
        # Remove directory if still exists
        rm -rf "$HOME/.oh-my-zsh"
        
        # Restore original shell config if backup exists
        [[ -f "$HOME/.zshrc.pre-oh-my-zsh" ]] && mv "$HOME/.zshrc.pre-oh-my-zsh" "$HOME/.zshrc"
    fi
    
    log "Oh My Zsh removed successfully"
}

install_starship() {
    log "Installing Starship prompt..."
    
    # Download and install Starship
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    
    # Add to shell configs if not already present
    local starship_init='eval "$(starship init zsh)"'
    
    # Add to .zshrc if it exists and doesn't already contain starship
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "starship init" "$HOME/.zshrc"; then
        echo "" >> "$HOME/.zshrc"
        echo "# Starship prompt" >> "$HOME/.zshrc"
        echo "$starship_init" >> "$HOME/.zshrc"
    fi
    
    # Add to .bashrc if it exists and doesn't already contain starship
    if [[ -f "$HOME/.bashrc" ]] && ! grep -q "starship init" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "# Starship prompt" >> "$HOME/.bashrc"
        echo 'eval "$(starship init bash)"' >> "$HOME/.bashrc"
    fi
    
    ui_msg "Starship Installed" "Starship prompt installed successfully. Restart your terminal to see changes."
}

remove_starship() {
    log "Removing Starship..."
    
    # Remove binary
    sudo rm -f /usr/local/bin/starship
    rm -f "$HOME/.cargo/bin/starship"
    
    # Remove from shell configs
    if [[ -f "$HOME/.zshrc" ]]; then
        sed -i '/starship init/d' "$HOME/.zshrc" 2>/dev/null || true
        sed -i '/# Starship prompt/d' "$HOME/.zshrc" 2>/dev/null || true
    fi
    
    if [[ -f "$HOME/.bashrc" ]]; then
        sed -i '/starship init/d' "$HOME/.bashrc" 2>/dev/null || true
        sed -i '/# Starship prompt/d' "$HOME/.bashrc" 2>/dev/null || true
    fi
    
    # Remove config directory
    rm -rf "$HOME/.config/starship.toml"
    
    log "Starship removed successfully"
}

install_zoxide() {
    log "Installing Zoxide..."
    
    # Download and install Zoxide
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    
    # Add to shell configs if not already present
    local zoxide_init_zsh='eval "$(zoxide init zsh)"'
    local zoxide_init_bash='eval "$(zoxide init bash)"'
    
    # Add to .zshrc if it exists and doesn't already contain zoxide
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "zoxide init" "$HOME/.zshrc"; then
        echo "" >> "$HOME/.zshrc"
        echo "# Zoxide - smarter cd" >> "$HOME/.zshrc"
        echo "$zoxide_init_zsh" >> "$HOME/.zshrc"
    fi
    
    # Add to .bashrc if it exists and doesn't already contain zoxide
    if [[ -f "$HOME/.bashrc" ]] && ! grep -q "zoxide init" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "# Zoxide - smarter cd" >> "$HOME/.bashrc"
        echo "$zoxide_init_bash" >> "$HOME/.bashrc"
    fi
    
    ui_msg "Zoxide Installed" "Zoxide installed successfully. Use 'z' instead of 'cd'. Restart terminal to activate."
}

remove_zoxide() {
    log "Removing Zoxide..."
    
    # Remove binary
    rm -f "$HOME/.local/bin/zoxide"
    
    # Remove from shell configs
    if [[ -f "$HOME/.zshrc" ]]; then
        sed -i '/zoxide init/d' "$HOME/.zshrc" 2>/dev/null || true
        sed -i '/# Zoxide - smarter cd/d' "$HOME/.zshrc" 2>/dev/null || true
    fi
    
    if [[ -f "$HOME/.bashrc" ]]; then
        sed -i '/zoxide init/d' "$HOME/.bashrc" 2>/dev/null || true
        sed -i '/# Zoxide - smarter cd/d' "$HOME/.bashrc" 2>/dev/null || true
    fi
    
    # Remove data directory
    rm -rf "$HOME/.local/share/zoxide"
    
    log "Zoxide removed successfully"
}

install_poetry() {
    log "Installing Poetry via apt..."
    if sudo apt-get update && sudo apt-get install -y python3-poetry; then
        ui_msg "Poetry Installed" "Poetry installed successfully via apt."
        return 0
    else
        log_error "Failed to install Poetry via apt"
        return 1
    fi
}

remove_poetry() {
    log "Removing Poetry via apt..."
    if sudo apt-get remove -y python3-poetry; then
        log "Poetry removed successfully via apt"
        return 0
    else
        log_error "Failed to remove Poetry via apt"
        return 1
    fi
}

install_deno() {
    log "Installing Deno JS/TS runtime..."
    
    local deno_url="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip"
    local temp_dir="/tmp/deno_install"
    local temp_file="$temp_dir/deno.zip"
    
    mkdir -p "$temp_dir"
    
    # Download and install Deno
    if wget -O "$temp_file" "$deno_url" 2>/dev/null; then
        cd "$temp_dir"
        unzip -q deno.zip
        sudo mv deno /usr/local/bin/
        sudo chmod +x /usr/local/bin/deno
        rm -rf "$temp_dir"
        ui_msg "Deno Installed" "Deno JS/TS runtime installed successfully."
        return 0
    else
        rm -rf "$temp_dir"
        log_error "Failed to download Deno"
        return 1
    fi
}

remove_deno() {
    log "Removing Deno..."
    sudo rm -f /usr/local/bin/deno
    log "Deno removed successfully"
    return 0
}

install_bun() {
    log "Installing Bun JS runtime..."
    
    # Install via official installer
    if curl -fsSL https://bun.sh/install | bash; then
        # Add to PATH if not already there
        if ! echo "$PATH" | grep -q "$HOME/.bun/bin"; then
            echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
            echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
        fi
        ui_msg "Bun Installed" "Bun JS runtime installed successfully."
        return 0
    else
        log_error "Failed to install Bun"
        return 1
    fi
}

remove_bun() {
    log "Removing Bun..."
    rm -rf "$HOME/.bun" 2>/dev/null || true
    log "Bun removed successfully"
    return 0
}

install_mkdocs() {
    log "Installing MkDocs via apt..."
    if sudo apt-get update && sudo apt-get install -y mkdocs; then
        ui_msg "MkDocs Installed" "MkDocs installed successfully via apt."
        return 0
    else
        log_error "Failed to install MkDocs via apt"
        return 1
    fi
}

remove_mkdocs() {
    log "Removing MkDocs via apt..."
    if sudo apt-get remove -y mkdocs; then
        log "MkDocs removed successfully via apt"
        return 0
    else
        log_error "Failed to remove MkDocs via apt"
        return 1
    fi
}

install_insomnia() {
    log "Installing Insomnia API client..."
    
    local insomnia_url="https://github.com/Kong/insomnia/releases/latest/download/Insomnia.Core-8.6.1.deb"
    local temp_file="/tmp/insomnia.deb"
    
    # Download the .deb file
    if wget -O "$temp_file" "$insomnia_url" 2>/dev/null; then
        # Install the .deb package
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "Insomnia Installed" "Insomnia API client installed successfully."
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to install Insomnia .deb package"
            return 1
        fi
    else
        log_error "Failed to download Insomnia"
        return 1
    fi
}

remove_insomnia() {
    log "Removing Insomnia..."
    sudo apt remove --purge -y insomnia 2>/dev/null || true
    log "Insomnia removed successfully"
    return 0
}

install_zed() {
    log "Installing Zed code editor..."
    
    local zed_url="https://zed.dev/api/releases/stable/latest/zed-linux-x86_64.tar.gz"
    local temp_dir="/tmp/zed_install"
    local temp_file="$temp_dir/zed.tar.gz"
    
    mkdir -p "$temp_dir"
    
    # Download and install Zed
    if wget -O "$temp_file" "$zed_url" 2>/dev/null; then
        cd "$temp_dir"
        tar -xzf zed.tar.gz
        sudo mv zed-linux-x86_64/zed /usr/local/bin/
        sudo chmod +x /usr/local/bin/zed
        rm -rf "$temp_dir"
        ui_msg "Zed Installed" "Zed code editor installed successfully."
        return 0
    else
        rm -rf "$temp_dir"
        log_error "Failed to download Zed"
        return 1
    fi
}

remove_zed() {
    log "Removing Zed..."
    sudo rm -f /usr/local/bin/zed
    log "Zed removed successfully"
    return 0
}

install_localwp() {
    log "Installing LocalWP..."
    
    local localwp_url="https://cdn.localwp.com/releases-stable/6.7.0+6387/local-6.7.0-linux.deb"
    local temp_file="/tmp/localwp.deb"
    
    # Download the .deb file
    if wget -O "$temp_file" "$localwp_url" 2>/dev/null; then
        # Install the .deb package
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "LocalWP Installed" "LocalWP WordPress development environment installed successfully."
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to install LocalWP .deb package"
            return 1
        fi
    else
        log_error "Failed to download LocalWP"
        return 1
    fi
}

remove_localwp() {
    log "Removing LocalWP..."
    sudo apt remove --purge -y local 2>/dev/null || true
    log "LocalWP removed successfully"
    return 0
}

install_devkinsta() {
    log "Installing DevKinsta..."
    
    local devkinsta_url="https://kinsta.com/devkinsta/download/devkinsta.deb"
    local temp_file="/tmp/devkinsta.deb"
    
    # Download the .deb file
    if wget -O "$temp_file" "$devkinsta_url" 2>/dev/null; then
        # Install the .deb package
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "DevKinsta Installed" "DevKinsta WordPress development environment installed successfully."
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to install DevKinsta .deb package"
            return 1
        fi
    else
        log_error "Failed to download DevKinsta"
        return 1
    fi
}

remove_devkinsta() {
    log "Removing DevKinsta..."
    sudo apt remove --purge -y devkinsta 2>/dev/null || true
    log "DevKinsta removed successfully"
    return 0
}

install_lando() {
    log "Installing Lando..."
    
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="x64" ;;
        arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    local lando_url="https://github.com/lando/lando/releases/latest/download/lando-linux-${arch}-stable.deb"
    local temp_file="/tmp/lando.deb"
    
    # Download the .deb file
    if wget -O "$temp_file" "$lando_url" 2>/dev/null; then
        # Install the .deb package
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "Lando Installed" "Lando containerized development environment installed successfully."
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to install Lando .deb package"
            return 1
        fi
    else
        log_error "Failed to download Lando"
        return 1
    fi
}

remove_lando() {
    log "Removing Lando..."
    sudo apt remove --purge -y lando 2>/dev/null || true
    log "Lando removed successfully"
    return 0
}

install_ddev() {
    log "Installing DDEV..."
    
    # Install via official installer script
    if curl -fsSL https://raw.githubusercontent.com/drud/ddev/master/scripts/install_ddev.sh | bash; then
        ui_msg "DDEV Installed" "DDEV containerized development environment installed successfully."
        return 0
    else
        log_error "Failed to install DDEV"
        return 1
    fi
}

remove_ddev() {
    log "Removing DDEV..."
    sudo rm -f /usr/local/bin/ddev
    rm -rf ~/.ddev 2>/dev/null || true
    log "DDEV removed successfully"
    return 0
}

install_xampp() {
    log "Installing XAMPP..."
    
    local xampp_url="https://www.apachefriends.org/xampp-files/8.2.12/xampp-linux-x64-8.2.12-0-installer.run"
    local temp_file="/tmp/xampp-installer.run"
    
    # Download the installer
    if wget -O "$temp_file" "$xampp_url" 2>/dev/null; then
        chmod +x "$temp_file"
        # Run installer in unattended mode
        if sudo "$temp_file" --mode unattended; then
            rm -f "$temp_file"
            ui_msg "XAMPP Installed" "XAMPP development stack installed successfully to /opt/lampp."
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to install XAMPP"
            return 1
        fi
    else
        log_error "Failed to download XAMPP"
        return 1
    fi
}

remove_xampp() {
    log "Removing XAMPP..."
    sudo rm -rf /opt/lampp 2>/dev/null || true
    log "XAMPP removed successfully"
    return 0
}

# ==============================================================================
# ADDITIONAL CLI TOOLS INSTALLATION FUNCTIONS
# ==============================================================================

install_lazygit() {
    log "Installing lazygit..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep "browser_download_url.*Linux_${arch}.tar.gz" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get lazygit download URL"
        return 1
    fi
    
    local temp_file="/tmp/lazygit.tar.gz"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        tar -xzf "$temp_file" -C /tmp/
        sudo mv /tmp/lazygit /usr/local/bin/
        sudo chmod +x /usr/local/bin/lazygit
        rm -f "$temp_file"
        log "lazygit installed successfully"
        return 0
    else
        log_error "Failed to download lazygit"
        return 1
    fi
}

install_glow() {
    log "Installing glow..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/charmbracelet/glow/releases/latest | grep "browser_download_url.*linux_${arch}.tar.gz" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get glow download URL"
        return 1
    fi
    
    local temp_file="/tmp/glow.tar.gz"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        tar -xzf "$temp_file" -C /tmp/
        sudo mv /tmp/glow /usr/local/bin/
        sudo chmod +x /usr/local/bin/glow
        rm -f "$temp_file"
        log "glow installed successfully"
        return 0
    else
        log_error "Failed to download glow"
        return 1
    fi
}

install_cheat() {
    log "Installing cheat..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/cheat/cheat/releases/latest | grep "browser_download_url.*linux-${arch}.gz" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get cheat download URL"
        return 1
    fi
    
    local temp_file="/tmp/cheat.gz"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        gunzip "$temp_file"
        sudo mv /tmp/cheat /usr/local/bin/
        sudo chmod +x /usr/local/bin/cheat
        log "cheat installed successfully"
        return 0
    else
        log_error "Failed to download cheat"
        return 1
    fi
}

install_broot() {
    log "Installing broot..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="x86_64-linux" ;;
        aarch64|arm64) arch="aarch64-linux" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/Canop/broot/releases/latest | grep "browser_download_url.*${arch}" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get broot download URL"
        return 1
    fi
    
    local temp_file="/tmp/broot"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        sudo mv "$temp_file" /usr/local/bin/broot
        sudo chmod +x /usr/local/bin/broot
        log "broot installed successfully"
        return 0
    else
        log_error "Failed to download broot"
        return 1
    fi
}

install_dog() {
    log "Installing dog..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/ogham/dog/releases/latest | grep "browser_download_url.*${arch}-unknown-linux-gnu.zip" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get dog download URL"
        return 1
    fi
    
    local temp_file="/tmp/dog.zip"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        unzip -q "$temp_file" -d /tmp/
        sudo mv /tmp/bin/dog /usr/local/bin/
        sudo chmod +x /usr/local/bin/dog
        rm -f "$temp_file"
        rm -rf /tmp/bin
        log "dog installed successfully"
        return 0
    else
        log_error "Failed to download dog"
        return 1
    fi
}

# ==============================================================================
# SBC/MICROCONTROLLER CUSTOM INSTALLERS
# ==============================================================================

install_balena-etcher() {
    log "Installing balenaEtcher..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/balena-io/etcher/releases/latest | grep "browser_download_url.*${arch}.deb" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get balenaEtcher download URL"
        return 1
    fi
    
    local temp_file="/tmp/balena-etcher.deb"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        sudo dpkg -i "$temp_file" || sudo apt-get install -f -y
        rm -f "$temp_file"
        log "balenaEtcher installed successfully"
        return 0
    else
        log_error "Failed to download balenaEtcher"
        return 1
    fi
}

remove_balena-etcher() {
    remove_apt_package "balena-etcher-electron"
}

install_arduino-ide() {
    log "Installing Arduino IDE 2.0..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="Linux_64bit" ;;
        aarch64|arm64) arch="Linux_ARM64" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/arduino/arduino-ide/releases/latest | grep "browser_download_url.*${arch}.zip" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get Arduino IDE download URL"
        return 1
    fi
    
    local temp_file="/tmp/arduino-ide.zip"
    local install_dir="/opt/arduino-ide"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        sudo rm -rf "$install_dir"
        sudo mkdir -p "$install_dir"
        sudo unzip -q "$temp_file" -d "$install_dir" --strip-components=1
        sudo chmod +x "$install_dir/arduino-ide"
        
        # Create desktop entry
        sudo tee /usr/share/applications/arduino-ide.desktop > /dev/null <<EOF
[Desktop Entry]
Name=Arduino IDE
Comment=Arduino IDE 2.0
Exec=$install_dir/arduino-ide
Icon=$install_dir/resources/app/resources/icons/512x512.png
Terminal=false
Type=Application
Categories=Development;Electronics;
EOF
        
        # Create symlink
        sudo ln -sf "$install_dir/arduino-ide" /usr/local/bin/arduino-ide
        
        rm -f "$temp_file"
        log "Arduino IDE installed successfully"
        return 0
    else
        log_error "Failed to download Arduino IDE"
        return 1
    fi
}

remove_arduino-ide() {
    sudo rm -rf /opt/arduino-ide
    sudo rm -f /usr/share/applications/arduino-ide.desktop
    sudo rm -f /usr/local/bin/arduino-ide
}

install_arduino-cli() {
    log "Installing Arduino CLI..."
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="Linux_64bit" ;;
        aarch64|arm64) arch="Linux_ARM64" ;;
        armv7l) arch="Linux_ARMv7" ;;
        *) log_error "Unsupported architecture"; return 1 ;;
    esac
    
    local latest_url=$(curl -s https://api.github.com/repos/arduino/arduino-cli/releases/latest | grep "browser_download_url.*${arch}.tar.gz" | cut -d '"' -f 4)
    
    if [[ -z "$latest_url" ]]; then
        log_error "Failed to get Arduino CLI download URL"
        return 1
    fi
    
    local temp_file="/tmp/arduino-cli.tar.gz"
    
    if wget -O "$temp_file" "$latest_url" 2>/dev/null; then
        tar -xzf "$temp_file" -C /tmp/
        sudo mv /tmp/arduino-cli /usr/local/bin/
        sudo chmod +x /usr/local/bin/arduino-cli
        rm -f "$temp_file"
        log "Arduino CLI installed successfully"
        return 0
    else
        log_error "Failed to download Arduino CLI"
        return 1
    fi
}

remove_arduino-cli() {
    sudo rm -f /usr/local/bin/arduino-cli
}

install_esp-idf() {
    log "Installing ESP-IDF..."
    
    local idf_path="$HOME/esp/esp-idf"
    
    # Install prerequisites
    install_apt_package "git"
    install_apt_package "wget"
    install_apt_package "flex"
    install_apt_package "bison"
    install_apt_package "gperf"
    install_apt_package "python3"
    install_apt_package "python3-pip"
    install_apt_package "python3-venv"
    install_apt_package "cmake"
    install_apt_package "ninja-build"
    install_apt_package "ccache"
    install_apt_package "libffi-dev"
    install_apt_package "libssl-dev"
    install_apt_package "dfu-util"
    install_apt_package "libusb-1.0-0"
    
    # Clone ESP-IDF
    mkdir -p "$HOME/esp"
    if [[ -d "$idf_path" ]]; then
        cd "$idf_path"
        git pull
    else
        git clone --recursive https://github.com/espressif/esp-idf.git "$idf_path"
    fi
    
    cd "$idf_path"
    ./install.sh esp32
    
    # Add to shell profile
    local shell_rc="$HOME/.bashrc"
    [[ "$SHELL" == *"zsh"* ]] && shell_rc="$HOME/.zshrc"
    
    if ! grep -q "esp-idf/export.sh" "$shell_rc" 2>/dev/null; then
        echo "# ESP-IDF" >> "$shell_rc"
        echo "alias get_idf='. $idf_path/export.sh'" >> "$shell_rc"
    fi
    
    ui_msg "ESP-IDF Installed" "ESP-IDF installed successfully. Run 'get_idf' to set up the environment, or restart your terminal."
}

remove_esp-idf() {
    if ui_yesno "Remove ESP-IDF?" "This will remove ESP-IDF installation. Continue?"; then
        rm -rf "$HOME/esp/esp-idf"
        
        # Remove from shell profile
        local shell_rc="$HOME/.bashrc"
        [[ "$SHELL" == *"zsh"* ]] && shell_rc="$HOME/.zshrc"
        
        if [[ -f "$shell_rc" ]]; then
            sed -i '/# ESP-IDF/d' "$shell_rc"
            sed -i '/get_idf=/d' "$shell_rc"
        fi
        
        log "ESP-IDF removed"
    fi
}

# ==============================================================================
# BUNTAGE MANAGEMENT DISPATCHER
# ==============================================================================

install_package() {
    local name="$1"
    local pkg="${PACKAGES[$name]}"
    local method="${PKG_METHOD[$name]}"
    
    # Check dependencies
    if [[ -n "${PKG_DEPS[$name]:-}" ]]; then
        local dep="${PKG_DEPS[$name]}"
        if ! is_package_installed "$dep"; then
            ui_msg "Dependency Required" "$name requires $dep. Install $dep first."
            return 1
        fi
    fi
    
    local install_result=0
    
    case "$method" in
        apt)
            apt_update
            install_apt_package "$pkg"
            install_result=$?
            ;;
        snap)
            ensure_snapd_ready || {
                ui_msg "snapd Not Ready" "snapd could not be prepared. Check logs at $LOGFILE."
                install_result=1
            }
            install_snap_package "$pkg"
            install_result=$?
            ;;
        npm)
            install_npm_package "$pkg"
            install_result=$?
            ;;
        pip)
            ui_msg "Pip Install Disabled" "Installing $name via pip is disabled. Please use APT, SNAP, FLATPAK, or a supported method."
            install_result=1
            ;;
        cargo)
            install_cargo_package "$pkg"
            install_result=$?
            ;;
        flatpak)
            if ! is_apt_installed "flatpak"; then
                ui_msg "Flatpak Required" "Installing Flatpak first...\n\n⏳ This process is automatic - please wait..."
                apt_update
                install_apt_package "flatpak"
                flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            fi
            install_flatpak_package "$pkg"
            install_result=$?
            ;;
        custom)
            case "$name" in
                docker) install_docker; install_result=$? ;;
                nodejs) install_nodejs; install_result=$? ;;
                vscode) install_vscode; install_result=$? ;;
                brave) install_brave; install_result=$? ;;
                sublime-text) install_sublime; install_result=$? ;;
                warp-terminal) install_warp; install_result=$? ;;
                ollama) install_ollama; install_result=$? ;;
                yt-dlp) install_yt-dlp; install_result=$? ;;
                invidious) install_invidious; install_result=$? ;;
                n8n) install_n8n; install_result=$? ;;
                gollama) install_gollama; install_result=$? ;;
                discord-deb) install_discord-deb; install_result=$? ;;
                phpmyadmin) install_phpmyadmin; install_result=$? ;;
                adminer) install_adminer; install_result=$? ;;
                bruno) install_bruno; install_result=$? ;;
                yaak) install_yaak; install_result=$? ;;
                rustup) install_rustup; install_result=$? ;;
                poetry) install_poetry; install_result=$? ;;
                deno) install_deno; install_result=$? ;;
                bun) install_bun; install_result=$? ;;
                mkdocs) install_mkdocs; install_result=$? ;;
                insomnia) install_insomnia; install_result=$? ;;
                zed) install_zed; install_result=$? ;;
                localwp) install_localwp; install_result=$? ;;
                devkinsta) install_devkinsta; install_result=$? ;;
                lando) install_lando; install_result=$? ;;
                ddev) install_ddev; install_result=$? ;;
                xampp) install_xampp; install_result=$? ;;
                lm-studio) install_lm-studio; install_result=$? ;;
                text-generation-webui) install_text-generation-webui; install_result=$? ;;
                whisper-cpp) install_whisper-cpp; install_result=$? ;;
                comfyui) install_comfyui; install_result=$? ;;
                invokeai) install_invokeai; install_result=$? ;;
                koboldcpp) install_koboldcpp; install_result=$? ;;
                minikube) install_minikube; install_result=$? ;;
                kind) install_kind; install_result=$? ;;
                ctop) install_ctop; install_result=$? ;;
                lazydocker) install_lazydocker; install_result=$? ;;
                caddy) install_caddy; install_result=$? ;;
                ngrok) install_ngrok; install_result=$? ;;
                mailhog) install_mailhog; install_result=$? ;;
                automatic1111) install_automatic1111; install_result=$? ;;
                fooocus) install_fooocus; install_result=$? ;;
                sd-next) install_sd-next; install_result=$? ;;
                kohya-ss-gui) install_kohya-ss-gui; install_result=$? ;;
                oh-my-zsh) install_oh-my-zsh; install_result=$? ;;
                starship) install_starship; install_result=$? ;;
                zoxide) install_zoxide; install_result=$? ;;
                seafile) install_seafile; install_result=$? ;;
                snapraid) install_snapraid; install_result=$? ;;
                greyhole) install_greyhole; install_result=$? ;;
                mergerfs) install_mergerfs; install_result=$? ;;
                plex) install_plex; install_result=$? ;;
                ums) install_ums; install_result=$? ;;
                lazygit) install_lazygit; install_result=$? ;;
                glow) install_glow; install_result=$? ;;
                cheat) install_cheat; install_result=$? ;;
                broot) install_broot; install_result=$? ;;
                dog) install_dog; install_result=$? ;;
                balena-etcher) install_balena-etcher; install_result=$? ;;
                arduino-ide) install_arduino-ide; install_result=$? ;;
                arduino-cli) install_arduino-cli; install_result=$? ;;
                esp-idf) install_esp-idf; install_result=$? ;;
                *) log_error "Unknown custom installer: $name"; install_result=1 ;;
            esac
            ;;
    esac
    
    # Update cache for this specific buntage if installation was successful
    if [[ $install_result -eq 0 ]]; then
        log "Installation successful, updating cache for buntage: $name"
        update_package_cache "$name"
    fi
    
    return $install_result
}

remove_package() {
    local name="$1"
    local pkg="${PACKAGES[$name]}"
    local method="${PKG_METHOD[$name]}"
    
    ui_yesno "Confirm Removal" "Are you sure you want to remove $name?\n\n${PKG_DESC[$name]}" || return 1
    
    local remove_result=0
    
    case "$method" in
        apt)
            remove_apt_package "$pkg"
            remove_result=$?
            ;;
        snap)
            remove_snap_package "$pkg"
            remove_result=$?
            ;;
        npm)
            remove_npm_package "$pkg"
            remove_result=$?
            ;;
        cargo)
            remove_cargo_package "$pkg"
            remove_result=$?
            ;;
        flatpak)
            remove_flatpak_package "$pkg"
            remove_result=$?
            ;;
        custom)
            case "$name" in
                docker) remove_docker; remove_result=$? ;;
                nodejs) remove_nodejs; remove_result=$? ;;
                vscode) remove_vscode; remove_result=$? ;;
                brave) remove_brave; remove_result=$? ;;
                sublime-text) remove_sublime; remove_result=$? ;;
                warp-terminal) remove_warp; remove_result=$? ;;
                ollama) remove_ollama; remove_result=$? ;;
                yt-dlp) remove_yt-dlp; remove_result=$? ;;
                invidious) remove_invidious; remove_result=$? ;;
                n8n) remove_n8n; remove_result=$? ;;
                gollama) remove_gollama; remove_result=$? ;;
                discord-deb) remove_discord-deb; remove_result=$? ;;
                phpmyadmin) remove_phpmyadmin; remove_result=$? ;;
                adminer) remove_adminer; remove_result=$? ;;
                bruno) remove_bruno; remove_result=$? ;;
                yaak) remove_yaak; remove_result=$? ;;
                rustup) remove_rustup; remove_result=$? ;;
                poetry) remove_poetry; remove_result=$? ;;
                deno) remove_deno; remove_result=$? ;;
                bun) remove_bun; remove_result=$? ;;
                mkdocs) remove_mkdocs; remove_result=$? ;;
                insomnia) remove_insomnia; remove_result=$? ;;
                zed) remove_zed; remove_result=$? ;;
                localwp) remove_localwp; remove_result=$? ;;
                devkinsta) remove_devkinsta; remove_result=$? ;;
                lando) remove_lando; remove_result=$? ;;
                ddev) remove_ddev; remove_result=$? ;;
                xampp) remove_xampp; remove_result=$? ;;
                lm-studio) remove_lm-studio; remove_result=$? ;;
                text-generation-webui) remove_text-generation-webui; remove_result=$? ;;
                whisper-cpp) remove_whisper-cpp; remove_result=$? ;;
                comfyui) remove_comfyui; remove_result=$? ;;
                invokeai) remove_invokeai; remove_result=$? ;;
                koboldcpp) remove_koboldcpp; remove_result=$? ;;
                minikube) remove_minikube; remove_result=$? ;;
                kind) remove_kind; remove_result=$? ;;
                ctop) remove_ctop; remove_result=$? ;;
                lazydocker) remove_lazydocker; remove_result=$? ;;
                caddy) remove_caddy; remove_result=$? ;;
                ngrok) remove_ngrok; remove_result=$? ;;
                mailhog) remove_mailhog; remove_result=$? ;;
                automatic1111) remove_automatic1111; remove_result=$? ;;
                fooocus) remove_fooocus; remove_result=$? ;;
                sd-next) remove_sd-next; remove_result=$? ;;
                kohya-ss-gui) remove_kohya-ss-gui; remove_result=$? ;;
                oh-my-zsh) remove_oh-my-zsh; remove_result=$? ;;
                starship) remove_starship; remove_result=$? ;;
                zoxide) remove_zoxide; remove_result=$? ;;
                seafile) remove_seafile; remove_result=$? ;;
                snapraid) remove_snapraid; remove_result=$? ;;
                greyhole) remove_greyhole; remove_result=$? ;;
                mergerfs) remove_mergerfs; remove_result=$? ;;
                plex) remove_plex; remove_result=$? ;;
                ums) remove_ums; remove_result=$? ;;
                balena-etcher) remove_balena-etcher; remove_result=$? ;;
                arduino-ide) remove_arduino-ide; remove_result=$? ;;
                arduino-cli) remove_arduino-cli; remove_result=$? ;;
                esp-idf) remove_esp-idf; remove_result=$? ;;
                *) log_error "Unknown custom remover: $name"; remove_result=1 ;;
            esac
            ;;
    esac
    
    # Update cache for this specific buntage if removal was successful
    if [[ $remove_result -eq 0 ]]; then
        log "Removal successful, updating cache for buntage: $name"
        update_package_cache "$name"
        ui_msg "Removed" "$name has been removed."
    else
        ui_msg "Error" "Failed to remove $name. Check the logs for details."
    fi
    
    return $remove_result
}

is_package_installed() {
    local name="$1"
    local silent="${2:-false}"  # Add silent mode parameter
    
    # Add error handling for empty or invalid buntage names
    if [[ -z "$name" ]]; then
        [[ "$silent" != "true" ]] && log "ERROR: Empty buntage name provided to is_package_installed"
        return 1
    fi
    
    if [[ -z "${PACKAGES[$name]:-}" ]]; then
        [[ "$silent" != "true" ]] && log "WARNING: Buntage '$name' not found in PACKAGES array"
        return 1
    fi
    
    local pkg="${PACKAGES[$name]}"
    local method="${PKG_METHOD[$name]:-}"
    
    if [[ -z "$method" ]]; then
        [[ "$silent" != "true" ]] && log "WARNING: No method defined for buntage '$name'"
        return 1
    fi
    
    [[ "$silent" != "true" ]] && log "Buntage '$name' uses method '$method' with buntage name '$pkg'"
    
    # Add error handling for each method
    local result=1
    case "$method" in
        apt) 
            log "Checking APT installation for '$pkg'"
            if is_apt_installed "$pkg"; then
                result=0
            else
                result=1
            fi
            ;;
        snap) 
            log "Checking Snap installation for '$pkg'"
            if is_snap_installed "$pkg"; then
                result=0
            else
                result=1
            fi
            ;;
        flatpak) 
            log "Checking Flatpak installation for '$pkg'"
            if is_flatpak_installed "$pkg"; then
                result=0
            else
                result=1
            fi
            ;;
        custom)
            log "Checking custom installation for '$name'"
            case "$name" in
                docker) 
                    if is_apt_installed "docker-ce"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                nodejs) 
                    if is_binary_available "node"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                vscode) 
                    if is_apt_installed "code"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                brave) 
                    if is_apt_installed "brave-browser"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                sublime-text) 
                    if is_apt_installed "sublime-text"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                warp-terminal) 
                    if is_apt_installed "warp-terminal"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                yt-dlp)
                    if is_binary_available "yt-dlp"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                phpmyadmin)
                    if is_apt_installed "phpmyadmin"; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                adminer)
                    if [[ -f "/var/www/adminer/index.php" ]]; then
                        result=0
                    else
                        result=1
                    fi
                    ;;
                *) 
                    log "WARNING: Unknown custom buntage '$name'"
                    result=1
                    ;;
            esac
            ;;
        *)
            log "ERROR: Unknown installation method '$method' for buntage '$name'"
            result=1
            ;;
    esac
    
    log "Buntage '$name' installation check result: $result"
    return $result
}

# ==============================================================================
# MENU SYSTEM
# ==============================================================================

# Function to refresh package cache in background without logging
refresh_cache_silent() {
    local refresh_pid
    {
        # Update cache for all packages silently
        for name in "${!PACKAGES[@]}"; do
            update_package_cache "$name" "true" &>/dev/null
        done
    } &
    refresh_pid=$!
    
    # Store the PID for potential cleanup
    echo "$refresh_pid" > "/tmp/ultrabunt_cache_refresh.pid" 2>/dev/null || true
}

# Function to check if background cache refresh is complete
is_cache_refresh_complete() {
    local pid_file="/tmp/ultrabunt_cache_refresh.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 1  # Still running
        else
            rm -f "$pid_file" 2>/dev/null || true
            return 0  # Complete
        fi
    fi
    return 0  # No refresh running
}

show_category_menu() {
    log "Entering show_category_menu function"
    
    # Hotkey cycling state tracking
    local -A last_hotkey_selection
    local -A hotkey_categories
    
    # Start background cache refresh on first load
    refresh_cache_silent
    
    while true; do
        log "Building category menu items..."
        local menu_items=()
        
        # System management tools at the top
        log "Adding system management menu items..."
        menu_items+=("cloudflare-setup" "(.Y.) Cloudflare Firewall Setup")
        menu_items+=("essentials-setup" "(.Y.) First-Time Essentials Setup")
        menu_items+=("system-info" "(.Y.) System Information")
        menu_items+=("mirror-management" "(.Y.) Mirror Management")
        menu_items+=("database-management" "(.Y.) Database Management")
        menu_items+=("swappiness" "(.Y.) Swappiness Tuning")
        menu_items+=("wordpress-setup" "(.Y.) WordPress Management")
        menu_items+=("keyboard-layout" "(.Y.) Keyboard Layout Configuration")
        menu_items+=("php-settings" "(.Y.) PHP Configuration")
        menu_items+=("log-viewer" "(.Y.) Log Viewer")
        menu_items+=("bulk-ops" "(.Y.) Bulk Operations")
        menu_items+=("terminal-size" "(.Y.) Dialog Box Size Configuration")
        menu_items+=("" "(_*_)")
        
        log "Processing categories array with ${#CATEGORIES[@]} entries"
        # Build sortable array as name:id:installed:total for alphabetical ordering by name
        local sortable_categories=()
        for entry in "${CATEGORIES[@]}"; do
            local cat_id="${entry%%:*}"
            local cat_name="${entry#*:}"

            # Skip excluded categories
            if [[ -n "${EXCLUDED_CATEGORIES[$cat_id]:-}" ]]; then
                log "Skipping excluded category: $cat_id"
                continue
            fi

            # Count installed buntages in category
            local total=0
            local installed=0

            # Use a safer iteration method
            local package_names=()
            for name in "${!PACKAGES[@]}"; do
                package_names+=("$name")
            done

            for name in "${package_names[@]}"; do
                local pkg_category="${PKG_CATEGORY[$name]:-}"
                if [[ "$pkg_category" == "$cat_id" ]]; then
                    total=$((total + 1))
                    if is_package_installed "$name" "true"; then
                        installed=$((installed + 1))
                    fi
                fi
            done

            sortable_categories+=("$cat_name:$cat_id:$installed:$total")
        done

        # Sort categories alphabetically by display name
        if [[ ${#sortable_categories[@]} -gt 0 ]]; then
            mapfile -t sortable_categories < <(printf "%s\n" "${sortable_categories[@]}" | sort)
        fi

        # Build dynamic hotkeys based on an allowed set, skipping reserved letters
        # Reserved: Q (Quit), Z (Back)
        local -A dynamic_hotkeys=()
        # Reset hotkey_categories for this render
        hotkey_categories=()

        local allowed_upper=(A B C D E F G H I J K L M N O P R S T U V W X Y)
        local allowed_lower=(a b c d e f g h i j k l m n o p r s t u v w x y)
        local index=0
        for item in "${sortable_categories[@]}"; do
            local rest="${item#*:}"
            local cat_id="${rest%%:*}"
            local letter=""
            if (( index < ${#allowed_upper[@]} )); then
                letter="${allowed_upper[$index]}"
            else
                local lower_index=$((index - ${#allowed_upper[@]}))
                if (( lower_index < ${#allowed_lower[@]} )); then
                    letter="${allowed_lower[$lower_index]}"
                else
                    # Fallback: cycle through allowed_upper again to ensure a tag exists
                    letter="${allowed_upper[$((index % ${#allowed_upper[@]}))]}"
                fi
            fi
            dynamic_hotkeys[$cat_id]="$letter"
            hotkey_categories[$letter]="$cat_id"
            index=$((index + 1))
        done

        # Add refresh indicator if cache is still updating
        local refresh_indicator=""
        if ! is_cache_refresh_complete; then
            refresh_indicator=" 🔄"
        fi

        # Rebuild menu_items from sorted categories
        for item in "${sortable_categories[@]}"; do
            local cat_name="${item%%:*}"
            local rest="${item#*:}"
            local cat_id="${rest%%:*}"
            local installed_total="${rest#*:}"
            local installed="${installed_total%%:*}"
            local total="${installed_total#*:}"

            # Get dynamic hotkey for this category (A..Z based on sorted order)
            local hotkey="${dynamic_hotkeys[$cat_id]:-}"
            local hotkey_display=""
            if [[ -n "$hotkey" ]]; then
                hotkey_display="($hotkey) "
            fi

            # Use the hotkey letter as the menu tag so typing the letter jumps
            # directly to the row that displays that bracketed hotkey.
            # The actual category id is recovered later via hotkey_categories.
            menu_items+=("$hotkey" "${hotkey_display}$cat_name [$installed/$total installed]$refresh_indicator")
        done
        
        log "Adding additional menu items..."
        # System management tools at the top
        menu_items+=("" "(_*_)")
        # Map Quit to the displayed hotkey letter so pressing 'Q' jumps/selects it
        menu_items+=("Q" "(Q) Exit Installer")
        
        log "Calling ui_menu with ${#menu_items[@]} menu items"
        log "Menu items array contents: ${menu_items[*]}"
        
        # Add error handling for ui_menu call
        local choice=""
        set +e  # Temporarily disable exit on error
        choice=$(ui_menu "Ultrabunt Ultimate Buntstaller" \
            "Select a buntegory to manage buntages:" \
            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}")
        local ui_result=$?
        set -e  # Re-enable exit on error
        
        if [[ $ui_result -ne 0 ]]; then
            log "User cancelled or error occurred"
            break
        fi
        
        case "$choice" in
            cloudflare-setup)
                show_cloudflare_setup_menu || {
                    log "ERROR: show_cloudflare_setup_menu failed"
                    ui_msg "Error" "Failed to display Cloudflare setup menu. Please check the logs."
                }
                ;;
            essentials-setup)
                show_essentials_setup_menu || {
                    log "ERROR: show_essentials_setup_menu failed"
                    ui_msg "Error" "Failed to run First-Time Essentials setup. Please check the logs."
                }
                ;;
            quit|back|q|Q) 
                # Simple confirmation for quit
                if [[ "$choice" == "quit" || "$choice" == "q" || "$choice" == "Q" ]]; then
                    if ui_yesno "Confirm Exit" "Are you sure you want to exit Ultrabunt?"; then
                        break
                    else
                        continue
                    fi
                else
                    break
                fi
                ;;
            terminal-size)
                show_dialog_size_menu || {
                    log "ERROR: show_dialog_size_menu failed"
                    ui_msg "Error" "Failed to display dialog size menu. Please check the logs."
                }
                ;;
            system-info) 
                show_system_info || {
                    log "ERROR: show_system_info failed"
                    ui_msg "Error" "Failed to display system information. Please check the logs."
                }
                ;;
            mirror-management)
                show_mirror_management_menu || {
                    log "ERROR: show_mirror_management_menu failed"
                    ui_msg "Error" "Failed to display mirror management menu. Please check the logs."
                }
                ;;
            keyboard-layout)
                show_keyboard_layout_menu || {
                    log "ERROR: show_keyboard_layout_menu failed"
                    ui_msg "Error" "Failed to display keyboard layout menu. Please check the logs."
                }
                ;;
            wordpress-setup)
                show_wordpress_setup_menu || {
                    log "ERROR: show_wordpress_setup_menu failed"
                    ui_msg "Error" "Failed to display WordPress setup menu. Please check the logs."
                }
                ;;
            php-settings)
                show_php_settings_menu || {
                    log "ERROR: show_php_settings_menu failed"
                    ui_msg "Error" "Failed to display PHP settings menu. Please check the logs."
                }
                ;;
            database-management)
                show_database_management_menu || {
                    log "ERROR: show_database_management_menu failed"
                    ui_msg "Error" "Failed to display database management menu. Please check the logs."
                }
                ;;
            swappiness)
                show_swappiness_menu || {
                    log "ERROR: show_swappiness_menu failed"
                    ui_msg "Error" "Failed to display Swappiness tuning menu. Please check the logs."
                }
                ;;
            log-viewer)
                show_log_viewer_menu || {
                    log "ERROR: show_log_viewer_menu failed"
                    ui_msg "Error" "Failed to display log viewer menu. Please check the logs."
                }
                ;;
            bulk-ops) 
                show_bulk_operations 
                ;;
            "") 
                continue 
                ;;
            *) 
                # Handle A-Z hotkey selection
                local upper_choice="${choice^^}"  # Convert to uppercase
                
                # Check if it's a valid hotkey (A-Y, excluding Z which is for back navigation)
                if [[ "$upper_choice" =~ ^[A-Y]$ ]]; then
                    # Get categories for this hotkey
                    local categories="${hotkey_categories[$upper_choice]:-}"
                    
                    if [[ -n "$categories" ]]; then
                        # Convert categories string to array
                        local cat_array=($categories)
                        local selected_category=""
                        
                        if [[ ${#cat_array[@]} -eq 1 ]]; then
                            # Only one category for this hotkey
                            selected_category="${cat_array[0]}"
                        else
                            # Multiple categories - cycle through them
                            local last_selected="${last_hotkey_selection[$upper_choice]:-}"
                            local current_index=0
                            
                            # Find current index if we have a previous selection
                            if [[ -n "$last_selected" ]]; then
                                for i in "${!cat_array[@]}"; do
                                    if [[ "${cat_array[$i]}" == "$last_selected" ]]; then
                                        current_index=$(( (i + 1) % ${#cat_array[@]} ))
                                        break
                                    fi
                                done
                            fi
                            
                            selected_category="${cat_array[$current_index]}"
                        fi
                        
                        # Update last selection for this hotkey
                        last_hotkey_selection[$upper_choice]="$selected_category"
                        
                        # Handle special cases
                        if [[ "$selected_category" == "quit" ]]; then
                            if ui_yesno "Confirm Exit" "Are you sure you want to exit Ultrabunt?"; then
                                break
                            else
                                continue
                            fi
                        else
                            show_buntage_list "$selected_category"
                        fi
                    else
                        # Not a valid hotkey, treat as category ID
                        show_buntage_list "$choice"
                    fi
                else
                    # Not a hotkey, treat as category ID
                    show_buntage_list "$choice"
                fi
                ;;
        esac
    done
    log "Exiting show_category_menu function"
}

show_buntage_list() {
    local category="$1"
    local cat_name=""
    
    for entry in "${CATEGORIES[@]}"; do
        if [[ "${entry%%:*}" == "$category" ]]; then
            cat_name="${entry#*:}"
            break
        fi
    done
    
    while true; do
        local menu_items=()
        
        for name in "${!PACKAGES[@]}"; do
            local pkg_category="${PKG_CATEGORY[$name]:-}"
            
            if [[ "$pkg_category" == "$category" ]]; then
                local status="✗ Not Installed"
                local display_text
                if is_package_installed "$name"; then
                    status="✓ Installed"
                    display_text="(.Y.) ${PKG_DESC[$name]:-No description} [$status]"
                else
                    display_text="(_*_) ${PKG_DESC[$name]:-No description} [$status]"
                fi
                # Use buntage key as both the selection value and display text
        # This ensures whiptail returns the buntage key, not the description
                menu_items+=("$name" "$display_text")
            fi
        done
        
        if [[ ${#menu_items[@]} -eq 0 ]]; then
            ui_msg "No Buntages" "No buntages found in category: $cat_name"
            return
        fi
        
        # Sort menu items alphabetically by buntage name (keeping key-value pairs together)
        # Create temporary array for sorting
        local sorted_items=()
        local temp_array=()
        
        # Convert menu_items to sortable format (key:value pairs)
        for ((i=0; i<${#menu_items[@]}; i+=2)); do
            if [[ -n "${menu_items[i]}" ]]; then
                temp_array+=("${menu_items[i]}:${menu_items[i+1]}")
            fi
        done
        
        # Sort the temp array
        IFS=$'\n' temp_array=($(sort <<<"${temp_array[*]}"))
        unset IFS
        
        # Convert back to menu_items format
        for item in "${temp_array[@]}"; do
            local key="${item%%:*}"
            local value="${item#*:}"
            sorted_items+=("$key" "$value")
        done
        
        menu_items=("${sorted_items[@]}")
        
        menu_items+=("" "(_*_)")
        menu_items+=("zback" "(B) ← Back to Categories")
        
        local choice
        choice=$(ui_menu "$cat_name" \
            "Select a buntage to manage:" \
            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            back|zback|z|"") break ;;
            *) show_buntage_actions "$choice" ;;
        esac
    done
}

show_buntage_actions() {
    local name="$1"
    
    # Validate that the buntage exists in our arrays
    if [[ -z "${PACKAGES[$name]:-}" ]]; then
        log "ERROR: Buntage '$name' not found in PACKAGES array"
        return 1
    fi
    
    local pkg="${PACKAGES[$name]}"
    local desc="${PKG_DESC[$name]:-No description available}"
    local method="${PKG_METHOD[$name]:-unknown}"
    
    local status="Not Installed"
    if is_package_installed "$name"; then
        status="✓ Installed"
    fi
    
    while true; do
        local info="Buntage: $name\nDescription: $desc\nInstall Method: $method\nBuntage Name: $pkg\nStatus: $status"
        if [[ "$method" == "snap" ]]; then
            if requires_classic_snap "$pkg"; then
                info+="\nNote: Snap uses classic confinement and will install with --classic"
            fi
        fi
        
        local menu_items=()
        
        if is_package_installed "$name"; then
            menu_items+=("reinstall" "(.Y.) Reinstall Buntage")
            menu_items+=("remove" "(.Y.) Remove Buntage")
            menu_items+=("info" "(.Y.) Show Detailed Info")
        else
            menu_items+=("install" "(.Y.) Install Buntage")
            menu_items+=("info" "(.Y.) Show Detailed Info")
        fi
        
        menu_items+=("zback" "(B) ← Back to Buntage List")
        
        local choice
        choice=$(ui_menu "Manage: $name" "$info" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}")
        
        case "$choice" in
            install)
                install_package_with_choice "$name"
                ui_msg "Success" "$name installed successfully!"
                status="✓ Installed"
                ;;
            reinstall)
                remove_package "$name"
                install_package_with_choice "$name"
                ui_msg "Success" "$name reinstalled successfully!"
                ;;
            remove)
                remove_package "$name"
                status="Not Installed"
                ;;
            info)
                show_buntage_info "$name"
                ;;
            ""|back|zback|z)
                return
                ;;
            *)
                return
                ;;
        esac
    done
}

show_buntage_info() {
    local name="$1"
    local pkg="${PACKAGES[$name]}"
    local desc="${PKG_DESC[$name]}"
    local method="${PKG_METHOD[$name]}"
    local category="${PKG_CATEGORY[$name]}"
    local deps="${PKG_DEPS[$name]:-None}"
    
    local status="Not Installed"
    local details=""
    
    if is_package_installed "$name"; then
        status="✓ Installed"
        
        case "$method" in
            apt)
                if is_apt_installed "$pkg"; then
                    local version=$(dpkg -l "$pkg" 2>/dev/null | awk '/^ii/ {print $3}')
                    details="Version: $version\n"
                    details+="Files: $(dpkg -L "$pkg" 2>/dev/null | wc -l) files installed\n"
                fi
                ;;
            snap)
                if is_snap_installed "$pkg"; then
                    local snap_info=$(snap info "$pkg" 2>/dev/null | grep -E "^(installed|tracking)" | head -2)
                    details="$snap_info\n"
                fi
                ;;
            flatpak)
                if is_flatpak_installed "$pkg"; then
                    local flat_info=$(flatpak info "$pkg" 2>/dev/null | grep -E "^(Version|Branch|Ref)")
                    details="$flat_info\n"
                fi
                ;;
        esac
    fi
    
    local info="BUNTAGE INFORMATION\n"
    info+="═══════════════════════════════════════\n\n"
    info+="Name: $name\n"
    info+="Description: $desc\n"
    info+="Category: $category\n"
    info+="Install Method: $method\n"
    info+="Buntage ID: $pkg\n"
    info+="Dependencies: $deps\n"
    info+="Status: $status\n\n"
    
    if [[ -n "$details" ]]; then
        info+="INSTALLED DETAILS\n"
        info+="═══════════════════════════════════════\n"
        info+="$details"
    fi
    
    ui_info "Buntage Info: $name" "$info"
}

# ==============================================================================
# DIALOG BOX SIZE MANAGEMENT FUNCTIONS
# ==============================================================================

# Function to apply dialog preset
apply_dialog_preset() {
    local preset="$1"
    if [[ -n "${DIALOG_PRESETS[$preset]:-}" ]]; then
        local preset_values=(${DIALOG_PRESETS[$preset]})
        DIALOG_HEIGHT="${preset_values[0]}"
        DIALOG_WIDTH="${preset_values[1]}"
        DIALOG_MENU_HEIGHT="${preset_values[2]}"
        CURRENT_DIALOG_PRESET="$preset"
        log "Applied dialog preset: $preset (${DIALOG_HEIGHT}x${DIALOG_WIDTH}, menu: ${DIALOG_MENU_HEIGHT})"
    fi
}

# Function to get current dialog dimensions
get_dialog_dimensions() {
    echo "$DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT"
}

show_dialog_size_menu() {
    log "Entering show_dialog_size_menu function"
    
    while true; do
        # Get current dialog size info
        local current_info="Current: ${CURRENT_DIALOG_PRESET} (${DIALOG_HEIGHT}×${DIALOG_WIDTH})"
        
        local menu_items=()
        menu_items+=("compact" "(.Y.) Compact (20×70) - Minimal space")
        menu_items+=("standard" "(.Y.) Standard (24×80) - Default size")
        menu_items+=("large" "(.Y.) Large (30×100) - More content")
        menu_items+=("wide" "(.Y.) Wide (24×120) - Wider menus")
        menu_items+=("tall" "(.Y.) Tall (35×80) - More menu items")
        menu_items+=("huge" "(.Y.) Huge (40×140) - Maximum size")
        menu_items+=("" "(_*_)")
        menu_items+=("custom" "(.Y.) Custom Size - Set your own")
        menu_items+=("preview" "(.Y.) Preview Current Size")
        menu_items+=("back" "(Z) ← Back to Main Menu")
        
        local choice
        choice=$(ui_menu "Dialog Box Size Configuration" \
            "$current_info\n\nSelect a dialog box size preset:\n(This controls the grey menu boxes, not the terminal window)" \
            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            compact|standard|large|wide|tall|huge)
                apply_dialog_preset "$choice"
                ui_msg "Success" "Dialog size changed to $choice preset!\n\nNew size: ${DIALOG_HEIGHT}×${DIALOG_WIDTH}\nMenu height: ${DIALOG_MENU_HEIGHT}\n\nYou'll see the change in the next menu."
                ;;
            custom)
                set_custom_dialog_size
                ;;
            preview)
                show_dialog_preview
                ;;
            back|z)
                break
                ;;
        esac
    done
    
    log "Exiting show_dialog_size_menu function"
}

set_custom_dialog_size() {
    local height
    local width
    local menu_height
    
    # Get current size as defaults
    height=$(ui_input "Custom Dialog Height" "Enter dialog box height (lines):" "$DIALOG_HEIGHT")
    [[ -z "$height" ]] && return
    
    width=$(ui_input "Custom Dialog Width" "Enter dialog box width (columns):" "$DIALOG_WIDTH")
    [[ -z "$width" ]] && return
    
    menu_height=$(ui_input "Custom Menu Height" "Enter menu area height (lines):" "$DIALOG_MENU_HEIGHT")
    [[ -z "$menu_height" ]] && return
    
    # Validate inputs
    if [[ "$height" =~ ^[0-9]+$ ]] && [[ "$width" =~ ^[0-9]+$ ]] && [[ "$menu_height" =~ ^[0-9]+$ ]]; then
        if [[ $height -ge 15 && $height -le 50 && $width -ge 60 && $width -le 200 && $menu_height -ge 5 && $menu_height -le 30 ]]; then
            DIALOG_HEIGHT="$height"
            DIALOG_WIDTH="$width"
            DIALOG_MENU_HEIGHT="$menu_height"
            CURRENT_DIALOG_PRESET="custom"
            ui_msg "Success" "Custom dialog size set!\n\nSize: ${DIALOG_HEIGHT}×${DIALOG_WIDTH}\nMenu height: ${DIALOG_MENU_HEIGHT}\n\nYou'll see the change in the next menu."
            log "Custom dialog size set: ${DIALOG_HEIGHT}x${DIALOG_WIDTH}, menu: ${DIALOG_MENU_HEIGHT}"
        else
            ui_msg "Error" "Invalid dimensions!\n\nHeight: 15-50 lines\nWidth: 60-200 columns\nMenu height: 5-30 lines"
        fi
    else
        ui_msg "Error" "Please enter valid numbers only."
    fi
}

show_dialog_preview() {
    local preview_items=()
    preview_items+=("item1" "(.Y.) Sample menu item 1")
    preview_items+=("item2" "(.Y.) Sample menu item 2")
    preview_items+=("item3" "(.Y.) Sample menu item 3")
    preview_items+=("item4" "(.Y.) Sample menu item 4")
    preview_items+=("item5" "(.Y.) Sample menu item 5")
    
    ui_menu "Dialog Size Preview" \
        "This is how your dialog boxes look with current settings:\n\nSize: ${DIALOG_HEIGHT}×${DIALOG_WIDTH}\nMenu height: ${DIALOG_MENU_HEIGHT}\nPreset: ${CURRENT_DIALOG_PRESET}" \
        $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${preview_items[@]}" >/dev/null || true
}

# ==============================================================================
# TERMINAL SIZE MANAGEMENT FUNCTIONS (Legacy - kept for compatibility)
# ==============================================================================

show_terminal_size_menu() {
    log "Entering show_terminal_size_menu function"
    
    while true; do
        # Get current terminal size
        local current_cols=$(tput cols 2>/dev/null || echo "Unknown")
        local current_lines=$(tput lines 2>/dev/null || echo "Unknown")
        local current_size="${current_cols}x${current_lines}"
        
        local menu_items=()
        menu_items+=("small" "(.Y.) Small Terminal (80x24) - Classic size")
        menu_items+=("medium" "(.Y.) Medium Terminal (120x30) - Balanced")
        menu_items+=("large" "(.Y.) Large Terminal (160x40) - Development")
        menu_items+=("xlarge" "(.Y.) Extra Large (200x50) - Multi-pane")
        menu_items+=("custom" "(.Y.) Custom Size - Set your own")
        menu_items+=("" "(_*_)")
        menu_items+=("detect" "(.Y.) Show Current Size")
        menu_items+=("back" "(Z) ← Back to Main Menu")
        
        local choice
        choice=$(ui_menu "Terminal Size Configuration" \
            "Current Terminal Size: $current_size\n\nSelect a terminal size preset or configure custom size:" \
            20 80 12 "${menu_items[@]}") || break
        
        case "$choice" in
            small)
                resize_terminal 80 24
                ;;
            medium)
                resize_terminal 120 30
                ;;
            large)
                resize_terminal 160 40
                ;;
            xlarge)
                resize_terminal 200 50
                ;;
            custom)
                set_custom_terminal_size
                ;;
            detect)
                show_terminal_info
                ;;
            back|z|"")
                break
                ;;
        esac
    done
    
    log "Exiting show_terminal_size_menu function"
}

resize_terminal() {
    local cols="$1"
    local lines="$2"
    
    log "Attempting to resize terminal to ${cols}x${lines}"
    
    # Try different methods to resize terminal
    local success=false
    
    # Method 1: Using printf escape sequences (works in most terminals)
    if command -v printf >/dev/null 2>&1; then
        printf '\e[8;%d;%dt' "$lines" "$cols" 2>/dev/null && success=true
    fi
    
    # Method 2: Using resize command if available
    if ! $success && command -v resize >/dev/null 2>&1; then
        resize -s "$lines" "$cols" 2>/dev/null && success=true
    fi
    
    # Method 3: Using stty if available
    if ! $success && command -v stty >/dev/null 2>&1; then
        stty rows "$lines" cols "$cols" 2>/dev/null && success=true
    fi
    
    # Give terminal time to resize
    sleep 0.5
    
    # Verify the resize worked
    local new_cols=$(tput cols 2>/dev/null || echo "0")
    local new_lines=$(tput lines 2>/dev/null || echo "0")
    
    if [[ "$new_cols" -eq "$cols" && "$new_lines" -eq "$lines" ]]; then
        ui_msg "Success" "Terminal resized to ${cols}x${lines} successfully!"
        log "Terminal resize successful: ${cols}x${lines}"
    elif $success; then
        ui_msg "Partial Success" "Resize command sent, but verification shows ${new_cols}x${new_lines}.\n\nSome terminals may need manual adjustment or don't support programmatic resizing."
        log "Terminal resize partially successful: requested ${cols}x${lines}, got ${new_cols}x${new_lines}"
    else
        ui_msg "Notice" "Terminal resizing may not be supported by your terminal emulator.\n\nCurrent size: ${new_cols}x${new_lines}\nRequested: ${cols}x${lines}\n\nTry manually resizing your terminal window."
        log "Terminal resize failed: terminal may not support programmatic resizing"
    fi
}

set_custom_terminal_size() {
    local cols
    local lines
    
    # Get current size as defaults
    local current_cols=$(tput cols 2>/dev/null || echo "80")
    local current_lines=$(tput lines 2>/dev/null || echo "24")
    
    cols=$(ui_input "Custom Terminal Width" "Enter terminal width (columns):" "$current_cols")
    [[ -z "$cols" ]] && return
    
    lines=$(ui_input "Custom Terminal Height" "Enter terminal height (lines):" "$current_lines")
    [[ -z "$lines" ]] && return
    
    # Validate input
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || ! [[ "$lines" =~ ^[0-9]+$ ]]; then
        ui_msg "Error" "Please enter valid numbers for width and height."
        return
    fi
    
    # Reasonable limits
    if [[ "$cols" -lt 20 || "$cols" -gt 500 || "$lines" -lt 5 || "$lines" -gt 200 ]]; then
        ui_msg "Error" "Please enter reasonable values:\nWidth: 20-500 columns\nHeight: 5-200 lines"
        return
    fi
    
    resize_terminal "$cols" "$lines"
}

show_terminal_info() {
    local cols=$(tput cols 2>/dev/null || echo "Unknown")
    local lines=$(tput lines 2>/dev/null || echo "Unknown")
    local term_type="${TERM:-Unknown}"
    local term_program="${TERM_PROGRAM:-Unknown}"
    
    local info="TERMINAL INFORMATION\n"
    info+="═══════════════════════════════════════\n\n"
    info+="Current Size: ${cols} columns × ${lines} lines\n"
    info+="Terminal Type: $term_type\n"
    info+="Terminal Program: $term_program\n\n"
    info+="COMMON SIZES FOR REFERENCE\n"
    info+="─────────────────────────────────────\n"
    info+="Small (80×24): Classic terminal size\n"
    info+="Medium (120×30): Good for most tasks\n"
    info+="Large (160×40): Development work\n"
    info+="Extra Large (200×50): Multi-pane setups\n\n"
    info+="NOTE: Some terminal emulators may not\n"
    info+="support programmatic resizing."
    
    ui_info "Terminal Information" "$info"
}

show_cpu_details() {
    log "Starting show_cpu_details function"
    
    local info="CPU & PROCESSOR DETAILS\n"
    info+="═══════════════════════════════════════\n\n"
    
    # Basic CPU Information
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_model cpu_vendor cpu_family cpu_stepping cpu_microcode
        cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_model="Unknown"
        cpu_vendor=$(grep "vendor_id" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_vendor="Unknown"
        cpu_family=$(grep "cpu family" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_family="Unknown"
        cpu_stepping=$(grep "stepping" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_stepping="Unknown"
        cpu_microcode=$(grep "microcode" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_microcode="Unknown"
        
        info+="Model: $cpu_model\n"
        info+="Vendor: $cpu_vendor\n"
        info+="Family: $cpu_family\n"
        info+="Stepping: $cpu_stepping\n"
        info+="Microcode: $cpu_microcode\n\n"
    fi
    
    # Core and Thread Information
    local physical_cores logical_cores threads_per_core
    physical_cores=$(grep "cpu cores" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || physical_cores="Unknown"
    logical_cores=$(nproc 2>/dev/null) || logical_cores="Unknown"
    if [[ "$physical_cores" != "Unknown" && "$logical_cores" != "Unknown" ]]; then
        threads_per_core=$((logical_cores / physical_cores))
    else
        threads_per_core="Unknown"
    fi
    
    info+="Physical Cores: $physical_cores\n"
    info+="Logical Cores: $logical_cores\n"
    info+="Threads per Core: $threads_per_core\n\n"
    
    # CPU Frequencies
    local cpu_freq_current cpu_freq_max cpu_freq_min
    if [[ -f /proc/cpuinfo ]]; then
        cpu_freq_current=$(grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_freq_current="Unknown"
        [[ "$cpu_freq_current" != "Unknown" ]] && cpu_freq_current="${cpu_freq_current} MHz"
    fi
    
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq ]]; then
        cpu_freq_max=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
        [[ -n "$cpu_freq_max" ]] && cpu_freq_max="$((cpu_freq_max / 1000)) MHz" || cpu_freq_max="Unknown"
    else
        cpu_freq_max="Unknown"
    fi
    
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq ]]; then
        cpu_freq_min=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null)
        [[ -n "$cpu_freq_min" ]] && cpu_freq_min="$((cpu_freq_min / 1000)) MHz" || cpu_freq_min="Unknown"
    else
        cpu_freq_min="Unknown"
    fi
    
    info+="Current Frequency: $cpu_freq_current\n"
    info+="Maximum Frequency: $cpu_freq_max\n"
    info+="Minimum Frequency: $cpu_freq_min\n\n"
    
    # Cache Information
    if command -v lscpu &>/dev/null; then
        local l1d_cache l1i_cache l2_cache l3_cache
        l1d_cache=$(lscpu 2>/dev/null | grep "L1d cache:" | awk '{print $3}' 2>/dev/null) || l1d_cache="Unknown"
        l1i_cache=$(lscpu 2>/dev/null | grep "L1i cache:" | awk '{print $3}' 2>/dev/null) || l1i_cache="Unknown"
        l2_cache=$(lscpu 2>/dev/null | grep "L2 cache:" | awk '{print $3}' 2>/dev/null) || l2_cache="Unknown"
        l3_cache=$(lscpu 2>/dev/null | grep "L3 cache:" | awk '{print $3}' 2>/dev/null) || l3_cache="Unknown"
        
        info+="L1 Data Cache: $l1d_cache\n"
        info+="L1 Instruction Cache: $l1i_cache\n"
        info+="L2 Cache: $l2_cache\n"
        info+="L3 Cache: $l3_cache\n\n"
    fi
    
    # CPU Features and Flags
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_flags
        cpu_flags=$(grep "flags" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_flags="Unknown"
        if [[ "$cpu_flags" != "Unknown" ]]; then
            local important_flags=""
            for flag in sse sse2 sse3 ssse3 sse4_1 sse4_2 avx avx2 avx512f aes pae nx lm vmx svm; do
                if echo "$cpu_flags" | grep -q "$flag"; then
                    important_flags+="$flag "
                fi
            done
            info+="Key Features: ${important_flags:-None detected}\n\n"
        fi
    fi
    
    # CPU Load and Temperature
    local load_avg cpu_temp
    load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' 2>/dev/null | sed 's/^ *//' 2>/dev/null) || load_avg="Unknown"
    info+="Load Average:$load_avg\n"
    
    # Try to get CPU temperature
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [[ -n "$cpu_temp" ]]; then
            cpu_temp="$((cpu_temp / 1000))°C"
        else
            cpu_temp="Unknown"
        fi
    else
        cpu_temp="Unknown"
    fi
    info+="Temperature: $cpu_temp\n\n"
    
    # Vulnerabilities
    if [[ -d /sys/devices/system/cpu/vulnerabilities ]]; then
        info+="SECURITY VULNERABILITIES\n"
        info+="─────────────────────────────────────\n"
        for vuln in /sys/devices/system/cpu/vulnerabilities/*; do
            if [[ -f "$vuln" ]]; then
                local vuln_name status
                vuln_name=$(basename "$vuln")
                status=$(cat "$vuln" 2>/dev/null) || status="Unknown"
                info+="$(printf "%-20s: %s\n" "$vuln_name" "$status")"
            fi
        done
    fi
    
    ui_info "CPU & Processor Details" "$info"
    return 0
}

show_memory_details() {
    log "Starting show_memory_details function"
    
    local info="MEMORY & RAM INFORMATION\n"
    info+="═══════════════════════════════════════\n\n"
    
    # Basic Memory Information
    if [[ -f /proc/meminfo ]]; then
        local mem_total mem_free mem_available mem_used mem_cached mem_buffers
        mem_total=$(grep "MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}' 2>/dev/null) || mem_total="0"
        mem_free=$(grep "MemFree:" /proc/meminfo 2>/dev/null | awk '{print $2}' 2>/dev/null) || mem_free="0"
        mem_available=$(grep "MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print $2}' 2>/dev/null) || mem_available="0"
        mem_cached=$(grep "^Cached:" /proc/meminfo 2>/dev/null | awk '{print $2}' 2>/dev/null) || mem_cached="0"
        mem_buffers=$(grep "Buffers:" /proc/meminfo 2>/dev/null | awk '{print $2}' 2>/dev/null) || mem_buffers="0"
        
        if [[ "$mem_total" != "0" ]]; then
            mem_used=$((mem_total - mem_available))
            local mem_total_gb mem_used_gb mem_free_gb mem_available_gb
            mem_total_gb=$(echo "scale=2; $mem_total / 1024 / 1024" | bc 2>/dev/null) || mem_total_gb="Unknown"
            mem_used_gb=$(echo "scale=2; $mem_used / 1024 / 1024" | bc 2>/dev/null) || mem_used_gb="Unknown"
            mem_free_gb=$(echo "scale=2; $mem_free / 1024 / 1024" | bc 2>/dev/null) || mem_free_gb="Unknown"
            mem_available_gb=$(echo "scale=2; $mem_available / 1024 / 1024" | bc 2>/dev/null) || mem_available_gb="Unknown"
            
            local usage_percent
            usage_percent=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc 2>/dev/null) || usage_percent="Unknown"
            
            info+="Total Memory: ${mem_total_gb} GB (${mem_total} KB)\n"
            info+="Used Memory: ${mem_used_gb} GB (${mem_used} KB)\n"
            info+="Free Memory: ${mem_free_gb} GB (${mem_free} KB)\n"
            info+="Available Memory: ${mem_available_gb} GB (${mem_available} KB)\n"
            info+="Memory Usage: ${usage_percent}%\n\n"
            
            # Cache and Buffer Information
            local cached_gb buffers_gb
            cached_gb=$(echo "scale=2; $mem_cached / 1024 / 1024" | bc 2>/dev/null) || cached_gb="Unknown"
            buffers_gb=$(echo "scale=2; $mem_buffers / 1024 / 1024" | bc 2>/dev/null) || buffers_gb="Unknown"
            
            info+="Cached: ${cached_gb} GB (${mem_cached} KB)\n"
            info+="Buffers: ${buffers_gb} GB (${mem_buffers} KB)\n\n"
        fi
    fi
    
    # Swap Information
    if [[ -f /proc/meminfo ]]; then
        local swap_total swap_free swap_used
        swap_total=$(grep "SwapTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}' 2>/dev/null) || swap_total="0"
        swap_free=$(grep "SwapFree:" /proc/meminfo 2>/dev/null | awk '{print $2}' 2>/dev/null) || swap_free="0"
        
        if [[ "$swap_total" != "0" ]]; then
            swap_used=$((swap_total - swap_free))
            local swap_total_gb swap_used_gb swap_usage_percent
            swap_total_gb=$(echo "scale=2; $swap_total / 1024 / 1024" | bc 2>/dev/null) || swap_total_gb="Unknown"
            swap_used_gb=$(echo "scale=2; $swap_used / 1024 / 1024" | bc 2>/dev/null) || swap_used_gb="Unknown"
            swap_usage_percent=$(echo "scale=1; $swap_used * 100 / $swap_total" | bc 2>/dev/null) || swap_usage_percent="Unknown"
            
            info+="SWAP INFORMATION\n"
            info+="─────────────────────────────────────\n"
            info+="Total Swap: ${swap_total_gb} GB\n"
            info+="Used Swap: ${swap_used_gb} GB\n"
            info+="Swap Usage: ${swap_usage_percent}%\n\n"
        else
            info+="SWAP INFORMATION\n"
            info+="─────────────────────────────────────\n"
            info+="No swap space configured\n\n"
        fi
    fi
    
    # Memory Hardware Information (DMI)
    if command -v dmidecode &>/dev/null; then
        info+="MEMORY HARDWARE DETAILS\n"
        info+="─────────────────────────────────────\n"
        
        local memory_devices
        memory_devices=$(dmidecode -t memory 2>/dev/null | grep -E "(Size|Speed|Type|Manufacturer|Part Number):" | head -20 2>/dev/null)
        if [[ -n "$memory_devices" ]]; then
            info+="$memory_devices\n\n"
        else
            info+="Memory hardware details not available\n\n"
        fi
    fi
    
    # Memory Usage by Process (Top 10)
    info+="TOP MEMORY CONSUMING PROCESSES\n"
    info+="─────────────────────────────────────\n"
    local top_processes
    top_processes=$(ps aux --sort=-%mem 2>/dev/null | head -11 | tail -10 | awk '{printf "%-15s %6s %s\n", $1, $4"%", $11}' 2>/dev/null)
    if [[ -n "$top_processes" ]]; then
        info+="USER            MEM%   COMMAND\n"
        info+="$top_processes\n"
    else
        info+="Process information not available\n"
    fi
    
    ui_info "Memory & RAM Information" "$info"
    return 0
}

show_storage_details() {
    log "Starting show_storage_details function"
    
    local info="STORAGE & DISK DETAILS\n"
    info+="═══════════════════════════════════════\n\n"
    
    # Disk Usage Summary
    info+="FILESYSTEM USAGE\n"
    info+="─────────────────────────────────────\n"
    local disk_usage
    disk_usage=$(df -h 2>/dev/null | grep -E '^/dev/' | grep -v -E '(tmpfs|udev|overlay)' 2>/dev/null)
    if [[ -n "$disk_usage" ]]; then
        info+="FILESYSTEM      SIZE  USED AVAIL USE% MOUNTED ON\n"
        info+="$disk_usage\n\n"
    else
        info+="Filesystem information not available\n\n"
    fi
    
    # Block Devices
    info+="BLOCK DEVICES\n"
    info+="─────────────────────────────────────\n"
    if command -v lsblk &>/dev/null; then
        local block_devices
        block_devices=$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null)
        if [[ -n "$block_devices" ]]; then
            info+="$block_devices\n\n"
        else
            info+="Block device information not available\n\n"
        fi
    fi
    
    # Disk Information
    info+="PHYSICAL DISKS\n"
    info+="─────────────────────────────────────\n"
    if [[ -d /sys/block ]]; then
        for disk in /sys/block/sd* /sys/block/nvme* /sys/block/hd*; do
            if [[ -d "$disk" ]]; then
                local disk_name size model
                disk_name=$(basename "$disk")
                
                # Get size
                if [[ -f "$disk/size" ]]; then
                    local sectors
                    sectors=$(cat "$disk/size" 2>/dev/null) || sectors="0"
                    if [[ "$sectors" != "0" ]]; then
                        size=$(echo "scale=2; $sectors * 512 / 1024 / 1024 / 1024" | bc 2>/dev/null) || size="Unknown"
                        size="${size} GB"
                    else
                        size="Unknown"
                    fi
                else
                    size="Unknown"
                fi
                
                # Get model
                if [[ -f "$disk/device/model" ]]; then
                    model=$(cat "$disk/device/model" 2>/dev/null | tr -d ' \t\n\r' 2>/dev/null) || model="Unknown"
                else
                    model="Unknown"
                fi
                
                info+="/dev/$disk_name: $size ($model)\n"
            fi
        done
        info+="\n"
    fi
    
    # SMART Information (if available)
    if command -v smartctl &>/dev/null; then
        info+="SMART STATUS\n"
        info+="─────────────────────────────────────\n"
        for disk in /dev/sd? /dev/nvme?n?; do
            if [[ -e "$disk" ]]; then
                local smart_status
                smart_status=$(smartctl -H "$disk" 2>/dev/null | grep "SMART overall-health" | awk '{print $6}' 2>/dev/null) || smart_status="Unknown"
                info+="$disk: $smart_status\n"
            fi
        done
        info+="\n"
    fi
    
    # Mount Information
    info+="MOUNT POINTS\n"
    info+="─────────────────────────────────────\n"
    local mount_info
    mount_info=$(mount 2>/dev/null | grep -E '^/dev/' | awk '{print $1 " on " $3 " type " $5}' 2>/dev/null)
    if [[ -n "$mount_info" ]]; then
        info+="$mount_info\n\n"
    else
        info+="Mount information not available\n\n"
    fi
    
    # I/O Statistics
    if [[ -f /proc/diskstats ]]; then
        info+="DISK I/O STATISTICS\n"
        info+="─────────────────────────────────────\n"
        local io_stats
        io_stats=$(awk '$3 ~ /^(sd|nvme|hd)/ {printf "%-10s: %10s reads, %10s writes\n", $3, $4, $8}' /proc/diskstats 2>/dev/null | head -10)
        if [[ -n "$io_stats" ]]; then
            info+="$io_stats\n"
        else
            info+="I/O statistics not available\n"
        fi
    fi
    
    ui_info "Storage & Disk Details" "$info"
    return 0
}

show_network_details() {
    log "Starting show_network_details function"
    
    local info="NETWORK & CONNECTIVITY DETAILS\n"
    info+="═══════════════════════════════════════\n\n"
    
    # Network Interfaces
    info+="NETWORK INTERFACES\n"
    info+="─────────────────────────────────────\n"
    if command -v ip &>/dev/null; then
        local interfaces
        interfaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2 " (" $3 ")"}' 2>/dev/null)
        if [[ -n "$interfaces" ]]; then
            info+="$interfaces\n\n"
        else
            info+="No interfaces detected\n\n"
        fi
    fi
    
    # IP Addresses
    info+="IP ADDRESSES\n"
    info+="─────────────────────────────────────\n"
    if command -v ip &>/dev/null; then
        local ip_addresses
        ip_addresses=$(ip -o addr show 2>/dev/null | awk '{print $2 ": " $4}' | grep -v "127.0.0.1\|::1" 2>/dev/null)
        if [[ -n "$ip_addresses" ]]; then
            info+="$ip_addresses\n\n"
        else
            info+="No IP addresses configured\n\n"
        fi
    fi
    
    # Routing Information
    info+="ROUTING TABLE\n"
    info+="─────────────────────────────────────\n"
    if command -v ip &>/dev/null; then
        local routes
        routes=$(ip route show 2>/dev/null | head -10 2>/dev/null)
        if [[ -n "$routes" ]]; then
            info+="$routes\n\n"
        else
            info+="No routes configured\n\n"
        fi
    fi
    
    # DNS Configuration
    info+="DNS CONFIGURATION\n"
    info+="─────────────────────────────────────\n"
    if [[ -f /etc/resolv.conf ]]; then
        local dns_servers
        dns_servers=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print "Nameserver: " $2}' 2>/dev/null)
        if [[ -n "$dns_servers" ]]; then
            info+="$dns_servers\n"
        else
            info+="No DNS servers configured\n"
        fi
        
        local search_domains
        search_domains=$(grep "^search" /etc/resolv.conf 2>/dev/null | cut -d' ' -f2- 2>/dev/null)
        [[ -n "$search_domains" ]] && info+="Search domains: $search_domains\n"
        info+="\n"
    fi
    
    # Network Statistics
    info+="NETWORK STATISTICS\n"
    info+="─────────────────────────────────────\n"
    if [[ -f /proc/net/dev ]]; then
        local net_stats
        net_stats=$(awk 'NR>2 && $1 !~ /lo:/ {gsub(/:/, "", $1); printf "%-10s: RX %10s bytes, TX %10s bytes\n", $1, $2, $10}' /proc/net/dev 2>/dev/null | head -10)
        if [[ -n "$net_stats" ]]; then
            info+="$net_stats\n\n"
        else
            info+="Network statistics not available\n\n"
        fi
    fi
    
    # Connectivity Test
    info+="CONNECTIVITY TEST\n"
    info+="─────────────────────────────────────\n"
    local internet_status ping_time
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        internet_status="Connected"
        ping_time=$(ping -c 1 8.8.8.8 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}' 2>/dev/null) || ping_time="Unknown"
        info+="Internet: $internet_status (ping: ${ping_time}ms)\n"
    else
        internet_status="Disconnected"
        info+="Internet: $internet_status\n"
    fi
    
    ui_info "Network & Connectivity Details" "$info"
    return 0
}

show_graphics_details() {
    log "Starting show_graphics_details function"
    
    local info="GRAPHICS & DISPLAY INFORMATION\n"
    info+="═══════════════════════════════════════\n\n"
    
    # GPU Information
    info+="GRAPHICS CARDS\n"
    info+="─────────────────────────────────────\n"
    local gpu_info=""
    if command -v lspci &>/dev/null; then
        gpu_info=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | sed 's/^[0-9a-f:.]* //' 2>/dev/null)
        if [[ -n "$gpu_info" ]]; then
            info+="$gpu_info\n\n"
        else
            info+="No PCI graphics devices detected\n\n"
        fi
    fi
    
    # Display Information
    info+="CONNECTED DISPLAYS\n"
    info+="─────────────────────────────────────\n"
    local display_info=""
    
    # Try xrandr first (X11)
    if command -v xrandr &>/dev/null && [[ -n "$DISPLAY" ]]; then
        display_info=$(xrandr 2>/dev/null | grep " connected" | awk '{print $1 " - " $3 " " $4}' 2>/dev/null)
        if [[ -n "$display_info" ]]; then
            info+="$display_info\n\n"
        fi
    fi
    
    # Fallback to DRM
    if [[ -z "$display_info" ]] && [[ -d /sys/class/drm ]]; then
        for connector in /sys/class/drm/card*/card*-*/status; do
            if [[ -f "$connector" ]]; then
                local status connector_name
                status=$(cat "$connector" 2>/dev/null)
                connector_name=$(basename "$(dirname "$connector")" | sed 's/card[0-9]*-//')
                
                if [[ "$status" == "connected" ]]; then
                    local modes_file="$(dirname "$connector")/modes"
                    local resolution="Unknown"
                    if [[ -f "$modes_file" ]]; then
                        resolution=$(head -1 "$modes_file" 2>/dev/null) || resolution="Unknown"
                    fi
                    info+="$connector_name - $resolution\n"
                fi
            fi
        done
        info+="\n"
    fi
    
    [[ -z "$display_info" ]] && info+="No connected displays detected\n\n"
    
    # OpenGL Information
    if command -v glxinfo &>/dev/null && [[ -n "$DISPLAY" ]]; then
        info+="OPENGL INFORMATION\n"
        info+="─────────────────────────────────────\n"
        local gl_vendor gl_renderer gl_version
        gl_vendor=$(glxinfo 2>/dev/null | grep "OpenGL vendor" | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || gl_vendor="Unknown"
        gl_renderer=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || gl_renderer="Unknown"
        gl_version=$(glxinfo 2>/dev/null | grep "OpenGL version" | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || gl_version="Unknown"
        
        info+="Vendor: $gl_vendor\n"
        info+="Renderer: $gl_renderer\n"
        info+="Version: $gl_version\n\n"
    fi
    
    # Framebuffer Information
    if [[ -d /sys/class/graphics ]]; then
        info+="FRAMEBUFFER DEVICES\n"
        info+="─────────────────────────────────────\n"
        for fb in /sys/class/graphics/fb*/virtual_size; do
            if [[ -f "$fb" ]]; then
                local fb_name resolution
                fb_name=$(basename "$(dirname "$fb")")
                resolution=$(cat "$fb" 2>/dev/null | tr ',' 'x' 2>/dev/null) || resolution="Unknown"
                info+="$fb_name: ${resolution}\n"
            fi
        done
        info+="\n"
    fi
    
    ui_info "Graphics & Display Information" "$info"
    return 0
}

show_audio_details() {
    log "Starting show_audio_details function"
    
    local info="AUDIO & SOUND DEVICES\n"
    info+="═══════════════════════════════════════\n\n"
    
    # ALSA Sound Cards
    if [[ -f /proc/asound/cards ]]; then
        info+="ALSA SOUND CARDS\n"
        info+="─────────────────────────────────────\n"
        local alsa_cards
        alsa_cards=$(cat /proc/asound/cards 2>/dev/null)
        if [[ -n "$alsa_cards" ]]; then
            info+="$alsa_cards\n\n"
        else
            info+="No ALSA sound cards detected\n\n"
        fi
    fi
    
    # PCI Audio Devices
    if command -v lspci &>/dev/null; then
        info+="PCI AUDIO CONTROLLERS\n"
        info+="─────────────────────────────────────\n"
        local pci_audio
        pci_audio=$(lspci 2>/dev/null | grep -i "audio\|sound" | sed 's/^[0-9a-f:.]* //' 2>/dev/null)
        if [[ -n "$pci_audio" ]]; then
            info+="$pci_audio\n\n"
        else
            info+="No PCI audio devices detected\n\n"
        fi
    fi
    
    # Audio Devices
    if [[ -d /proc/asound ]]; then
        info+="AUDIO DEVICE DETAILS\n"
        info+="─────────────────────────────────────\n"
        for card in /proc/asound/card*/id; do
            if [[ -f "$card" ]]; then
                local card_id card_name
                card_id=$(cat "$card" 2>/dev/null) || card_id="Unknown"
                card_name=$(cat "$(dirname "$card")/id" 2>/dev/null) || card_name="Unknown"
                info+="Card: $card_id\n"
                
                # Get PCM devices for this card
                local pcm_devices
                pcm_devices=$(find "$(dirname "$card")" -name "pcm*p" -o -name "pcm*c" 2>/dev/null | wc -l 2>/dev/null) || pcm_devices="0"
                info+="PCM devices: $pcm_devices\n\n"
            fi
        done
    fi
    
    # PulseAudio Information
    if command -v pactl &>/dev/null; then
        info+="PULSEAUDIO INFORMATION\n"
        info+="─────────────────────────────────────\n"
        local pa_sinks pa_sources
        pa_sinks=$(pactl list short sinks 2>/dev/null | wc -l 2>/dev/null) || pa_sinks="0"
        pa_sources=$(pactl list short sources 2>/dev/null | wc -l 2>/dev/null) || pa_sources="0"
        
        info+="Audio sinks: $pa_sinks\n"
        info+="Audio sources: $pa_sources\n\n"
        
        # Default sink
        local default_sink
        default_sink=$(pactl get-default-sink 2>/dev/null) || default_sink="Unknown"
        info+="Default sink: $default_sink\n\n"
    fi
    
    ui_info "Audio & Sound Devices" "$info"
    return 0
}

show_package_details() {
    log "Starting show_package_details function"
    
    local info="PACKAGE MANAGERS & SOFTWARE\n"
    info+="═══════════════════════════════════════\n\n"
    
    # APT Package Manager
    info+="APT PACKAGE MANAGER\n"
    info+="─────────────────────────────────────\n"
    local apt_installed apt_upgradable apt_auto_removable
    apt_installed=$(dpkg -l 2>/dev/null | grep -c "^ii" 2>/dev/null) || apt_installed="0"
    apt_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" 2>/dev/null) || apt_upgradable="0"
    apt_auto_removable=$(apt autoremove --dry-run 2>/dev/null | grep -c "^Remv" 2>/dev/null) || apt_auto_removable="0"
    
    info+="Installed packages: $apt_installed\n"
    info+="Upgradable packages: $apt_upgradable\n"
    info+="Auto-removable packages: $apt_auto_removable\n\n"
    
    # Snap Package Manager
    if command -v snap &>/dev/null; then
        info+="SNAP PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        local snap_installed snap_refreshable
        snap_installed=$(snap list 2>/dev/null | tail -n +2 | wc -l 2>/dev/null) || snap_installed="0"
        snap_refreshable=$(snap refresh --list 2>/dev/null | tail -n +2 | wc -l 2>/dev/null) || snap_refreshable="0"
        
        info+="Installed snaps: $snap_installed\n"
        info+="Refreshable snaps: $snap_refreshable\n\n"
    else
        info+="SNAP PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        info+="Snap not available\n\n"
    fi
    
    # Flatpak Package Manager
    if command -v flatpak &>/dev/null; then
        info+="FLATPAK PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        local flatpak_apps flatpak_updates flatpak_remotes
        flatpak_apps=$(flatpak list --app 2>/dev/null | wc -l 2>/dev/null) || flatpak_apps="0"
        flatpak_updates=$(flatpak remote-ls --updates 2>/dev/null | wc -l 2>/dev/null) || flatpak_updates="0"
        flatpak_remotes=$(flatpak remotes 2>/dev/null | tail -n +2 | wc -l 2>/dev/null) || flatpak_remotes="0"
        
        info+="Installed applications: $flatpak_apps\n"
        info+="Available updates: $flatpak_updates\n"
        info+="Configured remotes: $flatpak_remotes\n\n"
    else
        info+="FLATPAK PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        info+="Flatpak not available\n\n"
    fi
    
    # Python Package Manager
    if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
        info+="PYTHON PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        local pip_packages
        pip_packages=$(pip3 list 2>/dev/null | tail -n +3 | wc -l 2>/dev/null) || pip_packages="0"
        [[ "$pip_packages" == "0" ]] && pip_packages=$(pip list 2>/dev/null | tail -n +3 | wc -l 2>/dev/null) || pip_packages="0"
        
        info+="Installed packages: $pip_packages\n\n"
    else
        info+="PYTHON PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        info+="Python pip not available\n\n"
    fi
    
    # Node.js Package Manager
    if command -v npm &>/dev/null; then
        info+="NODE.JS PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        local npm_global npm_version
        npm_global=$(npm list -g --depth=0 2>/dev/null | grep -c "├──\|└──" 2>/dev/null) || npm_global="0"
        npm_version=$(npm --version 2>/dev/null) || npm_version="Unknown"
        
        info+="Global packages: $npm_global\n"
        info+="NPM version: $npm_version\n\n"
    else
        info+="NODE.JS PACKAGE MANAGER\n"
        info+="─────────────────────────────────────\n"
        info+="Node.js npm not available\n\n"
    fi
    
    # Ultrabunt Package Statistics
    info+="ULTRABUNT PACKAGE STATISTICS\n"
    info+="─────────────────────────────────────\n"
    local total_pkgs=${#PACKAGES[@]}
    local installed_count=0
    
    for name in "${!PACKAGES[@]}"; do
        if is_package_installed "$name" 2>/dev/null; then
            ((installed_count++)) 2>/dev/null || true
        fi
    done 2>/dev/null || true
    
    info+="Tracked packages: $total_pkgs\n"
    info+="Installed packages: $installed_count\n"
    info+="Available packages: $((total_pkgs - installed_count))\n"
    
    ui_info "Package Managers & Software" "$info"
    return 0
}

show_legacy_system_info() {
    log "Starting show_legacy_system_info function"
    
    local info="COMPLETE SYSTEM INFORMATION\n"
    info+="═══════════════════════════════════════\n\n"
    
    # OS Info
    if [[ -f /etc/os-release ]]; then
        local os_name="Unknown"
        local os_version="N/A"
        
        while IFS='=' read -r key value 2>/dev/null; do
            case "$key" in
                PRETTY_NAME) os_name="${value//\"/}" ;;
                VERSION) os_version="${value//\"/}" ;;
            esac
        done < /etc/os-release 2>/dev/null || true
        
        info+="OS: $os_name\n"
        info+="Version: $os_version\n"
    fi
    
    # Kernel
    local kernel_version
    kernel_version=$(uname -r 2>/dev/null) || kernel_version="Unknown"
    info+="Kernel: $kernel_version\n"
    
    # System Model
    local system_model="Unknown"
    local system_vendor="Unknown"
    
    if [[ -f /sys/class/dmi/id/product_name ]]; then
        system_model=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\0' 2>/dev/null) || system_model="Unknown"
    fi
    
    if [[ -f /sys/class/dmi/id/sys_vendor ]]; then
        system_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -d '\0' 2>/dev/null) || system_vendor="Unknown"
    fi
    
    if [[ "$system_vendor" != "Unknown" && "$system_model" != "Unknown" ]]; then
        info+="System: $system_vendor $system_model\n"
    elif [[ "$system_model" != "Unknown" ]]; then
        info+="System: $system_model\n"
    else
        info+="System: Model information not available\n"
    fi
    
    info+="\n"
    
    # Hardware Summary
    info+="HARDWARE SUMMARY\n"
    info+="─────────────────────────────────────\n"
    
    # CPU
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_info cpu_cores
        cpu_info=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_info="Unknown"
        cpu_cores=$(nproc 2>/dev/null) || cpu_cores="Unknown"
        info+="CPU: $cpu_info ($cpu_cores cores)\n"
    fi
    
    # Memory
    if [[ -f /proc/meminfo ]]; then
        local mem_total mem_available
        mem_total=$(grep "MemTotal:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}' 2>/dev/null) || mem_total="Unknown"
        mem_available=$(grep "MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}' 2>/dev/null) || mem_available="Unknown"
        if [[ "$mem_total" != "Unknown" && "$mem_available" != "Unknown" ]]; then
            local mem_used=$((mem_total - mem_available))
            info+="Memory: ${mem_used}MB used / ${mem_total}MB total\n"
        fi
    fi
    
    # Storage
    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1 | awk '{print $3 " used / " $2 " total (" $5 " full)"}' 2>/dev/null) || disk_info="Information not available"
    info+="Storage: $disk_info\n"
    
    # Network
    local primary_ip
    primary_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' 2>/dev/null) || primary_ip="Unknown"
    info+="Primary IP: $primary_ip\n"
    
    # Uptime
    local uptime_info
    uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' 2>/dev/null) || uptime_info="Unknown"
    info+="Uptime: $uptime_info\n\n"
    
    # Package Summary
    info+="PACKAGE SUMMARY\n"
    info+="─────────────────────────────────────\n"
    local apt_count snap_count flatpak_count
    apt_count=$(dpkg -l 2>/dev/null | grep -c "^ii" 2>/dev/null) || apt_count="0"
    snap_count=$(snap list 2>/dev/null | tail -n +2 | wc -l 2>/dev/null) || snap_count="0"
    flatpak_count=$(flatpak list --app 2>/dev/null | wc -l 2>/dev/null) || flatpak_count="0"
    
    info+="APT packages: $apt_count\n"
    info+="Snap packages: $snap_count\n"
    info+="Flatpak apps: $flatpak_count\n\n"
    
    # Ultrabunt Stats
    info+="ULTRABUNT STATISTICS\n"
    info+="─────────────────────────────────────\n"
    local total_pkgs=${#PACKAGES[@]}
    local installed_count=0
    
    for name in "${!PACKAGES[@]}"; do
        if is_package_installed "$name" 2>/dev/null; then
            ((installed_count++)) 2>/dev/null || true
        fi
    done 2>/dev/null || true
    
    info+="Tracked packages: $total_pkgs\n"
    info+="Installed: $installed_count\n"
    info+="Available: $((total_pkgs - installed_count))\n"
    
    ui_info "Complete System Information" "$info"
    return 0
}

show_hardware_details() {
    log "Starting show_hardware_details function"
    
    local info="HARDWARE & SYSTEM INFORMATION\n"
    info+="═══════════════════════════════════════\n\n"
    
    # System Information
    info+="SYSTEM INFORMATION\n"
    info+="─────────────────────────────────────\n"
    
    local system_vendor system_model system_version system_serial bios_vendor bios_version bios_date
    
    # Try DMI first
    if command -v dmidecode &>/dev/null; then
        system_vendor=$(dmidecode -s system-manufacturer 2>/dev/null | head -1 2>/dev/null) || system_vendor="Unknown"
        system_model=$(dmidecode -s system-product-name 2>/dev/null | head -1 2>/dev/null) || system_model="Unknown"
        system_version=$(dmidecode -s system-version 2>/dev/null | head -1 2>/dev/null) || system_version="Unknown"
        system_serial=$(dmidecode -s system-serial-number 2>/dev/null | head -1 2>/dev/null) || system_serial="Unknown"
        bios_vendor=$(dmidecode -s bios-vendor 2>/dev/null | head -1 2>/dev/null) || bios_vendor="Unknown"
        bios_version=$(dmidecode -s bios-version 2>/dev/null | head -1 2>/dev/null) || bios_version="Unknown"
        bios_date=$(dmidecode -s bios-release-date 2>/dev/null | head -1 2>/dev/null) || bios_date="Unknown"
    fi
    
    # Fallback to /sys/class/dmi/id/
    [[ "$system_vendor" == "Unknown" ]] && [[ -f /sys/class/dmi/id/sys_vendor ]] && system_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -d '\0' 2>/dev/null) || system_vendor="Unknown"
    [[ "$system_model" == "Unknown" ]] && [[ -f /sys/class/dmi/id/product_name ]] && system_model=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\0' 2>/dev/null) || system_model="Unknown"
    [[ "$bios_vendor" == "Unknown" ]] && [[ -f /sys/class/dmi/id/bios_vendor ]] && bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null | tr -d '\0' 2>/dev/null) || bios_vendor="Unknown"
    [[ "$bios_version" == "Unknown" ]] && [[ -f /sys/class/dmi/id/bios_version ]] && bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null | tr -d '\0' 2>/dev/null) || bios_version="Unknown"
    [[ "$bios_date" == "Unknown" ]] && [[ -f /sys/class/dmi/id/bios_date ]] && bios_date=$(cat /sys/class/dmi/id/bios_date 2>/dev/null | tr -d '\0' 2>/dev/null) || bios_date="Unknown"
    

    
    info+="Manufacturer: $system_vendor\n"
    info+="Model: $system_model\n"
    info+="Version: $system_version\n"
    info+="Serial Number: $system_serial\n\n"
    
    info+="BIOS/UEFI INFORMATION\n"
    info+="─────────────────────────────────────\n"
    info+="Vendor: $bios_vendor\n"
    info+="Version: $bios_version\n"
    info+="Release Date: $bios_date\n\n"
    
    # Motherboard Information
    if command -v dmidecode &>/dev/null; then
        info+="MOTHERBOARD INFORMATION\n"
        info+="─────────────────────────────────────\n"
        local mb_manufacturer mb_product mb_version mb_serial
        mb_manufacturer=$(dmidecode -s baseboard-manufacturer 2>/dev/null | head -1 2>/dev/null) || mb_manufacturer="Unknown"
        mb_product=$(dmidecode -s baseboard-product-name 2>/dev/null | head -1 2>/dev/null) || mb_product="Unknown"
        mb_version=$(dmidecode -s baseboard-version 2>/dev/null | head -1 2>/dev/null) || mb_version="Unknown"
        mb_serial=$(dmidecode -s baseboard-serial-number 2>/dev/null | head -1 2>/dev/null) || mb_serial="Unknown"
        
        info+="Manufacturer: $mb_manufacturer\n"
        info+="Product: $mb_product\n"
        info+="Version: $mb_version\n"
        info+="Serial: $mb_serial\n\n"
    fi
    
    # PCI Devices
    if command -v lspci &>/dev/null; then
        info+="PCI DEVICES\n"
        info+="─────────────────────────────────────\n"
        local pci_devices
        pci_devices=$(lspci 2>/dev/null | head -15 | sed 's/^[0-9a-f:.]* //' 2>/dev/null)
        if [[ -n "$pci_devices" ]]; then
            info+="$pci_devices\n"
            local pci_count
            pci_count=$(lspci 2>/dev/null | wc -l 2>/dev/null) || pci_count="0"
            [[ "$pci_count" -gt 15 ]] && info+="... and $((pci_count - 15)) more devices\n"
        else
            info+="PCI device information not available\n"
        fi
        info+="\n"
    fi
    
    # System Uptime and Load
    info+="SYSTEM STATUS\n"
    info+="─────────────────────────────────────\n"
    local uptime_info load_avg boot_time
    uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' 2>/dev/null) || uptime_info="Unknown"
    load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' 2>/dev/null | sed 's/^ *//' 2>/dev/null) || load_avg="Unknown"
    boot_time=$(who -b 2>/dev/null | awk '{print $3 " " $4}' 2>/dev/null) || boot_time="Unknown"
    
    info+="Uptime: $uptime_info\n"
    info+="Load Average:$load_avg\n"
    info+="Boot Time: $boot_time\n\n"
    
    # Process Information
    local process_count zombie_count
    process_count=$(ps aux 2>/dev/null | wc -l 2>/dev/null) || process_count="Unknown"
    [[ "$process_count" != "Unknown" ]] && process_count=$((process_count - 1))
    zombie_count=$(ps aux 2>/dev/null | awk '$8 ~ /^Z/ {count++} END {print count+0}' 2>/dev/null) || zombie_count="0"
    
    info+="Running Processes: $process_count\n"
    info+="Zombie Processes: $zombie_count\n"
    
    ui_info "Hardware & System Information" "$info"
    return 0
}

show_system_info() {
    log "Starting enhanced show_system_info function"
    
    while true; do
        local menu_items=()
        
        # Check if running as root/sudo for enhanced information
        local sudo_warning=""
        if [[ $EUID -ne 0 ]]; then
            sudo_warning="⚠️  Run this script as superuser (sudo) to see the magic inside!\n\n"
        fi
        
        # Get key system info for overview
        local os_name="Unknown"
        local os_version="N/A"
        if [[ -f /etc/os-release ]]; then
            while IFS='=' read -r key value 2>/dev/null; do
                case "$key" in
                    PRETTY_NAME) os_name="${value//\"/}" ;;
                    VERSION) os_version="${value//\"/}" ;;
                esac
            done < /etc/os-release 2>/dev/null || true
        fi
        
        local kernel_version
        kernel_version=$(uname -r 2>/dev/null) || kernel_version="Unknown"
        
        # Enhanced CPU information extraction
        local cpu_model cpu_cores cpu_threads cpu_freq cpu_max_freq cpu_family
        if [[ -f /proc/cpuinfo ]]; then
            cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_model="Unknown"
            cpu_cores=$(grep "cpu cores" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_cores="Unknown"
            cpu_threads=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null) || cpu_threads="Unknown"
            cpu_freq=$(grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_freq="Unknown"
            cpu_family=$(grep "cpu family" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_family="Unknown"
            
            # Fallback for cores if "cpu cores" not found
            if [[ "$cpu_cores" == "Unknown" ]]; then
                cpu_cores=$(grep "siblings" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_cores="$cpu_threads"
            fi
            
            # Get max frequency from lscpu if available
            if command -v lscpu &>/dev/null; then
                cpu_max_freq=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{print $4}' 2>/dev/null) || cpu_max_freq="Unknown"
                [[ "$cpu_max_freq" != "Unknown" ]] && cpu_max_freq="${cpu_max_freq} MHz"
                
                # Also try to get model from lscpu if /proc/cpuinfo failed
                if [[ "$cpu_model" == "Unknown" ]]; then
                    cpu_model=$(lscpu 2>/dev/null | grep "Model name:" | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_model="Unknown"
                fi
            else
                cpu_max_freq="Unknown"
            fi
            
            [[ "$cpu_freq" != "Unknown" ]] && cpu_freq="${cpu_freq} MHz"
        else
            cpu_model="Unknown"
            cpu_cores="Unknown"
            cpu_threads="Unknown"
            cpu_freq="Unknown"
            cpu_max_freq="Unknown"
            cpu_family="Unknown"
        fi
        
        # System model and serial information with enhanced detection
        local system_model system_serial system_manufacturer system_family system_version
        if command -v dmidecode &>/dev/null && [[ $EUID -eq 0 ]]; then
            system_manufacturer=$(dmidecode -s system-manufacturer 2>/dev/null | head -1 2>/dev/null) || system_manufacturer="Unknown"
            system_model=$(dmidecode -s system-product-name 2>/dev/null | head -1 2>/dev/null) || system_model="Unknown"
            system_serial=$(dmidecode -s system-serial-number 2>/dev/null | head -1 2>/dev/null) || system_serial="Unknown"
            system_family=$(dmidecode -s system-family 2>/dev/null | head -1 2>/dev/null) || system_family="Unknown"
            system_version=$(dmidecode -s system-version 2>/dev/null | head -1 2>/dev/null) || system_version="Unknown"
        else
            # Fallback methods for non-root users
            system_manufacturer=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) || system_manufacturer="Unknown"
            system_model=$(cat /sys/class/dmi/id/product_name 2>/dev/null) || system_model="Unknown"
            system_serial=$(cat /sys/class/dmi/id/product_serial 2>/dev/null) || system_serial="Unknown"
            system_family=$(cat /sys/class/dmi/id/product_family 2>/dev/null) || system_family="Unknown"
            system_version=$(cat /sys/class/dmi/id/product_version 2>/dev/null) || system_version="Unknown"
        fi
        
        # Memory information with detailed specs - convert to GB for consistency
        local memory_total memory_used memory_available memory_speed memory_type memory_slots
        if command -v free &>/dev/null; then
            # Get memory in bytes and convert to GB for cleaner display
            local mem_total_bytes mem_used_bytes mem_available_bytes
            mem_total_bytes=$(free -b 2>/dev/null | grep "Mem:" | awk '{print $2}' 2>/dev/null) || mem_total_bytes="0"
            mem_used_bytes=$(free -b 2>/dev/null | grep "Mem:" | awk '{print $3}' 2>/dev/null) || mem_used_bytes="0"
            mem_available_bytes=$(free -b 2>/dev/null | grep "Mem:" | awk '{print $7}' 2>/dev/null) || mem_available_bytes="0"
            
            # Convert bytes to GB (decimal) for cleaner display
            if [[ "$mem_total_bytes" -gt 0 ]]; then
                memory_total=$(awk "BEGIN {printf \"%.1fGB\", $mem_total_bytes/1000000000}")
            else
                memory_total="Unknown"
            fi
            
            if [[ "$mem_used_bytes" -gt 0 ]]; then
                memory_used=$(awk "BEGIN {printf \"%.1fGB\", $mem_used_bytes/1000000000}")
            else
                memory_used="Unknown"
            fi
            
            if [[ "$mem_available_bytes" -gt 0 ]]; then
                memory_available=$(awk "BEGIN {printf \"%.1fGB\", $mem_available_bytes/1000000000}")
            else
                memory_available="Unknown"
            fi
        else
            memory_total="Unknown"
            memory_used="Unknown"
            memory_available="Unknown"
        fi
        
        if command -v dmidecode &>/dev/null && [[ $EUID -eq 0 ]]; then
            # Get memory type - try multiple approaches
            memory_type=$(dmidecode -t memory 2>/dev/null | grep -E "^\s*Type:" | grep -v "Unknown" | grep -v "Error Correction Type" | head -1 | awk '{print $2}' 2>/dev/null) || memory_type="Unknown"
            if [[ "$memory_type" == "Unknown" ]]; then
                memory_type=$(dmidecode -t 17 2>/dev/null | grep -E "^\s*Type:" | grep -v "Unknown" | head -1 | awk '{print $2}' 2>/dev/null) || memory_type="Unknown"
            fi
            
            # Get memory speed - try multiple approaches
            memory_speed=$(dmidecode -t memory 2>/dev/null | grep -E "^\s*Speed:" | grep -v "Unknown" | head -1 | awk '{print $2, $3}' 2>/dev/null) || memory_speed="Unknown"
            if [[ "$memory_speed" == "Unknown" ]]; then
                memory_speed=$(dmidecode -t 17 2>/dev/null | grep -E "^\s*Speed:" | grep -v "Unknown" | head -1 | awk '{print $2, $3}' 2>/dev/null) || memory_speed="Unknown"
            fi
            
            # Count memory slots with actual memory
            memory_slots=$(dmidecode -t memory 2>/dev/null | grep -E "^\s*Size:" | grep -v "No Module Installed" | wc -l 2>/dev/null) || memory_slots="Unknown"
            if [[ "$memory_slots" == "0" || "$memory_slots" == "Unknown" ]]; then
                memory_slots=$(dmidecode -t 17 2>/dev/null | grep -E "^\s*Size:" | grep -v "No Module Installed" | wc -l 2>/dev/null) || memory_slots="Unknown"
            fi
        else
            memory_type="Unknown"
            memory_speed="Unknown"
            memory_slots="Unknown"
        fi
        
        # Storage information with usage percentage
        local storage_total storage_used storage_available storage_usage_percent storage_model storage_type
        if command -v df &>/dev/null; then
            local df_output
            df_output=$(df -h / 2>/dev/null | tail -1)
            storage_total=$(echo "$df_output" | awk '{print $2}' 2>/dev/null) || storage_total="Unknown"
            storage_used=$(echo "$df_output" | awk '{print $3}' 2>/dev/null) || storage_used="Unknown"
            storage_available=$(echo "$df_output" | awk '{print $4}' 2>/dev/null) || storage_available="Unknown"
            storage_usage_percent=$(echo "$df_output" | awk '{print $5}' 2>/dev/null) || storage_usage_percent="Unknown"
        else
            storage_total="Unknown"
            storage_used="Unknown"
            storage_available="Unknown"
            storage_usage_percent="Unknown"
        fi
        
        # Enhanced storage model detection with multiple devices
        local storage_devices=""
        if command -v lsblk &>/dev/null; then
            # Get all block devices with size and model info
            local block_devices=$(lsblk -dno NAME,SIZE,MODEL 2>/dev/null | grep -E "^(sd|hd|nvme|mmcblk)" 2>/dev/null)
            if [[ -n "$block_devices" ]]; then
                while IFS= read -r line; do
                    local device_name=$(echo "$line" | awk '{print $1}')
                    local device_size=$(echo "$line" | awk '{print $2}')
                    local device_model=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
                    
                    if [[ -n "$device_name" && -n "$device_size" ]]; then
                        if [[ -z "$device_model" || "$device_model" == " " ]]; then
                            device_model="Unknown Model"
                        fi
                        if [[ -n "$storage_devices" ]]; then
                            storage_devices="$storage_devices, "
                        fi
                        storage_devices="$storage_devices$device_name ($device_size, $device_model)"
                    fi
                done <<< "$block_devices"
            fi
        fi
        
        # Fallback to single device detection if no devices found
        if [[ -z "$storage_devices" ]]; then
            if [[ -f /sys/block/sda/device/model ]]; then
                storage_model=$(cat /sys/block/sda/device/model 2>/dev/null | tr -d ' \t\n\r' 2>/dev/null) || storage_model="Unknown"
            elif command -v lsblk &>/dev/null; then
                storage_model=$(lsblk -d -o MODEL 2>/dev/null | grep -v "MODEL" | head -1 | tr -d ' \t\n\r' 2>/dev/null) || storage_model="Unknown"
            else
                storage_model="Unknown"
            fi
            storage_devices="Primary: $storage_model"
        fi
        
        # Detect storage type (SSD/HDD)
        if [[ -f /sys/block/sda/queue/rotational ]]; then
            local rotational
            rotational=$(cat /sys/block/sda/queue/rotational 2>/dev/null)
            if [[ "$rotational" == "0" ]]; then
                storage_type="SSD"
            else
                storage_type="HDD"
            fi
        else
            storage_type="Unknown"
        fi
        
        # GPU information
        local gpu_info
        if command -v lspci &>/dev/null; then
            gpu_info=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | sed 's/^[0-9a-f:.]* //' | head -1 2>/dev/null) || gpu_info="Unknown"
        else
            gpu_info="Unknown"
        fi
        
        # Enhanced port detection with proper formatting - avoid double counting
        local usb_ports_list display_ports_list audio_ports_list thunderbolt_count
        usb_ports_list=""
        display_ports_list=""
        audio_ports_list=""
        thunderbolt_count="0"
        
        if command -v dmidecode &>/dev/null && [[ $EUID -eq 0 ]]; then
            # Get unique port connectors from dmidecode to avoid duplicates
            local port_connectors
            port_connectors=$(dmidecode -t 8 2>/dev/null | grep -E "External Reference Designator|Port Type" | paste - - 2>/dev/null)
            
            # Count USB ports more accurately
            local usb2_count usb3_count usbc_count
            usb2_count=$(echo "$port_connectors" | grep -i "USB.*2\|USB" | grep -v "USB.*3\|USB-C" | wc -l 2>/dev/null) || usb2_count="0"
            usb3_count=$(echo "$port_connectors" | grep -i "USB.*3" | wc -l 2>/dev/null) || usb3_count="0"
            usbc_count=$(echo "$port_connectors" | grep -i "USB-C\|Type-C" | wc -l 2>/dev/null) || usbc_count="0"
            
            # If dmidecode shows no USB ports, use lsusb as fallback but be conservative
            if [[ "$usb2_count" -eq 0 && "$usb3_count" -eq 0 && "$usbc_count" -eq 0 ]]; then
                if command -v lsusb &>/dev/null; then
                    # Count USB controllers and estimate conservatively
                    local usb_controllers
                    usb_controllers=$(lspci 2>/dev/null | grep -i "usb controller" | wc -l 2>/dev/null) || usb_controllers="0"
                    if [[ "$usb_controllers" -gt 0 ]]; then
                        # Conservative estimate: 1-2 ports per controller
                        usb3_count="$usb_controllers"
                    fi
                fi
            fi
            
            # Format USB ports cleanly
            local usb_parts=()
            [[ "$usb2_count" -gt 0 ]] && usb_parts+=("${usb2_count} x USB 2.0")
            [[ "$usb3_count" -gt 0 ]] && usb_parts+=("${usb3_count} x USB 3.0")
            [[ "$usbc_count" -gt 0 ]] && usb_parts+=("${usbc_count} x USB-C")
            
            if [[ ${#usb_parts[@]} -gt 0 ]]; then
                usb_ports_list=$(IFS=', '; echo "${usb_parts[*]}")
            else
                usb_ports_list="No USB ports detected"
            fi
            
            # Count display ports more accurately
            local hdmi_count mini_dp_count dp_count vga_count
            hdmi_count=$(echo "$port_connectors" | grep -i "HDMI" | wc -l 2>/dev/null) || hdmi_count="0"
            mini_dp_count=$(echo "$port_connectors" | grep -i "Mini.*Display\|Mini.*DP" | wc -l 2>/dev/null) || mini_dp_count="0"
            dp_count=$(echo "$port_connectors" | grep -i "DisplayPort\|Display Port" | grep -v -i "Mini" | wc -l 2>/dev/null) || dp_count="0"
            vga_count=$(echo "$port_connectors" | grep -i "VGA\|D-Sub" | wc -l 2>/dev/null) || vga_count="0"
            
            # Format display ports
            local display_parts=()
            [[ "$hdmi_count" -gt 0 ]] && display_parts+=("${hdmi_count} x HDMI")
            [[ "$mini_dp_count" -gt 0 ]] && display_parts+=("${mini_dp_count} x Mini DisplayPort")
            [[ "$dp_count" -gt 0 ]] && display_parts+=("${dp_count} x DisplayPort")
            [[ "$vga_count" -gt 0 ]] && display_parts+=("${vga_count} x VGA")
            
            if [[ ${#display_parts[@]} -gt 0 ]]; then
                display_ports_list=$(IFS=', '; echo "${display_parts[*]}")
            else
                display_ports_list="No display ports detected"
            fi
            
            # Count Thunderbolt ports accurately
            thunderbolt_count=$(echo "$port_connectors" | grep -i "Thunderbolt" | wc -l 2>/dev/null) || thunderbolt_count="0"
            
            # Count audio ports more accurately
            local audio_count
            audio_count=$(echo "$port_connectors" | grep -i "Audio\|Headphone\|Microphone" | wc -l 2>/dev/null) || audio_count="0"
            [[ "$audio_count" -gt 0 ]] && audio_ports_list="${audio_count} x Audio"
        else
            # Simplified fallback for non-root users
            usb_ports_list="Port detection requires sudo"
            display_ports_list="Port detection requires sudo"
            audio_ports_list="Port detection requires sudo"
        fi
        
        # Network adapter information with connectivity
        local network_adapters internet_status wifi_adapter eth_adapter
        network_adapters=""
        internet_status="❌ No connection"
        wifi_adapter="Not detected"
        eth_adapter="Not detected"
        
        # Check internet connectivity
        if ping -c 1 8.8.8.8 &>/dev/null || ping -c 1 1.1.1.1 &>/dev/null; then
            internet_status="✅ Connected"
        fi
        
        # Detect network adapters
        if command -v ip &>/dev/null; then
            # Check for Wi-Fi adapter
            if ip link show 2>/dev/null | grep -q "wl"; then
                local wifi_interface
                wifi_interface=$(ip link show 2>/dev/null | grep "wl" | head -1 | awk -F: '{print $2}' | tr -d ' ' 2>/dev/null)
                if [[ -n "$wifi_interface" ]]; then
                    wifi_adapter="$wifi_interface (Wi-Fi)"
                    # Check if Wi-Fi is connected
                    if ip addr show "$wifi_interface" 2>/dev/null | grep -q "inet "; then
                        wifi_adapter="$wifi_adapter - Connected"
                    else
                        wifi_adapter="$wifi_adapter - Disconnected"
                    fi
                fi
            fi
            
            # Check for Ethernet adapter
            if ip link show 2>/dev/null | grep -q "en\|eth"; then
                local eth_interface
                eth_interface=$(ip link show 2>/dev/null | grep -E "en|eth" | head -1 | awk -F: '{print $2}' | tr -d ' ' 2>/dev/null)
                if [[ -n "$eth_interface" ]]; then
                    eth_adapter="$eth_interface (Ethernet)"
                    # Check if Ethernet is connected
                    if ip addr show "$eth_interface" 2>/dev/null | grep -q "inet "; then
                        eth_adapter="$eth_adapter - Connected"
                    else
                        eth_adapter="$eth_adapter - Disconnected"
                    fi
                fi
            fi
        fi
        
        # Audio driver information
        local audio_drivers audio_devices
        audio_drivers="Unknown"
        audio_devices="Unknown"
        
        if command -v lspci &>/dev/null; then
            audio_drivers=$(lspci 2>/dev/null | grep -i "audio" | sed 's/^[0-9a-f:.]* //' | head -1 2>/dev/null) || audio_drivers="Unknown"
        fi
        
        if [[ -d /proc/asound ]]; then
            audio_devices=$(cat /proc/asound/cards 2>/dev/null | grep -E "^\s*[0-9]" | wc -l 2>/dev/null) || audio_devices="0"
            [[ "$audio_devices" -gt 0 ]] && audio_devices="${audio_devices} audio device(s)"
        fi
        
        local uptime_info
        uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' 2>/dev/null) || uptime_info="Unknown"
        
        # Get additional comprehensive system information
        local bios_vendor bios_version bios_date mb_manufacturer mb_product mb_version mb_serial
        local apt_count snap_count flatpak_count process_count zombie_count boot_time load_avg
        
        # BIOS/UEFI Information
        if command -v dmidecode &>/dev/null && [[ $EUID -eq 0 ]]; then
            bios_vendor=$(dmidecode -s bios-vendor 2>/dev/null | head -1 2>/dev/null) || bios_vendor="Unknown"
            bios_version=$(dmidecode -s bios-version 2>/dev/null | head -1 2>/dev/null) || bios_version="Unknown"
            bios_date=$(dmidecode -s bios-release-date 2>/dev/null | head -1 2>/dev/null) || bios_date="Unknown"
            mb_manufacturer=$(dmidecode -s baseboard-manufacturer 2>/dev/null | head -1 2>/dev/null) || mb_manufacturer="Unknown"
            mb_product=$(dmidecode -s baseboard-product-name 2>/dev/null | head -1 2>/dev/null) || mb_product="Unknown"
            mb_version=$(dmidecode -s baseboard-version 2>/dev/null | head -1 2>/dev/null) || mb_version="Unknown"
            mb_serial=$(dmidecode -s baseboard-serial-number 2>/dev/null | head -1 2>/dev/null) || mb_serial="Unknown"
        else
            # Fallback to /sys/class/dmi/id/
            [[ -f /sys/class/dmi/id/bios_vendor ]] && bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null | tr -d '\0' 2>/dev/null) || bios_vendor="Unknown"
            [[ -f /sys/class/dmi/id/bios_version ]] && bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null | tr -d '\0' 2>/dev/null) || bios_version="Unknown"
            [[ -f /sys/class/dmi/id/bios_date ]] && bios_date=$(cat /sys/class/dmi/id/bios_date 2>/dev/null | tr -d '\0' 2>/dev/null) || bios_date="Unknown"
            [[ -f /sys/class/dmi/id/board_vendor ]] && mb_manufacturer=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | tr -d '\0' 2>/dev/null) || mb_manufacturer="Unknown"
            [[ -f /sys/class/dmi/id/board_name ]] && mb_product=$(cat /sys/class/dmi/id/board_name 2>/dev/null | tr -d '\0' 2>/dev/null) || mb_product="Unknown"
            [[ -f /sys/class/dmi/id/board_version ]] && mb_version=$(cat /sys/class/dmi/id/board_version 2>/dev/null | tr -d '\0' 2>/dev/null) || mb_version="Unknown"
            [[ -f /sys/class/dmi/id/board_serial ]] && mb_serial=$(cat /sys/class/dmi/id/board_serial 2>/dev/null | tr -d '\0' 2>/dev/null) || mb_serial="Unknown"
        fi
        
        # Package counts
        apt_count=$(dpkg -l 2>/dev/null | grep -c "^ii" 2>/dev/null) || apt_count="0"
        snap_count=$(snap list 2>/dev/null | tail -n +2 | wc -l 2>/dev/null) || snap_count="0"
        flatpak_count=$(flatpak list --app 2>/dev/null | wc -l 2>/dev/null) || flatpak_count="0"
        
        # Process information
        process_count=$(ps aux 2>/dev/null | wc -l 2>/dev/null) || process_count="Unknown"
        [[ "$process_count" != "Unknown" ]] && process_count=$((process_count - 1))
        zombie_count=$(ps aux 2>/dev/null | awk '$8 ~ /^Z/ {count++} END {print count+0}' 2>/dev/null) || zombie_count="0"
        
        # System status
        boot_time=$(who -b 2>/dev/null | awk '{print $3 " " $4}' 2>/dev/null) || boot_time="Unknown"
        load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' 2>/dev/null | sed 's/^ *//' 2>/dev/null) || load_avg="Unknown"
        
        # Ultrabunt package statistics
        local total_pkgs=${#PACKAGES[@]}
        local installed_count=0
        for name in "${!PACKAGES[@]}"; do
            if is_package_installed "$name" 2>/dev/null; then
                ((installed_count++)) 2>/dev/null || true
            fi
        done 2>/dev/null || true
        
        # Ensure all variables are initialized with fallback values
        [[ -z "$cpu_model" ]] && cpu_model="Unknown"
        [[ -z "$cpu_cores" ]] && cpu_cores="Unknown"
        [[ -z "$cpu_threads" ]] && cpu_threads="Unknown"
        [[ -z "$cpu_freq" ]] && cpu_freq="Unknown"
        [[ -z "$cpu_max_freq" ]] && cpu_max_freq="Unknown"
        [[ -z "$cpu_family" ]] && cpu_family="Unknown"
        [[ -z "$memory_used" ]] && memory_used="Unknown"
        [[ -z "$memory_total" ]] && memory_total="Unknown"
        [[ -z "$memory_type" ]] && memory_type="Unknown"
        [[ -z "$memory_speed" ]] && memory_speed="Unknown"
        [[ -z "$memory_slots" ]] && memory_slots="Unknown"
        [[ -z "$storage_used" ]] && storage_used="Unknown"
        [[ -z "$storage_total" ]] && storage_total="Unknown"
        [[ -z "$storage_usage_percent" ]] && storage_usage_percent="Unknown"
        [[ -z "$storage_devices" ]] && storage_devices="Unknown"
        [[ -z "$storage_type" ]] && storage_type="Unknown"
        [[ -z "$usb_ports_list" ]] && usb_ports_list="Unknown"
        [[ -z "$display_ports_list" ]] && display_ports_list="Unknown"
        [[ -z "$thunderbolt_count" ]] && thunderbolt_count="0"
        [[ -z "$audio_ports_list" ]] && audio_ports_list="Unknown"
        [[ -z "$internet_status" ]] && internet_status="Unknown"
        [[ -z "$wifi_adapter" ]] && wifi_adapter="Unknown"
        [[ -z "$eth_adapter" ]] && eth_adapter="Unknown"
        [[ -z "$gpu_info" ]] && gpu_info="Unknown"
        [[ -z "$audio_drivers" ]] && audio_drivers="Unknown"
        [[ -z "$audio_devices" ]] && audio_devices="Unknown"
        [[ -z "$bios_vendor" ]] && bios_vendor="Unknown"
        [[ -z "$bios_version" ]] && bios_version="Unknown"
        [[ -z "$bios_date" ]] && bios_date="Unknown"
        [[ -z "$mb_manufacturer" ]] && mb_manufacturer="Unknown"
        [[ -z "$mb_product" ]] && mb_product="Unknown"
        [[ -z "$mb_version" ]] && mb_version="Unknown"
        [[ -z "$mb_serial" ]] && mb_serial="Unknown"
        [[ -z "$apt_count" ]] && apt_count="0"
        [[ -z "$snap_count" ]] && snap_count="0"
        [[ -z "$flatpak_count" ]] && flatpak_count="0"
        [[ -z "$process_count" ]] && process_count="Unknown"
        [[ -z "$zombie_count" ]] && zombie_count="0"
        [[ -z "$boot_time" ]] && boot_time="Unknown"
        [[ -z "$load_avg" ]] && load_avg="Unknown"
        [[ -z "$uptime_info" ]] && uptime_info="Unknown"
        [[ -z "$total_pkgs" ]] && total_pkgs="0"
        [[ -z "$installed_count" ]] && installed_count="0"
        
        # Create compact overview text with single-line format
        local overview=""
        [[ -n "$sudo_warning" ]] && overview+="$sudo_warning"
        
        overview+="SYSTEM INFORMATION (Compact View)\n"
        overview+="═══════════════════════════════════════\n"
        
        # Compact single-line format as requested
        overview+="OS: $os_name                                                                                                                   \n"
        overview+="Kernel: $kernel_version                                                                                                                \n"
        overview+="CPU: $cpu_model                                                                                            \n"
        overview+="Cores: $cpu_cores | Threads: $cpu_threads                                                                                                                    \n"
        overview+="Current: $cpu_freq"
        [[ "$cpu_max_freq" != "Unknown" ]] && overview+=" | Max: $cpu_max_freq"
        overview+="                                                                                               \n"
        overview+="RAM: $memory_used / $memory_total used"
        [[ "$memory_type" != "Unknown" ]] && overview+=" ($memory_type"
        [[ "$memory_speed" != "Unknown" ]] && overview+=" @ $memory_speed"
        [[ "$memory_slots" != "Unknown" ]] && overview+=" - $memory_slots slots"
        [[ "$memory_type" != "Unknown" ]] && overview+=")"
        overview+="                                                                                     \n"
        overview+="Storage: $storage_used / $storage_total used ($storage_usage_percent)"
        [[ "$storage_devices" != "Unknown" ]] && overview+=" - $storage_devices"
        [[ "$storage_type" != "Unknown" ]] && overview+=" ($storage_type)"
        overview+="                                                                   \n"
        overview+="USB Ports: $usb_ports_list                                                                                                       \n"
        overview+="Display Ports: $display_ports_list                                                                                             \n"
        [[ "$thunderbolt_count" -gt 0 ]] && overview+="Thunderbolt: ${thunderbolt_count} x Thunderbolt                                                                                                             \n"
        [[ -n "$audio_ports_list" ]] && overview+="Audio Ports: $audio_ports_list                                                                                                                   \n"
        overview+="Internet: $internet_status                                                                                                                   \n"
        overview+="Wi-Fi: $wifi_adapter                                                                                                        \n"
        overview+="Ethernet: $eth_adapter                                                                                                      \n"
        overview+="Graphics: $gpu_info                               \n"
        overview+="Audio Driver: $audio_drivers                                                   \n"
        [[ "$audio_devices" != "Unknown" ]] && overview+="Audio Devices: $audio_devices                                                                                                         \n"
        overview+="BIOS Vendor: $bios_vendor                                                                                                                  \n"
        overview+="BIOS Version: $bios_version                                                                                                                \n"
        overview+="BIOS Date: $bios_date                                                                                                                    \n"
        overview+="Motherboard: $mb_manufacturer $mb_product                                                                                             \n"
        [[ "$mb_version" != "Unknown" ]] && overview+="MB Version: $mb_version                                                                                                                \n"
        [[ "$mb_serial" != "Unknown" ]] && overview+="MB Serial: $mb_serial                                                                                                             \n"
        overview+="\n"
        overview+="Select a category below for detailed information:\n"
        
        # Build menu items
        menu_items+=("cpu" "🖥️  CPU & Processor Details")
        menu_items+=("memory" "🧠 Memory & RAM Information")
        menu_items+=("storage" "💾 Storage & Disk Details")
        menu_items+=("hardware" "⚙️  Hardware & System Info")
        menu_items+=("network" "🌐 Network & Connectivity")
        menu_items+=("graphics" "🎮 Graphics & Display Info")
        menu_items+=("audio" "🔊 Audio & Sound Devices")
        menu_items+=("packages" "📦 Package Managers & Software")
        menu_items+=("zback" "(B) Back to Main Menu")
        
        local choice
        choice=$(ui_menu "System Information Hub" "$overview" 50 140 8 "${menu_items[@]}") || break
        
        case "$choice" in
            cpu)
                show_cpu_details
                ;;
            memory)
                show_memory_details
                ;;
            storage)
                show_storage_details
                ;;
            hardware)
                show_hardware_details
                ;;
            network)
                show_network_details
                ;;
            graphics)
                show_graphics_details
                ;;
            audio)
                show_audio_details
                ;;
            packages)
                show_package_details
                ;;
            zback|back|""|q|z)
                break
                ;;
        esac
    done
    
    log "Enhanced show_system_info completed"
    return 0
}

show_bulk_operations() {
    while true; do
        local choice
        choice=$(ui_menu "Bulk Operations" \
            "Perform operations on multiple packages:" \
            20 80 10 \
            "install-category" "(.Y.) Install All Packages in Category" \
            "remove-category" "(.Y.) Remove All Packages in Category" \
            "install-selected" "(.Y.) Install Selected Packages" \
            "remove-selected" "(.Y.) Remove Selected Packages" \
            "update-all" "(.Y.) Update All Installed Buntages" \
            "cleanup" "(.Y.) Clean Buntage Cache & Remove Orphans" \
            "export-list" "(.Y.) Export Installed Buntage List" \
            "zback" "(Z) ← Back to Main Menu") || break
        
        case "$choice" in
            install-category) bulk_install_category ;;
            remove-category) bulk_remove_category ;;
            install-selected) bulk_install_selected ;;
            remove-selected) bulk_remove_selected ;;
            update-all) bulk_update_all ;;
            cleanup) bulk_cleanup ;;
            export-list) export_package_list ;;
            back|zback|"") break ;;
        esac
    done
}

bulk_install_category() {
    local menu_items=()
    
    for entry in "${CATEGORIES[@]}"; do
        local cat_id="${entry%%:*}"
        local cat_name="${entry#*:}"
        menu_items+=("$cat_id" "(.Y.) $cat_name")
    done
    
    local choice
    choice=$(ui_menu "Install Category" \
        "Select category to install all packages:" \
        20 70 10 "${menu_items[@]}") || return
    
    ui_yesno "Confirm Install" "Install ALL packages in this category?\n\nThis may take several minutes." || return
    
    local installed=0
    local failed=0
    
    for name in "${!PACKAGES[@]}"; do
        if [[ "${PKG_CATEGORY[$name]}" == "$choice" ]]; then
            if ! is_package_installed "$name"; then
                log "Bulk installing: $name"
                if install_package "$name" 2>&1 | tee -a "$LOGFILE"; then
                    ((installed++))
                else
                    ((failed++))
                    log_error "Failed to install: $name"
                fi
            fi
        fi
    done
    
    ui_msg "Bulk Install Complete" "Installed: $installed\nFailed: $failed\n\nCheck $LOGFILE for details."
}

bulk_remove_category() {
    local menu_items=()
    
    for entry in "${CATEGORIES[@]}"; do
        local cat_id="${entry%%:*}"
        local cat_name="${entry#*:}"
        menu_items+=("$cat_id" "(.Y.) $cat_name")
    done
    
    local choice
    choice=$(ui_menu "Remove Category" \
        "Select category to remove all packages:" \
        20 70 10 "${menu_items[@]}") || return
    
    ui_yesno "Confirm Removal" "⚠️  WARNING ⚠️\n\nRemove ALL packages in this category?\n\nThis cannot be undone!" || return
    
    ui_yesno "Final Confirmation" "Are you ABSOLUTELY SURE?\n\nThis will remove all packages in the selected category." || return
    
    local removed=0
    
    for name in "${!PACKAGES[@]}"; do
        if [[ "${PKG_CATEGORY[$name]}" == "$choice" ]]; then
            if is_package_installed "$name"; then
                log "Bulk removing: $name"
                local pkg="${PACKAGES[$name]}"
                local method="${PKG_METHOD[$name]}"
                
                case "$method" in
                    apt) remove_apt_package "$pkg" ;;
                    snap) remove_snap_package "$pkg" ;;
                    flatpak) remove_flatpak_package "$pkg" ;;
                    custom)
                        case "$name" in
                            docker) remove_docker ;;
                            nodejs) remove_nodejs ;;
                            vscode) remove_vscode ;;
                            brave) remove_brave ;;
                            sublime-text) remove_sublime ;;
                        esac
                        ;;
                esac
                ((removed++))
            fi
        fi
    done
    
    ui_msg "Bulk Remove Complete" "Removed: $removed packages\n\nCheck $LOGFILE for details."
}

bulk_install_selected() {
    local checklist_items=()
    
    for name in "${!PACKAGES[@]}"; do
        if ! is_package_installed "$name"; then
            local desc="${PKG_DESC[$name]}"
            local cat="${PKG_CATEGORY[$name]}"
            checklist_items+=("$name" "[$cat] $desc" "OFF")
        fi
    done
    
    if [[ ${#checklist_items[@]} -eq 0 ]]; then
        ui_msg "Nothing to Install" "All tracked packages are already installed!"
        return
    fi
    
    # Sort checklist
    IFS=$'\n' 
    checklist_items=($(sort -t$'\t' -k1 <<<"${checklist_items[*]}"))
    unset IFS
    
    local selected
    selected=$(ui_checklist "Select Packages to Install" \
        "Choose packages to install (Space to select, Enter to confirm):" \
        24 80 15 "${checklist_items[@]}") || return
    
    if [[ -z "$selected" ]]; then
        return
    fi
    
    local pkg_list=$(echo "$selected" | tr -d '"')
    local count=$(echo "$pkg_list" | wc -w)
    
    ui_yesno "Confirm Installation" "Install $count selected packages?" || return
    
    local installed=0
    local failed=0
    
    for name in $pkg_list; do
        log "Installing selected: $name"
        if install_package "$name" 2>&1 | tee -a "$LOGFILE"; then
            ((installed++))
        else
            ((failed++))
            log_error "Failed to install: $name"
        fi
    done
    
    ui_msg "Installation Complete" "Installed: $installed\nFailed: $failed\n\nCheck $LOGFILE for details."
}

bulk_remove_selected() {
    local checklist_items=()
    
    for name in "${!PACKAGES[@]}"; do
        if is_package_installed "$name" "true"; then
            local desc="${PKG_DESC[$name]}"
            local cat="${PKG_CATEGORY[$name]}"
            checklist_items+=("$name" "[$cat] $desc" "OFF")
        fi
    done
    
    if [[ ${#checklist_items[@]} -eq 0 ]]; then
        ui_msg "Nothing to Remove" "No tracked packages are currently installed!"
        return
    fi
    
    # Sort checklist
    IFS=$'\n' 
    checklist_items=($(sort -t$'\t' -k1 <<<"${checklist_items[*]}"))
    unset IFS
    
    local selected
    selected=$(ui_checklist "Select Packages to Remove" \
        "Choose packages to remove (Space to select, Enter to confirm):" \
        24 80 15 "${checklist_items[@]}") || return
    
    if [[ -z "$selected" ]]; then
        return
    fi
    
    local pkg_list=$(echo "$selected" | tr -d '"')
    local count=$(echo "$pkg_list" | wc -w)
    
    ui_yesno "Confirm Removal" "⚠️  Remove $count selected packages?" || return
    
    local removed=0
    
    for name in $pkg_list; do
        log "Removing selected: $name"
        local pkg="${PACKAGES[$name]}"
        local method="${PKG_METHOD[$name]}"
        
        case "$method" in
            apt) remove_apt_package "$pkg" ;;
            snap) remove_snap_package "$pkg" ;;
            flatpak) remove_flatpak_package "$pkg" ;;
            custom)
                case "$name" in
                    docker) remove_docker ;;
                    nodejs) remove_nodejs ;;
                    vscode) remove_vscode ;;
                    brave) remove_brave ;;
                    sublime-text) remove_sublime ;;
                esac
                ;;
        esac
        ((removed++))
    done
    
    ui_msg "Removal Complete" "Removed: $removed packages\n\nCheck $LOGFILE for details."
}

bulk_update_all() {
    ui_yesno "Update All" "Update all buntage managers and installed buntages?" || return
    
    log "Starting system update..."
    
    # APT
    log "Updating APT buntages..."
    sudo apt-get update -y 2>&1 | tee -a "$LOGFILE"
    sudo apt-get upgrade -y 2>&1 | tee -a "$LOGFILE"
    
    # Snap
    if command -v snap &>/dev/null; then
        log "Updating Snap buntages..."
        sudo snap refresh 2>&1 | tee -a "$LOGFILE"
    fi
    
    # Flatpak
    if command -v flatpak &>/dev/null; then
        log "Updating Flatpak apps..."
        flatpak update -y 2>&1 | tee -a "$LOGFILE"
    fi
    
    ui_msg "Update Complete" "All buntage managers updated!\n\nCheck $LOGFILE for details."
}

bulk_cleanup() {
    ui_yesno "System Cleanup" "This will:\n- Remove unused buntages\n- Clean buntage cache\n- Remove old kernels\n\nContinue?" || return
    
    log "Starting system cleanup..."
    
    # APT cleanup
    log "Cleaning APT cache..."
    sudo apt-get autoremove -y 2>&1 | tee -a "$LOGFILE"
    sudo apt-get autoclean -y 2>&1 | tee -a "$LOGFILE"
    sudo apt-get clean 2>&1 | tee -a "$LOGFILE"
    
    # Snap cleanup
    if command -v snap &>/dev/null; then
        log "Removing old snap revisions..."
        sudo snap list --all | awk '/disabled/{print $1, $3}' | \
            while read snapname revision; do
                sudo snap remove "$snapname" --revision="$revision" 2>&1 | tee -a "$LOGFILE"
            done
    fi
    
    # Flatpak cleanup
    if command -v flatpak &>/dev/null; then
        log "Cleaning Flatpak cache..."
        flatpak uninstall --unused -y 2>&1 | tee -a "$LOGFILE"
    fi
    
    # Journal cleanup
    log "Cleaning system journal..."
    sudo journalctl --vacuum-time=7d 2>&1 | tee -a "$LOGFILE"
    
    ui_msg "Cleanup Complete" "System cleanup finished!\n\nCheck $LOGFILE for details."
}

export_package_list() {
    local export_file="/tmp/ultrabunt-packages-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "ULTRABUNT BUNTAGE LIST - $(date)"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        
        for entry in "${CATEGORIES[@]}"; do
            local cat_id="${entry%%:*}"
            local cat_name="${entry#*:}"
            
            echo ""
            echo "[$cat_name]"
            echo "─────────────────────────────────────────────────────────"
            
            for name in "${!PACKAGES[@]}"; do
                if [[ "${PKG_CATEGORY[$name]}" == "$cat_id" ]]; then
                    local status="NOT INSTALLED"
                    if is_package_installed "$name" "true"; then
                        status="INSTALLED"
                    fi
                    printf "%-20s %-15s %s\n" "$name" "[$status]" "${PKG_DESC[$name]}"
                fi
            done
        done
        
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "Export completed: $(date)"
        
    } > "$export_file"
    
    ui_msg "Export Complete" "Buntage list exported to:\n\n$export_file"
}

# ==============================================================================
# ADVANCED FEATURES
# ==============================================================================

show_essentials_setup_menu() {
    log "Entering show_essentials_setup_menu"

    while true; do
        local menu_items=(
            "install" "(.Y.) Install Essentials (curl, wget, zip, unzip, htop, snapd)"
            "" "(_*_)"
            "back" "(Z) ← Back to Main Menu"
        )

        local choice
        choice=$(ui_menu "First-Time Essentials" \
            "Install minimal tools to continue." \
            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break

        case "$choice" in
            install)
                install_essentials_bundle || ui_msg "Install Error" "Failed to install essentials. Check $LOGFILE"
                ;;
            back|zback|z|"")
                break
                ;;
        esac
    done
}

install_essentials_bundle() {
    log "Installing First-Time Essentials bundle"
    ui_msg "Essentials" "Installing core tools: curl, wget, zip, unzip, htop\n\nThis may take a minute."

    apt_update

    # Ensure APT prerequisites for repository keys
    install_apt_package "ca-certificates" || true
    install_apt_package "gnupg" || true

    # Install core tools
    local tools=(curl wget zip unzip htop)
    local failures=()
    for t in "${tools[@]}"; do
        if ! install_apt_package "$t"; then
            failures+=("$t")
        fi
    done

    # Prepare snapd
    if ! ensure_snapd_ready; then
        ui_msg "snapd Issue" "snapd could not be prepared. You can retry from this menu."
    fi

    if [[ ${#failures[@]} -gt 0 ]]; then
        ui_msg "Install Partial" "Some tools failed to install:\n\n${failures[*]}\n\nPlease check the log: $LOGFILE"
        return 1
    else
        ui_msg "Essentials Installed" "All core tools installed and snapd prepared."
        return 0
    fi
}

install_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ui_msg "Already Installed" "Oh My Zsh is already installed!"
        return
    fi
    
    ui_yesno "Install Oh My Zsh?" "Install Oh My Zsh with Powerlevel10k theme?" || return
    
    if ! is_package_installed "zsh"; then
        install_package "zsh"
    fi
    
    log "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>&1 | tee -a "$LOGFILE"
    
    log "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" 2>&1 | tee -a "$LOGFILE"
    
    sed -i 's/ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
    
    ui_msg "Oh My Zsh Installed" "Oh My Zsh with Powerlevel10k installed!\n\nRun 'zsh' to start configuration."
}

# ==============================================================================
# WORDPRESS INSTALLATION SYSTEM
# ==============================================================================

# ==============================================================================
# CLOUDFLARE FIREWALL SETUP
# ============================================================================

cloudflare_check_dependencies() {
    local missing=()
    if ! command -v curl >/dev/null 2>&1; then missing+=("curl"); fi
    if ! command -v jq >/dev/null 2>&1; then missing+=("jq"); fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        local list="${missing[*]}"
        speak_if_enabled "Cloudflare setup requires $list."
        if ui_yesno "Install Dependencies" "Cloudflare setup requires: ${list}\n\nInstall them now via apt?"; then
            sudo apt-get update -y || true
            sudo apt-get install -y ${list} || {
                ui_msg "Install Failed" "Failed to install dependencies: ${list}. Please install manually and retry."
                return 1
            }
        else
            ui_msg "Missing Dependencies" "Cannot continue without: ${list}."
            return 1
        fi
    fi
}

cloudflare_create_rule() {
    local zone_id="$1"
    local api_token="$2"
    local desc="$3"
    local expr="$4"
    local action="block"
    local api="https://api.cloudflare.com/client/v4/zones/${zone_id}/firewall/rules"

    # Build JSON payload safely
    local payload
    payload=$(printf '[{"description":"%s","action":"%s","filter":{"expression":"%s"}}]' \
        "$desc" "$action" "$expr")

    speak_if_enabled "Creating Cloudflare rule: $desc"
    log "Cloudflare POST payload: $payload"
    local resp
    resp=$(curl -s -X POST "$api" \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" \
        --data "$payload")
    log "Cloudflare response: $resp"

    local ok
    ok=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)
    if [[ "$ok" == "true" ]]; then
        ui_msg "Cloudflare" "✅ Rule created: ${desc}"
        return 0
    else
        local errs
        errs=$(echo "$resp" | jq -r '.errors | map(.message) | join("; ")' 2>/dev/null)
        ui_info "Cloudflare API Error" "Failed to create rule: ${desc}\n\nErrors: ${errs}\n\nFull Response:\n$(echo "$resp" | jq . 2>/dev/null || echo "$resp")"
        return 1
    fi
}

show_cloudflare_setup_menu() {
    log "Entering show_cloudflare_setup_menu"

    # Ensure deps
    cloudflare_check_dependencies || return 1

    # Minimal instructions (Quick Guide)
    local cf_quick
    cf_quick="Cloudflare Setup — Quick Guide\n\n"
    cf_quick+="Dependencies: curl + jq (auto-install if missing).\n\n"
    cf_quick+="Zone ID: Cloudflare Dashboard → your domain → Overview → API → Zone ID.\n"
    cf_quick+="API Token: My Profile → API Tokens → Create Custom Token.\n"
    cf_quick+="Permissions: Zone → Firewall Services → Edit; Zone Resources → Specific Zone (your domain).\n"
    cf_quick+="Optional: Verify token works:\n"
    cf_quick+="curl -X GET https://api.cloudflare.com/client/v4/user/tokens/verify \\\n+ -H 'Authorization: Bearer YOUR_API_TOKEN' -H 'Content-Type: application/json'\n\n"
    cf_quick+="You will enter: Zone ID, API Token, Domain.\n"
    cf_quick+="Then choose: light/moderate/extreme, and optional bot blocking.\n"
    cf_quick+="This will create the corresponding firewall rules."
    ui_info "Cloudflare Setup (Minimal Instructions)" "$cf_quick"

    # Collect inputs
    local cf_email zone_id api_token domain level botblock
    cf_email=$(ui_input "Cloudflare Email (optional)" "Enter your Cloudflare email (optional, for logs only):" "") || return
    zone_id=$(ui_input "Cloudflare Zone ID" "Enter your Cloudflare Zone ID:" "") || return
    api_token=$(ui_input "Cloudflare API Token" "Enter your Cloudflare API Token (must have Firewall Rules permissions):" "") || return
    domain=$(ui_input "Domain Name" "Enter your domain name (e.g. example.com):" "") || return

    if [[ -z "$zone_id" || -z "$api_token" || -z "$domain" ]]; then
        ui_msg "Missing Inputs" "Zone ID, API Token, and Domain are required."
        return 1
    fi

    # Choose security level
    level=$(ui_menu "Security Level" \
        "Choose Cloudflare security level:" 12 60 6 \
        "light" "🟢 Light (basic protection)" \
        "moderate" "🟡 Moderate (adds wp-admin/wp-login limits)" \
        "extreme" "🔴 Extreme (adds country blocks)") || return

    # Bot blocking?
    if ui_yesno "Advanced Bot Blocking" "Enable advanced bot blocking (AI & SEO bots)?"; then
        botblock="y"
    else
        botblock="n"
    fi

    speak_if_enabled "Applying Cloudflare firewall rules"
    ui_msg "Applying Rules" "Applying Cloudflare firewall rules for ${domain} (${level}).\n\nThis may take a few seconds..."

    # Build expressions from instructions
    local expr_light expr_moderate expr_extreme expr_bots
    expr_light=$(printf '(http.request.uri.path contains "/xmlrpc.php") or ((http.request.uri.path eq "/wp-content/" or http.request.uri.path eq "/wp-includes/") and not http.referer contains "%s")' "$domain")

    expr_moderate='(
  http.request.uri.path contains "/wp-login.php" or
  (http.request.uri.path contains "/wp-admin/" and http.request.uri.path ne "/wp-admin/admin-ajax.php")
)
and not (ip.geoip.country in {"AU" "US" "UK"})'

    expr_extreme='(
  ip.geoip.country in {"RU" "CN" "KP" "IR" "VN" "TR" "IN" "NG"}
)
and not cf.client.bot'

    expr_bots='(http.request.uri.path ne "/robots.txt") and (
  (http.user_agent contains "SemrushBot") or
  (http.user_agent contains "AhrefsBot") or
  (http.user_agent contains "Barkrowler") or
  (http.user_agent contains "MJ12bot") or
  (http.user_agent contains "DotBot") or
  (http.user_agent contains "Exabot") or
  (http.user_agent contains "Sogou") or
  (http.user_agent contains "YandexBot") or
  (http.user_agent contains "Baidu") or
  (http.user_agent contains "ia_archiver") or
  (http.user_agent contains "SemanticaBot") or
  (http.user_agent contains "SiteLockSpider") or
  (http.user_agent contains "SeznamBot") or
  (http.user_agent contains "OpenLinkProfiler") or
  (http.user_agent contains "SiteBot") or
  (http.user_agent contains "Screaming Frog") or
  (http.user_agent contains "DataForSeoBot") or
  (http.user_agent contains "SEOkicks") or
  (http.user_agent contains "BLEXBot") or
  (http.user_agent contains "MegaIndex") or
  (http.user_agent contains "MegaIndex.ru") or
  (http.user_agent contains "NetcraftSurveyAgent") or
  (http.user_agent contains "Apache-HttpClient") or
  (http.user_agent contains "Python-urllib") or
  (http.user_agent contains "python-requests") or
  (http.user_agent contains "libwww-perl") or
  (http.user_agent contains "Curl") or
  (http.user_agent contains "wget") or
  (http.user_agent contains "CensysInspect") or
  (http.user_agent contains "ZoominfoBot") or
  (http.user_agent contains "MauiBot") or
  (http.user_agent contains "spbot") or
  (http.user_agent contains "GPTBot") or
  (http.user_agent contains "ClaudeBot") or
  (http.user_agent contains "Claude-SearchBot") or
  (http.user_agent contains "Claude-User") or
  (http.user_agent contains "Bytespider") or
  (http.user_agent contains "MistralAI-User") or
  (http.user_agent contains "Perplexity-User") or
  (http.user_agent contains "ProRataInc") or
  (http.user_agent contains "Novellum") or
  (http.user_agent contains "OAI-SearchBot") or
  (http.user_agent contains "Meta-ExternalFetcher") or
  (http.user_agent contains "Meta-ExternalAgent")
)'

    # Apply rules based on level
    cloudflare_create_rule "$zone_id" "$api_token" "Block XMLRPC and unauthorized includes" "$expr_light" || return 1
    if [[ "$level" == "moderate" || "$level" == "extreme" ]]; then
        cloudflare_create_rule "$zone_id" "$api_token" "Restrict wp-login/wp-admin to AU, US, UK" "$expr_moderate" || return 1
    fi
    if [[ "$level" == "extreme" ]]; then
        cloudflare_create_rule "$zone_id" "$api_token" "Block access from high-risk countries" "$expr_extreme" || return 1
    fi
    if [[ "$botblock" =~ ^[Yy]$ ]]; then
        cloudflare_create_rule "$zone_id" "$api_token" "AI Crawl Control - Block AI & SEO Bots" "$expr_bots" || return 1
    fi

    log "Cloudflare rules applied for domain: $domain level: $level"
    speak_if_enabled "Cloudflare security rules applied"
    ui_msg "Success" "✅ Cloudflare security rules applied for ${domain} (${level} mode)"
    return 0
}

show_wordpress_setup_menu() {
    log "Entering show_wordpress_setup_menu function"
    
    while true; do
        local menu_items=(
            "status" "(.Y.) 📊 Manage WordPress Sites"
            "" "(_*_)"
            "quick-nginx" "(.Y.) 🚀 Quick Setup (Nginx + WordPress)"
            "quick-apache" "(.Y.) 🚀 Quick Setup (Apache + WordPress)"
            "" "(_*_)"
            "custom-nginx" "(.Y.) ⚙️  Custom Nginx Setup"
            "custom-apache" "(.Y.) ⚙️  Custom Apache Setup"
            "custom-db-nginx" "(.Y.) 🔧 Custom Database + Nginx Setup"
            "custom-db-apache" "(.Y.) 🔧 Custom Database + Apache Setup"
            "" "(_*_)"
            "wp-cli" "(.Y.) 🔧 Install/Manage WP-CLI"
            "wp-cleanup" "(.Y.) 🧹 WordPress Cleanup & Customization"
            "sql-import-optimize" "(.Y.) 📊 Optimize for Large SQL Imports"
            "ssl-setup" "(.Y.) 🔒 SSL Setup (Local or Live)"
            "wp-security" "(.Y.) 🛡️  WordPress Security Hardening"
            "" "(_*_)"
            "zback" "(Z) ← Back to Main Menu"
        )
        
        local choice
        choice=$(ui_menu "WordPress Management" \
            "Manage your WordPress installations:\n\n📊 Manage Sites: View, configure, and troubleshoot existing WordPress sites\n🚀 Quick Setup: Auto-generated database credentials\n⚙️  Custom Setup: Choose site directory\n🔧 Custom Database: Choose database name, user, and password\n🧹 Cleanup: Remove default content and optimize existing WordPress sites" \
            22 90 15 "${menu_items[@]}") || break
        
        case "$choice" in
            quick-nginx)
                wordpress_quick_setup "nginx"
                ;;
            quick-apache)
                wordpress_quick_setup "apache"
                ;;
            custom-nginx)
                wordpress_custom_setup "nginx"
                ;;
            custom-apache)
                wordpress_custom_setup "apache"
                ;;
            custom-db-nginx)
                wordpress_custom_database_setup "nginx"
                ;;
            custom-db-apache)
                wordpress_custom_database_setup "apache"
                ;;
            wp-cli)
                wordpress_wpcli_management
                ;;
            wp-cleanup)
                wordpress_cleanup_menu
                ;;
            sql-import-optimize)
                optimize_for_large_sql_imports
                ;;
            ssl-setup)
                wordpress_ssl_setup_menu
                ;;
            wp-security)
                wordpress_security_hardening
                ;;
            status)
                show_wordpress_status
                ;;
            back|zback|z|"")
                break
                ;;
        esac
    done
    
    log "Exiting show_wordpress_setup_menu function"
}

wordpress_quick_setup() {
    local web_server="$1"
    log "Starting WordPress quick setup with $web_server"
    
    local info="WordPress Quick Setup ($web_server)\n\n"
    info+="This will install and configure:\n"
    info+="• $web_server web server\n"
    info+="• PHP and required extensions\n"
    info+="• MariaDB database server\n"
    info+="• Latest WordPress\n"
    info+="• Basic security configuration\n\n"
    info+="Perfect for new Ubuntu installations!\n\n"
    info+="Continue with installation?"
    
    if ! ui_yesno "Quick WordPress Setup" "$info"; then
        return
    fi
    
    # Install prerequisites
    ui_msg "Step 1/6" "Installing WordPress prerequisites...\n\nThis includes:\n• Web server ($web_server)\n• PHP and extensions\n• MariaDB database\n• Required system packages\n\n⏳ This process is automatic - please wait..."
    install_wordpress_prerequisites "$web_server" || {
        ui_msg "Installation Failed" "Failed to install prerequisites. Check the logs for details."
        return 1
    }
    
    log "Step 1 Complete: Prerequisites installed successfully"
    
    # Get domain name with validation
    ui_msg "Step 2/6" "Configuring domain settings...\n\nPlease enter your domain name or use 'localhost' for local development.\n\nFor local development, we recommend using '.localhost' suffix (e.g., mysite.localhost)\nwhich works automatically without DNS configuration.\n\n👆 User input required below..."
    local domain
    while true; do
        domain=$(ui_input "Domain Name" "Enter your domain name (or 'localhost' for local development):" "localhost") || return
        domain=${domain:-localhost}
        
        # Auto-suggest .localhost for simple names
        if [[ "$domain" != "localhost" ]] && [[ ! "$domain" =~ \. ]] && [[ ${#domain} -le 20 ]]; then
            if ui_yesno "Domain Suggestion" "For local development, would you like to use '$domain.localhost' instead of '$domain'?\n\nThis will work automatically without DNS configuration."; then
                domain="$domain.localhost"
            fi
        fi
        
        # Validate domain format
        if [[ "$domain" == "localhost" ]] || [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            break
        else
            ui_msg "Invalid Domain" "Please enter a valid domain name or 'localhost'.\n\nExamples:\n• localhost\n• mysite.localhost\n• mysite.local\n• example.com\n• subdomain.example.com"
        fi
    done
    
    ui_msg "Step 2 Complete" "✅ Domain configured: $domain\n\n• Site URL: http://$domain\n• Directory: /var/www/$domain\n• Admin URL: http://$domain/wp-admin/"
    
    # SSL Configuration for local domains
    local use_ssl=false
    if [[ "$domain" =~ \.(localhost|local)$ ]] || [[ "$domain" == "localhost" ]]; then
        if ui_yesno "SSL Configuration" "Would you like to enable HTTPS for your local WordPress site?\n\n✅ Pros:\n• Secure local development\n• Test SSL-dependent features\n• Modern browser compatibility\n\n⚠️  Note:\n• Uses self-signed certificate\n• Browser will show security warning (normal for local dev)\n• You can add certificate to system trust store"; then
            use_ssl=true
        fi
    fi
    
    # Confirm installation details
    local confirm_msg="WordPress Installation Summary\n\n"
    confirm_msg+="Web Server: $web_server\n"
    confirm_msg+="Domain: $domain\n"
    confirm_msg+="Site Directory: /var/www/$domain\n"
    confirm_msg+="Database: Auto-generated secure credentials\n"
    if [[ "$use_ssl" == true ]]; then
        confirm_msg+="SSL: Self-signed certificate (HTTPS enabled)\n"
    else
        confirm_msg+="SSL: HTTP only\n"
    fi
    confirm_msg+="\nProceed with installation?"
    
    if ! ui_yesno "Confirm Installation" "$confirm_msg"; then
        return
    fi
    
    # Create the WordPress database (this now handles MariaDB root access internally)
    ui_msg "Step 3/6" "Creating WordPress database...\n\n• Verifying MariaDB root access\n• Creating WordPress database\n• Setting up database user\n• Configuring permissions\n\n⏳ This process is automatic - please wait..."
    
    local db_info
    db_info=$(setup_wordpress_database "$domain") || {
        ui_msg "Database Creation Failed" "❌ Failed to create WordPress database.\n\nPossible causes:\n• MariaDB authentication issues\n• Insufficient privileges\n• Database service problems\n\nCheck the logs for details."
        return 1
    }
    
    # Parse and display database info
    IFS=':' read -r db_name db_user db_pass <<< "$db_info"
    
    # Debug logging for database info
    log "Database info received: '$db_info'"
    log "Parsed - DB Name: '$db_name', DB User: '$db_user', DB Pass: '${db_pass:0:4}...'"
    
    # Validate that we have all required database info
    if [[ -z "$db_name" || -z "$db_user" || -z "$db_pass" ]]; then
        log "ERROR: Incomplete database information - Name: '$db_name', User: '$db_user', Pass: '${db_pass:+[SET]}'"
        ui_msg "Database Error" "❌ Database creation returned incomplete information.\n\nReceived: '$db_info'\n\nPlease check the logs for details."
        return 1
    fi
    
    ui_msg "Step 3 Complete" "✅ Database created successfully!\n\n• Database Name: $db_name\n• Database User: $db_user\n• Database Password: $db_pass\n• Host: localhost\n\n🔒 Credentials saved for your reference."
    
    # Download and configure WordPress
    ui_msg "Step 4/6" "Downloading and configuring WordPress...\n\n• Downloading latest WordPress\n• Extracting files to /var/www/$domain\n• Configuring wp-config.php\n• Setting file permissions\n\n⏳ This process is automatic - please wait..."
    setup_wordpress_files "$domain" "$db_info" || {
        ui_msg "WordPress Setup Error" "Failed to download or configure WordPress files."
        return 1
    }
    
    ui_msg "Step 4 Complete" "✅ WordPress files configured!\n\n• Latest WordPress: Downloaded\n• Configuration: Complete\n• File permissions: Set\n• Upload directory: Created"
    
    # Configure web server
    ui_msg "Step 5/6" "Configuring $web_server web server...\n\n• Creating server configuration\n• Setting up PHP processing\n• Configuring security headers\n• Enabling site\n\n⏳ This process is automatic - please wait..."
    if [[ "$web_server" == "nginx" ]]; then
        configure_nginx_wordpress "$domain" || {
            ui_msg "Nginx Configuration Error" "Failed to configure Nginx. Check configuration syntax."
            return 1
        }
    else
        configure_apache_wordpress "$domain" || {
            ui_msg "Apache Configuration Error" "Failed to configure Apache. Check configuration syntax."
            return 1
        }
    fi
    
    # Set up SSL if requested
    if [[ "$use_ssl" == true ]]; then
        ui_msg "Step 5b/6" "Setting up SSL certificate...\n\n• Generating self-signed certificate\n• Configuring HTTPS\n• Updating server configuration\n\n⏳ This process is automatic - please wait..."
        if setup_local_ssl "$domain" "$web_server"; then
            ui_msg "SSL Setup Complete" "✅ SSL certificate configured successfully!\n\n• Self-signed certificate: Generated\n• HTTPS: Enabled\n• Security headers: Added\n\nYour site is accessible via HTTPS."
        else
            log "SSL setup failed, continuing with HTTP-only installation"
            ui_msg "SSL Setup Warning" "⚠️  SSL setup failed, but site will work with HTTP.\n\nYour WordPress site is fully functional at: http://$domain\n\nYou can set up SSL later using:\n• WordPress management menu\n• Manual SSL configuration\n• Let's Encrypt (for public domains)"
        fi
    fi

    # Removed Let's Encrypt prompt during quick install; SSL can be configured later via WordPress SSL menu (Local or Live)
    
    ui_msg "Step 5 Complete" "✅ $web_server configured successfully!\n\n• Server block: Created\n• PHP processing: Enabled\n• Security headers: Set\n• Site: Active and running$(if [[ "$use_ssl" == true ]]; then echo "\n• SSL: HTTPS enabled"; fi)"
    
    # Show completion message
    ui_msg "Step 6/6" "Finalizing WordPress installation...\n\nPreparing completion summary with all details.\n\n⏳ This process is automatic - please wait..."
    show_wordpress_completion "$domain" "$db_info"
    
    ui_msg "Installation Complete!" "🎉 WordPress installation finished successfully!\n\nYour site is ready at: http://$domain\n\nNext steps:\n1. Visit your site to complete WordPress setup\n2. Create your admin account\n3. Choose your theme and plugins\n\n💡 Tip: Use the WordPress Cleanup option in the WordPress menu to remove default content and optimize your site."
}

wordpress_custom_setup() {
    local web_server="$1"
    log "Starting WordPress custom setup with $web_server"
    
    local info="WordPress Custom Setup ($web_server)\n\n"
    info+="This allows you to customize:\n"
    info+="• Domain and directory settings\n"
    info+="• Database configuration\n"
    info+="• PHP settings\n"
    info+="• Security options\n\n"
    info+="Continue with custom setup?"
    
    if ! ui_yesno "Custom WordPress Setup" "$info"; then
        return
    fi
    
    # Check if prerequisites are installed
    if ! check_wordpress_prerequisites "$web_server"; then
        if ui_yesno "Install Prerequisites" "Required packages are missing. Install them now?"; then
            install_wordpress_prerequisites "$web_server"
        else
            ui_msg "Setup Cancelled" "Cannot proceed without required packages."
            return
        fi
    fi
    
    # Custom configuration options
    local domain
    domain=$(ui_input "Domain Name" "Enter your domain name:" "localhost") || return
    domain=${domain:-localhost}
    
    local site_dir
    site_dir=$(ui_input "Site Directory" "WordPress installation directory:" "/var/www/$domain") || return
    site_dir=${site_dir:-/var/www/$domain}
    
    # Database setup with custom options
    local db_info
    db_info=$(setup_wordpress_database_custom "$domain")
    
    # WordPress setup
    setup_wordpress_files_custom "$domain" "$site_dir" "$db_info"
    
    # Web server configuration
    if [[ "$web_server" == "nginx" ]]; then
        configure_nginx_wordpress_custom "$domain" "$site_dir"
    else
        configure_apache_wordpress_custom "$domain" "$site_dir"
    fi

    # Removed Let's Encrypt prompt during custom install; SSL can be configured later via WordPress SSL menu (Local or Live)
    
    # Show completion
    show_wordpress_completion "$domain" "$db_info"
}

wordpress_custom_database_setup() {
    local web_server="$1"
    log "Starting WordPress custom database setup with $web_server"
    
    local info="WordPress Custom Database Setup ($web_server)\n\n"
    info+="🔧 This setup allows you to:\n"
    info+="• Choose your own database name\n"
    info+="• Set custom database username\n"
    info+="• Define your own password\n"
    info+="• Understand user management\n\n"
    info+="🔐 You'll learn about:\n"
    info+="• ROOT user (administrative access)\n"
    info+="• WordPress user (application access)\n"
    info+="• Security best practices\n\n"
    info+="Continue with custom database setup?"
    
    if ! ui_yesno "Custom Database Setup" "$info"; then
        return
    fi
    
    # Check if prerequisites are installed
    if ! check_wordpress_prerequisites "$web_server"; then
        if ui_yesno "Install Prerequisites" "Required packages are missing. Install them now?"; then
            install_wordpress_prerequisites "$web_server"
        else
            ui_msg "Setup Cancelled" "Cannot proceed without required packages."
            return
        fi
    fi
    
    # Domain configuration
    local domain
    domain=$(ui_input "Domain Name" "Enter your domain name:" "localhost") || return
    domain=${domain:-localhost}
    
    # Custom database setup with detailed explanations
    local db_info
    db_info=$(setup_wordpress_database_custom "$domain") || {
        ui_msg "Database Setup Failed" "Database setup was cancelled or failed. Please try again."
        return 1
    }
    
    # Parse database info for confirmation
    IFS=':' read -r db_name db_user db_pass <<< "$db_info"
    
    # Confirm setup before proceeding
    local confirm_msg="🔐 Database Configuration Summary:\n\n"
    confirm_msg+="• Database Name: $db_name\n"
    confirm_msg+="• Database User: $db_user\n"
    confirm_msg+="• Database Password: $db_pass\n"
    confirm_msg+="• Host: localhost\n\n"
    confirm_msg+="📁 WordPress will be installed to: /var/www/$domain\n\n"
    confirm_msg+="Continue with WordPress installation?"
    
    if ! ui_yesno "Confirm Installation" "$confirm_msg"; then
        return
    fi
    
    # WordPress file setup
    ui_msg "Step 2/4" "Setting up WordPress files...\n\nDownloading and configuring WordPress with your custom database settings.\n\n⏳ This process is automatic - please wait..."
    setup_wordpress_files "$domain" "$db_info" || {
        ui_msg "WordPress Setup Error" "Failed to download or configure WordPress files."
        return 1
    }
    
    # Web server configuration
    ui_msg "Step 3/4" "Configuring web server...\n\nSetting up $web_server virtual host for $domain.\n\n⏳ This process is automatic - please wait..."
    if [[ "$web_server" == "nginx" ]]; then
        configure_nginx_wordpress "$domain" || {
            ui_msg "Nginx Configuration Error" "Failed to configure Nginx. Please check the logs."
            return 1
        }
    else
        configure_apache_wordpress "$domain" || {
            ui_msg "Apache Configuration Error" "Failed to configure Apache. Please check the logs."
            return 1
        }
    fi
    
    # Final setup and permissions
    ui_msg "Step 4/4" "Finalizing installation...\n\nSetting file permissions and restarting services.\n\n⏳ This process is automatic - please wait..."
    finalize_wordpress_setup "$domain" "$web_server" || {
        ui_msg "Finalization Error" "WordPress setup completed but some final steps failed."
    }
    
    # Show completion with custom database details
    show_wordpress_completion_custom "$domain" "$db_info" "$web_server"
}

show_wordpress_completion_custom() {
    local domain="$1"
    local db_info="$2"
    local web_server="$3"
    
    # Parse database info
    IFS=':' read -r db_name db_user db_pass <<< "$db_info"
    
    local completion_msg="🎉 WordPress Installation Complete!\n\n"
    completion_msg+="🌐 Website Details:\n"
    completion_msg+="• URL: http://$domain\n"
    completion_msg+="• Directory: /var/www/$domain\n"
    completion_msg+="• Web Server: $web_server\n\n"
    completion_msg+="🔐 Custom Database Configuration:\n"
    completion_msg+="• Database Name: $db_name\n"
    completion_msg+="• Database User: $db_user (WordPress-specific)\n"
    completion_msg+="• Database Password: $db_pass\n"
    completion_msg+="• Host: localhost\n\n"
    completion_msg+="👤 User Management Summary:\n"
    completion_msg+="• ROOT USER: Administrative MariaDB access\n"
    completion_msg+="• WORDPRESS USER: '$db_user' (limited to '$db_name' database)\n\n"
    completion_msg+="🔧 Next Steps:\n"
    completion_msg+="1. Visit http://$domain to complete WordPress setup\n"
    completion_msg+="2. Use the database credentials above during WordPress installation\n"
    completion_msg+="3. Consider adding SSL certificate for security\n\n"
    completion_msg+="📝 Database credentials are saved in wp-config.php"
    
    ui_msg "Installation Complete" "$completion_msg"
}

install_wordpress_prerequisites() {
    local web_server="$1"
    log "Installing WordPress prerequisites for $web_server"
    
    ui_msg "Installing Prerequisites" "Installing required packages for WordPress...\n\nThis may take a few minutes.\n\n⏳ This process is automatic - please wait..."
    
    # Common packages
    local packages=("mariadb" "php-mysql" "php-curl" "php-gd" "php-xml" "php-mbstring" "php-zip")
    
    # Web server specific packages
    if [[ "$web_server" == "nginx" ]]; then
        packages+=("nginx" "php-fpm")
    else
        packages+=("apache2" "libapache2-mod-php")
    fi
    
    # Install packages
    for pkg in "${packages[@]}"; do
        if ! is_package_installed "$pkg"; then
            log "Installing $pkg..."
            install_package "$pkg" || {
                ui_msg "Installation Error" "Failed to install $pkg. Please check the logs."
                return 1
            }
        fi
    done
    
    # Start and enable services
    if [[ "$web_server" == "nginx" ]]; then
        sudo systemctl enable nginx php${PHP_VER}-fpm mariadb 2>&1 | tee -a "$LOGFILE"
        sudo systemctl start nginx php${PHP_VER}-fpm mariadb 2>&1 | tee -a "$LOGFILE"
        
        # Verify PHP-FPM is running
        if ! systemctl is-active --quiet php${PHP_VER}-fpm; then
            log "ERROR: PHP-FPM failed to start"
            ui_msg "Service Error" "PHP-FPM failed to start. This will cause 500 errors.\n\nTrying to restart..."
            sudo systemctl restart php${PHP_VER}-fpm
            sleep 2
            if ! systemctl is-active --quiet php${PHP_VER}-fpm; then
                ui_msg "Critical Error" "PHP-FPM still not running. Check: sudo systemctl status php${PHP_VER}-fpm"
                return 1
            fi
        fi
    else
        sudo systemctl enable apache2 mariadb 2>&1 | tee -a "$LOGFILE"
        sudo systemctl start apache2 mariadb 2>&1 | tee -a "$LOGFILE"
        sudo a2enmod rewrite 2>&1 | tee -a "$LOGFILE"
    fi
    
    # Secure MariaDB installation
    setup_mariadb_security
    
    log "WordPress prerequisites installed successfully"
}

check_wordpress_prerequisites() {
    local web_server="$1"
    
    local required_packages=("mariadb" "php-mysql" "php-curl" "php-gd")
    
    if [[ "$web_server" == "nginx" ]]; then
        required_packages+=("nginx" "php-fpm")
    else
        required_packages+=("apache2" "libapache2-mod-php")
    fi
    
    for pkg in "${required_packages[@]}"; do
        if ! is_package_installed "$pkg"; then
            return 1
        fi
    done
    
    return 0
}

setup_mariadb_security() {
    log "Setting up MariaDB security"
    
    # Check if MariaDB is already configured
    local existing_pass=""
    if [[ -f "/root/.mysql_root_password" ]]; then
        existing_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
        log "Found existing MariaDB password file"
        
        # Test if existing password works
        if [[ -n "$existing_pass" ]] && mysql -u root -p"$existing_pass" -e "SELECT 1;" >/dev/null 2>&1; then
            log "Existing MariaDB password is valid, skipping setup"
            return 0
        else
            log "Existing password doesn't work, reconfiguring MariaDB"
        fi
    fi
    
    # Generate random root password
    local root_pass
    root_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
    
    # First, check if MariaDB is using unix_socket authentication
    local auth_plugin
    auth_plugin=$(sudo mysql -e "SELECT plugin FROM mysql.user WHERE User='root' AND Host='localhost';" 2>/dev/null | tail -n +2 | head -n 1)
    
    # Configure root user for password authentication
    if [[ "$auth_plugin" == "unix_socket" ]] || [[ -z "$auth_plugin" ]]; then
        # Change from unix_socket to mysql_native_password
        sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${root_pass}';" 2>/dev/null || {
            # If that fails, try creating the user
            sudo mysql -e "CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${root_pass}';" 2>/dev/null || true
            sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;" 2>/dev/null || true
        }
    else
        # For existing installations, we might need to reset the password
        log "Attempting to reset existing MariaDB root password"
        
        # Try multiple methods to set the password
        if sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_pass';" 2>/dev/null; then
            log "Password set using ALTER USER"
        elif sudo mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$root_pass');" 2>/dev/null; then
            log "Password set using SET PASSWORD"
        elif sudo mysql -e "UPDATE mysql.user SET Password=PASSWORD('$root_pass') WHERE User='root' AND Host='localhost';" 2>/dev/null; then
            log "Password set using UPDATE"
        else
            log "All password setting methods failed, trying to reset authentication plugin"
            sudo mysql -e "UPDATE mysql.user SET plugin='mysql_native_password', Password=PASSWORD('$root_pass') WHERE User='root' AND Host='localhost';" 2>/dev/null
        fi
    fi
    
    # Secure installation - clean up
    sudo mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    sudo mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
    sudo mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    # Verify the password works
    if mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        # Save root password and display to user
        echo "$root_pass" | sudo tee /root/.mysql_root_password > /dev/null
        sudo chmod 600 /root/.mysql_root_password
        
        # Display password to user immediately
        ui_msg "MariaDB Root Password Generated" "🔐 MariaDB Root Password Created!\n\n📋 ROOT PASSWORD: $root_pass\n\n📝 Important:\n• This password has been saved to /root/.mysql_root_password\n• Copy this password now for your records\n• You can view it later in Database Management > Show Credentials\n\n🔧 Access Methods:\n• Command line: mysql -u root -p'$root_pass'\n• Sudo access: sudo mysql"
        
        # Log credentials (non-blocking)
        log "MariaDB Root Password Set: $root_pass"
        log "Password saved to: /root/.mysql_root_password"
        log "Password displayed to user during setup"
    else
        log "MariaDB Setup Warning: Password authentication setup may have failed"
    fi
    
    log "MariaDB security setup completed"
}

setup_wordpress_database() {
    local domain="$1"
    
    # Prompt user for database configuration
    ui_msg "WordPress Database Configuration" "🔐 WordPress Database Setup\n\nYou can customize your database settings or use auto-generated values.\n\nCustom settings allow you to:\n• Choose meaningful database names\n• Set your own passwords\n• Maintain consistent naming\n\nAuto-generated settings provide:\n• Unique, secure credentials\n• No naming conflicts\n• Quick setup" >/dev/tty
    
    local use_custom=false
    if ui_yesno "Database Configuration" "Do you want to customize database settings?\n\n• YES: Choose database name, user, and password\n• NO: Use auto-generated secure credentials" >/dev/tty; then
        use_custom=true
    fi
    
    local db_name db_user db_pass
    
    if [[ "$use_custom" == "true" ]]; then
        # Custom database configuration
        ui_msg "Custom Database Setup" "🔧 Custom Database Configuration\n\nPlease provide your preferred database settings.\n\nDatabase names should:\n• Be descriptive (e.g., mysite_wp, blog_db)\n• Use only letters, numbers, and underscores\n• Be unique on this server" >/dev/tty
        
        # Get database name
        while true; do
            db_name=$(ui_input "Database Name" "Enter database name for WordPress:" "wp_${domain//[^a-zA-Z0-9]/_}") || return
            db_name=${db_name:-"wp_${domain//[^a-zA-Z0-9]/_}"}
            
            # Validate database name
            if [[ "$db_name" =~ ^[a-zA-Z0-9_]+$ ]] && [[ ${#db_name} -le 64 ]]; then
                break
            else
                ui_msg "Invalid Database Name" "Database name must:\n• Contain only letters, numbers, and underscores\n• Be 64 characters or less\n• Not be empty\n\nExample: wp_mysite, blog_database" >/dev/tty
            fi
        done
        
        # Get database user
        while true; do
            db_user=$(ui_input "Database User" "Enter database username:" "wp_user_${domain//[^a-zA-Z0-9]/_}") || return
            db_user=${db_user:-"wp_user_${domain//[^a-zA-Z0-9]/_}"}
            
            # Validate username
            if [[ "$db_user" =~ ^[a-zA-Z0-9_]+$ ]] && [[ ${#db_user} -le 32 ]]; then
                break
            else
                ui_msg "Invalid Username" "Username must:\n• Contain only letters, numbers, and underscores\n• Be 32 characters or less\n• Not be empty\n\nExample: wp_user, mysite_user" >/dev/tty
            fi
        done
        
        # Get database password
        db_pass=$(ui_input "Database Password" "Enter database password (leave empty for auto-generated):" "") || return
        if [[ -z "$db_pass" ]]; then
            db_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
            ui_msg "Auto-Generated Password" "🔐 Password auto-generated for security:\n\nPassword: $db_pass\n\n📝 Please save this password - you'll need it for WordPress setup!" >/dev/tty
        fi
    else
        # Auto-generated configuration
        db_name="wp_${domain//[^a-zA-Z0-9]/_}_$(date +%s)"
        db_user="wpuser_$(date +%s)"
        db_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
        
        ui_msg "Auto-Generated Credentials" "🔐 Secure database credentials generated:\n\n• Database: $db_name\n• User: $db_user\n• Password: $db_pass\n\n📝 These will be automatically configured in WordPress!" >/dev/tty
    fi
    
    log "Creating WordPress database: $db_name for domain: $domain"
    log "Database user: $db_user"
    
    # Check MariaDB service first
    if ! systemctl is-active --quiet mariadb; then
        log "ERROR: MariaDB service is not running"
        return 1
    fi
    
    # Ensure MariaDB root access for database operations
    local root_pass
    local auth_method="sudo"
    
    ui_msg "Database Access" "🔐 Checking MariaDB root access...\n\nThis is required to create the WordPress database and user." >/dev/tty
    
    # First, try to get saved root password
    if [[ -f "/root/.mysql_root_password" ]]; then
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
        if [[ -n "$root_pass" ]]; then
            # Test if password authentication works
            if mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
                auth_method="password"
                log "Using saved root password for database operations"
                ui_msg "Root Access" "✅ MariaDB root access verified using saved credentials." >/dev/tty
            else
                log "Saved password authentication failed"
                root_pass=""
            fi
        fi
    fi
    
    # If password auth failed, try sudo
    if [[ "$auth_method" != "password" ]]; then
        if sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
            auth_method="sudo"
            log "Using sudo authentication for database operations"
            ui_msg "Root Access" "✅ MariaDB root access verified using sudo." >/dev/tty
        else
            log "Sudo authentication also failed"
            # Need to prompt for root password
            ui_msg "Root Password Required" "🔑 MariaDB root access is required to create the WordPress database.\n\nPlease enter the MariaDB root password, or we can attempt to reset it." >/dev/tty
            
            local max_attempts=3
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                root_pass=$(ui_input "MariaDB Root Password" "Enter MariaDB root password (attempt $attempt/$max_attempts):" "" "password") || {
                    if ui_yesno "Reset Root Password" "Would you like to attempt resetting the MariaDB root password instead?\n\n⚠️  This will stop MariaDB temporarily." >/dev/tty; then
                        if reset_mariadb_root_password; then
                            # Try to get the new password
                            if [[ -f "/root/.mysql_root_password" ]]; then
                                root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
                                if mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
                                    auth_method="password"
                                    ui_msg "Root Access" "✅ MariaDB root password reset successfully." >/dev/tty
                                    break
                                fi
                            fi
                        fi
                        ui_msg "Reset Failed" "❌ Failed to reset MariaDB root password. Please try entering the password manually." >/dev/tty
                        continue
                    else
                        return 1
                    fi
                }
                
                if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
                    auth_method="password"
                    # Save the working password
                    echo "$root_pass" | sudo tee /root/.mysql_root_password >/dev/null
                    sudo chmod 600 /root/.mysql_root_password
                    ui_msg "Root Access" "✅ MariaDB root access verified with provided password." >/dev/tty
                    break
                else
                    ui_msg "Authentication Failed" "❌ Invalid password. Please try again." >/dev/tty
                    ((attempt++))
                fi
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                ui_msg "Access Failed" "❌ Failed to establish MariaDB root access after $max_attempts attempts.\n\nWordPress installation cannot continue without database access." >/dev/tty
                return 1
            fi
        fi
    fi
    
    log "Authentication method: $auth_method"
    
    # Function to execute MySQL commands with proper error handling
    execute_mysql_cmd() {
        local cmd="$1"
        local operation="$2"
        local result
        
        if [[ "$auth_method" == "password" ]]; then
            if result=$(mysql -u root -p"$root_pass" -e "$cmd" 2>&1); then
                log "SUCCESS: $operation completed with password auth"
                return 0
            else
                log "FAILED: $operation with password auth: $result"
                # Try sudo fallback
                if result=$(sudo mysql -e "$cmd" 2>&1); then
                    log "SUCCESS: $operation completed with sudo fallback"
                    return 0
                else
                    log "FAILED: $operation with sudo fallback: $result"
                    return 1
                fi
            fi
        else
            if result=$(sudo mysql -e "$cmd" 2>&1); then
                log "SUCCESS: $operation completed with sudo"
                return 0
            else
                log "FAILED: $operation with sudo: $result"
                return 1
            fi
        fi
    }
    
    # Create database
    log "Creating database: $db_name"
    execute_mysql_cmd "CREATE DATABASE IF NOT EXISTS \`${db_name}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" "Database creation" || {
        log "ERROR: Failed to create database $db_name"
        return 1
    }
    
    # Create user
    log "Creating database user: $db_user"
    execute_mysql_cmd "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" "User creation" || {
        log "ERROR: Failed to create user $db_user"
        return 1
    }
    
    # Grant privileges
    log "Granting privileges to user: $db_user on database: $db_name"
    execute_mysql_cmd "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';" "Grant privileges" || {
        log "ERROR: Failed to grant privileges"
        return 1
    }
    
    # Flush privileges
    log "Flushing privileges"
    execute_mysql_cmd "FLUSH PRIVILEGES;" "Flush privileges" || {
        log "ERROR: Failed to flush privileges"
        return 1
    }
    
    # Verify database creation
    log "Verifying database creation"
    local db_exists
    if [[ "$auth_method" == "password" ]]; then
        db_exists=$(mysql -u root -p"$root_pass" -e "SHOW DATABASES LIKE '${db_name}';" 2>/dev/null | tail -n +2)
    else
        db_exists=$(sudo mysql -e "SHOW DATABASES LIKE '${db_name}';" 2>/dev/null | tail -n +2)
    fi
    
    if [[ -n "$db_exists" ]]; then
        log "SUCCESS: Database $db_name verified to exist"
        
        # Test WordPress user connection
        log "Testing WordPress user connection"
        if mysql -u "$db_user" -p"$db_pass" -e "USE \`${db_name}\`; SELECT 1;" >/dev/null 2>&1; then
            log "SUCCESS: WordPress user can connect to database"
            echo "${db_name}:${db_user}:${db_pass}"
            return 0
        else
            log "ERROR: WordPress user cannot connect to database"
            return 1
        fi
    else
        log "ERROR: Database $db_name was not created or cannot be verified"
        return 1
    fi
}

setup_wordpress_database_custom() {
    local domain="$1"
    
    # Display user management explanation
    ui_msg "Database User Management" "🔐 WordPress Database Setup\n\n📋 User Management Explanation:\n\n• ROOT USER: Administrative access to MariaDB\n  - Username: root\n  - Used for: Creating databases, managing users\n  - Authentication: Password or sudo access\n\n• WORDPRESS USER: Dedicated user for each WordPress site\n  - Username: Custom (e.g., wp_user_sitename)\n  - Used for: WordPress application database access\n  - Authentication: Password only\n  - Privileges: Limited to specific database only\n\n🎯 This setup follows security best practices:\n- Separation of administrative and application access\n- Minimal privileges for WordPress users\n- Unique credentials per site"
    
    local db_name
    db_name=$(ui_input "Database Name" "Enter WordPress database name:\n\n💡 Suggestions:\n• wp_${domain//[^a-zA-Z0-9]/_}\n• ${domain//[^a-zA-Z0-9]/_}_wp\n• custom_name_wp" "wp_${domain//[^a-zA-Z0-9]/_}") || return
    
    # Validate database name
    if [[ ! "$db_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        ui_msg "Invalid Name" "Database name can only contain letters, numbers, and underscores."
        return 1
    fi
    
    local db_user
    db_user=$(ui_input "Database User" "Enter WordPress database username:\n\n💡 Suggestions:\n• wp_user_${domain//[^a-zA-Z0-9]/_}\n• ${domain//[^a-zA-Z0-9]/_}_user\n• wpuser_$(date +%s)" "wp_user_${domain//[^a-zA-Z0-9]/_}") || return
    
    # Validate username
    if [[ ! "$db_user" =~ ^[a-zA-Z0-9_]+$ ]]; then
        ui_msg "Invalid Username" "Username can only contain letters, numbers, and underscores."
        return 1
    fi
    
    local db_pass
    db_pass=$(ui_input "Database Password" "Enter database password:\n\n🔒 Password Requirements:\n• Minimum 8 characters\n• Mix of letters, numbers, symbols\n• Avoid spaces and quotes\n\n💡 Leave empty for auto-generated secure password" "") || return
    
    if [[ -z "$db_pass" ]]; then
        db_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c 16)
        ui_msg "Generated Password" "🔐 Auto-generated secure password:\n\n$db_pass\n\n📝 Please save this password securely!"
    else
        # Validate password strength
        if [[ ${#db_pass} -lt 8 ]]; then
            ui_msg "Weak Password" "Password must be at least 8 characters long."
            return 1
        fi
    fi
    
    log "Creating custom WordPress database: $db_name with user: $db_user"
    
    # Check MariaDB service first
    if ! systemctl is-active --quiet mariadb; then
        ui_msg "Service Error" "MariaDB service is not running. Please start MariaDB first."
        return 1
    fi
    
    # Get root authentication method
    local root_pass
    local auth_method="sudo"
    if [[ -f "/root/.mysql_root_password" ]]; then
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
        if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
            auth_method="password"
        fi
    fi
    
    # Function to execute MySQL commands with proper error handling
    execute_mysql_cmd() {
        local cmd="$1"
        local operation="$2"
        local result
        
        if [[ "$auth_method" == "password" ]]; then
            if result=$(mysql -u root -p"$root_pass" -e "$cmd" 2>&1); then
                log "SUCCESS: $operation completed with password auth"
                return 0
            else
                log "FAILED: $operation with password auth: $result"
                ui_msg "Database Error" "Failed: $operation\n\nError: $result\n\nTrying alternative authentication..."
                # Try sudo fallback
                if result=$(sudo mysql -e "$cmd" 2>&1); then
                    log "SUCCESS: $operation completed with sudo fallback"
                    return 0
                else
                    log "FAILED: $operation with sudo fallback: $result"
                    ui_msg "Database Error" "Failed: $operation\n\nError: $result"
                    return 1
                fi
            fi
        else
            if result=$(sudo mysql -e "$cmd" 2>&1); then
                log "SUCCESS: $operation completed with sudo"
                return 0
            else
                log "FAILED: $operation with sudo: $result"
                ui_msg "Database Error" "Failed: $operation\n\nError: $result"
                return 1
            fi
        fi
    }
    
    # Check if database already exists
    local existing_db
    if [[ "$auth_method" == "password" ]]; then
        existing_db=$(mysql -u root -p"$root_pass" -e "SHOW DATABASES LIKE '${db_name}';" 2>/dev/null | tail -n +2)
    else
        existing_db=$(sudo mysql -e "SHOW DATABASES LIKE '${db_name}';" 2>/dev/null | tail -n +2)
    fi
    
    if [[ -n "$existing_db" ]]; then
        if ! ui_yesno "Database Exists" "Database '$db_name' already exists.\n\nDo you want to use the existing database?\n\n⚠️  WARNING: This will create a new user with access to the existing database."; then
            return 1
        fi
    else
        # Create database
        execute_mysql_cmd "CREATE DATABASE \`${db_name}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" "Database creation" || return 1
    fi
    
    # Check if user already exists
    local existing_user
    if [[ "$auth_method" == "password" ]]; then
        existing_user=$(mysql -u root -p"$root_pass" -e "SELECT User FROM mysql.user WHERE User='${db_user}' AND Host='localhost';" 2>/dev/null | tail -n +2)
    else
        existing_user=$(sudo mysql -e "SELECT User FROM mysql.user WHERE User='${db_user}' AND Host='localhost';" 2>/dev/null | tail -n +2)
    fi
    
    if [[ -n "$existing_user" ]]; then
        if ui_yesno "User Exists" "User '$db_user' already exists.\n\nDo you want to update the password and grant access to '$db_name'?"; then
            # Update existing user password
            execute_mysql_cmd "ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" "User password update" || return 1
        else
            return 1
        fi
    else
        # Create new user
        execute_mysql_cmd "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" "User creation" || return 1
    fi
    
    # Grant privileges
    execute_mysql_cmd "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';" "Grant privileges" || return 1
    
    # Flush privileges
    execute_mysql_cmd "FLUSH PRIVILEGES;" "Flush privileges" || return 1
    
    # Test WordPress user connection
    if mysql -u "$db_user" -p"$db_pass" -e "USE \`${db_name}\`; SELECT 1;" >/dev/null 2>&1; then
        ui_msg "Database Setup Complete" "✅ WordPress Database Setup Successful!\n\n🔐 Database Credentials:\n• Database Name: $db_name\n• Username: $db_user\n• Password: $db_pass\n• Host: localhost\n\n👤 User Management Summary:\n• ROOT USER: Administrative access (existing)\n• WORDPRESS USER: '$db_user' (dedicated for this site)\n• Database: '$db_name' (exclusive access)\n\n🔒 Security: WordPress user has minimal privileges"
        echo "${db_name}:${db_user}:${db_pass}"
    else
        ui_msg "Connection Test Failed" "Database and user created but connection test failed.\n\nPlease check the credentials manually."
        return 1
    fi
}

setup_wordpress_files() {
    local domain="$1"
    local db_info="$2"
    local site_dir="/var/www/$domain"
    
    log "Setting up WordPress files for $domain"
    
    # Parse database info
    IFS=':' read -r db_name db_user db_pass <<< "$db_info"
    
    # Create site directory with proper initial permissions
    sudo mkdir -p "$site_dir"
    
    # Download WordPress
    ui_msg "Downloading WordPress" "Downloading latest WordPress...\n\n⏳ This process is automatic - please wait..."
    wget -q https://wordpress.org/latest.tar.gz -O /tmp/wordpress.tar.gz || {
        ui_msg "Download Error" "Failed to download WordPress. Please check your internet connection."
        return 1
    }
    
    tar -xzf /tmp/wordpress.tar.gz -C /tmp
    sudo rsync -a /tmp/wordpress/ "$site_dir/"
    rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
    
    # Configure WordPress with sudo
    sudo cp "$site_dir/wp-config-sample.php" "$site_dir/wp-config.php"
    
    # Database configuration - escape special characters in passwords
    local escaped_db_name="${db_name//\'/\\\'}"
    local escaped_db_user="${db_user//\'/\\\'}"
    local escaped_db_pass="${db_pass//\'/\\\'}"
    
    # Use more robust sed replacements with different delimiters (with sudo)
    sudo sed -i "s|database_name_here|${escaped_db_name}|g" "$site_dir/wp-config.php"
    sudo sed -i "s|username_here|${escaped_db_user}|g" "$site_dir/wp-config.php"
    sudo sed -i "s|password_here|${escaped_db_pass}|g" "$site_dir/wp-config.php"
    sudo sed -i "s|localhost|localhost|g" "$site_dir/wp-config.php"
    
    # Verify database configuration was applied (using fixed-string grep to avoid regex issues)
    if grep -F "$escaped_db_name" "$site_dir/wp-config.php" >/dev/null 2>&1 && \
       grep -F "$escaped_db_user" "$site_dir/wp-config.php" >/dev/null 2>&1 && \
       grep -F "$escaped_db_pass" "$site_dir/wp-config.php" >/dev/null 2>&1; then
        log "Database configuration applied successfully to wp-config.php"
        
        # Test database connection
        if mysql -u"$db_user" -p"$db_pass" -h"localhost" -e "USE \`$db_name\`; SELECT 1;" >/dev/null 2>&1; then
            log "Database connection test successful"
        else
            log "WARNING: Database connection test failed - WordPress may have connection issues"
            ui_msg "Database Warning" "⚠️ Database configuration applied but connection test failed.\n\nThis may cause WordPress installation issues.\n\nPlease verify:\n• Database '$db_name' exists\n• User '$db_user' has access\n• Password is correct\n\nContinuing with installation..."
        fi
    else
        log "WARNING: Database configuration may not have been applied correctly"
        # Try alternative method with PHP-style replacement (with sudo)
        sudo tee /tmp/wp-db-config.php > /dev/null << EOF
<?php
\$config_content = file_get_contents('$site_dir/wp-config.php');
\$config_content = str_replace('database_name_here', '$escaped_db_name', \$config_content);
\$config_content = str_replace('username_here', '$escaped_db_user', \$config_content);
\$config_content = str_replace('password_here', '$escaped_db_pass', \$config_content);
file_put_contents('$site_dir/wp-config.php', \$config_content);
echo "Database configuration updated via PHP";
?>
EOF
        sudo php /tmp/wp-db-config.php
        sudo rm -f /tmp/wp-db-config.php
        
        # Test database connection after PHP method
        if mysql -u"$db_user" -p"$db_pass" -h"localhost" -e "USE \`$db_name\`; SELECT 1;" >/dev/null 2>&1; then
            log "Database connection test successful after PHP method"
        else
            log "ERROR: Database connection test failed after both methods"
            ui_msg "Database Error" "❌ Database configuration failed!\n\nWordPress will not be able to connect to the database.\n\nPlease check:\n• Database '$db_name' exists\n• User '$db_user' has proper permissions\n• Password is correct\n• MariaDB is running\n\nYou may need to recreate the database and user."
        fi
    fi
    
    # Add security keys
    local salts
    salts=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null) || {
        log "Warning: Could not fetch WordPress security keys"
        salts="// Security keys could not be fetched automatically"
    }
    
    # Replace the placeholder keys using a temporary file to avoid sed escaping issues
    if [[ -n "$salts" ]]; then
        # Create temporary file with salts
        echo "$salts" > /tmp/wp-salts.txt
        
        # Remove existing placeholder keys
        sudo sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$site_dir/wp-config.php"
        
        # Insert new keys before MySQL settings using a more robust method
        sudo awk '
            /\/\*\* MySQL settings/ {
                while ((getline line < "/tmp/wp-salts.txt") > 0) {
                    print line
                }
                close("/tmp/wp-salts.txt")
                print ""
            }
            { print }
        ' "$site_dir/wp-config.php" > /tmp/wp-config-new.php
        
        sudo mv /tmp/wp-config-new.php "$site_dir/wp-config.php"
        rm -f /tmp/wp-salts.txt
    else
        log "Skipping security keys insertion due to fetch failure"
    fi
    
    # Set proper permissions
    sudo chown -R www-data:www-data "$site_dir"
    sudo find "$site_dir" -type d -exec chmod 755 {} \;
    sudo find "$site_dir" -type f -exec chmod 644 {} \;
    
    # Ensure wp-config.php has correct permissions
    sudo chmod 600 "$site_dir/wp-config.php"
    
    # Create uploads directory with proper permissions
    sudo mkdir -p "$site_dir/wp-content/uploads"
    sudo chown -R www-data:www-data "$site_dir/wp-content/uploads"
    sudo chmod -R 755 "$site_dir/wp-content/uploads"
    
    log "WordPress files setup completed"
}

setup_wordpress_files_custom() {
    local domain="$1"
    local site_dir="$2"
    local db_info="$3"
    
    setup_wordpress_files "$domain" "$db_info"
}

configure_nginx_wordpress() {
    local domain="$1"
    local site_dir="/var/www/$domain"
    
    log "Configuring Nginx for WordPress: $domain"
    
    # Extract base domain name for config file naming (remove .localhost/.local suffix if present)
    local base_domain="$domain"
    if [[ "$domain" == *.localhost ]]; then
        base_domain="${domain%.localhost}"
    elif [[ "$domain" == *.local ]]; then
        base_domain="${domain%.local}"
    fi
    
    # Use full domain for directory path to match where WordPress files are installed
    local actual_site_dir="/var/www/$domain"
    local nginx_conf="/etc/nginx/sites-available/$base_domain"
    
    sudo tee "$nginx_conf" > /dev/null <<EOF
server {
    listen 80;
    server_name $domain www.$domain;
    root $actual_site_dir;
    index index.php index.html index.htm;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # File upload size
    client_max_body_size 100M;
    
    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # PHP processing
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # Additional PHP settings for WordPress
        fastcgi_read_timeout 300;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }
    
    # Security: Block access to sensitive files
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\.user\.ini {
        deny all;
    }
    
    location ~ /wp-config\.php {
        deny all;
    }
    
    # Cache static files
    location ~* \.(css|gif|ico|jpeg|jpg|js|png)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Block XML-RPC attacks
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
    
    # Remove default site if it exists and this is the first site
    if [[ -f "/etc/nginx/sites-enabled/default" ]] && [[ $(ls -1 /etc/nginx/sites-enabled/ | wc -l) -eq 1 ]]; then
        log "Removing default Nginx site"
        sudo rm -f "/etc/nginx/sites-enabled/default"
    fi
    
    # Enable site
    log "Enabling Nginx site: $domain"
    sudo ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/$base_domain"
    
    # Verify the symlink was created correctly
    if [[ ! -L "/etc/nginx/sites-enabled/$base_domain" ]]; then
        log "ERROR: Failed to create symlink for $base_domain"
        return 1
    fi
    
    # Test Nginx configuration
    log "Testing Nginx configuration..."
    if sudo nginx -t 2>&1 | tee -a "$LOGFILE"; then
        log "Nginx configuration test passed"
        
        # Reload Nginx
        log "Reloading Nginx..."
        if sudo systemctl reload nginx 2>&1 | tee -a "$LOGFILE"; then
            log "Nginx reloaded successfully"
            
            # Verify Nginx is running
            if systemctl is-active --quiet nginx; then
                log "Nginx is running and site $domain is configured"
                
                # Show site status
                ui_msg "Site Configured" "✅ Nginx site '$domain' has been configured successfully!\n\n📁 Config file: /etc/nginx/sites-available/$base_domain\n🔗 Enabled at: /etc/nginx/sites-enabled/$base_domain\n🌐 Access at: http://$domain\n\n🔄 Nginx has been reloaded and is running."
            else
                log "WARNING: Nginx is not running after reload"
                ui_msg "Nginx Issue" "⚠️ Site configured but Nginx is not running.\n\nTry: sudo systemctl start nginx"
                return 1
            fi
        else
            log "ERROR: Failed to reload Nginx"
            ui_msg "Reload Failed" "❌ Nginx configuration is valid but reload failed.\n\nCheck: sudo systemctl status nginx"
            return 1
        fi
    else
        log "ERROR: Nginx configuration test failed"
        ui_msg "Config Error" "❌ Nginx configuration test failed!\n\nThe site configuration has been removed.\n\nCheck the logs for details."
        
        # Remove the broken configuration
        sudo rm -f "/etc/nginx/sites-enabled/$base_domain"
        return 1
    fi
}

configure_nginx_wordpress_custom() {
    local domain="$1"
    local site_dir="$2"
    
    configure_nginx_wordpress "$domain"
}

cleanup_wordpress_installation() {
    local domain="$1"
    local site_dir="/var/www/$domain"
    
    log "Starting WordPress cleanup and customization for: $domain"
    
    # Check if wp-cli is available
    if ! command -v wp >/dev/null 2>&1; then
        log "ERROR: wp-cli not found, skipping WordPress cleanup"
        ui_error "WP-CLI Missing" "WordPress cleanup requires wp-cli to be installed.\n\nPlease install wp-cli first or run cleanup manually."
        return 1
    fi
    
    # Check if WordPress is properly installed
    if [[ ! -f "$site_dir/wp-config.php" ]]; then
        log "ERROR: wp-config.php not found, skipping cleanup"
        ui_error "WordPress Not Found" "WordPress installation not found at: $site_dir\n\nPlease complete WordPress installation first."
        return 1
    fi
    
    local cleanup_info="🧹 WordPress Cleanup & Customization\n\n"
    cleanup_info+="This will customize your fresh WordPress installation:\n\n"
    cleanup_info+="🗑️  Remove Default Content:\n"
    cleanup_info+="• Delete default plugins (Akismet, Hello Dolly)\n"
    cleanup_info+="• Remove default themes (Twenty Twenty series)\n"
    cleanup_info+="• Delete sample posts, pages, and comments\n\n"
    cleanup_info+="✨ Install Essentials:\n"
    cleanup_info+="• LiteSpeed Cache plugin\n"
    cleanup_info+="• Hello Elementor theme (clean, fast)\n\n"
    cleanup_info+="⚙️  Configure Settings:\n"
    cleanup_info+="• Set homepage as static page\n"
    cleanup_info+="• Disable comments globally\n"
    cleanup_info+="• Match system timezone and locale\n"
    cleanup_info+="• Clean up dashboard widgets\n\n"
    cleanup_info+="📁 Site: $site_dir\n\n"
    cleanup_info+="Continue with cleanup?"
    
    if ! ui_yesno "WordPress Cleanup" "$cleanup_info"; then
        return
    fi
    
    # Change to WordPress directory
    cd "$site_dir" || {
        ui_error "Directory Error" "Could not access WordPress directory: $site_dir"
        return 1
    }
    
    local cleanup_results=""
    local cleanup_success=true
    
    # Detect system timezone and locale
    local system_tz
    local system_locale
    system_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
    system_locale=$(locale | grep LANG= | cut -d= -f2 | cut -d. -f1 2>/dev/null || echo "en_US")
    
    cleanup_results+="🌍 System Detection:\n"
    cleanup_results+="• Timezone: $system_tz\n"
    cleanup_results+="• Locale: $system_locale\n\n"
    
    # Remove default plugins
    cleanup_results+="🗑️  Removing default plugins...\n"
    if wp plugin delete akismet hello --quiet 2>/dev/null; then
        cleanup_results+="• Default plugins removed ✅\n"
    else
        cleanup_results+="• Default plugins removal failed ❌\n"
        cleanup_success=false
    fi
    
    # Install and activate essential plugins
    cleanup_results+="📦 Installing LiteSpeed Cache...\n"
    if wp plugin install litespeed-cache --activate --quiet 2>/dev/null; then
        cleanup_results+="• LiteSpeed Cache installed ✅\n"
    else
        cleanup_results+="• LiteSpeed Cache installation failed ❌\n"
        cleanup_success=false
    fi
    
    # Install and activate Hello Elementor theme
    cleanup_results+="🎨 Installing Hello Elementor theme...\n"
    if wp theme install hello-elementor --activate --quiet 2>/dev/null; then
        cleanup_results+="• Hello Elementor theme installed ✅\n"
    else
        cleanup_results+="• Hello Elementor theme installation failed ❌\n"
        cleanup_success=false
    fi
    
    # Remove default themes
    cleanup_results+="🗑️  Removing default themes...\n"
    local themes_removed=0
    for theme in twentytwentythree twentytwentyfour twentytwentyfive; do
        if wp theme delete "$theme" --quiet 2>/dev/null; then
            ((themes_removed++))
        fi
    done
    cleanup_results+="• $themes_removed default themes removed ✅\n"
    
    # Delete default posts, pages, and comments
    cleanup_results+="🗑️  Cleaning default content...\n"
    local posts_deleted=0
    local comments_deleted=0
    
    # Count and delete posts
    local post_ids
    post_ids=$(wp post list --format=ids 2>/dev/null || echo "")
    if [[ -n "$post_ids" ]]; then
        if wp post delete $post_ids --force --quiet 2>/dev/null; then
            posts_deleted=$(echo "$post_ids" | wc -w)
        fi
    fi
    
    # Count and delete comments
    local comment_ids
    comment_ids=$(wp comment list --format=ids 2>/dev/null || echo "")
    if [[ -n "$comment_ids" ]]; then
        if wp comment delete $comment_ids --force --quiet 2>/dev/null; then
            comments_deleted=$(echo "$comment_ids" | wc -w)
        fi
    fi
    
    cleanup_results+="• $posts_deleted posts deleted ✅\n"
    cleanup_results+="• $comments_deleted comments deleted ✅\n"
    
    # Create a clean homepage
    cleanup_results+="🏠 Creating homepage...\n"
    if wp post create --post_type=page --post_title='Home' --post_status=publish --quiet 2>/dev/null; then
        local home_id
        home_id=$(wp post list --post_type=page --name=home --format=ids 2>/dev/null)
        if [[ -n "$home_id" ]] && wp option update show_on_front 'page' --quiet 2>/dev/null && wp option update page_on_front "$home_id" --quiet 2>/dev/null; then
            cleanup_results+="• Homepage created and set ✅\n"
        else
            cleanup_results+="• Homepage configuration failed ❌\n"
            cleanup_success=false
        fi
    else
        cleanup_results+="• Homepage creation failed ❌\n"
        cleanup_success=false
    fi
    
    # Disable comments globally
    cleanup_results+="💬 Disabling comments...\n"
    local comment_settings=(
        "default_comment_status:closed"
        "default_ping_status:closed"
        "comment_registration:0"
        "close_comments_for_old_posts:1"
        "comments_notify:0"
        "moderation_notify:0"
    )
    
    local comment_success=true
    for setting in "${comment_settings[@]}"; do
        local key="${setting%:*}"
        local value="${setting#*:}"
        if ! wp option update "$key" "$value" --quiet 2>/dev/null; then
            comment_success=false
        fi
    done
    
    if [[ "$comment_success" == "true" ]]; then
        cleanup_results+="• Comments disabled globally ✅\n"
    else
        cleanup_results+="• Comment settings failed ❌\n"
        cleanup_success=false
    fi
    
    # Create mu-plugin to disable comment support
    if mkdir -p wp-content/mu-plugins 2>/dev/null; then
        cat > wp-content/mu-plugins/disable-comments.php << 'PHP'
<?php
// Disable comment support on all post types
add_action('init', function() {
    $post_types = get_post_types(array('public' => true), 'names');
    foreach ($post_types as $type) {
        remove_post_type_support($type, 'comments');
        remove_post_type_support($type, 'trackbacks');
    }
});

add_action('admin_init', function() {
    $types = get_post_types(array('public' => true), 'names');
    foreach ($types as $type) {
        remove_post_type_support($type, 'comments');
        remove_post_type_support($type, 'trackbacks');
    }
});
PHP
        cleanup_results+="• Comment support disabled ✅\n"
    else
        cleanup_results+="• Comment support disable failed ❌\n"
        cleanup_success=false
    fi
    
    # Set timezone and language
    cleanup_results+="🌍 Setting timezone and locale...\n"
    if wp option update timezone_string "$system_tz" --quiet 2>/dev/null; then
        cleanup_results+="• Timezone set to $system_tz ✅\n"
    else
        cleanup_results+="• Timezone setting failed ❌\n"
        cleanup_success=false
    fi
    
    # Try to install matching language if available
    if wp language core is-installed "$system_locale" >/dev/null 2>&1; then
        if wp site switch-language "$system_locale" --quiet 2>/dev/null; then
            cleanup_results+="• Language set to $system_locale ✅\n"
        else
            cleanup_results+="• Language setting failed ❌\n"
        fi
    else
        cleanup_results+="• System locale $system_locale not available, keeping English ℹ️\n"
    fi
    
    # Hide dashboard widgets
    cleanup_results+="📊 Cleaning dashboard...\n"
    cat > wp-content/mu-plugins/clean-dashboard.php << 'PHP'
<?php
add_action('wp_dashboard_setup', function() {
    remove_meta_box('dashboard_quick_press', 'dashboard', 'side');
    remove_meta_box('dashboard_activity', 'dashboard', 'normal');
    remove_meta_box('dashboard_primary', 'dashboard', 'side'); // WP Events & News
});
PHP
    cleanup_results+="• Dashboard widgets cleaned ✅\n"
    
    # Show final results
    if [[ "$cleanup_success" == "true" ]]; then
        # Get current theme and plugin info
        local current_theme
        local active_plugins
        current_theme=$(wp theme list --status=active --field=name 2>/dev/null || echo "Unknown")
        active_plugins=$(wp plugin list --status=active --field=name 2>/dev/null | tr '\n' ', ' | sed 's/,$//' || echo "None")
        
        cleanup_results+="🎉 Cleanup completed successfully!\n\n"
        cleanup_results+="📊 Final Status:\n"
        cleanup_results+="• Active Theme: $current_theme\n"
        cleanup_results+="• Active Plugins: $active_plugins\n"
        
        ui_info "WordPress Cleanup Complete" "$cleanup_results"
    else
        cleanup_results+="⚠️  Cleanup completed with some errors.\n\nSome operations may have failed. Check the details above."
        ui_info "WordPress Cleanup Finished" "$cleanup_results"
    fi
    
    log "WordPress cleanup completed for: $domain"
}

wordpress_cleanup_menu() {
    log "Entering WordPress cleanup menu"
    
    # Detect WordPress installations
    local wp_sites=()
    if [[ -d "/var/www" ]]; then
        while IFS= read -r -d '' site_dir; do
            local domain
            domain=$(basename "$site_dir")
            if [[ -f "$site_dir/wp-config.php" ]]; then
                wp_sites+=("$domain")
            fi
        done < <(find /var/www -maxdepth 1 -type d -name "*.localhost" -o -name "*.local" -print0 2>/dev/null)
    fi
    
    if [[ ${#wp_sites[@]} -eq 0 ]]; then
        ui_error "No WordPress Sites Found" "No WordPress installations found in /var/www/\n\nPlease install WordPress first using the setup options."
        return
    fi
    
    local cleanup_info="🧹 WordPress Cleanup & Customization\n\n"
    cleanup_info+="Select a WordPress site to clean up and customize:\n\n"
    cleanup_info+="Found ${#wp_sites[@]} WordPress installation(s):\n"
    for site in "${wp_sites[@]}"; do
        cleanup_info+="• $site\n"
    done
    cleanup_info+="\nThis will:\n"
    cleanup_info+="• Remove default content and plugins\n"
    cleanup_info+="• Install essential plugins (LiteSpeed Cache)\n"
    cleanup_info+="• Set up a clean theme (Hello Elementor)\n"
    cleanup_info+="• Configure optimal settings\n"
    cleanup_info+="• Disable comments globally\n"
    cleanup_info+="• Match system timezone and locale\n\n"
    cleanup_info+="⚠️  Requires wp-cli to be installed"
    
    while true; do
        local menu_items=()
        
        # Add WordPress sites to menu
        for site in "${wp_sites[@]}"; do
            menu_items+=("$site" "(.Y.) 🧹 Clean up $site")
        done
        
        menu_items+=("" "(_*_)")
        menu_items+=("zback" "(Z) ← Back to WordPress Menu")
        
        local choice
        choice=$(ui_menu "WordPress Cleanup" "$cleanup_info" $DIALOG_HEIGHT $DIALOG_WIDTH $((${#wp_sites[@]} + 2)) "${menu_items[@]}") || break
        
        case "$choice" in
            back|zback|z|"")
                break
                ;;
            *)
                # Check if choice is a valid WordPress site
                local found=false
                for site in "${wp_sites[@]}"; do
                    if [[ "$choice" == "$site" ]]; then
                        found=true
                        break
                    fi
                done
                
                if [[ "$found" == "true" ]]; then
                    cleanup_wordpress_installation "$choice"
                fi
                ;;
        esac
    done
    
    log "Exiting WordPress cleanup menu"
}

configure_apache_wordpress() {
    local domain="$1"
    local site_dir="/var/www/$domain"
    
    log "Configuring Apache for WordPress: $domain"
    
    local apache_conf="/etc/apache2/sites-available/${domain}.conf"
    sudo tee "$apache_conf" > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $site_dir
    
    # Security headers
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "no-referrer-when-downgrade"
    
    # WordPress directory configuration
    <Directory $site_dir>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Security: Block access to sensitive files
    <Files "wp-config.php">
        Require all denied
    </Files>
    
    <Files ".htaccess">
        Require all denied
    </Files>
    
    <Files ".user.ini">
        Require all denied
    </Files>
    
    # Block XML-RPC attacks
    <Files "xmlrpc.php">
        Require all denied
    </Files>
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF
    
    # Enable required modules
    sudo a2enmod rewrite headers 2>&1 | tee -a "$LOGFILE"
    
    # Enable site
    sudo a2ensite "${domain}.conf" 2>&1 | tee -a "$LOGFILE"
    
    # Test and reload Apache
    if sudo apache2ctl configtest 2>&1 | tee -a "$LOGFILE"; then
        sudo systemctl reload apache2
        log "Apache configuration applied successfully"
    else
        log "ERROR: Apache configuration test failed"
        return 1
    fi
}

configure_apache_wordpress_custom() {
    local domain="$1"
    local site_dir="$2"
    
    configure_apache_wordpress "$domain"
}

show_wordpress_completion() {
    local domain="$1"
    local db_info="$2"
    
    # Parse database info
    IFS=':' read -r db_name db_user db_pass <<< "$db_info"
    
    # Save credentials with comprehensive details
    local creds_file="$BACKUP_DIR/wordpress-${domain}-$(date +%Y%m%d-%H%M%S).txt"
    cat > "$creds_file" <<EOF
WordPress Installation Complete - Full Details
═══════════════════════════════════════════════════════════════
Installation Date: $(date)
Domain: $domain
Site Directory: /var/www/$domain

DATABASE CREDENTIALS:
═══════════════════════════════════════════════════════════════
Database Name: $db_name
Database User: $db_user
Database Password: $db_pass
Database Host: localhost
Database Port: 3306

SITE ACCESS:
═══════════════════════════════════════════════════════════════
Site URL: http://$domain
Admin URL: http://$domain/wp-admin/
WordPress Setup: http://$domain/wp-admin/install.php

SYSTEM INFORMATION:
═══════════════════════════════════════════════════════════════
Web Server: $(if systemctl is-active --quiet nginx; then echo "Nginx"; elif systemctl is-active --quiet apache2; then echo "Apache"; else echo "Unknown"; fi)
PHP Version: ${PHP_VER}
Database: MariaDB
Site Directory: /var/www/$domain
Config File: /var/www/$domain/wp-config.php

NEXT STEPS:
═══════════════════════════════════════════════════════════════
1. Visit: http://$domain
2. Complete the WordPress installation wizard
3. Create your admin account with strong password
4. Configure site title and description
5. Choose your theme and install plugins

SECURITY RECOMMENDATIONS:
═══════════════════════════════════════════════════════════════
- Set up SSL certificate with Let's Encrypt
- Install security plugins (Wordfence, etc.)
- Configure regular backups
- Update WordPress core and plugins regularly
- Use strong passwords for all accounts

TROUBLESHOOTING:
═══════════════════════════════════════════════════════════════
If you encounter 500 errors:
• Check PHP-FPM: sudo systemctl status php${PHP_VER}-fpm
• Check web server: sudo systemctl status nginx (or apache2)
• Check error logs: sudo tail -f /var/log/nginx/error.log
• Verify file permissions: ls -la /var/www/$domain

Support: Keep this file safe - it contains all your installation details!
EOF
    
    # Enhanced completion message with all details
    local completion_msg="🎉 WORDPRESS INSTALLATION COMPLETE! 🎉\n\n"
    completion_msg+="═══════════════════════════════════════════════════════════════\n"
    completion_msg+="🌐 SITE ACCESS:\n"
    completion_msg+="   Site URL: http://$domain\n"
    completion_msg+="   Admin URL: http://$domain/wp-admin/\n"
    completion_msg+="   Setup URL: http://$domain/wp-admin/install.php\n\n"
    completion_msg+="🗄️  DATABASE CREDENTIALS:\n"
    completion_msg+="   Database Name: $db_name\n"
    completion_msg+="   Database User: $db_user\n"
    completion_msg+="   Database Password: $db_pass\n"
    completion_msg+="   Database Host: localhost\n"
    completion_msg+="   Database Port: 3306\n\n"
    completion_msg+="📁 SYSTEM DETAILS:\n"
    completion_msg+="   Site Directory: /var/www/$domain\n"
    completion_msg+="   Config File: /var/www/$domain/wp-config.php\n"
    completion_msg+="   PHP Version: ${PHP_VER}\n"
    completion_msg+="   Web Server: $(if systemctl is-active --quiet nginx; then echo "Nginx"; elif systemctl is-active --quiet apache2; then echo "Apache"; else echo "Unknown"; fi)\n\n"
    completion_msg+="📝 CREDENTIALS SAVED TO:\n"
    completion_msg+="   $creds_file\n\n"
    completion_msg+="🚀 NEXT STEPS:\n"
    completion_msg+="   1. Visit http://$domain to start WordPress setup\n"
    completion_msg+="   2. Complete the 5-minute installation wizard\n"
    completion_msg+="   3. Create your admin account (use strong password!)\n"
    completion_msg+="   4. Configure site title and description\n"
    completion_msg+="   5. Start customizing your site!\n\n"
    completion_msg+="🔧 TROUBLESHOOTING (if needed):\n"
    completion_msg+="   • Check PHP-FPM: sudo systemctl status php${PHP_VER}-fpm\n"
    completion_msg+="   • Check Nginx: sudo systemctl status nginx\n"
    completion_msg+="   • View error logs: sudo tail -f /var/log/nginx/error.log\n"
    completion_msg+="   • Check permissions: ls -la /var/www/$domain\n\n"
    completion_msg+="🔒 SECURITY TIP: Set up SSL with Let's Encrypt after setup!\n"
    completion_msg+="═══════════════════════════════════════════════════════════════"
    
    ui_info "WordPress Installation Complete!" "$completion_msg"
    
    log "WordPress installation completed for $domain with full details displayed"
}

wordpress_ssl_setup() {
    log "Starting WordPress SSL setup"
    
    # Check if certbot is installed
    if ! is_package_installed "certbot"; then
        if ui_yesno "Install Certbot" "Certbot is required for SSL certificates. Install it now?"; then
            install_package "certbot"
        else
            return
        fi
    fi
    
    # Get domain name (allow optional argument)
    local domain
    if [[ -n "$1" ]]; then
        domain="$1"
    else
        domain=$(ui_input "Domain Name" "Enter domain for SSL certificate:" "") || return
    fi
    
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        ui_msg "Invalid Domain" "SSL certificates cannot be issued for localhost or empty domains.\n\nPlease use a real domain name."
        return
    fi
    
    # Detect web server
    local web_server=""
    if systemctl is-active --quiet nginx; then
        web_server="nginx"
    elif systemctl is-active --quiet apache2; then
        web_server="apache2"
    else
        ui_msg "No Web Server" "No active web server detected. Please start Nginx or Apache first."
        return
    fi
    
    # Install appropriate certbot plugin
    local certbot_plugin=""
    if [[ "$web_server" == "nginx" ]]; then
        if ! is_package_installed "python3-certbot-nginx"; then
            install_package "python3-certbot-nginx"
        fi
        certbot_plugin="nginx"
    else
        if ! is_package_installed "python3-certbot-apache"; then
            install_package "python3-certbot-apache"
        fi
        certbot_plugin="apache"
    fi
    
    # Get email for Let's Encrypt
    local email
    email=$(ui_input "Email Address" "Email for Let's Encrypt notifications:" "") || return
    
    if [[ -z "$email" ]]; then
        ui_msg "Email Required" "Email address is required for Let's Encrypt certificates."
        return
    fi
    
    # Run certbot
    ui_msg "Obtaining SSL Certificate" "Requesting SSL certificate from Let's Encrypt...\n\nThis may take a moment."
    
    if sudo certbot --${certbot_plugin} -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive 2>&1 | tee -a "$LOGFILE"; then
    ui_msg "SSL Success" "SSL certificate installed successfully!\n\nYour site is now available at:\nhttps://$domain\n\nCertbot will automatically renew the certificate."
    else
        ui_msg "SSL Error" "Failed to obtain SSL certificate. Please check:\n\n• Domain DNS points to this server\n• Port 80/443 are open\n• Domain is accessible from internet\n\nCheck logs for details."
    fi
}

setup_local_ssl() {
    local domain="$1"
    local web_server="$2"
    
    log "Setting up local SSL certificate for $domain"
    
    # Create SSL directory
    local ssl_dir="/etc/ssl/local"
    sudo mkdir -p "$ssl_dir"
    
    # Generate local certificate (prefer mkcert if available)
    local cert_file="$ssl_dir/$domain.crt"
    local key_file="$ssl_dir/$domain.key"
    
    if command -v mkcert >/dev/null 2>&1; then
        log "mkcert detected - generating local certificate"
        if ! sudo mkcert -key-file "$key_file" -cert-file "$cert_file" "$domain" "www.$domain" 2>/dev/null; then
            log_warning "mkcert failed, falling back to self-signed OpenSSL certificate"
            sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$key_file" \
                -out "$cert_file" \
                -subj "/C=US/ST=Local/L=Local/O=Local Development/CN=$domain" \
                -extensions v3_req \
                -config <(cat /etc/ssl/openssl.cnf <(printf "\n[v3_req]\nsubjectAltName=DNS:$domain,DNS:*.$domain,IP:127.0.0.1")) 2>/dev/null || {
                log_error "Failed to generate SSL certificate"
                return 1
            }
        fi
    else
        log "mkcert not found - generating self-signed OpenSSL certificate"
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -subj "/C=US/ST=Local/L=Local/O=Local Development/CN=$domain" \
            -extensions v3_req \
            -config <(cat /etc/ssl/openssl.cnf <(printf "\n[v3_req]\nsubjectAltName=DNS:$domain,DNS:*.$domain,IP:127.0.0.1")) 2>/dev/null || {
            log_error "Failed to generate SSL certificate"
            return 1
        }
    fi
    
    # Set proper permissions
    sudo chmod 600 "$key_file"
    sudo chmod 644 "$cert_file"
    
    # Update web server configuration for SSL
    if [[ "$web_server" == "nginx" ]]; then
        setup_nginx_ssl "$domain" "$cert_file" "$key_file"
    else
        setup_apache_ssl "$domain" "$cert_file" "$key_file"
    fi
    
    log "Local SSL certificate setup completed for $domain"
    return 0
}

# Dedicated SSL setup menu for existing WordPress installations
wordpress_ssl_setup_menu() {
    log "Entering wordpress_ssl_setup_menu"

    while true; do
        # Discover WordPress sites
        local wp_sites=()
        if [[ -d "/var/www" ]]; then
            while IFS= read -r -d '' dir; do
                local site_name
                site_name=$(basename "$dir")
                if [[ -f "$dir/wp-config.php" ]]; then
                    wp_sites+=("$site_name")
                fi
            done < <(find /var/www -maxdepth 1 -type d -print0 2>/dev/null)
        fi

        local info="WordPress SSL Setup\n\n"
        if [[ ${#wp_sites[@]} -eq 0 ]]; then
            info+="No WordPress installations detected under /var/www.\n\nUse WordPress Installation to create a site first."
        else
            info+="Choose a site, then select Local or Live SSL:\n"
            info+="═══════════════════════════════════════════════════════════\n"
            info+="Local (Development): .localhost domains recommended → self-signed or mkcert.\n"
            info+="Live (Production): Public domain via Let’s Encrypt with Certbot.\n\n"
            info+="Live prerequisites:\n"
            info+="• DNS points to this server (A/AAAA record)\n"
            info+="• If using Cloudflare, set records to your server’s IP (proxied OK)\n"
            info+="• Ports 80/443 open and reachable\n"
            info+="• Web server active (Nginx or Apache)\n"
        fi

        local menu_items=()
        for site in "${wp_sites[@]}"; do
            local ssl_icon="🔓"
            if [[ -f "/etc/letsencrypt/live/$site/fullchain.pem" ]] || [[ -f "/etc/ssl/local/$site.crt" ]]; then
                ssl_icon="🔒"
            fi
            menu_items+=("$site" "$ssl_icon $site")
        done
        menu_items+=("" "(_*)")
        menu_items+=("zback" "(Z) ← Back to WordPress Menu")

        local choice
        choice=$(ui_menu "SSL Setup" "$info" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break

        case "$choice" in
            back|zback|z|"")
                break
                ;;
            *)
                if [[ " ${wp_sites[*]} " =~ " $choice " ]]; then
                    wordpress_ssl_method_menu "$choice"
                fi
                ;;
        esac
    done

    log "Exiting wordpress_ssl_setup_menu"
}

wordpress_ssl_method_menu() {
    local domain="$1"

    # Detect web server for local SSL config
    local web_server=""
    if systemctl is-active --quiet nginx; then
        web_server="nginx"
    elif systemctl is-active --quiet apache2; then
        web_server="apache2"
    fi

    local info="SSL for: $domain\n\n"
    if [[ -z "$web_server" ]]; then
        info+="No active web server detected. Please start Nginx or Apache before configuring SSL."
    else
        info+="Choose SSL type:\n"
        info+="═══════════════════════════════════════════════════════════\n"
        info+="Local (Development): Generates a local certificate (mkcert if available, otherwise self-signed). Best for .localhost domains.\n\n"
        info+="Live (Production): Obtains a certificate from Let’s Encrypt via Certbot.\n"
        info+="Requirements: DNS points to this server, Cloudflare (if used) is set to your server IP, and ports 80/443 are open.\n"
    fi

    local menu_items=(
        "local" "🔒 Local SSL (self-signed/mkcert)"
        "live" "🌍 Live SSL (Let’s Encrypt via Certbot)"
        "" "(_*)"
        "zback" "(Z) ← Back to Site List"
    )

    local choice
    choice=$(ui_menu "Choose SSL Type" "$info" $DIALOG_HEIGHT $DIALOG_WIDTH 8 "${menu_items[@]}") || return

    case "$choice" in
        local)
            if [[ -z "$web_server" ]]; then
                ui_error "No web server detected. Start Nginx or Apache first."
                return
            fi
            ui_msg "Configuring Local SSL" "Generating a local certificate and updating $web_server configuration for $domain."
            if setup_local_ssl "$domain" "$web_server"; then
                ui_success "Local SSL configured: https://$domain"
            else
                ui_error "Local SSL setup failed for $domain"
            fi
            ;;
        live)
            # Route to Let’s Encrypt flow, passing domain
            wordpress_ssl_setup "$domain"
            ;;
        back|zback|z|"")
            ;;
    esac
}

setup_nginx_ssl() {
    local domain="$1"
    local cert_file="$2"
    local key_file="$3"
    
    local nginx_conf="/etc/nginx/sites-available/$domain"
    
    # Add SSL server block to existing configuration
    sudo tee -a "$nginx_conf" > /dev/null <<EOF

# HTTPS server block
server {
    listen 443 ssl http2;
    server_name $domain www.$domain;
    root /var/www/$domain;
    index index.php index.html index.htm;
    
    # SSL Configuration
    ssl_certificate $cert_file;
    ssl_certificate_key $key_file;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # File upload size
    client_max_body_size 100M;
    
    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # PHP processing
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # Additional PHP settings for WordPress
        fastcgi_read_timeout 300;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }
    
    # Security: Block access to sensitive files
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\.user\.ini {
        deny all;
    }
    
    location ~ /wp-config\.php {
        deny all;
    }
    
    # Cache static files
    location ~* \.(css|gif|ico|jpeg|jpg|js|png)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Block XML-RPC attacks
    location = /xmlrpc.php {
        deny all;
    }
}
EOF
    
    # Test and reload nginx
    if sudo nginx -t; then
        sudo systemctl reload nginx
        return 0
    else
        log_error "Nginx SSL configuration test failed"
        return 1
    fi
}

setup_apache_ssl() {
    local domain="$1"
    local cert_file="$2"
    local key_file="$3"
    
    # Enable SSL module
    sudo a2enmod ssl
    
    # Create SSL virtual host
    local apache_ssl_conf="/etc/apache2/sites-available/${domain}-ssl.conf"
    sudo tee "$apache_ssl_conf" > /dev/null <<EOF
<VirtualHost *:443>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot /var/www/$domain
    
    # SSL Configuration
    SSLEngine on
    SSLCertificateFile $cert_file
    SSLCertificateKeyFile $key_file
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder off
    
    # Security headers
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    
    # WordPress configuration
    <Directory /var/www/$domain>
        AllowOverride All
        Require all granted
    </Directory>
    
    # PHP processing
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/var/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>
    
    ErrorLog \${APACHE_LOG_DIR}/${domain}_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_ssl_access.log combined
</VirtualHost>
EOF
    
    # Enable the SSL site
    sudo a2ensite "${domain}-ssl.conf"
    
    # Test and reload Apache
    if sudo apache2ctl configtest; then
        sudo systemctl reload apache2
        return 0
    else
        log_error "Apache SSL configuration test failed"
        return 1
    fi
}

wordpress_security_hardening() {
    log "Starting WordPress security hardening"
    
    local domain
    domain=$(ui_input "Domain Name" "Enter WordPress domain to harden:" "") || return
    
    if [[ -z "$domain" ]]; then
        return
    fi
    
    local site_dir="/var/www/$domain"
    
    if [[ ! -d "$site_dir" ]]; then
        ui_msg "Site Not Found" "WordPress installation not found at $site_dir"
        return
    fi
    
    local security_options=(
        "file-permissions" "Fix File Permissions" on
        "disable-file-editing" "Disable File Editing in Admin" on
        "hide-wp-version" "Hide WordPress Version" on
        "limit-login-attempts" "Install Login Security Plugin" off
        "security-headers" "Add Security Headers" on
        "disable-xmlrpc" "Disable XML-RPC" on
    )
    
    local selected
    selected=$(ui_checklist "WordPress Security" "Select security hardening options:" 20 80 10 "${security_options[@]}") || return
    
    if [[ -z "$selected" ]]; then
        return
    fi
    
    ui_msg "Applying Security" "Applying selected security hardening options..."
    
    # Apply selected security measures
    for option in $selected; do
        case "$option" in
            "file-permissions")
                apply_wp_file_permissions "$site_dir"
                ;;
            "disable-file-editing")
                apply_wp_disable_editing "$site_dir"
                ;;
            "hide-wp-version")
                apply_wp_hide_version "$site_dir"
                ;;
            "security-headers")
                apply_wp_security_headers "$domain"
                ;;
            "disable-xmlrpc")
                apply_wp_disable_xmlrpc "$site_dir"
                ;;
        esac
    done
    
    ui_msg "Security Applied" "WordPress security hardening completed for $domain"
}

apply_wp_file_permissions() {
    local site_dir="$1"
    log "Applying WordPress file permissions to $site_dir"
    
    sudo chown -R www-data:www-data "$site_dir"
    sudo find "$site_dir" -type d -exec chmod 755 {} \;
    sudo find "$site_dir" -type f -exec chmod 644 {} \;
    sudo chmod 600 "$site_dir/wp-config.php"
}

apply_wp_disable_editing() {
    local site_dir="$1"
    log "Disabling WordPress file editing"
    
    if ! grep -q "DISALLOW_FILE_EDIT" "$site_dir/wp-config.php"; then
        sudo sed -i "/\/\* That's all, stop editing/i define('DISALLOW_FILE_EDIT', true);" "$site_dir/wp-config.php"
    fi
}

apply_wp_hide_version() {
    local site_dir="$1"
    log "Hiding WordPress version"
    
    local functions_php="$site_dir/wp-content/themes/*/functions.php"
    for file in $functions_php; do
        if [[ -f "$file" ]]; then
            if ! grep -q "remove_action.*wp_head.*wp_generator" "$file"; then
                echo "remove_action('wp_head', 'wp_generator');" | sudo tee -a "$file" > /dev/null
            fi
        fi
    done
}

apply_wp_security_headers() {
    local domain="$1"
    log "Adding security headers for $domain"
    
    # This is already handled in the web server configuration
    # Just log that it's already applied
    log "Security headers already applied in web server configuration"
}

apply_wp_disable_xmlrpc() {
    local site_dir="$1"
    log "Disabling XML-RPC"
    
    if ! grep -q "xmlrpc_enabled" "$site_dir/wp-config.php"; then
        sudo sed -i "/\/\* That's all, stop editing/i add_filter('xmlrpc_enabled', '__return_false');" "$site_dir/wp-config.php"
    fi
}

show_wordpress_status() {
    log "Showing WordPress sites status"
    
    while true; do
        local status_info="WordPress\n\n"
        
        # Check for WordPress installations
        local wp_sites=()
        if [[ -d "/var/www" ]]; then
            while IFS= read -r -d '' dir; do
                local site_name
                site_name=$(basename "$dir")
                if [[ -f "$dir/wp-config.php" ]]; then
                    wp_sites+=("$site_name")
                fi
            done < <(find /var/www -maxdepth 1 -type d -print0 2>/dev/null)
        fi
        
        if [[ ${#wp_sites[@]} -eq 0 ]]; then
            status_info+="No WordPress installations found in /var/www/\n\n"
            status_info+="Use the WordPress Installation menu to set up new sites.\n\n"
        else
            status_info+="WordPress Sites (${#wp_sites[@]} found):\n"
            status_info+="═══════════════════════════════════════════════════════════\n"
            for site in "${wp_sites[@]}"; do
                local site_dir="/var/www/$site"
                
                # Quick status check
                local status_icon="❌"
                local ssl_icon="🔓"
                local access_icon="❌"
                
                # Check if site is properly configured
                if [[ -f "/etc/nginx/sites-available/$site" && -L "/etc/nginx/sites-enabled/$site" ]] || \
                   [[ -f "/etc/apache2/sites-available/${site}.conf" ]]; then
                    status_icon="✅"
                fi
                
                # Check SSL
                if [[ -f "/etc/letsencrypt/live/$site/fullchain.pem" ]]; then
                    ssl_icon="🔒"
                fi
                
                # Quick accessibility test
                if command -v curl >/dev/null 2>&1; then
                    if curl -s -o /dev/null -w "%{http_code}" "http://$site" --connect-timeout 3 --max-time 5 | grep -q "200\|301\|302"; then
                        access_icon="🌍"
                    fi
                fi
                
                status_info+="$status_icon $ssl_icon $access_icon  $site\n"
            done
            status_info+="\n"
        fi
        
        # Web server status
        status_info+="Services:\n"
        status_info+="═══════════════════════════════════════════════════════════\n"
        if systemctl is-active --quiet nginx; then
            status_info+="🟢 Nginx: Running\n"
        else
            status_info+="🔴 Nginx: Not running\n"
        fi
        
        if systemctl is-active --quiet apache2; then
            status_info+="🟢 Apache: Running\n"
        else
            status_info+="🔴 Apache: Not running\n"
        fi
        
        if systemctl is-active --quiet mariadb; then
            status_info+="🟢 MariaDB: Running\n"
        else
            status_info+="🔴 MariaDB: Not running\n"
        fi
        
        status_info+="\nLegend: ✅=Configured 🔒=SSL 🌍=Accessible\n"
        
        # Create menu items for site management
        local menu_items=()
        if [[ ${#wp_sites[@]} -gt 0 ]]; then
            menu_items+=("manage" "🔧 Manage Sites")
            menu_items+=("" "(_*_)")
        fi
        menu_items+=("install" "➕ Install New WordPress Site")
        menu_items+=("refresh" "🔄 Refresh Status")
        menu_items+=("zback" "(Z) ← Back to Main Menu")
        
        local choice
        choice=$(ui_menu "WordPress" "$status_info" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            manage)
                show_wordpress_site_management "${wp_sites[@]}"
                ;;
            install)
                show_wordpress_setup_menu
                ;;
            refresh)
                # Just loop back to refresh the display
                ;;
            back|zback|z|"")
                break
                ;;
        esac
    done
}

show_wordpress_site_management() {
    local wp_sites=("$@")
    
    while true; do
        local status_info="WordPress Site Management\n\n"
        status_info+="Select a site to manage:\n"
        status_info+="═══════════════════════════════════════════════════════════\n"
        
        local menu_items=()
        for site in "${wp_sites[@]}"; do
            local site_dir="/var/www/$site"
            local status_indicators=""
            
            # Check configuration status
            if [[ -f "/etc/nginx/sites-available/$site" ]]; then
                if [[ -L "/etc/nginx/sites-enabled/$site" ]]; then
                    status_indicators+="✅"
                else
                    status_indicators+="⚠️"
                fi
            elif [[ -f "/etc/apache2/sites-available/${site}.conf" ]]; then
                if sudo a2ensite "${site}.conf" --quiet 2>/dev/null && sudo apache2ctl -S 2>/dev/null | grep -q "$site"; then
                    status_indicators+="✅"
                else
                    status_indicators+="⚠️"
                fi
            else
                status_indicators+="❌"
            fi
            
            # Check SSL status
            if [[ -f "/etc/letsencrypt/live/$site/fullchain.pem" ]]; then
                status_indicators+=" 🔒"
            else
                status_indicators+=" 🔓"
            fi
            
            # Check accessibility
            if command -v curl >/dev/null 2>&1; then
                if curl -s -o /dev/null -w "%{http_code}" "http://$site" --connect-timeout 5 --max-time 10 | grep -q "200\|301\|302"; then
                    status_indicators+=" 🌍"
                else
                    status_indicators+=" ⚠️"
                fi
            fi
            
            menu_items+=("$site" "$status_indicators $site")
        done
        
        menu_items+=("" "(_*_)")
        menu_items+=("zback" "(Z) ← Back to Status View")
        
        local choice
        choice=$(ui_menu "WordPress Site Management" "$status_info" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            back|zback|z|"")
                break
                ;;
            *)
                if [[ " ${wp_sites[*]} " =~ " $choice " ]]; then
                    show_individual_site_management "$choice"
                fi
                ;;
        esac
    done
}

show_individual_site_management() {
    local site="$1"
    local site_dir="/var/www/$site"
    
    while true; do
        local status_info="Managing Site: $site\n\n"
        
        # Detailed site information
        status_info+="Site Details:\n"
        status_info+="═══════════════════════════════════════════════════════════\n"
        status_info+="📁 Directory: $site_dir\n"
        
        # WordPress version
        local wp_version=""
        if [[ -f "$site_dir/wp-includes/version.php" ]]; then
            wp_version=$(grep "wp_version =" "$site_dir/wp-includes/version.php" | cut -d"'" -f2 2>/dev/null || echo "Unknown")
        fi
        status_info+="🌐 WordPress Version: $wp_version\n"
        
        # Web server configuration
        local web_server=""
        local config_file=""
        local config_content=""
        
        if [[ -f "/etc/nginx/sites-available/$site" ]]; then
            web_server="Nginx"
            config_file="/etc/nginx/sites-available/$site"
            config_content=$(head -20 "$config_file" 2>/dev/null)
        elif [[ -f "/etc/apache2/sites-available/${site}.conf" ]]; then
            web_server="Apache"
            config_file="/etc/apache2/sites-available/${site}.conf"
            config_content=$(head -20 "$config_file" 2>/dev/null)
        fi
        
        if [[ -n "$web_server" ]]; then
            status_info+="🔧 Web Server: $web_server\n"
            status_info+="📄 Config File: $config_file\n"
            
            # Sites enabled status
            if [[ "$web_server" == "Nginx" ]]; then
                if [[ -L "/etc/nginx/sites-enabled/$site" ]]; then
                    status_info+="🔗 Sites Enabled: ✅ Yes\n"
                else
                    status_info+="🔗 Sites Enabled: ❌ No\n"
                fi
            elif [[ "$web_server" == "Apache" ]]; then
                if sudo a2ensite "${site}.conf" --quiet 2>/dev/null && sudo apache2ctl -S 2>/dev/null | grep -q "$site"; then
                    status_info+="🔗 Sites Enabled: ✅ Yes\n"
                else
                    status_info+="🔗 Sites Enabled: ❌ No\n"
                fi
            fi
            
            status_info+="\nConfiguration Preview:\n"
            status_info+="───────────────────────────────────────────────────────────\n"
            status_info+="$config_content\n"
            if [[ $(echo "$config_content" | wc -l) -ge 20 ]]; then
                status_info+="... (truncated, showing first 20 lines)\n"
            fi
        else
            status_info+="⚠️  Web Server: Not configured\n"
        fi
        
        status_info+="\n"
        
        # SSL status
        if [[ -f "/etc/letsencrypt/live/$site/fullchain.pem" ]]; then
            local cert_expiry=""
            cert_expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$site/fullchain.pem" 2>/dev/null | cut -d= -f2)
            status_info+="🔒 SSL Certificate: ✅ Enabled (Expires: ${cert_expiry:-Unknown})\n"
        else
            status_info+="🔒 SSL Certificate: ❌ Not configured\n"
        fi
        
        # Database connection test and detailed diagnostics
        local db_status="❌"
        local db_error_msg=""
        local db_tables_count="0"
        local wp_tables_exist="❌"
        
        if [[ -f "$site_dir/wp-config.php" ]]; then
            local db_name db_user db_pass db_host
            db_name=$(grep "DB_NAME" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            db_user=$(grep "DB_USER" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            db_pass=$(grep "DB_PASSWORD" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            db_host=$(grep "DB_HOST" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            
            if [[ -n "$db_name" && -n "$db_user" ]]; then
                # Test database connection
                local db_test_result
                if db_test_result=$(mysql -u"$db_user" -p"$db_pass" -h"${db_host:-localhost}" -e "USE \`$db_name\`; SELECT 'Connection OK' as status;" 2>&1); then
                    if echo "$db_test_result" | grep -q "Connection OK"; then
                        db_status="✅ Connected"
                        
                        # Count tables in database
                        db_tables_count=$(mysql -u"$db_user" -p"$db_pass" -h"${db_host:-localhost}" -e "USE \`$db_name\`; SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_name';" 2>/dev/null | tail -n1)
                        
                        # Check for WordPress core tables
                        local wp_core_tables=$(mysql -u"$db_user" -p"$db_pass" -h"${db_host:-localhost}" -e "USE \`$db_name\`; SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_name' AND table_name LIKE '%wp_posts' OR table_name LIKE '%wp_users' OR table_name LIKE '%wp_options';" 2>/dev/null | tail -n1)
                        if [[ "$wp_core_tables" -ge 3 ]]; then
                            wp_tables_exist="✅ WordPress tables found"
                        else
                            wp_tables_exist="⚠️ WordPress tables missing ($wp_core_tables/3)"
                        fi
                    else
                        db_status="❌ Connection failed"
                        db_error_msg="Database exists but connection failed"
                    fi
                else
                    db_status="❌ Connection failed"
                    # Parse error message for common issues
                    if echo "$db_test_result" | grep -q "Access denied"; then
                        db_error_msg="Access denied - check credentials"
                    elif echo "$db_test_result" | grep -q "Unknown database"; then
                        db_error_msg="Database '$db_name' does not exist"
                    elif echo "$db_test_result" | grep -q "Can't connect"; then
                        db_error_msg="Cannot connect to MySQL server"
                    else
                        db_error_msg="Connection error: $(echo "$db_test_result" | head -n1)"
                    fi
                fi
            else
                db_status="❌ Missing credentials"
                db_error_msg="Database credentials not found in wp-config.php"
            fi
        else
            db_status="❌ No wp-config.php"
            db_error_msg="WordPress configuration file not found"
        fi
        
        status_info+="🗄️  Database Connection: $db_status\n"
        if [[ -n "$db_error_msg" ]]; then
            status_info+="⚠️  Error: $db_error_msg\n"
        fi
        
        # Database credentials and diagnostics (if available)
        if [[ -f "$site_dir/wp-config.php" ]]; then
            status_info+="\nDatabase Information:\n"
            status_info+="───────────────────────────────────────────────────────────\n"
            status_info+="📊 Database: ${db_name:-❌ Not found}\n"
            status_info+="👤 User: ${db_user:-❌ Not found}\n"
            status_info+="🔑 Password: ${db_pass:+✅ Set}${db_pass:-❌ Not found}\n"
            status_info+="🏠 Host: ${db_host:-localhost}\n"
            status_info+="📋 Tables Count: $db_tables_count\n"
            status_info+="🔧 WordPress Tables: $wp_tables_exist\n"
            
            # Additional database diagnostics
            if [[ "$db_status" == "✅ Connected" ]]; then
                # Check database charset
                local db_charset=$(mysql -u"$db_user" -p"$db_pass" -h"${db_host:-localhost}" -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$db_name';" 2>/dev/null | tail -n1)
                status_info+="🔤 Charset: ${db_charset:-unknown}\n"
                
                # Check if WordPress is installed (has admin user)
                local wp_installed=$(mysql -u"$db_user" -p"$db_pass" -h"${db_host:-localhost}" -e "USE \`$db_name\`; SELECT COUNT(*) FROM wp_users WHERE user_login != '';" 2>/dev/null | tail -n1)
                if [[ "$wp_installed" -gt 0 ]]; then
                    status_info+="👥 WordPress Users: $wp_installed found\n"
                else
                    status_info+="👥 WordPress Users: ❌ No users found (not installed)\n"
                fi
            fi
        fi
        
        # Site accessibility
        local site_accessible="❌"
        if command -v curl >/dev/null 2>&1; then
            local http_code
            http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$site" --connect-timeout 5 --max-time 10)
            if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
                site_accessible="✅ (HTTP $http_code)"
            else
                site_accessible="❌ (HTTP ${http_code:-timeout})"
            fi
        fi
        status_info+="🌍 Site Accessible: $site_accessible\n"
        
        # WordPress admin URL and setup status
        status_info+="\nWordPress Setup:\n"
        status_info+="───────────────────────────────────────────────────────────\n"
        status_info+="🔗 Admin URL: http://$site/wp-admin/\n"
        status_info+="🏠 Site URL: http://$site/\n"
        
        # Check if WordPress is configured
        if [[ -f "$site_dir/wp-config.php" ]]; then
            local wp_configured="❌"
            if mysql -u"$db_user" -p"$db_pass" -h"${db_host:-localhost}" -e "SELECT COUNT(*) FROM ${db_name}.wp_options WHERE option_name='siteurl';" 2>/dev/null | grep -q "1"; then
                wp_configured="✅"
            fi
            status_info+="⚙️  WordPress Configured: $wp_configured\n"
        fi
        
        local menu_items=(
            "" "(_*_)"
            "view-config" "📄 View Full Web Server Config"
            "edit-config" "✏️  Edit Web Server Config"
            "wp-config" "⚙️  View/Edit wp-config.php"
            "test-db" "🗄️  Test Database Connection"
            "repair-db" "🔧 Repair Database Connection"
            "" "(_*_)"
            "file-access" "📁 Grant File Access to Current User"
            "enable-site" "🔗 Enable/Disable Site"
            "test-site" "🧪 Test Site Accessibility"
            "" "(_*_)"
            "delete-site" "🗑️  Delete This Site (DANGER)"
            "" "(_*_)"
            "zback" "(Z) ← Back to Site List"
        )
        
        local choice
        choice=$(ui_menu "Site Management: $site" "$status_info" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            view-config)
                if [[ -n "$config_file" && -f "$config_file" ]]; then
                    local full_config
                    full_config=$(cat "$config_file")
                    ui_info "Configuration: $config_file" "$full_config"
                else
                    ui_error "No configuration file found for $site"
                fi
                ;;
            edit-config)
                if [[ -n "$config_file" && -f "$config_file" ]]; then
                    sudo nano "$config_file"
                    if [[ "$web_server" == "Nginx" ]]; then
                        sudo nginx -t && sudo systemctl reload nginx
                    elif [[ "$web_server" == "Apache" ]]; then
                        sudo apache2ctl configtest && sudo systemctl reload apache2
                    fi
                else
                    ui_error "No configuration file found for $site"
                fi
                ;;
            wp-config)
                if [[ -f "$site_dir/wp-config.php" ]]; then
                    local wp_config_content
                    wp_config_content=$(cat "$site_dir/wp-config.php")
                    ui_info "WordPress Configuration: $site_dir/wp-config.php" "$wp_config_content"
                    
                    if ui_yesno "Edit wp-config.php" "Do you want to edit the WordPress configuration file?"; then
                        sudo nano "$site_dir/wp-config.php"
                    fi
                else
                    ui_error "wp-config.php not found at $site_dir/wp-config.php"
                fi
                ;;
            test-db)
                test_wordpress_database_connection "$site"
                ;;
            repair-db)
                repair_wordpress_database_connection "$site"
                ;;
            file-access)
                grant_file_access_to_user "$site"
                ;;
            enable-site)
                manage_site_enablement "$site" "$web_server"
                ;;
            test-site)
                test_site_accessibility "$site"
                ;;
            delete-site)
                delete_wordpress_site "$site"
                break
                ;;
            back|zback|z|"")
                break
                ;;
        esac
    done
}

manage_site_enablement() {
    local site="$1"
    local web_server="$2"
    
    if [[ "$web_server" == "Nginx" ]]; then
        if [[ -L "/etc/nginx/sites-enabled/$site" ]]; then
            if ui_confirm "Disable site $site?"; then
                sudo rm "/etc/nginx/sites-enabled/$site"
                sudo nginx -t && sudo systemctl reload nginx
                ui_success "Site $site disabled"
            fi
        else
            if ui_confirm "Enable site $site?"; then
                sudo ln -sf "/etc/nginx/sites-available/$site" "/etc/nginx/sites-enabled/$site"
                sudo nginx -t && sudo systemctl reload nginx
                ui_success "Site $site enabled"
            fi
        fi
    elif [[ "$web_server" == "Apache" ]]; then
        if sudo a2ensite "${site}.conf" --quiet 2>/dev/null && sudo apache2ctl -S 2>/dev/null | grep -q "$site"; then
            if ui_confirm "Disable site $site?"; then
                sudo a2dissite "${site}.conf"
                sudo apache2ctl configtest && sudo systemctl reload apache2
                ui_success "Site $site disabled"
            fi
        else
            if ui_confirm "Enable site $site?"; then
                sudo a2ensite "${site}.conf"
                sudo apache2ctl configtest && sudo systemctl reload apache2
                ui_success "Site $site enabled"
            fi
        fi
    else
        ui_error "No web server configuration found for $site"
    fi
}

test_site_accessibility() {
    local site="$1"
    
    local test_info="Testing Site Accessibility: $site\n\n"
    
    # HTTP test
    if command -v curl >/dev/null 2>&1; then
        test_info+="HTTP Test:\n"
        local http_result
        
        # For .localhost domains, test both the full domain and localhost fallback
        if [[ "$site" =~ \.localhost$ ]]; then
            http_result=$(curl -s -o /dev/null -w "HTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes" "http://$site" --connect-timeout 10 --max-time 30 2>&1)
            test_info+="$http_result\n"
            
            # Also test with Host header for local resolution
            test_info+="\nLocal Resolution Test:\n"
            local local_result
            local_result=$(curl -s -o /dev/null -w "HTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes" "http://127.0.0.1" -H "Host: $site" --connect-timeout 10 --max-time 30 2>&1)
            test_info+="$local_result\n\n"
        else
            http_result=$(curl -s -o /dev/null -w "HTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes" "http://$site" --connect-timeout 10 --max-time 30 2>&1)
            test_info+="$http_result\n\n"
        fi
        
        # HTTPS test if SSL is configured
        if [[ -f "/etc/letsencrypt/live/$site/fullchain.pem" ]] || [[ -f "/etc/ssl/certs/$site.crt" ]] || [[ -f "/etc/ssl/local/$site.crt" ]]; then
            test_info+="HTTPS Test:\n"
            local https_result
            if [[ "$site" =~ \.localhost$ ]]; then
                https_result=$(curl -s -o /dev/null -w "HTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes" "https://$site" --connect-timeout 10 --max-time 30 -k 2>&1)
            else
                https_result=$(curl -s -o /dev/null -w "HTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes" "https://$site" --connect-timeout 10 --max-time 30 2>&1)
            fi
            test_info+="$https_result\n\n"
        fi
    else
        test_info+="curl not available for testing\n"
    fi
    
    # DNS resolution test - skip for .localhost domains as they resolve automatically
    if command -v nslookup >/dev/null 2>&1; then
        if [[ "$site" =~ \.localhost$ ]]; then
            test_info+="DNS Resolution:\n"
            test_info+="✅ .localhost domain - automatically resolves to 127.0.0.1\n"
            test_info+="No external DNS lookup required for .localhost domains\n"
        else
            test_info+="DNS Resolution:\n"
            local dns_result
            dns_result=$(nslookup "$site" 2>&1 | head -10)
            test_info+="$dns_result\n"
        fi
    fi
    
    ui_info "Site Test Results" "$test_info"
}

delete_wordpress_site() {
    local site="$1"
    local site_dir="/var/www/$site"
    
    # Extract database credentials from wp-config.php before deletion
    local db_name db_user db_pass db_host
    if [[ -f "$site_dir/wp-config.php" ]]; then
        db_name=$(grep "DB_NAME" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
        db_user=$(grep "DB_USER" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
        db_pass=$(grep "DB_PASSWORD" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
        db_host=$(grep "DB_HOST" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
        db_host=${db_host:-localhost}
    fi
    
    local warning_info="⚠️  WARNING: DELETE WORDPRESS SITE ⚠️\n\n"
    warning_info+="You are about to permanently delete:\n"
    warning_info+="• Site: $site\n"
    warning_info+="• Directory: $site_dir\n"
    warning_info+="• Database: ${db_name:-'N/A'}\n"
    warning_info+="• Database user: ${db_user:-'N/A'}\n"
    warning_info+="• Web server configuration\n"
    warning_info+="• SSL certificates (if any)\n\n"
    warning_info+="This action CANNOT be undone!\n\n"
    warning_info+="Type 'DELETE $site' to confirm:"
    
    local confirmation
    confirmation=$(ui_input "Confirm Site Deletion" "$warning_info")
    
    if [[ "$confirmation" == "DELETE $site" ]]; then
        # Get MySQL root password for database cleanup
        local mysql_root_pass
        if [[ -f "/root/.mysql_root_password" ]]; then
            mysql_root_pass=$(cat /root/.mysql_root_password)
        fi
        
        # Remove database and user
        if [[ -n "$db_name" && -n "$db_user" && -n "$mysql_root_pass" ]]; then
            # Test if database exists and is accessible
            if mysql -uroot -p"$mysql_root_pass" -e "USE \`$db_name\`;" >/dev/null 2>&1; then
                # Drop database
                if mysql -uroot -p"$mysql_root_pass" -e "DROP DATABASE IF EXISTS \`$db_name\`;" >/dev/null 2>&1; then
                    ui_success "Removed database: $db_name"
                else
                    ui_warning "Failed to remove database: $db_name"
                fi
                
                # Drop database user
                if mysql -uroot -p"$mysql_root_pass" -e "DROP USER IF EXISTS '$db_user'@'$db_host';" >/dev/null 2>&1; then
                    ui_success "Removed database user: $db_user"
                else
                    ui_warning "Failed to remove database user: $db_user"
                fi
                
                # Flush privileges
                mysql -uroot -p"$mysql_root_pass" -e "FLUSH PRIVILEGES;" >/dev/null 2>&1
            else
                ui_warning "Database '$db_name' not found or not accessible"
            fi
        elif [[ -n "$db_name" || -n "$db_user" ]]; then
            ui_warning "Could not clean up database - missing credentials or root password"
        fi
        
        # Remove web server configuration (check both domain and base_domain patterns)
        local nginx_removed=false
        for config_name in "$site" "${site%%.*}"; do
            if [[ -f "/etc/nginx/sites-available/$config_name" ]]; then
                sudo rm -f "/etc/nginx/sites-available/$config_name"
                sudo rm -f "/etc/nginx/sites-enabled/$config_name"
                ui_success "Removed Nginx configuration: $config_name"
                nginx_removed=true
            fi
        done
        
        if [[ "$nginx_removed" == true ]]; then
            sudo nginx -t && sudo systemctl reload nginx
        fi
        
        if [[ -f "/etc/apache2/sites-available/${site}.conf" ]]; then
            sudo a2dissite "${site}.conf" 2>/dev/null
            sudo rm -f "/etc/apache2/sites-available/${site}.conf"
            sudo apache2ctl configtest && sudo systemctl reload apache2
        fi
        
        # Remove SSL certificates (check multiple possible certificate names)
        local ssl_removed=false
        for cert_name in "$site" "${site%%.*}" "www.$site" "www.${site%%.*}"; do
            if [[ -d "/etc/letsencrypt/live/$cert_name" ]]; then
                sudo certbot delete --cert-name "$cert_name" --non-interactive >/dev/null 2>&1
                ui_success "Removed SSL certificate: $cert_name"
                ssl_removed=true
            fi
        done
        
        # Remove site directory completely
        if [[ -d "$site_dir" ]]; then
            # Double-check we're not deleting something critical
            if [[ "$site_dir" == "/var/www/$site" && "$site" != "" && "$site" != "." && "$site" != ".." ]]; then
                sudo rm -rf "$site_dir"
                ui_success "Removed site directory: $site_dir"
            else
                ui_warning "Skipped removing directory for safety: $site_dir"
            fi
        fi
        
        # Clean up any remaining broken symlinks in sites-enabled
        sudo find /etc/nginx/sites-enabled/ -type l ! -exec test -e {} \; -delete 2>/dev/null
        
        ui_success "Site $site has been completely removed including database and all files"
    else
        ui_info "Deletion Cancelled" "Site deletion cancelled - nothing was removed"
    fi
}

# Legacy function for backward compatibility
setup_wordpress() {
    show_wordpress_setup_menu
}

# PHP Configuration Management Functions
show_php_settings_menu() {
    log "Entering PHP settings management menu"
    
    while true; do
        local current_settings=""
        local php_ini_path=""
        
        # Find PHP ini file - more comprehensive search
        local php_ini_candidates=(
            "/etc/php/8.3/apache2/php.ini"
            "/etc/php/8.2/apache2/php.ini"
            "/etc/php/8.1/apache2/php.ini"
            "/etc/php/8.0/apache2/php.ini"
            "/etc/php/7.4/apache2/php.ini"
            "/etc/php/8.3/fpm/php.ini"
            "/etc/php/8.2/fpm/php.ini"
            "/etc/php/8.1/fpm/php.ini"
            "/etc/php/8.0/fpm/php.ini"
            "/etc/php/7.4/fpm/php.ini"
            "/etc/php/8.3/cli/php.ini"
            "/etc/php/8.2/cli/php.ini"
            "/etc/php/8.1/cli/php.ini"
            "/etc/php/8.0/cli/php.ini"
            "/etc/php/7.4/cli/php.ini"
        )
        
        # Check predefined candidates first
        for candidate in "${php_ini_candidates[@]}"; do
            if [[ -f "$candidate" ]]; then
                php_ini_path="$candidate"
                break
            fi
        done
        
        # If not found, try to find any PHP ini file
        if [[ -z "$php_ini_path" ]]; then
            php_ini_path=$(find /etc/php -name "php.ini" 2>/dev/null | head -n1)
        fi
        
        # Last resort - check common locations
        if [[ -z "$php_ini_path" ]]; then
            local fallback_paths=(
                "/etc/php.ini"
                "/usr/local/etc/php.ini"
                "/opt/php/etc/php.ini"
            )
            for fallback in "${fallback_paths[@]}"; do
                if [[ -f "$fallback" ]]; then
                    php_ini_path="$fallback"
                    break
                fi
            done
        fi
        
        if [[ -z "$php_ini_path" || ! -f "$php_ini_path" ]]; then
            local error_msg="🚫 PHP Configuration Not Found\n\n"
            error_msg+="Could not locate php.ini file in common locations:\n\n"
            error_msg+="• /etc/php/*/apache2/php.ini\n"
            error_msg+="• /etc/php/*/fpm/php.ini\n"
            error_msg+="• /etc/php/*/cli/php.ini\n"
            error_msg+="• /etc/php.ini\n\n"
            error_msg+="Please ensure PHP is installed:\n"
            error_msg+="sudo apt update && sudo apt install php"
            
            ui_error "PHP Configuration Not Found" "$error_msg"
            return 1
        fi
        
        # Get current PHP settings with better error handling
        local upload_max=$(grep "^[[:space:]]*upload_max_filesize" "$php_ini_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | tail -n1)
        local post_max=$(grep "^[[:space:]]*post_max_size" "$php_ini_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | tail -n1)
        local memory_limit=$(grep "^[[:space:]]*memory_limit" "$php_ini_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | tail -n1)
        local max_exec=$(grep "^[[:space:]]*max_execution_time" "$php_ini_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | tail -n1)
        local max_input=$(grep "^[[:space:]]*max_input_time" "$php_ini_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | tail -n1)
        
        # Set defaults if not found
        [[ -z "$upload_max" ]] && upload_max="Not set"
        [[ -z "$post_max" ]] && post_max="Not set"
        [[ -z "$memory_limit" ]] && memory_limit="Not set"
        [[ -z "$max_exec" ]] && max_exec="Not set"
        [[ -z "$max_input" ]] && max_input="Not set"
        
        current_settings="🐘 PHP Configuration Management\n\n"
        current_settings+="📁 Configuration File: $php_ini_path\n\n"
        current_settings+="📊 Current Settings:\n"
        current_settings+="• Upload Max Filesize: $upload_max\n"
        current_settings+="• Post Max Size: $post_max\n"
        current_settings+="• Memory Limit: $memory_limit\n"
        current_settings+="• Max Execution Time: $max_exec\n"
        current_settings+="• Max Input Time: $max_input\n\n"
        current_settings+="💡 Recommended for large file uploads:\n"
        current_settings+="• Upload Max Filesize: 8G\n"
        current_settings+="• Post Max Size: 8G\n"
        current_settings+="• Memory Limit: 8G\n"
        current_settings+="• Max Execution Time: 300\n"
        current_settings+="• Max Input Time: 300"
        
        local menu_items=(
            "optimize-uploads" "🚀 Optimize for Large File Uploads (8G)"
            "custom-settings" "⚙️  Custom PHP Settings"
            "view-config" "📄 View Full php.ini File"
            "restart-services" "🔄 Restart Web Services"
            "back" "(Z) ← Back to Main Menu"
        )
        
        local choice
        choice=$(ui_menu "PHP Settings Management" "$current_settings" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            optimize-uploads)
                optimize_php_for_uploads "$php_ini_path"
                ;;
            custom-settings)
                configure_custom_php_settings "$php_ini_path"
                ;;
            view-config)
                view_php_config "$php_ini_path"
                ;;
            restart-services)
                restart_web_services
                ;;
            back|z|"")
                break
                ;;
        esac
    done
}

optimize_php_for_uploads() {
    local php_ini_path="$1"
    
    log "Optimizing PHP settings for large file uploads"
    
    local optimization_info="🚀 PHP Upload Optimization\n\n"
    optimization_info+="This will configure PHP for large file uploads:\n\n"
    optimization_info+="📤 Upload Settings:\n"
    optimization_info+="• upload_max_filesize = 8G\n"
    optimization_info+="• post_max_size = 8G\n\n"
    optimization_info+="💾 Memory & Performance:\n"
    optimization_info+="• memory_limit = 8G\n"
    optimization_info+="• max_execution_time = 300\n"
    optimization_info+="• max_input_time = 300\n\n"
    optimization_info+="⚠️  This will modify: $php_ini_path\n\n"
    optimization_info+="Continue with optimization?"
    
    if ! ui_yesno "PHP Upload Optimization" "$optimization_info"; then
        return
    fi
    
    # Backup current php.ini
    local backup_file="$BACKUP_DIR/php.ini.backup.$(date +%Y%m%d_%H%M%S)"
    if sudo cp "$php_ini_path" "$backup_file" 2>/dev/null; then
        log "PHP configuration backed up to: $backup_file"
    else
        ui_error "Backup Failed" "Could not create backup of php.ini file.\n\nOperation cancelled for safety."
        return 1
    fi
    
    # Apply optimizations
    local temp_file="/tmp/php_optimization.tmp"
    
    # Create sed script for all modifications
    cat > "$temp_file" << 'EOF'
# Update or add upload_max_filesize
/^[[:space:]]*upload_max_filesize[[:space:]]*=/ c\
upload_max_filesize = 8G
# Update or add post_max_size
/^[[:space:]]*post_max_size[[:space:]]*=/ c\
post_max_size = 8G
# Update or add memory_limit
/^[[:space:]]*memory_limit[[:space:]]*=/ c\
memory_limit = 8G
# Update or add max_execution_time
/^[[:space:]]*max_execution_time[[:space:]]*=/ c\
max_execution_time = 300
# Update or add max_input_time
/^[[:space:]]*max_input_time[[:space:]]*=/ c\
max_input_time = 300
EOF
    
    # Apply changes
    if sudo sed -i -f "$temp_file" "$php_ini_path" 2>/dev/null; then
        # Verify settings were applied, if not, append them
        local settings_to_check=(
            "upload_max_filesize = 8G"
            "post_max_size = 8G" 
            "memory_limit = 8G"
            "max_execution_time = 300"
            "max_input_time = 300"
        )
        
        for setting in "${settings_to_check[@]}"; do
            local key="${setting%% =*}"
            if ! grep -q "^[[:space:]]*$key[[:space:]]*=" "$php_ini_path" 2>/dev/null; then
                echo "$setting" | sudo tee -a "$php_ini_path" >/dev/null
            fi
        done
        
        rm -f "$temp_file"
        
        ui_info "Optimization Complete" "✅ PHP has been optimized for large file uploads!\n\n📁 Configuration: $php_ini_path\n💾 Backup: $backup_file\n\n🔄 Web services need to be restarted for changes to take effect.\n\nRestart services now?"
        
        if ui_yesno "Restart Services" "Restart Apache/Nginx and PHP-FPM to apply changes?"; then
            restart_web_services
        fi
    else
        rm -f "$temp_file"
        ui_error "Optimization Failed" "Could not modify PHP configuration.\n\nPlease check file permissions and try again."
        return 1
    fi
}

configure_custom_php_settings() {
    local php_ini_path="$1"
    
    log "Configuring custom PHP settings"
    
    local custom_info="⚙️  Custom PHP Settings\n\n"
    custom_info+="Configure individual PHP parameters:\n\n"
    custom_info+="📁 File: $php_ini_path\n\n"
    custom_info+="Select a setting to modify:"
    
    local menu_items=(
        "upload_max" "📤 Upload Max Filesize"
        "post_max" "📮 Post Max Size"
        "memory_limit" "💾 Memory Limit"
        "max_execution" "⏱️  Max Execution Time"
        "max_input" "⏲️  Max Input Time"
        "back" "← Back"
    )
    
    while true; do
        local choice
        choice=$(ui_menu "Custom PHP Settings" "$custom_info" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            upload_max)
                modify_php_setting "$php_ini_path" "upload_max_filesize" "Upload Max Filesize" "8G" "Maximum size for uploaded files (e.g., 8G, 512M, 100M)"
                ;;
            post_max)
                modify_php_setting "$php_ini_path" "post_max_size" "Post Max Size" "8G" "Maximum size for POST data (e.g., 8G, 512M, 100M)"
                ;;
            memory_limit)
                modify_php_setting "$php_ini_path" "memory_limit" "Memory Limit" "8G" "Maximum memory per script (e.g., 8G, 512M, 256M)"
                ;;
            max_execution)
                modify_php_setting "$php_ini_path" "max_execution_time" "Max Execution Time" "300" "Maximum execution time in seconds (e.g., 300, 600, 0 for unlimited)"
                ;;
            max_input)
                modify_php_setting "$php_ini_path" "max_input_time" "Max Input Time" "300" "Maximum input parsing time in seconds (e.g., 300, 600)"
                ;;
            back)
                break
                ;;
        esac
    done
}

modify_php_setting() {
    local php_ini_path="$1"
    local setting_key="$2"
    local setting_name="$3"
    local default_value="$4"
    local description="$5"
    
    local current_value=$(grep "^[[:space:]]*$setting_key[[:space:]]*=" "$php_ini_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "Not set")
    
    local input_info="⚙️  Configure $setting_name\n\n"
    input_info+="📁 File: $php_ini_path\n"
    input_info+="🔧 Setting: $setting_key\n"
    input_info+="📊 Current Value: $current_value\n\n"
    input_info+="💡 Description: $description\n\n"
    input_info+="Enter new value (or press Cancel to abort):"
    
    local new_value
    new_value=$(ui_inputbox "$setting_name Configuration" "$input_info" "$default_value") || return
    
    if [[ -z "$new_value" ]]; then
        ui_error "Invalid Input" "Value cannot be empty."
        return 1
    fi
    
    # Backup and modify
    local backup_file="$BACKUP_DIR/php.ini.backup.$(date +%Y%m%d_%H%M%S)"
    if sudo cp "$php_ini_path" "$backup_file" 2>/dev/null; then
        if grep -q "^[[:space:]]*$setting_key[[:space:]]*=" "$php_ini_path" 2>/dev/null; then
            # Update existing setting
            sudo sed -i "s/^[[:space:]]*$setting_key[[:space:]]*=.*/$setting_key = $new_value/" "$php_ini_path"
        else
            # Add new setting
            echo "$setting_key = $new_value" | sudo tee -a "$php_ini_path" >/dev/null
        fi
        
        ui_info "Setting Updated" "✅ $setting_name updated successfully!\n\n🔧 Setting: $setting_key\n📊 New Value: $new_value\n💾 Backup: $backup_file\n\n🔄 Restart web services to apply changes."
    else
        ui_error "Update Failed" "Could not modify PHP configuration.\n\nPlease check file permissions."
        return 1
    fi
}

view_php_config() {
    local php_ini_path="$1"
    
    log "Viewing PHP configuration file"
    
    if [[ -f "$php_ini_path" ]]; then
        local config_content
        config_content=$(sudo cat "$php_ini_path" 2>/dev/null | head -n 100)
        
        ui_info "PHP Configuration: $php_ini_path" "$config_content\n\n(Showing first 100 lines)\n\nFull file path: $php_ini_path"
        
        if ui_yesno "Edit php.ini" "Do you want to edit the PHP configuration file with nano?"; then
            sudo nano "$php_ini_path"
        fi
    else
        ui_error "File Not Found" "PHP configuration file not found at: $php_ini_path"
    fi
}

restart_web_services() {
    log "Restarting web services to apply PHP configuration changes"
    
    local restart_info="🔄 Restart Web Services\n\n"
    restart_info+="This will restart the following services to apply PHP configuration changes:\n\n"
    restart_info+="🌐 Web Server:\n"
    
    # Detect web server
    local web_services=()
    if systemctl is-active --quiet apache2 2>/dev/null; then
        restart_info+="• Apache2 (active)\n"
        web_services+=("apache2")
    fi
    if systemctl is-active --quiet nginx 2>/dev/null; then
        restart_info+="• Nginx (active)\n"
        web_services+=("nginx")
    fi
    
    restart_info+="🐘 PHP Services:\n"
    
    # Detect PHP-FPM services
    local php_services=()
    for version in 8.1 8.0 7.4; do
        if systemctl is-active --quiet "php$version-fpm" 2>/dev/null; then
            restart_info+="• PHP $version FPM (active)\n"
            php_services+=("php$version-fpm")
        fi
    done
    
    if [[ ${#web_services[@]} -eq 0 && ${#php_services[@]} -eq 0 ]]; then
        ui_error "No Services Found" "No active web or PHP services found to restart."
        return 1
    fi
    
    restart_info+="⚠️  Services will be briefly unavailable during restart.\n\nContinue?"
    
    if ! ui_yesno "Restart Services" "$restart_info"; then
        return
    fi
    
    local restart_results=""
    local restart_success=true
    
    # Restart web services
    for service in "${web_services[@]}"; do
        restart_results+="Restarting $service... "
        if sudo systemctl restart "$service" 2>/dev/null; then
            restart_results+="✅ Success\n"
        else
            restart_results+="❌ Failed\n"
            restart_success=false
        fi
    done
    
    # Restart PHP services
    for service in "${php_services[@]}"; do
        restart_results+="Restarting $service... "
        if sudo systemctl restart "$service" 2>/dev/null; then
            restart_results+="✅ Success\n"
        else
            restart_results+="❌ Failed\n"
            restart_success=false
        fi
    done
    
    if [[ "$restart_success" == "true" ]]; then
        ui_info "Services Restarted" "✅ All services restarted successfully!\n\n$restart_results\n🎉 PHP configuration changes are now active."
    else
        ui_info "Restart Issues" "⚠️  Some services failed to restart:\n\n$restart_results\n🔧 Please check service status manually if needed."
    fi
}

# WordPress file access management function
grant_file_access_to_user() {
    local site="$1"
    local current_user
    current_user=$(whoami)
    
    log "Granting file access to user $current_user for WordPress site: $site"
    
    # Check if running as root
    if [[ "$EUID" -ne 0 ]]; then
        ui_error "Root Access Required" "This function requires root privileges to modify file permissions.\n\nPlease run the script with sudo or as root user."
        return 1
    fi
    
    # Get the actual user (not root) if running with sudo
    if [[ -n "$SUDO_USER" ]]; then
        current_user="$SUDO_USER"
    fi
    
    local info_text="File Access Management for WordPress Sites\n\n"
    info_text+="This will grant the current user ($current_user) access to manage files in /var/www/\n\n"
    info_text+="The following actions will be performed:\n"
    info_text+="• Add user '$current_user' to the 'www-data' group\n"
    info_text+="• Change ownership of /var/www to $current_user:www-data\n"
    info_text+="• Set permissions to 2775 (rwxrwsr-x) for directories\n"
    info_text+="• Set the setgid bit on directories for proper group inheritance\n"
    info_text+="• Activate the www-data group for the current session\n\n"
    info_text+="⚠️  This will affect ALL WordPress sites in /var/www/\n\n"
    info_text+="Benefits:\n"
    info_text+="✅ Edit files directly without sudo\n"
    info_text+="✅ Proper file permissions maintained\n"
    info_text+="✅ Shared access with web server (www-data)\n"
    info_text+="✅ New files inherit correct group ownership\n"
    
    if ! ui_yesno "Grant File Access" "$info_text"; then
        return 0
    fi
    
    local results=""
    local success=true
    
    # Step 1: Add user to www-data group
    results+="Adding user '$current_user' to www-data group...\n"
    if usermod -aG www-data "$current_user" 2>/dev/null; then
        results+="✅ User added to www-data group successfully\n\n"
    else
        results+="❌ Failed to add user to www-data group\n\n"
        success=false
    fi
    
    # Step 2: Change ownership of /var/www
    results+="Changing ownership of /var/www to $current_user:www-data...\n"
    if chown -R "$current_user:www-data" /var/www 2>/dev/null; then
        results+="✅ Ownership changed successfully\n\n"
    else
        results+="❌ Failed to change ownership\n\n"
        success=false
    fi
    
    # Step 3: Set permissions
    results+="Setting permissions to 2775 for /var/www...\n"
    if chmod -R 2775 /var/www 2>/dev/null; then
        results+="✅ Permissions set successfully\n\n"
    else
        results+="❌ Failed to set permissions\n\n"
        success=false
    fi
    
    # Step 4: Set setgid bit on directories
    results+="Setting setgid bit on directories...\n"
    if find /var/www -type d -exec chmod g+s {} \; 2>/dev/null; then
        results+="✅ Setgid bit set on directories\n\n"
    else
        results+="❌ Failed to set setgid bit\n\n"
        success=false
    fi
    
    # Step 5: Information about group activation
    results+="Group Activation:\n"
    results+="⚠️  To activate the www-data group for your current session, run:\n"
    results+="   newgrp www-data\n\n"
    results+="Or log out and log back in for the group changes to take effect.\n\n"
    
    if [[ "$success" == "true" ]]; then
        results+="🎉 File access granted successfully!\n\n"
        results+="You can now:\n"
        results+="• Edit files in /var/www/ without sudo\n"
        results+="• Create new files with proper permissions\n"
        results+="• Manage WordPress sites directly\n\n"
        results+="Note: You may need to start a new shell session or run 'newgrp www-data' to activate the group membership."
        
        ui_info "File Access Granted" "$results"
    else
        ui_error "File Access Setup Failed" "$results"
    fi
}

# WordPress database testing and repair functions
test_wordpress_database_connection() {
    local site="$1"
    local site_dir="/var/www/$site"
    
    log "Testing database connection for WordPress site: $site"
    
    if [[ ! -f "$site_dir/wp-config.php" ]]; then
        ui_error "wp-config.php not found" "Cannot test database connection.\n\nFile not found: $site_dir/wp-config.php"
        return 1
    fi
    
    # Extract database credentials
    local db_name db_user db_pass db_host
    db_name=$(grep "DB_NAME" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_user=$(grep "DB_USER" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_pass=$(grep "DB_PASSWORD" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_host=$(grep "DB_HOST" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_host=${db_host:-localhost}
    
    local test_info="🗄️  Database Connection Test\n\n"
    test_info+="Site: $site\n"
    test_info+="Database: ${db_name:-❌ Not found}\n"
    test_info+="User: ${db_user:-❌ Not found}\n"
    test_info+="Host: $db_host\n\n"
    
    if [[ -z "$db_name" || -z "$db_user" || -z "$db_pass" ]]; then
        test_info+="❌ FAILED: Missing database credentials in wp-config.php\n\n"
        test_info+="Required credentials not found:\n"
        [[ -z "$db_name" ]] && test_info+="• DB_NAME is missing\n"
        [[ -z "$db_user" ]] && test_info+="• DB_USER is missing\n"
        [[ -z "$db_pass" ]] && test_info+="• DB_PASSWORD is missing\n"
        ui_info "Database Test Failed" "$test_info"
        return 1
    fi
    
    # Test connection
    local db_test_result
    if db_test_result=$(mysql -u"$db_user" -p"$db_pass" -h"$db_host" -e "USE \`$db_name\`; SELECT 'Connection successful' as status, NOW() as timestamp;" 2>&1); then
        if echo "$db_test_result" | grep -q "Connection successful"; then
            test_info+="✅ SUCCESS: Database connection established\n\n"
            
            # Additional diagnostics
            local table_count=$(mysql -u"$db_user" -p"$db_pass" -h"$db_host" -e "USE \`$db_name\`; SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_name';" 2>/dev/null | tail -n1)
            local wp_tables=$(mysql -u"$db_user" -p"$db_pass" -h"$db_host" -e "USE \`$db_name\`; SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_name' AND (table_name LIKE '%wp_posts' OR table_name LIKE '%wp_users' OR table_name LIKE '%wp_options');" 2>/dev/null | tail -n1)
            local user_count=$(mysql -u"$db_user" -p"$db_pass" -h"$db_host" -e "USE \`$db_name\`; SELECT COUNT(*) FROM wp_users;" 2>/dev/null | tail -n1)
            
            test_info+="Database Statistics:\n"
            test_info+="• Total tables: $table_count\n"
            test_info+="• WordPress core tables: $wp_tables/3\n"
            test_info+="• WordPress users: $user_count\n\n"
            
            if [[ "$wp_tables" -ge 3 && "$user_count" -gt 0 ]]; then
                test_info+="✅ WordPress appears to be fully installed\n"
            elif [[ "$wp_tables" -ge 3 ]]; then
                test_info+="⚠️  WordPress tables exist but no users found\n"
            else
                test_info+="⚠️  WordPress tables missing - installation incomplete\n"
            fi
            
            ui_info "Database Test Successful" "$test_info"
        else
            test_info+="❌ FAILED: Connection established but database query failed\n\n"
            test_info+="Error details:\n$db_test_result"
            ui_info "Database Test Failed" "$test_info"
        fi
    else
        test_info+="❌ FAILED: Cannot connect to database\n\n"
        
        # Parse error for common issues
        if echo "$db_test_result" | grep -q "Access denied"; then
            test_info+="Error: Access denied\n"
            test_info+="• Check username and password\n"
            test_info+="• Verify user has database permissions\n"
        elif echo "$db_test_result" | grep -q "Unknown database"; then
            test_info+="Error: Database does not exist\n"
            test_info+="• Database '$db_name' was not found\n"
            test_info+="• Check database name spelling\n"
            test_info+="• Create database if needed\n"
        elif echo "$db_test_result" | grep -q "Can't connect"; then
            test_info+="Error: Cannot connect to MySQL server\n"
            test_info+="• Check if MariaDB/MySQL is running\n"
            test_info+="• Verify host address: $db_host\n"
            test_info+="• Check firewall settings\n"
        else
            test_info+="Error details:\n$(echo "$db_test_result" | head -n3)\n"
        fi
        
        ui_info "Database Test Failed" "$test_info"
    fi
}

repair_wordpress_database_connection() {
    local site="$1"
    local site_dir="/var/www/$site"
    
    log "Starting database repair for WordPress site: $site"
    
    if [[ ! -f "$site_dir/wp-config.php" ]]; then
        ui_error "wp-config.php not found" "Cannot repair database connection.\n\nFile not found: $site_dir/wp-config.php"
        return 1
    fi
    
    local repair_info="🔧 Database Connection Repair\n\n"
    repair_info+="This will attempt to:\n"
    repair_info+="• Verify database credentials\n"
    repair_info+="• Test database connectivity\n"
    repair_info+="• Create missing database if needed\n"
    repair_info+="• Recreate database user if needed\n"
    repair_info+="• Fix common connection issues\n\n"
    repair_info+="Continue with repair?"
    
    if ! ui_yesno "Database Repair" "$repair_info"; then
        return
    fi
    
    # Extract current credentials
    local db_name db_user db_pass db_host
    db_name=$(grep "DB_NAME" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_user=$(grep "DB_USER" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_pass=$(grep "DB_PASSWORD" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_host=$(grep "DB_HOST" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
    db_host=${db_host:-localhost}
    
    local repair_steps=""
    local repair_success=true
    
    # Step 1: Validate credentials
    repair_steps+="Step 1: Validating credentials...\n"
    if [[ -z "$db_name" || -z "$db_user" || -z "$db_pass" ]]; then
        repair_steps+="❌ Missing credentials in wp-config.php\n"
        repair_success=false
    else
        repair_steps+="✅ Credentials found\n"
    fi
    
    # Step 2: Test MariaDB service
    repair_steps+="Step 2: Checking MariaDB service...\n"
    if systemctl is-active --quiet mariadb; then
        repair_steps+="✅ MariaDB is running\n"
    else
        repair_steps+="⚠️  MariaDB is not running - attempting to start...\n"
        if sudo systemctl start mariadb 2>/dev/null; then
            repair_steps+="✅ MariaDB started successfully\n"
        else
            repair_steps+="❌ Failed to start MariaDB\n"
            repair_success=false
        fi
    fi
    
    if [[ "$repair_success" == "true" && -n "$db_name" && -n "$db_user" && -n "$db_pass" ]]; then
        # Step 3: Test connection with current credentials
        repair_steps+="Step 3: Testing database connection...\n"
        if mysql -u"$db_user" -p"$db_pass" -h"$db_host" -e "USE \`$db_name\`;" 2>/dev/null; then
            repair_steps+="✅ Connection successful - no repair needed\n"
        else
            repair_steps+="⚠️  Connection failed - attempting repair...\n"
            
            # Step 4: Try to recreate database and user with root access
            repair_steps+="Step 4: Recreating database and user...\n"
            
            # Get root access
            local root_pass=""
            if [[ -f "/root/.mysql_root_password" ]]; then
                root_pass=$(sudo cat "/root/.mysql_root_password" 2>/dev/null | tr -d '\n\r')
            fi
            
            local mysql_cmd=""
            if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" 2>/dev/null; then
                mysql_cmd="mysql -u root -p\"$root_pass\""
            elif sudo mysql -e "SELECT 1;" 2>/dev/null; then
                mysql_cmd="sudo mysql"
            else
                repair_steps+="❌ Cannot access MariaDB as root\n"
                repair_success=false
            fi
            
            if [[ -n "$mysql_cmd" ]]; then
                # Create database
                if eval "$mysql_cmd -e \"CREATE DATABASE IF NOT EXISTS \\\`$db_name\\\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\"" 2>/dev/null; then
                    repair_steps+="✅ Database '$db_name' created/verified\n"
                else
                    repair_steps+="❌ Failed to create database\n"
                    repair_success=false
                fi
                
                # Create user and grant privileges
                if eval "$mysql_cmd -e \"CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';\"" 2>/dev/null; then
                    repair_steps+="✅ User '$db_user' created/verified\n"
                else
                    repair_steps+="❌ Failed to create user\n"
                    repair_success=false
                fi
                
                if eval "$mysql_cmd -e \"GRANT ALL PRIVILEGES ON \\\`$db_name\\\`.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;\"" 2>/dev/null; then
                    repair_steps+="✅ Privileges granted\n"
                else
                    repair_steps+="❌ Failed to grant privileges\n"
                    repair_success=false
                fi
                
                # Final test
                repair_steps+="Step 5: Final connection test...\n"
                if mysql -u"$db_user" -p"$db_pass" -h"$db_host" -e "USE \`$db_name\`;" 2>/dev/null; then
                    repair_steps+="✅ Database connection repaired successfully!\n"
                else
                    repair_steps+="❌ Connection still failing after repair\n"
                    repair_success=false
                fi
            fi
        fi
    fi
    
    # Show repair results
    if [[ "$repair_success" == "true" ]]; then
        ui_info "Repair Successful" "✅ Database connection repair completed!\n\n$repair_steps\nYour WordPress site should now be able to connect to the database."
    else
        ui_info "Repair Failed" "❌ Database connection repair failed\n\n$repair_steps\nManual intervention may be required. Check the database credentials and MariaDB configuration."
    fi
}

# ==============================================================================
# LARGE SQL IMPORT OPTIMIZATION
# ==============================================================================

optimize_for_large_sql_imports() {
    log "Starting large SQL import optimization"
    
    local info="🗄️ Large SQL Import Optimization\n\n"
    info+="This will optimize your server configuration for importing large SQL files:\n\n"
    info+="📊 PHP Configuration:\n"
    info+="• Memory limit: 1024M (1GB)\n"
    info+="• Execution time: 1800s (30 minutes)\n"
    info+="• Upload limits: 256M\n\n"
    info+="🌐 Web Server (Nginx/Apache):\n"
    info+="• Client body size: 256M\n"
    info+="• Timeout settings: 30 minutes\n"
    info+="• Buffer optimizations\n\n"
    info+="🗄️ MySQL/MariaDB:\n"
    info+="• Connection timeouts: 30 minutes\n"
    info+="• Packet size: 256M\n"
    info+="• Buffer optimizations\n\n"
    info+="⚠️ Services will be restarted to apply changes.\n\n"
    info+="Continue with optimization?"
    
    if ! ui_yesno "SQL Import Optimization" "$info"; then
        return
    fi
    
    ui_msg "Step 1/4" "🔧 Optimizing PHP configuration...\n\nConfiguring memory limits, execution times, and upload settings for large SQL operations."
    
    # Optimize PHP settings
    optimize_php_for_sql_imports || {
        ui_error "PHP Optimization Failed" "Failed to optimize PHP configuration. Check the logs for details."
        return 1
    }
    
    ui_msg "Step 2/4" "🌐 Optimizing web server configuration...\n\nConfiguring Nginx/Apache timeouts and buffer sizes for large requests."
    
    # Optimize web server settings
    optimize_webserver_for_sql_imports || {
        ui_error "Web Server Optimization Failed" "Failed to optimize web server configuration. Check the logs for details."
        return 1
    }
    
    ui_msg "Step 3/4" "🗄️ Optimizing MySQL/MariaDB configuration...\n\nConfiguring database timeouts, packet sizes, and buffer settings."
    
    # Optimize MySQL/MariaDB settings
    optimize_mysql_for_sql_imports || {
        ui_error "MySQL Optimization Failed" "Failed to optimize MySQL configuration. Check the logs for details."
        return 1
    }
    
    ui_msg "Step 4/4" "🔄 Restarting services...\n\nRestarting web server, PHP-FPM, and MySQL to apply all optimizations."
    
    # Restart all services
    restart_services_for_sql_imports || {
        ui_error "Service Restart Failed" "Failed to restart services. Some optimizations may not be active."
        return 1
    }
    
    ui_msg "Optimization Complete!" "✅ Your server is now optimized for large SQL imports!\n\n🎯 Optimized Components:\n• PHP: Memory, execution time, upload limits\n• Web Server: Timeouts, buffer sizes\n• MySQL: Connection limits, packet size\n• Services: All restarted and active\n\n💡 Tips for importing large SQL files:\n• Use phpMyAdmin's import feature\n• Consider using command line: mysql -u user -p database < file.sql\n• Monitor the process in /var/log/mysql/error.log\n• Large imports may still take 10-30 minutes"
}

optimize_php_for_sql_imports() {
    log "Optimizing PHP for large SQL imports"
    
    # Detect PHP version
    local php_version
    php_version=$(php -v 2>/dev/null | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2) || {
        log_error "Could not detect PHP version"
        return 1
    }
    
    log "Detected PHP version: $php_version"
    
    # Update PHP-FPM configuration (this is what handles web requests!)
    local php_fpm_ini="/etc/php/$php_version/fpm/php.ini"
    if [[ -f "$php_fpm_ini" ]]; then
        log "Updating PHP-FPM configuration: $php_fpm_ini"
        
        # Backup original configuration
        local backup_file="${php_fpm_ini}.backup-sql-import-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$php_fpm_ini" "$backup_file" || {
            log_error "Failed to backup PHP-FPM configuration"
            return 1
        }
        
        # Apply optimizations using sed (more reliable than append method)
        sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 256M/' "$php_fpm_ini"
        sudo sed -i 's/^post_max_size = .*/post_max_size = 256M/' "$php_fpm_ini"
        sudo sed -i 's/^memory_limit = .*/memory_limit = 1024M/' "$php_fpm_ini"
        sudo sed -i 's/^max_execution_time = .*/max_execution_time = 1800/' "$php_fpm_ini"
        sudo sed -i 's/^max_input_time = .*/max_input_time = 1800/' "$php_fpm_ini"
        sudo sed -i 's/^max_file_uploads = .*/max_file_uploads = 50/' "$php_fpm_ini"
        
        # Add settings that might not exist
        if ! grep -q "mysql.connect_timeout" "$php_fpm_ini"; then
            echo "mysql.connect_timeout = 300" | sudo tee -a "$php_fpm_ini" >/dev/null
        fi
        if ! grep -q "default_socket_timeout" "$php_fpm_ini"; then
            echo "default_socket_timeout = 300" | sudo tee -a "$php_fpm_ini" >/dev/null
        fi
        
        log "PHP-FPM configuration updated successfully"
    else
        log_error "PHP-FPM configuration file not found: $php_fpm_ini"
        return 1
    fi
    
    # Update PHP-FPM pool configuration for better handling of large requests
    local php_fpm_pool="/etc/php/$php_version/fpm/pool.d/www.conf"
    if [[ -f "$php_fpm_pool" ]]; then
        log "Updating PHP-FPM pool configuration: $php_fpm_pool"
        
        # Backup the pool configuration
        local pool_backup="${php_fpm_pool}.backup-sql-import-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$php_fpm_pool" "$pool_backup"
        
        # Update pool settings for better performance with large uploads
        sudo sed -i 's/^pm.max_children = .*/pm.max_children = 50/' "$php_fpm_pool"
        sudo sed -i 's/^pm.start_servers = .*/pm.start_servers = 10/' "$php_fpm_pool"
        sudo sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$php_fpm_pool"
        sudo sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 15/' "$php_fpm_pool"
        
        # Add request_terminate_timeout if it doesn't exist or is commented
        if ! grep -q "^request_terminate_timeout" "$php_fpm_pool"; then
            if grep -q "^;request_terminate_timeout" "$php_fpm_pool"; then
                sudo sed -i 's/^;request_terminate_timeout = .*/request_terminate_timeout = 1800/' "$php_fpm_pool"
            else
                echo "request_terminate_timeout = 1800" | sudo tee -a "$php_fpm_pool" > /dev/null
            fi
        else
            sudo sed -i 's/^request_terminate_timeout = .*/request_terminate_timeout = 1800/' "$php_fpm_pool"
        fi
        
        log "PHP-FPM pool configuration updated"
    else
        log_error "PHP-FPM pool configuration file not found: $php_fpm_pool"
    fi
    
    # Also update Apache PHP config if it exists
    local php_apache_ini="/etc/php/$php_version/apache2/php.ini"
    if [[ -f "$php_apache_ini" ]]; then
        log "Also updating Apache PHP configuration: $php_apache_ini"
        
        # Backup and update Apache PHP config
        local backup_file="${php_apache_ini}.backup-sql-import-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$php_apache_ini" "$backup_file"
        
        sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 256M/' "$php_apache_ini"
        sudo sed -i 's/^post_max_size = .*/post_max_size = 256M/' "$php_apache_ini"
        sudo sed -i 's/^memory_limit = .*/memory_limit = 1024M/' "$php_apache_ini"
        sudo sed -i 's/^max_execution_time = .*/max_execution_time = 1800/' "$php_apache_ini"
        sudo sed -i 's/^max_input_time = .*/max_input_time = 1800/' "$php_apache_ini"
        sudo sed -i 's/^max_file_uploads = .*/max_file_uploads = 50/' "$php_apache_ini"
        
        log "Apache PHP configuration updated successfully"
    fi
    
    log "PHP configuration optimized for SQL imports"
    return 0
}

optimize_webserver_for_sql_imports() {
    log "Optimizing web server for large SQL imports"
    
    # Check which web server is running
    local webserver=""
    if systemctl is-active --quiet nginx; then
        webserver="nginx"
    elif systemctl is-active --quiet apache2; then
        webserver="apache2"
    else
        log_error "No active web server found (nginx or apache2)"
        return 1
    fi
    
    if [[ "$webserver" == "nginx" ]]; then
        optimize_nginx_for_sql_imports
    else
        optimize_apache_for_sql_imports
    fi
}

optimize_nginx_for_sql_imports() {
    log "Optimizing Nginx for large SQL imports"
    
    # First, update the global optimization file
    local sql_import_conf="/etc/nginx/conf.d/sql-import-optimization.conf"
    sudo tee "$sql_import_conf" > /dev/null << 'EOF'
# Large SQL Import Optimizations
client_max_body_size 256M;
client_body_timeout 300s;
client_header_timeout 300s;
fastcgi_read_timeout 1800s;
fastcgi_send_timeout 1800s;
fastcgi_connect_timeout 300s;
fastcgi_buffer_size 256k;
fastcgi_buffers 8 256k;
fastcgi_busy_buffers_size 512k;
keepalive_timeout 300s;
EOF
    
    log "Global Nginx optimization configuration created"
    
    # Now fix site-specific configurations that might override global settings
    local sites_dir="/etc/nginx/sites-available"
    if [[ -d "$sites_dir" ]]; then
        log "Checking site-specific configurations for client_max_body_size overrides"
        
        # Find all site configs with client_max_body_size less than 256M
        local site_files
        site_files=$(find "$sites_dir" -name "*.conf" -o -name "*" ! -name "*.backup*" ! -name "*.bak" ! -name "*.orig" 2>/dev/null)
        
        for site_file in $site_files; do
            if [[ -f "$site_file" ]]; then
                # Check if this site has a client_max_body_size setting
                if grep -q "client_max_body_size" "$site_file"; then
                    log "Found client_max_body_size in $site_file, updating to 256M"
                    
                    # Backup the site file
                    local backup_file="${site_file}.backup-sql-import-$(date +%Y%m%d-%H%M%S)"
                    sudo cp "$site_file" "$backup_file"
                    
                    # Update client_max_body_size to 256M
                    sudo sed -i 's/client_max_body_size [^;]*;/client_max_body_size 256M;/g' "$site_file"
                    
                    log "Updated client_max_body_size in $(basename "$site_file")"
                fi
            fi
        done
    fi
    
    # Test Nginx configuration
    if sudo nginx -t 2>/dev/null; then
        log "Nginx configuration optimized for SQL imports"
        return 0
    else
        log_error "Nginx configuration test failed, checking what went wrong..."
        
        # Show the actual error
        local nginx_error
        nginx_error=$(sudo nginx -t 2>&1)
        log_error "Nginx test output: $nginx_error"
        
        # Try to fix common issues
        if echo "$nginx_error" | grep -q "duplicate"; then
            log "Attempting to fix duplicate directive issues..."
            # Remove our optimization file and try again
            sudo rm -f "$sql_import_conf"
            
            # Create a simpler version
            sudo tee "$sql_import_conf" > /dev/null << 'EOF'
# Large SQL Import Optimizations - Simplified
client_max_body_size 256M;
fastcgi_read_timeout 1800s;
EOF
            
            if sudo nginx -t 2>/dev/null; then
                log "Nginx configuration fixed with simplified settings"
                return 0
            fi
        fi
        
        # If still failing, remove our config file
        sudo rm -f "$sql_import_conf"
        log_error "Could not fix Nginx configuration, removed optimization file"
        return 1
    fi
}

optimize_apache_for_sql_imports() {
    log "Optimizing Apache for large SQL imports"
    
    # Create optimization configuration
    local sql_import_conf="/etc/apache2/conf-available/sql-import-optimization.conf"
    sudo tee "$sql_import_conf" > /dev/null << 'EOF'
# Large SQL Import Optimizations
LimitRequestBody 268435456
Timeout 1800
KeepAliveTimeout 300

<IfModule mod_php7.c>
    php_value max_execution_time 1800
    php_value max_input_time 1800
    php_value memory_limit 1024M
    php_value upload_max_filesize 256M
    php_value post_max_size 256M
</IfModule>

<IfModule mod_php8.c>
    php_value max_execution_time 1800
    php_value max_input_time 1800
    php_value memory_limit 1024M
    php_value upload_max_filesize 256M
    php_value post_max_size 256M
</IfModule>
EOF
    
    # Enable the configuration
    sudo a2enconf sql-import-optimization 2>/dev/null || {
        log_error "Failed to enable Apache SQL import configuration"
        return 1
    }
    
    # Test Apache configuration
    if sudo apache2ctl configtest 2>/dev/null; then
        log "Apache configuration optimized for SQL imports"
        return 0
    else
        log_error "Apache configuration test failed"
        sudo a2disconf sql-import-optimization 2>/dev/null
        sudo rm -f "$sql_import_conf"
        return 1
    fi
}

optimize_mysql_for_sql_imports() {
    log "Optimizing MySQL/MariaDB for large SQL imports"
    
    local mysql_conf="/etc/mysql/conf.d/sql-import-optimization.cnf"
    local backup_dir="/etc/mysql/conf.d/backups"
    
    # Create backup directory
    sudo mkdir -p "$backup_dir" 2>/dev/null
    
    # Create optimization configuration
    sudo tee "$mysql_conf" > /dev/null << 'EOF'
[mysqld]
# Large SQL Import Optimizations
max_connections = 200
connect_timeout = 300
wait_timeout = 1800
interactive_timeout = 1800
net_read_timeout = 300
net_write_timeout = 300
innodb_buffer_pool_size = 512M
max_allowed_packet = 256M
bulk_insert_buffer_size = 64M
myisam_sort_buffer_size = 128M
tmp_table_size = 256M
max_heap_table_size = 256M
innodb_log_file_size = 256M
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 2
EOF
    
    log "MySQL/MariaDB configuration optimized for SQL imports"
    return 0
}

restart_services_for_sql_imports() {
    log "Restarting services for SQL import optimizations"
    
    local services_restarted=0
    local services_failed=()
    
    # Restart PHP-FPM
    local php_version
    php_version=$(php -v 2>/dev/null | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2)
    if [[ -n "$php_version" ]]; then
        if sudo systemctl restart "php${php_version}-fpm" 2>/dev/null; then
            log "PHP-FPM restarted successfully"
            ((services_restarted++))
        else
            log_error "Failed to restart PHP-FPM"
            services_failed+=("PHP-FPM")
        fi
    fi
    
    # Restart web server
    if systemctl is-active --quiet nginx; then
        if sudo systemctl restart nginx 2>/dev/null; then
            log "Nginx restarted successfully"
            ((services_restarted++))
        else
            log_error "Failed to restart Nginx"
            services_failed+=("Nginx")
        fi
    elif systemctl is-active --quiet apache2; then
        if sudo systemctl restart apache2 2>/dev/null; then
            log "Apache restarted successfully"
            ((services_restarted++))
        else
            log_error "Failed to restart Apache"
            services_failed+=("Apache")
        fi
    fi
    
    # Restart MySQL/MariaDB
    if sudo systemctl restart mariadb 2>/dev/null; then
        log "MariaDB restarted successfully"
        ((services_restarted++))
    else
        log_error "Failed to restart MariaDB"
        services_failed+=("MariaDB")
    fi
    
    if [[ ${#services_failed[@]} -eq 0 ]]; then
        log "All services restarted successfully ($services_restarted services)"
        return 0
    else
        log_error "Some services failed to restart: ${services_failed[*]}"
        return 1
    fi
}

# WordPress WP-CLI Management
wordpress_wpcli_management() {
    while true; do
        local wpcli_status="WP-CLI Management\n\n"
        
        # Check if WP-CLI is installed
        if command -v wp >/dev/null 2>&1; then
            local wp_version=$(wp --version 2>/dev/null | cut -d' ' -f2 || echo "Unknown")
            wpcli_status+="📦 WP-CLI Status: ✅ Installed (Version: $wp_version)\n"
            wpcli_status+="📍 Location: $(which wp)\n"
        else
            wpcli_status+="📦 WP-CLI Status: ❌ Not installed\n"
        fi
        
        # Check for WordPress sites
        local wp_sites=()
        if [[ -d "/var/www" ]]; then
            while IFS= read -r -d '' site_dir; do
                if [[ -f "$site_dir/wp-config.php" ]]; then
                    wp_sites+=("$(basename "$site_dir")")
                fi
            done < <(find /var/www -maxdepth 1 -type d -print0 2>/dev/null)
        fi
        
        if [[ ${#wp_sites[@]} -gt 0 ]]; then
            wpcli_status+="\n🌐 WordPress Sites Found: ${#wp_sites[@]}\n"
            for site in "${wp_sites[@]}"; do
                wpcli_status+="   • $site\n"
            done
        else
            wpcli_status+="\n⚠️  No WordPress sites found in /var/www\n"
        fi
        
        wpcli_status+="\n"
        
        local menu_items=(
            "install" "(.Y.) 📥 Install WP-CLI"
            "update" "(.Y.) 🔄 Update WP-CLI"
            "uninstall" "(.Y.) 🗑️  Uninstall WP-CLI"
            "" "(_*_)"
            "test" "(.Y.) 🧪 Test WP-CLI on Sites"
            "info" "(.Y.) ℹ️  Show WP-CLI Info & Commands"
            "" "(_*_)"
            "zback" "(Z) ← Back to WordPress Menu"
        )
        
        local choice
        choice=$(ui_menu "WP-CLI Management" "$wpcli_status" 20 70 10 "${menu_items[@]}") || break
        
        case $choice in
            install)
                install_wpcli
                ;;
            update)
                update_wpcli
                ;;
            uninstall)
                uninstall_wpcli
                ;;
            test)
                test_wpcli_sites
                ;;
            info)
                show_wpcli_info
                ;;
            zback)
                break
                ;;
        esac
    done
}

# Install WP-CLI
install_wpcli() {
    log "Installing WP-CLI..."
    
    # Check if already installed
    if command -v wp >/dev/null 2>&1; then
        local wp_version=$(wp --version 2>/dev/null | cut -d' ' -f2 || echo "Unknown")
        log_warning "WP-CLI is already installed (Version: $wp_version)"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Ensure PHP CLI is available
    if ! command -v php >/dev/null 2>&1; then
        log_error "PHP CLI (php) is required for WP-CLI"
        ui_msg "WP-CLI Install Error" "WP-CLI requires the PHP command-line interpreter (php).\n\nPlease install it first: sudo apt-get update && sudo apt-get install -y php-cli"
        return 1
    fi
    
    # Download and install WP-CLI
    log "Downloading WP-CLI..."
    # Use official builds URL and follow redirects
    if curl -L -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; then
        log "Making WP-CLI executable..."
        chmod +x wp-cli.phar
        
        log "Moving WP-CLI to /usr/local/bin/wp..."
        if sudo mv wp-cli.phar /usr/local/bin/wp; then
            log "Testing WP-CLI installation..."
            if wp --info >/dev/null 2>&1; then
                log "✅ WP-CLI installed successfully!"
                wp --version
            else
                log_error "WP-CLI installation failed - command not working"
                return 1
            fi
        else
            log_error "Failed to move WP-CLI to /usr/local/bin/"
            return 1
        fi
    else
        log_error "Failed to download WP-CLI"
        return 1
    fi
    
    # Install bash completion (optional)
    log "Installing bash completion for WP-CLI..."
    if curl -L -o /tmp/wp-completion.bash https://raw.githubusercontent.com/wp-cli/wp-cli/main/utils/wp-completion.bash 2>/dev/null; then
        sudo mv /tmp/wp-completion.bash /etc/bash_completion.d/wp-cli
        log "Bash completion installed"
    else
        log_warning "Failed to install bash completion (optional)"
    fi
    
    read -p "Press Enter to continue..."
}

# Update WP-CLI
update_wpcli() {
    log "Updating WP-CLI..."
    
    if ! command -v wp >/dev/null 2>&1; then
        log_error "WP-CLI is not installed. Please install it first."
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Update using WP-CLI's self-update command
    local wp_cmd=(wp)
    if [[ $EUID -eq 0 ]]; then
        wp_cmd=(wp --allow-root)
    fi
    if "${wp_cmd[@]}" cli update; then
        log "✅ WP-CLI updated successfully!"
        "${wp_cmd[@]}" --version
    else
        log_warning "WP-CLI self-update failed. Trying manual update..."
        install_wpcli
    fi
    
    read -p "Press Enter to continue..."
}

# Uninstall WP-CLI
uninstall_wpcli() {
    log "Uninstalling WP-CLI..."
    
    if ! command -v wp >/dev/null 2>&1; then
        log_warning "WP-CLI is not installed"
        read -p "Press Enter to continue..."
        return 0
    fi
    
    read -p "Are you sure you want to uninstall WP-CLI? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    # Remove WP-CLI binary
    if sudo rm -f /usr/local/bin/wp; then
        log "WP-CLI binary removed"
    else
        log_error "Failed to remove WP-CLI binary"
    fi
    
    # Remove bash completion
    if sudo rm -f /etc/bash_completion.d/wp-cli; then
        log "Bash completion removed"
    fi
    
    log "✅ WP-CLI uninstalled successfully!"
    read -p "Press Enter to continue..."
}

# Test WP-CLI on WordPress sites
test_wpcli_sites() {
    log "Testing WP-CLI on WordPress sites..."
    
    if ! command -v wp >/dev/null 2>&1; then
        log_error "WP-CLI is not installed. Please install it first."
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Find WordPress sites
    local wp_sites=()
    if [[ -d "/var/www" ]]; then
        while IFS= read -r -d '' site_dir; do
            if [[ -f "$site_dir/wp-config.php" ]]; then
                wp_sites+=("$site_dir")
            fi
        done < <(find /var/www -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    
    if [[ ${#wp_sites[@]} -eq 0 ]]; then
        log_warning "No WordPress sites found in /var/www"
        read -p "Press Enter to continue..."
        return 0
    fi
    
    echo "Testing WP-CLI on found WordPress sites:"
    echo "========================================"
    
    for site_dir in "${wp_sites[@]}"; do
        local site_name=$(basename "$site_dir")
        echo
        echo "🌐 Testing site: $site_name"
        echo "   Path: $site_dir"
        
        cd "$site_dir" || continue
        
        # Select the appropriate WP-CLI invocation based on user context
        local wp_cmd=()
        if [[ $EUID -eq 0 ]]; then
            # Prefer running as www-data; fallback to allow-root
            if sudo -u www-data -H wp --path="$site_dir" core version >/dev/null 2>&1; then
                wp_cmd=(sudo -u www-data -H wp --path="$site_dir")
            elif wp --allow-root --path="$site_dir" core version >/dev/null 2>&1; then
                wp_cmd=(wp --allow-root --path="$site_dir")
            else
                echo "   ❌ WP-CLI not working on this site"
                echo "   💡 Try: sudo -u www-data -H wp --path=\"$site_dir\" core version"
                echo "   💡 Or: wp --allow-root --path=\"$site_dir\" core version"
                echo "   🔍 Checking permissions..."
                ls -la wp-config.php 2>/dev/null || echo "   ⚠️  wp-config.php not readable"
                continue
            fi
        else
            if wp --path="$site_dir" core version >/dev/null 2>&1; then
                wp_cmd=(wp --path="$site_dir")
            else
                echo "   ❌ WP-CLI not working on this site"
                echo "   💡 Try: sudo -u www-data -H wp --path=\"$site_dir\" core version"
                echo "   🔍 Checking permissions..."
                ls -la wp-config.php 2>/dev/null || echo "   ⚠️  wp-config.php not readable"
                continue
            fi
        fi

        echo "   ✅ WP-CLI working - WordPress version: $("${wp_cmd[@]}" core version 2>/dev/null)"
        echo "   📊 Database status: $("${wp_cmd[@]}" db check >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Error")"
        echo "   🔌 Active plugins: $("${wp_cmd[@]}" plugin list --status=active --format=count 2>/dev/null || echo "Unknown")"
        echo "   🎨 Active theme: $("${wp_cmd[@]}" theme list --status=active --field=name 2>/dev/null || echo "Unknown")"
    done
    
    echo
    read -p "Press Enter to continue..."
}

# Show WP-CLI information and common commands
show_wpcli_info() {
    clear
    echo "WP-CLI Information & Common Commands"
    echo "===================================="
    echo
    
    if command -v wp >/dev/null 2>&1; then
        echo "📦 WP-CLI Version:"
        wp --version
        echo
        
        echo "📍 WP-CLI Location:"
        which wp
        echo
        
        echo "ℹ️  WP-CLI Info:"
        wp --info
        echo
    else
        echo "❌ WP-CLI is not installed"
        echo
    fi
    
    echo "🔧 Common WP-CLI Commands:"
    echo "========================="
    echo
    echo "Core Management:"
    echo "  wp core download          # Download WordPress core"
    echo "  wp core install           # Install WordPress"
    echo "  wp core update            # Update WordPress core"
    echo "  wp core version           # Show WordPress version"
    echo
    echo "Plugin Management:"
    echo "  wp plugin list            # List all plugins"
    echo "  wp plugin install <name>  # Install a plugin"
    echo "  wp plugin activate <name> # Activate a plugin"
    echo "  wp plugin deactivate <name> # Deactivate a plugin"
    echo "  wp plugin delete <name>   # Delete a plugin"
    echo
    echo "Theme Management:"
    echo "  wp theme list             # List all themes"
    echo "  wp theme install <name>   # Install a theme"
    echo "  wp theme activate <name>  # Activate a theme"
    echo "  wp theme delete <name>    # Delete a theme"
    echo
    echo "Database Management:"
    echo "  wp db check               # Check database connection"
    echo "  wp db export              # Export database"
    echo "  wp db import <file>       # Import database"
    echo "  wp db search <text>       # Search database"
    echo
    echo "User Management:"
    echo "  wp user list              # List all users"
    echo "  wp user create <username> # Create a new user"
    echo "  wp user delete <username> # Delete a user"
    echo "  wp user update <username> # Update user info"
    echo
    echo "Content Management:"
    echo "  wp post list              # List posts"
    echo "  wp post create            # Create a new post"
    echo "  wp post delete <ID>       # Delete a post"
    echo "  wp media import <file>    # Import media file"
    echo
    echo "Maintenance:"
    echo "  wp cache flush            # Clear all caches"
    echo "  wp rewrite flush          # Flush rewrite rules"
    echo "  wp cron event list        # List cron events"
    echo "  wp search-replace <old> <new> # Search and replace in database"
    echo
    echo "📚 For more commands, visit: https://wp-cli.org/commands/"
    echo
    read -p "Press Enter to continue..."
}

# ==============================================================================
# MIRROR MANAGEMENT FUNCTIONS
# ==============================================================================

# Function to get current mirror configuration
get_current_mirror() {
    local sources_file="/etc/apt/sources.list"
    local sources_dir="/etc/apt/sources.list.d"
    
    # First try to get from main sources.list
    if [[ -f "$sources_file" ]]; then
        local mirror=$(grep -E "^deb\s+https?://" "$sources_file" | grep -v "security\|backports" | head -1 | awk '{print $2}' | sed 's|https\?://||' | sed 's|/.*||')
        if [[ -n "$mirror" && "$mirror" != "Unknown" ]]; then
            echo "$mirror"
            return
        fi
    fi
    
    # Try sources.list.d directory for Ubuntu sources
    if [[ -d "$sources_dir" ]]; then
        local mirror=$(find "$sources_dir" -name "*.list" -exec grep -l "ubuntu" {} \; | head -1 | xargs grep -E "^deb\s+https?://" | grep -v "security\|backports" | head -1 | awk '{print $2}' | sed 's|https\?://||' | sed 's|/.*||')
        if [[ -n "$mirror" && "$mirror" != "Unknown" ]]; then
            echo "$mirror"
            return
        fi
    fi
    
    # Fallback: try to detect from apt-cache policy
    local mirror=$(apt-cache policy | grep -E "^\s+\d+\s+https?://" | head -1 | awk '{print $2}' | sed 's|https\?://||' | sed 's|/.*||')
    if [[ -n "$mirror" ]]; then
        echo "$mirror"
    else
        echo "archive.ubuntu.com"
    fi
}

# Function to check if mirrorselect is installed
is_mirrorselect_installed() {
    # Ubuntu doesn't use mirrorselect - we'll use apt-mirror and netselect-apt instead
    command -v netselect-apt &>/dev/null
}

# Function to install mirror selection tools for Ubuntu
install_mirrorselect() {
    log "Installing Ubuntu mirror selection tools..."
    if ! is_mirrorselect_installed; then
        if sudo apt update && sudo apt install -y netselect-apt; then
            log "netselect-apt installed successfully"
            return 0
        else
            log "ERROR: Failed to install netselect-apt"
            return 1
        fi
    else
        log "netselect-apt is already installed"
        return 0
    fi
}

# Function to scan and set fastest mirror
scan_and_set_fastest_mirror() {
    log "Starting mirror scan and configuration"
    
    # Ensure mirrorselect is installed
    if ! install_mirrorselect; then
        ui_msg "Error" "Failed to install MirrorSelect. Cannot proceed with mirror optimization."
        return 1
    fi
    
    # Show progress dialog
    ui_info "Mirror Optimization" "Scanning Ubuntu mirrors to find the fastest one...\n\nThis may take a few minutes. Please wait."
    
    # Create a temporary file for the new sources.list
    local temp_sources="/tmp/sources.list.new"
    
    # Run mirrorselect to find fastest mirror
    if sudo mirrorselect -i > "$temp_sources" 2>/dev/null; then
        # Backup current sources.list
        sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)
        
        # Apply new mirror configuration
        sudo cp "$temp_sources" /etc/apt/sources.list
        
        # Update package cache
        if sudo apt update; then
            local new_mirror
            new_mirror=$(get_current_mirror)
            ui_msg "Success" "Mirror optimization completed successfully!\n\nNew fastest mirror: $new_mirror\n\nPackage cache has been updated."
            log "Mirror optimization completed. New mirror: $new_mirror"
        else
            # Restore backup if update fails
            sudo cp /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S) /etc/apt/sources.list
            ui_msg "Error" "Failed to update package cache with new mirror. Configuration has been restored."
            log "ERROR: Failed to update package cache, restored backup"
            return 1
        fi
    else
        ui_msg "Error" "Failed to scan mirrors. Please check your internet connection and try again."
        log "ERROR: Mirror scan failed"
        return 1
    fi
    
    # Clean up
    rm -f "$temp_sources"
}

# Local mirror management functions
get_local_mirror_path() {
    local config_file="/etc/apt/mirror.list"
    if [[ -f "$config_file" ]]; then
        grep "^set base_path" "$config_file" 2>/dev/null | awk '{print $3}' || echo "/var/spool/apt-mirror"
    else
        echo "/var/spool/apt-mirror"
    fi
}

is_apt_mirror_installed() {
    command -v apt-mirror >/dev/null 2>&1
}

install_apt_mirror() {
    log "Installing apt-mirror"
    ui_info "Installing apt-mirror" "Installing apt-mirror package...\n\nThis may take a few moments."
    
    if sudo apt-get update && sudo apt-get install -y apt-mirror; then
        ui_msg "Installation Complete" "apt-mirror has been successfully installed!"
        log "apt-mirror installation completed successfully"
        return 0
    else
        ui_msg "Installation Failed" "Failed to install apt-mirror. Please check your internet connection and try again."
        log "ERROR: apt-mirror installation failed"
        return 1
    fi
}

setup_local_mirror() {
    log "Setting up local mirror"
    
    # Get mirror path from user
    local mirror_path
    mirror_path=$(ui_input "Local Mirror Setup" "Enter the path where you want to store the local mirror:\n\n(Default: /var/spool/apt-mirror)\n\nNote: This will require significant disk space (50GB+)" "/var/spool/apt-mirror")
    
    if [[ -z "$mirror_path" ]]; then
        mirror_path="/var/spool/apt-mirror"
    fi
    
    # Create directory if it doesn't exist
    if ! mkdir -p "$mirror_path" 2>/dev/null; then
        ui_msg "Permission Error" "Cannot create directory: $mirror_path\n\nPlease run as root or choose a different path."
        return 1
    fi
    
    # Create apt-mirror configuration
    local config_file="/etc/apt/mirror.list"
    local ubuntu_version
    ubuntu_version=$(lsb_release -cs 2>/dev/null || echo "jammy")
    
    cat > "$config_file" << EOF
############# config ##################
set base_path    $mirror_path
set mirror_path  \$base_path/mirror
set skel_path    \$base_path/skel
set var_path     \$base_path/var
set cleanscript  \$var_path/clean.sh
set defaultarch  amd64
set postmirror_script \$var_path/postmirror.sh
set run_postmirror 0
set nthreads     20
set _tilde 0
#######################################

deb http://archive.ubuntu.com/ubuntu $ubuntu_version main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $ubuntu_version-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $ubuntu_version-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $ubuntu_version-security main restricted universe multiverse

clean http://archive.ubuntu.com/ubuntu
clean http://security.ubuntu.com/ubuntu
EOF
    
    ui_msg "Configuration Created" "Local mirror configuration created at:\n$config_file\n\nMirror path: $mirror_path\n\nUse 'Update Local Mirror' to download packages."
    log "Local mirror configuration created: $config_file"
}

update_local_mirror() {
    log "Updating local mirror"
    
    if ! is_apt_mirror_installed; then
        ui_msg "Not Installed" "apt-mirror is not installed. Please install it first."
        return 1
    fi
    
    local mirror_path
    mirror_path=$(get_local_mirror_path)
    
    if ui_yesno "Update Local Mirror" "Start downloading/updating local mirror?\n\nPath: $mirror_path\n\nWarning: This will download many GB of data and may take hours.\nEnsure you have sufficient disk space and bandwidth.\n\nContinue?"; then
        ui_info "Mirror Update" "Starting local mirror update...\n\nThis will run in a new terminal window.\nYou can monitor progress there."
        
        # Run apt-mirror in a new terminal
        gnome-terminal -- bash -c "
            echo 'Starting local mirror update...'
            echo 'This may take several hours depending on your connection.'
            echo 'Press Ctrl+C to cancel at any time.'
            echo ''
            sudo apt-mirror
            echo ''
            echo 'Mirror update completed!'
            read -p 'Press Enter to close...'
        "
    fi
}

use_local_mirror() {
    log "Switching to local mirror"
    
    local mirror_path
    mirror_path=$(get_local_mirror_path)
    local mirror_url="file://$mirror_path/mirror/archive.ubuntu.com/ubuntu"
    
    if [[ ! -d "$mirror_path/mirror/archive.ubuntu.com/ubuntu" ]]; then
        ui_msg "Mirror Not Ready" "Local mirror not found at:\n$mirror_path/mirror/archive.ubuntu.com/ubuntu\n\nPlease update the local mirror first."
        return 1
    fi
    
    if ui_yesno "Use Local Mirror" "Switch to local mirror for package installations?\n\nThis will modify /etc/apt/sources.list to use:\n$mirror_url\n\nYour current configuration will be backed up."; then
        # Backup current sources.list
        local backup_file="/etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/apt/sources.list "$backup_file"
        
        # Create new sources.list with local mirror
        local ubuntu_version
        ubuntu_version=$(lsb_release -cs 2>/dev/null || echo "jammy")
        
        cat > /etc/apt/sources.list << EOF
# Local mirror configuration - created by ultrabunt
# Backup saved as: $backup_file

deb $mirror_url $ubuntu_version main restricted universe multiverse
deb $mirror_url $ubuntu_version-updates main restricted universe multiverse
deb $mirror_url $ubuntu_version-backports main restricted universe multiverse
deb file://$mirror_path/mirror/security.ubuntu.com/ubuntu $ubuntu_version-security main restricted universe multiverse
EOF
        
        # Update package cache
        if apt-get update; then
            ui_msg "Success" "Successfully switched to local mirror!\n\nBackup saved as:\n$backup_file\n\nPackage cache updated."
            log "Switched to local mirror successfully"
        else
            ui_msg "Update Failed" "Mirror switched but package cache update failed.\nYou may need to run 'apt update' manually."
            log "WARNING: Package cache update failed after switching to local mirror"
        fi
    fi
}

# Main mirror management menu
show_mirror_management_menu() {
    log "Entering show_mirror_management_menu function"
    
    while true; do
        local current_mirror
        current_mirror=$(get_current_mirror)
        
        local mirrorselect_status="🔴 Not Installed"
        if is_mirrorselect_installed; then
            mirrorselect_status="🟢 Installed"
        fi
        
        local apt_mirror_status="🔴 Not Installed"
        if is_apt_mirror_installed; then
            apt_mirror_status="🟢 Installed"
        fi
        
        local local_mirror_path
        local_mirror_path=$(get_local_mirror_path)
        local local_mirror_status="🔴 Not Setup"
        if [[ -d "$local_mirror_path/mirror/archive.ubuntu.com/ubuntu" ]]; then
            local_mirror_status="🟢 Available at $local_mirror_path"
        fi
        
        local menu_items=()
        menu_items+=("current-mirror" "(.Y.) Current Mirror: $current_mirror")
        menu_items+=("" "(_*_)")
        menu_items+=("install-mirrorselect" "(.Y.) Install MirrorSelect Tool")
        menu_items+=("mirrorselect-options" "(.Y.) MirrorSelect Options & Modes")
        menu_items+=("scan-fastest" "(.Y.) Scan & Set Fastest Mirror (Quick)")
        menu_items+=("manual-mirrorselect" "(.Y.) Open MirrorSelect Terminal (Advanced)")
        menu_items+=("" "(_*_)")
        menu_items+=("install-apt-mirror" "(.Y.) Install apt-mirror Tool")
        menu_items+=("setup-local-mirror" "(.Y.) Setup Local Mirror Storage")
        menu_items+=("update-local-mirror" "(.Y.) Update Local Mirror (Download)")
        menu_items+=("use-local-mirror" "(.Y.) Switch to Local Mirror")
        menu_items+=("" "(_*_)")
        menu_items+=("back" "(Z) Back to Main Menu")
        
        local choice
        choice=$(ui_menu "Mirror Management" \
            "MirrorSelect Status: $mirrorselect_status\napt-mirror Status: $apt_mirror_status\nLocal Mirror: $local_mirror_status\nCurrent Mirror: $current_mirror\n\nOptimize your Ubuntu package downloads:" \
            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            current-mirror)
                local mirror_info="Current Ubuntu Mirror Configuration:\n\n"
                mirror_info+="Mirror Server: $current_mirror\n\n"
                mirror_info+="This is the server your system uses to download packages.\n"
                mirror_info+="A faster mirror can significantly improve download speeds.\n\n"
                mirror_info+="Use 'Scan & Set Fastest Mirror' to automatically find\n"
                mirror_info+="and configure the optimal mirror for your location.\n\n"
                mirror_info+="For offline installations, use the local mirror options\n"
                mirror_info+="to create a complete Ubuntu repository on your system."
                ui_info "Current Mirror Information" "$mirror_info"
                ;;
            install-mirrorselect)
                if is_mirrorselect_installed; then
                    ui_msg "Already Installed" "MirrorSelect is already installed on your system."
                else
                    if ui_yesno "Install MirrorSelect" "Install MirrorSelect tool for mirror optimization?\n\nThis will download and install the mirrorselect package."; then
                        install_mirrorselect
                    fi
                fi
                ;;
            mirrorselect-options)
                show_mirrorselect_options_menu
                ;;
            scan-fastest)
                if ui_yesno "Scan for Fastest Mirror" "Scan Ubuntu mirrors and automatically set the fastest one?\n\nThis will:\n• Test multiple Ubuntu mirrors\n• Select the fastest one\n• Update your system configuration\n• Backup your current settings\n\nThis process may take a few minutes."; then
                    scan_and_set_fastest_mirror
                fi
                ;;
            manual-mirrorselect)
                if is_mirrorselect_installed; then
                    ui_info "Manual MirrorSelect" "Opening terminal for manual mirror selection...\n\nCommon commands:\n• mirrorselect -i (interactive mode)\n• mirrorselect -s3 (select 3 fastest)\n• mirrorselect -h (help)\n\nPress any key to continue..."
                    # Open terminal with mirrorselect
                    gnome-terminal -- bash -c "echo 'MirrorSelect Manual Mode - Type \"mirrorselect -h\" for help'; mirrorselect -i; read -p 'Press Enter to close...'"
                else
                    ui_msg "Not Installed" "MirrorSelect is not installed. Please install it first using the 'Install MirrorSelect Tool' option."
                fi
                ;;
            install-apt-mirror)
                if is_apt_mirror_installed; then
                    ui_msg "Already Installed" "apt-mirror is already installed on your system."
                else
                    if ui_yesno "Install apt-mirror" "Install apt-mirror tool for local repository creation?\n\nThis will download and install the apt-mirror package."; then
                        install_apt_mirror
                    fi
                fi
                ;;
            setup-local-mirror)
                if ! is_apt_mirror_installed; then
                    ui_msg "Not Installed" "apt-mirror is not installed. Please install it first."
                else
                    setup_local_mirror
                fi
                ;;
            update-local-mirror)
                update_local_mirror
                ;;
            use-local-mirror)
                use_local_mirror
                ;;
            back|z|"")
                break
                ;;
        esac
    done
    
    log "Exiting show_mirror_management_menu function"
}

# Function to show mirrorselect options submenu
show_mirrorselect_options_menu() {
    log "Entering show_mirrorselect_options_menu function"
    
    if ! is_mirrorselect_installed; then
        ui_msg "MirrorSelect Not Installed" "MirrorSelect is not installed on your system.\n\nPlease install it first from the Mirror Management menu."
        return
    fi
    
    while true; do
        local menu_items=()
        menu_items+=("interactive" "(.Y.) Interactive Mode - Select from list")
        menu_items+=("deep" "(.Y.) Deep Mode - Accurate speed test (100k file)")
        menu_items+=("auto" "(.Y.) Automatic Mode - Select fastest mirrors")
        menu_items+=("" "(_*_)")
        menu_items+=("country" "(.Y.) Filter by Country")
        menu_items+=("region" "(.Y.) Filter by Region")
        menu_items+=("" "(_*_)")
        menu_items+=("http-only" "(.Y.) HTTP Only Mode")
        menu_items+=("ftp-only" "(.Y.) FTP Only Mode")
        menu_items+=("ipv4-only" "(.Y.) IPv4 Only Mode")
        menu_items+=("ipv6-only" "(.Y.) IPv6 Only Mode")
        menu_items+=("" "(_*_)")
        menu_items+=("custom" "(.Y.) Custom Command Builder")
        menu_items+=("" "(_*_)")
        menu_items+=("zback" "(Z) ← Back to Mirror Management")
        
        local choice
        choice=$(ui_menu "MirrorSelect Options" \
            "Choose how to run MirrorSelect:\n\n• Interactive: Select mirrors from a list\n• Deep: More accurate but slower testing\n• Automatic: Let mirrorselect choose the fastest\n• Filters: Limit by country, region, or protocol" \
            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT "${menu_items[@]}") || break
        
        case "$choice" in
            interactive)
                run_mirrorselect_interactive
                ;;
            deep)
                run_mirrorselect_deep
                ;;
            auto)
                run_mirrorselect_auto
                ;;
            country)
                run_mirrorselect_country
                ;;
            region)
                run_mirrorselect_region
                ;;
            http-only)
                run_mirrorselect_protocol "http"
                ;;
            ftp-only)
                run_mirrorselect_protocol "ftp"
                ;;
            ipv4-only)
                run_mirrorselect_protocol "ipv4"
                ;;
            ipv6-only)
                run_mirrorselect_protocol "ipv6"
                ;;
            custom)
                run_mirrorselect_custom
                ;;
            zback|back|z|"")
                break
                ;;
        esac
    done
    
    log "Exiting show_mirrorselect_options_menu function"
}

# Function to run mirrorselect in interactive mode
run_mirrorselect_interactive() {
    log "Running mirrorselect in interactive mode"
    
    if ui_yesno "Interactive Mirror Selection" "Run MirrorSelect in interactive mode?\n\nThis will present a list of mirrors for you to select from.\nThe selected mirrors will be applied to your system."; then
        ui_msg "Running MirrorSelect" "Starting interactive mirror selection...\n\nPlease wait while the mirror list is loaded."
        
        if sudo mirrorselect -i; then
            ui_msg "Success" "Mirror selection completed successfully!\n\nYour system has been updated with the selected mirrors."
            log "MirrorSelect interactive mode completed successfully"
        else
            ui_msg "Error" "MirrorSelect failed to complete.\n\nPlease check your internet connection and try again."
            log "MirrorSelect interactive mode failed"
        fi
    fi
}

# Function to run mirrorselect in deep mode
run_mirrorselect_deep() {
    log "Running mirrorselect in deep mode"
    
    local warning_msg="Deep Mode Warning:\n\n"
    warning_msg+="• Downloads a 100KB file from each server\n"
    warning_msg+="• More accurate but significantly slower\n"
    warning_msg+="• Recommended only for good connections\n"
    warning_msg+="• May take several minutes to complete\n\n"
    warning_msg+="Continue with deep mode testing?"
    
    if ui_yesno "Deep Mode Mirror Testing" "$warning_msg"; then
        ui_msg "Running Deep Mode" "Starting deep mode mirror testing...\n\nThis will take several minutes.\nPlease be patient while testing completes."
        
        if sudo mirrorselect -D -i; then
            ui_msg "Success" "Deep mode mirror selection completed!\n\nYour system has been updated with the fastest mirrors."
            log "MirrorSelect deep mode completed successfully"
        else
            ui_msg "Error" "Deep mode testing failed.\n\nPlease check your internet connection and try again."
            log "MirrorSelect deep mode failed"
        fi
    fi
}

# Function to run mirrorselect in automatic mode
run_mirrorselect_auto() {
    log "Running automatic mirror selection for Ubuntu"
    
    local servers
    servers=$(ui_input "Number of Servers" "How many servers should be tested for speed?\n\nEnter a number between 1 and 10:" "3")
    
    if [[ -z "$servers" ]] || ! [[ "$servers" =~ ^[0-9]+$ ]] || [[ "$servers" -lt 1 ]] || [[ "$servers" -gt 10 ]]; then
        ui_msg "Invalid Input" "Please enter a valid number between 1 and 10."
        return
    fi
    
    if ui_yesno "Automatic Mirror Selection" "Test and select the fastest Ubuntu mirror?\n\nThis will test multiple mirrors and configure the fastest one."; then
        ui_msg "Testing Mirrors" "Testing Ubuntu mirrors for speed...\n\nThis may take a few minutes. Please wait."
        
        # Create temporary directory for netselect-apt
        local temp_dir=$(mktemp -d)
        cd "$temp_dir" || return 1
        
        # Run netselect-apt to find fastest mirror
        if sudo netselect-apt -n -o sources.list; then
            # Extract the mirror URL from the generated sources.list
            local new_mirror=$(grep -E "^deb\s+https?://" sources.list | head -1 | awk '{print $2}' | sed 's|https\?://||' | sed 's|/.*||')
            
            if [[ -n "$new_mirror" ]]; then
                # Backup current sources.list
                sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)
                
                # Replace the mirror in sources.list
                sudo sed -i.bak "s|archive\.ubuntu\.com|$new_mirror|g; s|[a-z][a-z]\.archive\.ubuntu\.com|$new_mirror|g" /etc/apt/sources.list
                
                # Update package lists
                if sudo apt update; then
                    ui_msg "Success" "Fastest mirror configured successfully!\n\nNew mirror: $new_mirror\n\nPackage lists have been updated."
                    log "Mirror selection completed: $new_mirror"
                else
                    ui_msg "Warning" "Mirror configured but package update failed.\n\nNew mirror: $new_mirror\n\nYou may need to run 'sudo apt update' manually."
                fi
            else
                ui_msg "Error" "Could not determine fastest mirror.\n\nPlease try again or select a mirror manually."
                log "Mirror selection failed - no mirror found"
            fi
        else
            ui_msg "Error" "Mirror testing failed.\n\nPlease check your internet connection and try again."
            log "netselect-apt failed"
        fi
        
        # Cleanup
        cd - >/dev/null
        rm -rf "$temp_dir"
    fi
}

# Function to run mirrorselect with country filter
run_mirrorselect_country() {
    log "Running mirrorselect with country filter"
    
    local country
    country=$(ui_input "Country Filter" "Enter the country name to filter mirrors:\n\nExamples:\n• United States\n• Germany\n• Japan\n• 'South Korea' (use quotes for spaces)\n\nCountry name:" "")
    
    if [[ -z "$country" ]]; then
        ui_msg "No Country" "No country specified. Operation cancelled."
        return
    fi
    
    if ui_yesno "Country Filter" "Filter mirrors by country: $country\n\nThis will show only mirrors from the specified country."; then
        ui_msg "Filtering by Country" "Loading mirrors from $country...\n\nPlease wait while the list is prepared."
        
        if sudo mirrorselect -c "$country" -i; then
            ui_msg "Success" "Country-filtered mirror selection completed!"
            log "MirrorSelect country filter completed for: $country"
        else
            ui_msg "Error" "Country filtering failed.\n\nPlease check the country name and try again."
            log "MirrorSelect country filter failed for: $country"
        fi
    fi
}

# Function to run mirrorselect with region filter
run_mirrorselect_region() {
    log "Running mirrorselect with region filter"
    
    local region
    region=$(ui_input "Region Filter" "Enter the region name to filter mirrors:\n\nExamples:\n• North America\n• Europe\n• Asia\n• 'South America' (use quotes for spaces)\n\nRegion name:" "")
    
    if [[ -z "$region" ]]; then
        ui_msg "No Region" "No region specified. Operation cancelled."
        return
    fi
    
    if ui_yesno "Region Filter" "Filter mirrors by region: $region\n\nThis will show only mirrors from the specified region."; then
        ui_msg "Filtering by Region" "Loading mirrors from $region...\n\nPlease wait while the list is prepared."
        
        if sudo mirrorselect -R "$region" -i; then
            ui_msg "Success" "Region-filtered mirror selection completed!"
            log "MirrorSelect region filter completed for: $region"
        else
            ui_msg "Error" "Region filtering failed.\n\nPlease check the region name and try again."
            log "MirrorSelect region filter failed for: $region"
        fi
    fi
}

# Function to run mirrorselect with protocol filter
run_mirrorselect_protocol() {
    local protocol="$1"
    log "Running mirrorselect with $protocol protocol filter"
    
    local protocol_flag=""
    local protocol_name=""
    
    case "$protocol" in
        http)
            protocol_flag="-H"
            protocol_name="HTTP"
            ;;
        ftp)
            protocol_flag="-F"
            protocol_name="FTP"
            ;;
        ipv4)
            protocol_flag="-4"
            protocol_name="IPv4"
            ;;
        ipv6)
            protocol_flag="-6"
            protocol_name="IPv6"
            ;;
    esac
    
    if ui_yesno "$protocol_name Only Mode" "Filter mirrors to $protocol_name only?\n\nThis will show only mirrors that support $protocol_name."; then
        ui_msg "Filtering by $protocol_name" "Loading $protocol_name mirrors...\n\nPlease wait while the list is prepared."
        
        if sudo mirrorselect "$protocol_flag" -i; then
            ui_msg "Success" "$protocol_name-filtered mirror selection completed!"
            log "MirrorSelect $protocol filter completed"
        else
            ui_msg "Error" "$protocol_name filtering failed.\n\nPlease try again."
            log "MirrorSelect $protocol filter failed"
        fi
    fi
}

# Function to build custom mirrorselect command
run_mirrorselect_custom() {
    log "Building custom mirrorselect command"
    
    local custom_info="Custom MirrorSelect Command Builder\n\n"
    custom_info+="Build your own mirrorselect command with specific options.\n"
    custom_info+="You can combine multiple flags for advanced usage.\n\n"
    custom_info+="Available options:\n"
    custom_info+="• -i: Interactive mode\n"
    custom_info+="• -D: Deep mode (100k test)\n"
    custom_info+="• -s N: Select N servers\n"
    custom_info+="• -b N: Block size for testing\n"
    custom_info+="• -c 'Country': Filter by country\n"
    custom_info+="• -R 'Region': Filter by region\n"
    custom_info+="• -H: HTTP only\n"
    custom_info+="• -F: FTP only\n"
    custom_info+="• -4: IPv4 only\n"
    custom_info+="• -6: IPv6 only\n"
    custom_info+="• -t N: Timeout in seconds\n"
    custom_info+="• -q: Quiet mode\n"
    
    ui_info "Custom Command Builder" "$custom_info"
    
    local custom_flags
    custom_flags=$(ui_input "Custom Flags" "Enter mirrorselect flags (without 'sudo mirrorselect'):\n\nExample: -D -s 3 -c 'United States'\nExample: -i -H -4\n\nFlags:" "-i")
    
    if [[ -z "$custom_flags" ]]; then
        ui_msg "No Flags" "No flags specified. Operation cancelled."
        return
    fi
    
    local full_command="sudo mirrorselect $custom_flags"
    
    if ui_yesno "Execute Custom Command" "Execute this command?\n\n$full_command\n\nThis will run mirrorselect with your custom options."; then
        ui_msg "Running Custom Command" "Executing: $full_command\n\nPlease wait..."
        
        if eval "$full_command"; then
            ui_msg "Success" "Custom mirrorselect command completed successfully!"
            log "Custom mirrorselect command completed: $full_command"
        else
            ui_msg "Error" "Custom command failed.\n\nPlease check your flags and try again."
            log "Custom mirrorselect command failed: $full_command"
        fi
    fi
}

# ==============================================================================
# KEYBOARD LAYOUT CONFIGURATION
# ==============================================================================

# Function to detect current keyboard layout
get_current_keyboard_layout() {
    if [[ -f "$HOME/.config/ultrabunt-keyboard-layout" ]]; then
        cat "$HOME/.config/ultrabunt-keyboard-layout"
    else
        echo "none"
    fi
}

show_keyboard_layout_menu() {
    log "Entering show_keyboard_layout_menu function"
    
    while true; do
        local current_layout
        current_layout=$(get_current_keyboard_layout)
        
        local macbook_status="(_*_)"
        local thinkpad_status="(_*_)"
        local generic_status="(_*_)"
        
        case "$current_layout" in
            "macbook")
                macbook_status="(.Y.)"
                ;;
            "thinkpad")
                thinkpad_status="(.Y.)"
                ;;
            "generic")
                generic_status="(.Y.)"
                ;;
        esac
        
        local menu_items=(
            "macbook" "$macbook_status MacBook Layout (Cmd as Super, Cmd+Tab switching)"
            "thinkpad" "$thinkpad_status ThinkPad Layout (Standard PC layout optimized)"
            "generic" "$generic_status Generic Laptop Layout (Standard configuration)"
            "" "(_*_)"
            "current-status" "(.Y.) Show Current Keyboard Configuration"
            "reset" "(.Y.) Reset to Ubuntu Defaults"
            "" "(_*_)"
            "zback" "(Z) ← Back to Main Menu"
        )
        
        local choice
        choice=$(ui_menu "Keyboard Layout Configuration" \
            "Choose a keyboard layout optimized for your laptop:" \
            20 80 12 "${menu_items[@]}") || break
        
        case "$choice" in
            macbook)
                configure_macbook_layout
                ;;
            thinkpad)
                configure_thinkpad_layout
                ;;
            generic)
                configure_generic_layout
                ;;
            current-status)
                show_keyboard_status
                ;;
            reset)
                reset_keyboard_layout
                ;;
            back|zback|z|"")
                break
                ;;
        esac
    done
    
    log "Exiting show_keyboard_layout_menu function"
}

configure_macbook_layout() {
    log "Configuring MacBook keyboard layout"
    
    local info="MacBook Layout Configuration:\n\n"
    info+="• Command key → Super key (for shortcuts)\n"
    info+="• Cmd+Tab → Switch applications\n"
    info+="• Cmd+\` → Switch windows of same app\n"
    info+="• Cmd+C/V/X/Z → Copy/Paste/Cut/Undo\n"
    info+="• Cmd+Space → Show applications\n"
    info+="• Control key remains as Control\n\n"
    info+="This layout makes Ubuntu feel more like macOS.\n\n"
    info+="Apply this configuration?"
    
    if ui_yesno "MacBook Layout" "$info"; then
        apply_macbook_keyboard_config
        ui_msg "Success" "MacBook keyboard layout applied successfully!\n\nYou may need to log out and back in for all changes to take effect."
    fi
}

configure_thinkpad_layout() {
    log "Configuring ThinkPad keyboard layout"
    
    local info="ThinkPad Layout Configuration:\n\n"
    info+="• Optimized for ThinkPad keyboards\n"
    info+="• Caps Lock → Additional Control key\n"
    info+="• Alt+Tab → Switch applications\n"
    info+="• Super key for launcher\n"
    info+="• Standard PC shortcuts (Ctrl+C/V/X/Z)\n\n"
    info+="This layout optimizes the ThinkPad keyboard experience.\n\n"
    info+="Apply this configuration?"
    
    if ui_yesno "ThinkPad Layout" "$info"; then
        apply_thinkpad_keyboard_config
        ui_msg "Success" "ThinkPad keyboard layout applied successfully!\n\nYou may need to log out and back in for all changes to take effect."
    fi
}

configure_generic_layout() {
    log "Configuring generic laptop keyboard layout"
    
    local info="Generic Laptop Layout Configuration:\n\n"
    info+="• Standard PC keyboard layout\n"
    info+="• Alt+Tab → Switch applications\n"
    info+="• Super key for launcher\n"
    info+="• Standard shortcuts (Ctrl+C/V/X/Z)\n"
    info+="• Optimized for most laptop keyboards\n\n"
    info+="This is a safe, standard configuration.\n\n"
    info+="Apply this configuration?"
    
    if ui_yesno "Generic Layout" "$info"; then
        apply_generic_keyboard_config
        ui_msg "Success" "Generic keyboard layout applied successfully!\n\nYou may need to log out and back in for all changes to take effect."
    fi
}

show_keyboard_status() {
    log "Showing current keyboard configuration status"
    
    local status_info=""
    
    # Check current XKB options
    local xkb_options
    xkb_options=$(setxkbmap -query | grep options || echo "options: (none)")
    
    # Check gsettings for key mappings
    local switch_apps
    switch_apps=$(gsettings get org.gnome.desktop.wm.keybindings switch-applications 2>/dev/null || echo "Not set")
    
    local switch_windows
    switch_windows=$(gsettings get org.gnome.desktop.wm.keybindings switch-windows 2>/dev/null || echo "Not set")
    
    status_info="Current Keyboard Configuration:\n\n"
    status_info+="XKB Options: ${xkb_options#options: }\n\n"
    status_info+="Switch Applications: $switch_apps\n"
    status_info+="Switch Windows: $switch_windows\n\n"
    
    # Check for autostart keyboard mapping
    if [[ -f "$HOME/.config/autostart/keyboard-mapping.desktop" ]]; then
        status_info+="Autostart Mapping: ✓ Enabled\n"
    else
        status_info+="Autostart Mapping: ✗ Not configured\n"
    fi
    
    ui_info "Keyboard Status" "$status_info"
}

reset_keyboard_layout() {
    log "Resetting keyboard layout to Ubuntu defaults"
    
    local info="Reset Keyboard Layout:\n\n"
    info+="This will restore Ubuntu's default keyboard configuration:\n\n"
    info+="• Remove all custom key mappings\n"
    info+="• Reset XKB options to defaults\n"
    info+="• Remove autostart keyboard configurations\n"
    info+="• Restore standard Ubuntu shortcuts\n\n"
    info+="⚠️  This will undo any custom keyboard configurations.\n\n"
    info+="Continue with reset?"
    
    if ui_yesno "Reset Keyboard" "$info"; then
        apply_keyboard_reset
        ui_msg "Success" "Keyboard layout reset to Ubuntu defaults!\n\nYou may need to log out and back in for all changes to take effect."
    fi
}

apply_macbook_keyboard_config() {
    log "Applying MacBook keyboard configuration"
    
    # Create autostart directory if it doesn't exist
    mkdir -p "$HOME/.config/autostart"
    
    # Create autostart file for MacBook keyboard mapping
    cat > "$HOME/.config/autostart/keyboard-mapping.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Keyboard Mapping
Exec=/bin/bash -c "setxkbmap -option altwin:swap_lalt_lwin"
X-GNOME-Autostart-enabled=true
EOF
    
    # Apply the mapping immediately - swap Alt and Super keys so Command acts like Super
    setxkbmap -option altwin:swap_lalt_lwin 2>/dev/null || log "Warning: Could not apply setxkbmap immediately"
    
    # Configure GNOME shortcuts for macOS-like behavior using Super (Command) key
    gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Super>Tab']" 2>/dev/null || log "Warning: Could not set switch-applications"
    gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Super>grave']" 2>/dev/null || log "Warning: Could not set switch-windows"
    
    # Set Super+Space for show applications (like Spotlight)
    gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>space']" 2>/dev/null || log "Warning: Could not set toggle-overview"
    
    # Set macOS-style copy/paste shortcuts using Super (Command) key
    gsettings set org.gnome.desktop.wm.keybindings close "['<Super>w']" 2>/dev/null || log "Warning: Could not set close window"
    gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "['<Super>t']" 2>/dev/null || log "Warning: Could not set terminal shortcut"
    
    # Create a flag file to indicate MacBook layout is active
    echo "macbook" > "$HOME/.config/ultrabunt-keyboard-layout"
    
    log "MacBook keyboard configuration applied"
}

apply_thinkpad_keyboard_config() {
    log "Applying ThinkPad keyboard configuration"
    
    # Create autostart directory if it doesn't exist
    mkdir -p "$HOME/.config/autostart"
    
    # Create autostart file for ThinkPad optimizations
    cat > "$HOME/.config/autostart/keyboard-mapping.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Keyboard Mapping
Exec=/bin/bash -c "setxkbmap -option caps:ctrl_modifier"
X-GNOME-Autostart-enabled=true
EOF
    
    # Apply the mapping immediately
    setxkbmap -option caps:ctrl_modifier 2>/dev/null || log "Warning: Could not apply setxkbmap immediately"
    
    # Configure standard GNOME shortcuts
    gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Alt>Tab']" 2>/dev/null || log "Warning: Could not set switch-applications"
    gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>grave']" 2>/dev/null || log "Warning: Could not set switch-windows"
    
    # Create a flag file to indicate ThinkPad layout is active
    echo "thinkpad" > "$HOME/.config/ultrabunt-keyboard-layout"
    
    log "ThinkPad keyboard configuration applied"
}

apply_generic_keyboard_config() {
    log "Applying generic laptop keyboard configuration"
    
    # Remove any existing autostart keyboard mapping
    rm -f "$HOME/.config/autostart/keyboard-mapping.desktop" 2>/dev/null || true
    
    # Reset XKB options to default
    setxkbmap -option 2>/dev/null || log "Warning: Could not reset setxkbmap options"
    
    # Configure standard GNOME shortcuts
    gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Alt>Tab']" 2>/dev/null || log "Warning: Could not set switch-applications"
    gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>grave']" 2>/dev/null || log "Warning: Could not set switch-windows"
    
    # Create a flag file to indicate generic layout is active
    echo "generic" > "$HOME/.config/ultrabunt-keyboard-layout"
    
    log "Generic laptop keyboard configuration applied"
}

apply_keyboard_reset() {
    log "Resetting keyboard configuration to Ubuntu defaults"
    
    # Remove autostart keyboard mapping
    rm -f "$HOME/.config/autostart/keyboard-mapping.desktop" 2>/dev/null || true
    
    # Reset XKB options to default
    setxkbmap -option 2>/dev/null || log "Warning: Could not reset setxkbmap options"
    
    # Reset GNOME shortcuts to defaults
    gsettings reset org.gnome.desktop.wm.keybindings switch-applications 2>/dev/null || log "Warning: Could not reset switch-applications"
    gsettings reset org.gnome.desktop.wm.keybindings switch-windows 2>/dev/null || log "Warning: Could not reset switch-windows"
    gsettings reset org.gnome.shell.keybindings toggle-overview 2>/dev/null || log "Warning: Could not reset toggle-overview"
    
    # Remove the layout flag file
    rm -f "$HOME/.config/ultrabunt-keyboard-layout" 2>/dev/null || true
    
    log "Keyboard configuration reset to defaults"
}

# ==============================================================================
# DATABASE MANAGEMENT FUNCTIONS
# ==============================================================================

show_database_management_menu() {
    log "Entering show_database_management_menu function"
    
    while true; do
        local menu_items=()
        
        # Check MariaDB status
        local mariadb_status="🔴 Not Running"
        if systemctl is-active --quiet mariadb; then
            mariadb_status="🟢 Running"
        fi
        
        menu_items+=("show-credentials" "(.Y.) Show MariaDB Root Credentials")
        menu_items+=("reset-root-password" "(.Y.) Reset MariaDB Root Password")
        menu_items+=("list-databases" "(.Y.) List All Databases")
        menu_items+=("list-users" "(.Y.) List Database Users")
        menu_items+=("create-database" "(.Y.) Create New Database")
        menu_items+=("create-user" "(.Y.) Create Database User")
        menu_items+=("backup-database" "(.Y.) Backup Database")
        menu_items+=("service-control" "(.Y.) MariaDB Service Control")
        
        # Show logout option if session is active
        if [[ "$MARIADB_SESSION_ACTIVE" == "true" ]]; then
            menu_items+=("logout-session" "(.Y.) Logout (Clear Saved Password)")
        fi
        
        menu_items+=("" "(_*_)")
        menu_items+=("zback" "(Z) Back to Main Menu")
        
        local choice
        choice=$(ui_menu "Database Management" \
            "MariaDB Status: $mariadb_status\n\nSelect database management option:" \
            35 120 15 "${menu_items[@]}") || break
        
        case "$choice" in
            show-credentials)
                show_mariadb_credentials
                ;;
            reset-root-password)
                reset_mariadb_root_password
                ;;
            list-databases)
                list_databases
                ;;
            list-users)
                list_database_users
                ;;
            create-database)
                create_database_interactive
                ;;
            create-user)
                create_database_user_interactive
                ;;
            backup-database)
                backup_database_interactive
                ;;
            service-control)
                mariadb_service_control
                ;;
            logout-session)
                MARIADB_SESSION_ACTIVE=false
                MARIADB_SESSION_PASSWORD=""
                ui_msg "Session Cleared" "MariaDB session cleared successfully.\n\nYou will need to re-enter the password for future operations."
                log "MariaDB session cleared by user"
                ;;
            zback|back|"")
                break
                ;;
        esac
    done
    
    log "Exiting show_database_management_menu function"
}

# ==============================================================================
# SWAPPINESS TUNING
# ==============================================================================

get_runtime_swappiness() {
    local value=""
    if command -v sysctl >/dev/null 2>&1; then
        value=$(sysctl -n vm.swappiness 2>/dev/null || true)
    fi
    if [[ -z "$value" && -r /proc/sys/vm/swappiness ]]; then
        value=$(cat /proc/sys/vm/swappiness 2>/dev/null || true)
    fi
    echo "${value:-unknown}"
}

get_persistent_swappiness() {
    local file="/etc/sysctl.conf"
    if [[ ! -r "$file" ]]; then
        echo ""
        return 0
    fi
    local line
    line=$(grep -E '^[[:space:]]*vm\.swappiness[[:space:]]*=' "$file" | grep -v '^[[:space:]]*#' | tail -n 1)
    if [[ -z "$line" ]]; then
        echo ""
    else
        echo "$line" | sed -E 's/^[[:space:]]*vm\.swappiness[[:space:]]*=[[:space:]]*([0-9]+).*/\1/'
    fi
}

validate_swappiness_value() {
    local v="$1"
    if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 0 && v <= 100 )); then
        return 0
    fi
    return 1
}

set_runtime_swappiness() {
    local v="$1"
    if ! validate_swappiness_value "$v"; then
        ui_msg "Invalid Value" "Please enter a number between 0 and 100."
        return 1
    fi
    if ! command -v sysctl >/dev/null 2>&1; then
        log_error "sysctl command not found"
        ui_msg "Error" "sysctl command not found on this system."
        return 1
    fi
    if sudo sysctl vm.swappiness="$v" >/dev/null 2>&1; then
        ui_msg "Runtime Updated" "Swappiness set to $v (runtime).\nCurrent runtime value: $(get_runtime_swappiness)"
        return 0
    else
        log_error "Failed to set runtime swappiness"
        ui_msg "Error" "Failed to set runtime swappiness. See /var/log/ultrabunt.log for details."
        return 1
    fi
}

ensure_persistent_swappiness() {
    local v="$1"
    if ! validate_swappiness_value "$v"; then
        ui_msg "Invalid Value" "Please enter a number between 0 and 100."
        return 1
    fi
    local file="/etc/sysctl.conf"
    if [[ ! -f "$file" ]]; then
        echo "vm.swappiness=$v" | sudo tee "$file" >/dev/null
    else
        if grep -Eq '^[[:space:]]*#?[[:space:]]*vm\\.swappiness[[:space:]]*=' "$file"; then
            sudo sed -i -E 's/^[[:space:]]*#?[[:space:]]*vm\\.swappiness[[:space:]]*=.*/vm.swappiness='"$v"'/g' "$file"
        else
            echo "vm.swappiness=$v" | sudo tee -a "$file" >/dev/null
        fi
    fi
    return 0
}

reload_sysctl_conf() {
    if sudo sysctl -p /etc/sysctl.conf >/dev/null 2>&1; then
        ui_msg "Sysctl Reloaded" "sysctl.conf reloaded.\nCurrent runtime value: $(get_runtime_swappiness)"
        return 0
    else
        log_warning "Failed to reload sysctl.conf"
        ui_msg "Error" "Failed to reload /etc/sysctl.conf."
        return 1
    fi
}

show_sysctl_swappiness_lines() {
    local file="/etc/sysctl.conf"
    local lines
    if [[ -r "$file" ]]; then
        lines=$(grep -n -E 'vm\\.swappiness' "$file" 2>/dev/null)
    fi
    ui_info "sysctl.conf swappiness" "${lines:-No swappiness entry found in /etc/sysctl.conf}"
}

show_swappiness_menu() {
    log "Entering show_swappiness_menu"
    while true; do
        local runtime_val persistent_val entry_state
        runtime_val=$(get_runtime_swappiness)
        persistent_val=$(get_persistent_swappiness)
        if [[ -n "$persistent_val" ]]; then
            entry_state="Persistent entry present (vm.swappiness=$persistent_val)"
        else
            entry_state="No persistent entry in /etc/sysctl.conf"
        fi

        local info="Swappiness Controls\n\n"
        info+="Runtime value: ${runtime_val}\n"
        info+="Persistent (/etc/sysctl.conf): ${persistent_val:-none}\n"
        info+="State: ${entry_state}\n\nChoose an action:"

        local menu_items=(
            "set-10" "(.Y.) Set runtime to 10"
            "set-30" "(.Y.) Set runtime to 30"
            "set-40" "(.Y.) Set runtime to 40"
            "set-custom" "(.Y.) Set runtime to custom value"
            "" "(_*_)"
            "persist-10" "(.Y.) Persist swappiness 10"
            "persist-30" "(.Y.) Persist swappiness 30"
            "persist-40" "(.Y.) Persist swappiness 40"
            "persist-custom" "(.Y.) Persist custom value"
            "apply-persist" "(.Y.) Reload sysctl.conf (apply persistent values)"
            "show-entry" "(.Y.) Show sysctl.conf swappiness lines"
            "edit-conf" "(.Y.) Edit /etc/sysctl.conf"
            "" "(_*_)"
            "zback" "(Z) ← Back to Main Menu"
        )

        local choice
        choice=$(ui_menu "Swappiness Tuning" "$info" 25 90 15 "${menu_items[@]}") || break

        case "$choice" in
            set-10) set_runtime_swappiness 10 ;;
            set-30) set_runtime_swappiness 30 ;;
            set-40) set_runtime_swappiness 40 ;;
            set-custom)
                local val
                val=$(ui_input "Custom Swappiness" "Enter a value between 0 and 100:" "${runtime_val:-60}") || continue
                [[ -z "$val" ]] && continue
                set_runtime_swappiness "$val"
                ;;
            persist-10)
                ensure_persistent_swappiness 10 && ui_msg "Persistent Updated" "vm.swappiness set to 10 in /etc/sysctl.conf"
                ;;
            persist-30)
                ensure_persistent_swappiness 30 && ui_msg "Persistent Updated" "vm.swappiness set to 30 in /etc/sysctl.conf"
                ;;
            persist-40)
                ensure_persistent_swappiness 40 && ui_msg "Persistent Updated" "vm.swappiness set to 40 in /etc/sysctl.conf"
                ;;
            persist-custom)
                local pval
                pval=$(ui_input "Custom Persistent Value" "Enter a value between 0 and 100:" "${persistent_val:-60}") || continue
                [[ -z "$pval" ]] && continue
                if ensure_persistent_swappiness "$pval"; then
                    ui_msg "Persistent Updated" "vm.swappiness set to $pval in /etc/sysctl.conf"
                fi
                ;;
            apply-persist)
                reload_sysctl_conf
                ;;
            show-entry)
                show_sysctl_swappiness_lines
                ;;
            edit-conf)
                sudo nano /etc/sysctl.conf
                ;;
            zback|back|"")
                break
                ;;
        esac
    done
    log "Exiting show_swappiness_menu"
}

# LOG VIEWER FUNCTIONS
show_log_viewer_menu() {
    log "Entering show_log_viewer_menu function"
    
    while true; do
        local menu_items=()
        
        # Always show ultrabunt log
        menu_items+=("ultrabunt" "(.Y.) Ultrabunt Log (/var/log/ultrabunt.log)")
        
        # Check for common service logs and add them if they exist
        if [[ -f "/var/log/nginx/error.log" ]]; then
            menu_items+=("nginx-error" "(.Y.) Nginx Error Log")
        fi
        
        if [[ -f "/var/log/nginx/access.log" ]]; then
            menu_items+=("nginx-access" "(.Y.) Nginx Access Log")
        fi
        
        if [[ -f "/var/log/apache2/error.log" ]]; then
            menu_items+=("apache-error" "(.Y.) Apache Error Log")
        fi
        
        if [[ -f "/var/log/apache2/access.log" ]]; then
            menu_items+=("apache-access" "(.Y.) Apache Access Log")
        fi
        
        if [[ -f "/var/log/mysql/error.log" ]]; then
            menu_items+=("mysql-error" "(.Y.) MySQL Error Log")
        fi
        
        if [[ -f "/var/log/php8.1-fpm.log" ]] || [[ -f "/var/log/php8.2-fpm.log" ]] || [[ -f "/var/log/php8.3-fpm.log" ]]; then
            menu_items+=("php-fpm" "(.Y.) PHP-FPM Log")
        fi
        
        if [[ -f "/var/log/syslog" ]]; then
            menu_items+=("syslog" "(.Y.) System Log (syslog)")
        fi
        
        if [[ -f "/var/log/auth.log" ]]; then
            menu_items+=("auth" "(.Y.) Authentication Log")
        fi
        
        menu_items+=("" "(_*_)")
        menu_items+=("zback" "(Z) ← Back to Main Menu")
        
        local choice
        choice=$(ui_menu "Log Viewer" \
            "Select a log file to view:" \
            20 80 15 "${menu_items[@]}") || break
        
        case "$choice" in
            ultrabunt)
                view_log_file "/var/log/ultrabunt.log" "Ultrabunt Log"
                ;;
            nginx-error)
                view_log_file "/var/log/nginx/error.log" "Nginx Error Log"
                ;;
            nginx-access)
                view_log_file "/var/log/nginx/access.log" "Nginx Access Log"
                ;;
            apache-error)
                view_log_file "/var/log/apache2/error.log" "Apache Error Log"
                ;;
            apache-access)
                view_log_file "/var/log/apache2/access.log" "Apache Access Log"
                ;;
            mysql-error)
                view_log_file "/var/log/mysql/error.log" "MySQL Error Log"
                ;;
            php-fpm)
                # Find the correct PHP-FPM log file
                local php_fpm_log=""
                for version in 8.3 8.2 8.1; do
                    if [[ -f "/var/log/php${version}-fpm.log" ]]; then
                        php_fpm_log="/var/log/php${version}-fpm.log"
                        break
                    fi
                done
                if [[ -n "$php_fpm_log" ]]; then
                    view_log_file "$php_fpm_log" "PHP-FPM Log"
                fi
                ;;
            syslog)
                view_log_file "/var/log/syslog" "System Log"
                ;;
            auth)
                view_log_file "/var/log/auth.log" "Authentication Log"
                ;;
            zback|back|"")
                break
                ;;
        esac
    done
    
    log "Exiting show_log_viewer_menu function"
}

view_log_file() {
    local log_file="$1"
    local log_name="$2"
    
    log "Viewing log file: $log_file"
    
    if [[ ! -f "$log_file" ]]; then
        ui_msg "Log Not Found" "The log file $log_file does not exist or is not accessible."
        return 1
    fi
    
    # Check if file is readable
    if [[ ! -r "$log_file" ]]; then
        ui_msg "Permission Denied" "Cannot read $log_file. You may need administrator privileges."
        return 1
    fi
    
    # Get file size for display
    local file_size
    file_size=$(du -h "$log_file" 2>/dev/null | cut -f1)
    
    # Show options for viewing the log
    local choice
    choice=$(ui_menu "$log_name" \
        "File: $log_file (Size: $file_size)\nChoose how to view the log:" \
        15 70 4 \
        "last100" "View Last 100 Lines (Scrollable)" \
        "last500" "View Last 500 Lines (Scrollable)" \
        "full" "View Full Log File (Scrollable)" \
        "tail-follow" "Follow Live Updates (tail -f)")
    
    case "$choice" in
        last100)
            view_log_with_pager "$log_file" "$log_name" 100
            ;;
        last500)
            view_log_with_pager "$log_file" "$log_name" 500
            ;;
        full)
            view_log_with_pager "$log_file" "$log_name" "full"
            ;;
        tail-follow)
            clear
            echo "=== Following $log_name ==="
            echo "File: $log_file"
            echo "Press Ctrl+C to exit"
            echo "=========================="
            echo
            sudo tail -f "$log_file" 2>/dev/null || tail -f "$log_file" 2>/dev/null
            ;;
        *)
            return 0
            ;;
    esac
}

view_log_with_pager() {
    local log_file="$1"
    local log_name="$2"
    local lines="$3"
    
    local temp_file="/tmp/ultrabunt_log_view_$$"
    
    # Create header with file info
    {
        echo "=== $log_name ==="
        echo "File: $log_file"
        echo "Size: $(du -h "$log_file" 2>/dev/null | cut -f1)"
        if [[ "$lines" == "full" ]]; then
            echo "Showing: Full file"
        else
            echo "Showing: Last $lines lines"
        fi
        echo "Navigation: Use arrow keys, Page Up/Down, 'q' to quit"
        echo "=============================================="
        echo
    } > "$temp_file"
    
    # Add log content
    if [[ "$lines" == "full" ]]; then
        sudo cat "$log_file" 2>/dev/null >> "$temp_file" || cat "$log_file" 2>/dev/null >> "$temp_file"
    else
        sudo tail -n "$lines" "$log_file" 2>/dev/null >> "$temp_file" || tail -n "$lines" "$log_file" 2>/dev/null >> "$temp_file"
    fi
    
    # Use less with better options for log viewing
    if command -v less >/dev/null 2>&1; then
        # less with: 
        # -R: handle ANSI colors
        # -S: don't wrap long lines
        # -X: don't clear screen on exit
        # -F: quit if content fits on one screen
        # +G: start at end of file
        PAGER=cat less -RSX +G "$temp_file"
    else
        # Fallback to more if less is not available
        more "$temp_file"
    fi
    
    rm -f "$temp_file" 2>/dev/null
}

# Function to prompt for MariaDB root password and test connection
prompt_mariadb_password() {
    local password
    local attempt=1
    local max_attempts=3
    
    # Check if we have a valid session password first
    if [[ "$MARIADB_SESSION_ACTIVE" == "true" && -n "$MARIADB_SESSION_PASSWORD" ]]; then
        if mysql -u root -p"$MARIADB_SESSION_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
            echo "$MARIADB_SESSION_PASSWORD"
            return 0
        else
            # Session password is invalid, reset session
            MARIADB_SESSION_ACTIVE=false
            MARIADB_SESSION_PASSWORD=""
        fi
    fi
    
    while [[ $attempt -le $max_attempts ]]; do
        password=$(ui_password "MariaDB Root Password" "Enter MariaDB root password (attempt $attempt/$max_attempts):") || return 1
        
        if [[ -n "$password" ]] && mysql -u root -p"$password" -e "SELECT 1;" >/dev/null 2>&1; then
            # Store password in session for future use
            MARIADB_SESSION_PASSWORD="$password"
            MARIADB_SESSION_ACTIVE=true
            echo "$password"
            return 0
        else
            if [[ $attempt -eq $max_attempts ]]; then
                ui_msg "Authentication Failed" "Failed to authenticate with MariaDB after $max_attempts attempts.\n\nPlease check:\n• Password is correct\n• MariaDB is running\n• Root user exists\n\nTry resetting the root password if needed."
                return 1
            fi
            ui_msg "Invalid Password" "Password incorrect. Please try again.\n\nAttempt $attempt of $max_attempts"
        fi
        ((attempt++))
    done
    
    return 1
}

show_mariadb_credentials() {
    log "Displaying MariaDB credentials"
    
    # Check if password file exists and try to read it
    if sudo test -f "/root/.mysql_root_password"; then
        local root_pass
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null | tr -d '\n\r')
        
        if [[ -n "$root_pass" ]]; then
            local creds_msg="🔐 MariaDB Root Credentials\n\n"
            creds_msg+="• Username: root\n"
            creds_msg+="• Password: $root_pass\n"
            creds_msg+="• Host: localhost\n"
            creds_msg+="• Port: 3306\n\n"
            creds_msg+="🔧 Access Methods:\n"
            creds_msg+="• Command line: sudo mysql -u root -p\n"
            creds_msg+="• With password: mysql -u root -p'$root_pass'\n"
            creds_msg+="• Direct access: sudo mysql (as root user)\n\n"
            creds_msg+="📝 Password file: /root/.mysql_root_password\n"
            creds_msg+="📋 Copy password: $root_pass\n\n"
            creds_msg+="💡 Tips:\n"
            creds_msg+="• Use 'sudo mysql' for direct access without password\n"
            creds_msg+="• Create separate users for applications\n"
            creds_msg+="• Keep root password secure and backed up"
            
            ui_info "MariaDB Credentials" "$creds_msg"
            log "MariaDB root password displayed successfully"
        else
            ui_msg "No Password Found" "Root password file exists but is empty or unreadable.\n\nFile permissions: $(sudo ls -la /root/.mysql_root_password 2>/dev/null || echo 'File not accessible')\n\nYou may need to reset the root password."
            log "ERROR: Root password file is empty or unreadable"
        fi
    else
        # Check if we can access MariaDB without password (sudo method)
        if sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
            local creds_msg="🔐 MariaDB Root Access Available\n\n"
            creds_msg+="• Username: root\n"
            creds_msg+="• Password: Not set (using sudo authentication)\n"
            creds_msg+="• Host: localhost\n"
            creds_msg+="• Port: 3306\n\n"
            creds_msg+="🔧 Access Method:\n"
            creds_msg+="• Command line: sudo mysql\n\n"
            creds_msg+="⚠️ Note: No password file found at /root/.mysql_root_password\n"
            creds_msg+="This means MariaDB is using system authentication.\n\n"
            creds_msg+="💡 To set a password, use the 'Reset Root Password' option."
            
            ui_info "MariaDB Access" "$creds_msg"
            log "MariaDB accessible via sudo, no password file found"
        else
            ui_msg "No Credentials Found" "MariaDB root password file not found and sudo access failed.\n\nThis could mean:\n• MariaDB was not installed through this script\n• Password file was deleted\n• MariaDB security setup was not completed\n• MariaDB service is not running\n\nYou can:\n• Check MariaDB status\n• Reset the root password\n• Reinstall MariaDB"
            log "ERROR: No MariaDB access method available"
        fi
    fi
}

reset_mariadb_root_password() {
    log "Resetting MariaDB root password"
    
    if ! systemctl is-active --quiet mariadb; then
        ui_msg "MariaDB Not Running" "MariaDB service is not running.\n\nStart MariaDB first using the service control option."
        return
    fi
    
    if ui_yesno "Reset Root Password" "This will reset the MariaDB root password.\n\nContinue?"; then
        # Generate new password
        local new_pass
        new_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
        
        # Reset password
        if sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${new_pass}';" 2>/dev/null; then
            # Save new password
            echo "$new_pass" | sudo tee /root/.mysql_root_password > /dev/null
            sudo chmod 600 /root/.mysql_root_password
            
            ui_info "Password Reset Complete" "🔐 New MariaDB Root Password:\n\n• Username: root\n• Password: $new_pass\n• Host: localhost\n\n📝 Password saved to: /root/.mysql_root_password\n\n✅ Password reset successful!"
        else
            ui_msg "Reset Failed" "Failed to reset MariaDB root password.\n\nThis could be due to:\n• Current password is different\n• MariaDB access issues\n• Permission problems\n\nTry using: sudo mysql_secure_installation"
        fi
    fi
}

list_databases() {
    log "Listing databases"
    
    # Check if MariaDB service is running
    if ! systemctl is-active --quiet mariadb; then
        ui_msg "MariaDB Not Running" "MariaDB service is not running.\n\nStart MariaDB first using the service control option."
        return 1
    fi
    
    # Try to connect and list databases
    local db_list
    local root_pass=""
    
    # Get root password if available
    if [[ -f "/root/.mysql_root_password" ]]; then
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
    fi
    
    # Try different authentication methods
    if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        db_list=$(mysql -u root -p"$root_pass" -e "SHOW DATABASES;" 2>/dev/null | tail -n +2)
    elif sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        db_list=$(sudo mysql -e "SHOW DATABASES;" 2>/dev/null | tail -n +2)
    else
        # Prompt for password if other methods fail
        local manual_pass
        if manual_pass=$(prompt_mariadb_password); then
            db_list=$(mysql -u root -p"$manual_pass" -e "SHOW DATABASES;" 2>/dev/null | tail -n +2)
        else
            ui_msg "Database Access Error" "Cannot connect to MariaDB.\n\nThis could be due to:\n• Authentication issues\n• MariaDB not properly configured\n• Permission problems\n\nTry resetting the root password or check MariaDB logs."
            return 1
        fi
    fi
    
    if [[ -n "$db_list" ]]; then
        local db_msg="📊 MariaDB Databases\n\n"
        db_msg+="Available databases:\n\n"
        
        while IFS= read -r db; do
            if [[ "$db" == "information_schema" || "$db" == "performance_schema" || "$db" == "mysql" || "$db" == "sys" ]]; then
                db_msg+="• $db (system)\n"
            else
                db_msg+="• $db (user)\n"
            fi
        done <<< "$db_list"
        
        db_msg+="\n💡 System databases are used by MariaDB internally.\n"
        db_msg+="User databases contain your application data."
        
        ui_info "Database List" "$db_msg"
    else
        ui_msg "No Access" "Cannot access MariaDB databases.\n\nThis could be due to:\n• MariaDB not running\n• Authentication issues\n• Permission problems"
    fi
}

list_database_users() {
    log "Listing database users"
    
    # Check if MariaDB service is running
    if ! systemctl is-active --quiet mariadb; then
        ui_msg "MariaDB Not Running" "MariaDB service is not running.\n\nStart MariaDB first using the service control option."
        return 1
    fi
    
    # Try to connect and list users
    local user_list
    local root_pass=""
    
    # Get root password if available
    if [[ -f "/root/.mysql_root_password" ]]; then
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
    fi
    
    # Try different authentication methods
    if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        user_list=$(mysql -u root -p"$root_pass" -e "SELECT User, Host FROM mysql.user;" 2>/dev/null | tail -n +2)
    elif sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        user_list=$(sudo mysql -e "SELECT User, Host FROM mysql.user;" 2>/dev/null | tail -n +2)
    else
        # Prompt for password if other methods fail
        local manual_pass
        if manual_pass=$(prompt_mariadb_password); then
            user_list=$(mysql -u root -p"$manual_pass" -e "SELECT User, Host FROM mysql.user;" 2>/dev/null | tail -n +2)
        else
            ui_msg "Database Access Error" "Cannot connect to MariaDB.\n\nThis could be due to:\n• Authentication issues\n• MariaDB not properly configured\n• Permission problems\n\nTry resetting the root password or check MariaDB logs."
            return 1
        fi
    fi
    
    if [[ -n "$user_list" ]]; then
        local user_msg="👥 MariaDB Users\n\n"
        user_msg+="Current database users:\n\n"
        
        while IFS=$'\t' read -r user host; do
            if [[ "$user" == "root" ]]; then
                user_msg+="• $user@$host (administrator)\n"
            elif [[ "$user" == "mysql.sys" || "$user" == "mysql.session" || "$user" == "mysql.infoschema" ]]; then
                user_msg+="• $user@$host (system)\n"
            else
                user_msg+="• $user@$host (application)\n"
            fi
        done <<< "$user_list"
        
        user_msg+="\n💡 Root users have full administrative access.\n"
        user_msg+="Application users should have limited privileges."
        
        ui_info "Database Users" "$user_msg"
    else
        ui_msg "No Access" "Cannot access MariaDB user list.\n\nThis could be due to:\n• MariaDB not running\n• Authentication issues\n• Permission problems"
    fi
}

create_database_interactive() {
    log "Creating database interactively"
    
    if ! systemctl is-active --quiet mariadb; then
        ui_msg "MariaDB Not Running" "MariaDB service is not running.\n\nStart MariaDB first using the service control option."
        return
    fi
    
    local db_name
    db_name=$(ui_input "Database Name" "Enter database name:" "") || return
    
    if [[ -z "$db_name" ]]; then
        ui_msg "Invalid Input" "Database name cannot be empty."
        return
    fi
    
    # Validate database name
    if [[ ! "$db_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        ui_msg "Invalid Name" "Database name must:\n• Start with a letter\n• Contain only letters, numbers, and underscores\n• Not contain spaces or special characters"
        return
    fi
    
    # Try to create database with different authentication methods
    local root_pass=""
    local success=false
    
    # Get root password if available
    if [[ -f "/root/.mysql_root_password" ]]; then
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
    fi
    
    # Try different authentication methods
    if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        mysql -u root -p"$root_pass" -e "CREATE DATABASE ${db_name} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null && success=true
    elif sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        sudo mysql -e "CREATE DATABASE ${db_name} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null && success=true
    else
        # Prompt for password if other methods fail
        local manual_pass
        if manual_pass=$(prompt_mariadb_password); then
            mysql -u root -p"$manual_pass" -e "CREATE DATABASE ${db_name} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null && success=true
        fi
    fi
    
    if [[ "$success" == "true" ]]; then
        ui_info "Database Created" "✅ Database '$db_name' created successfully!\n\n• Name: $db_name\n• Character Set: utf8mb4\n• Collation: utf8mb4_unicode_ci\n\n💡 You can now create users and grant privileges to this database."
    else
        ui_msg "Creation Failed" "Failed to create database '$db_name'.\n\nThis could be due to:\n• Database already exists\n• Invalid name format\n• Permission issues\n• MariaDB access problems"
    fi
}

create_database_user_interactive() {
    log "Creating database user interactively"
    
    if ! systemctl is-active --quiet mariadb; then
        ui_msg "MariaDB Not Running" "MariaDB service is not running.\n\nStart MariaDB first using the service control option."
        return
    fi
    
    local username
    username=$(ui_input "Username" "Enter username:" "") || return
    
    if [[ -z "$username" ]]; then
        ui_msg "Invalid Input" "Username cannot be empty."
        return
    fi
    
    local password
    password=$(ui_input "Password" "Enter password (leave empty for auto-generated):" "") || return
    
    if [[ -z "$password" ]]; then
        password=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 16)
    fi
    
    local database
    database=$(ui_input "Database" "Enter database name to grant access to (optional):" "") || return
    
    # Create user with different authentication methods
    local root_pass=""
    local success=false
    
    # Get root password if available
    if [[ -f "/root/.mysql_root_password" ]]; then
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
    fi
    
    # Try different authentication methods
    if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        mysql -u root -p"$root_pass" -e "CREATE USER '${username}'@'localhost' IDENTIFIED BY '${password}';" 2>/dev/null && success=true
    elif sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        sudo mysql -e "CREATE USER '${username}'@'localhost' IDENTIFIED BY '${password}';" 2>/dev/null && success=true
    else
        # Prompt for password if other methods fail
        local manual_pass
        if manual_pass=$(prompt_mariadb_password); then
            mysql -u root -p"$manual_pass" -e "CREATE USER '${username}'@'localhost' IDENTIFIED BY '${password}';" 2>/dev/null && success=true
        fi
    fi
    
    # Create user
    if [[ "$success" == "true" ]]; then
        local success_msg="✅ User '$username' created successfully!\n\n• Username: $username\n• Password: $password\n• Host: localhost\n"
        
        # Grant privileges if database specified
        if [[ -n "$database" ]]; then
            if sudo mysql -e "GRANT ALL PRIVILEGES ON ${database}.* TO '${username}'@'localhost';" 2>/dev/null; then
                sudo mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
                success_msg+="\n🔐 Privileges granted:\n• Full access to database: $database"
            else
                success_msg+="\n⚠️  Could not grant privileges to database: $database"
            fi
        else
            success_msg+="\n💡 No database privileges granted.\nUse GRANT commands to assign specific permissions."
        fi
        
        ui_info "User Created" "$success_msg"
    else
        ui_msg "Creation Failed" "Failed to create user '$username'.\n\nThis could be due to:\n• User already exists\n• Invalid username format\n• Permission issues\n• MariaDB access problems"
    fi
}

backup_database_interactive() {
    log "Starting interactive database backup"
    
    if ! systemctl is-active --quiet mariadb; then
        ui_msg "MariaDB Not Running" "MariaDB service is not running.\n\nStart MariaDB first using the service control option."
        return
    fi
    
    # Get list of databases with different authentication methods
    local db_list
    local root_pass=""
    
    # Get root password if available
    if [[ -f "/root/.mysql_root_password" ]]; then
        root_pass=$(sudo cat /root/.mysql_root_password 2>/dev/null)
    fi
    
    # Try different authentication methods
    if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        db_list=$(mysql -u root -p"$root_pass" -e "SHOW DATABASES;" 2>/dev/null | tail -n +2 | grep -v -E '^(information_schema|performance_schema|mysql|sys)$')
    elif sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        db_list=$(sudo mysql -e "SHOW DATABASES;" 2>/dev/null | tail -n +2 | grep -v -E '^(information_schema|performance_schema|mysql|sys)$')
    else
        # Prompt for password if other methods fail
        local manual_pass
        if manual_pass=$(prompt_mariadb_password); then
            db_list=$(mysql -u root -p"$manual_pass" -e "SHOW DATABASES;" 2>/dev/null | tail -n +2 | grep -v -E '^(information_schema|performance_schema|mysql|sys)$')
        else
            ui_msg "Database Access Error" "Cannot connect to MariaDB to list databases."
            return
        fi
    fi
    
    if [[ -z "$db_list" ]]; then
        ui_msg "No Databases" "No user databases found to backup.\n\nOnly system databases are present."
        return
    fi
    
    local database
    database=$(ui_input "Database Name" "Enter database name to backup:\n\nAvailable databases:\n$(echo "$db_list" | sed 's/^/• /')" "") || return
    
    if [[ -z "$database" ]]; then
        ui_msg "Invalid Input" "Database name cannot be empty."
        return
    fi
    
    # Check if database exists
    if ! echo "$db_list" | grep -q "^${database}$"; then
        ui_msg "Database Not Found" "Database '$database' not found.\n\nAvailable databases:\n$(echo "$db_list" | sed 's/^/• /')"
        return
    fi
    
    local backup_dir="$BACKUP_DIR/database-backups"
    mkdir -p "$backup_dir"
    
    local backup_file="$backup_dir/${database}-$(date +%Y%m%d-%H%M%S).sql"
    
    # Perform backup with different authentication methods
    local backup_success=false
    
    # Try different authentication methods for mysqldump
    if [[ -n "$root_pass" ]] && mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        mysqldump -u root -p"$root_pass" "$database" > "$backup_file" 2>/dev/null && backup_success=true
    elif sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        sudo mysqldump "$database" > "$backup_file" 2>/dev/null && backup_success=true
    else
        # Use the manual password if we got one earlier
        if [[ -n "$manual_pass" ]]; then
            mysqldump -u root -p"$manual_pass" "$database" > "$backup_file" 2>/dev/null && backup_success=true
        fi
    fi
    
    if [[ "$backup_success" == "true" ]]; then
        local file_size
        file_size=$(du -h "$backup_file" | cut -f1)
        
        ui_info "Backup Complete" "✅ Database backup successful!\n\n• Database: $database\n• Backup file: $backup_file\n• File size: $file_size\n• Timestamp: $(date)\n\n💾 Backup saved to:\n$backup_file\n\n💡 To restore:\nmysql $database < $backup_file"
    else
        ui_msg "Backup Failed" "Failed to backup database '$database'.\n\nThis could be due to:\n• Database access issues\n• Insufficient disk space\n• Permission problems\n• MariaDB connection issues"
    fi
}

mariadb_service_control() {
    log "MariaDB service control"
    
    local status_msg="🔧 MariaDB Service Control\n\n"
    
    if systemctl is-active --quiet mariadb; then
        status_msg+="Current Status: 🟢 Running\n\n"
    else
        status_msg+="Current Status: 🔴 Not Running\n\n"
    fi
    
    local menu_items=()
    menu_items+=("start" "(.Y.) Start MariaDB")
    menu_items+=("stop" "(.Y.) Stop MariaDB")
    menu_items+=("restart" "(.Y.) Restart MariaDB")
    menu_items+=("status" "(.Y.) Show Detailed Status")
    menu_items+=("enable" "(.Y.) Enable Auto-start")
    menu_items+=("disable" "(.Y.) Disable Auto-start")
    menu_items+=("logs" "(.Y.) View Recent Logs")
    menu_items+=("" "(_*_)")
    menu_items+=("back" "(B) Back")
    
    local choice
    choice=$(ui_menu "MariaDB Service Control" "$status_msg" \
        25 80 12 "${menu_items[@]}") || return
    
    case "$choice" in
        start)
            if sudo systemctl start mariadb 2>/dev/null; then
                ui_msg "Service Started" "✅ MariaDB service started successfully!"
            else
                ui_msg "Start Failed" "❌ Failed to start MariaDB service.\n\nCheck logs for details:\nsudo journalctl -u mariadb -n 20"
            fi
            ;;
        stop)
            if ui_yesno "Stop MariaDB" "This will stop the MariaDB service.\n\nAll database connections will be terminated.\n\nContinue?"; then
                if sudo systemctl stop mariadb 2>/dev/null; then
                    ui_msg "Service Stopped" "✅ MariaDB service stopped successfully!"
                else
                    ui_msg "Stop Failed" "❌ Failed to stop MariaDB service."
                fi
            fi
            ;;
        restart)
            if sudo systemctl restart mariadb 2>/dev/null; then
                ui_msg "Service Restarted" "✅ MariaDB service restarted successfully!"
            else
                ui_msg "Restart Failed" "❌ Failed to restart MariaDB service.\n\nCheck logs for details:\nsudo journalctl -u mariadb -n 20"
            fi
            ;;
        status)
            local detailed_status
            detailed_status=$(sudo systemctl status mariadb 2>/dev/null || echo "Status unavailable")
            ui_info "MariaDB Status" "$detailed_status"
            ;;
        enable)
            if sudo systemctl enable mariadb 2>/dev/null; then
                ui_msg "Auto-start Enabled" "✅ MariaDB will now start automatically on boot!"
            else
                ui_msg "Enable Failed" "❌ Failed to enable MariaDB auto-start."
            fi
            ;;
        disable)
            if ui_yesno "Disable Auto-start" "This will prevent MariaDB from starting automatically on boot.\n\nContinue?"; then
                if sudo systemctl disable mariadb 2>/dev/null; then
                    ui_msg "Auto-start Disabled" "✅ MariaDB auto-start disabled!"
                else
                    ui_msg "Disable Failed" "❌ Failed to disable MariaDB auto-start."
                fi
            fi
            ;;
        logs)
            local recent_logs
            recent_logs=$(sudo journalctl -u mariadb -n 30 --no-pager 2>/dev/null || echo "Logs unavailable")
            ui_info "MariaDB Logs" "$recent_logs"
            ;;
    esac
}

# ==============================================================================
# MAIN PROGRAM
# ==============================================================================

main() {
    # Show ASCII art splash screen first
    show_ascii_splash
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize
    init_logging
    log "Initializing Ultrabunt Ultimate Buntstaller..."
    
    # Announce initialization if TTS is enabled
    speak_if_enabled "Initializing Ultrabunt Ultimate Buntstaller" "important"
    
    ensure_deps
    log "Dependencies check completed"
    
    log "╔═══════════════════════════════════════════════╗"
    log "║ ULTRABUNT ULTIMATE BUNTSTALLER v4.2.0 STARTED ║"
    log "╚═══════════════════════════════════════════════╝"
    
    # Update buntage cache
    log "Starting APT cache update..."
    speak_if_enabled "Updating package cache, please wait..."
    apt_update
    log "APT cache update completed"
    speak_if_enabled "Package cache updated successfully"
    
    # Build buntage installation cache for fast lookups
    speak_if_enabled "Building package installation cache..."
    build_package_cache
    speak_if_enabled "Package cache built successfully"
    
    # Show main menu
    log "Loading main menu..."
    speak_if_enabled "Loading main menu" "important"
    show_category_menu
    log "Main menu completed"
    
    # Farewell
    log "Ultrabunt Ultimate Buntstaller exiting."
    speak_if_enabled "Thank you for using Ultrabunt Ultimate Buntstaller. Goodbye!" "important"
    ui_msg "Goodbye!" "Thanks for bunting Ultrabunt Ultimate Buntstaller!\n\nLog: $LOGFILE\nBackups: $BACKUP_DIR\n\n💡 Tip: Reboot to apply all changes."
}

# Run main program
main "$@"
exit 0