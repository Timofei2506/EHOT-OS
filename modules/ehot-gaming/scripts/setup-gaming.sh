#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Gaming Subsystem Setup
# Installs Steam, Wine, Lutris, GameMode, MangoHud, Vulkan (amd64 + i386), Flatpak.
# Explicitly does NOT install Minecraft Launcher or Telegram Desktop.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CFG_DIR="$MODULE_DIR/config"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите с правами root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[ehot-gaming] Включение архитектуры i386 (требуется для Steam, Wine и 32-bit игр)..."
dpkg --add-architecture i386
apt-get update -qq

# Preseed Steam license acceptance for automated/chroot installation
echo "steam steam/question select I AGREE" | debconf-set-selections || true
echo "steam steam/license note" | debconf-set-selections || true

echo "[ehot-gaming] Установка Steam, Wine, Lutris, GameMode, MangoHud, Vulkan..."
apt-get install -y --no-install-recommends \
  steam-installer \
  wine-installer \
  wine32 \
  winetricks \
  lutris \
  gamemode \
  gamemode-daemon \
  libgamemode0 \
  libgamemode0:i386 \
  mangohud \
  vulkan-tools \
  libvulkan1 \
  libvulkan1:i386 \
  mesa-vulkan-drivers \
  mesa-vulkan-drivers:i386 \
  flatpak \
  default-jre

echo "[ehot-gaming] Применение профилей GameMode и MangoHud..."
install -Dm644 "$CFG_DIR/gamemode.ini" /etc/gamemode.ini
mkdir -p /etc/skel/.config/MangoHud
install -Dm644 "$CFG_DIR/MangoHud.conf" /etc/skel/.config/MangoHud/MangoHud.conf

if [[ -d /home/Regzen ]]; then
  mkdir -p /home/Regzen/.config/MangoHud
  install -Dm644 "$CFG_DIR/MangoHud.conf" /home/Regzen/.config/MangoHud/MangoHud.conf
  chown -R Regzen:Regzen /home/Regzen/.config/MangoHud || true
fi

# Add Flathub remote cleanly (optional apps like Sober can be installed manually by owner)
if command -v flatpak >/dev/null 2>&1; then
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
fi

# Install compatibility checker tool
install -Dm755 "$SCRIPT_DIR/ehot-game-check.sh" /usr/local/bin/ehot-game-check

echo "[ehot-gaming] Игровая подсистема установлена."
