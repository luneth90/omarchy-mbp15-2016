# omarchy-mbp15-2016

**English** | [简体中文](README.zh-CN.md)

> Automated hardware enablement and driver integration suite for MacBook Pro (15-inch, Late 2016 / `MacBookPro13,3`) on Omarchy (Arch Linux).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Target: MacBookPro13,3](https://img.shields.io/badge/Hardware-MacBookPro13%2C3-blue.svg)](#hardware-specification)
[![OS: Omarchy](https://img.shields.io/badge/OS-Omarchy%20%2F%20Arch-orange.svg)](https://omarchy.org)
[![Kernel: Linux 7.1.x](https://img.shields.io/badge/Kernel-Linux%207.1.x-brightgreen.svg)](#requirements)

---

## Overview

Running Linux on Apple hardware from the 2016 Touch Bar era presents notorious hardware integration challenges. The 15-inch Late 2016 MacBook Pro (`MacBookPro13,3`) features a complex hardware topology: an Apple T1 security coprocessor (iBridge), a dynamic OLED Touch Bar, dual graphics (Intel HD 530 + AMD Radeon Pro 450/455/460 via `apple_gmux`), Cirrus Logic CS8409 high-definition audio, and a Broadcom BCM43602 PCIe Wi-Fi chip.

Out of the box on standard Linux installations:
- The **Touch Bar** remains dark or causes boot hangs due to kernel initialization races.
- **Wi-Fi** defaults to a placeholder MAC address (`00:90:4c:...`), locking out the 5GHz (Band 2) spectrum and causing high ping latency.
- **Internal speakers and headphone jack** lack audio output.
- **Suspend / sleep** fails or freezes the system when waking due to PCIe bus and NVMe D3cold power state conflicts with the AMD GPU.

**omarchy-mbp15-2016** provides a production-grade, battle-tested automated setup and diagnostic suite that resolves all these issues cleanly without touching disk partition tables or endangering existing macOS installations.

---

## Hardware Specification

| Component | Hardware Identifier | Linux Driver / Subsystem | Status |
| :--- | :--- | :--- | :---: |
| **Model** | `MacBookPro13,3` (15-inch, 2016) | DMI `product_name` | Supported |
| **Security Chip** | Apple T1 Coprocessor (`05ac:8600`) | `appleibridge` (late load) | Working |
| **Touch Bar** | 2170x60 OLED Multi-Touch Strip | `apple-ib-tb` DKMS + `touchbar.service` | Working |
| **Wi-Fi** | Broadcom BCM43602 (`14e4:43ba`) | `brcmfmac` + custom NVRAM firmware | Working (2.4G & 5G) |
| **Audio** | Cirrus Logic CS8409 HDA Codec | `snd_hda_macbookpro` DKMS | Working |
| **Keyboard / Trackpad** | Apple SPI Keyboard & Force Touch | Mainline `applespi` kernel module | Working |
| **Graphics** | Intel HD 530 + AMD Radeon Pro | `i915` + `amdgpu` + `apple_gmux` | Working |
| **Power / Suspend** | Apple NVMe Controller + PCIe PM | `s2idle` + NVMe D3cold override | Working |
| **Webcam** | FaceTime HD Camera | `uvcvideo` / V4L2 | Working |

---

## Key Features

- **Touch Bar & T1 Stabilization**:
  - Automatically builds and installs the `appleibridge` and `apple-ib-tb` DKMS kernel modules.
  - Blacklists early module loading to prevent race conditions and boot freezes.
  - Deploys `touchbar.service` for controlled post-boot initialization (defaults to multimedia strip, toggles to F1–F12 with the Fn key).
  - Configures `/usr/lib/systemd/system-sleep/90-mbp-touchbar-resume` hook for automatic driver reload upon wake.
- **Full 5GHz Wi-Fi Calibration**:
  - Pulls the correct BCM43602 NVRAM firmware table.
  - Replaces Broadcom's dummy placeholder MAC with your physical macOS Wi-Fi MAC, unlocking Band 2 (5GHz 802.11ac) channels and eliminating latency spikes.
- **Native Cirrus Audio DKMS**:
  - Builds and installs `snd_hda_macbookpro` for full ALSA/PipeWire routing across quad speakers and 3.5mm jack.
- **Rock-Solid Sleep / Resume**:
  - Configures `systemd-sleep` to `freeze` / `s2idle`.
  - Injects `mem_sleep_default=s2idle`, `iommu=pt`, `intel_iommu=on`, and `pcie_ports=compat` into Limine bootloader.
  - Deploys `mbp15-nvme-d3cold.service` to dynamically disable `d3cold_allowed` on active Apple NVMe controllers, avoiding sleep crashes.
- **Safety First & Safe Rollback**:
  - Pre-flight checks strictly enforce model identity (`MacBookPro13,3`) and T1 health (`05ac:8600`).
  - Never repartitions disks or modifies Apple APFS / EFI partitions.
  - One-command rollback restores original configuration files and removes installed services.

---

## Requirements

- **Device**: Apple MacBook Pro 15-inch (Late 2016, Touch Bar, `MacBookPro13,3`).
- **Operating System**: [Omarchy](https://omarchy.org) / Arch Linux.
- **Kernel**: Linux 7.1.x series (`linux`, `linux-headers`).
- **Bootloader**: Limine (`limine-entry-tool`, `limine-update`).
- **Permissions**: Root (`sudo`).

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/luneth90/omarchy-mbp15-2016.git
cd omarchy-mbp15-2016
chmod +x omarchy-mbp15-2016.sh
```

### 2. Check Current Hardware Status

```bash
sudo ./omarchy-mbp15-2016.sh status
```

### 3. Install All Drivers & Fixes

> [!IMPORTANT]
> To enable full 5GHz Wi-Fi channels, obtain your MacBook's real macOS Wi-Fi MAC address (e.g., from macOS `networksetup -getmacaddress en0` or your router's client list). Do **not** use a placeholder MAC starting with `00:90:4c:`.

With real Wi-Fi MAC:
```bash
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF
```

Or skip Wi-Fi NVRAM update if your Wi-Fi is already calibrated:
```bash
sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram
```

### 4. Reboot

```bash
sudo reboot
```

### 5. Verify Hardware Gates

After rebooting, run the automated verification suite:
```bash
sudo ./omarchy-mbp15-2016.sh verify
```

### 6. Test Sleep / Resume

Run simulated device-level power management testing before executing a physical suspend:
```bash
sudo ./omarchy-mbp15-2016.sh pm-test
```

Inspect kernel and sleep journal logs from the previous boot cycle:
```bash
sudo ./omarchy-mbp15-2016.sh previous-boot
```

---

## Available Commands

| Command | Description |
| :--- | :--- |
| `sudo ./omarchy-mbp15-2016.sh status` | Inspect active kernel, boot parameters, and status of all peripherals |
| `sudo ./omarchy-mbp15-2016.sh install` | Install all required packages, DKMS modules, systemd services, and Limine parameters |
| `sudo ./omarchy-mbp15-2016.sh verify` | Validate Wi-Fi MAC, SPI devices, audio cards, Touch Bar sysfs controls, and NVMe D3cold |
| `sudo ./omarchy-mbp15-2016.sh pm-test` | Staged PM test (`pm_test=devices`) to safely verify driver suspend/resume |
| `sudo ./omarchy-mbp15-2016.sh previous-boot` | Query systemd and dmesg logs from the previous boot session for PM debugging |
| `sudo ./omarchy-mbp15-2016.sh rollback` | Revert all configuration files, mask changes, and disable created services |

---

## Rollback

To cleanly uninstall and restore all original files:

```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```

---

## Upstream & Acknowledgments

This project builds upon vital community reverse-engineering efforts:
- [omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1) by nohzafk (Touch Bar & T1 iBridge Linux drivers)
- [snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) by davidjo (Cirrus Logic CS8409 audio driver)
- The [Omarchy](https://omarchy.org) project and the Arch Linux community.

---

## License

This project is licensed under the [MIT License](LICENSE).
