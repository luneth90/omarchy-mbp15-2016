#!/usr/bin/env bash
set -Eeuo pipefail

# MacBookPro13,3 (2016 15-inch Touch Bar/T1) Hardware Fix Script
# Validated target: Arch/Omarchy, Linux 7.1.x/7.2.x family.
#
# Commands:
#   sudo ./omarchy-mbp15-2016.sh status
#   sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF [--switch-igpu]
#   sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram [--switch-igpu]
#   sudo ./omarchy-mbp15-2016.sh install-suspend
#   sudo ./omarchy-mbp15-2016.sh install-cooling
#   sudo ./omarchy-mbp15-2016.sh gpu-igpu
#   sudo ./omarchy-mbp15-2016.sh gpu-dgpu
#   sudo reboot
#   sudo ./omarchy-mbp15-2016.sh verify
#   sudo ./omarchy-mbp15-2016.sh pm-test
#   sudo ./omarchy-mbp15-2016.sh previous-boot
#   sudo ./omarchy-mbp15-2016.sh rollback
#
# IMPORTANT:
# - Requires dual-boot alongside macOS! Clean wipe/format installs erase Touch Bar firmware.
# - Preserves macOS / Apple EFI / APFS. Never repartitions disks.
# - Never runs a real suspend automatically.
# - Real suspend must be tested manually with physical access.
# - Wi-Fi NVRAM needs the REAL macOS Wi-Fi MAC; never use 00:90:4c:*.
# - Touch Bar & Suspend are fully decoupled from GPU; iGPU mode is 100% compatible.

MODEL="MacBookPro13,3"
STATE="/var/lib/mbp15-2016-t1-touchbar-fix"
SRC="/usr/local/src/mbp15-2016-t1-touchbar-fix"
T1_REPO="$SRC/omarchy-macbookpro-t1"
AUDIO_REPO="$SRC/snd_hda_macbookpro"
MBPFAN_REPO="$SRC/mbpfan"
T1_URL="https://github.com/nohzafk/omarchy-macbookpro-t1.git"
AUDIO_URL="https://github.com/davidjo/snd_hda_macbookpro.git"
MBPFAN_URL="https://github.com/linux-on-mac/mbpfan.git"

WIFI_URL="https://raw.githubusercontent.com/nohzafk/omarchy-macbookpro-t1/main/firmware/brcmfmac43602-pcie.txt"
WIFI_FILE="/usr/lib/firmware/brcm/brcmfmac43602-pcie.txt"
WIFI_BAK="$STATE/brcmfmac43602-pcie.txt.before"

TB_HELPER="/usr/local/sbin/touchbar-enable.sh"
TB_UNIT="/etc/systemd/system/touchbar.service"
TB_RESUME="/usr/lib/systemd/system-sleep/90-mbp-touchbar-resume"
TB_MODPROBE="/etc/modprobe.d/99-appleibridge-late-load.conf"

LIMINE="/etc/limine-entry-tool.d/macbook-t1.conf"
SLEEP_CONF="/etc/systemd/sleep.conf.d/30-mbp15-suspend.conf"
NVME_UNIT="/etc/systemd/system/mbp15-nvme-d3cold.service"

MBPFAN_CONF="/etc/mbpfan.conf"
COOLING_UNIT="/etc/systemd/system/macbook-cpu-cooling.service"
EFI_VARS="/sys/firmware/efi/efivars"
EFI_GPU_VAR="gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9"

log(){ printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m OK \033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2; }
fail(){ printf '\033[1;31mFAIL\033[0m %s\n' "$*" >&2; }
die(){ fail "$*"; exit 1; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run with sudo/root."; }
have(){ command -v "$1" >/dev/null 2>&1; }

model(){ cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true; }
preflight(){
  [[ "$(model)" == "$MODEL" ]] || die "This script targets $MODEL; detected $(model)."
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
  ok "$MODEL detected"
  ok "T1/iBridge 05ac:8600 detected"
}

backup_once(){
  local src="$1" name="$2"
  install -d -m 0755 "$STATE"
  [[ -e "$src" && ! -e "$STATE/$name" ]] && cp -a "$src" "$STATE/$name" || true
}
restore_or_remove(){
  local dst="$1" name="$2"
  if [[ -e "$STATE/$name" ]]; then cp -a "$STATE/$name" "$dst"; else rm -f "$dst"; fi
}

git_sync(){
  local url="$1" dir="$2"
  install -d -m 0755 "$(dirname "$dir")"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --depth=1 origin
    git -C "$dir" reset --hard origin/HEAD
  else
    rm -rf "$dir"
    git clone --depth 1 "$url" "$dir"
  fi
}

install_packages(){
  have pacman || die "pacman not found; this script targets Omarchy/Arch."
  pacman -S --needed --noconfirm base-devel git curl wget dkms linux-headers zstd patch \
    alsa-utils pipewire wireplumber usbutils pciutils iw v4l-utils lm_sensors
  if pacman -Q macbook12-spi-driver-dkms >/dev/null 2>&1; then
    pacman -Rns --noconfirm macbook12-spi-driver-dkms || true
  fi
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
  grep -q '^devid=0x43ba$' "$tmp" || die "Downloaded BCM43602 NVRAM failed sanity check."
  grep -q '^macaddr=' "$tmp" || die "Downloaded NVRAM lacks macaddr=."
  sed -i "s/^macaddr=.*/macaddr=$mac/" "$tmp"
  install -m 0644 "$tmp" "$WIFI_FILE"
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
  git_sync "$AUDIO_URL" "$AUDIO_REPO"
  log "Installing Cirrus CS8409 audio DKMS"
  ( cd "$AUDIO_REPO" && ./install.cirrus.driver.sh -i )
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
  git_sync "$T1_URL" "$T1_REPO"
  local drv="$T1_REPO/drivers/appleibridge" ver="0.1" src="/usr/src/appleibridge-0.1"
  [[ -f "$drv/dkms.conf" ]] || die "appleibridge dkms.conf missing."
  backup_once "$TB_HELPER" "touchbar-enable.sh.before"
  backup_once "$TB_UNIT" "touchbar.service.before"
  backup_once "$TB_RESUME" "90-mbp-touchbar-resume.before"
  backup_once "$TB_MODPROBE" "99-appleibridge-late-load.conf.before"

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

  cat > "$TB_RESUME" <<'TBEOF'
#!/bin/sh
case "$1/$2" in
  post/*)
    sleep 2
    if [ ! -f /run/touchbar/apple-ib-tb.ko ]; then
      KDIR="/lib/modules/$(uname -r)/updates/dkms"
      mkdir -p /run/touchbar
      if [ -f "$KDIR/apple-ib-tb.ko.zst" ]; then
        zstd -qdf "$KDIR/apple-ib-tb.ko.zst" -o /run/touchbar/apple-ib-tb.ko || exit 0
      elif [ -f "$KDIR/apple-ib-tb.ko" ]; then
        cp -f "$KDIR/apple-ib-tb.ko" /run/touchbar/apple-ib-tb.ko || exit 0
      else
        exit 0
      fi
    fi
    /usr/bin/rmmod apple_ib_tb 2>/dev/null || true
    sleep 1
    /usr/bin/insmod /run/touchbar/apple-ib-tb.ko fnmode=1 idle_timeout=-1 dim_timeout=-1 2>/dev/null || true
    ;;
esac
TBEOF
  chmod 0755 "$TB_RESUME"
  systemctl daemon-reload
  systemctl enable touchbar.service
  ok "Touch Bar DKMS + late boot service + resume reload hook installed"
}
touchbar_attr(){
  local p; p="$(readlink -f /sys/bus/hid/devices/0003:05AC:8600.0001 2>/dev/null || true)"
  [[ -n "$p" && -e "$p/fnmode" ]] || return 1
  printf '%s\n' "$p"
}
verify_touchbar(){
  log "Touch Bar"
  systemctl is-active --quiet touchbar.service || { fail "touchbar.service not active"; return 1; }
  local d fn; d="$(touchbar_attr || true)"
  [[ -n "$d" ]] || { fail "Touch Bar sysfs controls missing"; return 1; }
  fn="$(cat "$d/fnmode" 2>/dev/null || true)"
  echo "fnmode=$fn idle_timeout=$(cat "$d/idle_timeout" 2>/dev/null || true) dim_timeout=$(cat "$d/dim_timeout" 2>/dev/null || true)"
  [[ "$fn" == "1" ]] || { fail "Expected fnmode=1"; return 1; }
  for dev in 0003:05AC:8600.0001 0003:05AC:8600.0002; do
    local drv; drv="$(basename "$(readlink -f "/sys/bus/hid/devices/$dev/driver" 2>/dev/null)" 2>/dev/null || true)"
    echo "$dev -> ${drv:-NONE}"
    [[ "$drv" == "apple-ibridge-hid" ]] || { fail "$dev not owned by apple-ibridge-hid"; return 1; }
  done
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
  local smc_dir="" f rpm manual count=0
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
    ((count++))
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
  ok "Fans and thermal sensors operating under SMC firmware management"
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
append_cmdline(){ local a="$1"; touch "$LIMINE"; grep -Fq "$a" "$LIMINE" 2>/dev/null || printf 'KERNEL_CMDLINE[default]+=" %s"\n' "$a" >> "$LIMINE"; }
install_suspend(){
  install -d -m 0755 "$STATE" /etc/limine-entry-tool.d /etc/systemd/sleep.conf.d /etc/systemd/system
  backup_once "$LIMINE" "macbook-t1.conf.before"
  backup_once "$SLEEP_CONF" "30-mbp15-suspend.conf.before"
  backup_once "$NVME_UNIT" "mbp15-nvme-d3cold.service.before"

  cat > "$SLEEP_CONF" <<'SEOF'
[Sleep]
SuspendState=freeze
MemorySleepMode=s2idle
SEOF
  append_cmdline "mem_sleep_default=s2idle"
  append_cmdline "iommu=pt"
  append_cmdline "intel_iommu=on"
  append_cmdline "pcie_ports=compat"
  append_cmdline "modprobe.blacklist=apple_ibridge,apple_ib_tb,apple_ib_als"

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

  if systemctl cat omarchy-nvme-suspend-fix.service >/dev/null 2>&1; then
    systemctl disable --now omarchy-nvme-suspend-fix.service >/dev/null 2>&1 || true
    systemctl mask omarchy-nvme-suspend-fix.service >/dev/null 2>&1 || true
    ok "Disabled/masked legacy omarchy-nvme-suspend-fix.service"
  fi
  systemctl daemon-reload
  systemctl enable --now mbp15-nvme-d3cold.service
  have limine-update || die "limine-update not found"
  limine-update
  ok "s2idle/IOMMU/PCIe/NVMe suspend configuration installed"
}
verify_suspend(){
  log "Suspend / NVMe"
  local rc=0 a b v
  for a in mem_sleep_default=s2idle iommu=pt intel_iommu=on pcie_ports=compat modprobe.blacklist=apple_ibridge,apple_ib_tb,apple_ib_als; do
    if grep -qw "$a" /proc/cmdline; then ok "$a active"; else fail "$a missing"; rc=1; fi
  done
  local ms; ms="$(cat /sys/power/mem_sleep 2>/dev/null || true)"; echo "mem_sleep: $ms"
  [[ "$ms" == *"[s2idle]"* ]] && ok "s2idle selected" || { fail "s2idle not selected"; rc=1; }
  local found=0
  while read -r b; do
    [[ -n "$b" ]] || continue; found=1
    v="$(cat "/sys/bus/pci/devices/$b/d3cold_allowed" 2>/dev/null || true)"
    echo "NVMe $b d3cold_allowed=$v"
    [[ "$v" == "0" ]] && ok "NVMe $b D3cold disabled" || { fail "NVMe $b D3cold is not disabled"; rc=1; }
  done < <(nvme_bdfs)
  (( found )) || { fail "No NVMe d3cold control found"; rc=1; }
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
  log "Installing mbpfan (active thermal & fan daemon)"
  local user="${SUDO_USER:-${USER:-root}}"
  local pkg_cache="/home/$user/.cache/yay/mbpfan"
  local pkg=""
  if [[ -d "$pkg_cache" ]]; then
    pkg="$(find "$pkg_cache" -maxdepth 1 -name "mbpfan-[0-9]*.pkg.tar.zst" ! -name "*debug*" 2>/dev/null | head -n 1)"
  fi

  if [[ -n "$pkg" && -f "$pkg" ]]; then
    log "Installing pre-built mbpfan package: $pkg"
    pacman -U --noconfirm --needed "$pkg"
  else
    log "Compiling mbpfan from source..."
    git_sync "$MBPFAN_URL" "$MBPFAN_REPO"
    ( cd "$MBPFAN_REPO" && make && make install )
  fi

  backup_once "$MBPFAN_CONF" "mbpfan.conf.before"
  backup_once "$COOLING_UNIT" "macbook-cpu-cooling.service.before"

  log "Configuring mbpfan for MacBookPro13,3"
  cat > "$MBPFAN_CONF" <<'EOF'
[general]
min_fan1_speed = 2500
max_fan1_speed = 5900
min_fan2_speed = 2500
max_fan2_speed = 5400
low_temp = 50       # Under 50°C: quiet low speed
high_temp = 62      # Above 62°C: ramp up fan speed linearly
max_temp = 78       # At 78°C: maximum fan speed
polling_interval = 2
EOF

  systemctl daemon-reload
  systemctl enable --now mbpfan
  systemctl restart mbpfan

  log "Configuring CPU power & thermal policy"
  if have powerprofilesctl; then
    powerprofilesctl set power-saver 2>/dev/null || true
  fi

  cat > "$COOLING_UNIT" <<'EOF'
[Unit]
Description=MacBookPro CPU Thermal & Power Optimization
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo && echo powersave > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true; echo auto > /sys/bus/pci/devices/0000:01:00.0/power/control 2>/dev/null || true; echo auto > /sys/bus/pci/devices/0000:01:00.1/power/control 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now macbook-cpu-cooling.service

  log "Configuring graphics environment & disabling phantom display"
  append_cmdline "video=eDP-2:d"
  have limine-update && limine-update || true

  local user="${SUDO_USER:-${USER:-root}}"
  local user_home
  user_home="$(getent passwd "$user" | cut -d: -f6)"
  if [[ -n "$user_home" && -d "$user_home" && "$user" != "root" ]]; then
    local env_dir="$user_home/.config/environment.d"
    install -d -m 0755 -o "$user" -g "$user" "$env_dir"
    cat > "$env_dir/10-graphics.conf" <<'EOF'
AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:00:02.0-card
EOF
    chown "$user:$user" "$env_dir/10-graphics.conf"

    local mon_file="$user_home/.config/hypr/monitors.lua"
    if [[ -f "$mon_file" ]]; then
      if ! grep -q 'output = "eDP-2"' "$mon_file"; then
        if grep -q 'local omarchy_monitor_scale' "$mon_file"; then
          sed -i '/local omarchy_monitor_scale/a hl.monitor({ output = "eDP-2", disabled = true })\nhl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })' "$mon_file"
        else
          echo 'hl.monitor({ output = "eDP-2", disabled = true })' >> "$mon_file"
        fi
        chown "$user:$user" "$mon_file"
      fi
    fi

    local hypr_file="$user_home/.config/hypr/hyprland.lua"
    if [[ -f "$hypr_file" ]] && ! grep -q 'AQ_DRM_DEVICES' "$hypr_file"; then
      if grep -q 'require("default.hypr.omarchy")' "$hypr_file"; then
        sed -i '/require("default.hypr.omarchy")/a hl.env("AQ_DRM_DEVICES", "/dev/dri/by-path/pci-0000:00:02.0-card")' "$hypr_file"
      else
        echo 'hl.env("AQ_DRM_DEVICES", "/dev/dri/by-path/pci-0000:00:02.0-card")' >> "$hypr_file"
      fi
      chown "$user:$user" "$hypr_file"
    fi
  fi
  ok "Active cooling daemon (mbpfan), thermal policy, and display configs deployed"
}

verify_cooling(){
  log "Cooling & Fan Daemon (mbpfan)"
  if systemctl is-active --quiet mbpfan; then
    ok "mbpfan.service is active"
  else
    fail "mbpfan.service is inactive"
    return 1
  fi
  if [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
    local nt; nt="$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo 0)"
    if [[ "$nt" == "1" ]]; then ok "CPU Turbo Boost disabled (low heat mode)"; else warn "CPU Turbo Boost enabled (higher heat)"; fi
  fi
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

efi_gpu_pref(){
  local f="${EFI_VARS}/${EFI_GPU_VAR}"
  [[ -e "$f" ]] || { echo "unset"; return 0; }
  local b; b="$(hexdump -v -e '1/1 "%02x "' "$f" 2>/dev/null | awk '{print $5}')"
  if [[ "$b" == "01" ]]; then echo "intel"; else echo "amd"; fi
}

switch_gpu(){
  local mode="$1"
  [[ -d "$EFI_VARS" ]] || die "EFI variables directory ($EFI_VARS) not found."
  local f="${EFI_VARS}/${EFI_GPU_VAR}"
  chattr -i "$f" 2>/dev/null || true

  local user="${SUDO_USER:-${USER:-root}}"
  local user_home
  user_home="$(getent passwd "$user" | cut -d: -f6)"

  if [[ "$mode" == "intel" || "$mode" == "igpu" ]]; then
    log "Switching EFI preference to Integrated GPU (Intel HD 530)..."
    printf "\x07\x00\x00\x00\x01\x00\x00\x00" > "$f"

    if [[ -n "$user_home" && -d "$user_home" && "$user" != "root" ]]; then
      local env_dir="$user_home/.config/environment.d"
      install -d -m 0755 -o "$user" -g "$user" "$env_dir"
      echo 'AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:00:02.0-card' > "$env_dir/10-graphics.conf"
      chown "$user:$user" "$env_dir/10-graphics.conf"
      local hypr_file="$user_home/.config/hypr/hyprland.lua"
      if [[ -f "$hypr_file" ]] && ! grep -q 'AQ_DRM_DEVICES' "$hypr_file"; then
        if grep -q 'require("default.hypr.omarchy")' "$hypr_file"; then
          sed -i '/require("default.hypr.omarchy")/a hl.env("AQ_DRM_DEVICES", "/dev/dri/by-path/pci-0000:00:02.0-card")' "$hypr_file"
        else
          echo 'hl.env("AQ_DRM_DEVICES", "/dev/dri/by-path/pci-0000:00:02.0-card")' >> "$hypr_file"
        fi
        chown "$user:$user" "$hypr_file"
      fi
    fi

    ok "Set to Intel HD 530 for next boot (AMD dGPU idle power 0W)."
    warn "External display output (USB-C) will NOT function under iGPU mode (ports wired to AMD dGPU)."
    warn "Reboot required to switch GPU: sudo reboot"
  elif [[ "$mode" == "amd" || "$mode" == "dgpu" ]]; then
    log "Switching EFI preference to Dedicated GPU (AMD Radeon Pro)..."
    printf "\x07\x00\x00\x00\x00\x00\x00\x00" > "$f"

    if [[ -n "$user_home" && -d "$user_home" && "$user" != "root" ]]; then
      local env_dir="$user_home/.config/environment.d"
      if [[ -f "$env_dir/10-graphics.conf" ]]; then
        rm -f "$env_dir/10-graphics.conf"
      fi
      local hypr_file="$user_home/.config/hypr/hyprland.lua"
      if [[ -f "$hypr_file" ]]; then
        sed -i '/AQ_DRM_DEVICES/d' "$hypr_file"
      fi
    fi

    ok "Set to AMD Radeon Pro for next boot."
    warn "Reboot required to switch GPU: sudo reboot"
  else
    die "Unknown GPU mode: $mode (expected 'intel' or 'amd')"
  fi
}

verify_gpu(){
  log "Graphics / GPU Switching"
  local cur efi
  cur="$(active_gpu)"
  efi="$(efi_gpu_pref)"
  echo "  Current Display GPU : $cur"
  echo "  Next Boot EFI Mode  : $efi"
  if [[ "$cur" == "intel" ]]; then
    ok "Running on Intel HD 530 (Cool / Low Power mode, ~0W on AMD dGPU)"
  elif [[ "$cur" == "amd" ]]; then
    warn "Running on AMD Radeon Pro (Higher heat/power, required for external displays)"
  fi
}

pm_test(){
  need_root; preflight; verify_suspend || die "Static suspend gates failed."
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
  verify_cooling || true
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

install_all(){
  need_root; preflight
  local mac="" skip=0 switch_igpu=0
  while (($#)); do
    case "$1" in
      --wifi-mac) shift; (($#)) || die "--wifi-mac requires an address"; mac="$1" ;;
      --skip-wifi-nvram) skip=1 ;;
      --switch-igpu|--igpu) switch_igpu=1 ;;
      *) die "Unknown argument: $1" ;;
    esac
    shift
  done
  install_packages
  git_sync "$T1_URL" "$T1_REPO"
  if (( ! skip )); then
    if [[ -n "$mac" ]]; then install_wifi "$mac";
    elif [[ "$(wifi_mac || true)" =~ ^00:90:4[cC]: ]]; then die "Wi-Fi still has placeholder MAC. Re-run with --wifi-mac <real macOS MAC>.";
    else ok "Wi-Fi already has a non-placeholder MAC; leaving NVRAM unchanged"; fi
  fi
  install_audio
  install_touchbar
  install_suspend
  install_cooling
  if (( switch_igpu )); then
    switch_gpu intel
  fi
  echo
  ok "Hardware fix, cooling, and graphics configuration staged"
  echo "NEXT:"; echo "  sudo reboot"; echo "  sudo $0 verify"; echo "  sudo $0 pm-test"
  if (( ! switch_igpu )); then
    echo "To switch to Intel HD 530 integrated graphics (ultimate cooling): sudo $0 gpu-igpu && sudo reboot"
  fi
  echo "Then, only with physical access: sudo systemctl suspend"
}

rollback(){
  need_root; preflight
  systemctl disable --now touchbar.service >/dev/null 2>&1 || true
  systemctl disable --now mbp15-nvme-d3cold.service >/dev/null 2>&1 || true
  systemctl disable --now mbp13-nvme-d3cold.service >/dev/null 2>&1 || true
  systemctl disable --now mbpfan.service >/dev/null 2>&1 || true
  systemctl disable --now macbook-cpu-cooling.service >/dev/null 2>&1 || true
  restore_or_remove "$TB_HELPER" "touchbar-enable.sh.before"
  restore_or_remove "$TB_UNIT" "touchbar.service.before"
  restore_or_remove "$TB_RESUME" "90-mbp-touchbar-resume.before"
  restore_or_remove "$TB_MODPROBE" "99-appleibridge-late-load.conf.before"
  restore_or_remove "$SLEEP_CONF" "30-mbp15-suspend.conf.before"
  restore_or_remove "$NVME_UNIT" "mbp15-nvme-d3cold.service.before"
  restore_or_remove "$MBPFAN_CONF" "mbpfan.conf.before"
  restore_or_remove "$COOLING_UNIT" "macbook-cpu-cooling.service.before"
  if [[ -e "$STATE/macbook-t1.conf.before" ]]; then cp -a "$STATE/macbook-t1.conf.before" "$LIMINE"; fi
  if [[ -e "$WIFI_BAK" ]]; then cp -a "$WIFI_BAK" "$WIFI_FILE"; fi

  local user="${SUDO_USER:-${USER:-root}}"
  local user_home
  user_home="$(getent passwd "$user" | cut -d: -f6)"
  if [[ -n "$user_home" && -d "$user_home" && "$user" != "root" ]]; then
    rm -f "$user_home/.config/environment.d/10-graphics.conf"
    sed -i '/AQ_DRM_DEVICES/d' "$user_home/.config/hypr/hyprland.lua" 2>/dev/null || true
    sed -i '/eDP-2/d' "$user_home/.config/hypr/monitors.lua" 2>/dev/null || true
  fi

  systemctl unmask omarchy-nvme-suspend-fix.service >/dev/null 2>&1 || true
  systemctl daemon-reload
  have limine-update && limine-update || true
  ok "Rollback staged; reboot required"
}

usage(){
  cat <<USAGE
MacBookPro13,3 (2016 15-inch Touch Bar/T1) hardware fix & cooling script

Usage:
  sudo $0 status
  sudo $0 install --wifi-mac AA:BB:CC:DD:EE:FF [--switch-igpu]
  sudo $0 install --skip-wifi-nvram [--switch-igpu]
  sudo $0 install-suspend
  sudo $0 install-cooling
  sudo $0 gpu-igpu
  sudo $0 gpu-dgpu
  sudo reboot
  sudo $0 verify
  sudo $0 pm-test
  sudo $0 previous-boot
  sudo $0 rollback

Options:
  --switch-igpu, --igpu : Immediately set EFI GPU preference to Intel HD 530 during install
  --skip-wifi-nvram     : Keep existing Wi-Fi NVRAM configuration without re-flashing MAC

Commands:
  install-cooling : Deploy active fan control (mbpfan) and CPU thermal policy
  gpu-igpu        : Switch to Intel HD 530 integrated graphics (cool, high battery life)
  gpu-dgpu        : Switch to AMD Radeon Pro discrete graphics (for external displays)
  install-suspend : Deploy NVMe D3cold fix and Limine s2idle configuration
  install-touchbar: Build and install Touch Bar DKMS driver and service
  install-audio   : Build and install Cirrus CS8409 audio DKMS driver

Touch Bar & Suspend are completely decoupled from GPU state.
USAGE
}

case "${1:-}" in
  status) status ;;
  install|apply) shift; install_all "$@" ;;
  install-suspend|install-nvme) need_root; preflight; install_suspend ;;
  install-cooling|install-thermal) need_root; preflight; install_cooling ;;
  gpu-igpu|switch-igpu) need_root; preflight; switch_gpu intel ;;
  gpu-dgpu|switch-dgpu) need_root; preflight; switch_gpu amd ;;
  install-touchbar) need_root; preflight; install_touchbar ;;
  install-audio) need_root; preflight; install_audio ;;
  verify) verify ;;
  pm-test) pm_test ;;
  previous-boot) previous_boot ;;
  rollback) rollback ;;
  help|-h|--help|"") usage ;;
  *) usage; exit 2 ;;
esac
