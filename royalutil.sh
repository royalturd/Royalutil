#!/bin/bash

################################################################################
# Script Name: Royalutil
# Description: Interactive System Utility for Linux Setup & Optimization
# Author:      Royalturd
# Repository:  https://github.com/royalturd/Royalutil
################################################################################

LOG_FILE="$HOME/royalutil_setup.log"
NON_INTERACTIVE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ICON_UPDATE="🔄"
ICON_GIT="󰊤"
ICON_BREW="🍺"
ICON_SHELL="🐚"
ICON_FLATPAK="📦"
ICON_TOOL="🛠️"
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
ICON_QUESTION="❓"

print_header() {
    local title=$1
    echo -e "\n${BOLD}${PURPLE}# $title${NC}"
    echo -e "${PURPLE}$(printf '%.s─' $(seq 1 $((${#title} + 2))))${NC}"
}

success_msg() { echo -e "${GREEN}${ICON_SUCCESS} $1${NC}"; }
error_msg() { echo -e "${RED}${ICON_ERROR} $1${NC}" | tee -a "$LOG_FILE"; }
warn_msg() { echo -e "${YELLOW}${ICON_WARN} $1${NC}"; }
info_msg() { echo -e "${CYAN}${ICON_INFO} $1${NC}"; }
ask_user() {
    if [ "$NON_INTERACTIVE" = true ]; then return 0; fi
    local prompt=$1
    echo -ne "${BOLD}${YELLOW}${ICON_QUESTION} $prompt (Y/N): ${NC}"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

[ -f "$LOG_FILE" ] && rm "$LOG_FILE"
# Redirect errors to the log file via helper functions, not global exec

check_dependencies() {
    local deps=("curl" "git" "sudo")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error_msg "Dependency missing: $dep. Please install it first."
            exit 1
        fi
    done
    check_network
}

show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    local bar=$(printf "%${completed}s" | tr ' ' '█')
    local space=$(printf "%${remaining}s" | tr ' ' '░')
    
    echo -ne "\r${BOLD}${BLUE}Progress: [${bar}${space}] ${percentage}% (${current}/${total})${NC}"
}

check_network() {
    info_msg "Checking network connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error_msg "No internet connection detected. Some modules may fail."
        if ! ask_user "Continue anyway?"; then
            exit 1
        fi
    else
        success_msg "Network connection verified."
    fi
}

append_if_missing() {
    local file=$1
    local line=$2
    local marker_start="# [Royalutil Start]"
    local marker_end="# [Royalutil End]"

    if [ ! -f "$file" ]; then touch "$file"; fi

    if ! grep -qF "$line" "$file"; then
        if ! grep -qF "$marker_start" "$file"; then
            {
                echo ""
                echo "$marker_start"
                echo "$line"
                echo "$marker_end"
            } >> "$file"
        else
            sed -i "/$marker_end/i $line" "$file"
        fi
    fi
}


maintenance() {
    print_header "System Maintenance"
    if ask_user "Update package lists and upgrade system?"; then
        info_msg "${ICON_UPDATE} Refreshing package lists and upgrading system..."
        sudo apt update
        sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
        sudo apt autoremove -y
        success_msg "System is now up to date."
    fi
}

setup_editor() {
    print_header "Default Code Editor"
    if ask_user "Set Nano as default code editor?"; then
        info_msg "${ICON_TOOL} Setting Nano as default code editor..."
        export EDITOR=nano
        export VISUAL=nano

        for file in "$HOME/.zshrc" "$HOME/.bashrc"; do
            [ -f "$file" ] && append_if_missing "$file" 'export EDITOR="nano"'
            [ -f "$file" ] && append_if_missing "$file" 'export VISUAL="nano"'
        done
        success_msg "Nano is now your default system editor."
    fi
}

install_git() {
    print_header "Git Setup"
    if ! command -v git &> /dev/null; then
        if ask_user "Install Git?"; then
            info_msg "Installing Git..."
            sudo apt update && sudo apt install git -y
        fi
    else
        success_msg "Git is already installed."
    fi

    if command -v git &> /dev/null; then
        if ask_user "Configure global Git settings?"; then
            git config --global core.editor "nano"
            git config --global credential.helper 'cache --timeout=99999'
            success_msg "Git global settings applied."
        fi

        if ask_user "Configure Git identity?"; then
            read -p "Name: " git_name
            read -p "Email: " git_email
            git config --global user.name "$git_name"
            git config --global user.email "$git_email"
            success_msg "Git identity configured."
        fi
    fi
}

setup_brew() {
    print_header "Homebrew Package Manager"
    if ! command -v brew &> /dev/null; then
        if ask_user "Install Homebrew?"; then
            info_msg "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Set up brew environment locally for the current session
            if [ -d "/home/linuxbrew/.linuxbrew" ]; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            elif [ -d "$HOME/.linuxbrew" ]; then
                eval "$($HOME/.linuxbrew/bin/brew shellenv)"
            fi
        fi
    else
        success_msg "Homebrew is already installed."
    fi
}

setup_zsh() {
    print_header "Zsh Shell"
    if ! command -v zsh &> /dev/null; then
        if ask_user "Install Zsh?"; then
            info_msg "Installing Zsh..."
            if command -v brew &> /dev/null; then brew install zsh; else sudo apt install zsh -y; fi
            success_msg "Zsh installed."
            
            if ask_user "Set Zsh as default shell?"; then
                chsh -s "$(which zsh)"
                success_msg "Zsh set as default shell."
            fi
        fi
    else
        success_msg "Zsh is already installed."
    fi

    if command -v zsh &> /dev/null; then
        if ask_user "Install Zsh enhancements?"; then
            if command -v brew &> /dev/null; then
                brew install zsh-autosuggestions zsh-syntax-highlighting
                ZSHRC="$HOME/.zshrc"
                append_if_missing "$ZSHRC" 'source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
                append_if_missing "$ZSHRC" 'source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
                success_msg "Zsh enhancements configured."
            else
                warn_msg "Homebrew required for Zsh enhancements in this script."
            fi
        fi
    fi
}

install_flatpak() {
    print_header "Flatpak Framework"
    if ! command -v flatpak &> /dev/null; then
        if ask_user "Install Flatpak?"; then
            sudo apt install flatpak -y
            sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            success_msg "Flatpak installed and configured."
        fi
    else
        success_msg "Flatpak is already installed."
    fi
}

install_apps() {
    print_header "Applications (Flatpak & Spotify)"
    if ask_user "Install essential applications?"; then
        if command -v flatpak &> /dev/null; then
            local apps=(
                "com.bitwarden.desktop"
                "com.visualstudio.code"
                "com.stremio.Stremio"
                "io.github.flattool.Warehouse"
                "io.github.getnf.Bazaar"
                "org.mozilla.FirefoxNightly"
            )
            for app in "${apps[@]}"; do
                if ! flatpak list | grep -q "$app"; then
                    info_msg "Installing $app..."
                    flatpak install flathub "$app" -y
                fi
            done
        fi

        # Spotify
        if ! command -v spotify &> /dev/null; then
            if ask_user "Install Spotify?"; then
                curl -sS https://download.spotify.com/debian/pubkey_C85661D9C2FE1440.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
                sudo apt update && sudo apt install spotify-client -y
            fi
        fi

        # Spicetify
        if ! command -v spicetify &> /dev/null; then
            if ask_user "Install Spicetify?"; then
                curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh
                curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
                [ -d "/usr/share/spotify" ] && sudo chmod a+wr /usr/share/spotify && sudo chmod a+wr /usr/share/spotify/Apps -R
            fi
        fi
    fi
}

install_utilities() {
    print_header "System Utilities"
    local tools=("fzf" "fastfetch" "btop" "zellij" "atuin")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            if ask_user "Install $tool?"; then
                if [ "$tool" == "fastfetch" ]; then sudo add-apt-repository ppa:zhangsongcui3371/fastfetch -y && sudo apt update; fi
                if [ "$tool" == "atuin" ]; then
                    curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | sh
                else
                    sudo apt install "$tool" -y 2>/dev/null || brew install "$tool"
                fi
                success_msg "$tool installed."
            fi
        fi
    done
}

install_themes() {
    print_header "Bootloader Themes"
    if ask_user "Install Top-5 Bootloader Themes?"; then
        THEME_DIR="$HOME/.local/share/Top-5-Bootloader-Themes"
        mkdir -p "$HOME/.local/share"
        [ -d "$THEME_DIR" ] && rm -rf "$THEME_DIR"
        if git clone https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes "$THEME_DIR"; then
            chmod +x "$THEME_DIR/install.sh"
            sudo "$THEME_DIR/install.sh"
            success_msg "Bootloader themes installed."
        fi
    fi
}


show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help            Show this help message.
  -y, --non-interactive Run all modules without user prompts.

Modules available:
  - System Maintenance
  - Default Code Editor (Nano)
  - Git Setup
  - Homebrew Setup
  - Zsh & Enhancements
  - Flatpak Framework
  - Applications (Spotify, VS Code, etc.)
  - System Utilities (fzf, btop, etc.)
  - Bootloader Themes
EOF
    exit 0
}

run_tui() {
    if ! command -v fzf &> /dev/null; then
        warn_msg "fzf not found. Falling back to simple menu."
        run_fallback_menu
        return
    fi

    local options=(
        "1. System Maintenance"
        "2. Default Code Editor"
        "3. Git Setup"
        "4. Homebrew Setup"
        "5. Zsh & Enhancements"
        "6. Flatpak Framework"
        "7. Applications"
        "8. System Utilities"
        "9. Bootloader Themes"
        "All. Run Full Setup"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" | fzf --multi --header="👑 Royalutil - Select modules (TAB to multi-select)" --prompt="> " --border --margin=1% --padding=1 --layout=reverse --height=80%)

    if [[ -z "$choice" ]]; then
        info_msg "No modules selected. Exiting."
        exit 0
    fi

    if [[ "$choice" == *"All. Run Full Setup"* ]]; then
        run_full_setup
    else
        local selected=()
        [[ "$choice" == *"1. System Maintenance"* ]] && selected+=("maintenance")
        [[ "$choice" == *"2. Default Code Editor"* ]] && selected+=("setup_editor")
        [[ "$choice" == *"3. Git Setup"* ]] && selected+=("install_git")
        [[ "$choice" == *"4. Homebrew Setup"* ]] && selected+=("setup_brew")
        [[ "$choice" == *"5. Zsh & Enhancements"* ]] && selected+=("setup_zsh")
        [[ "$choice" == *"6. Flatpak Framework"* ]] && selected+=("install_flatpak")
        [[ "$choice" == *"7. Applications"* ]] && selected+=("install_apps")
        [[ "$choice" == *"8. System Utilities"* ]] && selected+=("install_utilities")
        [[ "$choice" == *"9. Bootloader Themes"* ]] && selected+=("install_themes")

        local total=${#selected[@]}
        local count=0
        for task in "${selected[@]}"; do
            count=$((count + 1))
            info_msg "Running module: $task..."
            $task
            echo ""
            show_progress "$count" "$total"
            echo -e "\n"
        done
    fi
}

run_fallback_menu() {
    echo -e "\n${BOLD}Select a module to run:${NC}"
    echo "1. System Maintenance"
    echo "2. Default Code Editor"
    echo "3. Git Setup"
    echo "4. Homebrew Setup"
    echo "5. Zsh & Enhancements"
    echo "6. Flatpak Framework"
    echo "7. Applications"
    echo "8. System Utilities"
    echo "9. Bootloader Themes"
    echo "10. Full Setup"
    echo "0. Exit"
    
    read -p "Choice: " choice
    case $choice in
        1) maintenance ;;
        2) setup_editor ;;
        3) install_git ;;
        4) setup_brew ;;
        5) setup_zsh ;;
        6) install_flatpak ;;
        7) install_apps ;;
        8) install_utilities ;;
        9) install_themes ;;
        10) run_full_setup ;;
        0) exit 0 ;;
        *) warn_msg "Invalid choice." ;;
    esac
}

run_full_setup() {
    local tasks=(
        "maintenance"
        "setup_editor"
        "install_git"
        "setup_brew"
        "setup_zsh"
        "install_flatpak"
        "install_apps"
        "install_utilities"
        "install_themes"
    )
    local total=${#tasks[@]}
    local count=0
    for task in "${tasks[@]}"; do
        count=$((count + 1))
        info_msg "Running module: $task..."
        $task
        echo ""
        show_progress "$count" "$total"
        echo -e "\n"
    done
}


# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -y|--non-interactive) NON_INTERACTIVE=true ;;
    esac
    shift
done

clear
echo -e "${CYAN}"
cat << "EOF"
  ____                  _       _   _ _ 
 |  _ \ ___  _   _  __ _| |_   _| |_(_) |
 | |_) / _ \| | | |/ _` | | | | | __| | |
 |  _ < (_) | |_| | (_| | | |_| | |_| | |
 |_| \_\___/ \__, |\__,_|_|\__,_|\__|_|_|
             |___/                       
EOF
echo -e "${BOLD}${BLUE}           Interactive System Utility${NC}"
echo -e "${PURPLE}───────────────────────────────────────────────${NC}"

check_dependencies

if [ "$NON_INTERACTIVE" = true ]; then
    run_full_setup
else
    run_tui
fi

echo -e "\n${BOLD}${BLUE}=== Royalutil Setup Complete! ===${NC}"
command -v fastfetch &> /dev/null && fastfetch
info_msg "Error log saved to: ${BOLD}$LOG_FILE${NC}"
echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Setup finished. Please restart your terminal session.${NC}"
