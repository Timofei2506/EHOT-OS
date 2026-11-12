#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Remote Local Toggle
# Allows the laptop owner to turn AnyDesk service off or on locally at any time.

notify_user() {
  local title="$1"
  local body="$2"
  if command -v notify-send >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    notify-send -i preferences-desktop-remote-desktop "$title" "$body" || true
  fi
  echo "$title: $body"
}

run_priv() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif command -v pkexec >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    pkexec "$@"
  else
    sudo "$@"
  fi
}

if systemctl is-active --quiet anydesk.service; then
  run_priv systemctl disable --now anydesk.service
  pkill -x anydesk 2>/dev/null || true
  notify_user "EHOT OS Remote" "Удалённый доступ AnyDesk ОТКЛЮЧЁН локально."
else
  run_priv systemctl enable --now anydesk.service
  notify_user "EHOT OS Remote" "Удалённый доступ AnyDesk ВКЛЮЧЁН (ID: $(anydesk --get-id 2>/dev/null || echo 'см. AnyDesk'))."
fi
