# omarchy-mbp15-2016

**English** | [简体中文](README.zh-CN.md)

Staged Omarchy/Arch hardware setup and diagnostics for the 2016 15-inch Touch Bar MacBook Pro (`MacBookPro13,3`).

Code review and automated tests are not target-hardware certification. The pinned T1 recipe was reported upstream on another T1 Mac, so every stage still needs physical validation on `MacBookPro13,3`. DKMS installation is restricted to the reviewed Linux `7.1.x/7.2.x` families.

## Critical iGPU warning

On this model, non-macOS firmware boots normally expose only the AMD GPU. Writing `gpu-power-prefs` without a boot chain that executes `apple_set_os` can leave Intel unavailable and the internal panel black. USB-C display outputs normally depend on the AMD GPU, so an external monitor is not a reliable iGPU recovery path.

This version deliberately has no one-shot full install. GPU commands admit only Apple Radeon Pro 450/455/460 (`1002:67ef`, subsystems `106b:0167/0166/0160`). `gpu-igpu` refuses to proceed unless Intel `00:02.0` is visible, bound to `i915`, all external displays are disconnected, and legacy display/sleep/IOMMU overrides are gone. GPU commands never hot-switch graphics or write `AQ_DRM_DEVICES`, DRM card numbers, or eDP connector names. The first iGPU boot automatically selects AMD for the following reboot unless the working Intel session is explicitly confirmed.

Keep macOS, Apple EFI, and Recovery intact. See the upstream model notes in [Dunedan/mbp-2016-linux](https://github.com/Dunedan/mbp-2016-linux).

## Safe staged installation

The recommended daily-use baseline keeps the AMD GPU active and includes working internal audio. iGPU switching and suspend are separate experiments, not part of the default installation path.

### 0. Freeze the test environment and prepare recovery

For a fresh target deployment, prefer Omarchy `stable`; `edge` is not a prerequisite. If the machine already runs a working `edge` installation, do not change channel just for this script. Record the exact environment and do not update Omarchy, change kernel, switch channel, or pull a newer script revision between stages:

```bash
omarchy channel current
omarchy version
uname -r
git rev-parse HEAD
```

Keep macOS, Apple EFI, and Recovery bootable. Confirm that a known-good AMD or older-kernel entry is available, save all work, disconnect docks/displays and nonessential peripherals, and record the real Wi-Fi MAC in macOS with `networksetup -getmacaddress en0`.

### 1. Verify the target and remove legacy overrides first

```bash
chmod +x omarchy-mbp15-2016.sh
sudo ./omarchy-mbp15-2016.sh status
lspci -nnv -s 01:00.0
sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all --dry-run
```

For a Radeon Pro 460, the PCI output must contain device `1002:67ef` and Apple subsystem `106b:0160`. Do not continue when the physical identity is not the expected machine. If and only if the dry run reports legacy settings from an older script, remove them before installing anything else:

```bash
sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all
sudo reboot
sudo ./omarchy-mbp15-2016.sh status
```

### 2. Install the base and establish an AMD baseline

```bash
sudo ./omarchy-mbp15-2016.sh install-base
sudo reboot
sudo ./omarchy-mbp15-2016.sh status
```

`install-base` installs dependencies and checks the exact running-kernel headers. It does not install a hardware driver, change GPU preference, or install suspend configuration. Verify several successful AMD cold boots/reboots before continuing.

### 3. Install required hardware stages one at a time

Install and verify lower-risk stages first:

```bash
sudo ./omarchy-mbp15-2016.sh install-cooling
sudo ./omarchy-mbp15-2016.sh verify-cooling

sudo ./omarchy-mbp15-2016.sh install-wifi AA:BB:CC:DD:EE:FF
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-wifi

sudo ./omarchy-mbp15-2016.sh install-touchbar
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-touchbar
```

Apple SMC already manages the fans. Active fan control remains an optional, separate stage:

```bash
sudo ./omarchy-mbp15-2016.sh install-mbpfan
```

### 4. Install required audio last in the AMD baseline

Internal audio is required for a complete installation on this machine. Its out-of-tree driver has kernel-specific crash reports, so it is installed alone after every other required stage is stable. The source is pinned and explicit acknowledgement is required, but future-kernel compatibility cannot be guaranteed:

```bash
sudo ./omarchy-mbp15-2016.sh install-audio --ack-kernel-risk
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-audio
```

Test speakers, headphones, microphone, another reboot, and normal workload. This working AMD configuration, including audio, is the recommended completion point. Do not proceed to iGPU or suspend unless those experimental features are specifically required.

## Optional experiment: iGPU

Configure the bootloader to execute a trusted `apple_set_os.efi` on every iGPU boot. This is intentionally not automated because EFI layouts differ. The upstream `MacBookPro13,3` example used rEFInd with `spoof_osx_version 10.12`; verify current syntax for the installed rEFInd version and do not copy that setting to another bootloader. Reboot while retaining AMD preference, then confirm:

```bash
lspci -nnk -s 00:02.0
```

It must show Intel graphics with `Kernel driver in use: i915`. Only then, with all external displays disconnected:

```bash
sudo ./omarchy-mbp15-2016.sh gpu-igpu --yes
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-gpu
hyprctl monitors all
sudo ./omarchy-mbp15-2016.sh gpu-confirm-igpu --yes
```

On the first Intel boot, reaching `multi-user.target` automatically selects AMD for the following reboot. Confirm only after the desktop and input devices work. If the screen is black but Linux reaches userspace, wait one minute and reboot to use AMD. If the kernel locks before the fallback service runs, use the Apple boot picker/macOS or another known-good recovery entry. Do not assume the panel is named `eDP-1` or `eDP-2`. To restore AMD manually:

```bash
sudo ./omarchy-mbp15-2016.sh gpu-dgpu --yes
sudo reboot
```

## Optional experiment: suspend

Do not install suspend configuration until the iGPU session above has been confirmed and survived repeated boots. Then, while physically present and with no external display:

```bash
sudo ./omarchy-mbp15-2016.sh install-suspend
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-suspend
sudo ./omarchy-mbp15-2016.sh pm-test --yes
# Save all work before the first real test:
sudo systemctl suspend
```

## After any black screen, hang, or failed boot

Do not immediately reinstall and erase the evidence. After recovering by the AMD/recovery path, collect the previous-boot logs first:

```bash
sudo ./omarchy-mbp15-2016.sh previous-boot
sudo journalctl -b -1 -k
```

Then roll back if needed:

```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```

## Safety changes

- Pinned Touch Bar, audio, and mbpfan commits; pinned and SHA-256-verified Wi-Fi NVRAM.
- Exact running-kernel header check before DKMS work.
- No blocking Touch Bar module-unload hook in the system sleep/resume path.
- Minimal suspend setup: `pcie_ports=compat` plus NVMe D3cold override; no forced sleep mode or IOMMU.
- EFI original-value backup and write verification.
- Exact Pro 450/455/460 identity gate and an automatic next-boot AMD fallback for unconfirmed iGPU trials.
- `cleanup-legacy-all --dry-run` previews migration cleanup, including the old forced `freeze/s2idle` drop-in; rescue-root cleanup can scan all `/home/*` users.
- Rollback restores EFI/configuration/firmware/binary backups, removes installed DKMS modules, and reports bootloader update failures.
- `install-cooling` no longer changes boot or display configuration; `mbpfan` is a separate opt-in stage.

Upstreams: [T1/Touch Bar](https://github.com/nohzafk/omarchy-macbookpro-t1), [audio](https://github.com/davidjo/snd_hda_macbookpro), [mbpfan](https://github.com/linux-on-mac/mbpfan), [EFI GPU switch reference](https://github.com/0xbb/gpu-switch).

## Commands

Run `./omarchy-mbp15-2016.sh help` for the complete command list. For rollback:

```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```

If `limine-update` reports failure, repair the boot entry before rebooting.

## License

[MIT](LICENSE)
