# Arch Linux + i3 Dotfiles

A comprehensive, replica-ready configuration for Arch Linux using **i3-wm** and **LightDM**. Managed via **YADM**.

## 📋 Overview
* **Window Manager:** i3-wm
* **Display Manager:** LightDM (GTK Greeter)
* **Terminal:** Kitty
* **Shell:** Bash
* **AUR Helper:** yay-bin
* **Features:** Complete setup including Audio (Pipewire), Networking, Fonts, and Dev Tools.

## 🚀 Installation (Fresh Install)

1.  **Install Arch Linux** (Base system).
2.  **Install YADM and Git**:
    ```bash
    pacman -S git yadm
    ```
3.  **Clone this repository**:
    ```bash
    yadm clone <YOUR_REPO_URL>
    ```
4.  **Run the Bootstrap Script**:
    This script will install all packages, enable services, and fix permissions.
    ```bash
    yadm bootstrap
    ```

## 📦 Package Management
The installation logic is modular. To add/remove programs, edit these text files:

* **`pkg.txt`**: List of official Arch packages (pacman).
* **`pkg-aur.txt`**: List of AUR packages (yay).
* **`bootstrap`**: The main installer script.

## ⚠️ Notes
* **System Update:** The bootstrap script asks if you want to perform a full system update (`-Syu`) or just a local update (`-Su`) to save data.
* **Nvidia GPU:** If you use a legacy Nvidia card, uncomment the driver lines in `pkg-aur.txt`.
* **Font Cache:** You can skip the font cache update during bootstrap to save time.

## ⌨️ Quick Controls
* **Reload i3:** `Mod + Shift + R`
* **Terminal:** `Mod + Enter`
* **Menu (Rofi):** `Mod + D`
