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

echo "static safety tests passed"
