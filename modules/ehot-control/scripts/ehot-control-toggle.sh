#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Control Local Privacy Toggle
# Allows pausing or resuming monitoring locally at any time.

PAUSE_FLAG="/etc/ehot-control/paused"

notify_user() {
  local title="$1"
  local body="$2"
  if command -v notify-send >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    notify-send -i dialog-information "$title" "$body" || true
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

if [[ -f "$PAUSE_FLAG" ]]; then
  run_priv rm -f "$PAUSE_FLAG"
  run_priv systemctl restart ehot-control.service || true
  notify_user "EHOT OS Control" "Мониторинг уведомлений (4 события) ВКЛЮЧЁН."
else
  run_priv touch "$PAUSE_FLAG"
  run_priv chmod 644 "$PAUSE_FLAG"
  notify_user "EHOT OS Control" "Мониторинг уведомлений ПОСТАВЛЕН НА ПАУЗУ локально."
fi
