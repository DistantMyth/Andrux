# 🐧 Andrux — Linux Desktop on Android

Install ready-to-use Linux desktop environments on Android via Termux, with **GPU acceleration**, **audio**, and **networking** working out of the box.

![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Android](https://img.shields.io/badge/Android-8.0+-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

---

## ✨ Features

- **4 Distributions**: Debian, Ubuntu, Arch Linux, Fedora
- **3 Desktop Environments**: XFCE, KDE Plasma, GNOME
- **GPU Acceleration**: Auto-detected — ANGLE/VirGL for Mali, Turnip/Zink for Adreno
- **Audio**: PulseAudio bridge, works out of the box
- **Networking**: Internet access configured automatically
- **Interactive Installer**: Beautiful TUI with `dialog`
- **One-Command Launch**: `start-desktop` to start, `kill-desktop` to stop

## 📋 Requirements

| Component | Requirement |
|-----------|------------|
| **Android** | 8.0 or higher |
| **Termux** | Latest (from [GitHub](https://github.com/termux/termux-app/releases) or [F-Droid](https://f-droid.org/packages/com.termux/)) |
| **Termux:X11** | [Latest release](https://github.com/termux/termux-x11/releases) |
| **Termux:API** | [Latest release](https://github.com/termux/termux-api/releases) |
| **RAM** | 3 GB+ (8 GB+ recommended for KDE/GNOME) |
| **Storage** | 4-10 GB free |
| **Internet** | Stable connection (2-5 GB download) |

> ⚠️ **Important**: Do NOT use Termux from Google Play. It's outdated and lacks required APIs.

## 🚀 Quick Start

### 1. Install

```bash
git clone https://github.com/DistantMyth/Andrux.git
cd Andrux
bash andrux
```

The interactive installer will guide you through:
1. Hardware detection
2. Distribution selection
3. Desktop environment selection
4. User account creation
5. Automated installation

### 2. Start Desktop

```bash
start-desktop
```

Then switch to the **Termux:X11** app on your device to see your desktop.

### 3. Stop Desktop

```bash
kill-desktop
```

## 🎮 GPU Acceleration

Andrux automatically detects your GPU and configures the best acceleration method:

| GPU | Method | Performance |
|-----|--------|-------------|
| **Mali** (MediaTek, Exynos) | ANGLE → Vulkan → VirGL | Good |
| **Adreno 6xx/7xx** (Snapdragon) | Turnip → Zink | Best |
| **Adreno (older)** | VirGL | Fair |
| **Other** | Software (llvmpipe) | Basic |

To disable GPU acceleration:
```bash
start-desktop --no-gpu
```

## 🔊 Audio

Audio works via a PulseAudio TCP bridge between Termux and the proot environment. It's configured automatically during installation.

To disable audio:
```bash
start-desktop --no-audio
```

## 📁 Project Structure

```
Andrux/
├── andrux              # Main installer script
├── lib/
│   ├── common.sh       # Shared utilities
│   ├── detect.sh       # Hardware detection
│   ├── prereqs.sh      # Prerequisite installation
│   ├── distro.sh       # Distribution management
│   ├── desktop.sh      # Desktop environment setup
│   ├── gpu.sh          # GPU acceleration
│   ├── audio.sh        # Audio bridge
│   ├── network.sh      # Network configuration
│   └── apps.sh         # Default applications
├── launchers/
│   ├── start-desktop.sh
│   └── kill-desktop.sh
├── configs/
│   └── de/
│       ├── xfce.sh
│       ├── kde.sh
│       └── gnome.sh
├── README.md
└── LICENSE
```

## ⚙️ Commands

| Command | Description |
|---------|-------------|
| `bash andrux` | Run the interactive installer |
| `bash andrux --status` | Check installation status |
| `bash andrux --uninstall` | Remove the installation |
| `start-desktop` | Start the desktop environment |
| `start-desktop --no-gpu` | Start without GPU acceleration |
| `start-desktop --no-audio` | Start without audio |
| `kill-desktop` | Stop the desktop environment |

## 🔧 Troubleshooting

### Desktop doesn't appear
- Make sure the Termux:X11 app is open
- Try `start-desktop --no-gpu`
- Check if Phantom Process Killer is active (Android 12+)

### Phantom Process Killer (Android 12+)
Connect via ADB and run:
```bash
adb shell "settings put global settings_enable_monitor_phantom_procs false"
```

### No audio
- Make sure PulseAudio is running: `pulseaudio --check`
- Restart audio: `pulseaudio --kill && pulseaudio --start`

### Network issues
- Check DNS: run `cat /etc/resolv.conf` inside the proot
- Fix DNS: run `echo "nameserver 8.8.8.8" > /etc/resolv.conf` inside proot

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

Built on the shoulders of:
- [Termux](https://termux.dev)
- [proot-distro](https://github.com/termux/proot-distro)
- [Termux:X11](https://github.com/termux/termux-x11)
- [sabamdarif/termux-desktop](https://github.com/sabamdarif/termux-desktop)
- [LinuxDroidMaster/Termux-Desktops](https://github.com/LinuxDroidMaster/Termux-Desktops)
