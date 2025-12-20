# OpenZONE: Zotac Zone Linux Drivers & Manager
[![OpenZONE Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/YFhK768cex)
![License](https://img.shields.io/badge/license-GPL-blue.svg) ![Platform](https://img.shields.io/badge/platform-Linux-green.svg)

**OpenZONE** is a complete driver suite for the **Zotac Zone** handheld gaming console running Bazzite or Fedora. It enables full hardware functionality including the Radial Dials, RGB lighting, Back Buttons and Fans.

## ✨ Features

* **Kernel Drivers:** Full HID and Platform support (Battery, Fan, Thermals).
* **Radial Dials:** Map the mechanical dials to Volume, Brightness, Scroll, Zoom, or Arrows.
* **RGB Lighting:** Control both rear halo zones (Static, Breathe, Wave, Cycle).
* **Back Buttons:** Remap M1 and M2 to Gamepad buttons, Keyboard keys, or Mouse clicks.
* **Deadzones:** Calibrate stick deadzones to eliminate drift.
* **Vibration:** Adjust Trigger and Rumble motor intensity.
* **GUI Manager:** A terminal-based graphical interface to configure everything on the fly.

---

## 🚀 Installation

To install the drivers and the manager, you only need to download and run the installer script.

1.  **Download the installer:**
    You can download `install_openzone_drivers.sh` manually from the repository files, or use the command below:
    ```bash
    wget https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/main/install_openzone_drivers.sh
    ```

2.  **Make it executable:**
    ```bash
    chmod +x install_openzone_drivers.sh
    ```

3.  **Run the installer:**
    ```bash
    sudo ./install_openzone_drivers.sh
    ```

![Installer Interface](/img/openzone_installer.png)

The script will automatically compile the drivers, set up the services, and download the OpenZone Manager for you.

---

## 🎮 Usage: OpenZone Manager

Once installed, you can configure your device settings (RGB, Dials, Mappings) using the manager script.

**To run the manager:**
```bash
sudo ./openzone_manager.sh
```
*(If you are in the directory where it was downloaded. If you moved it to a bin folder, just run the command).*

![Installer Interface](/img/openzone_manager.png)

### Manager Features:
1.  **Back Buttons (M1/M2):** Map them to keys like `Space`, `Enter`, or gamepad buttons like `A`, `B`.
2.  **RGB Control:** Select effects like "Wave" or set a static hex color.
3.  **Dial Config:** Change what the Left/Right dials do (e.g., set Left to Volume and Right to Scroll).
4.  **Deadzones:** Set the inner deadzone percentage (default is usually 0-5%).
5.  **Vibration:** Turn off haptics or lower the intensity.

> **Note:** Changes made in the manager are saved immediately to the system configuration or the controller's onboard memory.

---

## 🗑️ Uninstallation

If you wish to remove the drivers, services, and configuration files completely, simply run the uninstall script provided in the repository.

```bash
sudo ./uninstall_openzone_drivers.sh
```

This will:
* Stop and disable the `zotac-zone-drivers` and `zotac-dials` services.
* Unload the kernel modules.
* Remove the installed driver files from `/usr/local/lib/zotac-zone`.
* Clean up systemd service files.

---

## ⚠️ Requirements & Compatibility

* **OS:** Linux (Bazzite, Fedora Atomic, Arch, etc.)
* **Kernel Headers:** Must be installed for your current kernel version to compile the driver.
    * *Bazzite/Fedora:* `rpm-ostree install kernel-devel-$(uname -r) gcc make`
* **Secure Boot:** If Secure Boot is enabled, you may need to sign the kernel modules manually, or disable Secure Boot.

## 🤝 Credits

* **Kernel Drivers:** [flukejones](https://github.com/flukejones)
* **Installer & Manager:** Pfahli
* **Testing:** OpenZONE Community
