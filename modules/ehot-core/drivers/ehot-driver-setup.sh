#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Automatic Hardware & Driver Setup
# Runs on target installed hardware (or first boot with internet) to detect and
# install official drivers for NVIDIA GPU, Wi-Fi, Bluetooth, and Audio safely.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${EHOT_DRIVER_LOG:-/var/log/ehot-driver-setup.log}"
DRY_RUN="${DRY_RUN:-0}"

log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local msg="[$ts] [ehot-driver-setup] $*"
  echo "$msg"
  if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ $EUID -eq 0 ]]; then
    echo "$msg" >> "$LOG_FILE" || true
  fi
}

if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" != "1" ]]; then
  echo "Ошибка: запустите скрипт от имени root (sudo $0)" >&2
  exit 1
fi

log "Начинается диагностика оборудования EHOT OS..."

if [[ "$DRY_RUN" == "1" ]]; then
  log "Режим DRY_RUN=1: изменения в системе не выполняются."
  python3 "$SCRIPT_DIR/gpu_detect.py" --json
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# 1. Base firmware & peripheral support (official Mint/Ubuntu repos only)
log "Проверка и установка базовых прошивок (Wi-Fi, Bluetooth, звук SOF/PipeWire)..."
apt-get update -qq || log "Предупреждение: не удалось обновить индексы APT (возможно нет сети)."
apt-get install -y --no-install-recommends \
  linux-firmware \
  firmware-sof-signed \
  ubuntu-drivers-common \
  pciutils \
  usbutils \
  rfkill \
  bluez \
  blueman \
  pipewire \
  pipewire-pulse \
  wireplumber || log "Предупреждение: часть пакетов прошивок недоступна офлайн."

# Unblock soft-blocked Wi-Fi/BT radios if hardware allows
if command -v rfkill >/dev/null 2>&1; then
  rfkill unblock wifi || true
  rfkill unblock bluetooth || true
fi

# 2. Check non-GPU hardware drivers via official ubuntu-drivers (e.g., Broadcom Wi-Fi)
if command -v ubuntu-drivers >/dev/null 2>&1; then
  log "Проверка доступных официальных драйверов периферии (Wi-Fi и др.)..."
  mapfile -t non_gpu_drivers < <(
    ubuntu-drivers list 2>/dev/null \
      | grep -Ev '^nvidia-' \
      | grep -E '^(bcmwl-kernel-source|broadcom-sta-dkms|rtl|r8168|backport)' || true
  )
  if (( ${#non_gpu_drivers[@]} > 0 )); then
    log "Найдены официальные драйверы периферии: ${non_gpu_drivers[*]}"
    apt-get install -y "${non_gpu_drivers[@]}" || log "Предупреждение: не удалось установить драйверы периферии."
  else
    log "Дополнительные проприетарные драйверы периферии не требуются (используются модули ядра)."
  fi
fi

# 3. Safe GPU detection & NVIDIA selection
PLAN_JSON="$(python3 "$SCRIPT_DIR/gpu_detect.py" --json)"
log "План GPU: $PLAN_JSON"

ACTION="$(printf '%s' "$PLAN_JSON" | jq -r '.recommended_action')"
PKG="$(printf '%s' "$PLAN_JSON" | jq -r '.recommended_package // empty')"
PRIME_MODE="$(printf '%s' "$PLAN_JSON" | jq -r '.prime_mode // empty')"

if [[ "$ACTION" == "install_official_nvidia" ]] && [[ -n "$PKG" ]]; then
  log "Установка официального драйвера NVIDIA: $PKG (с сохранением fallback на nouveau при сбое)."
  if apt-get install -y "$PKG" nvidia-settings; then
    if [[ -n "$PRIME_MODE" ]] && command -v prime-select >/dev/null 2>&1; then
      log "Включение режима NVIDIA Prime: $PRIME_MODE"
      prime-select "$PRIME_MODE" || true
    fi
    # Ensure DRM KMS is enabled for tear-free X11/Vulkan
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/ehot-nvidia-drm.conf <<'EOF'
# EHOT OS: Enable DRM modesetting for modern NVIDIA drivers
options nvidia-drm modeset=1
EOF
    update-initramfs -u || true
    log "Драйвер $PKG успешно установлен."
  else
    log "ОШИБКА установки $PKG — выполняется откат для сохранения работоспособного графического режима."
    apt-get remove -y "$PKG" || true
  fi
else
  log "Установка проприетарного NVIDIA не выполняется (действие: $ACTION). Сохраняется штатный графический режим."
fi

log "Настройка драйверов завершена."
