Royalutil

An interactive system utility bash script designed to automate the setup and configuration of development environments on Linux.

Features

Default Editor: Automatically sets nano as the global system editor.

Git Configuration: Installs Git and configures identity and credential caching (99,999s timeout).

Package Managers: Installs Homebrew (Linuxbrew) if not present.

Development Tools:

Visual Studio Code (via official Microsoft APT repository)

Bitwarden (via Snap)

Atuin (Shell History)

CLI Utilities: Installs fzf, fastfetch, and btop.

Logging: All installation steps and errors are logged to ~/royalutil_setup.log.

Usage

Download the script:
Ensure royalutil.sh is in your current directory.

Make it executable:

chmod +x royalutil.sh


Run the script:

./royalutil.sh


Follow the Prompts:
The script will ask for confirmation before installing major components.

Requirements

Operating System: Linux (specifically Debian/Ubuntu-based distributions for APT support).

Package Managers: Requires apt and snap.

Internet Connection: Required for downloading packages.

Post-Installation

After the script finishes, it is recommended to restart your terminal session to apply changes to your shell environment (e.g., Atuin integration and editor paths).
