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

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD_YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' 

# Fixed ASCII Art Header: Royalutil
echo -e "${CYAN}"
echo "  ____                  _       _   _ _ "
echo " |  _ \ ___  _   _  __ _| |_   _| |_(_) |"
echo " | |_) / _ \| | | |/ _\` | | | | | __| | |"
echo " |  _ < (_) | |_| | (_| | | |_| | |_| | |"
echo " |_| \_\___/ \__, |\__,_|_|\__,_|\__|_|_|"
echo "             |___/                      "
echo -e "${BLUE}           Interactive System Utility${NC}"
log_msg "${YELLOW}Error logging to: $LOG_FILE${NC}\n"

# 0. System Maintenance (Update & Upgrade)
echo -ne "${BOLD_YELLOW}==> Update package lists and upgrade system? (Y/N): ${NC}"
read update_sys
if [[ "$update_sys" =~ ^[Yy]$ ]]; then
    log_msg "${YELLOW}Refreshing package lists and upgrading system...${NC}"
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
    sudo apt autoremove -y
    log_msg "${GREEN}✓ System is now up to date.${NC}\n"
else
    log_msg "${BLUE}Skipping system update.${NC}\n"
fi

# 1. Set Nano as Default Editor
log_msg "${YELLOW}Setting Nano as default code editor...${NC}"
export EDITOR=nano
export VISUAL=nano

for file in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$file" ]; then
        sed -i.bak '/export EDITOR=/d' "$file" 2>/dev/null || sed -i '/export EDITOR=/d' "$file"
        echo 'export EDITOR="nano"' >> "$file"
        echo 'export VISUAL="nano"' >> "$file"
    fi
done
log_msg "${GREEN}✓ Nano is now your default system editor.${NC}"

# 2. Install & Configure Git
if ! command -v git &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Git? (Y/N): ${NC}"
    read install_git
    if [[ "$install_git" =~ ^[Yy]$ ]]; then
        log_msg "Installing Git..."
        sudo apt update && sudo apt install git -y
    fi
else
    log_msg "${GREEN}✓ Git is already installed.${NC}"
fi

# Git Config
if command -v git &> /dev/null; then
    git config --global core.editor "nano"
    git config --global credential.helper 'cache --timeout=99999'
    log_msg "${GREEN}✓ Git credential timeout set to 99,999s.${NC}"

    echo -ne "${BOLD_YELLOW}==> Configure Git identity? (Y/N): ${NC}"
    read git_conf
    if [[ "$git_conf" =~ ^[Yy]$ ]]; then
        read -p "Name: " git_name
        read -p "Email: " git_email
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        log_msg "${GREEN}✓ Git identity configured.${NC}"
    fi
fi

# 3. Install Homebrew
if ! command -v brew &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Homebrew Package Manager? (Y/N): ${NC}"
    read install_brew
    if [[ "$install_brew" =~ ^[Yy]$ ]]; then
        log_msg "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
    fi
else
    log_msg "${GREEN}✓ Homebrew is already installed.${NC}"
fi

# 4. Install Zsh and Enhancements
if ! command -v zsh &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Zsh? (Y/N): ${NC}"
    read install_zsh
    if [[ "$install_zsh" =~ ^[Yy]$ ]]; then
        log_msg "Installing Zsh..."
        brew install zsh -y
        log_msg "${GREEN}✓ Zsh installed.${NC}"
        
        echo -ne "${BOLD_YELLOW}==> Set Zsh as default shell? (Y/N): ${NC}"
        read set_default
        if [[ "$set_default" =~ ^[Yy]$ ]]; then
            chsh -s $(which zsh)
            log_msg "${GREEN}✓ Zsh set as default shell.${NC}"
        fi
    fi
else
    log_msg "${GREEN}✓ Zsh is already installed.${NC}"
fi

# Install Zsh plugins if Zsh is available
if command -v zsh &> /dev/null && command -v brew &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Zsh enhancements (autosuggestions, syntax-highlighting)? (Y/N): ${NC}"
    read install_zsh_plugins
    if [[ "$install_zsh_plugins" =~ ^[Yy]$ ]]; then
        log_msg "Installing zsh-autosuggestions..."
        brew install zsh-autosuggestions
        
        log_msg "Installing zsh-syntax-highlighting..."
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
        
        log_msg "${GREEN}✓ Zsh enhancements installed and configured.${NC}"
    fi
fi

# 5. Install Flatpak
if ! command -v flatpak &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Flatpak? (Y/N): ${NC}"
    read install_flatpak
    if [[ "$install_flatpak" =~ ^[Yy]$ ]]; then
        log_msg "Installing Flatpak..."
        sudo apt install flatpak -y
        log_msg "Adding Flathub repository..."
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        log_msg "${GREEN}✓ Flatpak installed and configured.${NC}"
    fi
else
    log_msg "${GREEN}✓ Flatpak is already installed.${NC}"
fi

# 6. Install Flatpak Applications
if command -v flatpak &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Flatpak applications (Bitwarden, VS Code, Stremio, Warehouse, Bazaar)? (Y/N): ${NC}"
    read install_flatpak_apps
    if [[ "$install_flatpak_apps" =~ ^[Yy]$ ]]; then
        # Bitwarden
        if ! flatpak list | grep -q "com.bitwarden.desktop"; then
            log_msg "Installing Bitwarden..."
            flatpak install flathub com.bitwarden.desktop -y
            log_msg "${GREEN}✓ Bitwarden installed.${NC}"
        else
            log_msg "${GREEN}✓ Bitwarden is already installed.${NC}"
        fi
        
        # VS Code
        if ! flatpak list | grep -q "com.visualstudio.code"; then
            log_msg "Installing Visual Studio Code..."
            flatpak install flathub com.visualstudio.code -y
            log_msg "${GREEN}✓ VS Code installed.${NC}"
        else
            log_msg "${GREEN}✓ VS Code is already installed.${NC}"
        fi
        
        # Stremio
        if ! flatpak list | grep -q "com.stremio.Stremio"; then
            log_msg "Installing Stremio..."
            flatpak install flathub com.stremio.Stremio -y
            log_msg "${GREEN}✓ Stremio installed.${NC}"
        else
            log_msg "${GREEN}✓ Stremio is already installed.${NC}"
        fi
        
        # Warehouse
        if ! flatpak list | grep -q "io.github.flattool.Warehouse"; then
            log_msg "Installing Warehouse..."
            flatpak install flathub io.github.flattool.Warehouse -y
            log_msg "${GREEN}✓ Warehouse installed.${NC}"
        else
            log_msg "${GREEN}✓ Warehouse is already installed.${NC}"
        fi
        
        # Bazaar
        if ! flatpak list | grep -q "io.github.getnf.Bazaar"; then
            log_msg "Installing Bazaar..."
            flatpak install flathub io.github.getnf.Bazaar -y
            log_msg "${GREEN}✓ Bazaar installed.${NC}"
        else
            log_msg "${GREEN}✓ Bazaar is already installed.${NC}"
        fi
    fi
fi

# 7. Install Atuin
if ! command -v atuin &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Atuin (Shell History)? (Y/N): ${NC}"
    read install_atuin
    if [[ "$install_atuin" =~ ^[Yy]$ ]]; then
        log_msg "Installing Atuin..."
        if command -v brew &> /dev/null; then
            brew install atuin
        else
            curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | sh
        fi
        [[ -f ~/.zshrc ]] && echo 'eval "$(atuin init zsh)"' >> ~/.zshrc
        [[ -f ~/.bashrc ]] && echo 'eval "$(atuin init bash)"' >> ~/.bashrc
    fi
else
    log_msg "${GREEN}✓ Atuin is already installed.${NC}"
fi

# 8. Install Extras (fzf, fastfetch, btop)
for tool in fzf fastfetch btop; do
    if ! command -v $tool &> /dev/null; then
        echo -ne "${BOLD_YELLOW}==> Install $tool? (Y/N): ${NC}"
        read install_tool
        if [[ "$install_tool" =~ ^[Yy]$ ]]; then
            log_msg "Installing $tool..."
            if [[ "$tool" == "fastfetch" ]]; then
                sudo add-apt-repository ppa:zhangsongcui3371/fastfetch -y
                sudo apt update
            fi
            sudo apt install $tool -y || brew install $tool
        fi
    fi
done

# 9. Install Zellij (Terminal Workspace)
if ! command -v zellij &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Zellij (Terminal Workspace)? (Y/N): ${NC}"
    read install_zellij
    if [[ "$install_zellij" =~ ^[Yy]$ ]]; then
        log_msg "Installing Zellij..."
        brew install zellij
        log_msg "${GREEN}✓ Zellij installed.${NC}"
    fi
else
    log_msg "${GREEN}✓ Zellij is already installed.${NC}"
fi

log_msg "\n${BLUE}=== Royalutil Setup Complete! ===${NC}"
command -v fastfetch &> /dev/null && fastfetch
log_msg "${CYAN}Error log saved to: $LOG_FILE${NC}"

echo -ne "${BOLD_YELLOW}==> Review the error log in Nano? (Y/N): ${NC}"
read view_log
[[ "$view_log" =~ ^[Yy]$ ]] && nano "$LOG_FILE"

echo -e "\n${GREEN}Setup finished. Please restart your terminal session.${NC}"
