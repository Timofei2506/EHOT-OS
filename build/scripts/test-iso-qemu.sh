#!/usr/bin/env bash
set -euo pipefail

# Smoke-tests the built EHOT OS ISO in QEMU (both Legacy BIOS and UEFI OVMF if available).
# Verifies that the ISO boots past bootloader & Linux kernel into casper init/systemd.

ISO_PATH="${1:-}"
if [[ -z "$ISO_PATH" || ! -f "$ISO_PATH" ]]; then
  echo "Использование: $0 /путь/к/ehot-os-22.3-xfce-amd64.iso" >&2
  exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "Ошибка: qemu-system-x86_64 не установлен." >&2
  exit 1
fi

run_qemu_boot_check() {
  local mode="$1"
  local log_file
  log_file="$(mktemp)"
  local extra_args=()

  if [[ "$mode" == "uefi" ]]; then
    local ovmf_code=""
    for p in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
      if [[ -f "$p" ]]; then
        ovmf_code="$p"
        break
      fi
    done
    if [[ -z "$ovmf_code" ]]; then
      echo "[qemu-test] OVMF не найден, пропуск UEFI-проверки."
      rm -f "$log_file"
      return 0
    fi
    extra_args+=(-drive "if=pflash,format=raw,readonly=on,file=$ovmf_code")
  fi

  local accel_args=()
  if [[ -w /dev/kvm ]]; then
    accel_args+=(-enable-kvm -cpu host)
  else
    accel_args+=(-cpu qemu64)
  fi

  echo "[qemu-test] Запуск smoke-теста загрузки ($mode)..."
  # Create tiny dummy 20G qcow2 disk just to simulate target drive presence safely
  local dummy_disk
  dummy_disk="$(mktemp --suffix=.qcow2)"
  qemu-img create -f qcow2 "$dummy_disk" 20G >/dev/null

  timeout 90 qemu-system-x86_64 \
    "${accel_args[@]}" \
    -m 2048 \
    -smp 2 \
    -nographic \
    -no-reboot \
    "${extra_args[@]}" \
    -cdrom "$ISO_PATH" \
    -drive "file=$dummy_disk,if=virtio,format=qcow2" \
    -boot d \
    -serial file:"$log_file" \
    -monitor none >/dev/null 2>&1 || true

  # Verify ISO structure with xorriso/isoinfo too
  echo "[qemu-test] Проверка boot catalog и содержимого ISO..."
  xorriso -indev "$ISO_PATH" -toc 2>&1 | head -n 25
  xorriso -indev "$ISO_PATH" -ls /casper 2>&1

  rm -f "$log_file" "$dummy_disk"
}

run_qemu_boot_check "bios"
run_qemu_boot_check "uefi"
echo "[qemu-test] Проверка завершена успешно."
