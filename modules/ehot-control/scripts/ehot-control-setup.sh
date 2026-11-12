#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Control Secrets Setup Wizard
# Writes Telegram Bot Token and Chat ID ONLY locally to /etc/ehot-control/secrets.env (chmod 600).

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите от имени root: sudo ehot-control-setup" >&2
  exit 1
fi

echo "=== Настройка EHOT OS Control (Telegram уведомления) ==="
echo "Уведомления отправляются только для: YouTube, начало загрузок, включение и выключение."
echo "В любой момент мониторинг можно отключить локально командой: ehot-control-toggle"
echo

read -r -s -p "Введите TELEGRAM_BOT_TOKEN вашего существующего бота: " BOT_TOKEN
echo
read -r -p "Введите TELEGRAM_CHAT_ID владельца: " CHAT_ID
echo

BOT_TOKEN="${BOT_TOKEN//[[:space:]]/}"
CHAT_ID="${CHAT_ID//[[:space:]]/}"

if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
  echo "Ошибка: токен или Chat ID не могут быть пустыми." >&2
  exit 1
fi

install -d -m 750 -o root -g ehotcontrol /etc/ehot-control
umask 077
cat > /etc/ehot-control/secrets.env <<EOF
# Managed locally by ehot-control-setup (NEVER commit or pack into ISO)
TELEGRAM_BOT_TOKEN=${BOT_TOKEN}
TELEGRAM_CHAT_ID=${CHAT_ID}
EOF
unset BOT_TOKEN CHAT_ID

chown ehotcontrol:ehotcontrol /etc/ehot-control/secrets.env
chmod 600 /etc/ehot-control/secrets.env

systemctl enable --now ehot-control.service
systemctl enable ehot-control-boot.service
systemctl enable ehot-control-shutdown.service

echo "Проверка отправки тестового уведомления..."
if sudo -u ehotcontrol /usr/local/bin/ehot-control-cli test; then
  echo "Настройка EHOT OS Control завершена успешно."
else
  echo "Не удалось отправить тестовое сообщение (проверьте сеть, токен и Chat ID)." >&2
  exit 1
fi
