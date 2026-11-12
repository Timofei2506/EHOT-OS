#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Remote: Install AnyDesk from official repository (deb.anydesk.com)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CFG_DIR="$MODULE_DIR/config"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите с правами root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[ehot-remote] Импорт официального GPG-ключа AnyDesk..."
install -d -m 755 /usr/share/keyrings /etc/apt/sources.list.d
curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY | gpg --dearmor --yes -o /usr/share/keyrings/anydesk.gpg
chmod 644 /usr/share/keyrings/anydesk.gpg

cat > /etc/apt/sources.list.d/anydesk.sources <<'EOF'
Types: deb
URIs: https://deb.anydesk.com/
Suites: all
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/anydesk.gpg
EOF

echo "[ehot-remote] Установка AnyDesk..."
apt-get update -qq
apt-get install -y --no-install-recommends anydesk

# Apply safe baseline system.conf ONLY if not already customized (no passwords!)
mkdir -p /etc/anydesk
if [[ ! -f /etc/anydesk/system.conf ]]; then
  install -m 644 "$CFG_DIR/anydesk-system.conf.template" /etc/anydesk/system.conf
fi

# Install setup wizard & local toggle tool
install -Dm755 "$SCRIPT_DIR/ehot-remote-setup.sh" /usr/local/sbin/ehot-remote-setup
install -Dm755 "$SCRIPT_DIR/ehot-remote-toggle.sh" /usr/local/bin/ehot-remote-toggle
install -Dm644 "$CFG_DIR/ehot-remote-toggle.desktop" /usr/share/applications/ehot-remote-toggle.desktop

# Enable service after OS installation
systemctl enable anydesk.service || true

echo "[ehot-remote] AnyDesk установлен. Для задания пароля постоянного доступа после установки выполните: sudo ehot-remote-setup"
