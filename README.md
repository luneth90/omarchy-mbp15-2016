# omarchy-mbp15-2016

**English** | [简体中文](README.zh-CN.md)

> Automated hardware enablement and driver integration suite for MacBook Pro (15-inch, Late 2016 / `MacBookPro13,3`) in a **macOS + Omarchy (Arch Linux) dual-boot** configuration.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Target: MacBookPro13,3](https://img.shields.io/badge/Hardware-MacBookPro13%2C3-blue.svg)](#hardware-specification)
[![Setup: Dual Boot](https://img.shields.io/badge/Setup-macOS%20%2B%20Omarchy%20Dual%20Boot-brightgreen.svg)](#-critical-installation-notice-dual-boot-required-do-not-wipe-disk)
[![OS: Omarchy](https://img.shields.io/badge/OS-Omarchy%20%2F%20Arch-orange.svg)](https://omarchy.org)
[![Kernel: Linux 7.1.x](https://img.shields.io/badge/Kernel-Linux%207.1.x-brightgreen.svg)](#requirements)

---

## ⚠️ Critical Installation Notice: Dual Boot Required (Do NOT Wipe Disk)

> [!CAUTION]
> **This suite MUST be used in a dual-boot setup alongside macOS. A clean wipe/format will permanently break Touch Bar functionality!**
> 
> - **Touch Bar Firmware Dependency**: The OLED Touch Bar on the 2016 MacBook Pro is managed by an independent **Apple T1 security coprocessor (iBridge)** running embeddedOS/bridgeOS. During boot, the T1 chip relies on Apple's native EFI and proprietary firmware environment provided by the macOS partition to initialize.
> - **Consequence of Formatting the Whole Drive**: If you wipe/reformat the entire SSD to install Linux as a single OS, **the necessary Touch Bar firmware is lost**. The T1 coprocessor will fail to initialize and will drop into DFU recovery mode (reporting USB ID `05ac:1281` instead of the operational `05ac:8600`). In this state, **no Linux driver can initialize or light up the Touch Bar—it will stay completely black and non-functional**.
> - **Recommended Dual-Boot Installation Workflow**:
>   1. Boot into macOS and open **Disk Utility**;
>   2. Select the "Macintosh HD" APFS container, click **Partition**, and shrink the container to allocate unallocated free space (60 GB or more recommended) for Omarchy;
>   3. Run `networksetup -getmacaddress en0` in the macOS terminal to record your true physical Wi-Fi MAC address;
>   4. Boot the Omarchy / Arch Linux installer and **install Linux only into the free unallocated space**, preserving the macOS APFS container, Recovery partition, and Apple EFI partition;
>   5. Boot into Omarchy and run this suite to enable all drivers.

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
| **Fans & Thermal** | Apple SMC (Dual Fans + Thermal Sensors) | `applesmc` + `coretemp` | Working (Firmware-managed, mbpfan optional) |

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
- **Firmware-Managed Dual Fan & Thermal Control**:
  - Mainline `applesmc` and `coretemp` drivers natively read all zone temperature sensors and dual-fan telemetry.
  - Apple SMC hardware firmware autonomously manages thermal throttling and dynamic fan curves in a closed loop (i.e. `mbpfan is not needed`; users seeking aggressive cooling curves may still optionally install `mbpfan`).
  - Automated status inspection and verification gates audit SMC fan RPMs and operating modes.
- **Rock-Solid Sleep / Resume**:
  - Configures `systemd-sleep` to `freeze` / `s2idle`.
  - Injects `mem_sleep_default=s2idle`, `iommu=pt`, `intel_iommu=on`, and `pcie_ports=compat` into Limine bootloader.
  - Deploys `mbp15-nvme-d3cold.service` to dynamically disable `d3cold_allowed` on active Apple NVMe controllers, avoiding sleep crashes.
- **Safety First & Safe Rollback**:
  - Pre-flight checks strictly enforce model identity (`MacBookPro13,3`) and T1 health (`05ac:8600`; fails immediately with clear error if T1 dropped into DFU recovery mode `05ac:1281` due to missing firmware after a full disk wipe).
  - Never repartitions disks or modifies Apple APFS / EFI partitions.
  - One-command rollback restores original configuration files and removes installed services.

---

## Requirements

- **Setup Mode**: **macOS + Omarchy Dual Boot** (must preserve original macOS partition and Apple EFI; clean format installs will leave Touch Bar without firmware).
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

### 3. Install Drivers & System Configurations

> [!IMPORTANT]
> 1. **Dual-Boot Environment**: Ensure this machine retains its original macOS partitions and firmware environment. Do not wipe or format the entire drive, or Touch Bar firmware will be lost and cannot be driven.
> 2. **Wi-Fi 5GHz Calibration**: To enable full 5GHz Wi-Fi channels, obtain your MacBook's real macOS Wi-Fi MAC address (e.g., from macOS `networksetup -getmacaddress en0` or your router's client list). Do **not** use a placeholder MAC starting with `00:90:4c:`.

The suite provides three flexible installation modes depending on your needs:

#### Option A: Full Automated Installation (Recommended for first-time setup)
Installs all dependencies, calibrates 5GHz Wi-Fi with your physical macOS MAC, builds Cirrus audio and Touch Bar DKMS drivers, and deploys suspend/NVMe services:
```bash
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF
```

#### Option B: Full Install Skipping Wi-Fi NVRAM
Installs audio, Touch Bar, and suspend fixes, while keeping the current Wi-Fi NVRAM firmware table untouched (useful if already calibrated or MAC is unknown):
```bash
sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram
```

#### Option C: Targeted Suspend & NVMe Fix Only (Fast, seconds)
Skips lengthy DKMS kernel builds and exclusively deploys `mbp15-nvme-d3cold.service` along with Limine `s2idle` and IOMMU kernel parameters to prevent sleep/wake crashes:
```bash
sudo ./omarchy-mbp15-2016.sh install-suspend
```

#### Installation Modes Comparison

| Command | 5GHz Wi-Fi Calibration | Cirrus Audio DKMS | Touch Bar DKMS | Suspend & NVMe D3cold | Expected Duration |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `install --wifi-mac <MAC>` | ✅ Injects physical MAC | ✅ Builds & Deploys | ✅ Builds & Deploys | ✅ Enables Service | ~2-3 mins |
| `install --skip-wifi-nvram` | ❌ Skipped | ✅ Builds & Deploys | ✅ Builds & Deploys | ✅ Enables Service | ~2-3 mins |
| `install-suspend` | ❌ Skipped | ❌ Skipped | ❌ Skipped | ✅ Enables Service | **A few seconds** |

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
| `sudo ./omarchy-mbp15-2016.sh install --wifi-mac <MAC>` | [Recommended] Full setup: calibrate 5GHz Wi-Fi, build audio/Touch Bar DKMS, and deploy suspend fixes |
| `sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram` | Full setup for audio, Touch Bar, and suspend, while skipping Wi-Fi NVRAM updates |
| `sudo ./omarchy-mbp15-2016.sh install-suspend` | Fast targeted setup: deploy `mbp15-nvme-d3cold.service` and Limine s2idle/IOMMU suspend parameters |
| `sudo ./omarchy-mbp15-2016.sh install-touchbar` | Rebuild and deploy only the Apple T1 and Touch Bar DKMS drivers and resume hooks |
| `sudo ./omarchy-mbp15-2016.sh install-audio` | Rebuild and deploy only the Cirrus CS8409 audio DKMS driver |
| `sudo ./omarchy-mbp15-2016.sh verify` | Validate Wi-Fi MAC, SPI devices, audio cards, Touch Bar, SMC fans & thermal, and NVMe D3cold |
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
