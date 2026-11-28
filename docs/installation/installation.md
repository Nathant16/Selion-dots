---
sidebar_position: 1
title: Installation
sidebar_label: Installation
slug: /installation
---

# Installation

:::warning[IMPORTANT]
**Migrating from v1:** All previous configuration will be backed up and unused. Configuration of compositor settings such as monitors, keybinds, and autostart is now up to you, as the project migrated from being dotfiles to being a shell.
:::

Serpantinum installs through an automated script on Arch Linux, Fedora, Void Linux, Gentoo, and their derivatives. The script detects your distribution and uses the matching package manager (`pacman`, `dnf`, `xbps`, or `emerge`). On NixOS, use the [flake and modules](/installation/nixos) instead.

Use this installer:

```bash
curl -fsSL https://install.serpantinum.dev | bash
```

If this doesn't work, use:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nathant16/Selion-dots/master/install/install.sh)"
```

:::info[NOTE]
To update, run the installer script again and choose **Update**.
:::

## Fedora

Fedora and its derivatives, such as **Nobara** and **Ultramarine**, are installed with `dnf`. Fedora does not package `gpu-screen-recorder`, so screen recording is unavailable there. SDDM is set up with its Wayland greeter, since Fedora ships no Xorg server. Mango and Umbriel are installed from the [Terra](https://terra.fyralabs.com) repository, which the installer enables when needed.

## Void Linux

Void Linux, both glibc and musl, is installed with `xbps`. Everything comes from the official repositories except:

- **Hyprland**, which Void does not package. When you select it, the installer adds the third-party [black-hole.dev](https://mirror.black-hole.dev) repository in `/etc/xbps.d/20-serpantinum-hyprland.conf` and accepts its signing key.
- **Umbriel**, which Void does not package either. When you select it, the installer adds the third-party [UniversalRepository](https://universalrepo.pages.dev) in `/etc/xbps.d/10-universalrepository.conf` and accepts its signing key.

Niri, Sway, and Mango come from the official repositories.
- **adw-gtk3** and **JetBrains Mono**, which are downloaded from their latest GitHub releases into `/usr/share/themes` and `/usr/share/fonts`.

Services are enabled through runit. `dbus`, `bluetoothd`, and `power-profiles-daemon` start right away. `NetworkManager` and `sddm` start from the next boot, so the installer does not cut your network or take over the screen while it runs. If `dhcpcd` or `wpa_supplicant` were enabled, they are kept from starting at the next boot, since they conflict with NetworkManager. Wi-Fi networks must then be connected again through Serpantinum or `nmcli`. Display managers being replaced keep running until you reboot.

PipeWire is configured system-wide to launch WirePlumber and `pipewire-pulse`, with ALSA routed through it. Sessions started from SDDM get a D-Bus session bus and PipeWire automatically. If you start your compositor from a TTY instead, launch it with `dbus-run-session` and start `pipewire` from its autostart.

## Gentoo

Gentoo and its derivatives are installed with `emerge` on both glibc and musl, with systemd or OpenRC. Before emerging packages, the installer writes the required USE flags (including `sound-server`, `pipewire-alsa`, `bluetooth`, `dbus`, and `echo-cancel` on `media-video/pipewire`, `vulkan` on `media-video/ffmpeg`, Qt6 Wayland/PipeWire/QML flags, and `weston` for the SDDM Wayland greeter) and testing keywords (`~amd64` / `~arm64`) to `/etc/portage/package.use/serpantinum` and `/etc/portage/package.accept_keywords/serpantinum` (or appends to `/etc/portage/package.use` and `/etc/portage/package.accept_keywords` when those are files).

Packages outside the main `gentoo` tree are pulled from overlays enabled via `eselect repository`:

- **GURU** (`eselect repository enable guru` and `emaint sync -r guru`), which provides `quickshell`, `matugen`, `cliphist`, `satty`, `gpu-screen-recorder`, `adw-gtk3`, `xwayland-satellite`, **Niri**, **Mango**, and **Umbriel**.
- **hyproverlay** (`eselect repository enable hyproverlay`), which is only enabled when you select **Hyprland**.

**Sway** comes from the main `gentoo` repository.

On systemd, the installer enables `NetworkManager`, `bluetooth`, `power-profiles-daemon`, and `sddm.service`, along with the `pipewire.socket`, `pipewire-pulse.socket`, and `wireplumber.service` user units.

On OpenRC, the installer adds `dbus`, `elogind`, `bluetooth`, `power-profiles-daemon`, and `NetworkManager` to the `default` runlevel. If `dhcpcd` or `wpa_supplicant` are enabled, they are removed from `default`, while an active `dhcpcd` or `net.*` connection stays running until reboot so your network is not interrupted. SDDM is enabled through `gui-libs/display-manager-init` by setting `DISPLAYMANAGER="sddm"` in `/etc/conf.d/display-manager` and adding `display-manager` to `default`. SDDM Wayland sessions are wrapped with `dbus-run-session` and `gentoo-pipewire-launcher` so D-Bus and PipeWire start automatically; if you launch your compositor from a TTY instead, start it with `dbus-run-session` and run `gentoo-pipewire-launcher` from its autostart.

## Arch Linux and derivatives

Arch Linux and its derivatives (EndeavourOS, Manjaro, CachyOS, Garuda, Artix and others) are supported on systemd, OpenRC and other init systems. Umbriel is installed from the AUR package `umbriel-git`, so an AUR helper is required; the installer sets up `yay` if none is present.
