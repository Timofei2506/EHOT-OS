#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Control Installer
# Deploys daemon, Telegram client module, Firefox Native Messaging host,
# systemd units, and secured config directories (without secrets!).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите с правами root." >&2
  exit 1
fi

echo "[ehot-control] Создание системного пользователя ehotcontrol..."
if ! id -u ehotcontrol >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin ehotcontrol
fi

install -d -m 755 /usr/local/lib/ehot-control
install -m 644 "$MODULE_DIR/agent/config.py" /usr/local/lib/ehot-control/config.py
install -m 644 "$MODULE_DIR/agent/telegram_client.py" /usr/local/lib/ehot-control/telegram_client.py
install -m 755 "$MODULE_DIR/agent/ehot_control_agent.py" /usr/local/lib/ehot-control/ehot_control_agent.py
install -m 755 "$MODULE_DIR/agent/cli.py" /usr/local/lib/ehot-control/cli.py
install -m 755 "$MODULE_DIR/native-host/ehot_native_host.py" /usr/local/lib/ehot-control/ehot_native_host.py

# Wrapper CLI
cat > /usr/local/bin/ehot-control-cli <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/local/lib/ehot-control/cli.py "$@"
EOF
chmod 755 /usr/local/bin/ehot-control-cli

# Native Messaging manifest for Mozilla Firefox
install -d -m 755 /usr/lib/mozilla/native-messaging-hosts
install -m 644 "$MODULE_DIR/native-host/com.ehotos.control.json" \
  /usr/lib/mozilla/native-messaging-hosts/com.ehotos.control.json

# Store extension source & README locally for easy signing / inspection
install -d -m 755 /usr/local/share/ehot-control/extension
cp -r "$MODULE_DIR/extension/"* /usr/local/share/ehot-control/extension/

# Config & secret protection (NEVER put real token/chat_id here!)
install -d -m 750 -o root -g ehotcontrol /etc/ehot-control
install -d -m 750 -o ehotcontrol -g ehotcontrol /var/lib/ehot-control
install -m 644 "$MODULE_DIR/config/control.conf" /etc/ehot-control/control.conf
install -m 644 "$MODULE_DIR/config/secrets.env.example" /etc/ehot-control/secrets.env.example
if [[ ! -f /etc/ehot-control/secrets.env ]]; then
  install -m 600 -o ehotcontrol -g ehotcontrol "$MODULE_DIR/config/secrets.env.example" /etc/ehot-control/secrets.env
fi

# Systemd units
install -m 644 "$MODULE_DIR/systemd/ehot-control.service" /etc/systemd/system/ehot-control.service
install -m 644 "$MODULE_DIR/systemd/ehot-control-boot.service" /etc/systemd/system/ehot-control-boot.service
install -m 644 "$MODULE_DIR/systemd/ehot-control-shutdown.service" /etc/systemd/system/ehot-control-shutdown.service

systemctl daemon-reload || true
systemctl enable ehot-control.service || true
systemctl enable ehot-control-boot.service || true
systemctl enable ehot-control-shutdown.service || true

# Local toggle & setup scripts
install -Dm755 "$SCRIPT_DIR/ehot-control-setup.sh" /usr/local/sbin/ehot-control-setup
install -Dm755 "$SCRIPT_DIR/ehot-control-toggle.sh" /usr/local/bin/ehot-control-toggle
install -Dm644 "$MODULE_DIR/config/ehot-control-toggle.desktop" /usr/share/applications/ehot-control-toggle.desktop

echo "[ehot-control] Модуль установлен. Настройте токен и Chat ID на целевом ноутбуке: sudo ehot-control-setup"
