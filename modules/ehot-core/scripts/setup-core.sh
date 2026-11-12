#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Core Setup Script
# Modes:
#   --mode chroot : Inside ISO squashfs customization (skips /swapfile creation)
#   --mode target : On installed target system (also creates 4 GB /swapfile)

MODE="target"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CFG_DIR="$MODULE_DIR/config"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите с правами root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[ehot-core] Установка базовых пакетов EHOT OS Core (режим: $MODE)..."
apt-get update -qq
apt-get install -y --no-install-recommends \
  systemd-zram-generator \
  earlyoom \
  ubuntu-drivers-common \
  linux-firmware \
  firmware-sof-signed \
  pipewire \
  pipewire-pulse \
  wireplumber \
  bluez \
  blueman \
  firefox \
  libreoffice-writer \
  libreoffice-calc \
  libreoffice-impress \
  libreoffice-gtk3 \
  libreoffice-l10n-ru \
  timeshift \
  ufw \
  inxi \
  pciutils \
  usbutils \
  python3 \
  python3-tk \
  zenity \
  curl \
  ca-certificates \
  gnupg \
  jq \
  htop \
  grub-efi-amd64-bin \
  grub-pc-bin

echo "[ehot-core] Применение конфигураций ZRAM, sysctl, earlyoom, journald, Firefox, LightDM..."
install -Dm644 "$CFG_DIR/zram-generator.conf" /etc/systemd/zram-generator.conf
install -Dm644 "$CFG_DIR/99-ehot-sysctl.conf" /etc/sysctl.d/99-ehot-sysctl.conf
install -Dm644 "$CFG_DIR/earlyoom" /etc/default/earlyoom
mkdir -p /etc/systemd/journald.conf.d
install -Dm644 "$CFG_DIR/journald-ehot.conf" /etc/systemd/journald.conf.d/99-ehot.conf

mkdir -p /etc/firefox/policies
install -Dm644 "$CFG_DIR/firefox-policies.json" /etc/firefox/policies/policies.json

mkdir -p /etc/lightdm
install -Dm644 "$CFG_DIR/lightdm-ehot.conf" /etc/lightdm/slick-greeter.conf

# Install driver setup helper system-wide
install -Dm755 "$MODULE_DIR/drivers/gpu_detect.py" /usr/local/lib/ehot-os/gpu_detect.py
install -Dm755 "$MODULE_DIR/drivers/ehot-driver-setup.sh" /usr/local/sbin/ehot-driver-setup

# Enable earlyoom and ufw firewall safely (avoid loading iptables inside chroot)
systemctl enable earlyoom.service || true
systemctl enable ufw.service || true
if [[ "$MODE" == "target" ]]; then
  ufw --force enable || true
fi

if [[ "$MODE" == "target" ]]; then
  sysctl --system || true
  systemctl daemon-reload || true
  systemctl restart systemd-zram-setup@zram0.service || true
  systemctl restart earlyoom.service || true

  # Create 4 GB disk swapfile (low priority 10, secondary to ZRAM priority 100)
  if [[ ! -f /swapfile ]]; then
    echo "[ehot-core] Создание /swapfile (4 ГБ) с приоритетом 10 для страховки 4 ГБ RAM..."
    if ! fallocate -l 4G /swapfile 2>/dev/null; then
      dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
    fi
    chmod 600 /swapfile
    mkswap /swapfile
    swapon -p 10 /swapfile || true
    if ! grep -q '^/swapfile ' /etc/fstab; then
      echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
    fi
  fi
fi

# Optimize non-essential services safely
bash "$SCRIPT_DIR/optimize-services.sh"

echo "[ehot-core] Модуль ehot-core успешно настроен."
