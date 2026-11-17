#!/usr/bin/env bash
set -euo pipefail

# EHOT OS First-Boot Hardware & Owner Setup Service
# Runs once on the newly installed Lenovo laptop after first boot.

STAMP_FILE="/var/lib/ehot-os/firstboot.done"
LOG_FILE="/var/log/ehot-firstboot.log"

# Product identity (EHOT OS by default; public edition overrides /etc/ehot-edition.conf)
EDITION_CONF="/etc/ehot-edition.conf"
PRODUCT_NAME="EHOT OS"
TARGET_USERNAME="Regzen"
if [[ -f "$EDITION_CONF" ]]; then
  while IFS="=" read -r _key _val; do
    _key="${_key//[$'\t']/}"
    _key="${_key% }"
    _val="${_val%\r}"
    _val="${_val%\"}"; _val="${_val#\"}"
    _sq="'"
    _val="${_val%"$_sq"}"; _val="${_val#"$_sq"}"
    case "$_key" in
      PRODUCT_NAME)     [[ -n "$_val" ]] && PRODUCT_NAME="$_val" ;;
      PRODUCT_USERNAME) [[ -n "$_val" ]] && TARGET_USERNAME="$_val" ;;
    esac
  done < "$EDITION_CONF"
fi

mkdir -p /var/lib/ehot-os
if [[ -f "$STAMP_FILE" ]]; then
  exit 0
fi

exec > >(tee -a "$LOG_FILE") 2>&1

echo "[ehot-firstboot] Запуск первоначальной настройки оборудования $PRODUCT_NAME..."

if command -v ufw >/dev/null 2>&1; then
  ufw --force enable || true
fi

# Auto-detect and install official GPU, Wi-Fi, Bluetooth, and Audio drivers
if [[ -x /usr/local/sbin/ehot-driver-setup ]]; then
  /usr/local/sbin/ehot-driver-setup || echo "[ehot-firstboot] Предупреждение: драйверы будут доустановлены после появления сети."
fi

# Reminder to finish the personal-edition remote/agent setup. The public edition does not
# ship those helper scripts at all, so this block is skipped entirely there.
if command -v ehot-remote-setup >/dev/null 2>&1 || command -v ehot-control-setup >/dev/null 2>&1; then
  if [[ -d "/home/$TARGET_USERNAME/Desktop" ]]; then
    cat > "/home/$TARGET_USERNAME/Desktop/ehot-finish-setup.desktop" <<'EOF'
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
    chmod +x "/home/$TARGET_USERNAME/Desktop/ehot-finish-setup.desktop"
    chown "$TARGET_USERNAME:$TARGET_USERNAME" "/home/$TARGET_USERNAME/Desktop/ehot-finish-setup.desktop" || true
  fi
fi

touch "$STAMP_FILE"
systemctl disable ehot-firstboot.service || true
echo "[ehot-firstboot] Первичная настройка завершена."
