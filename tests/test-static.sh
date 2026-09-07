#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo/omarchy-mbp15-2016.sh"

bash -n "$script"

gpu_body="$(sed -n '/^switch_gpu(){/,/^}/p' "$script")"
if grep -Eq 'AQ_DRM_DEVICES|eDP-[0-9]|/dev/dri/card' <<<"$gpu_body"; then
  echo "GPU switch function contains a hard-coded compositor/DRM route" >&2
  exit 1
fi

install_base_body="$(sed -n '/^install_base(){/,/^}/p' "$script")"
if grep -Eq 'switch_gpu|confirm_igpu|install_suspend|pm_test|systemctl suspend' <<<"$install_base_body"; then
  echo "Base install path invokes an experimental GPU or suspend action" >&2
  exit 1
fi

install_default_body="$(sed -n '/^install_default(){/,/^}/p' "$script")"
if grep -Eq 'switch_gpu|confirm_igpu|install_suspend|pm_test|systemctl suspend' <<<"$install_default_body"; then
  echo "Default install path invokes an experimental GPU or suspend action" >&2
  exit 1
fi
for required_stage in install_packages install_wifi install_cooling install_mbpfan install_touchbar install_audio; do
  grep -Fq "$required_stage" <<<"$install_default_body" || {
    echo "Default install path is missing $required_stage" >&2
    exit 1
  }
done

verify_body="$(sed -n '/^verify(){/,/^}/p' "$script")"
if grep -Fq 'verify_suspend' <<<"$verify_body"; then
  echo "Default verification still requires the optional suspend experiment" >&2
  exit 1
fi

verify_audio_body="$(sed -n '/^verify_audio(){/,/^}/p' "$script")"
grep -Fq 'Internal PCH ALSA card missing' <<<"$verify_audio_body"
grep -Fq 'Required snd_hda_macbookpro DKMS row not found' <<<"$verify_audio_body"

if grep -Eq 'append_cmdline "(video=|mem_sleep_default=|iommu=|intel_iommu=)' "$script"; then
  echo "Unsafe display/suspend boot parameter is still installed" >&2
  exit 1
fi

export MBP15_LIB_ONLY=1
# shellcheck source=../omarchy-mbp15-2016.sh
source "$script"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

LIMINE="$tmp/limine.conf"
printf '%s\n' \
  'KERNEL_CMDLINE[default]+=" pcie_ports=compat"' \
  'KERNEL_CMDLINE[default]+=" quiet"' > "$LIMINE"
remove_exact_limine_arg pcie_ports=compat
! grep -Fq pcie_ports=compat "$LIMINE"
grep -Fqx 'KERNEL_CMDLINE[default]+=" quiet"' "$LIMINE"

STATE="$tmp/limine-state"
mkdir -p "$STATE"
printf '%s\n' \
  'KERNEL_CMDLINE[default]+=" pcie_ports=compat"' \
  'KERNEL_CMDLINE[default]+=" quiet"' > "$STATE/macbook-t1.conf.before"
printf '%s\n' \
  'KERNEL_CMDLINE[default]+=" pcie_ports=compat"' \
  'KERNEL_CMDLINE[default]+=" video=eDP-2:d"' \
  'KERNEL_CMDLINE[default]+=" user_new_option=1"' > "$LIMINE"
restore_limine_arg pcie_ports=compat
restore_limine_arg video=eDP-2:d
grep -Fqx 'KERNEL_CMDLINE[default]+=" pcie_ports=compat"' "$LIMINE"
! grep -Fq video=eDP-2:d "$LIMINE"
grep -Fqx 'KERNEL_CMDLINE[default]+=" user_new_option=1"' "$LIMINE"

aq_only="$tmp/aq-only"
printf '%s\n' 'export AQ_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0' > "$aq_only"
remove_script_aq_file "$aq_only"
[[ ! -e "$aq_only" ]]

mixed="$tmp/mixed"
printf '%s\n' 'export AQ_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0' 'export KEEP_ME=1' > "$mixed"
remove_script_aq_file "$mixed" 2>/dev/null
grep -Fqx 'export KEEP_ME=1' "$mixed"
! grep -Fq AQ_DRM_DEVICES "$mixed"

test_home="$tmp/home/tester"
mkdir -p "$test_home/.config/hypr"
target_user_home(){ printf '%s\n' "$test_home"; }
SYSTEM_ENVIRONMENT="$tmp/environment"
SLEEP_CONF="$tmp/sleep.conf"
: > "$SYSTEM_ENVIRONMENT"
printf '%s\n' 'KERNEL_CMDLINE[default]+=" video=eDP-2:d"' > "$LIMINE"
legacy_graphics_present
printf '%s\n' 'KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle"' > "$LIMINE"
legacy_suspend_overrides_present
printf '%s\n' '[Sleep]' 'SuspendState=freeze' 'MemorySleepMode=s2idle' > "$SLEEP_CONF"
: > "$LIMINE"
legacy_suspend_overrides_present

PCI_DEVICES="$tmp/pci"
pro460="$PCI_DEVICES/0000:01:00.0"
mkdir -p "$pro460"
printf '%s\n' 0x1002 > "$pro460/vendor"
printf '%s\n' 0x67ef > "$pro460/device"
printf '%s\n' 0x106b > "$pro460/subsystem_vendor"
for supported_subsystem in 0x0160 0x0166 0x0167; do
  printf '%s\n' "$supported_subsystem" > "$pro460/subsystem_device"
  preflight_gpu_identity >/dev/null
done
printf '%s\n' 0xffff > "$pro460/subsystem_device"
if (preflight_gpu_identity >/dev/null 2>&1); then
  echo "GPU identity gate accepted an unsupported subsystem" >&2
  exit 1
fi
printf '%s\n' 0x0160 > "$pro460/subsystem_device"

default_calls="$(
  default_calls=""
  need_root(){ :; }
  preflight(){ default_calls+=" preflight"; }
  legacy_configuration_present(){ return 1; }
  install_packages(){ default_calls+=" packages"; }
  install_wifi(){ default_calls+=" wifi:$1"; }
  install_cooling(){ default_calls+=" cooling"; }
  install_mbpfan(){ default_calls+=" mbpfan"; }
  install_touchbar(){ default_calls+=" touchbar"; }
  install_audio(){ (($# == 0)); default_calls+=" audio"; }
  install_default --wifi-mac AA:BB:CC:DD:EE:FF >/dev/null
  printf '%s' "$default_calls"
)"
[[ "$default_calls" == " preflight packages wifi:AA:BB:CC:DD:EE:FF cooling mbpfan touchbar audio" ]]
if (need_root(){ :; }; install_default >/dev/null 2>&1); then
  echo "Default install accepted a missing Wi-Fi decision" >&2
  exit 1
fi
if (need_root(){ :; }; install_default --wifi-mac AA:BB:CC:DD:EE:FF --skip-wifi-nvram >/dev/null 2>&1); then
  echo "Default install accepted conflicting Wi-Fi options" >&2
  exit 1
fi

STATE="$tmp/gpu-state"
EFI_VARS="$tmp/switch-efivars"
EFI_GPU_VAR=test-switch-gpu-var
mkdir -p "$STATE" "$EFI_VARS"
printf '\x07\x00\x00\x00\x01\x00\x00\x00' > "$EFI_VARS/$EFI_GPU_VAR"
printf '%s\n' 'KERNEL_CMDLINE[default]+=" video=eDP-2:d"' > "$LIMINE"
if (switch_gpu amd --yes >/dev/null 2>&1); then
  echo "dGPU switch accepted legacy display configuration" >&2
  exit 1
fi
[[ "$(efi_gpu_pref)" == intel ]]
: > "$LIMINE"

STATE="$tmp/state"
owned="$tmp/owned"
backup_once "$owned" owned.before
printf '%s\n' created > "$owned"
restore_or_remove "$owned" owned.before
[[ ! -e "$owned" ]]

original="$tmp/original"
printf '%s\n' before > "$original"
backup_once "$original" original.before
printf '%s\n' after > "$original"
restore_or_remove "$original" original.before
grep -Fqx before "$original"

if (switch_gpu intel >/dev/null 2>&1); then
  echo "GPU switch accepted a missing --yes acknowledgement" >&2
  exit 1
fi

EFI_VARS="$tmp/efivars"
EFI_GPU_VAR=test-gpu-var
mkdir -p "$EFI_VARS"
printf '\x07\x00\x00\x00\x01\x00\x00\x00' > "$EFI_VARS/$EFI_GPU_VAR"
[[ "$(efi_gpu_pref)" == intel ]]
printf '\x07\x00\x00\x00\x00\x00\x00\x00' > "$EFI_VARS/$EFI_GPU_VAR"
[[ "$(efi_gpu_pref)" == amd ]]
write_efi_gpu_pref intel
[[ "$(efi_gpu_pref)" == intel ]]
write_efi_gpu_pref amd
[[ "$(efi_gpu_pref)" == amd ]]

fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fakebin/systemctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fakebin/limine-update"
chmod +x "$fakebin/systemctl"
chmod +x "$fakebin/limine-update"
PATH="$fakebin:$PATH"

need_root(){ :; }
preflight_model(){ :; }
STATE="$tmp/cleanup-state"
LIMINE="$tmp/cleanup-limine.conf"
SYSTEM_ENVIRONMENT="$tmp/cleanup-environment"
SLEEP_CONF="$tmp/cleanup-sleep.conf"
printf '%s\n' \
  'KERNEL_CMDLINE[default]+=" pcie_ports=compat"' \
  'KERNEL_CMDLINE[default]+=" video=eDP-2:d"' \
  'KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle"' \
  'KERNEL_CMDLINE[default]+=" iommu=pt"' \
  'KERNEL_CMDLINE[default]+=" intel_iommu=on"' > "$LIMINE"
printf '%s\n' 'AQ_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0' 'KEEP_SYSTEM=1' > "$SYSTEM_ENVIRONMENT"
printf '%s\n' '[Sleep]' 'SuspendState=freeze' 'MemorySleepMode=s2idle' > "$SLEEP_CONF"
mkdir -p "$test_home/.config/environment.d" "$test_home/.config/uwsm/env.d" "$test_home/.config/hypr"
printf '%s\n' 'AQ_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0' > "$test_home/.config/environment.d/10-graphics.conf"
printf '%s\n' 'export AQ_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0' 'export KEEP_USER=1' > "$test_home/.config/uwsm/default"
printf '%s\n' 'hl.env("AQ_DRM_DEVICES", "/dev/dri/card1:/dev/dri/card0")' 'hl.env("KEEP_USER", "1")' > "$test_home/.config/hypr/hyprland.lua"
printf '%s\n' 'hl.monitor({ output = "eDP-2", disabled = true })' 'hl.monitor({ output = "KEEP-1", disabled = true })' > "$test_home/.config/hypr/monitors.lua"
before_cleanup="$(sha256sum "$LIMINE" "$SLEEP_CONF" "$SYSTEM_ENVIRONMENT" "$test_home/.config/uwsm/default")"
cleanup_legacy_all --dry-run >/dev/null
[[ "$before_cleanup" == "$(sha256sum "$LIMINE" "$SLEEP_CONF" "$SYSTEM_ENVIRONMENT" "$test_home/.config/uwsm/default")" ]]
cleanup_legacy_all >/dev/null 2>&1
grep -Fq pcie_ports=compat "$LIMINE"
! grep -Eq 'video=eDP|mem_sleep_default=|(^|[[:space:]])iommu=pt|intel_iommu=on' "$LIMINE"
[[ ! -e "$SLEEP_CONF" ]]
grep -Fqx KEEP_SYSTEM=1 "$SYSTEM_ENVIRONMENT"
grep -Fqx 'export KEEP_USER=1' "$test_home/.config/uwsm/default"
grep -Fqx 'hl.env("KEEP_USER", "1")' "$test_home/.config/hypr/hyprland.lua"
grep -Fqx 'hl.monitor({ output = "KEEP-1", disabled = true })' "$test_home/.config/hypr/monitors.lua"
! legacy_configuration_present

STATE="$tmp/fallback-state"
EFI_VARS="$tmp/fallback-efivars"
EFI_GPU_VAR=test-fallback-gpu-var
GPU_FALLBACK_MARKER="$STATE/gpu-igpu-unconfirmed"
GPU_FALLBACK_ARMED_BOOT="$STATE/gpu-igpu-armed-boot-id"
GPU_FALLBACK_HELPER="$tmp/usr/local/sbin/mbp15-gpu-fallback-amd"
GPU_FALLBACK_UNIT="$tmp/etc/systemd/system/mbp15-gpu-fallback-amd.service"
mkdir -p "$STATE" "$EFI_VARS"
printf '\x07\x00\x00\x00\x01\x00\x00\x00' > "$EFI_VARS/$EFI_GPU_VAR"
arm_gpu_fallback >/dev/null
[[ -x "$GPU_FALLBACK_HELPER" && -f "$GPU_FALLBACK_UNIT" && -e "$GPU_FALLBACK_MARKER" && -s "$GPU_FALLBACK_ARMED_BOOT" ]]
preflight_gpu_switch(){ :; }
active_gpu(){ echo intel; }
if (confirm_igpu --yes >/dev/null 2>&1); then
  echo "iGPU confirmation was accepted before the required reboot" >&2
  exit 1
fi
"$GPU_FALLBACK_HELPER"
[[ "$(efi_gpu_pref)" == amd ]]
grep -Fq 'WantedBy=multi-user.target' "$GPU_FALLBACK_UNIT"
disarm_gpu_fallback
[[ ! -e "$GPU_FALLBACK_MARKER" && ! -e "$GPU_FALLBACK_ARMED_BOOT" && ! -e "$GPU_FALLBACK_HELPER" && ! -e "$GPU_FALLBACK_UNIT" ]]

grep -Fq 'apply_immediate_cooling' <<<"$install_default_body"
grep -Fq 'apply_immediate_cooling' <<<"$install_base_body"

fake_modules="$tmp/fake_modules"
mkdir -p "$fake_modules/fake-k/build"
printf '%s\n' "linux-omarchy" > "$fake_modules/fake-k/pkgbase"
running_kernel_pkgbase(){
  local pkgbase_file="$fake_modules/fake-k/pkgbase"
  [[ -r "$pkgbase_file" ]] && cat "$pkgbase_file"
}
[[ "$(running_kernel_pkgbase)" == "linux-omarchy" ]]

echo "static safety tests passed"

