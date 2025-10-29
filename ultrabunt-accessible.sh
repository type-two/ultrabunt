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

# Function to speak text using spd-say
speak_text() {
    local text="$1"
    local priority="${2:-text}"  # Default priority is 'text'
    
    if [[ "$TTS_ENABLED" == true ]] && command -v spd-say >/dev/null 2>&1; then
        # Clean the text of ANSI color codes for speech
        local clean_text=$(echo "$text" | sed 's/\x1b\[[0-9;]*m//g')
        
        spd-say \
            --voice-type "$TTS_VOICE" \
            --rate "$TTS_RATE" \
            --pitch "$TTS_PITCH" \
            --volume "$TTS_VOLUME" \
            --punctuation-mode "$TTS_PUNCTUATION" \
            --priority "$priority" \
            --wait \
            "$clean_text" 2>/dev/null
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
        read -p "Press Enter to continue without TTS, or Ctrl+C to exit and install Speech Dispatcher..."
        return 1
    fi
    return 0
}

# Function to test TTS and let user adjust settings
test_and_configure_tts() {
    if [[ "$TTS_ENABLED" == true ]]; then
        announce "Welcome to the Ultrabunt Accessible Installer!" "$GREEN" "important"
        announce "This installer includes text-to-speech support for visually impaired users." "$CYAN"
        
        echo ""
        announce "Testing your text-to-speech settings..." "$YELLOW"
        speak_text "This is a test of the text to speech system. Can you hear this clearly?"
        
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
                    speak_text "This is the new slower speed setting."
                    ;;
                3)
                    TTS_RATE="0"
                    announce "Voice speed set to normal. Testing..." "$CYAN"
                    speak_text "This is the normal speed setting."
                    ;;
                4)
                    TTS_VOLUME="30"
                    announce "Voice volume set to louder. Testing..." "$CYAN"
                    speak_text "This is the louder volume setting."
                    ;;
                5)
                    TTS_VOLUME="0"
                    announce "Voice volume set to normal. Testing..." "$CYAN"
                    speak_text "This is the normal volume setting."
                    ;;
                6)
                    announce "Testing current settings..." "$YELLOW"
                    speak_text "This is a test of your current text to speech settings. How does this sound?"
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
    
    # Check TTS availability
    check_tts_availability
    
    # Welcome and TTS configuration
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                    ULTRABUNT ACCESSIBLE INSTALLER                            ║${NC}"
    echo -e "${PURPLE}║                   Enhanced for Visually Impaired Users                      ║${NC}"
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

# Run main function with all arguments
main "$@"