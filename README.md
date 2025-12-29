# 👑 Royalutil

<p align="center">
  <img src="https://img.shields.io/badge/Shell-Bash-blue?style=for-the-badge&logo=gnu-bash" alt="Bash">
  <img src="https://img.shields.io/badge/Platform-Linux-orange?style=for-the-badge&logo=linux" alt="Linux">
</p>

An interactive system utility bash script designed to automate the setup and configuration of development environments on Linux with a focus on aesthetics and ease of use.

---

## ✨ Features

### 🛠️ Core System
* **System Maintenance**: Optional update/upgrade with automatic cleanup.
* **Default Editor**: Sets `nano` as the global system editor.
* **Git Setup**: Installs Git and configures identity with long-term credential caching.

### 📦 Package Management
* **Homebrew**: Installs Linuxbrew for extra package support.
* **Flatpak**: Full setup with the Flathub repository enabled.

### 🚀 GUI Applications (via Flatpak)
* 🔐 **Bitwarden**: Premium password management.
* 💻 **VS Code**: The industry-standard code editor.
* 🎬 **Stremio**: Modern media streaming.
* 🏪 **Warehouse**: Graphic Flatpak manager.
* 🎨 **Bazaar**: Nerd Fonts manager.
* 🦊 **Firefox Nightly**: Cutting-edge web browsing.

### 🎵 Entertainment & Customization
* 🎧 **Spotify**: Installed via official `apt` repository for seamless updates.
* 🪄 **Spicetify**: Powerful CLI for Spotify themes and Marketplace extensions.

### 🐚 Shell & Terminal
* **Zsh**: Enhanced with autosuggestions and syntax highlighting.
* **Atuin**: Magical shell history synchronization.
* **Modern Tools**: `fzf` (Fuzzy Finder), `fastfetch` (System Info), `btop` (Resource Monitor).
* **Zellij**: Modern terminal workspace manager.

---

## 🚀 Usage

### 1. Download & Prepare
Ensure `royalutil.sh` is in your current directory.

### 2. Make it Executable
```bash
chmod +x royalutil.sh
```

### 3. Run the Utility
```bash
./royalutil.sh
```

### 4. Interactive Setup
Follow the prompts! The script uses a modern UI with icons and clear headers to guide you through the process.

---

## 📜 Requirements

* **OS**: Linux (Debian/Ubuntu-based recommended).
* **Package Manager**: `apt` for base system packages.
* **Connectivity**: Internet connection for downloads.
* **Permissions**: `sudo` access for installations.

---

## 🏁 Post-Installation

1. **New Session**: Restart your terminal to apply shell changes (Zsh, Atuin).
2. **Launch Apps**: Open your application menu or use:
   ```bash
   flatpak run org.mozilla.FirefoxNightly
   flatpak run com.visualstudio.code
   ```
3. **Customize Spotify**:
   - Launch Spotify and log in.
   - Run: `spicetify backup apply` to initialize Marketplace.

---

## 🛠️ Troubleshooting

* **Logs**: Check `~/royalutil_setup.log` for detailed error tracking.
* **Shell**: If commands aren't found, ensure you've restarted your terminal or run `source ~/.zshrc`.
* **Flatpak**: If icons don't appear, a system logout/login may be required.

---

<p align="center">
  Built with ❤️ for the Linux Community
</p>
