#!/bin/bash

# Define log file path
LOG_FILE="$HOME/royalutil_setup.log"

# Delete old log if it exists and start a fresh one
[ -f "$LOG_FILE" ] && rm "$LOG_FILE"

# Function to log messages to both terminal and file
log_msg() {
    echo -e "$1"
}

# Function to log only errors
log_error() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Redirect stderr to the log file (errors only)
exec 2>>"$LOG_FILE"

# Clear the terminal screen
clear

# Colors & Styles
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Icons
ICON_UPDATE="🔄"
ICON_GIT="GitHub"
ICON_BREW="🍺"
ICON_SHELL="🐚"
ICON_FLATPAK="📦"
ICON_TOOL="🛠️"
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
ICON_QUESTION="❓"

# UI Helper Functions
print_header() {
    local title=$1
    echo -e "\n${BOLD}${PURPLE}# $title${NC}"
    echo -e "${PURPLE}$(printf '%.s─' $(seq 1 $((${#title} + 2))))${NC}"
}

success_msg() {
    echo -e "${GREEN}${ICON_SUCCESS} $1${NC}"
}

error_msg() {
    echo -e "${RED}${ICON_ERROR} $1${NC}" | tee -a "$LOG_FILE"
}

warn_msg() {
    echo -e "${YELLOW}${ICON_WARN} $1${NC}"
}

info_msg() {
    echo -e "${CYAN}${ICON_INFO} $1${NC}"
}

log_msg() {
    echo -e "$1"
}

ask_user() {
    local prompt=$1
    echo -ne "${BOLD}${YELLOW}${ICON_QUESTION} $prompt (Y/N): ${NC}"
}

# Fixed ASCII Art Header: Royalutil
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
info_msg "Error logging to: ${BOLD}$LOG_FILE${NC}\n"

# 0. System Maintenance (Update & Upgrade)
print_header "System Maintenance"
ask_user "Update package lists and upgrade system?"
read update_sys
if [[ "$update_sys" =~ ^[Yy]$ ]]; then
    info_msg "${ICON_UPDATE} Refreshing package lists and upgrading system..."
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
    sudo apt autoremove -y
    success_msg "System is now up to date."
else
    info_msg "Skipping system update."
fi

# 1. Set Nano as Default Editor
print_header "Default Code Editor"
info_msg "Setting Nano as default code editor..."
export EDITOR=nano
export VISUAL=nano

for file in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$file" ]; then
        sed -i.bak '/export EDITOR=/d' "$file" 2>/dev/null || sed -i '/export EDITOR=/d' "$file"
        echo 'export EDITOR="nano"' >> "$file"
        echo 'export VISUAL="nano"' >> "$file"
    fi
done
success_msg "Nano is now your default system editor."

# 2. Install & Configure Git
print_header "Git Setup"
if ! command -v git &> /dev/null; then
    ask_user "Install Git?"
    read install_git
    if [[ "$install_git" =~ ^[Yy]$ ]]; then
        info_msg "Installing Git..."
        sudo apt update && sudo apt install git -y
    fi
else
    success_msg "Git is already installed."
fi

# Git Config
if command -v git &> /dev/null; then
    git config --global core.editor "nano"
    git config --global credential.helper 'cache --timeout=99999'
    success_msg "Git credential timeout set to 99,999s."

    ask_user "Configure Git identity?"
    read git_conf
    if [[ "$git_conf" =~ ^[Yy]$ ]]; then
        read -p "Name: " git_name
        read -p "Email: " git_email
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        success_msg "Git identity configured."
    fi
fi

# 3. Install Homebrew
print_header "Homebrew Package Manager"
if ! command -v brew &> /dev/null; then
    ask_user "Install Homebrew Package Manager?"
    read install_brew
    if [[ "$install_brew" =~ ^[Yy]$ ]]; then
        info_msg "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
    fi
else
    success_msg "Homebrew is already installed."
fi

# 4. Install Zsh and Enhancements
print_header "Zsh Shell"
if ! command -v zsh &> /dev/null; then
    ask_user "Install Zsh?"
    read install_zsh
    if [[ "$install_zsh" =~ ^[Yy]$ ]]; then
        info_msg "Installing Zsh..."
        brew install zsh -y
        success_msg "Zsh installed."
        
        ask_user "Set Zsh as default shell?"
        read set_default
        if [[ "$set_default" =~ ^[Yy]$ ]]; then
            chsh -s $(which zsh)
            success_msg "Zsh set as default shell."
        fi
    fi
else
    success_msg "Zsh is already installed."
fi

# Install Zsh plugins if Zsh is available
if command -v zsh &> /dev/null && command -v brew &> /dev/null; then
    ask_user "Install Zsh enhancements (autosuggestions, syntax-highlighting)?"
    read install_zsh_plugins
    if [[ "$install_zsh_plugins" =~ ^[Yy]$ ]]; then
        info_msg "Installing zsh-autosuggestions..."
        brew install zsh-autosuggestions
        
        info_msg "Installing zsh-syntax-highlighting..."
        brew install zsh-syntax-highlighting
        
        # Add plugin sources to .zshrc if not already present
        ZSHRC="$HOME/.zshrc"
        touch "$ZSHRC"
        
        # Add autosuggestions
        if ! grep -q "zsh-autosuggestions.zsh" "$ZSHRC"; then
            echo '' >> "$ZSHRC"
            echo '# Zsh autosuggestions' >> "$ZSHRC"
            echo 'source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh' >> "$ZSHRC"
        fi
        
        # Add syntax highlighting
        if ! grep -q "zsh-syntax-highlighting.zsh" "$ZSHRC"; then
            echo '' >> "$ZSHRC"
            echo '# Zsh syntax highlighting' >> "$ZSHRC"
            echo 'source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> "$ZSHRC"
        fi
        
        success_msg "Zsh enhancements installed and configured."
    fi
fi

# 5. Install Flatpak
print_header "Flatpak Framework"
if ! command -v flatpak &> /dev/null; then
    ask_user "Install Flatpak?"
    read install_flatpak
    if [[ "$install_flatpak" =~ ^[Yy]$ ]]; then
        info_msg "Installing Flatpak..."
        sudo apt install flatpak -y
        info_msg "Adding Flathub repository..."
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        success_msg "Flatpak installed and configured."
    fi
else
    success_msg "Flatpak is already installed."
fi

# 6. Install Flatpak Applications
print_header "Flatpak Applications"
if command -v flatpak &> /dev/null; then
    ask_user "Install Flatpak applications (Bitwarden, VS Code, Stremio, Warehouse, Bazaar, Firefox Nightly)?"
    read install_flatpak_apps
    if [[ "$install_flatpak_apps" =~ ^[Yy]$ ]]; then
        # Bitwarden
        if ! flatpak list | grep -q "com.bitwarden.desktop"; then
            info_msg "Installing Bitwarden..."
            flatpak install flathub com.bitwarden.desktop -y
            success_msg "Bitwarden installed."
        else
            success_msg "Bitwarden is already installed."
        fi
        
        # VS Code
        if ! flatpak list | grep -q "com.visualstudio.code"; then
            info_msg "Installing Visual Studio Code..."
            flatpak install flathub com.visualstudio.code -y
            success_msg "VS Code installed."
        else
            success_msg "VS Code is already installed."
        fi
        
        # Stremio
        if ! flatpak list | grep -q "com.stremio.Stremio"; then
            info_msg "Installing Stremio..."
            flatpak install flathub com.stremio.Stremio -y
            success_msg "Stremio installed."
        else
            success_msg "Stremio is already installed."
        fi
        
        # Warehouse
        if ! flatpak list | grep -q "io.github.flattool.Warehouse"; then
            info_msg "Installing Warehouse..."
            flatpak install flathub io.github.flattool.Warehouse -y
            success_msg "Warehouse installed."
        else
            success_msg "Warehouse is already installed."
        fi
        
        # Bazaar
        if ! flatpak list | grep -q "io.github.getnf.Bazaar"; then
            info_msg "Installing Bazaar..."
            flatpak install flathub io.github.getnf.Bazaar -y
            success_msg "Bazaar installed."
        else
            success_msg "Bazaar is already installed."
        fi

        # Firefox Nightly
        if ! flatpak list | grep -q "org.mozilla.FirefoxNightly"; then
            info_msg "Installing Firefox Nightly..."
            flatpak install flathub org.mozilla.FirefoxNightly -y
            success_msg "Firefox Nightly installed."
        else
            success_msg "Firefox Nightly is already installed."
        fi
    fi
fi

# 7. Install Atuin
print_header "Atuin Shell History"
if ! command -v atuin &> /dev/null; then
    ask_user "Install Atuin (Shell History)?"
    read install_atuin
    if [[ "$install_atuin" =~ ^[Yy]$ ]]; then
        info_msg "Installing Atuin..."
        if command -v brew &> /dev/null; then
            brew install atuin
        else
            curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | sh
        fi
        [[ -f ~/.zshrc ]] && echo 'eval "$(atuin init zsh)"' >> ~/.zshrc
        [[ -f ~/.bashrc ]] && echo 'eval "$(atuin init bash)"' >> ~/.bashrc
        success_msg "Atuin installed and initialized."
    fi
else
    success_msg "Atuin is already installed."
fi

# 8. Install Extras (fzf, fastfetch, btop)
print_header "System Utilities"
for tool in fzf fastfetch btop; do
    if ! command -v $tool &> /dev/null; then
        ask_user "Install $tool?"
        read install_tool
        if [[ "$install_tool" =~ ^[Yy]$ ]]; then
            info_msg "Installing $tool..."
            if [[ "$tool" == "fastfetch" ]]; then
                sudo add-apt-repository ppa:zhangsongcui3371/fastfetch -y
                sudo apt update
            fi
            sudo apt install $tool -y || brew install $tool
            success_msg "$tool installed."
        fi
    else
        success_msg "$tool is already installed."
    fi
done

# 9. Install Zellij (Terminal Workspace)
print_header "Terminal Workspace"
if ! command -v zellij &> /dev/null; then
    ask_user "Install Zellij (Terminal Workspace)?"
    read install_zellij
    if [[ "$install_zellij" =~ ^[Yy]$ ]]; then
        info_msg "Installing Zellij..."
        brew install zellij
        success_msg "Zellij installed."
    fi
else
    success_msg "Zellij is already installed."
fi

# 10. Install Spotify (via apt)
print_header "Spotify"
if ! command -v spotify &> /dev/null; then
    ask_user "Install Spotify (via apt)?"
    read install_spotify
    if [[ "$install_spotify" =~ ^[Yy]$ ]]; then
        info_msg "Installing Spotify..."
        curl -sS https://download.spotify.com/debian/pubkey_C85661D9C2FE1440.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
        sudo apt update && sudo apt install spotify-client -y
        success_msg "Spotify installed."
    fi
else
    success_msg "Spotify is already installed."
fi

# 11. Install Spicetify (Spotify Customization)
print_header "Spicetify Customization"
if ! command -v spicetify &> /dev/null; then
    ask_user "Install Spicetify (Spotify Customization)?"
    read install_spicetify
    if [[ "$install_spicetify" =~ ^[Yy]$ ]]; then
        info_msg "Installing Spicetify..."
        curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh
        curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
        
        # Grant permissions to Spotify directory for Spicetify
        if [ -d "/usr/share/spotify" ]; then
            sudo chmod a+wr /usr/share/spotify
            sudo chmod a+wr /usr/share/spotify/Apps -R
        fi
        
        success_msg "Spicetify installed. Run 'spicetify backup apply' after launching Spotify to initialize."
    fi
else
    success_msg "Spicetify is already installed."
fi

echo -e "\n${BOLD}${BLUE}=== Royalutil Setup Complete! ===${NC}"
command -v fastfetch &> /dev/null && fastfetch
info_msg "Error log saved to: ${BOLD}$LOG_FILE${NC}"

ask_user "Review the error log in Nano?"
read view_log
[[ "$view_log" =~ ^[Yy]$ ]] && nano "$LOG_FILE"

echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Setup finished. Please restart your terminal session.${NC}"
