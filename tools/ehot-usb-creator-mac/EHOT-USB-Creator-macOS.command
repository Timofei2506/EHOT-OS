#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Safe USB Flasher for macOS (Bash 3.2+ / BSD tools compatible)
# - Combines .iso.part.* files automatically if needed
# - Verifies SHA-256 via macOS built-in `shasum -a 256`
# - Filters strictly to external, physical, non-virtual USB disks (`diskutil list external physical`)
# - Blocks internal Mac SSD (disk0), virtual DMG images, and undersized drives
# - Unmounts via `diskutil unmountDisk`, writes via raw `/dev/rdiskN` (`bs=4m`), verifies first 8 MiB, ejects

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ISO_NAME="ehot-os-22.3-xfce-amd64.iso"

pause_on_command_exit() {
  local rc=$?
  if [[ -t 0 ]]; then
    echo
    if [[ $rc -ne 0 ]]; then
      echo "[Завершено с кодом $rc]"
    fi
    read -r -p "Нажмите Enter, чтобы закрыть окно..." _ || true
  fi
}

parse_diskutil_field() {
  local info_text="$1"
  local field_name="$2"
  printf '%s\n' "$info_text" | awk -F':' -v key="$field_name" '
    {
      k = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k == key) {
        sub(/^[^:]*:[[:space:]]*/, "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }
  '
}

extract_disk_bytes() {
  local size_field="$1"
  printf '%s\n' "$size_field" | sed -n 's/.*(\([0-9][0-9]*\) Bytes).*/\1/p' | head -n 1
}

validate_macos_disk_info() {
  local disk_id="$1"
  local info_text="$2"
  local min_bytes="${3:-4000000000}"

  if [[ "$disk_id" == "disk0" ]]; then
    echo "BLOCKED:disk0 (internal system disk)"
    return 1
  fi
  if ! printf '%s' "$disk_id" | grep -Eq '^disk[1-9][0-9]*$'; then
    echo "BLOCKED:invalid whole disk id '$disk_id'"
    return 1
  fi

  local whole internal virtual_flag location protocol media_name size_str size_bytes removable
  whole="$(parse_diskutil_field "$info_text" "Whole")"
  internal="$(parse_diskutil_field "$info_text" "Internal")"
  virtual_flag="$(parse_diskutil_field "$info_text" "Virtual")"
  location="$(parse_diskutil_field "$info_text" "Device Location")"
  protocol="$(parse_diskutil_field "$info_text" "Protocol")"
  removable="$(parse_diskutil_field "$info_text" "Removable Media")"
  media_name="$(parse_diskutil_field "$info_text" "Device / Media Name")"
  size_str="$(parse_diskutil_field "$info_text" "Disk Size")"
  size_bytes="$(extract_disk_bytes "$size_str")"

  if [[ "$whole" != "Yes" ]]; then
    echo "BLOCKED:not whole disk ($whole)"
    return 1
  fi
  if [[ "$internal" == "Yes" ]] || printf '%s' "$location" | grep -qi "Internal"; then
    echo "BLOCKED:internal drive ($location)"
    return 1
  fi
  if [[ "$virtual_flag" == "Yes" ]]; then
    echo "BLOCKED:virtual image ($virtual_flag)"
    return 1
  fi
  if ! printf '%s' "$location" | grep -qi "External"; then
    echo "BLOCKED:location is not External ($location)"
    return 1
  fi
  if ! printf '%s' "$protocol" | grep -qi "USB" && ! printf '%s' "$removable" | grep -qiE "Removable|Yes"; then
    echo "BLOCKED:not USB/removable (Protocol=$protocol, Removable=$removable)"
    return 1
  fi
  if [[ -z "$size_bytes" ]] || [[ "$size_bytes" -lt "$min_bytes" ]]; then
    echo "BLOCKED:disk too small (${size_bytes:-0} < $min_bytes)"
    return 1
  fi

  local short_size
  short_size="$(printf '%s' "$size_str" | sed 's/ (.*//')"
  printf 'OK|%s|%s|%s|%s\n' "$disk_id" "${media_name:-USB Disk}" "${protocol:-USB}" "${short_size:-unknown}"
  return 0
}

find_or_reassemble_iso() {
  local work_dir="$1"
  local candidate_iso="$work_dir/$DEFAULT_ISO_NAME"
  if [[ -f "$candidate_iso" ]]; then
    printf '%s\n' "$candidate_iso"
    return 0
  fi

  if [[ -f "$work_dir/${DEFAULT_ISO_NAME}.part.aa" ]]; then
    echo "[ehot-mac] Найдены многотомные части ${DEFAULT_ISO_NAME}.part.* в $work_dir" >&2
    if [[ -f "$work_dir/${DEFAULT_ISO_NAME}.parts.sha256" ]]; then
      echo "[ehot-mac] Проверка SHA-256 каждой части..." >&2
      (cd "$work_dir" && shasum -a 256 -c "${DEFAULT_ISO_NAME}.parts.sha256" >&2)
    fi
    echo "[ehot-mac] Склейка томов в $candidate_iso (займёт ~15-30 секунд)..." >&2
    cat "$work_dir/${DEFAULT_ISO_NAME}.part."* > "$candidate_iso"
    printf '%s\n' "$candidate_iso"
    return 0
  fi

  return 1
}

get_file_size_bytes() {
  local f="$1"
  if stat -f%z "$f" >/dev/null 2>&1; then
    stat -f%z "$f"
  else
    stat -c%s "$f"
  fi
}

main() {
  case "$(basename "$0")" in
    *.command)
      trap pause_on_command_exit EXIT
      ;;
  esac

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Ошибка: этот скрипт предназначен для запуска на macOS (текущая ОС: $(uname -s))." >&2
    exit 1
  fi

  local input_path="${1:-}"
  local work_dir="$SCRIPT_DIR"
  local iso_path=""

  if [[ -n "$input_path" ]]; then
    if [[ ! -f "$input_path" ]]; then
      echo "Ошибка: файл '$input_path' не найден." >&2
      exit 1
    fi
    work_dir="$(cd "$(dirname "$input_path")" && pwd)"
    case "$input_path" in
      *.iso.part.*)
        iso_path="$(find_or_reassemble_iso "$work_dir")"
        ;;
      *)
        iso_path="$work_dir/$(basename "$input_path")"
        ;;
    esac
  else
    if ! iso_path="$(find_or_reassemble_iso "$work_dir")"; then
      if [[ -d "$HOME/Downloads" ]] && iso_path="$(find_or_reassemble_iso "$HOME/Downloads")"; then
        work_dir="$HOME/Downloads"
      else
        echo "Не найден файл $DEFAULT_ISO_NAME или тома ${DEFAULT_ISO_NAME}.part.*." >&2
        echo "Положите этот скрипт в ту же папку, куда скачали файлы релиза, или укажите путь аргументом:" >&2
        echo "  bash \"$0\" ~/Downloads/$DEFAULT_ISO_NAME" >&2
        exit 1
      fi
    fi
  fi

  echo "=== EHOT OS USB Creator (macOS) ==="
  echo "Образ: $iso_path"

  local sha_file="${iso_path}.sha256"
  if [[ -f "$sha_file" ]]; then
    echo "[1/5] Проверка контрольной суммы SHA-256 образа..."
    (cd "$(dirname "$iso_path")" && shasum -a 256 -c "$(basename "$sha_file")")
  else
    echo "[1/5] Файл .sha256 рядом не найден — пропуск автопроверки (вы можете проверить хеш вручную)."
  fi

  local iso_bytes
  iso_bytes="$(get_file_size_bytes "$iso_path")"

  echo
  echo "[2/5] Поиск внешних физических USB-накопителей (внутренний диск Mac скрыт защитой)..."
  local raw_disks
  raw_disks="$(diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk[0-9]+/ {gsub("/dev/", "", $1); print $1}' || true)"

  local valid_lines=""
  local valid_count=0
  local d
  for d in $raw_disks; do
    local d_info res
    d_info="$(diskutil info "/dev/$d" 2>/dev/null || true)"
    if res="$(validate_macos_disk_info "$d" "$d_info" "$iso_bytes" 2>/dev/null)"; then
      valid_count=$((valid_count + 1))
      valid_lines="${valid_lines}${res}
"
    fi
  done

  if [[ "$valid_count" -eq 0 ]]; then
    echo "Подходящая внешняя USB-флешка (>= $((iso_bytes / 1048576)) МиБ) не найдена." >&2
    echo "Вставьте Kingston DataTraveler 64 ГБ в Mac и запустите скрипт снова." >&2
    exit 1
  fi

  echo "Доступные USB-накопители:"
  local idx=1
  while IFS='|' read -r status d_id d_name d_proto d_size; do
    [[ -z "$status" ]] && continue
    printf "  [%d] /dev/%s — %s (%s, %s)\n" "$idx" "$d_id" "$d_name" "$d_proto" "$d_size"
    idx=$((idx + 1))
  done <<EOF
$valid_lines
EOF

  echo
  local choice
  read -r -p "Введите номер флешки (1-$valid_count): " choice
  if ! printf '%s' "$choice" | grep -Eq '^[0-9]+$' || [[ "$choice" -lt 1 || "$choice" -gt "$valid_count" ]]; then
    echo "Неверный выбор. Отмена." >&2
    exit 1
  fi

  local chosen_line target_id target_name target_proto target_size
  chosen_line="$(printf '%s' "$valid_lines" | sed -n "${choice}p")"
  IFS='|' read -r _ target_id target_name target_proto target_size <<EOF
$chosen_line
EOF

  echo
  echo "ВНИМАНИЕ! ВСЕ ДАННЫЕ НА /dev/$target_id ($target_name, $target_proto, $target_size) БУДУТ БЕЗВОЗВРАТНО УДАЛЕНЫ!"
  local confirm
  read -r -p "Для подтверждения записи на /dev/$target_id введите YES: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "Отменено пользователем. Данные не изменены."
    exit 0
  fi

  echo
  echo "[3/5] Размонтирование томов на /dev/$target_id..."
  diskutil unmountDisk "/dev/$target_id"

  echo "[4/5] Запись образа в /dev/r$target_id (введите пароль пользователя Mac для sudo; наберите Ctrl+T для просмотра прогресса)..."
  sudo dd if="$iso_path" of="/dev/r$target_id" bs=4m
  sync

  echo "[5/5] Контрольная проверка первых 8 МиБ и безопасное извлечение..."
  local expected_head actual_head
  expected_head="$(dd if="$iso_path" bs=1m count=8 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  actual_head="$(sudo dd if="/dev/r$target_id" bs=1m count=8 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  if [[ "$expected_head" != "$actual_head" ]]; then
    echo "ОШИБКА ВЕРИФИКАЦИИ: записанные загрузочные сектора не совпадают с ISO!" >&2
    echo "  Ожидалось:   $expected_head" >&2
    echo "  Прочитано:   $actual_head" >&2
    exit 2
  fi

  diskutil eject "/dev/$target_id"
  echo
  echo "ГОТОВО! Контрольная сумма 8 МиБ совпала ($actual_head), флешка /dev/$target_id безопасно извлечена."
  echo "Вставьте Kingston DataTraveler в выключенный Lenovo и выберите загрузку с USB (F12 / Fn+F12 / кнопка Novo)."
}

if [[ "${1:-}" == "--self-test-parse" ]]; then
  shift
  validate_macos_disk_info "$@"
else
  main "$@"
fi
