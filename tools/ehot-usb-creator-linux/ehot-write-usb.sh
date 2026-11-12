#!/usr/bin/env bash
set -euo pipefail

# Safe USB Flasher for Linux (`ehot-write-usb.sh`)
# Strictly verifies target device is USB & removable, verifies SHA-256, and requires explicit confirmation.

ISO_PATH="${1:-}"
TARGET_DEV="${2:-}"

if [[ -z "$ISO_PATH" || ! -f "$ISO_PATH" ]]; then
  echo "Использование: sudo $0 /путь/к/ehot-os-22.3-xfce-amd64.iso [/dev/sdX]" >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите с правами root (sudo)." >&2
  exit 1
fi

if [[ -f "${ISO_PATH}.sha256" ]]; then
  echo "[usb-write] Проверка SHA-256 образа..."
  (cd "$(dirname "$ISO_PATH")" && sha256sum -c "$(basename "${ISO_PATH}.sha256")")
fi

echo "Доступные съёмные USB-накопители:"
lsblk -d -o NAME,PATH,SIZE,TRAN,RM,MODEL,SERIAL | grep -E 'NAME|usb' || true

if [[ -z "$TARGET_DEV" ]]; then
  read -r -p "Введите путь к USB-флешке (например /dev/sdb): " TARGET_DEV
fi

if [[ ! -b "$TARGET_DEV" ]]; then
  echo "Ошибка: $TARGET_DEV не является блочным устройством." >&2
  exit 1
fi

TRAN="$(lsblk -no TRAN "$TARGET_DEV" | head -n1 | tr -d '[:space:]')"
RM="$(lsblk -no RM "$TARGET_DEV" | head -n1 | tr -d '[:space:]')"
MODEL="$(lsblk -no MODEL "$TARGET_DEV" | head -n1)"
SIZE="$(lsblk -no SIZE "$TARGET_DEV" | head -n1)"

if [[ "$TRAN" != "usb" || "$RM" != "1" ]]; then
  echo "ЗАБЛОКИРОВАНО: $TARGET_DEV не является съёмным USB-носителем (TRAN=$TRAN, RM=$RM)." >&2
  exit 2
fi

echo
echo "ВНИМАНИЕ! ВСЕ ДАННЫЕ НА $TARGET_DEV ($MODEL, $SIZE) БУДУТ УДАЛЕНЫ!"
read -r -p "Для продолжения введите YES: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Отменено."
  exit 0
fi

# Unmount any mounted partitions on the target USB stick
for part in "${TARGET_DEV}"*; do
  if mountpoint -q "$part" 2>/dev/null || findmnt "$part" >/dev/null 2>&1; then
    umount "$part" || true
  fi
done

dd if="$ISO_PATH" of="$TARGET_DEV" bs=4M status=progress conv=fsync oflag=direct
sync
echo "Готово! Флешка $TARGET_DEV записана."
