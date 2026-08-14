#!/bin/bash

################################################################################
# Script Name: Royalutil
# Description: Interactive System Utility for Linux Setup & Optimization
# Author:      Royalturd
# Repository:  https://github.com/royalturd/Royalutil
################################################################################

LOG_FILE="$HOME/royalutil_setup.log"
NON_INTERACTIVE=false
UNINSTALL_MODE=false
DRY_RUN=false
MODULES_ARG=""

SCRIPT_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
CONFIG_FILE="${ROYALUTIL_CONFIG:-${SCRIPT_SELF_DIR:+$SCRIPT_SELF_DIR/royalutil.conf}}"

# id|Display Name|Description entries, populated by load_catalog().
FLATPAK_CATALOG=()
UTIL_CATALOG=()

DEFAULT_FLATPAK_CATALOG=(
    "com.bitwarden.desktop|Bitwarden|Password manager"
    "com.visualstudio.code|VS Code|Code editor"
    "com.stremio.Stremio|Stremio|Media center / streaming"
    "io.github.flattool.Warehouse|Warehouse|Flatpak app manager"
    "io.github.getnf.Bazaar|Bazaar|Nerd Font manager"
    "org.mozilla.FirefoxNightly|Firefox Nightly|Web browser"
)
DEFAULT_UTIL_CATALOG=(
    "fzf|fzf|Fuzzy finder"
    "fastfetch|fastfetch|System info tool"
    "btop|btop|Resource monitor"
    "zellij|zellij|Terminal multiplexer"
    "atuin|Atuin|Shell history sync"
)

# Reads royalutil.conf ([flatpak] / [utilities] sections, id|Name|Desc lines)
# into FLATPAK_CATALOG / UTIL_CATALOG, falling back to the built-in defaults
# above when the file is missing or a section is empty.
load_catalog() {
    FLATPAK_CATALOG=()
    UTIL_CATALOG=()
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        local section="" line
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            case "$line" in
                ''|'#'*) continue ;;
                '['*']')
                    section="${line#[}"
                    section="${section%]}"
                    continue
                    ;;
            esac
            case "$section" in
                flatpak) FLATPAK_CATALOG+=("$line") ;;
                utilities) UTIL_CATALOG+=("$line") ;;
            esac
        done < "$CONFIG_FILE"
    fi
    [ "${#FLATPAK_CATALOG[@]}" -eq 0 ] && FLATPAK_CATALOG=("${DEFAULT_FLATPAK_CATALOG[@]}")
    [ "${#UTIL_CATALOG[@]}" -eq 0 ] && UTIL_CATALOG=("${DEFAULT_UTIL_CATALOG[@]}")
}

# Filters a "id|Name|Desc" catalog array down to the ids listed in a
# comma-separated string, preserving catalog order. Echoes nothing (fills
# a nameref-free global via stdout, one id per line) - callers capture with
# a `while read` loop or mapfile.
catalog_filter_ids() {
    local -n _catalog=$1
    local wanted=$2
    local entry id want
    local IFS=','
    for want in $wanted; do
        for entry in "${_catalog[@]}"; do
            id="${entry%%|*}"
            if [ "$id" = "$want" ]; then
                printf '%s\n' "$entry"
                break
            fi
        done
    done
}

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
ICON_FONT="🔤"

print_header() {
    local title=$1
    echo -e "\n${BOLD}${PURPLE}# $title${NC}"
    echo -e "${PURPLE}$(printf '%.s─' $(seq 1 $((${#title} + 2))))${NC}"
}

success_msg() { 
    echo -e "${GREEN}${ICON_SUCCESS} $1${NC}"
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [SUCCESS] $1" >> "$LOG_FILE"
}
error_msg() { 
    echo -e "${RED}${ICON_ERROR} $1${NC}"
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [ERROR] $1" >> "$LOG_FILE"
}
warn_msg() { 
    echo -e "${YELLOW}${ICON_WARN} $1${NC}"
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [WARN] $1" >> "$LOG_FILE"
}
info_msg() { 
    echo -e "${CYAN}${ICON_INFO} $1${NC}"
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [INFO] $1" >> "$LOG_FILE"
}
ask_user() {
    if [ "$NON_INTERACTIVE" = true ]; then return 0; fi
    local prompt=$1
    echo -ne "${BOLD}${YELLOW}${ICON_QUESTION} $prompt (Y/N): ${NC}"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}
dry_run_notice() {
    echo -e "${YELLOW}${ICON_INFO} [DRY-RUN] Would: $1${NC}"
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [DRY-RUN] $1" >> "$LOG_FILE"
}

[ -f "$LOG_FILE" ] && rm "$LOG_FILE"
touch "$LOG_FILE"
# Redirect errors to the log file via helper functions, not global exec

cleanup() {
    echo -e "\n${RED}${ICON_WARN} Setup interrupted by user. Exiting gracefully...${NC}"
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [WARN] Setup interrupted by user." >> "$LOG_FILE"
    [[ -n "$SUDO_KEEP_ALIVE_PID" ]] && kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null
    exit 1
}
trap cleanup SIGINT SIGTERM

backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        local backup="${file}.bak_$(date +%F_%H-%M-%S)"
        cp "$file" "$backup"
        info_msg "Created backup of $file -> $backup"
    fi
}

check_dependencies() {
    if ! command -v apt &> /dev/null; then
        error_msg "This script currently requires 'apt' (Debian/Ubuntu-based system)."
        return 1
    fi

    local deps=("curl" "git" "sudo")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ "${#missing_deps[@]}" -gt 0 ]; then
        warn_msg "Missing dependencies: ${missing_deps[*]}"
        if ask_user "Would you like to install the missing dependencies?"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Install missing dependencies: ${missing_deps[*]}"
                return 0
            fi
            info_msg "Installing missing dependencies: ${missing_deps[*]}..."
            sudo apt update && sudo apt install -y "${missing_deps[@]}"

            # Re-check after installation
            for dep in "${missing_deps[@]}"; do
                if ! command -v "$dep" &> /dev/null; then
                    error_msg "Failed to install $dep. Please install it manually."
                    return 1
                fi
            done
            success_msg "All dependencies installed successfully."
        else
            error_msg "Dependencies are required to continue."
            return 1
        fi
    fi
    return 0
}

check_network() {
    info_msg "Checking network connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        warn_msg "No internet connection detected. Some modules may fail."
        if ! ask_user "Continue anyway?"; then
            return 1
        fi
    else
        success_msg "Network connection verified."
    fi
    return 0
}

if [[ "$(locale charmap 2>/dev/null)" == "UTF-8" ]]; then
    BAR_FULL="█"
    BAR_EMPTY="░"
else
    BAR_FULL="#"
    BAR_EMPTY="-"
fi

show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))

    local bar="" space=""
    for ((i=0; i<completed; i++)); do bar+="$BAR_FULL"; done
    for ((i=0; i<remaining; i++)); do space+="$BAR_EMPTY"; done

    echo -ne "\r${BOLD}${BLUE}Progress: [${bar}${space}] ${percentage}% (${current}/${total})${NC}"
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
            local tmp_file
            tmp_file=$(mktemp)
            awk -v marker="$marker_end" -v newline="$line" '
                index($0, marker) == 1 { print newline }
                { print }
            ' "$file" > "$tmp_file" && mv "$tmp_file" "$file"
        fi
    fi
}

remove_marker_block() {
    local file=$1
    local marker_start="# [Royalutil Start]"
    local marker_end="# [Royalutil End]"

    [ -f "$file" ] || return 0
    grep -qF "$marker_start" "$file" || return 0

    backup_file "$file"
    local tmp_file
    tmp_file=$(mktemp)
    awk -v s="$marker_start" -v e="$marker_end" '
        index($0, s) == 1 { skip=1 }
        skip != 1 { print }
        index($0, e) == 1 { skip=0; next }
    ' "$file" > "$tmp_file" && mv "$tmp_file" "$file"
    success_msg "Removed Royalutil-managed block from $file"
}


maintenance() {
    print_header "System Maintenance"
    if ask_user "Update package lists and upgrade system?"; then
        if [ "$DRY_RUN" = true ]; then
            dry_run_notice "Run 'apt update && apt upgrade -y && apt autoremove -y'"
            return
        fi
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
        if [ "$DRY_RUN" = true ]; then
            dry_run_notice "Set EDITOR/VISUAL to nano and append export lines to ~/.zshrc and ~/.bashrc"
            return
        fi
        info_msg "${ICON_TOOL} Setting Nano as default code editor..."
        export EDITOR=nano
        export VISUAL=nano

        for file in "$HOME/.zshrc" "$HOME/.bashrc"; do
            if [ -f "$file" ]; then
                backup_file "$file"
                append_if_missing "$file" 'export EDITOR="nano"'
                append_if_missing "$file" 'export VISUAL="nano"'
            fi
        done
        success_msg "Nano is now your default system editor."
    fi
}

install_git() {
    print_header "Git Setup"
    if ! command -v git &> /dev/null; then
        if ask_user "Install Git?"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Install git via apt"
            else
                info_msg "Installing Git..."
                sudo apt update && sudo apt install git -y
            fi
        fi
    else
        success_msg "Git is already installed."
    fi

    if command -v git &> /dev/null || [ "$DRY_RUN" = true ]; then
        if ask_user "Configure global Git settings?"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Set git core.editor=nano and credential.helper cache"
            else
                git config --global core.editor "nano"
                git config --global credential.helper 'cache --timeout=99999'
                success_msg "Git global settings applied."
            fi
        fi

        if [ "$NON_INTERACTIVE" = true ]; then
            if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
                if [ "$DRY_RUN" = true ]; then
                    dry_run_notice "Set git user.name=\"$GIT_NAME\" and user.email=\"$GIT_EMAIL\""
                else
                    git config --global user.name "$GIT_NAME"
                    git config --global user.email "$GIT_EMAIL"
                    success_msg "Git identity configured."
                fi
            else
                info_msg "Skipping Git identity (set GIT_NAME/GIT_EMAIL to configure non-interactively)."
            fi
        elif ask_user "Configure Git identity?"; then
            local git_name git_email
            read -p "Name: " git_name
            read -p "Email: " git_email
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Set git user.name=\"$git_name\" and user.email=\"$git_email\""
            else
                git config --global user.name "$git_name"
                git config --global user.email "$git_email"
                success_msg "Git identity configured."
            fi
        fi
    fi
}

setup_brew() {
    print_header "Homebrew Package Manager"
    if ! command -v brew &> /dev/null; then
        if ask_user "Install Homebrew?"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Install Homebrew via the official install script"
                return
            fi
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
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Install zsh via brew/apt"
            else
                info_msg "Installing Zsh..."
                if command -v brew &> /dev/null; then brew install zsh; else sudo apt install zsh -y; fi
                success_msg "Zsh installed."
            fi

            if ask_user "Set Zsh as default shell?"; then
                if [ "$DRY_RUN" = true ]; then
                    dry_run_notice "Set default shell to zsh (chsh)"
                else
                    chsh -s "$(which zsh)"
                    success_msg "Zsh set as default shell."
                fi
            fi
        fi
    else
        success_msg "Zsh is already installed."
    fi

    if command -v zsh &> /dev/null || [ "$DRY_RUN" = true ]; then
        if ask_user "Install Zsh enhancements?"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Install zsh-autosuggestions/zsh-syntax-highlighting via brew and append source lines to ~/.zshrc"
            elif command -v brew &> /dev/null; then
                brew install zsh-autosuggestions zsh-syntax-highlighting
                ZSHRC="$HOME/.zshrc"
                backup_file "$ZSHRC"
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
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Install flatpak and add the Flathub remote"
            else
                sudo apt install flatpak -y
                sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
                success_msg "Flatpak installed and configured."
            fi
        fi
    else
        success_msg "Flatpak is already installed."
    fi
}

install_apps() {
    print_header "Applications (Flatpak & Spotify)"
    load_catalog
    if ask_user "Install essential applications?"; then
        if command -v flatpak &> /dev/null; then
            local entries=()
            if [ -n "$ROYALUTIL_APPS" ]; then
                mapfile -t entries < <(catalog_filter_ids FLATPAK_CATALOG "$ROYALUTIL_APPS")
            else
                entries=("${FLATPAK_CATALOG[@]}")
            fi
            local entry app
            for entry in "${entries[@]}"; do
                app="${entry%%|*}"
                if ! flatpak list | grep -q "$app"; then
                    if [ "$DRY_RUN" = true ]; then
                        dry_run_notice "Install Flatpak app $app"
                    else
                        info_msg "Installing $app..."
                        flatpak install flathub "$app" -y
                    fi
                fi
            done
        fi

        # Spotify
        if ! command -v spotify &> /dev/null; then
            if ask_user "Install Spotify?"; then
                if [ "$DRY_RUN" = true ]; then
                    dry_run_notice "Add the Spotify apt repo/keyring and install spotify-client"
                else
                    curl -sS https://download.spotify.com/debian/pubkey_C85661D9C2FE1440.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
                    echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
                    sudo apt update && sudo apt install spotify-client -y
                fi
            fi
        fi

        # Spicetify
        if ! command -v spicetify &> /dev/null; then
            if ask_user "Install Spicetify?"; then
                if [ "$DRY_RUN" = true ]; then
                    dry_run_notice "Run the Spicetify CLI and Marketplace install scripts, then chmod /usr/share/spotify"
                else
                    curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh
                    curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
                    [ -d "/usr/share/spotify" ] && sudo chmod a+wr /usr/share/spotify && sudo chmod a+wr /usr/share/spotify/Apps -R
                fi
            fi
        fi
    fi
}

install_utilities() {
    print_header "System Utilities"
    load_catalog
    local entries=()
    if [ -n "$ROYALUTIL_UTILITIES" ]; then
        mapfile -t entries < <(catalog_filter_ids UTIL_CATALOG "$ROYALUTIL_UTILITIES")
    else
        entries=("${UTIL_CATALOG[@]}")
    fi
    local entry tool
    for entry in "${entries[@]}"; do
        tool="${entry%%|*}"
        if ! command -v "$tool" &> /dev/null; then
            if ask_user "Install $tool?"; then
                if [ "$DRY_RUN" = true ]; then
                    dry_run_notice "Install $tool"
                else
                    if [ "$tool" == "fastfetch" ]; then sudo add-apt-repository ppa:zhangsongcui3371/fastfetch -y && sudo apt update; fi
                    if [ "$tool" == "atuin" ]; then
                        curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | sh
                    else
                        sudo apt install "$tool" -y 2>/dev/null || brew install "$tool"
                    fi
                    success_msg "$tool installed."
                fi
            fi
        fi
    done
}

install_nerdfonts() {
    print_header "Nerd Fonts Installation"
    if ask_user "Install JetBrainsMono Nerd Font?"; then
        if [ "$DRY_RUN" = true ]; then
            dry_run_notice "Download and install the JetBrainsMono Nerd Font to ~/.local/share/fonts and refresh the font cache"
            return
        fi
        info_msg "${ICON_FONT} Installing JetBrainsMono Nerd Font..."
        local font_dir="$HOME/.local/share/fonts"
        mkdir -p "$font_dir"
        
        # Ensure dependencies are present
        sudo apt update && sudo apt install unzip fontconfig -y
        
        local temp_dir=$(mktemp -d)
        local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
        
        if curl -fsSL "$font_url" -o "$temp_dir/font.zip"; then
            unzip -o "$temp_dir/font.zip" -d "$temp_dir"
            find "$temp_dir" -name "*.[ot]tf" -exec cp {} "$font_dir/" \;
            
            info_msg "Refreshing font cache..."
            fc-cache -f "$font_dir"
            
            rm -rf "$temp_dir"
            success_msg "JetBrainsMono Nerd Font installed successfully."
        else
            error_msg "Failed to download Nerd Font from $font_url"
            rm -rf "$temp_dir"
        fi
    fi
}

install_themes() {
    print_header "Bootloader Themes"
    if ask_user "Install Top-5 Bootloader Themes?"; then
        if [ "$DRY_RUN" = true ]; then
            dry_run_notice "Clone Top-5-Bootloader-Themes and run its install.sh with sudo"
            return
        fi
        local theme_dir="$HOME/.local/share/Top-5-Bootloader-Themes"
        mkdir -p "$HOME/.local/share"
        [ -d "$theme_dir" ] && rm -rf "$theme_dir"
        if git clone https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes "$theme_dir"; then
            chmod +x "$theme_dir/install.sh"
            sudo "$theme_dir/install.sh"
            success_msg "Bootloader themes installed."
        fi
    fi
}


uninstall_royalutil() {
    print_header "Uninstall / Rollback Royalutil Changes"
    warn_msg "This reverts config-file edits made by Royalutil. Installed packages are left in place unless you opt in below."

    if ask_user "Remove Royalutil-managed lines from .zshrc/.bashrc (editor & Zsh enhancement config)?"; then
        if [ "$DRY_RUN" = true ]; then
            dry_run_notice "Remove the Royalutil-managed block from ~/.zshrc and ~/.bashrc"
        else
            for file in "$HOME/.zshrc" "$HOME/.bashrc"; do
                remove_marker_block "$file"
            done
        fi
    fi

    if [[ "$SHELL" == *zsh* ]] && command -v bash &> /dev/null; then
        if ask_user "Revert default shell back to bash?"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_notice "Set default shell back to bash (chsh)"
            else
                chsh -s "$(command -v bash)"
                success_msg "Default shell reverted to bash."
            fi
        fi
    fi

    if command -v flatpak &> /dev/null; then
        if ask_user "Remove Flatpak applications installed by Royalutil?"; then
            load_catalog
            local entry app
            for entry in "${FLATPAK_CATALOG[@]}"; do
                app="${entry%%|*}"
                if flatpak list | grep -q "$app"; then
                    if [ "$DRY_RUN" = true ]; then
                        dry_run_notice "Uninstall Flatpak app $app"
                    else
                        info_msg "Removing $app..."
                        flatpak uninstall "$app" -y
                    fi
                fi
            done
            [ "$DRY_RUN" = true ] || success_msg "Selected Flatpak applications removed."
        fi
    fi

    if ask_user "Remove system utilities Royalutil may have installed?"; then
        load_catalog
        local entry tool
        for entry in "${UTIL_CATALOG[@]}"; do
            tool="${entry%%|*}"
            [ "$tool" = "atuin" ] && continue
            if command -v "$tool" &> /dev/null; then
                if [ "$DRY_RUN" = true ]; then
                    dry_run_notice "Remove $tool"
                else
                    info_msg "Removing $tool..."
                    sudo apt remove "$tool" -y 2>/dev/null || brew uninstall "$tool" 2>/dev/null
                fi
            fi
        done
        [ "$DRY_RUN" = true ] || success_msg "Selected utilities removed."
    fi

    if command -v atuin &> /dev/null; then
        warn_msg "Atuin was installed via its own install script and is not removed automatically. Remove manually with: rm -rf ~/.atuin"
    fi

    success_msg "Rollback complete."
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help            Show this help message.
  -y, --non-interactive Run all modules without user prompts.
  -u, --uninstall       Roll back Royalutil's config changes (skips the setup menu).
  -n, --dry-run         Show what each selected module would do, without changing anything.
  --modules=LIST        Run only the given comma-separated module numbers, non-interactively
                        (e.g. --modules=1,3,8). Intended for scripting/GUI front-ends.

Modules available (numbers used by --modules):
  1  - System Maintenance
  2  - Default Code Editor (Nano)
  3  - Git Setup
  4  - Homebrew Setup
  5  - Zsh & Enhancements
  6  - Flatpak Framework
  7  - Applications (Spotify, VS Code, etc.)
  8  - System Utilities (fzf, btop, etc.)
  9  - Bootloader Themes
  10 - Nerd Fonts (JetBrainsMono)
  11 - Uninstall / Rollback

Environment variables:
  GIT_NAME, GIT_EMAIL     Used by module 3 (Git Setup) to configure git identity when
                          running non-interactively (--modules or -y). If unset, identity
                          configuration is skipped rather than prompting.
  ROYALUTIL_CONFIG        Path to the catalog config file (default: royalutil.conf next
                          to this script). See that file for its [flatpak]/[utilities]
                          format; it lists the apps/tools modules 7 and 8 offer.
  ROYALUTIL_APPS          Comma-separated Flatpak app IDs from the [flatpak] catalog.
                          Restricts module 7 to just these apps (e.g. --modules=7 with
                          ROYALUTIL_APPS=com.visualstudio.code,org.gimp.GIMP).
  ROYALUTIL_UTILITIES     Comma-separated tool IDs from the [utilities] catalog.
                          Restricts module 8 the same way ROYALUTIL_APPS restricts 7.
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
        "10. Nerd Fonts"
        "11. Uninstall / Rollback"
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
        [[ "$choice" == *"10. Nerd Fonts"* ]] && selected+=("install_nerdfonts")
        [[ "$choice" == *"11. Uninstall / Rollback"* ]] && selected+=("uninstall_royalutil")

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
    echo "10. Nerd Fonts"
    echo "11. Uninstall / Rollback"
    echo "12. Full Setup"
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
        10) install_nerdfonts ;;
        11) uninstall_royalutil ;;
        12) run_full_setup ;;
        0) exit 0 ;;
        *) warn_msg "Invalid choice." ;;
    esac
}

run_selected_modules() {
    local list=$1
    local tasks=()
    local IFS=','
    local num
    for num in $list; do
        case $num in
            1) tasks+=("maintenance") ;;
            2) tasks+=("setup_editor") ;;
            3) tasks+=("install_git") ;;
            4) tasks+=("setup_brew") ;;
            5) tasks+=("setup_zsh") ;;
            6) tasks+=("install_flatpak") ;;
            7) tasks+=("install_apps") ;;
            8) tasks+=("install_utilities") ;;
            9) tasks+=("install_themes") ;;
            10) tasks+=("install_nerdfonts") ;;
            11) tasks+=("uninstall_royalutil") ;;
            *) warn_msg "Ignoring unknown module number: $num" ;;
        esac
    done

    if [ "${#tasks[@]}" -eq 0 ]; then
        error_msg "No valid modules selected."
        return 1
    fi

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
        "install_nerdfonts"
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
        -u|--uninstall) UNINSTALL_MODE=true ;;
        -n|--dry-run) DRY_RUN=true ;;
        --modules=*) MODULES_ARG="${1#--modules=}"; NON_INTERACTIVE=true ;;
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

if [ "$DRY_RUN" = true ]; then
    warn_msg "Dry-run mode: no packages, files, or system settings will actually be changed."
fi

if ! check_dependencies; then
    exit 1
fi

check_network

if [ "$DRY_RUN" = true ]; then
    info_msg "Skipping sudo prompt (dry-run mode)."
else
    info_msg "Prompting for sudo password to prevent interruptions..."
    sudo -v
    # Keep-alive: update existing `sudo` time stamp until the script has finished
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEP_ALIVE_PID=$!
    trap '[[ -n "$SUDO_KEEP_ALIVE_PID" ]] && kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null' EXIT
fi

if [ -n "$MODULES_ARG" ]; then
    run_selected_modules "$MODULES_ARG"
elif [ "$UNINSTALL_MODE" = true ]; then
    uninstall_royalutil
elif [ "$NON_INTERACTIVE" = true ]; then
    run_full_setup
else
    run_tui
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "\n${BOLD}${BLUE}=== Royalutil Dry-Run Complete! ===${NC}"
    info_msg "No changes were made. Dry-run log saved to: ${BOLD}$LOG_FILE${NC}"
    echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Dry-run finished. Re-run without --dry-run to apply.${NC}"
elif [ "$UNINSTALL_MODE" = true ]; then
    echo -e "\n${BOLD}${BLUE}=== Royalutil Rollback Complete! ===${NC}"
    command -v fastfetch &> /dev/null && fastfetch
    info_msg "Error log saved to: ${BOLD}$LOG_FILE${NC}"
    echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Rollback finished. Please restart your terminal session.${NC}"
else
    echo -e "\n${BOLD}${BLUE}=== Royalutil Setup Complete! ===${NC}"
    command -v fastfetch &> /dev/null && fastfetch
    info_msg "Error log saved to: ${BOLD}$LOG_FILE${NC}"
    echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Setup finished. Please restart your terminal session.${NC}"
fi
