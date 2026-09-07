# omarchy-mbp15-2016

**English** | [简体中文](README.zh-CN.md)

Staged Omarchy/Arch hardware setup and diagnostics for the 2016 15-inch Touch Bar MacBook Pro (`MacBookPro13,3`).

Code review and automated tests are not target-hardware certification. The pinned T1 recipe was reported upstream on another T1 Mac, so every stage still needs physical validation on `MacBookPro13,3`. DKMS installation is restricted to the reviewed Linux `7.1.x/7.2.x` families.

## Critical iGPU warning

On this model, non-macOS firmware boots normally expose only the AMD GPU. Writing `gpu-power-prefs` without a boot chain that executes `apple_set_os` can leave Intel unavailable and the internal panel black. USB-C display outputs normally depend on the AMD GPU, so an external monitor is not a reliable iGPU recovery path.

This version deliberately has no one-shot full install. GPU commands admit only Apple Radeon Pro 450/455/460 (`1002:67ef`, subsystems `106b:0167/0166/0160`). `gpu-igpu` refuses to proceed unless Intel `00:02.0` is visible, bound to `i915`, all external displays are disconnected, and legacy display/sleep/IOMMU overrides are gone. GPU commands never hot-switch graphics or write `AQ_DRM_DEVICES`, DRM card numbers, or eDP connector names. The first iGPU boot automatically selects AMD for the following reboot unless the working Intel session is explicitly confirmed.

Keep macOS, Apple EFI, and Recovery intact. See the upstream model notes in [Dunedan/mbp-2016-linux](https://github.com/Dunedan/mbp-2016-linux).

## Safe staged installation

Prepare a known-good macOS/recovery boot path, save all work, disconnect docks and displays, and record the real Wi-Fi MAC in macOS with `networksetup -getmacaddress en0`.

Run each stage separately and verify a successful boot before continuing:

```bash
chmod +x omarchy-mbp15-2016.sh
sudo ./omarchy-mbp15-2016.sh status
sudo ./omarchy-mbp15-2016.sh install-base

sudo ./omarchy-mbp15-2016.sh install-touchbar
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-touchbar

sudo ./omarchy-mbp15-2016.sh install-suspend
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-suspend

sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all --dry-run
sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all
sudo reboot
```

Next, configure your bootloader to execute a trusted `apple_set_os.efi` on every iGPU boot. This is intentionally not automated because EFI layouts differ. The upstream `MacBookPro13,3` example used rEFInd with `spoof_osx_version 10.12`; verify current syntax for your rEFInd version and do not copy that setting to a different bootloader. Reboot while retaining AMD preference, then confirm:

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

Finish lower-risk components separately:

```bash
sudo ./omarchy-mbp15-2016.sh install-wifi AA:BB:CC:DD:EE:FF
sudo reboot
sudo ./omarchy-mbp15-2016.sh install-cooling
# Optional active fan control:
sudo ./omarchy-mbp15-2016.sh install-mbpfan
```

Run suspend tests only while physically present, on Intel internal graphics, with no external display:

```bash
sudo ./omarchy-mbp15-2016.sh pm-test --yes
# Save work before the first real test:
sudo systemctl suspend
```

Install audio last. Its out-of-tree driver has had kernel-specific crash reports, so the source is pinned and explicit acknowledgement is required, but compatibility with future kernels cannot be guaranteed:

```bash
sudo ./omarchy-mbp15-2016.sh install-audio --ack-kernel-risk
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
