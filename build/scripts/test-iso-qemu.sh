#!/usr/bin/env bash
set -euo pipefail

# Smoke-tests the built EHOT OS ISO in QEMU (both Legacy BIOS and UEFI OVMF if available).
# Verifies ISO boot catalog, squashfs/kernel presence, and live screen output via QEMU monitor.

ISO_PATH="${1:-}"
if [[ -z "$ISO_PATH" || ! -f "$ISO_PATH" ]]; then
  echo "Использование: $0 /путь/к/ehot-os-22.3-xfce-amd64.iso" >&2
  exit 1
fi

for cmd in qemu-system-x86_64 qemu-img xorriso python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Ошибка: утилита '$cmd' не установлена." >&2
    exit 1
  fi
done

echo "[qemu-test] Проверка структуры, El-Torito и ключевых файлов ISO..."
xorriso -indev "$ISO_PATH" -report_el_torito plain 2>&1 | head -n 30
ISO_CASPER_LS="$(xorriso -indev "$ISO_PATH" -ls /casper 2>&1)"
echo "$ISO_CASPER_LS"
for req in filesystem.squashfs vmlinuz initrd.lz; do
  if ! grep -q "$req" <<<"$ISO_CASPER_LS"; then
    echo "ОШИБКА: в /casper отсутствует обязательный файл $req" >&2
    exit 1
  fi
done

MEM_TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
QEMU_RAM_MB=2048
if (( MEM_TOTAL_MB < 2500 )); then
  QEMU_RAM_MB=1280
fi

run_qemu_boot_check() {
  local mode="$1"
  local log_file mon_sock ppm_menu ppm_boot dummy_disk
  log_file="$(mktemp)"
  mon_sock="$(mktemp -u /tmp/ehot-qmon-XXXXXX.sock)"
  ppm_menu="$(mktemp --suffix=.ppm)"
  ppm_boot="$(mktemp --suffix=.ppm)"
  dummy_disk="$(mktemp --suffix=.qcow2)"
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
      rm -f "$log_file" "$ppm_menu" "$ppm_boot" "$dummy_disk"
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

  echo "[qemu-test] Запуск smoke-теста загрузки ($mode, RAM=${QEMU_RAM_MB}M)..."
  qemu-img create -f qcow2 "$dummy_disk" 20G >/dev/null

  qemu-system-x86_64 \
    "${accel_args[@]}" \
    -m "$QEMU_RAM_MB" \
    -smp 2 \
    -display none \
    -vga std \
    -no-reboot \
    "${extra_args[@]}" \
    -cdrom "$ISO_PATH" \
    -drive "file=$dummy_disk,if=virtio,format=qcow2" \
    -boot d \
    -serial "file:$log_file" \
    -monitor "unix:$mon_sock,server,nowait" >/dev/null 2>&1 &
  local qpid=$!

  cleanup_qemu_instance() {
    kill "$qpid" 2>/dev/null || true
    wait "$qpid" 2>/dev/null || true
    rm -f "$mon_sock" "$log_file" "$ppm_menu" "$ppm_boot" "$dummy_disk"
  }

  local wait_sec=10
  if [[ ! -w /dev/kvm ]]; then
    wait_sec=18
  fi
  sleep "$wait_sec"

  if ! kill -0 "$qpid" 2>/dev/null; then
    echo "ОШИБКА: QEMU завершился преждевременно в режиме $mode!" >&2
    cleanup_qemu_instance
    return 1
  fi

  python3 - "$mon_sock" "$ppm_menu" "$ppm_boot" <<'PY'
import socket, sys, time

sock_path, ppm_menu, ppm_boot = sys.argv[1], sys.argv[2], sys.argv[3]

def hmp(cmd):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect(sock_path)
        s.recv(4096)
        s.sendall((cmd + "\n").encode("ascii"))
        time.sleep(0.4)
        try:
            s.recv(4096)
        except Exception:
            pass

def ppm_nonblack_pct(path):
    with open(path, "rb") as f:
        data = f.read()
    # Skip P6 header (3 whitespace-separated tokens after magic P6 + 1 whitespace byte)
    parts = data.split(None, 4)
    if len(parts) < 5 or parts[0] != b"P6":
        return 0.0
    pixels = parts[4]
    if not pixels:
        return 0.0
    nonblack = sum(1 for i in range(0, len(pixels) - 2, 3) if pixels[i] or pixels[i+1] or pixels[i+2])
    total = max(1, len(pixels) // 3)
    return (nonblack / total) * 100.0

hmp(f"screendump {ppm_menu}")
menu_pct = ppm_nonblack_pct(ppm_menu)
hmp("sendkey ret")
time.sleep(15)
hmp(f"screendump {ppm_boot}")
boot_pct = ppm_nonblack_pct(ppm_boot)
print(f"[qemu-test] Screen non-black pixels: menu={menu_pct:.2f}%, post-Enter={boot_pct:.2f}%")
if menu_pct < 0.1 and boot_pct < 0.1:
    sys.stderr.write("ОШИБКА: экран QEMU полностью чёрный на обоих этапах загрузки!\n")
    sys.exit(2)
PY

  local py_rc=$?
  if [[ -n "${EHOT_QEMU_SAVE_DIR:-}" ]]; then
    mkdir -p "$EHOT_QEMU_SAVE_DIR"
    cp -f "$ppm_menu" "$EHOT_QEMU_SAVE_DIR/${mode}_menu.ppm" 2>/dev/null || true
    cp -f "$ppm_boot" "$EHOT_QEMU_SAVE_DIR/${mode}_boot.ppm" 2>/dev/null || true
  fi
  cleanup_qemu_instance
  return "$py_rc"
}

run_qemu_boot_check "bios"
run_qemu_boot_check "uefi"
echo "[qemu-test] Проверка BIOS и UEFI завершена успешно."
