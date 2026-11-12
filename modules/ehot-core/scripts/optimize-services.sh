#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Safe Service Optimization for 4 GB RAM + HDD
# Preserves security updates, AppArmor, UFW, Timeshift, PipeWire, and NetworkManager.

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите с правами root." >&2
  exit 1
fi

echo "[optimize-services] Оптимизация фоновых служб (без отключения защиты и обновлений)..."

# Disable crash-telemetry uploaders if present (keeps system lighter and private)
for svc in apport.service whoopsie.service kerneloops.service; do
  if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
    systemctl disable "$svc" 2>/dev/null || true
    systemctl mask "$svc" 2>/dev/null || true
  fi
done

# Do not block boot for up to 2 minutes if Ethernet is unplugged (laptop uses Wi-Fi)
if systemctl list-unit-files systemd-networkd-wait-online.service >/dev/null 2>&1; then
  systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
fi

# Disable Mint's heavy welcome popup auto-start on every login (still available in menu)
rm -f /etc/xdg/autostart/mintwelcome.desktop || true

# Disable unneeded XDG autostart bloat while keeping nm-applet, power manager, blueman, polkit
for autostart in \
  /etc/xdg/autostart/mintreport.desktop \
  /etc/xdg/autostart/orca-autostart.desktop \
  /etc/xdg/autostart/tracker-miner-fs-3.desktop; do
  if [[ -f "$autostart" ]]; then
    if ! grep -q '^Hidden=true' "$autostart"; then
      echo 'Hidden=true' >> "$autostart"
    fi
  fi
done

echo "[optimize-services] Оптимизация служб завершена."
