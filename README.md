# omarchy-mbp15-2016

**English** | [简体中文](README.zh-CN.md)

Hardware setup and diagnostics script for the 2016 15-inch Touch Bar MacBook Pro (`MacBookPro13,3`) running Omarchy / Arch Linux.

---

## 1. Dual-Boot Preparation & Notes

Before running the installation, note these key preparation steps:

- **Preserve macOS and dual-boot layout**: Do NOT wipe the disk completely. Keep macOS, Apple EFI, and Recovery intact. Wiping the macOS / T1 firmware environment causes the Touch Bar to lose firmware support and enter `05ac:1281` DFU recovery mode.
- **Obtain your real Wi-Fi MAC address**: Boot into macOS, open Terminal, and run:
  ```bash
  networksetup -getmacaddress en0
  ```
  Record this address. It is required to calibrate the Broadcom BCM43602 Wi-Fi NVRAM file. Do not use placeholder or virtual MACs.
- **Supported GPU models**: Apple Radeon Pro 450, 455, and 460 (`1002:67ef`, subsystems `106b:0167/0166/0160`).
- **Clean legacy overrides (optional)**: If you previously tested an older script release, remove legacy display and forced sleep overrides:
  ```bash
  sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all
  ```

---

## 2. One-Command Default Installation

Make the script executable and run the single default installation command:

```bash
chmod +x omarchy-mbp15-2016.sh
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF
```

> **Tip**: If you have already installed and calibrated the Wi-Fi NVRAM, you can use `--skip-wifi-nvram` instead:
> ```bash
> sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram
> ```

This single command sets up the recommended stable daily-use hardware profile:
1. **Base dependencies**: Installs build tools and exact running-kernel headers.
2. **Wi-Fi networking**: Installs BCM43602 NVRAM calibrated with your real macOS MAC.
3. **Cooling & thermals**: Applies conservative CPU thermal policy and sets up the `mbpfan` fan daemon.
4. **Touch Bar**: Builds and installs the pinned T1/Touch Bar DKMS driver and auto-load service.
5. **Audio**: Builds and installs the internal sound card DKMS driver (`snd_hda_macbookpro`).

The default profile keeps the **AMD discrete GPU** active (internal audio works, both internal panel and external USB-C displays work), and deliberately leaves iGPU switching and suspend untouched for maximum out-of-the-box stability.

### Reboot and Verify

Reboot your machine, then run the verification command:

```bash
sudo reboot
# After logging in:
sudo ./omarchy-mbp15-2016.sh verify
```

`verify` checks all installed components and services. Once you have verified internal speakers, headphones, microphone, and the Touch Bar, your system is ready for daily use.

---

## 3. Standalone Setup: iGPU Switching

On `MacBookPro13,3`, non-macOS boot loaders expose only the AMD dGPU by default. Switching to the Intel integrated GPU (for reduced power consumption and lower heat) requires the bootloader to coordinate exposing the iGPU.

> **Note**: USB-C video outputs are wired directly to the AMD dGPU. In iGPU mode, external displays are generally unavailable. Always disconnect external monitors before switching.

### Step 1: Configure `apple_set_os` in your bootloader
Configure your bootloader to execute `apple_set_os.efi` before booting Linux (for example, in rEFInd's `refind.conf` via `spoof_osx_version 10.12`). Reboot while keeping the AMD dGPU active.

### Step 2: Confirm Intel iGPU is exposed and handled by kernel
After booting, check that the Intel graphics device is visible and bound to `i915`:
```bash
lspci -nnk -s 00:02.0
```
The output must show Intel graphics with `Kernel driver in use: i915`. Do not proceed if this is not met.

### Step 3: Switch to iGPU and reboot
Disconnect all external displays and run:
```bash
sudo ./omarchy-mbp15-2016.sh gpu-igpu --yes
sudo reboot
```
> **Automatic Fallback Protection**: To prevent getting locked out by a black screen, the script arms an automatic fallback on the first iGPU boot: if the session is not explicitly confirmed, the next reboot automatically reverts to AMD.

### Step 4: Verify and confirm the iGPU session
Once you reach the desktop and confirm the display, keyboard, and trackpad are working properly:
```bash
sudo ./omarchy-mbp15-2016.sh verify-gpu
sudo ./omarchy-mbp15-2016.sh gpu-confirm-igpu --yes
```
This confirms the configuration and permanently sets Intel as the preferred GPU.

> **Switching back to AMD dGPU at any time**:
> ```bash
> sudo ./omarchy-mbp15-2016.sh gpu-dgpu --yes
> sudo reboot
> ```

---

## 4. Standalone Setup: Suspend

Due to MacBook hardware and power management constraints, suspend is an experimental feature on this model. It is recommended to configure suspend only after iGPU mode is confirmed and running stably.

### Step 1: Install suspend configuration
```bash
sudo ./omarchy-mbp15-2016.sh install-suspend
sudo reboot
```
This adds the `pcie_ports=compat` boot parameter and enables the NVMe D3cold override service to prevent NVMe disconnects and PCIe controller lockups upon wake.

### Step 2: Verify suspend configuration
After rebooting:
```bash
sudo ./omarchy-mbp15-2016.sh verify-suspend
```

### Step 3: Test suspend
Perform a device-level suspend test to verify that devices resume cleanly:
```bash
sudo ./omarchy-mbp15-2016.sh pm-test --yes
```
If the test succeeds, save all open work and trigger a real suspend manually:
```bash
sudo systemctl suspend
```
Wake the system using the lid or keyboard and confirm that peripherals and networking resume normally.

---

## 5. Troubleshooting & Rollback

### Inspecting Previous Boot Logs
If you experience a black screen, freeze, or wake failure, reboot into the system (via the AMD fallback or macOS) and inspect the previous boot logs:
```bash
sudo ./omarchy-mbp15-2016.sh previous-boot
sudo journalctl -b -1 -k
```

### Rollback
To remove installed drivers and restore the original system state:
```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```
Rollback restores the original EFI GPU preference, uninstalls DKMS drivers, stops script services, and refreshes the bootloader.

---

## 6. Command Reference

| Command | Description |
| :--- | :--- |
| `status` | Display current hardware, driver, and kernel configuration status |
| `install --wifi-mac <MAC>` | Install the complete default hardware profile (excludes iGPU and suspend) |
| `install --skip-wifi-nvram` | Install default hardware profile while skipping Wi-Fi NVRAM |
| `verify` | Verify all default hardware modules and services after reboot |
| `cleanup-legacy-all [--dry-run]` | Inspect / remove legacy display and forced sleep overrides |
| `gpu-igpu --yes` | Set next-boot preference to Intel iGPU with automatic AMD fallback |
| `gpu-confirm-igpu --yes` | Confirm working Intel session and disable automatic fallback |
| `gpu-dgpu --yes` | Set next-boot preference to AMD dGPU |
| `verify-gpu` | Check current active display GPU and next-boot EFI setting |
| `install-suspend` | Install minimal PCIe compat parameter and NVMe D3cold fix service |
| `verify-suspend` | Verify suspend and NVMe configuration status |
| `pm-test --yes` | Run device-level suspend and resume test |
| `previous-boot` | Inspect previous-boot suspend/resume and kernel error logs |
| `rollback` | Revert configuration changes, restore original EFI vars, and remove DKMS |

---

## Upstream References

- T1 / Touch Bar: [nohzafk/omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1)
- Internal Audio: [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)
- Fan Daemon: [linux-on-mac/mbpfan](https://github.com/linux-on-mac/mbpfan)
- EFI GPU Switching: [0xbb/gpu-switch](https://github.com/0xbb/gpu-switch)
- Hardware Reference: [Dunedan/mbp-2016-linux](https://github.com/Dunedan/mbp-2016-linux)

## License

[MIT](LICENSE)
