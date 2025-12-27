# Royalutil

An interactive system utility bash script designed to automate the setup and configuration of development environments on Linux.

## Features

* **System Maintenance**: Optional system update and upgrade with package cleanup
* **Default Editor**: Automatically sets nano as the global system editor
* **Git Configuration**: Installs Git and configures identity and credential caching (99,999s timeout)
* **Package Managers**: 
  * Installs Homebrew (Linuxbrew) if not present
  * Installs Flatpak with Flathub repository
* **GUI Applications** (via Flatpak):
  * Bitwarden (Password Manager)
  * Visual Studio Code (Code Editor)
  * Stremio (Media Streaming)
  * Warehouse (Flatpak Manager)
  * Bazaar (Nerd Fonts Manager)
* **Shell Enhancements**:
  * Zsh with autosuggestions and syntax highlighting
  * Atuin (Enhanced Shell History)
* **Terminal Tools**:
  * fzf (Fuzzy Finder)
  * fastfetch (System Information)
  * btop (Resource Monitor)
  * Zellij (Terminal Workspace Manager)
* **Logging**: Errors are logged to `~/royalutil_setup.log` while all progress is shown in terminal

## Usage

1. **Download the script**: Ensure `royalutil.sh` is in your current directory.

2. **Make it executable**:
   ```bash
   chmod +x royalutil.sh
   ```

3. **Run the script**:
   ```bash
   ./royalutil.sh
   ```

4. **Follow the Prompts**: The script will ask for confirmation before installing each component.

## Requirements

* **Operating System**: Linux (Debian/Ubuntu-based distributions)
* **Package Managers**: Requires `apt` for base packages
* **Internet Connection**: Required for downloading packages and repositories
* **Permissions**: sudo access for system-level installations

## Post-Installation

After the script finishes:

1. **Restart your terminal session** to apply changes to your shell environment (Zsh, Atuin integration, and editor paths)
2. **Launch Flatpak applications** from your application menu or via command line:
   ```bash
   flatpak run com.bitwarden.desktop
   flatpak run com.visualstudio.code
   flatpak run com.stremio.Stremio
   flatpak run io.github.flattool.Warehouse
   flatpak run io.github.getnf.Bazaar
   ```

## Troubleshooting

* **Check the error log**: Review `~/royalutil_setup.log` for any errors that occurred during installation
* **Flatpak not working**: Ensure you log out and log back in after Flatpak installation for proper desktop integration
* **Command not found**: Source your shell configuration or restart your terminal session
