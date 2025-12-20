#!/bin/bash

# Define log file path
LOG_FILE="$HOME/royalutil_setup.log"

# Delete old log if it exists and start a fresh one
[ -f "$LOG_FILE" ] && rm "$LOG_FILE"

# Function to log messages to both terminal and file
log_msg() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Redirect stderr to the log file
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
log_msg "${YELLOW}Logging to: $LOG_FILE${NC}\n"

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
        sudo apt update && sudo apt install git -y >> "$LOG_FILE" 2>&1
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
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
    fi
else
    log_msg "${GREEN}✓ Homebrew is already installed.${NC}"
fi

# 4. Install Visual Studio Code
if ! command -v code &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Visual Studio Code? (Y/N): ${NC}"
    read install_code
    if [[ "$install_code" =~ ^[Yy]$ ]]; then
        log_msg "Installing VS Code via official APT repository..."
        sudo apt-get install wget gpg -y >> "$LOG_FILE" 2>&1
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
        sudo install -D -o root -g root -m 644 microsoft.gpg /etc/apt/keyrings/microsoft.gpg >> "$LOG_FILE" 2>&1
        sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        rm -f microsoft.gpg
        sudo apt update && sudo apt install code -y >> "$LOG_FILE" 2>&1
        log_msg "${GREEN}✓ VS Code installed.${NC}"
    fi
fi

# 5. Install Bitwarden (Snap Only - Visible)
if ! command -v bitwarden &> /dev/null; then
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -ne "${BOLD_YELLOW}==> Install Bitwarden via Snap? (Y/N): ${NC}"
        read install_bw
        if [[ "$install_bw" =~ ^[Yy]$ ]]; then
            log_msg "Installing Bitwarden... (Progress visible below)"
            # Note: We do NOT redirect output to LOG_FILE here so you can see the snap progress bar
            sudo snap install bitwarden
            log_msg "${GREEN}✓ Bitwarden installation process finished.${NC}"
        fi
    fi
else
    log_msg "${GREEN}✓ Bitwarden is already installed.${NC}"
fi

# 6. Install Atuin
if ! command -v atuin &> /dev/null; then
    echo -ne "${BOLD_YELLOW}==> Install Atuin (Shell History)? (Y/N): ${NC}"
    read install_atuin
    if [[ "$install_atuin" =~ ^[Yy]$ ]]; then
        log_msg "Installing Atuin..."
        if command -v brew &> /dev/null; then
            brew install atuin >> "$LOG_FILE" 2>&1
        else
            curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | sh >> "$LOG_FILE" 2>&1
        fi
        [[ -f ~/.zshrc ]] && echo 'eval "$(atuin init zsh)"' >> ~/.zshrc
        [[ -f ~/.bashrc ]] && echo 'eval "$(atuin init bash)"' >> ~/.bashrc
    fi
else
    log_msg "${GREEN}✓ Atuin is already installed.${NC}"
fi

# 7. Install Extras (fzf, fastfetch, btop)
for tool in fzf fastfetch btop; do
    if ! command -v $tool &> /dev/null; then
        echo -ne "${BOLD_YELLOW}==> Install $tool? (Y/N): ${NC}"
        read install_tool
        if [[ "$install_tool" =~ ^[Yy]$ ]]; then
            log_msg "Installing $tool..."
            [[ "$tool" == "fastfetch" ]] && { sudo add-apt-repository ppa:zhangsongcui3371/fastfetch -y; sudo apt update; } >> "$LOG_FILE" 2>&1
            sudo apt install $tool -y >> "$LOG_FILE" 2>&1 || brew install $tool >> "$LOG_FILE" 2>&1
        fi
    fi
done

log_msg "\n${BLUE}=== Royalutil Setup Complete! ===${NC}"
command -v fastfetch &> /dev/null && fastfetch
log_msg "${CYAN}Log saved to: $LOG_FILE${NC}"

echo -ne "${BOLD_YELLOW}==> Review the installation log in Nano? (Y/N): ${NC}"
read view_log
[[ "$view_log" =~ ^[Yy]$ ]] && nano "$LOG_FILE"

echo -e "\n${GREEN}Setup finished. Please restart your terminal session.${NC}"
