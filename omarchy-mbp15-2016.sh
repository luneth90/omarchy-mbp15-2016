#!/usr/bin/env bash
set -Eeuo pipefail

# MacBookPro13,3 (2016 15-inch Touch Bar/T1) Hardware Fix Script
# Intended target: Arch/Omarchy, Linux 7.1.x/7.2.x family.
# Out-of-tree drivers still require physical validation on MacBookPro13,3.
#
# Commands:
#   sudo ./omarchy-mbp15-2016.sh status
#   sudo ./omarchy-mbp15-2016.sh install-base
#   sudo ./omarchy-mbp15-2016.sh install-wifi AA:BB:CC:DD:EE:FF
#   sudo ./omarchy-mbp15-2016.sh install-touchbar
#   sudo ./omarchy-mbp15-2016.sh install-suspend
#   sudo ./omarchy-mbp15-2016.sh install-cooling
#   sudo ./omarchy-mbp15-2016.sh install-mbpfan
#   sudo ./omarchy-mbp15-2016.sh install-audio --ack-kernel-risk
#   sudo ./omarchy-mbp15-2016.sh cleanup-legacy-graphics
#   sudo ./omarchy-mbp15-2016.sh gpu-igpu --yes
#   sudo ./omarchy-mbp15-2016.sh gpu-dgpu --yes
#   sudo reboot
#   sudo ./omarchy-mbp15-2016.sh verify
#   sudo ./omarchy-mbp15-2016.sh pm-test --yes
#   sudo ./omarchy-mbp15-2016.sh previous-boot
#   sudo ./omarchy-mbp15-2016.sh rollback
#
# IMPORTANT:
# - Requires dual-boot alongside macOS! Clean wipe/format installs erase Touch Bar firmware.
# - Preserves macOS / Apple EFI / APFS. Never repartitions disks.
# - Never runs a real suspend automatically.
# - Real suspend must be tested manually with physical access.
# - Wi-Fi NVRAM needs the REAL macOS Wi-Fi MAC; never use 00:90:4c:*.
# - GPU switching is staged separately and never changes a running display route.
# - iGPU mode requires a boot path that keeps Intel IGD enabled (apple_set_os/rEFInd).

MODEL="MacBookPro13,3"
STATE="/var/lib/mbp15-2016-t1-touchbar-fix"
SRC="/usr/local/src/mbp15-2016-t1-touchbar-fix"
T1_REPO="$SRC/omarchy-macbookpro-t1"
AUDIO_REPO="$SRC/snd_hda_macbookpro"
MBPFAN_REPO="$SRC/mbpfan"
T1_URL="https://github.com/nohzafk/omarchy-macbookpro-t1.git"
AUDIO_URL="https://github.com/davidjo/snd_hda_macbookpro.git"
MBPFAN_URL="https://github.com/linux-on-mac/mbpfan.git"
T1_REF="8e479f0af82d16f47de811bef6e1a5cfd7d8c5f8"
AUDIO_REF="89b22ff90b86468b186706861dd18663562defa7"
MBPFAN_REF="afb8bbb83dd8de85856e297e267581dab4f3f201"

WIFI_URL="https://raw.githubusercontent.com/nohzafk/omarchy-macbookpro-t1/${T1_REF}/firmware/brcmfmac43602-pcie.txt"
WIFI_SHA256="b109f3e6663b0e888c2559e36f7e0109f2a3a6b9765786d11f849f16d4b32d06"
WIFI_FILE="/usr/lib/firmware/brcm/brcmfmac43602-pcie.txt"
WIFI_BAK="$STATE/brcmfmac43602-pcie.txt.before"
WIFI_INSTALLED="$STATE/wifi-nvram.installed"

TB_HELPER="/usr/local/sbin/touchbar-enable.sh"
TB_UNIT="/etc/systemd/system/touchbar.service"
TB_RESUME="/usr/lib/systemd/system-sleep/90-mbp-touchbar-resume"
TB_MODPROBE="/etc/modprobe.d/99-appleibridge-late-load.conf"

LIMINE="/etc/limine-entry-tool.d/macbook-t1.conf"
SLEEP_CONF="/etc/systemd/sleep.conf.d/30-mbp15-suspend.conf"
NVME_UNIT="/etc/systemd/system/mbp15-nvme-d3cold.service"

MBPFAN_CONF="/etc/mbpfan.conf"
MBPFAN_UNIT="/etc/systemd/system/mbpfan.service"
COOLING_UNIT="/etc/systemd/system/macbook-cpu-cooling.service"
EFI_VARS="/sys/firmware/efi/efivars"
EFI_GPU_VAR="gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9"
EFI_GPU_BAK="$STATE/${EFI_GPU_VAR}.before"
EFI_GPU_ABSENT="$STATE/${EFI_GPU_VAR}.absent"
AUDIO_INSTALLED="$STATE/audio-dkms.installed"
TB_INSTALLED="$STATE/touchbar-dkms.installed"
MBPFAN_INSTALLED="$STATE/mbpfan.installed"
MBPFAN_BIN_BAK="$STATE/mbpfan.binary.before"
MBPFAN_BIN_ABSENT="$STATE/mbpfan.binary.absent"
MBPFAN_BIN_PATH="$STATE/mbpfan.binary.path"

log(){ printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m OK \033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2; }
fail(){ printf '\033[1;31mFAIL\033[0m %s\n' "$*" >&2; }
die(){ fail "$*"; exit 1; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run with sudo/root."; }
have(){ command -v "$1" >/dev/null 2>&1; }

model(){ cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true; }
preflight_model(){
  local detected
  detected="$(model)"
  [[ "$detected" == "$MODEL" ]] || die "This script targets $MODEL; detected ${detected:-unknown}."
  ok "$MODEL detected"
}
preflight_t1(){
  local p=""
  for d in /sys/bus/usb/devices/*/; do
    [[ "$(cat "$d/idVendor" 2>/dev/null || true)" == "05ac" ]] || continue
    p="$(cat "$d/idProduct" 2>/dev/null || true)"
    [[ "$p" == "8600" || "$p" == "1281" ]] && break
  done
  if [[ "$p" == "1281" ]]; then
    die "T1/iBridge is in DFU recovery mode (05ac:1281). Missing Touch Bar firmware! Omarchy must be dual-booted with macOS preserved; clean wipe/format installs erase required bridgeOS firmware."
  fi
  [[ "$p" == "8600" ]] || die "T1/iBridge is not healthy (expected 05ac:8600, got ${p:-unknown})."
  ok "T1/iBridge 05ac:8600 detected"
}
preflight(){ preflight_model; preflight_t1; }

backup_once(){
  local src="$1" name="$2"
  install -d -m 0755 "$STATE"
  [[ ! -e "$STATE/$name" && ! -e "$STATE/$name.absent" ]] || return 0
  if [[ -e "$src" ]]; then cp -a "$src" "$STATE/$name"; else touch "$STATE/$name.absent"; fi
}
restore_or_remove(){
  local dst="$1" name="$2"
  if [[ -e "$STATE/$name" ]]; then
    cp -a "$STATE/$name" "$dst"
  elif [[ -e "$STATE/$name.absent" ]]; then
    rm -f "$dst"
  else
    warn "No ownership/backup marker for $dst; leaving it unchanged"
  fi
}
restore_tree_or_remove(){
  local dst="$1" name="$2"
  if [[ -e "$STATE/$name" ]]; then
    rm -rf "$dst"
    cp -a "$STATE/$name" "$dst"
  elif [[ -e "$STATE/$name.absent" ]]; then
    rm -rf "$dst"
  else
    warn "No ownership/backup marker for $dst; leaving it unchanged"
  fi
}

git_sync(){
  local url="$1" dir="$2" ref="$3" actual
  install -d -m 0755 "$(dirname "$dir")"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" remote set-url origin "$url"
  else
    [[ ! -e "$dir" ]] || die "Refusing to replace non-git path: $dir"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
  fi
  git -C "$dir" fetch --depth=1 origin "$ref"
  git -C "$dir" reset --hard FETCH_HEAD
  actual="$(git -C "$dir" rev-parse HEAD)"
  [[ "$actual" == "$ref" ]] || die "Pinned source verification failed for $url (expected $ref, got $actual)."
}

require_kernel_headers(){
  local build="/usr/lib/modules/$(uname -r)/build"
  [[ -e "$build/Makefile" ]] || die "Headers for running kernel $(uname -r) are missing at $build. Install the matching headers package; do not blindly install linux-headers for a custom kernel."
}
require_reviewed_kernel_family(){
  case "$(uname -r)" in
    7.1.*|7.2.*) ;;
    *) die "Out-of-tree DKMS installation is restricted to the reviewed Linux 7.1.x/7.2.x families; running $(uname -r). Re-audit the pinned driver before extending this allowlist." ;;
  esac
}

install_packages(){
  have pacman || die "pacman not found; this script targets Omarchy/Arch."
  pacman -S --needed --noconfirm base-devel git curl wget dkms zstd patch \
    alsa-utils pipewire wireplumber usbutils pciutils iw v4l-utils lm_sensors
  if pacman -Q macbook12-spi-driver-dkms >/dev/null 2>&1; then
    modinfo applespi >/dev/null 2>&1 || die "Refusing to remove macbook12-spi-driver-dkms: mainline applespi is not available."
    pacman -Rns --noconfirm macbook12-spi-driver-dkms || true
  fi
  require_kernel_headers
}

# ---------- Wi-Fi ----------
wifi_iface(){ iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}'; }
wifi_mac(){ local i; i="$(wifi_iface || true)"; [[ -n "$i" ]] && cat "/sys/class/net/$i/address" 2>/dev/null || true; }
valid_mac(){ [[ "$1" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; }
install_wifi(){
  local mac="$1"
  valid_mac "$mac" || die "Invalid Wi-Fi MAC: $mac"
  mac="$(tr '[:upper:]' '[:lower:]' <<<"$mac")"
  [[ ! "$mac" =~ ^00:90:4c: ]] || die "Refusing Broadcom placeholder MAC. Use the REAL macOS Wi-Fi MAC."
  lspci -nn | grep -qi '14e4:43ba' || { warn "BCM43602 14e4:43ba not found; skipping NVRAM."; return; }
  install -d -m 0755 /usr/lib/firmware/brcm "$STATE"
  backup_once "$WIFI_FILE" "brcmfmac43602-pcie.txt.before"
  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
  curl -fL --retry 3 --connect-timeout 15 "$WIFI_URL" -o "$tmp"
  printf '%s  %s\n' "$WIFI_SHA256" "$tmp" | sha256sum -c - >/dev/null || die "Downloaded BCM43602 NVRAM checksum mismatch."
  grep -q '^devid=0x43ba$' "$tmp" || die "Downloaded BCM43602 NVRAM failed sanity check."
  grep -q '^macaddr=' "$tmp" || die "Downloaded NVRAM lacks macaddr=."
  sed -i "s/^macaddr=.*/macaddr=$mac/" "$tmp"
  install -m 0644 "$tmp" "$WIFI_FILE"
  touch "$WIFI_INSTALLED"
  ok "BCM43602 board NVRAM installed with supplied macOS MAC"
}
verify_wifi(){
  log "Wi-Fi"
  lspci -nnk | sed -n '/Network controller/,+4p' | head -n 6 || true
  local i m; i="$(wifi_iface || true)"; m="$(wifi_mac || true)"
  [[ -n "$i" ]] || { fail "No Wi-Fi interface"; return 1; }
  echo "Interface: $i"; echo "MAC: $m"
  if [[ "$m" =~ ^00:90:4[cC]: ]]; then fail "Broadcom placeholder MAC active"; return 1; fi
  ok "Non-placeholder Wi-Fi MAC active"
  iw dev "$i" link 2>/dev/null || true
}

# ---------- Keyboard / trackpad ----------
verify_applespi(){
  log "Keyboard / trackpad"
  if lsmod | grep -q '^applespi'; then ok "mainline applespi loaded"; else fail "applespi not loaded"; return 1; fi
  grep -Ei '^N: Name="Apple SPI (Keyboard|Touchpad)"' /proc/bus/input/devices 2>/dev/null || true
}

# ---------- Audio ----------
install_audio(){
  [[ "${1:-}" == "--ack-kernel-risk" ]] || die "Audio is optional and can crash incompatible kernels. Re-run as: sudo $0 install-audio --ack-kernel-risk"
  require_reviewed_kernel_family
  require_kernel_headers
  git_sync "$AUDIO_URL" "$AUDIO_REPO" "$AUDIO_REF"
  log "Installing Cirrus CS8409 audio DKMS"
  ( cd "$AUDIO_REPO" && ./install.cirrus.driver.sh -i )
  touch "$AUDIO_INSTALLED"
}
verify_audio(){
  log "Audio"
  local cards; cards="$(cat /proc/asound/cards 2>/dev/null || true)"; printf '%s\n' "$cards"
  if printf '%s\n' "$cards" | grep -Eq 'HDA Intel PCH|HDA ATI HDMI|\[PCH|\[HDMI'; then
    ok "ALSA card(s) present"
  else
    fail "No ALSA sound card found"; return 1
  fi
  if dkms status 2>/dev/null | grep -qi 'snd_hda_macbookpro'; then ok "snd_hda_macbookpro DKMS installed"; else warn "Audio DKMS row not found"; fi
}

# ---------- Touch Bar ----------
install_touchbar(){
  require_reviewed_kernel_family
  require_kernel_headers
  git_sync "$T1_URL" "$T1_REPO" "$T1_REF"
  local drv="$T1_REPO/drivers/appleibridge" ver="0.1" src="/usr/src/appleibridge-0.1"
  [[ -f "$drv/dkms.conf" ]] || die "appleibridge dkms.conf missing."
  backup_once "$TB_HELPER" "touchbar-enable.sh.before"
  backup_once "$TB_UNIT" "touchbar.service.before"
  backup_once "$TB_RESUME" "90-mbp-touchbar-resume.before"
  backup_once "$TB_MODPROBE" "99-appleibridge-late-load.conf.before"
  backup_once "$src" "appleibridge-0.1.src.before"

  dkms remove -m appleibridge -v "$ver" --all >/dev/null 2>&1 || true
  rm -rf "$src"; install -d -m 0755 "$src"
  cp "$drv/"*.c "$drv/"*.h "$drv/Makefile" "$drv/dkms.conf" "$src/"
  dkms add -m appleibridge -v "$ver"
  dkms build -m appleibridge -v "$ver"
  dkms install -m appleibridge -v "$ver"

  install -m 0755 "$T1_REPO/systemd/touchbar-enable.sh" "$TB_HELPER"
  install -m 0644 "$T1_REPO/systemd/touchbar.service" "$TB_UNIT"

  sed -i 's/fnmode=0/fnmode=1/g' "$TB_HELPER"
  sed -i "s/printf '%s' '0'  > \"\$d\/fnmode\"/printf '%s' '1'  > \"\$d\/fnmode\"/" "$TB_HELPER"

  cat > "$TB_MODPROBE" <<'TBEOF'
blacklist apple_ibridge
blacklist apple_ib_tb
blacklist apple_ib_als
TBEOF

  # A blocking system-sleep hook that unloads HID modules can stall the entire
  # resume path inside the kernel. Prefer a non-working Touch Bar after resume
  # over turning a cosmetic recovery into a machine-wide resume deadlock.
  rm -f "$TB_RESUME"
  install -d -m 0755 /etc/limine-entry-tool.d
  backup_once "$LIMINE" "macbook-t1.conf.before"
  append_cmdline "modprobe.blacklist=apple_ibridge,apple_ib_tb,apple_ib_als"
  have limine-update || die "limine-update not found"
  limine-update
  systemctl daemon-reload
  systemctl enable touchbar.service
  touch "$TB_INSTALLED"
  ok "Touch Bar DKMS + late boot service installed; no blocking module-unload resume hook"
}
touchbar_attr(){
  local d p
  shopt -s nullglob
  for d in /sys/bus/hid/devices/0003:05AC:8600.*; do
    p="$(readlink -f "$d" 2>/dev/null || true)"
    if [[ -n "$p" && -e "$p/fnmode" ]]; then shopt -u nullglob; printf '%s\n' "$p"; return 0; fi
  done
  shopt -u nullglob
  return 1
}
verify_touchbar(){
  log "Touch Bar"
  systemctl is-active --quiet touchbar.service || { fail "touchbar.service not active"; return 1; }
  local d fn; d="$(touchbar_attr || true)"
  [[ -n "$d" ]] || { fail "Touch Bar sysfs controls missing"; return 1; }
  fn="$(cat "$d/fnmode" 2>/dev/null || true)"
  echo "fnmode=$fn idle_timeout=$(cat "$d/idle_timeout" 2>/dev/null || true) dim_timeout=$(cat "$d/dim_timeout" 2>/dev/null || true)"
  [[ "$fn" == "1" ]] || { fail "Expected fnmode=1"; return 1; }
  local dev drv count=0
  shopt -s nullglob
  for dev in /sys/bus/hid/devices/0003:05AC:8600.*; do
    drv="$(basename "$(readlink -f "$dev/driver" 2>/dev/null)" 2>/dev/null || true)"
    echo "$(basename "$dev") -> ${drv:-NONE}"
    [[ "$drv" == "apple-ibridge-hid" ]] || continue
    ((++count))
  done
  shopt -u nullglob
  (( count >= 2 )) || { fail "Expected at least two T1 HID functions owned by apple-ibridge-hid"; return 1; }
  grep -q 'Name="Apple Touch Bar' /proc/bus/input/devices || { fail "Touch Bar input device missing"; return 1; }
  ok "Touch Bar automated gates passed"
}

# ---------- Webcam ----------
verify_webcam(){
  log "Webcam"
  shopt -s nullglob; local v=(/dev/video*); shopt -u nullglob
  (( ${#v[@]} > 0 )) || { fail "No /dev/video*"; return 1; }
  printf '%s\n' "${v[@]}"; ok "Video device node(s) present"
  v4l2-ctl --list-devices 2>/dev/null || true
}

# ---------- Fans / Thermal sensors ----------
verify_fans_thermal(){
  log "Fans & Thermal sensors (Apple SMC)"
  local smc_dir="" coretemp_dir="" d f tf rpm manual count=0

  modprobe coretemp 2>/dev/null || true
  for d in /sys/devices/platform/coretemp.*; do
    [[ -d "$d" ]] && { coretemp_dir="$d"; break; }
  done
  if [[ -z "$coretemp_dir" ]]; then
    fail "CPU core temperature interface not found; coretemp driver not loaded"
    return 1
  fi
  ok "CPU core temperature sensors detected at $(basename "$coretemp_dir")"

  for d in /sys/devices/platform/applesmc.*; do
    [[ -d "$d" ]] && { smc_dir="$d"; break; }
  done
  if [[ -z "$smc_dir" ]]; then
    modprobe applesmc 2>/dev/null || true
    for d in /sys/devices/platform/applesmc.*; do
      [[ -d "$d" ]] && { smc_dir="$d"; break; }
    done
  fi
  if [[ -z "$smc_dir" ]]; then
    fail "Apple SMC sysfs interface not found; applesmc driver not loaded"
    return 1
  fi
  ok "Apple SMC detected at $(basename "$smc_dir")"
  for f in "$smc_dir"/fan*_input; do
    [[ -e "$f" ]] || continue
    local fname fan_num
    fname="$(basename "$f")"
    fan_num="${fname#fan}"
    fan_num="${fan_num%_input}"
    rpm="$(cat "$f" 2>/dev/null || echo 0)"
    manual="$(cat "$smc_dir/fan${fan_num}_manual" 2>/dev/null || echo "?")"
    echo "  Fan $fan_num: ${rpm} RPM (manual=$manual [0=firmware-managed])"
    ((++count))
  done
  if (( count == 0 )); then
    fail "No fan inputs found under Apple SMC"
    return 1
  fi
  local t=""
  for tf in "$smc_dir"/temp*_input /sys/class/thermal/thermal_zone*/temp; do
    if [[ -e "$tf" ]]; then
      local raw; raw="$(cat "$tf" 2>/dev/null || echo 0)"
      if (( raw > 1000 )); then t="$(( raw / 1000 ))°C"; break; fi
    fi
  done
  [[ -n "$t" ]] && echo "  Current temperature: $t"
  ok "Fan and thermal sensor interfaces are available"
}

# ---------- Suspend / NVMe ----------
nvme_bdfs(){
  local n d bdf
  shopt -s nullglob
  for n in /sys/class/nvme/nvme*/device; do
    d="$(readlink -f "$n" 2>/dev/null || true)"; [[ -n "$d" ]] || continue
    bdf="$(basename "$d")"; [[ -e "/sys/bus/pci/devices/$bdf/d3cold_allowed" ]] && echo "$bdf"
  done
  shopt -u nullglob
}
append_cmdline(){
  local a="$1" line
  line="KERNEL_CMDLINE[default]+=\" $a\""
  touch "$LIMINE"
  grep -Fqx "$line" "$LIMINE" 2>/dev/null || printf '%s\n' "$line" >> "$LIMINE"
}
install_suspend(){
  install -d -m 0755 "$STATE" /etc/limine-entry-tool.d /etc/systemd/system
  backup_once "$LIMINE" "macbook-t1.conf.before"
  backup_once "$NVME_UNIT" "mbp15-nvme-d3cold.service.before"

  # This is the one boot parameter verified to recover all USB-C controllers
  # on T1 MacBooks. IOMMU and sleep-mode changes must be tested separately.
  append_cmdline "pcie_ports=compat"

  cat > "$NVME_UNIT" <<'NEOF'
[Unit]
Description=Disable D3cold on actual Apple NVMe controller(s)
After=local-fs.target
Before=sleep.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/sh -c 'for n in /sys/class/nvme/nvme*/device; do dev=$(readlink -f "$n" 2>/dev/null) || continue; bdf=$(basename "$dev"); p="/sys/bus/pci/devices/$bdf/d3cold_allowed"; if [ -e "$p" ]; then echo 0 > "$p"; fi; done; exit 0'

[Install]
WantedBy=multi-user.target
NEOF

  systemctl daemon-reload
  systemctl enable --now mbp15-nvme-d3cold.service
  have limine-update || die "limine-update not found"
  limine-update
  ok "Minimal PCIe/NVMe suspend configuration installed"
}
verify_suspend(){
  log "Suspend / NVMe"
  local rc=0 b v
  if grep -qw "pcie_ports=compat" /proc/cmdline; then ok "pcie_ports=compat active"; else fail "pcie_ports=compat missing"; rc=1; fi
  local ms; ms="$(cat /sys/power/mem_sleep 2>/dev/null || true)"; echo "mem_sleep: $ms"
  local found=0
  while read -r b; do
    [[ -n "$b" ]] || continue; found=1
    v="$(cat "/sys/bus/pci/devices/$b/d3cold_allowed" 2>/dev/null || true)"
    echo "NVMe $b d3cold_allowed=$v"
    [[ "$v" == "0" ]] && ok "NVMe $b D3cold disabled" || { fail "NVMe $b D3cold is not disabled"; rc=1; }
  done < <(nvme_bdfs)
  (( found )) || warn "No NVMe d3cold control found; nothing to override on this controller/kernel"
  if systemctl is-active --quiet mbp15-nvme-d3cold.service; then
    ok "mbp15-nvme-d3cold.service active"
  else
    local st; st="$(systemctl is-active mbp15-nvme-d3cold.service 2>/dev/null || echo 'not-found')"
    fail "NVMe service inactive (state: $st). Run 'sudo systemctl restart mbp15-nvme-d3cold.service' or re-run install."
    rc=1
  fi
  return "$rc"
}

# ---------- Cooling / Fan / CPU Thermal ----------
install_cooling(){
  log "Configuring conservative CPU power policy (firmware keeps fan control)"
  backup_once "$COOLING_UNIT" "macbook-cpu-cooling.service.before"
  log "Configuring CPU power & thermal policy"
  if have powerprofilesctl; then
    powerprofilesctl set power-saver 2>/dev/null || true
  fi

  cat > "$COOLING_UNIT" <<'EOF'
[Unit]
Description=MacBookPro CPU Thermal & Power Optimization
After=power-profiles-daemon.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true; powerprofilesctl set power-saver 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now macbook-cpu-cooling.service
  verify_cooling || die "Cooling services failed post-install verification."
  ok "CPU cooling policy deployed; no boot or display configuration was changed"
}

install_mbpfan(){
  verify_fans_thermal || die "Cooling hardware preflight failed; refusing to install mbpfan."
  backup_once "$MBPFAN_CONF" "mbpfan.conf.before"
  backup_once "$MBPFAN_UNIT" "mbpfan.service.before"
  install -d -m 0755 "$STATE"
  local old_mbpfan
  old_mbpfan="$(command -v mbpfan || true)"
  if [[ -n "$old_mbpfan" && ! -e "$MBPFAN_BIN_BAK" && ! -e "$MBPFAN_BIN_ABSENT" ]]; then
    [[ "$old_mbpfan" == /usr/*/mbpfan || "$old_mbpfan" == /usr/local/*/mbpfan ]] || die "Refusing to replace mbpfan at unexpected path: $old_mbpfan"
    cp -a "$old_mbpfan" "$MBPFAN_BIN_BAK"
    printf '%s\n' "$old_mbpfan" > "$MBPFAN_BIN_PATH"
  fi
  have pacman || die "pacman not found; this script targets Omarchy/Arch."
  pacman -S --needed --noconfirm base-devel git
  git_sync "$MBPFAN_URL" "$MBPFAN_REPO" "$MBPFAN_REF"
  ( cd "$MBPFAN_REPO" && make && make install )

  local mbpfan_bin modprobe_bin
  mbpfan_bin="$(command -v mbpfan || true)"
  modprobe_bin="$(command -v modprobe || true)"
  [[ -n "$mbpfan_bin" && "$mbpfan_bin" == /* ]] || die "mbpfan executable not found after installation."
  [[ -n "$modprobe_bin" && "$modprobe_bin" == /* ]] || die "modprobe not found."
  if [[ ! -e "$MBPFAN_BIN_BAK" && ! -e "$MBPFAN_BIN_ABSENT" ]]; then
    touch "$MBPFAN_BIN_ABSENT"
    printf '%s\n' "$mbpfan_bin" > "$MBPFAN_BIN_PATH"
  fi

  cat > "$MBPFAN_CONF" <<'EOF'
[general]
min_fan1_speed = 2500
max_fan1_speed = 5900
min_fan2_speed = 2500
max_fan2_speed = 5400
low_temp = 50
high_temp = 62
max_temp = 78
polling_interval = 2
EOF
  cat > "$MBPFAN_UNIT" <<EOF
[Unit]
Description=MacBook Pro fan manager daemon
After=systemd-modules-load.service

[Service]
Type=simple
ExecStartPre=$modprobe_bin coretemp
ExecStartPre=$modprobe_bin applesmc
ExecStart=$mbpfan_bin -f
ExecReload=/usr/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now mbpfan.service
  systemctl is-active --quiet mbpfan.service || die "mbpfan.service failed to start."
  touch "$MBPFAN_INSTALLED"
  ok "Optional pinned mbpfan service installed; no display configuration was changed"
}

verify_cooling(){
  log "Cooling / Fan policy"
  local rc=0
  if systemctl is-enabled --quiet mbpfan.service 2>/dev/null; then
    if systemctl is-active --quiet mbpfan.service; then ok "optional mbpfan.service is active"; else fail "mbpfan.service is enabled but inactive"; rc=1; fi
  else
    ok "Apple SMC firmware fan control retained (mbpfan not enabled)"
  fi
  if systemctl is-active --quiet macbook-cpu-cooling.service; then
    ok "macbook-cpu-cooling.service is active"
  else
    fail "macbook-cpu-cooling.service is inactive"
    rc=1
  fi
  if [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
    local nt; nt="$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo 0)"
    if [[ "$nt" == "1" ]]; then ok "CPU Turbo Boost disabled (low heat mode)"; else warn "CPU Turbo Boost enabled (higher heat)"; fi
  fi
  return "$rc"
}

# ---------- GPU Switching (apple-gmux / EFI) ----------
active_gpu(){
  local d conn card pci bdf edid
  for d in /sys/class/drm/card*-eDP-*; do
    [[ -e "$d/status" && "$(cat "$d/status" 2>/dev/null)" == "connected" ]] || continue
    edid="$(head -c 4 "$d/edid" 2>/dev/null | wc -c)"
    # Filter out phantom connected connectors with no valid EDID
    (( edid > 0 )) || continue
    conn="$(basename "$d")"
    card="${conn%%-*}"
    pci="$(readlink -f "/sys/class/drm/$card/device" 2>/dev/null || true)"
    bdf="$(basename "$pci")"
    if [[ "$bdf" =~ ^0000:00:02 ]]; then echo "intel"; return 0; fi
    if [[ "$bdf" =~ ^0000:01:00 ]]; then echo "amd"; return 0; fi
  done
  echo "unknown"
}

external_output_connected(){
  local d
  shopt -s nullglob
  for d in /sys/class/drm/card*-DP-* /sys/class/drm/card*-HDMI-A-*; do
    if [[ -e "$d/status" && "$(cat "$d/status" 2>/dev/null)" == "connected" ]]; then
      shopt -u nullglob
      echo "$(basename "$d")"
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

target_user_home(){
  local user="${SUDO_USER:-${USER:-root}}"
  [[ "$user" != "root" ]] || return 1
  getent passwd "$user" | awk -F: '{print $6}'
}

legacy_graphics_present(){
  local home
  grep -Eq '(^|[[:space:]])video=eDP-2:d([[:space:]]|$)' "$LIMINE" 2>/dev/null && return 0
  grep -q '^AQ_DRM_DEVICES=' /etc/environment 2>/dev/null && return 0
  home="$(target_user_home || true)"
  if [[ -n "$home" ]]; then
    legacy_graphics_in_home "$home" && return 0
  else
    for home in /home/*; do
      [[ -d "$home" ]] || continue
      legacy_graphics_in_home "$home" && return 0
    done
  fi
  return 1
}

legacy_graphics_in_home(){
  local home="$1"
  grep -q 'AQ_DRM_DEVICES' "$home/.config/environment.d/10-graphics.conf" 2>/dev/null && return 0
  grep -q 'AQ_DRM_DEVICES' "$home/.config/uwsm/env.d/10-graphics" 2>/dev/null && return 0
  grep -q 'AQ_DRM_DEVICES' "$home/.config/uwsm/default" 2>/dev/null && return 0
  grep -q 'hl.env("AQ_DRM_DEVICES"' "$home/.config/hypr/hyprland.lua" 2>/dev/null && return 0
  grep -Fq 'hl.monitor({ output = "eDP-2", disabled = true })' "$home/.config/hypr/monitors.lua" 2>/dev/null && return 0
  grep -Fq 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })' "$home/.config/hypr/monitors.lua" 2>/dev/null && return 0
  return 1
}

preflight_igpu(){
  local driver ext
  [[ -e /sys/bus/pci/devices/0000:00:02.0 ]] || die "Intel IGD 00:02.0 is hidden by firmware. Configure apple_set_os/rEFInd first, reboot, and confirm 'lspci -nnk -s 00:02.0' shows Intel graphics before changing EFI GPU preference."
  driver="$(basename "$(readlink -f /sys/bus/pci/devices/0000:00:02.0/driver 2>/dev/null)" 2>/dev/null || true)"
  [[ "$driver" == "i915" ]] || die "Intel IGD is visible but not bound to i915 (driver: ${driver:-none}); refusing an iGPU switch."
  ext="$(external_output_connected || true)"
  [[ -z "$ext" ]] || die "External output $ext is connected. Disconnect all USB-C/DisplayPort/HDMI displays before selecting iGPU mode."
  ! legacy_graphics_present || die "Legacy hard-coded eDP/AQ_DRM settings are present. Run '$0 cleanup-legacy-graphics', log out/reboot if it changed user graphics config, then retry."
  ok "Intel IGD is visible and bound to i915; no external display is connected"
}

backup_efi_gpu_once(){
  local f="${EFI_VARS}/${EFI_GPU_VAR}"
  install -d -m 0755 "$STATE"
  [[ ! -e "$EFI_GPU_BAK" && ! -e "$EFI_GPU_ABSENT" ]] || return 0
  if [[ -e "$f" ]]; then
    cp -a "$f" "$EFI_GPU_BAK"
  else
    touch "$EFI_GPU_ABSENT"
  fi
}

restore_efi_gpu(){
  local f="${EFI_VARS}/${EFI_GPU_VAR}"
  if [[ -e "$EFI_GPU_BAK" ]]; then
    chattr -i "$f" 2>/dev/null || true
    cp -f "$EFI_GPU_BAK" "$f"
    ok "Original EFI GPU preference restored"
  elif [[ -e "$EFI_GPU_ABSENT" ]]; then
    chattr -i "$f" 2>/dev/null || true
    rm -f "$f"
    ok "Script-created EFI GPU preference removed"
  else
    warn "No EFI GPU backup marker exists; EFI preference was left unchanged"
  fi
}

efi_gpu_pref(){
  local f="${EFI_VARS}/${EFI_GPU_VAR}"
  [[ -e "$f" ]] || { echo "unset"; return 0; }
  local b; b="$(od -An -j4 -N1 -t u1 "$f" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$b" == "1" ]]; then echo "intel"; elif [[ "$b" == "0" ]]; then echo "amd"; else echo "unknown"; fi
}

write_efi_gpu_pref(){
  local mode="$1" f="${EFI_VARS}/${EFI_GPU_VAR}" tmp had_old=0
  tmp="$(mktemp)"
  if [[ -e "$f" ]]; then cp -f "$f" "$tmp"; had_old=1; fi
  chattr -i "$f" 2>/dev/null || true
  if [[ "$mode" == "intel" ]]; then
    if ! printf "\x07\x00\x00\x00\x01\x00\x00\x00" > "$f" || [[ "$(efi_gpu_pref)" != "intel" ]]; then
      chattr -i "$f" 2>/dev/null || true
      if (( had_old )); then cp -f "$tmp" "$f"; else rm -f "$f"; fi
      rm -f "$tmp"
      die "EFI Intel preference write failed verification; the value from before this command was restored."
    fi
  else
    if ! printf "\x07\x00\x00\x00\x00\x00\x00\x00" > "$f" || [[ "$(efi_gpu_pref)" != "amd" ]]; then
      chattr -i "$f" 2>/dev/null || true
      if (( had_old )); then cp -f "$tmp" "$f"; else rm -f "$f"; fi
      rm -f "$tmp"
      die "EFI AMD preference write failed verification; the value from before this command was restored."
    fi
  fi
  rm -f "$tmp"
  sync
}

switch_gpu(){
  local mode="$1" acknowledgement="${2:-}"
  [[ "$acknowledgement" == "--yes" ]] || die "GPU changes take effect at reboot and can make the internal display unusable. Re-run with --yes after reading the recovery steps in README.zh-CN.md."
  [[ "$mode" == "intel" || "$mode" == "igpu" || "$mode" == "amd" || "$mode" == "dgpu" ]] || die "Unknown GPU mode: $mode"
  [[ -d "$EFI_VARS" ]] || die "EFI variables directory ($EFI_VARS) not found."
  [[ "$mode" == "amd" || "$mode" == "dgpu" ]] || preflight_igpu
  backup_efi_gpu_once

  if [[ "$mode" == "intel" || "$mode" == "igpu" ]]; then
    log "Setting the next-boot EFI preference to Intel HD 530"
    write_efi_gpu_pref intel
    ok "Next-boot preference is Intel HD 530; no Hyprland, connector, or card-number override was written"
    warn "The bootloader must run apple_set_os on every iGPU boot. External USB-C display outputs normally require the AMD dGPU."
  elif [[ "$mode" == "amd" || "$mode" == "dgpu" ]]; then
    log "Setting the next-boot EFI preference to AMD Radeon Pro"
    write_efi_gpu_pref amd
    ok "Next-boot preference is AMD Radeon Pro; no running display route was changed"
  fi
  warn "Reboot required. Keep macOS/recovery boot media available until the next boot is verified."
}

verify_gpu(){
  log "Graphics / GPU Switching"
  local cur efi rc=0
  cur="$(active_gpu)"
  efi="$(efi_gpu_pref)"
  echo "  Current Display GPU : $cur"
  echo "  Next Boot EFI Mode  : $efi"
  if [[ "$cur" == "intel" ]]; then
    ok "Running on Intel HD 530"
  elif [[ "$cur" == "amd" ]]; then
    warn "Running on AMD Radeon Pro (Higher heat/power, required for external displays)"
  else
    fail "Could not identify a connected internal eDP panel with a valid EDID"
    rc=1
  fi
  if [[ "$efi" == "intel" || "$efi" == "amd" ]]; then
    [[ "$cur" == "$efi" ]] || { fail "Active display GPU does not match the saved EFI preference (pending reboot or failed switch)"; rc=1; }
  else
    warn "EFI GPU preference is $efi; no active/next-boot match can be asserted"
  fi
  return "$rc"
}

pm_test(){
  [[ "${1:-}" == "--yes" ]] || die "pm-test invokes system suspend. Re-run with --yes while physically present and after saving work."
  need_root; preflight; verify_suspend || die "Static suspend gates failed."
  [[ "$(active_gpu)" == "intel" ]] || die "Suspend testing on MacBookPro13,3 is only permitted while the internal display is on Intel iGPU."
  local ext; ext="$(external_output_connected || true)"
  [[ -z "$ext" ]] || die "Disconnect external display $ext before suspend testing."
  warn "pm_test=devices is staged testing; this is NOT a real low-power suspend."
  cleanup(){ echo none > /sys/power/pm_test 2>/dev/null || true; }
  trap cleanup EXIT INT TERM
  echo devices > /sys/power/pm_test
  log "Running systemctl suspend with pm_test=devices"
  systemctl suspend
  cleanup; trap - EXIT INT TERM
  ok "pm_test=devices returned successfully"
  journalctl -k -b --no-pager | grep -Ei 'PM: suspend|PM: resume|PM:.*test|nvme|xhci|amdgpu|i915|apple|ibridge' | tail -n 180 || true
  warn "Real suspend must still be tested manually with physical access: sudo systemctl suspend"
}
previous_boot(){
  need_root
  echo "=== Previous boot: kernel suspend/resume ==="
  journalctl -b -1 -k --no-pager 2>/dev/null | grep -Ei 'PM: suspend|PM: resume|freeze|nvme|d3cold|amdgpu|i915|drm|xhci|thunderbolt|apple|ibridge|error|fail' | tail -n 300 || true
  echo; echo "=== Previous boot: systemd sleep ==="
  journalctl -b -1 --no-pager 2>/dev/null | grep -Ei 'systemd-sleep|systemd-logind.*(suspend|sleep|lid)|suspend entry|suspend exit' | tail -n 180 || true
}

status(){
  need_root; preflight
  echo "Kernel: $(uname -r)"; echo "Boot: $(cat /proc/cmdline)"; echo
  verify_gpu || true; echo
  verify_cooling || true; echo
  verify_wifi || true; echo
  verify_applespi || true; echo
  verify_webcam || true; echo
  verify_fans_thermal || true; echo
  verify_audio || true; echo
  verify_touchbar || true; echo
  verify_suspend || true
}
verify(){
  need_root; preflight; local rc=0
  verify_gpu || true
  verify_cooling || rc=1
  verify_wifi || rc=1
  verify_applespi || rc=1
  verify_webcam || rc=1
  verify_fans_thermal || rc=1
  verify_audio || rc=1
  verify_touchbar || rc=1
  verify_suspend || rc=1
  echo
  if (( rc == 0 )); then
    ok "All automated hardware fix gates passed"
    warn "Manual gates: physical audio playback and repeated real suspend/resume stability."
  else
    fail "One or more hardware fix gates failed"
  fi
  return "$rc"
}

install_base(){
  need_root; preflight
  (($# == 0)) || die "install-base takes no arguments; risky components are installed as separate stages."
  install_packages
  ok "Base dependencies and matching running-kernel headers are ready"
  echo "NEXT: install and verify one hardware component at a time; see README.zh-CN.md."
}

remove_exact_limine_arg(){
  local arg="$1" line tmp
  [[ -f "$LIMINE" ]] || return 0
  line="KERNEL_CMDLINE[default]+=\" $arg\""
  tmp="$(mktemp)"
  grep -Fvx "$line" "$LIMINE" > "$tmp" || true
  if ! cmp -s "$tmp" "$LIMINE"; then
    install -m 0644 "$tmp" "$LIMINE"
  fi
  rm -f "$tmp"
}

restore_limine_arg(){
  local arg="$1" line backup="$STATE/macbook-t1.conf.before"
  line="KERNEL_CMDLINE[default]+=\" $arg\""
  if [[ -f "$backup" ]] && grep -Fqx "$line" "$backup"; then
    touch "$LIMINE"
    grep -Fqx "$line" "$LIMINE" || printf '%s\n' "$line" >> "$LIMINE"
  else
    remove_exact_limine_arg "$arg"
  fi
}

remove_script_aq_file(){
  local file="$1"
  [[ -f "$file" ]] || return 0
  if awk 'NF && $0 !~ /^(export )?AQ_DRM_DEVICES=\/dev\/dri\/card[0-9]+:\/dev\/dri\/card[0-9]+$/ { bad=1 } END { exit bad }' "$file"; then
    rm -f "$file"
  else
    warn "Preserving $file because it contains settings other than the legacy script AQ_DRM_DEVICES line"
  fi
}

cleanup_legacy_graphics(){
  need_root; preflight_model
  local changed_boot=0 home hypr monitors
  if grep -Fqx 'KERNEL_CMDLINE[default]+=" video=eDP-2:d"' "$LIMINE" 2>/dev/null; then
    remove_exact_limine_arg "video=eDP-2:d"
    changed_boot=1
  fi
  sed -i '/^AQ_DRM_DEVICES=\/dev\/dri\/card[0-9]\+:\/dev\/dri\/card[0-9]\+$/d' /etc/environment 2>/dev/null || true
  home="$(target_user_home || true)"
  if [[ -n "$home" && -d "$home" ]]; then
    remove_script_aq_file "$home/.config/environment.d/10-graphics.conf"
    remove_script_aq_file "$home/.config/uwsm/env.d/10-graphics"
    remove_script_aq_file "$home/.config/uwsm/default"
    hypr="$home/.config/hypr/hyprland.lua"
    monitors="$home/.config/hypr/monitors.lua"
    [[ ! -f "$hypr" ]] || sed -i '/^[[:space:]]*hl\.env("AQ_DRM_DEVICES", "\/dev\/dri\/card[0-9]\+:\/dev\/dri\/card[0-9]\+")[[:space:]]*$/d' "$hypr"
    if [[ -f "$monitors" ]]; then
      sed -i '/^[[:space:]]*hl\.monitor({ output = "eDP-2", disabled = true })[[:space:]]*$/d' "$monitors"
      sed -i '/^[[:space:]]*hl\.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })[[:space:]]*$/d' "$monitors"
    fi
  fi
  if (( changed_boot )); then
    have limine-update || die "Removed legacy Limine source configuration, but limine-update is unavailable. Install/fix Limine before rebooting."
    limine-update
  fi
  ok "Legacy hard-coded DRM card ordering and eDP connector overrides removed"
  warn "Log out and back in (or reboot) before GPU preflight if a user graphics file changed."
}

rollback(){
  need_root; preflight_model
  systemctl disable --now touchbar.service >/dev/null 2>&1 || true
  systemctl disable --now mbp15-nvme-d3cold.service >/dev/null 2>&1 || true
  systemctl disable --now mbp13-nvme-d3cold.service >/dev/null 2>&1 || true
  systemctl disable --now mbpfan.service >/dev/null 2>&1 || true
  systemctl disable --now macbook-cpu-cooling.service >/dev/null 2>&1 || true
  if [[ -e "$TB_INSTALLED" || -d "$T1_REPO/.git" ]]; then dkms remove -m appleibridge -v 0.1 --all >/dev/null 2>&1 || true; fi
  if [[ -e "$AUDIO_INSTALLED" || -d "$AUDIO_REPO/.git" ]]; then dkms remove -m snd_hda_macbookpro -v 0.1 --all >/dev/null 2>&1 || true; fi
  restore_or_remove "$TB_HELPER" "touchbar-enable.sh.before"
  restore_or_remove "$TB_UNIT" "touchbar.service.before"
  restore_or_remove "$TB_RESUME" "90-mbp-touchbar-resume.before"
  restore_or_remove "$TB_MODPROBE" "99-appleibridge-late-load.conf.before"
  restore_tree_or_remove "/usr/src/appleibridge-0.1" "appleibridge-0.1.src.before"
  if [[ -e "$STATE/30-mbp15-suspend.conf.before" || -e "$STATE/30-mbp15-suspend.conf.before.absent" ]]; then
    restore_or_remove "$SLEEP_CONF" "30-mbp15-suspend.conf.before"
  fi
  restore_or_remove "$NVME_UNIT" "mbp15-nvme-d3cold.service.before"
  restore_or_remove "$MBPFAN_CONF" "mbpfan.conf.before"
  restore_or_remove "$MBPFAN_UNIT" "mbpfan.service.before"
  restore_or_remove "$COOLING_UNIT" "macbook-cpu-cooling.service.before"
  if [[ -f "$MBPFAN_BIN_PATH" ]]; then
    local mbpfan_path
    mbpfan_path="$(head -n 1 "$MBPFAN_BIN_PATH")"
    if [[ "$mbpfan_path" == /usr/*/mbpfan || "$mbpfan_path" == /usr/local/*/mbpfan ]]; then
      if [[ -e "$MBPFAN_BIN_BAK" ]]; then cp -a "$MBPFAN_BIN_BAK" "$mbpfan_path"; elif [[ -e "$MBPFAN_BIN_ABSENT" ]]; then rm -f "$mbpfan_path"; fi
    else
      warn "Ignoring unsafe saved mbpfan path: $mbpfan_path"
    fi
  fi
  restore_limine_arg "modprobe.blacklist=apple_ibridge,apple_ib_tb,apple_ib_als"
  restore_limine_arg "pcie_ports=compat"
  restore_limine_arg "video=eDP-2:d"
  restore_limine_arg "mem_sleep_default=s2idle"
  restore_limine_arg "iommu=pt"
  restore_limine_arg "intel_iommu=on"
  [[ ! -f "$LIMINE" || -s "$LIMINE" ]] || rm -f "$LIMINE"
  if [[ -e "$WIFI_BAK" ]]; then
    cp -a "$WIFI_BAK" "$WIFI_FILE"
  elif [[ -e "$WIFI_INSTALLED" ]]; then
    rm -f "$WIFI_FILE"
  fi
  restore_efi_gpu

  local user_home
  user_home="$(target_user_home || true)"
  if [[ -n "$user_home" && -d "$user_home" ]]; then
    remove_script_aq_file "$user_home/.config/environment.d/10-graphics.conf"
    remove_script_aq_file "$user_home/.config/uwsm/env.d/10-graphics"
    remove_script_aq_file "$user_home/.config/uwsm/default"
    sed -i '/^[[:space:]]*hl\.env("AQ_DRM_DEVICES", "\/dev\/dri\/card[0-9]\+:\/dev\/dri\/card[0-9]\+")[[:space:]]*$/d' "$user_home/.config/hypr/hyprland.lua" 2>/dev/null || true
    sed -i '/^[[:space:]]*hl\.monitor({ output = "eDP-2", disabled = true })[[:space:]]*$/d' "$user_home/.config/hypr/monitors.lua" 2>/dev/null || true
    sed -i '/^[[:space:]]*hl\.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })[[:space:]]*$/d' "$user_home/.config/hypr/monitors.lua" 2>/dev/null || true
  fi
  sed -i '/^AQ_DRM_DEVICES=\/dev\/dri\/card[0-9]\+:\/dev\/dri\/card[0-9]\+$/d' /etc/environment 2>/dev/null || true

  systemctl daemon-reload
  if have limine-update; then limine-update || warn "limine-update failed; repair/update the boot entry before rebooting"; else warn "limine-update not found; boot entry was not refreshed"; fi
  rm -f "$AUDIO_INSTALLED" "$TB_INSTALLED" "$WIFI_INSTALLED" "$MBPFAN_INSTALLED"
  ok "Rollback staged; reboot required"
}

usage(){
  cat <<USAGE
MacBookPro13,3 (2016 15-inch Touch Bar/T1) hardware fix & cooling script

Usage:
  sudo $0 status
  sudo $0 install-base
  sudo $0 install-wifi AA:BB:CC:DD:EE:FF
  sudo $0 install-touchbar
  sudo $0 install-suspend
  sudo $0 install-cooling
  sudo $0 install-mbpfan
  sudo $0 install-audio --ack-kernel-risk
  sudo $0 cleanup-legacy-graphics
  sudo $0 gpu-igpu --yes
  sudo $0 gpu-dgpu --yes
  sudo reboot
  sudo $0 verify
  sudo $0 verify-COMPONENT  # COMPONENT: touchbar, suspend, gpu, wifi, cooling, or audio
  sudo $0 pm-test --yes
  sudo $0 previous-boot
  sudo $0 rollback

Commands:
  install-base     Install dependencies only; there is deliberately no full one-shot install
  install-cooling  Deploy a conservative CPU policy without changing displays
  install-mbpfan   Optionally build the pinned active fan daemon
  gpu-igpu         Preflight Intel/i915 and external displays, then set next-boot EFI preference
  gpu-dgpu         Set next-boot AMD EFI preference; neither GPU command edits Hyprland
  install-suspend  Deploy only pcie_ports=compat and the NVMe D3cold service
  install-touchbar Build the pinned Touch Bar DKMS driver without a blocking resume hook
  install-audio    Opt-in pinned audio DKMS; install last because kernel compatibility varies
USAGE
}

if [[ "${MBP15_LIB_ONLY:-0}" != "1" ]]; then
  case "${1:-}" in
    status) status ;;
    install|apply|install-base) shift; install_base "$@" ;;
    install-wifi) shift; (($# == 1)) || die "Usage: sudo $0 install-wifi AA:BB:CC:DD:EE:FF"; need_root; preflight; install_wifi "$1" ;;
    install-suspend|install-nvme) need_root; preflight; install_suspend ;;
    install-cooling|install-thermal) need_root; preflight_model; install_cooling ;;
    install-mbpfan) need_root; preflight_model; install_mbpfan ;;
    cleanup-legacy-graphics) cleanup_legacy_graphics ;;
    gpu-igpu|switch-igpu) shift; [[ $# -eq 1 ]] || die "Usage: sudo $0 gpu-igpu --yes"; need_root; preflight_model; switch_gpu intel "$1" ;;
    gpu-dgpu|switch-dgpu) shift; [[ $# -eq 1 ]] || die "Usage: sudo $0 gpu-dgpu --yes"; need_root; preflight_model; switch_gpu amd "$1" ;;
    install-touchbar) need_root; preflight; install_touchbar ;;
    install-audio) shift; [[ $# -eq 1 ]] || die "Usage: sudo $0 install-audio --ack-kernel-risk"; need_root; preflight; install_audio "$1" ;;
    verify) verify ;;
    verify-touchbar) need_root; preflight; verify_touchbar ;;
    verify-suspend) need_root; preflight; verify_suspend ;;
    verify-gpu) need_root; preflight_model; verify_gpu ;;
    verify-wifi) need_root; preflight; verify_wifi ;;
    verify-cooling) need_root; preflight_model; verify_cooling ;;
    verify-audio) need_root; preflight; verify_audio ;;
    pm-test) shift; [[ $# -eq 1 ]] || die "Usage: sudo $0 pm-test --yes"; pm_test "$1" ;;
    previous-boot) previous_boot ;;
    rollback) rollback ;;
    help|-h|--help|"") usage ;;
    *) usage; exit 2 ;;
  esac
fi
