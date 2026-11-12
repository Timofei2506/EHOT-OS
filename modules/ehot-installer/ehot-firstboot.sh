#!/usr/bin/env bash
set -euo pipefail

# EHOT OS First-Boot Hardware & Owner Setup Service
# Runs once on the newly installed Lenovo laptop after first boot.

STAMP_FILE="/var/lib/ehot-os/firstboot.done"
LOG_FILE="/var/log/ehot-firstboot.log"

mkdir -p /var/lib/ehot-os
if [[ -f "$STAMP_FILE" ]]; then
  exit 0
fi

exec > >(tee -a "$LOG_FILE") 2>&1

echo "[ehot-firstboot] Запуск первоначальной настройки оборудования EHOT OS..."

if command -v ufw >/dev/null 2>&1; then
  ufw --force enable || true
fi

# Auto-detect and install official GPU, Wi-Fi, Bluetooth, and Audio drivers
if [[ -x /usr/local/sbin/ehot-driver-setup ]]; then
  /usr/local/sbin/ehot-driver-setup || echo "[ehot-firstboot] Предупреждение: драйверы будут доустановлены после появления сети."
fi

# Create desktop reminder for owner to finish AnyDesk & Telegram setup interactively
if [[ -d /home/Regzen/Desktop ]]; then
  cat > /home/Regzen/Desktop/ehot-finish-setup.desktop <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Завершить настройку AnyDesk и Telegram
Comment=Задать пароль постоянного доступа AnyDesk и подключить бота EHOT Control
Exec=xfce4-terminal -T "Настройка EHOT OS" -e "bash -c 'sudo ehot-remote-setup; echo; sudo ehot-control-setup; echo Нажмите Enter...; read'"
Icon=preferences-system
Terminal=false
Categories=System;
EOF
  chmod +x /home/Regzen/Desktop/ehot-finish-setup.desktop
  chown Regzen:Regzen /home/Regzen/Desktop/ehot-finish-setup.desktop || true
fi

touch "$STAMP_FILE"
systemctl disable ehot-firstboot.service || true
echo "[ehot-firstboot] Первичная настройка завершена."
