# omarchy-mbp15-2016

**English** | [简体中文](README.zh-CN.md)

> Automated hardware enablement, GPU switching, and thermal cooling suite for MacBook Pro (15-inch, Late 2016 / `MacBookPro13,3`) in a **macOS + Omarchy (Arch Linux) dual-boot** configuration.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Target: MacBookPro13,3](https://img.shields.io/badge/Hardware-MacBookPro13%2C3-blue.svg)](#hardware-specification)
[![Setup: Dual Boot](https://img.shields.io/badge/Setup-macOS%20%2B%20Omarchy%20Dual%20Boot-brightgreen.svg)](#-critical-installation-notice-dual-boot-required-do-not-wipe-disk)
[![OS: Omarchy](https://img.shields.io/badge/OS-Omarchy%20%2F%20Arch-orange.svg)](https://omarchy.org)
[![Kernel: Linux 7.1.x/7.2.x](https://img.shields.io/badge/Kernel-Linux%207.1.x%2F7.2.x-brightgreen.svg)](#requirements)

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
- **Severe Overheating & High Idle Power**: The AMD discrete GPU runs constantly with memory clocks locked at maximum (drawing 10–15W idle), making the aluminum chassis uncomfortably hot.
- **The Touch Bar** remains dark or causes boot hangs due to kernel initialization races.
- **Wi-Fi** defaults to a placeholder MAC address (`00:90:4c:...`), locking out the 5GHz (Band 2) spectrum and causing high ping latency.
- **Internal speakers and headphone jack** lack audio output.
- **Suspend / sleep** fails or freezes the system when waking due to PCIe bus and NVMe D3cold power state conflicts with the AMD GPU.

**omarchy-mbp15-2016** provides a production-grade, battle-tested automated setup, thermal optimization, and diagnostic suite that resolves all these issues cleanly without touching disk partition tables or endangering existing macOS installations.

---

## Hardware Specification

| Component | Hardware Identifier | Linux Driver / Subsystem | Status |
| :--- | :--- | :--- | :---: |
| **Model** | `MacBookPro13,3` (15-inch, 2016) | DMI `product_name` | Supported |
| **Security Chip** | Apple T1 Coprocessor (`05ac:8600`) | `appleibridge` (late load) | Working |
| **Touch Bar** | 2170x60 OLED Multi-Touch Strip | `apple-ib-tb` DKMS + `touchbar.service` | Working |
| **Graphics** | Intel HD 530 (iGPU) + AMD Radeon Pro (dGPU) | `i915` + `amdgpu` + EFI `gpu-power-prefs` | Working (One-click toggle) |
| **Cooling & Fans** | Apple SMC Dual Fans + `mbpfan` active curve | `applesmc` + `coretemp` + `mbpfan` | Working (Active cooling + Turbo limits) |
| **Wi-Fi** | Broadcom BCM43602 (`14e4:43ba`) | `brcmfmac` + custom NVRAM firmware | Working (2.4G & 5G) |
| **Audio** | Cirrus Logic CS8409 HDA Codec | `snd_hda_macbookpro` DKMS | Working |
| **Keyboard / Trackpad** | Apple SPI Keyboard & Force Touch | Mainline `applespi` kernel module | Working |
| **Power / Suspend** | Apple NVMe Controller + PCIe PM | `s2idle` + NVMe D3cold override | Working |
| **Webcam** | FaceTime HD Camera | `uvcvideo` / V4L2 | Working |

---

## Key Features

- **Radical Thermal Taming & Flexible GPU Switching**:
  - **Decoupled Verification**: Touch Bar runs on internal USB HID and suspend relies on NVMe s2idle management—**completely decoupled from AMD GPU state**.
  - **Integrated Graphics (iGPU) Mode (`gpu-igpu`)**: Modifies Apple EFI variables to route internal display to Intel HD 530. The power-hungry AMD dGPU is powered down (0W), dropping idle consumption by 10–15W and temperatures to a cool ~38–45°C.
  - **Discrete Graphics (dGPU) Mode (`gpu-dgpu`)**: Toggle back to the AMD GPU whenever external USB-C displays or 3D compute are needed.
  - **`mbpfan` Active Thermal Daemon**: Overrides Apple SMC's sluggish default curve to aggressively vent heat before the body warms up.
  - **CPU Turbo Power Throttling**: Restrains Intel Turbo Boost spikes on battery to prevent sudden heat surges.
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

## Thermal Management & GPU Switching Guide

### Why Does the 2016 15" MBP Run Hot on Linux?
1. **AMD dGPU Clock Lock**: Linux EFI defaults to driving the 2880×1800 display via the AMD discrete GPU. Due to V-Blank timing constraints on Polaris 11, the memory clock locks at maximum (`1270 MHz`, `3D_FULL_SCREEN`), dissipating >10W constantly at idle.
2. **Passive Apple SMC Curves**: Factory SMC firmware prioritizes silence, keeping fans under 3000 RPM even when core temperatures climb beyond 65°C.
3. **Intel Turbo Spikes**: The 14nm Skylake CPU momentarily spikes up to 45W+ under light multi-threaded tasks.

### One-Click Solution: Switch to Intel HD 530 iGPU (Recommended)
If you do not need external monitors, forcing Intel integrated graphics is the **most definitive fix**:

```bash
# 1. Deploy mbpfan custom curve and CPU cooling policy
sudo ./omarchy-mbp15-2016.sh install-cooling

# 2. Switch EFI preference to Intel HD 530
sudo ./omarchy-mbp15-2016.sh gpu-igpu

# 3. Reboot
sudo reboot
```

> [!TIP]
> **Connecting External Displays Later**:
> External USB-C video outputs on `MacBookPro13,3` are physically hardwired to the AMD dGPU. If you ever need to connect external monitors, simply run:
> ```bash
> sudo ./omarchy-mbp15-2016.sh gpu-dgpu
> sudo reboot
> ```

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

The suite provides flexible installation options:

#### Option A: One-Shot Complete Installation (Recommended, includes thermal cool-down)
Installs all dependencies, calibrates 5GHz Wi-Fi with your physical macOS MAC, builds Cirrus audio and Touch Bar DKMS drivers, deploys suspend/NVMe services and `mbpfan` cooling, suppresses phantom displays, and switches EFI preference to Intel HD 530 iGPU in a single command:
```bash
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF --switch-igpu
```

> [!NOTE]
> If you frequently connect to external monitors, simply omit `--switch-igpu` to keep AMD dGPU output enabled. You can always toggle between iGPU and dGPU later via `gpu-igpu` and `gpu-dgpu`.

#### Option B: Full Install Skipping Wi-Fi NVRAM
Installs audio, Touch Bar, suspend fixes, cooling, and optional iGPU switch, while keeping the current Wi-Fi NVRAM firmware table untouched:
```bash
sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram --switch-igpu
```

#### Option C: Targeted Thermal Cooling Only (Fast, seconds)
Exclusively deploys the tuned `mbpfan` fan daemon, CPU thermal power limits, and phantom display suppression:
```bash
sudo ./omarchy-mbp15-2016.sh install-cooling
```

#### Installation Modes Comparison

| Command | 5GHz Wi-Fi Calibration | Cirrus Audio DKMS | Touch Bar DKMS | Suspend & NVMe D3cold | mbpfan Active Cooling | EFI iGPU Switch (Cooling) | Expected Duration |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `install ... --switch-igpu` | ✅ Injects physical MAC | ✅ Builds & Deploys | ✅ Builds & Deploys | ✅ Enables Service | ✅ Enables Service | ✅ Sets Intel HD 530 (0W dGPU) | ~2-3 mins |
| `install --wifi-mac <MAC>` | ✅ Injects physical MAC | ✅ Builds & Deploys | ✅ Builds & Deploys | ✅ Enables Service | ✅ Enables Service | ➖ Keeps Current GPU | ~2-3 mins |
| `install --skip-wifi-nvram` | ❌ Skipped | ✅ Builds & Deploys | ✅ Builds & Deploys | ✅ Enables Service | ✅ Enables Service | ➖ Keeps Current GPU | ~2-3 mins |
| `install-cooling` | ❌ Skipped | ❌ Skipped | ❌ Skipped | ❌ Skipped | ✅ Enables Service | ❌ Skipped | **A few seconds** |
| `install-suspend` | ❌ Skipped | ❌ Skipped | ❌ Skipped | ✅ Enables Service | ❌ Skipped | ❌ Skipped | **A few seconds** |
| `gpu-igpu` | ❌ Skipped | ❌ Skipped | ❌ Skipped | ❌ Skipped | ❌ Skipped | ✅ Sets Intel HD 530 | **A few seconds** |

### 4. Reboot

```bash
sudo reboot
```

### 5. Verify Hardware Gates

```bash
sudo ./omarchy-mbp15-2016.sh verify
```

---

## Command Quick Reference

| Command | Description |
| :--- | :--- |
| `sudo ./omarchy-mbp15-2016.sh status` | Inspect kernel, active GPU, thermal curves, boot parameters, and driver states |
| `sudo ./omarchy-mbp15-2016.sh install --wifi-mac <MAC>` | Full installation: dependencies, Wi-Fi 5GHz calibration, audio, Touch Bar, suspend, and cooling |
| `sudo ./omarchy-mbp15-2016.sh install-cooling` | Deploy tuned `mbpfan` service and CPU thermal limit configuration |
| `sudo ./omarchy-mbp15-2016.sh gpu-igpu` | Switch EFI to Intel HD 530 integrated graphics (ultimate cooling; reboot required) |
| `sudo ./omarchy-mbp15-2016.sh gpu-dgpu` | Switch EFI to AMD Radeon Pro discrete graphics (for external monitors; reboot required) |
| `sudo ./omarchy-mbp15-2016.sh install-suspend` | Deploy NVMe D3cold fix and Limine s2idle configuration |
| `sudo ./omarchy-mbp15-2016.sh install-touchbar` | Rebuild and deploy Touch Bar & Apple T1 iBridge DKMS driver and systemd service |
| `sudo ./omarchy-mbp15-2016.sh install-audio` | Rebuild and deploy Cirrus Logic CS8409 audio DKMS driver |
| `sudo ./omarchy-mbp15-2016.sh verify` | Validate active GPU, thermals, Wi-Fi MAC, SPI keyboard/trackpad, audio, Touch Bar, and NVMe |
| `sudo ./omarchy-mbp15-2016.sh pm-test` | Run `pm_test=devices` staged suspend and resume cycle |
| `sudo ./omarchy-mbp15-2016.sh previous-boot` | Retrieve kernel suspend/resume logs from the previous boot |
| `sudo ./omarchy-mbp15-2016.sh rollback` | Restore original configuration files, disable services, and update Limine |

---

## Uninstallation & Rollback

```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```

---

## Upstream Acknowledgements

- [omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1) by nohzafk (Touch Bar & T1 iBridge Linux drivers)
- [snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) by davidjo (Cirrus Logic CS8409 audio driver)
- [mbpfan](https://github.com/linux-on-mac/mbpfan) by linux-on-mac (MacBook thermal fan daemon)
- [gpu-switch](https://github.com/0xbb/gpu-switch) by 0xbb (MacBook Pro dual GPU EFI switching logic)
- [Omarchy](https://omarchy.org) team and Arch Linux community.

---

## License

This project is licensed under the [MIT License](LICENSE).
