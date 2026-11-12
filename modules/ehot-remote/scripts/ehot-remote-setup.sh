#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Remote Interactive Setup Wizard
# Configures unattended access password locally (never stored in ISO/repo),
# connection notifications, and optional AnyDesk ID whitelist.

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите мастер настройки от root: sudo ehot-remote-setup" >&2
  exit 1
fi

if ! command -v anydesk >/dev/null 2>&1; then
  echo "Ошибка: AnyDesk не установлен." >&2
  exit 1
fi

echo "=== Настройка удалённого доступа EHOT OS (AnyDesk) ==="
echo "Доступ предоставляется только с согласия владельца ноутбука."
echo

# Ensure service is running to fetch ID and apply password
systemctl enable anydesk.service
systemctl start anydesk.service || true
sleep 2

ANYDESK_ID="$(anydesk --get-id 2>/dev/null || echo 'будет присвоен после запуска сети')"
echo "Текущий AnyDesk ID этого ноутбука: $ANYDESK_ID"
echo

read -r -p "Включить постоянный удалённый доступ по паролю? [y/N]: " CONFIRM_ENABLE
if [[ ! "${CONFIRM_ENABLE,,}" =~ ^(y|yes|д|да)$ ]]; then
  echo "Постоянный доступ не включён. При необходимости запустите: sudo ehot-remote-setup"
  exit 0
fi

while true; do
  read -r -s -p "Введите надёжный пароль постоянного доступа (мин. 8 символов): " PASS1
  echo
  read -r -s -p "Повторите пароль: " PASS2
  echo
  if [[ "$PASS1" != "$PASS2" ]]; then
    echo "Пароли не совпадают. Попробуйте снова."
    continue
  fi
  if (( ${#PASS1} < 8 )); then
    echo "Пароль слишком короткий (минимум 8 символов)."
    continue
  fi
  break
done

# Pass password via stdin directly to AnyDesk daemon without writing plaintext to repo/logs
printf '%s\n' "$PASS1" | anydesk --set-password
unset PASS1 PASS2

# Ensure interactive notification and unattended flags in /etc/anydesk/system.conf
mkdir -p /etc/anydesk
touch /etc/anydesk/system.conf
sed -i '/^ad\.security\.interactive_access=/d;/^ad\.features\.unattended=/d;/^ad\.ui\.show_tray_icon=/d' /etc/anydesk/system.conf
cat >> /etc/anydesk/system.conf <<'EOF'
ad.security.interactive_access=1
ad.features.unattended=true
ad.ui.show_tray_icon=true
EOF

read -r -p "Ограничить подключения только к доверенному AnyDesk ID (необязательно, Enter — пропустить): " TRUSTED_ID
TRUSTED_ID="${TRUSTED_ID//[[:space:]]/}"
if [[ -n "$TRUSTED_ID" ]]; then
  sed -i '/^ad\.security\.acl_enabled=/d;/^ad\.security\.acl_list=/d' /etc/anydesk/system.conf
  printf 'ad.security.acl_enabled=true\nad.security.acl_list=%s:true;\n' "$TRUSTED_ID" >> /etc/anydesk/system.conf
  echo "Разрешены подключения только с AnyDesk ID: $TRUSTED_ID"
fi

anydesk --restart-service 2>/dev/null || systemctl restart anydesk.service

echo
echo "Готово! AnyDesk ID: $(anydesk --get-id 2>/dev/null || echo "$ANYDESK_ID")"
echo "Локально отключить или снова включить удалённый доступ можно через меню или команду: ehot-remote-toggle"
