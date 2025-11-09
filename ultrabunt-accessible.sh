#!/bin/bash

# Ultrabunt Accessible Installer
# Enhanced version with Text-to-Speech support for visually impaired users
# Uses spd-say (Speech Dispatcher) for audio feedback

# Color codes for visual users who might have partial sight
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# TTS Configuration
TTS_ENABLED=true
TTS_VOICE="female1"
TTS_RATE="-20"  # Slightly slower for clarity
TTS_PITCH="0"   # Normal pitch
TTS_VOLUME="10" # Slightly louder
TTS_PUNCTUATION="some" # Read some punctuation for clarity

# Function to check and install TTS dependencies
install_tts_dependencies() {
    echo -e "${CYAN}Checking Text-to-Speech Dependencies...${NC}"
    
    # Check if running with sudo privileges
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}Error: This script needs to be run with sudo to install dependencies.${NC}"
        echo -e "${YELLOW}Please run: sudo ./ultrabunt-accessible.sh${NC}"
        exit 1
    fi
    
    local packages_to_install=()
    local missing_packages=()
    
    # Check for required packages
    echo -e "${YELLOW}Checking required packages...${NC}"
    
    # Speech Dispatcher
    if ! dpkg -l | grep -q "^ii.*speech-dispatcher "; then
        missing_packages+=("speech-dispatcher")
        echo -e "  ${RED}✗${NC} speech-dispatcher (not installed)"
    else
        echo -e "  ${GREEN}✓${NC} speech-dispatcher (installed)"
    fi
    
    # PulseAudio
    if ! dpkg -l | grep -q "^ii.*pulseaudio "; then
        missing_packages+=("pulseaudio")
        echo -e "  ${RED}✗${NC} pulseaudio (not installed)"
    else
        echo -e "  ${GREEN}✓${NC} pulseaudio (installed)"
    fi
    
    # ALSA utilities
    if ! dpkg -l | grep -q "^ii.*alsa-utils "; then
        missing_packages+=("alsa-utils")
        echo -e "  ${RED}✗${NC} alsa-utils (not installed)"
    else
        echo -e "  ${GREEN}✓${NC} alsa-utils (installed)"
    fi
    
    # PulseAudio utilities
    if ! dpkg -l | grep -q "^ii.*pulseaudio-utils "; then
        missing_packages+=("pulseaudio-utils")
        echo -e "  ${RED}✗${NC} pulseaudio-utils (not installed)"
    else
        echo -e "  ${GREEN}✓${NC} pulseaudio-utils (installed)"
    fi
    
    # Festival speech synthesis (fallback TTS engine)
    if ! dpkg -l | grep -q "^ii.*festival "; then
        missing_packages+=("festival")
        echo -e "  ${RED}✗${NC} festival (not installed)"
    else
        echo -e "  ${GREEN}✓${NC} festival (installed)"
    fi
    
    # eSpeak (another TTS engine)
    if ! dpkg -l | grep -q "^ii.*espeak "; then
        missing_packages+=("espeak")
        echo -e "  ${RED}✗${NC} espeak (not installed)"
    else
        echo -e "  ${GREEN}✓${NC} espeak (installed)"
    fi
    
    # If packages are missing, offer to install them
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Missing packages detected:${NC}"
        for package in "${missing_packages[@]}"; do
            echo -e "  • $package"
        done
        echo ""
        echo -e "${CYAN}These packages are required for text-to-speech functionality.${NC}"
        echo -e "${WHITE}Would you like to install them now? (y/n)${NC}"
        read -p "Install missing packages? " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Installing missing packages...${NC}"
            
            # Update package list
            echo -e "${YELLOW}Updating package list...${NC}"
            apt update
            
            # Install missing packages
            for package in "${missing_packages[@]}"; do
                echo -e "${YELLOW}Installing $package...${NC}"
                if apt install -y "$package"; then
                    echo -e "${GREEN}✓ $package installed successfully${NC}"
                else
                    echo -e "${RED}✗ Failed to install $package${NC}"
                fi
            done
            
            # Configure audio system
            echo -e "${YELLOW}Configuring audio system...${NC}"
            
            # Start PulseAudio if not running
            if ! pgrep -x "pulseaudio" > /dev/null && ! pgrep -x "pipewire" > /dev/null; then
                echo -e "${YELLOW}Starting PulseAudio...${NC}"
                # Get the actual user (not root) if running with sudo
                local actual_user="${SUDO_USER:-$USER}"
                if [[ -n "$actual_user" && "$actual_user" != "root" ]]; then
                    sudo -u "$actual_user" pulseaudio --start 2>/dev/null || true
                fi
            else
                echo -e "${GREEN}✓ Audio system is running (PulseAudio/PipeWire)${NC}"
            fi
            
            # Configure Speech Dispatcher
            echo -e "${YELLOW}Configuring Speech Dispatcher...${NC}"
            
            # Stop Speech Dispatcher service first
            systemctl stop speech-dispatcher 2>/dev/null || true
            
            # Create basic Speech Dispatcher config if it doesn't exist
            local spd_config_dir="/etc/speech-dispatcher"
            if [[ -d "$spd_config_dir" ]]; then
                # Ensure Speech Dispatcher can use available TTS engines
                if [[ -f "$spd_config_dir/speechd.conf" ]]; then
                    # Enable espeak as default if available
                    if command -v espeak >/dev/null 2>&1; then
                        sed -i 's/^#.*DefaultModule.*espeak/DefaultModule espeak/' "$spd_config_dir/speechd.conf" 2>/dev/null || true
                        echo -e "  ${GREEN}✓${NC} Set espeak as default TTS engine"
                    fi
                fi
                
                # Create user-specific Speech Dispatcher config
                local actual_user="${SUDO_USER:-$USER}"
                if [[ -n "$actual_user" && "$actual_user" != "root" ]]; then
                    local user_spd_dir="/home/$actual_user/.config/speech-dispatcher"
                    sudo -u "$actual_user" mkdir -p "$user_spd_dir" 2>/dev/null || true
                    
                    # Create a simple user config that prefers espeak with female voice
                    if [[ ! -f "$user_spd_dir/speechd.conf" ]]; then
                        sudo -u "$actual_user" cat > "$user_spd_dir/speechd.conf" << 'EOF'
# User Speech Dispatcher Configuration
LogLevel 3
DefaultModule espeak
DefaultLanguage en
DefaultRate -20
DefaultPitch 0
DefaultVolume 100
DefaultVoiceType female1
EOF
                        echo -e "  ${GREEN}✓${NC} Created user Speech Dispatcher config with female voice"
                    fi
                    
                    # Also create espeak-specific config for female voice
                    if [[ ! -f "$user_spd_dir/modules/espeak.conf" ]]; then
                        sudo -u "$actual_user" mkdir -p "$user_spd_dir/modules" 2>/dev/null || true
                        sudo -u "$actual_user" cat > "$user_spd_dir/modules/espeak.conf" << 'EOF'
# Espeak module configuration
EspeakDefaultVoice "en+f3"
EspeakRate -20
EspeakPitch 0
EspeakVolume 100
EOF
                        echo -e "  ${GREEN}✓${NC} Created espeak module config with female voice"
                    fi
                fi
            fi
            
            # Restart Speech Dispatcher service
            echo -e "${YELLOW}Restarting Speech Dispatcher service...${NC}"
            systemctl start speech-dispatcher 2>/dev/null || true
            sleep 2  # Give it time to start
            
            # Check if Speech Dispatcher is running
            if systemctl is-active --quiet speech-dispatcher 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Speech Dispatcher service is running"
            else
                echo -e "  ${YELLOW}⚠${NC} Speech Dispatcher service may not be running properly"
            fi
            
            # Test audio output
            echo -e "${YELLOW}Testing audio system...${NC}"
            if command -v speaker-test >/dev/null 2>&1; then
                echo -e "${CYAN}Running brief audio test (2 seconds)...${NC}"
                timeout 2s speaker-test -t sine -f 1000 -l 1 2>/dev/null || echo -e "${YELLOW}Audio test completed (or no audio device available)${NC}"
            fi
            
            echo -e "${GREEN}✓ Dependencies installation completed!${NC}"
            echo ""
        else
            echo -e "${YELLOW}Skipping package installation. TTS may not work properly.${NC}"
            echo -e "${CYAN}You can install them manually later with:${NC}"
            echo -e "${WHITE}sudo apt update && sudo apt install ${missing_packages[*]}${NC}"
            echo ""
        fi
    else
        echo -e "${GREEN}✓ All required packages are already installed!${NC}"
    fi
    
    # Additional audio system checks
    echo -e "${YELLOW}Performing audio system checks...${NC}"
    
    # Check if audio devices are available
    if command -v aplay >/dev/null 2>&1; then
        local audio_devices=$(aplay -l 2>/dev/null | grep -c "card" || echo "0")
        if [[ "$audio_devices" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} Audio devices found ($audio_devices)"
        else
            echo -e "  ${YELLOW}⚠${NC} No audio devices detected"
        fi
    fi
    
    # Check PulseAudio/PipeWire status
    if command -v pulseaudio >/dev/null 2>&1 || command -v pipewire >/dev/null 2>&1; then
        if pgrep -x "pulseaudio" > /dev/null || pgrep -x "pipewire" > /dev/null; then
            echo -e "  ${GREEN}✓${NC} Audio system is running (PulseAudio/PipeWire)"
        else
            echo -e "  ${YELLOW}⚠${NC} Audio system is not running"
        fi
    fi
    
    # Check if pactl (PulseAudio control) works
    if command -v pactl >/dev/null 2>&1; then
        if pactl info >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} PulseAudio control interface is working"
        else
            echo -e "  ${YELLOW}⚠${NC} PulseAudio control interface not responding"
        fi
    fi
    
    echo ""
}

# Function to speak text using spd-say or fallback TTS engines
speak_text() {
    local text="$1"
    local priority="${2:-text}"  # Default priority is 'text'
    
    if [[ "$TTS_ENABLED" == true ]]; then
        # Clean the text of ANSI color codes for speech
        local clean_text=$(echo "$text" | sed 's/\x1b\[[0-9;]*m//g')
        
        # Kill any existing TTS processes to prevent overlap
        pkill -f "spd-say" 2>/dev/null || true
        pkill -f "espeak" 2>/dev/null || true
        
        # Try spd-say first if no fallback is set
        if [[ -z "$TTS_FALLBACK" ]] && command -v spd-say >/dev/null 2>&1; then
            # Use spd-say with wait flag to prevent overlapping
            timeout 10s spd-say \
                --voice-type "$TTS_VOICE" \
                --rate "$TTS_RATE" \
                --pitch "$TTS_PITCH" \
                --volume "$TTS_VOLUME" \
                --punctuation-mode "$TTS_PUNCTUATION" \
                --priority "$priority" \
                --wait \
                "$clean_text" 2>/dev/null
        
        # Use fallback TTS engines
        elif [[ "$TTS_FALLBACK" == "espeak" ]] && command -v espeak >/dev/null 2>&1; then
            # Use espeak directly with similar settings
            local espeak_rate=$((TTS_RATE + 175))  # Convert spd-say rate to espeak rate (approx)
            # Ensure espeak_rate is within valid range (80-450)
            if [[ $espeak_rate -lt 80 ]]; then espeak_rate=80; fi
            if [[ $espeak_rate -gt 450 ]]; then espeak_rate=450; fi
            
            timeout 10s espeak \
                -s "$espeak_rate" \
                -p "$((TTS_PITCH + 50))" \
                -a "$((TTS_VOLUME * 20))" \
                -v "en+f3" \
                "$clean_text" 2>/dev/null
            
        elif [[ "$TTS_FALLBACK" == "festival" ]] && command -v festival >/dev/null 2>&1; then
            # Use festival for TTS
            timeout 10s echo "$clean_text" | festival --tts 2>/dev/null
        fi
    fi
}

# Function to display and speak messages
announce() {
    local message="$1"
    local color="${2:-$WHITE}"
    local priority="${3:-text}"
    
    echo -e "${color}${message}${NC}"
    speak_text "$message" "$priority"
}

# Function to check if Speech Dispatcher is available
check_tts_availability() {
    if ! command -v spd-say >/dev/null 2>&1; then
        echo -e "${RED}Warning: spd-say (Speech Dispatcher) not found!${NC}"
        echo -e "${YELLOW}Text-to-speech will be disabled.${NC}"
        echo -e "${CYAN}To install Speech Dispatcher on Ubuntu/Debian:${NC}"
        echo -e "${WHITE}sudo apt update && sudo apt install speech-dispatcher${NC}"
        echo ""
        TTS_ENABLED=false
        echo -e "${WHITE}Press Enter to continue without TTS, or Ctrl+C to exit and install Speech Dispatcher...${NC}"
        read
        return 1
    fi
    
    echo -e "${YELLOW}Testing Speech Dispatcher functionality...${NC}"
    
    # Test if Speech Dispatcher is actually working with multiple methods
    local spd_working=false
    
    # Method 1: Test with spd-say directly
    echo -e "${CYAN}Testing spd-say directly...${NC}"
    if timeout 5s spd-say -w "Testing speech" 2>/dev/null; then
        echo -e "${GREEN}✓ spd-say direct test successful${NC}"
        spd_working=true
    else
        echo -e "${RED}✗ spd-say direct test failed${NC}"
    fi
    
    # Method 2: Test with different TTS engines if spd-say failed
    if [[ "$spd_working" == false ]]; then
        echo -e "${CYAN}Testing alternative TTS engines...${NC}"
        
        # Try espeak directly
        if command -v espeak >/dev/null 2>&1; then
            echo -e "${YELLOW}Trying espeak directly...${NC}"
            if timeout 3s espeak "Testing espeak" 2>/dev/null; then
                echo -e "${GREEN}✓ espeak works directly${NC}"
                # Update speak_text function to use espeak as fallback
                TTS_FALLBACK="espeak"
                spd_working=true
            else
                echo -e "${RED}✗ espeak test failed${NC}"
            fi
        fi
        
        # Try festival if espeak failed
        if [[ "$spd_working" == false ]] && command -v festival >/dev/null 2>&1; then
            echo -e "${YELLOW}Trying festival...${NC}"
            if timeout 3s echo "Testing festival" | festival --tts 2>/dev/null; then
                echo -e "${GREEN}✓ festival works${NC}"
                TTS_FALLBACK="festival"
                spd_working=true
            else
                echo -e "${RED}✗ festival test failed${NC}"
            fi
        fi
    fi
    
    # Final result
    if [[ "$spd_working" == true ]]; then
        echo -e "${GREEN}✓ Text-to-speech is working!${NC}"
        TTS_ENABLED=true
        if [[ -n "$TTS_FALLBACK" ]]; then
            echo -e "${YELLOW}Note: Using $TTS_FALLBACK as fallback TTS engine${NC}"
        fi
        return 0
    else
        echo -e "${RED}Warning: Speech Dispatcher found but not working properly!${NC}"
        echo -e "${YELLOW}This might be due to audio system issues or configuration problems.${NC}"
        echo -e "${CYAN}Troubleshooting steps:${NC}"
        echo -e "${WHITE}1. Check if PulseAudio is running: pulseaudio --check${NC}"
        echo -e "${WHITE}2. Test audio: speaker-test -c2 -t wav${NC}"
        echo -e "${WHITE}3. Restart Speech Dispatcher: sudo systemctl restart speech-dispatcher${NC}"
        echo -e "${WHITE}4. Check Speech Dispatcher status: systemctl status speech-dispatcher${NC}"
        echo ""
        TTS_ENABLED=false
        echo -e "${WHITE}Press Enter to continue without TTS...${NC}"
        read
        return 1
    fi
}

# Function to test TTS and let user adjust settings
test_and_configure_tts() {
    if [[ "$TTS_ENABLED" == true ]]; then
        announce "Welcome to the Ultrabunt Accessible Installer!" "$GREEN" "important"
        announce "This installer includes text-to-speech support for visually impaired users." "$CYAN"
        
        echo ""
        announce "Testing your text-to-speech settings..." "$YELLOW"
        speak_text "This is a test of the text to speech system. Can you hear this clearly?"
        
        # Give time for speech to complete
        sleep 2
        
        echo ""
        echo -e "${WHITE}TTS Settings Test Complete${NC}"
        echo -e "${CYAN}Current settings:${NC}"
        echo -e "  Voice: ${WHITE}$TTS_VOICE${NC} (friendly female voice)"
        echo -e "  Speed: ${WHITE}$TTS_RATE${NC} (slightly slower for clarity)"
        echo -e "  Volume: ${WHITE}$TTS_VOLUME${NC} (slightly louder)"
        echo -e "  Punctuation: ${WHITE}$TTS_PUNCTUATION${NC} (reads some punctuation)"
        echo ""
        
        while true; do
            echo -e "${YELLOW}TTS Configuration Options:${NC}"
            echo -e "  ${WHITE}1)${NC} Continue with current settings"
            echo -e "  ${WHITE}2)${NC} Make voice slower"
            echo -e "  ${WHITE}3)${NC} Make voice faster"
            echo -e "  ${WHITE}4)${NC} Make voice louder"
            echo -e "  ${WHITE}5)${NC} Make voice quieter"
            echo -e "  ${WHITE}6)${NC} Test current settings again"
            echo -e "  ${WHITE}7)${NC} Disable TTS and continue silently"
            echo ""
            
            read -p "Choose an option (1-7): " choice
            speak_text "You selected option $choice"
            
            case $choice in
                1)
                    announce "Continuing with current TTS settings." "$GREEN"
                    break
                    ;;
                2)
                    TTS_RATE="-40"
                    announce "Voice speed set to slower. Testing..." "$CYAN"
                    # Update Speech Dispatcher config if needed
                    update_spd_config
                    speak_text "This is the new slower speed setting."
                    sleep 3
                    ;;
                3)
                    TTS_RATE="0"
                    announce "Voice speed set to normal. Testing..." "$CYAN"
                    # Update Speech Dispatcher config if needed
                    update_spd_config
                    speak_text "This is the normal speed setting."
                    sleep 3
                    ;;
                4)
                    TTS_VOLUME="30"
                    announce "Voice volume set to louder. Testing..." "$CYAN"
                    # Update Speech Dispatcher config if needed
                    update_spd_config
                    speak_text "This is the louder volume setting."
                    sleep 3
                    ;;
                5)
                    TTS_VOLUME="0"
                    announce "Voice volume set to normal. Testing..." "$CYAN"
                    # Update Speech Dispatcher config if needed
                    update_spd_config
                    speak_text "This is the normal volume setting."
                    sleep 3
                    ;;
                6)
                    announce "Testing current settings..." "$YELLOW"
                    speak_text "This is a test of your current text to speech settings. How does this sound?"
                    sleep 2
                    ;;
                7)
                    TTS_ENABLED=false
                    announce "Text-to-speech disabled. Continuing in silent mode." "$YELLOW"
                    break
                    ;;
                *)
                    announce "Invalid option. Please choose 1 through 7." "$RED"
                    ;;
            esac
        done
    fi
}

# Function to update Speech Dispatcher configuration with current settings
update_spd_config() {
    # Only update if we have a user config directory
    local actual_user="${SUDO_USER:-$USER}"
    if [[ -n "$actual_user" && "$actual_user" != "root" ]]; then
        local user_spd_dir="/home/$actual_user/.config/speech-dispatcher"
        
        # Update the main config file if it exists
        if [[ -f "$user_spd_dir/speechd.conf" ]]; then
            # Update rate setting
            sed -i "s/^DefaultRate.*/DefaultRate $TTS_RATE/" "$user_spd_dir/speechd.conf" 2>/dev/null || true
            # Update volume setting  
            sed -i "s/^DefaultVolume.*/DefaultVolume $TTS_VOLUME/" "$user_spd_dir/speechd.conf" 2>/dev/null || true
        fi
        
        # Update espeak module config if it exists
        if [[ -f "$user_spd_dir/modules/espeak.conf" ]]; then
            sed -i "s/^EspeakRate.*/EspeakRate $TTS_RATE/" "$user_spd_dir/modules/espeak.conf" 2>/dev/null || true
            sed -i "s/^EspeakVolume.*/EspeakVolume $TTS_VOLUME/" "$user_spd_dir/modules/espeak.conf" 2>/dev/null || true
        fi
        
        # Restart Speech Dispatcher to apply changes
        systemctl restart speech-dispatcher 2>/dev/null || true
        sleep 1
    fi
}

# Function to provide audio navigation help
provide_navigation_help() {
    announce "Navigation Help for Ultrabunt Installer" "$CYAN" "important"
    announce "This installer uses numbered menus for easy navigation." "$WHITE"
    announce "Simply type the number of your choice and press Enter." "$WHITE"
    announce "You can always type 'help' for assistance, or 'quit' to exit." "$WHITE"
    announce "The installer will read all options aloud before asking for your choice." "$WHITE"
    echo ""
}

# Function to announce menu options with audio
announce_menu_options() {
    local menu_title="$1"
    shift
    local options=("$@")
    
    announce "$menu_title" "$GREEN" "important"
    announce "Available options:" "$CYAN"
    
    for i in "${!options[@]}"; do
        local option_num=$((i + 1))
        announce "Option $option_num: ${options[$i]}" "$WHITE"
        # Small pause between options for clarity
        sleep 0.3
    done
    
    echo ""
    announce "Please enter your choice:" "$YELLOW"
}

# Main function
main() {
    clear
    
    # Check if we're running on a Linux system
    if [[ "$(uname)" != "Linux" ]]; then
        announce "Error: This accessible installer is designed for Linux systems only." "$RED" "important"
        announce "The main ultrabunt.sh script may work on other systems." "$YELLOW"
        exit 1
    fi
    
    # Install TTS dependencies if needed (requires sudo)
    if [[ "$EUID" -eq 0 ]]; then
        install_tts_dependencies
    else
        echo -e "${YELLOW}Note: Running without sudo. If TTS doesn't work, try: sudo ./ultrabunt-accessible.sh${NC}"
        echo ""
    fi
    
    # Check TTS availability
    check_tts_availability
    
    # Welcome and TTS configuration
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                    ULTRABUNT ACCESSIBLE INSTALLER                            ║${NC}"
    echo -e "${PURPLE}║                   Enhanced for Visually Impaired Users                       ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ "$TTS_ENABLED" == true ]]; then
        test_and_configure_tts
        provide_navigation_help
        
        # Ask if user wants to continue
        announce "Are you ready to start the Ultrabunt installation?" "$GREEN"
        announce "Type 'yes' to continue, 'help' for more information, or 'no' to exit." "$CYAN"
        
        while true; do
            read -p "Your choice: " user_response
            speak_text "You entered: $user_response"
            
            case "${user_response,,}" in
                yes|y)
                    announce "Starting Ultrabunt installer with accessibility features enabled." "$GREEN" "important"
                    break
                    ;;
                help|h)
                    provide_navigation_help
                    announce "Type 'yes' to continue or 'no' to exit." "$CYAN"
                    ;;
                no|n|quit|exit)
                    announce "Exiting Ultrabunt accessible installer. Goodbye!" "$YELLOW" "important"
                    exit 0
                    ;;
                *)
                    announce "Please type 'yes' to continue, 'help' for information, or 'no' to exit." "$RED"
                    ;;
            esac
        done
    else
        echo -e "${YELLOW}Running in silent mode (TTS disabled)${NC}"
        echo -e "${WHITE}Press Enter to continue with the standard installer...${NC}"
        read
    fi
    
    # Export TTS settings for the main script to use
    export ULTRABUNT_TTS_ENABLED="$TTS_ENABLED"
    export ULTRABUNT_TTS_VOICE="$TTS_VOICE"
    export ULTRABUNT_TTS_RATE="$TTS_RATE"
    export ULTRABUNT_TTS_PITCH="$TTS_PITCH"
    export ULTRABUNT_TTS_VOLUME="$TTS_VOLUME"
    export ULTRABUNT_TTS_PUNCTUATION="$TTS_PUNCTUATION"
    
    # Launch the main Ultrabunt script
    announce "Loading main Ultrabunt installer..." "$GREEN" "important"
    
    # Check if main script exists
    if [[ -f "./ultrabunt.sh" ]]; then
        # Make sure it's executable
        chmod +x ./ultrabunt.sh
        
        # Run the main script with accessibility enhancements
        ./ultrabunt.sh "$@"
    else
        announce "Error: ultrabunt.sh not found in current directory!" "$RED" "important"
        announce "Please ensure both scripts are in the same directory." "$YELLOW"
        exit 1
    fi
}

# Handle script interruption gracefully
trap 'announce "Installation interrupted by user. Goodbye!" "$YELLOW" "important"; exit 130' INT

# Only run main when executed directly, not when sourced for tests
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"