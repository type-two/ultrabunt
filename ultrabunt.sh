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

# Cache for installed buntages - populated once at startup
declare -A INSTALLED_CACHE

# Session variables for database authentication
MARIADB_SESSION_PASSWORD=""
MARIADB_SESSION_ACTIVE=false

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
    
    # Cache APT buntages
    log "Caching APT buntages..."
    while IFS= read -r pkg; do
        INSTALLED_CACHE["apt:$pkg"]=1
    done < <(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)
    
    # Cache Snap buntages
    if command -v snap &>/dev/null; then
        log "Caching Snap buntages..."
        while IFS= read -r pkg; do
            INSTALLED_CACHE["snap:$pkg"]=1
        done < <(snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort)
    fi
    
    # Cache Flatpak buntages
    if command -v flatpak &>/dev/null; then
        log "Caching Flatpak buntages..."
        while IFS= read -r pkg; do
            INSTALLED_CACHE["flatpak:$pkg"]=1
        done < <(flatpak list --app --columns=application 2>/dev/null | sort)
    fi
    
    local total_cached=${#INSTALLED_CACHE[@]}
    log "Buntage cache built with $total_cached entries"
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
    whiptail --title "$1" --msgbox "$2" 20 80
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
    
    # Check for alternative methods in preferred order: APT → Snap → Flatpak → Custom
    for variant in "${base_name}-deb" "${base_name}-snap" "${base_name}-flatpak"; do
        if [[ -n "${PACKAGES[$variant]:-}" ]]; then
            local desc="${PKG_DESC[$variant]}"
            methods+=("$variant" "$desc")
        fi
    done
    
    # Special cases for apps with different naming patterns
    case "$base_name" in
        "vscode")
            if [[ -n "${PACKAGES[vscode-snap]:-}" ]]; then
                methods+=("vscode-snap" "${PKG_DESC[vscode-snap]}")
            fi
            if [[ -n "${PACKAGES[vscode-flatpak]:-}" ]]; then
                methods+=("vscode-flatpak" "${PKG_DESC[vscode-flatpak]}")
            fi
            ;;
        "discord")
            if [[ -n "${PACKAGES[discord-deb]:-}" ]]; then
                methods+=("discord-deb" "${PKG_DESC[discord-deb]}")
            fi
            if [[ -n "${PACKAGES[discord-flatpak]:-}" ]]; then
                methods+=("discord-flatpak" "${PKG_DESC[discord-flatpak]}")
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
        choice=$(ui_menu "Installation Method" "Multiple installation methods available for $base_name.\nChoose your preferred method:" 20 80 10 "${available_methods[@]}")
        
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
    
    # Use cache for fast lookup
    if [[ -n "${INSTALLED_CACHE["apt:$pkg"]:-}" ]]; then
        return 0
    else
        return 1
    fi
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

PACKAGES[poetry]="poetry"
PKG_DESC[poetry]="Modern Python dependency manager [PIP]"
PKG_METHOD[poetry]="custom"
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
PKG_DESC[mkdocs]="Static site generator for docs (dev favorite) [PIP]"
PKG_METHOD[mkdocs]="custom"
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
PKG_DESC[sqlitestudio]="SQLite database manager [SNAP]"
PKG_METHOD[sqlitestudio]="snap"
PKG_CATEGORY[sqlitestudio]="web"

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
PKG_CATEGORY[htop]="monitoring"

PACKAGES[btop]="btop"
PKG_DESC[btop]="Resource monitor with better graphs [APT]"
PKG_METHOD[btop]="apt"
PKG_CATEGORY[btop]="monitoring"

PACKAGES[glances]="glances"
PKG_DESC[glances]="Cross-platform system monitor [APT]"
PKG_METHOD[glances]="apt"
PKG_CATEGORY[glances]="monitoring"

PACKAGES[nethogs]="nethogs"
PKG_DESC[nethogs]="Network bandwidth monitor per process [APT]"
PKG_METHOD[nethogs]="apt"
PKG_CATEGORY[nethogs]="monitoring"

PACKAGES[iotop]="iotop"
PKG_DESC[iotop]="I/O monitor [APT]"
PKG_METHOD[iotop]="apt"
PKG_CATEGORY[iotop]="monitoring"

# Additional Process Monitors
PACKAGES[bpytop]="bpytop"
PKG_DESC[bpytop]="Python-based resource monitor (btop predecessor) [APT]"
PKG_METHOD[bpytop]="apt"
PKG_CATEGORY[bpytop]="monitoring"

PACKAGES[bashtop]="bashtop"
PKG_DESC[bashtop]="Bash-based resource monitor (original) [APT]"
PKG_METHOD[bashtop]="apt"
PKG_CATEGORY[bashtop]="monitoring"

PACKAGES[bottom]="bottom"
PKG_DESC[bottom]="Cross-platform graphical process monitor (btm) [APT]"
PKG_METHOD[bottom]="apt"
PKG_CATEGORY[bottom]="monitoring"

PACKAGES[gotop]="gotop"
PKG_DESC[gotop]="Terminal-based graphical activity monitor [SNAP]"
PKG_METHOD[gotop]="snap"
PKG_CATEGORY[gotop]="monitoring"

PACKAGES[vtop]="vtop"
PKG_DESC[vtop]="Visually appealing terminal monitor [NPM]"
PKG_METHOD[vtop]="npm"
PKG_CATEGORY[vtop]="monitoring"

PACKAGES[zenith]="zenith"
PKG_DESC[zenith]="Terminal monitor with zoomable charts [CARGO]"
PKG_METHOD[zenith]="cargo"
PKG_CATEGORY[zenith]="monitoring"

PACKAGES[nmon]="nmon"
PKG_DESC[nmon]="Nigel's Monitor - modular system statistics [APT]"
PKG_METHOD[nmon]="apt"
PKG_CATEGORY[nmon]="monitoring"

PACKAGES[atop]="atop"
PKG_DESC[atop]="Advanced system and process monitor [APT]"
PKG_METHOD[atop]="apt"
PKG_CATEGORY[atop]="monitoring"

# I/O, Memory, and Disk Tools
PACKAGES[iostat]="sysstat"
PKG_DESC[iostat]="CPU utilization and disk I/O statistics [APT]"
PKG_METHOD[iostat]="apt"
PKG_CATEGORY[iostat]="monitoring"

PACKAGES[vmstat]="procps"
PKG_DESC[vmstat]="Virtual memory, processes, I/O, and CPU activity [APT]"
PKG_METHOD[vmstat]="apt"
PKG_CATEGORY[vmstat]="monitoring"

PACKAGES[free]="procps"
PKG_DESC[free]="Display free and used memory [APT]"
PKG_METHOD[free]="apt"
PKG_CATEGORY[free]="monitoring"

# Network Monitoring Tools
PACKAGES[iftop]="iftop"
PKG_DESC[iftop]="Real-time bandwidth usage per network interface [APT]"
PKG_METHOD[iftop]="apt"
PKG_CATEGORY[iftop]="monitoring"

PACKAGES[nload]="nload"
PKG_DESC[nload]="Network traffic visualizer with graphical bars [APT]"
PKG_METHOD[nload]="apt"
PKG_CATEGORY[nload]="monitoring"

PACKAGES[bmon]="bmon"
PKG_DESC[bmon]="Interactive bandwidth monitor [APT]"
PKG_METHOD[bmon]="apt"
PKG_CATEGORY[bmon]="monitoring"

PACKAGES[iptraf-ng]="iptraf-ng"
PKG_DESC[iptraf-ng]="Console-based network monitoring utility [APT]"
PKG_METHOD[iptraf-ng]="apt"
PKG_CATEGORY[iptraf-ng]="monitoring"

PACKAGES[ss]="iproute2"
PKG_DESC[ss]="Socket investigation utility (netstat replacement) [APT]"
PKG_METHOD[ss]="apt"
PKG_CATEGORY[ss]="monitoring"

# Process and System Information Tools
PACKAGES[lsof]="lsof"
PKG_DESC[lsof]="List open files and processes [APT]"
PKG_METHOD[lsof]="apt"
PKG_CATEGORY[lsof]="monitoring"

PACKAGES[sar]="sysstat"
PKG_DESC[sar]="System Activity Reporter - historical monitoring [APT]"
PKG_METHOD[sar]="apt"
PKG_CATEGORY[sar]="monitoring"

PACKAGES[mpstat]="sysstat"
PKG_DESC[mpstat]="Individual or combined CPU processor statistics [APT]"
PKG_METHOD[mpstat]="apt"
PKG_CATEGORY[mpstat]="monitoring"

PACKAGES[pidstat]="sysstat"
PKG_DESC[pidstat]="Per-process CPU, memory, and I/O statistics [APT]"
PKG_METHOD[pidstat]="apt"
PKG_CATEGORY[pidstat]="monitoring"

# GPU Monitoring Tools
PACKAGES[nvtop]="nvtop"
PKG_DESC[nvtop]="htop-like utility for monitoring NVIDIA GPUs [APT]"
PKG_METHOD[nvtop]="apt"
PKG_CATEGORY[nvtop]="monitoring"

PACKAGES[radeontop]="radeontop"
PKG_DESC[radeontop]="TUI utility for monitoring AMD GPUs [APT]"
PKG_METHOD[radeontop]="apt"
# System Information Tools
PACKAGES[ps]="procps"
PKG_DESC[ps]="Standard process status command - reports a snapshot of current processes (non-interactive)"
PKG_METHOD[ps]="apt"
PKG_CATEGORY[ps]="monitoring"

PKG_CATEGORY[radeontop]="monitoring"

# Additional GPU Monitoring Tool
PACKAGES[qmasa]="qmasa"
PKG_DESC[qmasa]="Terminal-based tool for displaying general GPU usage stats on Linux [Cargo]"
PKG_METHOD[qmasa]="cargo"
PKG_CATEGORY[qmasa]="monitoring"

# Additional Process Monitoring Tool
PACKAGES[gtop]="gtop"
PKG_DESC[gtop]="System monitoring dashboard for the terminal, written in Node.js [NPM]"
PKG_METHOD[gtop]="npm"
PKG_CATEGORY[gtop]="monitoring"

# Additional System Utilities
PACKAGES[pv]="pv"
PKG_DESC[pv]="Pipe Viewer - monitor progress of data through a pipeline with progress bar [APT]"
PKG_METHOD[pv]="apt"
PKG_CATEGORY[pv]="monitoring"

PACKAGES[tree]="tree"
PKG_DESC[tree]="Display directory structure in tree format [APT]"
PKG_METHOD[tree]="apt"
PKG_CATEGORY[tree]="monitoring"

PACKAGES[ncdu]="ncdu"
PKG_DESC[ncdu]="NCurses Disk Usage - interactive disk usage analyzer [APT]"
PKG_METHOD[ncdu]="apt"
PKG_CATEGORY[ncdu]="monitoring"

PACKAGES[duf]="duf"
PKG_DESC[duf]="Disk Usage/Free Utility - better 'df' alternative with colors [APT]"
PKG_METHOD[duf]="apt"
PKG_CATEGORY[duf]="monitoring"

PACKAGES[dust]="dust"
PKG_DESC[dust]="More intuitive version of du written in Rust [Cargo]"
PKG_METHOD[dust]="cargo"
PKG_CATEGORY[dust]="monitoring"

PACKAGES[fd-find]="fd-find"
PKG_DESC[fd-find]="Simple, fast and user-friendly alternative to 'find' [APT]"
PKG_METHOD[fd-find]="apt"
PKG_CATEGORY[fd-find]="monitoring"

PACKAGES[ripgrep]="ripgrep"
PKG_DESC[ripgrep]="Recursively search directories for regex patterns (rg command) [APT]"
PKG_METHOD[ripgrep]="apt"
PKG_CATEGORY[ripgrep]="monitoring"

PACKAGES[bat]="bat"
PKG_DESC[bat]="Cat clone with syntax highlighting and Git integration [APT]"
PKG_METHOD[bat]="apt"
PKG_CATEGORY[bat]="monitoring"

PACKAGES[exa]="exa"
PKG_DESC[exa]="Modern replacement for 'ls' with colors and Git status [APT]"
PKG_METHOD[exa]="apt"
PKG_CATEGORY[exa]="monitoring"

PACKAGES[bandwhich]="bandwhich"
PKG_DESC[bandwhich]="Terminal bandwidth utilization tool by process [Cargo]"
PKG_METHOD[bandwhich]="cargo"
PKG_CATEGORY[bandwhich]="monitoring"

PACKAGES[procs]="procs"
PKG_DESC[procs]="Modern replacement for ps written in Rust [Cargo]"
PKG_METHOD[procs]="cargo"
PKG_CATEGORY[procs]="monitoring"

PACKAGES[tokei]="tokei"
PKG_DESC[tokei]="Count lines of code quickly [Cargo]"
PKG_METHOD[tokei]="cargo"
PKG_CATEGORY[tokei]="monitoring"

PACKAGES[hyperfine]="hyperfine"
PKG_DESC[hyperfine]="Command-line benchmarking tool [APT]"
PKG_METHOD[hyperfine]="apt"
PKG_CATEGORY[hyperfine]="monitoring"

PACKAGES[fzf]="fzf"
PKG_DESC[fzf]="Command-line fuzzy finder [APT]"
PKG_METHOD[fzf]="apt"
PKG_CATEGORY[fzf]="monitoring"

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

PACKAGES[jq]="jq"
PKG_DESC[jq]="Lightweight and flexible command-line JSON processor [APT]"
PKG_METHOD[jq]="apt"
PKG_CATEGORY[jq]="monitoring"

PACKAGES[yq]="yq"
PKG_DESC[yq]="Command-line YAML processor (jq wrapper for YAML files) [Snap]"
PKG_METHOD[yq]="snap"
PKG_CATEGORY[yq]="monitoring"

PACKAGES[delta]="git-delta"
PKG_DESC[delta]="Syntax-highlighting pager for git and diff output [APT]"
PKG_METHOD[delta]="apt"
PKG_CATEGORY[delta]="monitoring"

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

# SNAP APPS
PACKAGES[spotify]="spotify"
PKG_DESC[spotify]="Music streaming service [SNP]"
PKG_METHOD[spotify]="snap"
PKG_CATEGORY[spotify]="multimedia"

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
PKG_CATEGORY[obs-studio]="multimedia"

PACKAGES[vlc]="vlc"
PKG_DESC[vlc]="VLC media player [APT]"
PKG_METHOD[vlc]="apt"
PKG_CATEGORY[vlc]="multimedia"

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
PKG_DESC[warp-terminal]="Modern terminal with AI features [DEB]"
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
PKG_CATEGORY[steam]="gaming"

PACKAGES[heroic-launcher]="heroic"
PKG_DESC[heroic-launcher]="Open-source Epic Games/GOG launcher [SNP]"
PKG_METHOD[heroic-launcher]="snap"
PKG_CATEGORY[heroic-launcher]="gaming"
PKG_DEPS[heroic-launcher]="snapd"

PACKAGES[lutris]="lutris"
PKG_DESC[lutris]="Gaming on Linux made easy [APT]"
PKG_METHOD[lutris]="apt"
PKG_CATEGORY[lutris]="gaming"

PACKAGES[gamemode]="gamemode"
PKG_DESC[gamemode]="Optimize gaming performance [APT]"
PKG_METHOD[gamemode]="apt"
PKG_CATEGORY[gamemode]="gaming"

PACKAGES[gimp]="gimp"
PKG_DESC[gimp]="GIMP image editor [APT]"
PKG_METHOD[gimp]="apt"
PKG_CATEGORY[gimp]="multimedia"

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
PKG_CATEGORY[audacity]="multimedia"

PACKAGES[blender]="blender"
PKG_DESC[blender]="Blender 3D creation suite [SNP]"
PKG_METHOD[blender]="snap"
PKG_CATEGORY[blender]="multimedia"

PACKAGES[inkscape]="inkscape"
PKG_DESC[inkscape]="Inkscape vector graphics editor [APT]"
PKG_METHOD[inkscape]="apt"
PKG_CATEGORY[inkscape]="multimedia"

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

PACKAGES[lmdeploy]="lmdeploy"
PKG_DESC[lmdeploy]="Lightweight framework to serve LLMs efficiently [PIP]"
PKG_METHOD[lmdeploy]="pip"
PKG_CATEGORY[lmdeploy]="ai"

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

PACKAGES[faster-whisper]="faster-whisper"
PKG_DESC[faster-whisper]="Optimized Python Whisper with CTranslate2 [PIP]"
PKG_METHOD[faster-whisper]="pip"
PKG_CATEGORY[faster-whisper]="ai"

PACKAGES[whisperx]="whisperx"
PKG_DESC[whisperx]="Whisper with speaker diarization support [PIP]"
PKG_METHOD[whisperx]="pip"
PKG_CATEGORY[whisperx]="ai"

PACKAGES[coqui-stt]="coqui-stt"
PKG_DESC[coqui-stt]="Open-source speech-to-text engine [PIP]"
PKG_METHOD[coqui-stt]="pip"
PKG_CATEGORY[coqui-stt]="ai"

PACKAGES[piper-tts]="piper-tts"
PKG_DESC[piper-tts]="Modern local text-to-speech by Rhasspy [PIP]"
PKG_METHOD[piper-tts]="pip"
PKG_CATEGORY[piper-tts]="ai"

PACKAGES[mimic3]="mimic3"
PKG_DESC[mimic3]="Neural voice synthesis by Mycroft AI [PIP]"
PKG_METHOD[mimic3]="pip"
PKG_CATEGORY[mimic3]="ai"

PACKAGES[coqui-tts]="coqui-tts"
PKG_DESC[coqui-tts]="Deep-learning TTS with voice cloning [PIP]"
PKG_METHOD[coqui-tts]="pip"
PKG_CATEGORY[coqui-tts]="ai"

PACKAGES[ffmpeg]="ffmpeg"
PKG_DESC[ffmpeg]="Complete multimedia processing toolkit [APT]"
PKG_METHOD[ffmpeg]="apt"
PKG_CATEGORY[ffmpeg]="multimedia"

PACKAGES[yt-dlp]="yt-dlp"
PKG_DESC[yt-dlp]="Modern YouTube/media downloader (youtube-dl fork) [PIP]"
PKG_METHOD[yt-dlp]="custom"
PKG_CATEGORY[yt-dlp]="multimedia"

PACKAGES[freetube]="freetube"
PKG_DESC[freetube]="Privacy-focused YouTube client [FLATPAK]"
PKG_METHOD[freetube]="flatpak"
PKG_CATEGORY[freetube]="multimedia"

PACKAGES[invidious]="invidious"
PKG_DESC[invidious]="Alternative YouTube frontend [CUSTOM]"
PKG_METHOD[invidious]="custom"
PKG_CATEGORY[invidious]="multimedia"

PACKAGES[mpv]="mpv"
PKG_DESC[mpv]="Minimalist media player [APT]"
PKG_METHOD[mpv]="apt"
PKG_CATEGORY[mpv]="multimedia"

PACKAGES[kodi]="kodi"
PKG_DESC[kodi]="Open-source media center [APT]"
PKG_METHOD[kodi]="apt"
PKG_CATEGORY[kodi]="multimedia"

PACKAGES[stremio]="stremio"
PKG_DESC[stremio]="Modern media center with streaming [FLATPAK]"
PKG_METHOD[stremio]="flatpak"
PKG_CATEGORY[stremio]="multimedia"

# MUSIC PRODUCTION & AUDIO
PACKAGES[ardour]="ardour"
PKG_DESC[ardour]="Professional digital audio workstation [APT]"
PKG_METHOD[ardour]="apt"
PKG_CATEGORY[ardour]="multimedia"

PACKAGES[lmms]="lmms"
PKG_DESC[lmms]="Free pattern-based music production suite [APT]"
PKG_METHOD[lmms]="apt"
PKG_CATEGORY[lmms]="multimedia"

PACKAGES[mixxx]="mixxx"
PKG_DESC[mixxx]="Open-source DJ software [APT]"
PKG_METHOD[mixxx]="apt"
PKG_CATEGORY[mixxx]="multimedia"

# GAMING & EMULATION
PACKAGES[retroarch]="retroarch"
PKG_DESC[retroarch]="Multi-system emulator frontend [APT]"
PKG_METHOD[retroarch]="apt"
PKG_CATEGORY[retroarch]="gaming"

PACKAGES[retroarch-snap]="retroarch"
PKG_DESC[retroarch-snap]="Multi-system emulator frontend [SNAP]"
PKG_METHOD[retroarch-snap]="snap"
PKG_CATEGORY[retroarch-snap]="gaming"

PACKAGES[retroarch-flatpak]="org.libretro.RetroArch"
PKG_DESC[retroarch-flatpak]="Multi-system emulator frontend [FLATPAK]"
PKG_METHOD[retroarch-flatpak]="flatpak"
PKG_CATEGORY[retroarch-flatpak]="gaming"

PACKAGES[mame]="mame"
PKG_DESC[mame]="Multiple Arcade Machine Emulator [APT]"
PKG_METHOD[mame]="apt"
PKG_CATEGORY[mame]="gaming"

PACKAGES[mame-flatpak]="net.mame.MAME"
PKG_DESC[mame-flatpak]="Multiple Arcade Machine Emulator [FLATPAK]"
PKG_METHOD[mame-flatpak]="flatpak"
PKG_CATEGORY[mame-flatpak]="gaming"

PACKAGES[dolphin-emu]="dolphin-emu"
PKG_DESC[dolphin-emu]="GameCube and Wii emulator [APT]"
PKG_METHOD[dolphin-emu]="apt"
PKG_CATEGORY[dolphin-emu]="gaming"

PACKAGES[dolphin-emu-flatpak]="org.DolphinEmu.dolphin-emu"
PKG_DESC[dolphin-emu-flatpak]="GameCube and Wii emulator [FLATPAK]"
PKG_METHOD[dolphin-emu-flatpak]="flatpak"
PKG_CATEGORY[dolphin-emu-flatpak]="gaming"

PACKAGES[pcsx2]="pcsx2"
PKG_DESC[pcsx2]="PlayStation 2 emulator [APT]"
PKG_METHOD[pcsx2]="apt"
PKG_CATEGORY[pcsx2]="gaming"

PACKAGES[pcsx2-flatpak]="net.pcsx2.PCSX2"
PKG_DESC[pcsx2-flatpak]="PlayStation 2 emulator [FLATPAK]"
PKG_METHOD[pcsx2-flatpak]="flatpak"
PKG_CATEGORY[pcsx2-flatpak]="gaming"

PACKAGES[rpcs3-flatpak]="net.rpcs3.RPCS3"
PKG_DESC[rpcs3-flatpak]="PlayStation 3 emulator [FLATPAK]"
PKG_METHOD[rpcs3-flatpak]="flatpak"
PKG_CATEGORY[rpcs3-flatpak]="gaming"

PACKAGES[yuzu-flatpak]="org.yuzu_emu.yuzu"
PKG_DESC[yuzu-flatpak]="Nintendo Switch emulator [FLATPAK]"
PKG_METHOD[yuzu-flatpak]="flatpak"
PKG_CATEGORY[yuzu-flatpak]="gaming"

PACKAGES[cemu-flatpak]="info.cemu.Cemu"
PKG_DESC[cemu-flatpak]="Wii U emulator [FLATPAK]"
PKG_METHOD[cemu-flatpak]="flatpak"
PKG_CATEGORY[cemu-flatpak]="gaming"

PACKAGES[mednafen]="mednafen"
PKG_DESC[mednafen]="Multi-system accurate emulator [APT]"
PKG_METHOD[mednafen]="apt"
PKG_CATEGORY[mednafen]="gaming"

PACKAGES[duckstation-flatpak]="org.duckstation.DuckStation"
PKG_DESC[duckstation-flatpak]="PlayStation 1 emulator [FLATPAK]"
PKG_METHOD[duckstation-flatpak]="flatpak"
PKG_CATEGORY[duckstation-flatpak]="gaming"

PACKAGES[bsnes]="bsnes"
PKG_DESC[bsnes]="Super Nintendo emulator [APT]"
PKG_METHOD[bsnes]="apt"
PKG_CATEGORY[bsnes]="gaming"

PACKAGES[mgba]="mgba-qt"
PKG_DESC[mgba]="Game Boy Advance emulator [APT]"
PKG_METHOD[mgba]="apt"
PKG_CATEGORY[mgba]="gaming"

PACKAGES[mgba-snap]="mgba"
PKG_DESC[mgba-snap]="Game Boy Advance emulator [SNAP]"
PKG_METHOD[mgba-snap]="snap"
PKG_CATEGORY[mgba-snap]="gaming"

PACKAGES[mgba-flatpak]="io.mgba.mGBA"
PKG_DESC[mgba-flatpak]="Game Boy Advance emulator [FLATPAK]"
PKG_METHOD[mgba-flatpak]="flatpak"
PKG_CATEGORY[mgba-flatpak]="gaming"

PACKAGES[desmume]="desmume"
PKG_DESC[desmume]="Nintendo DS emulator [APT]"
PKG_METHOD[desmume]="apt"
PKG_CATEGORY[desmume]="gaming"

PACKAGES[desmume-flatpak]="org.desmume.DeSmuME"
PKG_DESC[desmume-flatpak]="Nintendo DS emulator [FLATPAK]"
PKG_METHOD[desmume-flatpak]="flatpak"
PKG_CATEGORY[desmume-flatpak]="gaming"

PACKAGES[citra]="citra"
PKG_DESC[citra]="Nintendo 3DS emulator [APT]"
PKG_METHOD[citra]="apt"
PKG_CATEGORY[citra]="gaming"

PACKAGES[citra-flatpak]="org.citra_emu.citra"
PKG_DESC[citra-flatpak]="Nintendo 3DS emulator [FLATPAK]"
PKG_METHOD[citra-flatpak]="flatpak"
PKG_CATEGORY[citra-flatpak]="gaming"

PACKAGES[dosbox]="dosbox"
PKG_DESC[dosbox]="DOS emulator [APT]"
PKG_METHOD[dosbox]="apt"
PKG_CATEGORY[dosbox]="gaming"

PACKAGES[dosbox-snap]="dosbox"
PKG_DESC[dosbox-snap]="DOS emulator [SNAP]"
PKG_METHOD[dosbox-snap]="snap"
PKG_CATEGORY[dosbox-snap]="gaming"

PACKAGES[dosbox-flatpak]="com.dosbox.DOSBox"
PKG_DESC[dosbox-flatpak]="DOS emulator [FLATPAK]"
PKG_METHOD[dosbox-flatpak]="flatpak"
PKG_CATEGORY[dosbox-flatpak]="gaming"

PACKAGES[mupen64plus]="mupen64plus-qt"
PKG_DESC[mupen64plus]="Nintendo 64 emulator [APT]"
PKG_METHOD[mupen64plus]="apt"
PKG_CATEGORY[mupen64plus]="gaming"

PACKAGES[scummvm]="scummvm"
PKG_DESC[scummvm]="Adventure game engine [APT]"
PKG_METHOD[scummvm]="apt"
PKG_CATEGORY[scummvm]="gaming"

PACKAGES[scummvm-snap]="scummvm"
PKG_DESC[scummvm-snap]="Adventure game engine [SNAP]"
PKG_METHOD[scummvm-snap]="snap"
PKG_CATEGORY[scummvm-snap]="gaming"

PACKAGES[scummvm-flatpak]="org.scummvm.ScummVM"
PKG_DESC[scummvm-flatpak]="Adventure game engine [FLATPAK]"
PKG_METHOD[scummvm-flatpak]="flatpak"
PKG_CATEGORY[scummvm-flatpak]="gaming"

PACKAGES[qemu]="qemu-system"
PKG_DESC[qemu]="System hardware emulator [APT]"
PKG_METHOD[qemu]="apt"
PKG_CATEGORY[qemu]="gaming"

PACKAGES[wine]="wine"
PKG_DESC[wine]="Windows API compatibility layer [APT]"
PKG_METHOD[wine]="apt"
PKG_CATEGORY[wine]="gaming"

PACKAGES[wine-snap]="wine-platform-runtime"
PKG_DESC[wine-snap]="Windows API compatibility layer [SNAP]"
PKG_METHOD[wine-snap]="snap"
PKG_CATEGORY[wine-snap]="gaming"

PACKAGES[wine-flatpak]="org.winehq.Wine"
PKG_DESC[wine-flatpak]="Windows API compatibility layer [FLATPAK]"
PKG_METHOD[wine-flatpak]="flatpak"
PKG_CATEGORY[wine-flatpak]="gaming"

PACKAGES[stella]="stella"
PKG_DESC[stella]="Atari 2600 emulator [APT]"
PKG_METHOD[stella]="apt"
PKG_CATEGORY[stella]="gaming"

PACKAGES[dosbox-staging]="dosbox-staging"
PKG_DESC[dosbox-staging]="DOS emulator for retro PC games [APT]"
PKG_METHOD[dosbox-staging]="apt"
PKG_CATEGORY[dosbox-staging]="gaming"

PACKAGES[n8n]="n8n"
PKG_DESC[n8n]="Workflow automation tool (self-hosted Zapier alternative) [NPM]"
PKG_METHOD[n8n]="custom"
PKG_CATEGORY[n8n]="development"

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
PKG_CATEGORY[vlc-snap]="multimedia"

PACKAGES[vlc-flatpak]="org.videolan.VLC"
PKG_DESC[vlc-flatpak]="VLC media player [FLT] - Alternative to APT version"
PKG_METHOD[vlc-flatpak]="flatpak"
PKG_CATEGORY[vlc-flatpak]="multimedia"
PKG_DEPS[vlc-flatpak]="flatpak"

# GIMP alternatives
PACKAGES[gimp-snap]="gimp"
PKG_DESC[gimp-snap]="GIMP image editor [SNP] - Alternative to APT version"
PKG_METHOD[gimp-snap]="snap"
PKG_CATEGORY[gimp-snap]="multimedia"

PACKAGES[gimp-flatpak]="org.gimp.GIMP"
PKG_DESC[gimp-flatpak]="GIMP image editor [FLT] - Alternative to APT version"
PKG_METHOD[gimp-flatpak]="flatpak"
PKG_CATEGORY[gimp-flatpak]="multimedia"
PKG_DEPS[gimp-flatpak]="flatpak"

# OBS Studio alternatives
PACKAGES[obs-studio-flatpak]="com.obsproject.Studio"
PKG_DESC[obs-studio-flatpak]="OBS Studio streaming/recording [FLT] - Alternative to APT version"
PKG_METHOD[obs-studio-flatpak]="flatpak"
PKG_CATEGORY[obs-studio-flatpak]="multimedia"
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
PKG_CATEGORY[audacity-snap]="multimedia"

PACKAGES[audacity-flatpak]="org.audacityteam.Audacity"
PKG_DESC[audacity-flatpak]="Audacity audio editor [FLT] - Alternative to APT version"
PKG_METHOD[audacity-flatpak]="flatpak"
PKG_CATEGORY[audacity-flatpak]="multimedia"
PKG_DEPS[audacity-flatpak]="flatpak"

# Inkscape alternatives
PACKAGES[inkscape-snap]="inkscape"
PKG_DESC[inkscape-snap]="Inkscape vector graphics [SNP] - Alternative to APT version"
PKG_METHOD[inkscape-snap]="snap"
PKG_CATEGORY[inkscape-snap]="multimedia"

PACKAGES[inkscape-flatpak]="org.inkscape.Inkscape"
PKG_DESC[inkscape-flatpak]="Inkscape vector graphics [FLT] - Alternative to APT version"
PKG_METHOD[inkscape-flatpak]="flatpak"
PKG_CATEGORY[inkscape-flatpak]="multimedia"
PKG_DEPS[inkscape-flatpak]="flatpak"

# Drawing and Creative Tools
PACKAGES[webcamize]="webcamize"
PKG_DESC[webcamize]="Webcam effects and virtual camera tool [APT]"
PKG_METHOD[webcamize]="apt"
PKG_CATEGORY[webcamize]="multimedia"

PACKAGES[durdraw]="durdraw"
PKG_DESC[durdraw]="ASCII art drawing and animation tool [PIP]"
PKG_METHOD[durdraw]="pip"
PKG_CATEGORY[durdraw]="multimedia"

PACKAGES[pastel]="pastel"
PKG_DESC[pastel]="Command-line tool for color manipulation and palette generation [APT]"
PKG_METHOD[pastel]="apt"
PKG_CATEGORY[pastel]="multimedia"

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
    "monitoring:System Monitoring"
    "database:Database Management"
    "security:Security Tools"
    "system:System Tools"
    "office:Office & Productivity"
    "communication:Communication"
    "multimedia:Multimedia & Graphics"
    "cloud:Cloud & Sync"
    "terminals:Terminals"
    "gaming:Gaming"
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
    
    # Packages that require classic confinement
    case "$pkg" in
        ghostty)
            log "Installing $pkg with classic confinement..."
            timeout 300 sudo snap install "$pkg" --classic 2>&1 | tee -a "$LOGFILE"
            local exit_code=${PIPESTATUS[0]}
            ;;
        *)
            log "Installing $pkg..."
            timeout 300 sudo snap install "$pkg" 2>&1 | tee -a "$LOGFILE"
            local exit_code=${PIPESTATUS[0]}
            ;;
    esac
    
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
    log "Installing $pkg via pip..."
    
    # Ensure Python3 and pip are installed
    if ! command -v pip3 >/dev/null 2>&1; then
        ui_msg "Python3 Required" "Installing Python3 and pip first...\n\n⏳ This process is automatic - please wait..."
        apt_update
        install_apt_package "python3-pip"
        if [[ $? -ne 0 ]]; then
            log_error "Failed to install Python3/pip prerequisite"
            return 1
        fi
    fi
    
    pip3 install --user "$pkg" 2>&1 | tee -a "$LOGFILE"
}

remove_pip_package() {
    local pkg="$1"
    log "Removing $pkg via pip..."
    pip3 uninstall -y "$pkg" 2>/dev/null || true
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
    
    curl -fsSL https://deb.nodesource.com/setup_${NODE_LTS}.x | sudo -E bash -
    apt_update
    install_apt_package "nodejs"
    
    ui_msg "Node.js Installed" "Node.js ${NODE_LTS} and npm installed successfully."
}

remove_nodejs() {
    remove_apt_package "nodejs"
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
}

install_vscode() {
    log "Installing VS Code from Microsoft repository..."
    
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
}

install_brave() {
    log "Installing Brave browser..."
    
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
}

install_sublime() {
    log "Installing Sublime Text..."
    
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
}

install_warp() {
    log "Installing Warp terminal..."
    
    # Add Warp's official GPG key and repository
    sudo mkdir -p /usr/share/keyrings
    if ! wget -qO- https://releases.warp.dev/linux/keys/warp.asc | sudo gpg --dearmor -o /usr/share/keyrings/warp-archive-keyring.gpg; then
        log_error "Failed to add Warp GPG key"
        return 1
    fi
    
    # Add Warp repository
    echo "deb [signed-by=/usr/share/keyrings/warp-archive-keyring.gpg] https://releases.warp.dev/linux/deb stable main" | sudo tee /etc/apt/sources.list.d/warp-terminal.list > /dev/null
    
    # Update package list and install
    sudo apt-get update -qq
    if install_apt_package "warp-terminal"; then
        ui_msg "Warp Installed" "Warp terminal installed successfully."
    else
        log_error "Failed to install Warp terminal from repository"
        return 1
    fi
}

remove_warp() {
    remove_apt_package "warp-terminal"
    sudo rm -f /etc/apt/sources.list.d/warp-terminal.list
    sudo rm -f /usr/share/keyrings/warp-archive-keyring.gpg
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
    log "Installing yt-dlp..."
    
    # Install via pip for latest version
    if command -v pip3 >/dev/null 2>&1; then
        if pip3 install --user yt-dlp; then
            ui_msg "yt-dlp Installed" "yt-dlp YouTube downloader installed successfully."
        else
            log_error "Failed to install yt-dlp via pip"
            return 1
        fi
    else
        log_error "pip3 not found. Please install Python3 and pip first."
        return 1
    fi
}

remove_yt-dlp() {
    log "Removing yt-dlp..."
    pip3 uninstall -y yt-dlp 2>/dev/null || true
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
    
    # Pre-configure phpMyAdmin with the MySQL root password
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | sudo debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password " | sudo debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password $mysql_root_pass" | sudo debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password " | sudo debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect " | sudo debconf-set-selections
    
    # Install phpMyAdmin non-interactively
    apt_update
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin php-mbstring php-zip php-gd php-json php-curl 2>&1 | tee -a "$LOGFILE"; then
        
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
        log_error "Failed to install phpMyAdmin"
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
    
    # Download and install ngrok
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update
    install_apt_package "ngrok"
    
    ui_msg "ngrok Installed" "ngrok installed successfully. Run 'ngrok config add-authtoken <token>' to authenticate."
}

remove_ngrok() {
    remove_apt_package "ngrok"
    sudo rm -f /etc/apt/sources.list.d/ngrok.list
    sudo rm -f /etc/apt/trusted.gpg.d/ngrok.asc
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
    log "Installing Poetry Python dependency manager..."
    
    # Install via pip3
    if pip3 install --user poetry; then
        # Add to PATH if not already there
        if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
        fi
        ui_msg "Poetry Installed" "Poetry Python dependency manager installed successfully via pip3."
        return 0
    else
        log_error "Failed to install Poetry"
        return 1
    fi
}

remove_poetry() {
    log "Removing Poetry..."
    pip3 uninstall -y poetry 2>/dev/null || true
    log "Poetry removed successfully"
    return 0
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
    log "Installing MkDocs static site generator..."
    
    # Install via pip3
    if pip3 install --user mkdocs mkdocs-material; then
        ui_msg "MkDocs Installed" "MkDocs static site generator installed successfully via pip3."
        return 0
    else
        log_error "Failed to install MkDocs"
        return 1
    fi
}

remove_mkdocs() {
    log "Removing MkDocs..."
    pip3 uninstall -y mkdocs mkdocs-material 2>/dev/null || true
    log "MkDocs removed successfully"
    return 0
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
            install_snap_package "$pkg"
            install_result=$?
            ;;
        npm)
            install_npm_package "$pkg"
            install_result=$?
            ;;
        pip)
            install_pip_package "$pkg"
            install_result=$?
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
    
    # Start background cache refresh on first load
    refresh_cache_silent
    
    while true; do
        log "Building category menu items..."
        local menu_items=()
        
        log "Processing categories array with ${#CATEGORIES[@]} entries"
        for entry in "${CATEGORIES[@]}"; do
            local cat_id="${entry%%:*}"
            local cat_name="${entry#*:}"
            
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
                    
                    # Re-enable installation check with silent mode
                    if is_package_installed "$name" "true"; then
                        installed=$((installed + 1))
                    fi
                fi
            done
            
            # Add refresh indicator if cache is still updating
            local refresh_indicator=""
            if ! is_cache_refresh_complete; then
                refresh_indicator=" 🔄"
            fi
            
            menu_items+=("$cat_id" "(.Y.) $cat_name [$installed/$total installed]$refresh_indicator")
        done
        
        log "Adding additional menu items..."
        menu_items+=("" "(_*_)")
        menu_items+=("wordpress-setup" "(.Y.) WordPress Management")
        menu_items+=("php-settings" "(.Y.) PHP Configuration")
        menu_items+=("system-info" "(.Y.) System Information")
        menu_items+=("keyboard-layout" "(.Y.) Keyboard Layout Configuration")
        menu_items+=("database-management" "(.Y.) Database Management")
        menu_items+=("log-viewer" "(.Y.) Log Viewer")
        menu_items+=("bulk-ops" "(.Y.) Bulk Operations")
        menu_items+=("quit" "(Q) Exit Installer")
        
        log "Calling ui_menu with ${#menu_items[@]} menu items"
        log "Menu items array contents: ${menu_items[*]}"
        
        # Add error handling for ui_menu call
        local choice=""
        set +e  # Temporarily disable exit on error
        choice=$(ui_menu "Ultrabunt Ultimate Buntstaller" \
            "Select a buntegory to manage buntages:" \
            24 80 14 "${menu_items[@]}")
        local ui_result=$?
        set -e  # Re-enable exit on error
        
        if [[ $ui_result -ne 0 ]]; then
            log "User cancelled or error occurred"
            break
        fi
        
        case "$choice" in
            quit|back|q) 
                # Add confirmation for quit
                if [[ "$choice" == "quit" || "$choice" == "q" ]]; then
                    if ui_yesno "Confirm Exit" "Are you sure you want to exit the Ultrabunt installer?"; then
                        break
                    else
                        continue
                    fi
                else
                    break
                fi
                ;;
            system-info) 
                show_system_info || {
                    log "ERROR: show_system_info failed"
                    ui_msg "Error" "Failed to display system information. Please check the logs."
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
                show_buntage_list "$choice" 
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
        menu_items+=("zback" "(Z) ← Back to Categories")
        
        local choice
        choice=$(ui_menu "$cat_name" \
            "Select a buntage to manage:" \
            24 80 14 "${menu_items[@]}") || break
        
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
        
        local menu_items=()
        
        if is_package_installed "$name"; then
            menu_items+=("reinstall" "(.Y.) Reinstall Buntage")
            menu_items+=("remove" "(.Y.) Remove Buntage")
            menu_items+=("info" "(.Y.) Show Detailed Info")
        else
            menu_items+=("install" "(.Y.) Install Buntage")
            menu_items+=("info" "(.Y.) Show Detailed Info")
        fi
        
        menu_items+=("zback" "(Z) ← Back to Buntage List")
        
        local choice
        choice=$(ui_menu "Manage: $name" "$info" 20 80 10 "${menu_items[@]}")
        
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

show_system_info() {
    log "Starting show_system_info function"
    
    local info="SYSTEM INFORMATION\n"
    info+="═══════════════════════════════════════\n\n"
    
    # OS Info
    if [[ -f /etc/os-release ]]; then
        local os_name="Unknown"
        local os_version="N/A"
        
        # Safely parse os-release
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
    info+="Kernel: $kernel_version\n\n"
    
    # Hardware Info
    info+="HARDWARE INFORMATION\n"
    info+="─────────────────────────────────────\n"
    
    # CPU Info
    local cpu_info
    if [[ -f /proc/cpuinfo ]]; then
        cpu_info=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null) || cpu_info="Unknown"
        local cpu_cores
        cpu_cores=$(nproc 2>/dev/null) || cpu_cores="Unknown"
        info+="CPU: $cpu_info ($cpu_cores cores)\n"
    else
        info+="CPU: Information not available\n"
    fi
    
    # Memory Info
    if [[ -f /proc/meminfo ]]; then
        local mem_total mem_available
        mem_total=$(grep "MemTotal:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}' 2>/dev/null) || mem_total="Unknown"
        mem_available=$(grep "MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}' 2>/dev/null) || mem_available="Unknown"
        if [[ "$mem_total" != "Unknown" && "$mem_available" != "Unknown" ]]; then
            local mem_used=$((mem_total - mem_available))
            info+="Memory: ${mem_used}MB used / ${mem_total}MB total\n"
        else
            info+="Memory: Information not available\n"
        fi
    else
        info+="Memory: Information not available\n"
    fi
    
    # Storage Information
    info+="STORAGE INFORMATION\n"
    info+="─────────────────────────────────────\n"
    
    # Root filesystem
    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1 2>/dev/null | awk '{print $3 " used / " $2 " total (" $5 " full)"}' 2>/dev/null) || disk_info="Information not available"
    info+="Root (/): $disk_info\n"
    
    # All mounted filesystems (excluding special filesystems)
    local mount_info
    mount_info=$(df -h 2>/dev/null | grep -E '^/dev/' | grep -v -E '(tmpfs|udev|overlay)' | awk '{print $6 ": " $3 " used / " $2 " total (" $5 " full)"}' 2>/dev/null | tail -n +2 2>/dev/null)
    if [[ -n "$mount_info" ]]; then
        while IFS= read -r line; do
            [[ "$line" != *"/ :"* ]] && info+="$line\n"
        done <<< "$mount_info"
    fi
    
    # Swap information
    local swap_info
    swap_info=$(free -h 2>/dev/null | grep "Swap:" 2>/dev/null | awk '{print $3 " used / " $2 " total"}' 2>/dev/null) || swap_info="Not available"
    info+="Swap: $swap_info\n"
    
    # Disk usage summary
    local total_disk_count
    total_disk_count=$(lsblk -d 2>/dev/null | grep -c "disk" 2>/dev/null) || total_disk_count="Unknown"
    info+="Physical disks: $total_disk_count detected\n\n"
    
    # System Uptime and Load
    local uptime_info load_avg
    uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' 2>/dev/null) || uptime_info="Unknown"
    load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' 2>/dev/null | sed 's/^ *//' 2>/dev/null) || load_avg="Unknown"
    
    info+="Uptime: $uptime_info\n"
    info+="Load average:$load_avg\n"
    
    # Process count
    local process_count
    process_count=$(ps aux 2>/dev/null | wc -l 2>/dev/null) || process_count="Unknown"
    [[ "$process_count" != "Unknown" ]] && process_count=$((process_count - 1))  # Subtract header line
    info+="Running processes: $process_count\n\n"
    
    # Buntage Managers
    info+="BUNTAGE MANAGERS\n"
    info+="─────────────────────────────────────\n"
    
    # APT detailed info
    local apt_count apt_upgradable apt_auto_removable
    apt_count=$(dpkg -l 2>/dev/null | grep -c "^ii" 2>/dev/null) || apt_count="0"
    apt_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" 2>/dev/null) || apt_upgradable="0"
    apt_auto_removable=$(apt autoremove --dry-run 2>/dev/null | grep -c "^Remv" 2>/dev/null) || apt_auto_removable="0"
    
    info+="APT: $apt_count installed"
    [[ "$apt_upgradable" != "0" ]] && info+=" ($apt_upgradable upgradable)"
    [[ "$apt_auto_removable" != "0" ]] && info+=" ($apt_auto_removable auto-removable)"
    info+="\n"
    
    # Snap detailed info
    if command -v snap &>/dev/null; then
        local snap_count snap_refreshable
        snap_count=$(snap list 2>/dev/null | tail -n +2 2>/dev/null | wc -l 2>/dev/null) || snap_count="0"
        snap_refreshable=$(snap refresh --list 2>/dev/null | tail -n +2 2>/dev/null | wc -l 2>/dev/null) || snap_refreshable="0"
        
        info+="Snap: $snap_count installed"
        [[ "$snap_refreshable" != "0" ]] && info+=" ($snap_refreshable refreshable)"
        info+="\n"
    else
        info+="Snap: Not available\n"
    fi
    
    # Flatpak detailed info
    if command -v flatpak &>/dev/null; then
        local flat_count flat_updates flat_remotes
        flat_count=$(flatpak list --app 2>/dev/null | wc -l 2>/dev/null) || flat_count="0"
        flat_updates=$(flatpak remote-ls --updates 2>/dev/null | wc -l 2>/dev/null) || flat_updates="0"
        flat_remotes=$(flatpak remotes 2>/dev/null | tail -n +2 2>/dev/null | wc -l 2>/dev/null) || flat_remotes="0"
        
        info+="Flatpak: $flat_count apps"
        [[ "$flat_updates" != "0" ]] && info+=" ($flat_updates updates)"
        info+=" [$flat_remotes remotes]\n"
    else
        info+="Flatpak: Not available\n"
    fi
    
    # Additional buntage managers
    if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
        local pip_count
        pip_count=$(pip3 list 2>/dev/null | tail -n +3 2>/dev/null | wc -l 2>/dev/null) || pip_count="0"
        [[ "$pip_count" == "0" ]] && pip_count=$(pip list 2>/dev/null | tail -n +3 2>/dev/null | wc -l 2>/dev/null) || pip_count="0"
        info+="Python (pip): $pip_count packages\n"
    fi
    
    if command -v npm &>/dev/null; then
        local npm_global_count
        npm_global_count=$(npm list -g --depth=0 2>/dev/null | grep -c "├──\|└──" 2>/dev/null) || npm_global_count="0"
        info+="Node.js (npm global): $npm_global_count packages\n"
    fi
    
    info+="\n"
    
    # Network Information
    info+="NETWORK INFORMATION\n"
    info+="─────────────────────────────────────\n"
    
    # Active network interfaces
    local active_interfaces
    active_interfaces=$(ip -o link show 2>/dev/null | awk -F': ' '$3 !~ /lo|docker|br-/ && $3 ~ /UP/ {print $2}' 2>/dev/null | tr '\n' ' ' 2>/dev/null) || active_interfaces="Unknown"
    [[ -n "$active_interfaces" ]] && info+="Active interfaces: $active_interfaces\n" || info+="Active interfaces: None detected\n"
    
    # IP addresses
    local primary_ip
    primary_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' 2>/dev/null) || primary_ip="Unknown"
    info+="Primary IP: $primary_ip\n"
    
    # Internet connectivity check
    local internet_status
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        internet_status="Connected"
    else
        internet_status="Disconnected"
    fi
    info+="Internet: $internet_status\n"
    
    # DNS servers
    local dns_servers
    dns_servers=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' 2>/dev/null | tr '\n' ' ' 2>/dev/null) || dns_servers="Unknown"
    [[ -n "$dns_servers" ]] && info+="DNS servers: $dns_servers\n" || info+="DNS servers: Not configured\n"
    
    info+="\n"
    
    # Ultrabunt Stats
    info+="ULTRABUNT STATISTICS\n"
    info+="─────────────────────────────────────\n"
    
    local total_pkgs=${#PACKAGES[@]}
    local installed_count=0
    
    # Safely count installed packages
    for name in "${!PACKAGES[@]}"; do
        if is_package_installed "$name" 2>/dev/null; then
            ((installed_count++)) 2>/dev/null || true
        fi
    done 2>/dev/null || true
    
    info+="Tracked packages: $total_pkgs\n"
    info+="Installed: $installed_count\n"
    info+="Available: $((total_pkgs - installed_count))\n\n"
    
    info+="Log file: $LOGFILE\n"
    info+="Backup dir: $BACKUP_DIR\n"
    
    log "Calling ui_info with system information"
    ui_info "System Information" "$info" || {
        log "ERROR: ui_info failed in show_system_info"
        return 1
    }
    
    log "show_system_info completed successfully"
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
            "ssl-setup" "(.Y.) 🔒 Add SSL Certificate (Let's Encrypt)"
            "wp-security" "(.Y.) 🛡️  WordPress Security Hardening"
            "" "(_*_)"
            "zback" "(Z) ← Back to Main Menu"
        )
        
        local choice
        choice=$(ui_menu "WordPress Management" \
            "Manage your WordPress installations:\n\n📊 Manage Sites: View, configure, and troubleshoot existing WordPress sites\n🚀 Quick Setup: Auto-generated database credentials\n⚙️  Custom Setup: Choose site directory\n🔧 Custom Database: Choose database name, user, and password" \
            22 90 14 "${menu_items[@]}") || break
        
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
            ssl-setup)
                wordpress_ssl_setup
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
    ui_msg "Step 2/6" "Configuring domain settings...\n\nPlease enter your domain name or use 'localhost' for local development.\n\n👆 User input required below..."
    local domain
    while true; do
        domain=$(ui_input "Domain Name" "Enter your domain name (or 'localhost' for local development):" "localhost") || return
        domain=${domain:-localhost}
        
        # Validate domain format
        if [[ "$domain" == "localhost" ]] || [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            break
        else
            ui_msg "Invalid Domain" "Please enter a valid domain name or 'localhost'.\n\nExamples:\n• localhost\n• mysite.local\n• example.com\n• subdomain.example.com"
        fi
    done
    
    ui_msg "Step 2 Complete" "✅ Domain configured: $domain\n\n• Site URL: http://$domain\n• Directory: /var/www/$domain\n• Admin URL: http://$domain/wp-admin/"
    
    # Confirm installation details
    local confirm_msg="WordPress Installation Summary\n\n"
    confirm_msg+="Web Server: $web_server\n"
    confirm_msg+="Domain: $domain\n"
    confirm_msg+="Site Directory: /var/www/$domain\n"
    confirm_msg+="Database: Auto-generated secure credentials\n\n"
    confirm_msg+="Proceed with installation?"
    
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
    
    ui_msg "Step 5 Complete" "✅ $web_server configured successfully!\n\n• Server block: Created\n• PHP processing: Enabled\n• Security headers: Set\n• Site: Active and running"
    
    # Show completion message
    ui_msg "Step 6/6" "Finalizing WordPress installation...\n\nPreparing completion summary with all details.\n\n⏳ This process is automatic - please wait..."
    show_wordpress_completion "$domain" "$db_info"
    
    ui_msg "Installation Complete!" "🎉 WordPress installation finished successfully!\n\nYour site is ready at: http://$domain\n\nNext steps:\n1. Visit your site to complete WordPress setup\n2. Create your admin account\n3. Choose your theme and plugins\n\nAll details have been saved and displayed in the completion screen."
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
    
    local nginx_conf="/etc/nginx/sites-available/$domain"
    sudo tee "$nginx_conf" > /dev/null <<EOF
server {
    listen 80;
    server_name $domain www.$domain;
    root $site_dir;
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
    sudo ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/"
    
    # Verify the symlink was created correctly
    if [[ ! -L "/etc/nginx/sites-enabled/$domain" ]]; then
        log "ERROR: Failed to create symlink for $domain"
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
                ui_msg "Site Configured" "✅ Nginx site '$domain' has been configured successfully!\n\n📁 Config file: /etc/nginx/sites-available/$domain\n🔗 Enabled at: /etc/nginx/sites-enabled/$domain\n🌐 Access at: http://$domain\n\n🔄 Nginx has been reloaded and is running."
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
        sudo rm -f "/etc/nginx/sites-enabled/$domain"
        return 1
    fi
}

configure_nginx_wordpress_custom() {
    local domain="$1"
    local site_dir="$2"
    
    configure_nginx_wordpress "$domain"
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
    
    # Get domain name
    local domain
    domain=$(ui_input "Domain Name" "Enter domain for SSL certificate:" "") || return
    
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
        choice=$(ui_menu "WordPress" "$status_info" 25 90 15 "${menu_items[@]}") || break
        
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
        choice=$(ui_menu "WordPress Site Management" "$status_info" 20 80 10 "${menu_items[@]}") || break
        
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
            "enable-site" "🔗 Enable/Disable Site"
            "test-site" "🧪 Test Site Accessibility"
            "" "(_*_)"
            "delete-site" "🗑️  Delete This Site (DANGER)"
            "" "(_*_)"
            "zback" "(Z) ← Back to Site List"
        )
        
        local choice
        choice=$(ui_menu "Site Management: $site" "$status_info" 35 120 15 "${menu_items[@]}") || break
        
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
        http_result=$(curl -s -o /dev/null -w "HTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes" "http://$site" --connect-timeout 10 --max-time 30 2>&1)
        test_info+="$http_result\n\n"
        
        # HTTPS test if SSL is configured
        if [[ -f "/etc/letsencrypt/live/$site/fullchain.pem" ]]; then
            test_info+="HTTPS Test:\n"
            local https_result
            https_result=$(curl -s -o /dev/null -w "HTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes" "https://$site" --connect-timeout 10 --max-time 30 2>&1)
            test_info+="$https_result\n\n"
        fi
    else
        test_info+="curl not available for testing\n"
    fi
    
    # DNS resolution test
    if command -v nslookup >/dev/null 2>&1; then
        test_info+="DNS Resolution:\n"
        local dns_result
        dns_result=$(nslookup "$site" 2>&1 | head -10)
        test_info+="$dns_result\n"
    fi
    
    ui_info "Site Test Results" "$test_info"
}

delete_wordpress_site() {
    local site="$1"
    local site_dir="/var/www/$site"
    
    local warning_info="⚠️  WARNING: DELETE WORDPRESS SITE ⚠️\n\n"
    warning_info+="You are about to permanently delete:\n"
    warning_info+="• Site: $site\n"
    warning_info+="• Directory: $site_dir\n"
    warning_info+="• Web server configuration\n"
    warning_info+="• SSL certificates (if any)\n\n"
    warning_info+="This action CANNOT be undone!\n\n"
    warning_info+="Type 'DELETE $site' to confirm:"
    
    local confirmation
    confirmation=$(ui_input "Confirm Site Deletion" "$warning_info")
    
    if [[ "$confirmation" == "DELETE $site" ]]; then
        # Remove web server configuration
        if [[ -f "/etc/nginx/sites-available/$site" ]]; then
            sudo rm -f "/etc/nginx/sites-available/$site"
            sudo rm -f "/etc/nginx/sites-enabled/$site"
            sudo nginx -t && sudo systemctl reload nginx
        fi
        
        if [[ -f "/etc/apache2/sites-available/${site}.conf" ]]; then
            sudo a2dissite "${site}.conf" 2>/dev/null
            sudo rm -f "/etc/apache2/sites-available/${site}.conf"
            sudo apache2ctl configtest && sudo systemctl reload apache2
        fi
        
        # Remove SSL certificates
        if [[ -d "/etc/letsencrypt/live/$site" ]]; then
            sudo certbot delete --cert-name "$site" --non-interactive 2>/dev/null
        fi
        
        # Remove site directory
        if [[ -d "$site_dir" ]]; then
            sudo rm -rf "$site_dir"
        fi
        
        ui_success "Site $site has been completely removed"
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
            "back" "← Back to Main Menu"
        )
        
        local choice
        choice=$(ui_menu "PHP Settings Management" "$current_settings" 20 80 8 "${menu_items[@]}") || break
        
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
            back)
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
        choice=$(ui_menu "Custom PHP Settings" "$custom_info" 16 70 8 "${menu_items[@]}") || break
        
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
    # Initialize
    init_logging
    log "Initializing Ultrabunt Ultimate Buntstaller..."
    
    ensure_deps
    log "Dependencies check completed"
    
    log "╔═══════════════════════════════════════════════════════╗"
    log "║     ULTRABUNT ULTIMATE BUNTSTALLER v4.2.0 STARTED     ║"
    log "╚═══════════════════════════════════════════════════════╝"
    
    # Update buntage cache
    log "Starting APT cache update..."
    apt_update
    log "APT cache update completed"
    
    # Build buntage installation cache for fast lookups
    build_package_cache
    
    # Show main menu
    log "Loading main menu..."
    show_category_menu
    log "Main menu completed"
    
    # Farewell
    log "Ultrabunt Ultimate Buntstaller exiting."
    ui_msg "Goodbye!" "Thanks for bunting Ultrabunt Ultimate Buntstaller!\n\nLog: $LOGFILE\nBackups: $BACKUP_DIR\n\n💡 Tip: Reboot to apply all changes."
}

# Run main program
main
exit 0