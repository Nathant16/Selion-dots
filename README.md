<div align="center">
  <img src="docs/assets/banner.png" alt="Selion Shell" width="850" />

  <p align="center">
    A modern, highly customizable, and fluid desktop shell for Wayland.
  </p>

  <p align="center">
    <a href="https://github.com/Nathant16/Selion-dots/releases">
      <img src="https://img.shields.io/badge/version-2.6.1-blue.svg?style=for-the-badge" alt="Version 2.6.1" />
    </a>
    <a href="https://t.me/Nathant16">
      <img src="https://img.shields.io/badge/Telegram-@Nathant16-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram" />
    </a>
    <a href="LICENSE.md">
      <img src="https://img.shields.io/badge/License-AGPL--3.0-green.svg?style=for-the-badge" alt="License" />
    </a>
  </p>
</div>

---

## 📸 Previews

| | |
|---|---|
| ![Preview 1](docs/assets/previews/preview_1.png) | ![Preview 2](docs/assets/previews/preview_2.png) |
| ![Preview 3](docs/assets/previews/preview_3.png) | ![Preview 4](docs/assets/previews/preview_4.png) |

---

## 🚀 Installation

Run the automated installer on any supported distribution (**Arch Linux**, **Fedora**, **Void Linux** and their derivatives):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nathant16/Selion-dots/master/install/install.sh)"
```

> [!TIP]
> **To update:** Either run the command above and choose **`6. Update`**, or click the **Update** button inside the **Settings → About** tab. Your custom configurations, keybindings, and preferences will be preserved.

---

## ✨ Features

- **Supported Compositors:** Full integration with **Hyprland**, **Sway**, **DriftWM**, and **Niri**.
- **Dynamic Theming:** Powered by **Material You** (`matugen`) — automatically derives accent colors from your wallpaper or lets you choose manual presets, dynamically theming GTK, Qt, Kitty, Fish, and Fastfetch.
- **Terminal & Shell Out-of-the-Box:**
  - **Fish Shell** with a custom two-line prompt, theme synchronization on the fly, and handy aliases (`eza`, `bat`, `zoxide`).
  - **Fastfetch** with a 7-step vertical color gradient matching the active theme palette.
  - **Kitty** terminal preconfigured with `JetBrainsMono Nerd Font` and Fish.
  - **Starship** prompt support (`starship.toml`).
- **Complete Desktop Suite:**
  - Modular **Top Bar** with system monitors, workspaces, media player, and weather cards.
  - Smart **Dock** with app pinning, running indicators, and context menus.
  - Fullscreen/windowed **App Launcher** with instant fuzzy search.
  - **Control Center / Quick Actions** for volume, brightness, Bluetooth, Wi-Fi, night light, and power profiles.
  - **Lockscreen** with modern clock styles, pam fprintd fingerprint support, and media controls.
- **Laptop & Power Management:**
  - Battery charge threshold support (Conservation mode: 80% / custom limit).
  - Power profiles (Power Saver, Balanced, Performance) with automated CPU frequency controls and boost management.
- **Curated Wallpapers:** Includes a built-in collection of 130+ UHD/QHD wallpapers with recursive indexing and live preview.

---

## ⌨️ Quick Controls

| Keybinding | Action |
|---|---|
| <kbd>Super</kbd> | Toggle App Launcher |
| <kbd>Super</kbd> + <kbd>Return</kbd> | Open Kitty Terminal |
| <kbd>Super</kbd> + <kbd>I</kbd> | Open Settings / Guide |
| <kbd>Super</kbd> + <kbd>E</kbd> | Open File Manager |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | Screenshot tool (Satty / Grim) |
| <kbd>Super</kbd> + <kbd>L</kbd> | Lock Screen |
| <kbd>Super</kbd> + <kbd>Q</kbd> | Close focused window |

---

## 🛠️ Service Management

To start or restart the shell manually:

```bash
# Start shell daemon
serpantinumd start

# Restart shell
serpantinumd restart

# Stop shell
serpantinumd stop
```

---

## 📄 License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE.md).
