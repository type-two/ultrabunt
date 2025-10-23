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
    
    if [[ -z "$name" ]]; then
        log "ERROR: No buntage name provided to update_package_cache"
        return 1
    fi
    
    if [[ -z "${PACKAGES[$name]:-}" ]]; then
        log "WARNING: Buntage '$name' not found in PACKAGES array"
        return 1
    fi
    
    local pkg="${PACKAGES[$name]}"
    local method="${PKG_METHOD[$name]:-}"
    
    log "Updating cache for buntage: $name (method: $method, pkg: $pkg)"
    
    # Update the specific buntage in the cache
    case "$method" in
        apt)
            if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                INSTALLED_CACHE["apt:$pkg"]="1"
                log "Cache updated: $name is installed (APT)"
            else
                unset INSTALLED_CACHE["apt:$pkg"]
                log "Cache updated: $name is not installed (APT)"
            fi
            ;;
        snap)
            if snap list "$pkg" &>/dev/null; then
                INSTALLED_CACHE["snap:$pkg"]="1"
                log "Cache updated: $name is installed (Snap)"
            else
                unset INSTALLED_CACHE["snap:$pkg"]
                log "Cache updated: $name is not installed (Snap)"
            fi
            ;;
        flatpak)
            if flatpak list --app 2>/dev/null | grep -q "$pkg"; then
                INSTALLED_CACHE["flatpak:$pkg"]="1"
                log "Cache updated: $name is installed (Flatpak)"
            else
                unset INSTALLED_CACHE["flatpak:$pkg"]
                log "Cache updated: $name is not installed (Flatpak)"
            fi
            ;;
        custom)
            # For custom buntages, we can't easily cache them, so we'll just log
            log "Cache update skipped for custom buntage: $name"
            ;;
        *)
            log "WARNING: Unknown method '$method' for buntage '$name'"
            return 1
            ;;
    esac
    
    return 0
}

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOGFILE"
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
PKG_DESC[git]="Version control system"
PKG_METHOD[git]="apt"
PKG_CATEGORY[git]="core"

PACKAGES[curl]="curl"
PKG_DESC[curl]="Command line tool for transferring data"
PKG_METHOD[curl]="apt"
PKG_CATEGORY[curl]="core"

PACKAGES[wget]="wget"
PKG_DESC[wget]="Network downloader"
PKG_METHOD[wget]="apt"
PKG_CATEGORY[wget]="core"

PACKAGES[build-essential]="build-essential"
PKG_DESC[build-essential]="Compilation tools (gcc, make, etc)"
PKG_METHOD[build-essential]="apt"
PKG_CATEGORY[build-essential]="core"

PACKAGES[tree]="tree"
PKG_DESC[tree]="Directory listing in tree format"
PKG_METHOD[tree]="apt"
PKG_CATEGORY[tree]="core"

PACKAGES[ncdu]="ncdu"
PKG_DESC[ncdu]="NCurses Disk Usage analyzer"
PKG_METHOD[ncdu]="apt"
PKG_CATEGORY[ncdu]="core"

PACKAGES[jq]="jq"
PKG_DESC[jq]="JSON processor"
PKG_METHOD[jq]="apt"
PKG_CATEGORY[jq]="core"

PACKAGES[tmux]="tmux"
PKG_DESC[tmux]="Terminal multiplexer"
PKG_METHOD[tmux]="apt"
PKG_CATEGORY[tmux]="core"

PACKAGES[fzf]="fzf"
PKG_DESC[fzf]="Fuzzy finder"
PKG_METHOD[fzf]="apt"
PKG_CATEGORY[fzf]="core"

PACKAGES[ripgrep]="ripgrep"
PKG_DESC[ripgrep]="Fast grep alternative (rg)"
PKG_METHOD[ripgrep]="apt"
PKG_CATEGORY[ripgrep]="core"

PACKAGES[bat]="bat"
PKG_DESC[bat]="Cat clone with syntax highlighting"
PKG_METHOD[bat]="apt"
PKG_CATEGORY[bat]="core"

PACKAGES[eza]="eza"
PKG_DESC[eza]="Modern ls replacement"
PKG_METHOD[eza]="apt"
PKG_CATEGORY[eza]="core"

PACKAGES[tldr]="tldr"
PKG_DESC[tldr]="Simplified man pages"
PKG_METHOD[tldr]="apt"
PKG_CATEGORY[tldr]="core"

# DEVELOPMENT TOOLS
PACKAGES[neovim]="neovim"
PKG_DESC[neovim]="Modern Vim-based editor"
PKG_METHOD[neovim]="apt"
PKG_CATEGORY[neovim]="dev"

PACKAGES[python3-pip]="python3-pip"
PKG_DESC[python3-pip]="Python buntage installer"
PKG_METHOD[python3-pip]="apt"
PKG_CATEGORY[python3-pip]="dev"

PACKAGES[python3-venv]="python3-venv"
PKG_DESC[python3-venv]="Python virtual environments"
PKG_METHOD[python3-venv]="apt"
PKG_CATEGORY[python3-venv]="dev"

PACKAGES[default-jdk]="default-jdk"
PKG_DESC[default-jdk]="Java Development Kit"
PKG_METHOD[default-jdk]="apt"
PKG_CATEGORY[default-jdk]="dev"

PACKAGES[golang]="golang-go"
PKG_DESC[golang]="Go programming language"
PKG_METHOD[golang]="apt"
PKG_CATEGORY[golang]="dev"

# CONTAINERS
PACKAGES[docker]="docker-ce"
PKG_DESC[docker]="Docker container platform"
PKG_METHOD[docker]="custom"
PKG_CATEGORY[docker]="containers"

PACKAGES[docker-compose]="docker-compose-plugin"
PKG_DESC[docker-compose]="Docker Compose plugin"
PKG_METHOD[docker-compose]="apt"
PKG_CATEGORY[docker-compose]="containers"
PKG_DEPS[docker-compose]="docker"

# WEB STACK
PACKAGES[nginx]="nginx"
PKG_DESC[nginx]="High-performance web server"
PKG_METHOD[nginx]="apt"
PKG_CATEGORY[nginx]="web"

PACKAGES[apache2]="apache2"
PKG_DESC[apache2]="Apache HTTP Server"
PKG_METHOD[apache2]="apt"
PKG_CATEGORY[apache2]="web"

PACKAGES[php-fpm]="php${PHP_VER}-fpm"
PKG_DESC[php-fpm]="PHP FastCGI Process Manager"
PKG_METHOD[php-fpm]="apt"
PKG_CATEGORY[php-fpm]="web"

PACKAGES[libapache2-mod-php]="libapache2-mod-php${PHP_VER}"
PKG_DESC[libapache2-mod-php]="PHP module for Apache"
PKG_METHOD[libapache2-mod-php]="apt"
PKG_CATEGORY[libapache2-mod-php]="web"

PACKAGES[php-mysql]="php${PHP_VER}-mysql"
PKG_DESC[php-mysql]="PHP MySQL extension"
PKG_METHOD[php-mysql]="apt"
PKG_CATEGORY[php-mysql]="web"

PACKAGES[php-curl]="php${PHP_VER}-curl"
PKG_DESC[php-curl]="PHP cURL extension"
PKG_METHOD[php-curl]="apt"
PKG_CATEGORY[php-curl]="web"

PACKAGES[php-gd]="php${PHP_VER}-gd"
PKG_DESC[php-gd]="PHP GD graphics extension"
PKG_METHOD[php-gd]="apt"
PKG_CATEGORY[php-gd]="web"

PACKAGES[php-xml]="php${PHP_VER}-xml"
PKG_DESC[php-xml]="PHP XML extension"
PKG_METHOD[php-xml]="apt"
PKG_CATEGORY[php-xml]="web"

PACKAGES[php-mbstring]="php${PHP_VER}-mbstring"
PKG_DESC[php-mbstring]="PHP multibyte string extension"
PKG_METHOD[php-mbstring]="apt"
PKG_CATEGORY[php-mbstring]="web"

PACKAGES[php-zip]="php${PHP_VER}-zip"
PKG_DESC[php-zip]="PHP ZIP extension"
PKG_METHOD[php-zip]="apt"
PKG_CATEGORY[php-zip]="web"

PACKAGES[mariadb]="mariadb-server"
PKG_DESC[mariadb]="MariaDB database server"
PKG_METHOD[mariadb]="apt"
PKG_CATEGORY[mariadb]="web"

PACKAGES[certbot]="certbot"
PKG_DESC[certbot]="Let's Encrypt SSL certificate tool"
PKG_METHOD[certbot]="apt"
PKG_CATEGORY[certbot]="web"

PACKAGES[python3-certbot-nginx]="python3-certbot-nginx"
PKG_DESC[python3-certbot-nginx]="Certbot Nginx plugin"
PKG_METHOD[python3-certbot-nginx]="apt"
PKG_CATEGORY[python3-certbot-nginx]="web"

PACKAGES[python3-certbot-apache]="python3-certbot-apache"
PKG_DESC[python3-certbot-apache]="Certbot Apache plugin"
PKG_METHOD[python3-certbot-apache]="apt"
PKG_CATEGORY[python3-certbot-apache]="web"

PACKAGES[redis]="redis-server"
PKG_DESC[redis]="Redis in-memory data store"
PKG_METHOD[redis]="apt"
PKG_CATEGORY[redis]="web"

# NODE.JS
PACKAGES[nodejs]="nodejs"
PKG_DESC[nodejs]="Node.js JavaScript runtime"
PKG_METHOD[nodejs]="custom"
PKG_CATEGORY[nodejs]="dev"

PACKAGES[npm]="npm"
PKG_DESC[npm]="Node buntage manager"
PKG_METHOD[npm]="apt"
PKG_CATEGORY[npm]="dev"

# SHELLS & UI
PACKAGES[zsh]="zsh"
PKG_DESC[zsh]="Z shell"
PKG_METHOD[zsh]="apt"
PKG_CATEGORY[zsh]="shell"

PACKAGES[fonts-powerline]="fonts-powerline"
PKG_DESC[fonts-powerline]="Powerline fonts"
PKG_METHOD[fonts-powerline]="apt"
PKG_CATEGORY[fonts-powerline]="shell"

# EDITORS & IDEs
PACKAGES[vscode]="code"
PKG_DESC[vscode]="Visual Studio Code"
PKG_METHOD[vscode]="custom"
PKG_CATEGORY[vscode]="editors"

PACKAGES[sublime-text]="sublime-text"
PKG_DESC[sublime-text]="Sublime Text editor"
PKG_METHOD[sublime-text]="custom"
PKG_CATEGORY[sublime-text]="editors"

# BROWSERS
PACKAGES[brave]="brave-browser"
PKG_DESC[brave]="Brave web browser"
PKG_METHOD[brave]="custom"
PKG_CATEGORY[brave]="browsers"

PACKAGES[firefox]="firefox"
PKG_DESC[firefox]="Mozilla Firefox browser"
PKG_METHOD[firefox]="apt"
PKG_CATEGORY[firefox]="browsers"

PACKAGES[chromium]="chromium"
PKG_DESC[chromium]="Chromium web browser"
PKG_METHOD[chromium]="apt"
PKG_CATEGORY[chromium]="browsers"

# MONITORING
PACKAGES[htop]="htop"
PKG_DESC[htop]="Interactive process viewer"
PKG_METHOD[htop]="apt"
PKG_CATEGORY[htop]="monitoring"

PACKAGES[btop]="btop"
PKG_DESC[btop]="Resource monitor with better graphs"
PKG_METHOD[btop]="apt"
PKG_CATEGORY[btop]="monitoring"

PACKAGES[glances]="glances"
PKG_DESC[glances]="Cross-platform system monitor"
PKG_METHOD[glances]="apt"
PKG_CATEGORY[glances]="monitoring"

PACKAGES[nethogs]="nethogs"
PKG_DESC[nethogs]="Network bandwidth monitor per process"
PKG_METHOD[nethogs]="apt"
PKG_CATEGORY[nethogs]="monitoring"

PACKAGES[iotop]="iotop"
PKG_DESC[iotop]="I/O monitor"
PKG_METHOD[iotop]="apt"
PKG_CATEGORY[iotop]="monitoring"

# SECURITY
PACKAGES[ufw]="ufw"
PKG_DESC[ufw]="Uncomplicated Firewall"
PKG_METHOD[ufw]="apt"
PKG_CATEGORY[ufw]="security"

PACKAGES[fail2ban]="fail2ban"
PKG_DESC[fail2ban]="Intrusion prevention system"
PKG_METHOD[fail2ban]="apt"
PKG_CATEGORY[fail2ban]="security"

# FLATPAK & APPS
PACKAGES[flatpak]="flatpak"
PKG_DESC[flatpak]="Flatpak buntage manager"
PKG_METHOD[flatpak]="apt"
PKG_CATEGORY[flatpak]="system"

PACKAGES[localsend]="org.localsend.localsend_app"
PKG_DESC[localsend]="LocalSend file sharing"
PKG_METHOD[localsend]="flatpak"
PKG_CATEGORY[localsend]="communication"
PKG_DEPS[localsend]="flatpak"

# SNAP APPS
PACKAGES[spotify]="spotify"
PKG_DESC[spotify]="Music streaming service"
PKG_METHOD[spotify]="snap"
PKG_CATEGORY[spotify]="multimedia"

PACKAGES[postman]="postman"
PKG_DESC[postman]="API development platform"
PKG_METHOD[postman]="snap"
PKG_CATEGORY[postman]="development"

# DESKTOP APPS
PACKAGES[obs-studio]="obs-studio"
PKG_DESC[obs-studio]="OBS Studio streaming/recording"
PKG_METHOD[obs-studio]="apt"
PKG_CATEGORY[obs-studio]="multimedia"

PACKAGES[vlc]="vlc"
PKG_DESC[vlc]="VLC media player"
PKG_METHOD[vlc]="apt"
PKG_CATEGORY[vlc]="multimedia"

# CLOUD & SYNC
PACKAGES[rclone]="rclone"
PKG_DESC[rclone]="Cloud storage sync tool"
PKG_METHOD[rclone]="apt"
PKG_CATEGORY[rclone]="cloud"

# TERMINALS
PACKAGES[warp-terminal]="warp-terminal"
PKG_DESC[warp-terminal]="Modern terminal with AI features"
PKG_METHOD[warp-terminal]="custom"
PKG_CATEGORY[warp-terminal]="terminals"

# GAMING
PACKAGES[steam]="steam"
PKG_DESC[steam]="Steam gaming platform"
PKG_METHOD[steam]="apt"
PKG_CATEGORY[steam]="gaming"

PACKAGES[heroic-launcher]="com.heroicgameslauncher.hgl"
PKG_DESC[heroic-launcher]="Open-source Epic Games/GOG launcher"
PKG_METHOD[heroic-launcher]="flatpak"
PKG_CATEGORY[heroic-launcher]="gaming"
PKG_DEPS[heroic-launcher]="flatpak"

PACKAGES[gimp]="gimp"
PKG_DESC[gimp]="GIMP image editor"
PKG_METHOD[gimp]="apt"
PKG_CATEGORY[gimp]="multimedia"

# OFFICE & PRODUCTIVITY
PACKAGES[libreoffice]="libreoffice"
PKG_DESC[libreoffice]="LibreOffice office suite"
PKG_METHOD[libreoffice]="apt"
PKG_CATEGORY[libreoffice]="office"

PACKAGES[thunderbird]="thunderbird"
PKG_DESC[thunderbird]="Thunderbird email client"
PKG_METHOD[thunderbird]="apt"
PKG_CATEGORY[thunderbird]="office"

# COMMUNICATION
PACKAGES[discord]="discord"
PKG_DESC[discord]="Discord voice and text chat"
PKG_METHOD[discord]="snap"
PKG_CATEGORY[discord]="communication"

PACKAGES[telegram-desktop]="telegram-desktop"
PKG_DESC[telegram-desktop]="Telegram messaging app"
PKG_METHOD[telegram-desktop]="apt"
PKG_CATEGORY[telegram-desktop]="communication"

PACKAGES[zoom]="zoom-client"
PKG_DESC[zoom]="Zoom video conferencing"
PKG_METHOD[zoom]="snap"
PKG_CATEGORY[zoom]="communication"

# MULTIMEDIA
PACKAGES[audacity]="audacity"
PKG_DESC[audacity]="Audacity audio editor"
PKG_METHOD[audacity]="apt"
PKG_CATEGORY[audacity]="multimedia"

PACKAGES[blender]="blender"
PKG_DESC[blender]="Blender 3D creation suite"
PKG_METHOD[blender]="snap"
PKG_CATEGORY[blender]="multimedia"

PACKAGES[inkscape]="inkscape"
PKG_DESC[inkscape]="Inkscape vector graphics editor"
PKG_METHOD[inkscape]="apt"
PKG_CATEGORY[inkscape]="multimedia"

# AI & MODERN TOOLS
PACKAGES[ollama]="ollama"
PKG_DESC[ollama]="Local AI model runner (Llama, Mistral, etc.)"
PKG_METHOD[ollama]="custom"
PKG_CATEGORY[ollama]="ai"

PACKAGES[gollama]="gollama"
PKG_DESC[gollama]="Advanced LLM model management and interaction tool"
PKG_METHOD[gollama]="custom"
PKG_CATEGORY[gollama]="ai"

PACKAGES[ffmpeg]="ffmpeg"
PKG_DESC[ffmpeg]="Complete multimedia processing toolkit"
PKG_METHOD[ffmpeg]="apt"
PKG_CATEGORY[ffmpeg]="multimedia"

PACKAGES[yt-dlp]="yt-dlp"
PKG_DESC[yt-dlp]="Modern YouTube/media downloader (youtube-dl fork)"
PKG_METHOD[yt-dlp]="custom"
PKG_CATEGORY[yt-dlp]="multimedia"

PACKAGES[n8n]="n8n"
PKG_DESC[n8n]="Workflow automation tool (self-hosted Zapier alternative)"
PKG_METHOD[n8n]="custom"
PKG_CATEGORY[n8n]="development"

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
    sudo snap install "$pkg" 2>&1 | tee -a "$LOGFILE"
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
    
    # Download and install Warp terminal .deb buntage
    local warp_url="https://releases.warp.dev/linux/v0.2024.10.29.08.02.stable_02/warp-terminal_0.2024.10.29.08.02.stable.02_amd64.deb"
    local temp_file="/tmp/warp-terminal.deb"
    
    if wget -O "$temp_file" "$warp_url" 2>/dev/null; then
        if sudo dpkg -i "$temp_file" 2>/dev/null || sudo apt-get install -f -y; then
            rm -f "$temp_file"
            ui_msg "Warp Installed" "Warp terminal installed successfully."
        else
            rm -f "$temp_file"
            log_error "Failed to install Warp terminal"
            return 1
        fi
    else
        log_error "Failed to download Warp terminal"
        return 1
    fi
}

remove_warp() {
    remove_apt_package "warp-terminal"
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
        flatpak)
            if ! is_apt_installed "flatpak"; then
                ui_msg "Flatpak Required" "Installing Flatpak first..."
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
    log "Checking if buntage '$name' is installed"
    
    # Add error handling for empty or invalid buntage names
    if [[ -z "$name" ]]; then
        log "ERROR: Empty buntage name provided to is_package_installed"
        return 1
    fi
    
    if [[ -z "${PACKAGES[$name]:-}" ]]; then
        log "WARNING: Buntage '$name' not found in PACKAGES array"
        return 1
    fi
    
    local pkg="${PACKAGES[$name]}"
    local method="${PKG_METHOD[$name]:-}"
    
    if [[ -z "$method" ]]; then
        log "WARNING: No method defined for buntage '$name'"
        return 1
    fi
    
    log "Buntage '$name' uses method '$method' with buntage name '$pkg'"
    
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

show_category_menu() {
    log "Entering show_category_menu function"
    
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
                    
                    # Re-enable installation check
                    if is_package_installed "$name"; then
                        installed=$((installed + 1))
                    fi
                fi
            done
            
            menu_items+=("$cat_id" "(.Y.) $cat_name [$installed/$total installed]")
        done
        
        log "Adding additional menu items..."
        menu_items+=("" "(_*_)")
        menu_items+=("system-info" "(.Y.) System Information")
        menu_items+=("keyboard-layout" "(.Y.) Keyboard Layout Configuration")
        menu_items+=("wordpress-setup" "(.Y.) WordPress Installation")
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
                install_package "$name"
                ui_msg "Success" "$name installed successfully!"
                status="✓ Installed"
                ;;
            reinstall)
                remove_package "$name"
                install_package "$name"
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
        if is_package_installed "$name"; then
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
                    if is_package_installed "$name"; then
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
            "quick-nginx" "(.Y.) 🚀 Quick Setup (Nginx + WordPress)"
            "quick-apache" "(.Y.) 🚀 Quick Setup (Apache + WordPress)"
            "" "(_*_)"
            "custom-nginx" "(.Y.) ⚙️  Custom Nginx Setup"
            "custom-apache" "(.Y.) ⚙️  Custom Apache Setup"
            "" "(_*_)"
            "ssl-setup" "(.Y.) 🔒 Add SSL Certificate (Let's Encrypt)"
            "wp-security" "(.Y.) 🛡️  WordPress Security Hardening"
            "" "(_*_)"
            "status" "(.Y.) 📊 Show WordPress Sites Status"
            "zback" "(Z) ← Back to Main Menu"
        )
        
        local choice
        choice=$(ui_menu "WordPress Installation" \
            "Choose your WordPress installation method:" \
            20 80 12 "${menu_items[@]}") || break
        
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
    install_wordpress_prerequisites "$web_server"
    
    # Get domain name
    local domain
    domain=$(ui_input "Domain Name" "Enter your domain name:" "localhost") || return
    domain=${domain:-localhost}
    
    # Setup database
    local db_info
    db_info=$(setup_wordpress_database "$domain")
    
    # Download and configure WordPress
    setup_wordpress_files "$domain" "$db_info"
    
    # Configure web server
    if [[ "$web_server" == "nginx" ]]; then
        configure_nginx_wordpress "$domain"
    else
        configure_apache_wordpress "$domain"
    fi
    
    # Show completion message
    show_wordpress_completion "$domain" "$db_info"
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

install_wordpress_prerequisites() {
    local web_server="$1"
    log "Installing WordPress prerequisites for $web_server"
    
    ui_msg "Installing Prerequisites" "Installing required packages for WordPress...\n\nThis may take a few minutes."
    
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
    
    # Generate random root password
    local root_pass
    root_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
    
    # Secure installation
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}';" 2>/dev/null || true
    sudo mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    sudo mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
    sudo mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    # Save root password
    echo "$root_pass" | sudo tee /root/.mysql_root_password > /dev/null
    sudo chmod 600 /root/.mysql_root_password
    
    log "MariaDB security setup completed"
}

setup_wordpress_database() {
    local domain="$1"
    local db_name="wp_${domain//[^a-zA-Z0-9]/_}_$(date +%s)"
    local db_user="wpuser_$(date +%s)"
    local db_pass
    db_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
    
    log "Creating WordPress database: $db_name"
    
    # Create database and user
    sudo mysql -e "CREATE DATABASE ${db_name} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 | tee -a "$LOGFILE"
    sudo mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" 2>&1 | tee -a "$LOGFILE"
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';" 2>&1 | tee -a "$LOGFILE"
    sudo mysql -e "FLUSH PRIVILEGES;" 2>&1 | tee -a "$LOGFILE"
    
    echo "${db_name}:${db_user}:${db_pass}"
}

setup_wordpress_database_custom() {
    local domain="$1"
    
    local db_name
    db_name=$(ui_input "Database Name" "WordPress database name:" "wp_${domain//[^a-zA-Z0-9]/_}") || return
    
    local db_user
    db_user=$(ui_input "Database User" "WordPress database user:" "wp_user") || return
    
    local db_pass
    db_pass=$(ui_input "Database Password" "Database password (leave empty for auto-generated):" "") || return
    
    if [[ -z "$db_pass" ]]; then
        db_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
    fi
    
    log "Creating custom WordPress database: $db_name"
    
    # Create database and user
    sudo mysql -e "CREATE DATABASE ${db_name} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 | tee -a "$LOGFILE"
    sudo mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" 2>&1 | tee -a "$LOGFILE"
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';" 2>&1 | tee -a "$LOGFILE"
    sudo mysql -e "FLUSH PRIVILEGES;" 2>&1 | tee -a "$LOGFILE"
    
    echo "${db_name}:${db_user}:${db_pass}"
}

setup_wordpress_files() {
    local domain="$1"
    local db_info="$2"
    local site_dir="/var/www/$domain"
    
    log "Setting up WordPress files for $domain"
    
    # Parse database info
    IFS=':' read -r db_name db_user db_pass <<< "$db_info"
    
    # Create site directory
    sudo mkdir -p "$site_dir"
    sudo chown "$USER:$USER" "$site_dir"
    
    # Download WordPress
    ui_msg "Downloading WordPress" "Downloading latest WordPress..."
    wget -q https://wordpress.org/latest.tar.gz -O /tmp/wordpress.tar.gz || {
        ui_msg "Download Error" "Failed to download WordPress. Please check your internet connection."
        return 1
    }
    
    tar -xzf /tmp/wordpress.tar.gz -C /tmp
    rsync -a /tmp/wordpress/ "$site_dir/"
    rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
    
    # Configure WordPress
    cp "$site_dir/wp-config-sample.php" "$site_dir/wp-config.php"
    
    # Database configuration
    sed -i "s/database_name_here/${db_name}/" "$site_dir/wp-config.php"
    sed -i "s/username_here/${db_user}/" "$site_dir/wp-config.php"
    sed -i "s/password_here/${db_pass}/" "$site_dir/wp-config.php"
    
    # Add security keys
    local salts
    salts=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null) || {
        log "Warning: Could not fetch WordPress security keys"
        salts="// Security keys could not be fetched automatically"
    }
    
    # Replace the placeholder keys
    sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$site_dir/wp-config.php"
    sed -i "/\/\*\* MySQL settings/i\\$salts" "$site_dir/wp-config.php"
    
    # Set proper permissions
    sudo chown -R www-data:www-data "$site_dir"
    sudo find "$site_dir" -type d -exec chmod 755 {} \;
    sudo find "$site_dir" -type f -exec chmod 644 {} \;
    
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
    
    # Save credentials
    local creds_file="$BACKUP_DIR/wordpress-${domain}-$(date +%Y%m%d-%H%M%S).txt"
    cat > "$creds_file" <<EOF
WordPress Installation Complete
═══════════════════════════════════════════════════════════════
Domain: $domain
Site Directory: /var/www/$domain
Database Name: $db_name
Database User: $db_user
Database Password: $db_pass

WordPress Admin Setup:
1. Visit: http://$domain
2. Complete the WordPress installation wizard
3. Create your admin account

Next Steps:
- Consider setting up SSL with Let's Encrypt
- Configure WordPress security hardening
- Install essential plugins
- Set up backups

Installation completed: $(date)
EOF
    
    local completion_msg="🎉 WordPress Installation Complete!\n\n"
    completion_msg+="Your WordPress site is ready at:\n"
    completion_msg+="http://$domain\n\n"
    completion_msg+="Database Details:\n"
    completion_msg+="• Name: $db_name\n"
    completion_msg+="• User: $db_user\n"
    completion_msg+="• Password: $db_pass\n\n"
    completion_msg+="📝 Credentials saved to:\n$creds_file\n\n"
    completion_msg+="🔗 Visit your site to complete the WordPress setup wizard!"
    
    ui_info "WordPress Ready!" "$completion_msg"
    
    log "WordPress installation completed for $domain"
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
        
        # Database connection test
        local db_status="❌"
        if [[ -f "$site_dir/wp-config.php" ]]; then
            local db_name db_user db_pass db_host
            db_name=$(grep "DB_NAME" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            db_user=$(grep "DB_USER" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            db_pass=$(grep "DB_PASSWORD" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            db_host=$(grep "DB_HOST" "$site_dir/wp-config.php" | cut -d"'" -f4 2>/dev/null)
            
            if [[ -n "$db_name" && -n "$db_user" ]]; then
                if mysql -u"$db_user" -p"$db_pass" -h"${db_host:-localhost}" -e "USE $db_name;" 2>/dev/null; then
                    db_status="✅"
                fi
            fi
        fi
        status_info+="🗄️  Database Connection: $db_status\n"
        
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
        
        local menu_items=(
            "" "(_*_)"
            "view-config" "📄 View Full Web Server Config"
            "edit-config" "✏️  Edit Web Server Config"
            "enable-site" "🔗 Enable/Disable Site"
            "test-site" "🧪 Test Site Accessibility"
            "" "(_*_)"
            "delete-site" "🗑️  Delete This Site (DANGER)"
            "" "(_*_)"
            "zback" "(Z) ← Back to Site List"
        )
        
        local choice
        choice=$(ui_menu "Site Management: $site" "$status_info" 25 90 15 "${menu_items[@]}") || break
        
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

# ==============================================================================
# KEYBOARD LAYOUT CONFIGURATION
# ==============================================================================

show_keyboard_layout_menu() {
    log "Entering show_keyboard_layout_menu function"
    
    while true; do
        local menu_items=(
            "macbook" "(.Y.) MacBook Layout (Cmd as Super, Cmd+Tab switching)"
            "thinkpad" "(.Y.) ThinkPad Layout (Standard PC layout optimized)"
            "generic" "(.Y.) Generic Laptop Layout (Standard configuration)"
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
    
    # Create autostart file for keyboard mapping
    cat > "$HOME/.config/autostart/keyboard-mapping.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Keyboard Mapping
Exec=/bin/bash -c "setxkbmap -option caps:ctrl_modifier"
X-GNOME-Autostart-enabled=true
EOF
    
    # Apply the mapping immediately
    setxkbmap -option caps:ctrl_modifier 2>/dev/null || log "Warning: Could not apply setxkbmap immediately"
    
    # Configure GNOME shortcuts for macOS-like behavior
    gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Alt>Tab']" 2>/dev/null || log "Warning: Could not set switch-applications"
    gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>grave']" 2>/dev/null || log "Warning: Could not set switch-windows"
    
    # Set Super+Space for show applications (like Spotlight)
    gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>space']" 2>/dev/null || log "Warning: Could not set toggle-overview"
    
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
    
    log "Generic keyboard configuration applied"
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
    
    log "Keyboard configuration reset to defaults"
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
    log "║     ULTRABUNT ULTIMATE BUNTSTALLER v4.2.0 STARTED       ║"
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