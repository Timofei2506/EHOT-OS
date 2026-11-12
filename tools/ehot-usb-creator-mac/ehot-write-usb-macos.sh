#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Safe USB Flasher for macOS (Bash 3.2+ / BSD tools compatible)
# Supports:
#   - Auto-locating .iso or .iso.part.* across current folder, parent folder, and ~/Downloads/*
#   - Optional automatic download from public GitHub Release v1.0.0 via curl + unzip
#   - SHA-256 verification via macOS built-in `shasum -a 256`
#   - Mode [1]: Full hybrid mode (UEFI + Legacy BIOS via sudo dd -> /dev/rdiskN)
#   - Mode [2]: No-sudo UEFI FAT32 mode (diskutil eraseDisk FAT32 + bsdtar extract)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ISO_NAME="ehot-os-22.3-xfce-amd64.iso"
RELEASE_BASE_URL="${EHOT_RELEASE_URL:-https://github.com/Timofei2506/EHOT-OS/releases/download/v1.0.0}"

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

verify_extracted_uefi_tree() {
  local mount_dir="$1"
  if [[ -z "$mount_dir" || ! -d "$mount_dir" ]]; then
    echo "ОШИБКА: каталог смонтированной флешки '$mount_dir' не найден." >&2
    return 1
  fi

  local bootx64=""
  bootx64="$(find "$mount_dir" -maxdepth 3 -iname 'bootx64.efi' 2>/dev/null | head -n 1 || true)"
  if [[ -z "$bootx64" ]]; then
    echo "ОШИБКА: на флешке не найден загрузчик EFI/boot/bootx64.efi." >&2
    return 1
  fi

  local rel
  for rel in \
    "boot/grub/grub.cfg" \
    "casper/vmlinuz" \
    "casper/initrd.lz" \
    "casper/filesystem.squashfs" \
    ".disk/casper-uuid-generic"; do
    if [[ ! -f "$mount_dir/$rel" ]]; then
      echo "ОШИБКА: на флешке отсутствует обязательный файл $rel." >&2
      return 1
    fi
  done

  local sq_bytes
  sq_bytes="$(get_file_size_bytes "$mount_dir/casper/filesystem.squashfs")"
  if [[ -z "$sq_bytes" || "$sq_bytes" -lt 500000000 ]]; then
    echo "ОШИБКА: casper/filesystem.squashfs скопирован не полностью ($sq_bytes байт)." >&2
    return 1
  fi

  return 0
}

get_file_size_bytes() {
  local f="$1"
  if stat -f%z "$f" >/dev/null 2>&1; then
    stat -f%z "$f"
  else
    stat -c%s "$f"
  fi
}

sha256_of_file() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    sha256sum "$f" | awk '{print $1}'
  fi
}

find_named_file_in_roots() {
  local target_name="$1"
  shift
  local root found
  for root in "$@"; do
    [[ -d "$root" ]] || continue
    found="$(find "$root" -maxdepth 3 -type f -name "$target_name" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
  done
  return 1
}

find_or_reassemble_iso() {
  local primary_dir="$1"
  local parent_dir
  parent_dir="$(cd "$primary_dir/.." 2>/dev/null && pwd || printf '%s' "$primary_dir")"

  local search_roots=("$primary_dir" "$parent_dir")
  if [[ -d "$HOME/Downloads" && "$HOME/Downloads" != "$primary_dir" && "$HOME/Downloads" != "$parent_dir" ]]; then
    search_roots+=("$HOME/Downloads")
  fi

  local existing_iso=""
  existing_iso="$(find_named_file_in_roots "$DEFAULT_ISO_NAME" "${search_roots[@]}" || true)"
  if [[ -n "$existing_iso" && -f "$existing_iso" ]]; then
    printf '%s\n' "$existing_iso"
    return 0
  fi

  local parts_sha=""
  parts_sha="$(find_named_file_in_roots "${DEFAULT_ISO_NAME}.parts.sha256" "${search_roots[@]}" || true)"

  local part_aa=""
  part_aa="$(find_named_file_in_roots "${DEFAULT_ISO_NAME}.part.aa" "${search_roots[@]}" || true)"
  if [[ -z "$part_aa" ]]; then
    return 1
  fi

  local out_dir="$primary_dir"
  local target_iso="$out_dir/$DEFAULT_ISO_NAME"
  local part_paths=()

  if [[ -n "$parts_sha" && -f "$parts_sha" ]]; then
    echo "[ehot-mac] Найдены части образа. Проверка SHA-256 каждой части..." >&2
    local expected_hash part_filename found_part actual_hash
    while read -r expected_hash part_filename; do
      [[ -z "$expected_hash" || -z "$part_filename" ]] && continue
      part_filename="${part_filename#\*}"
      found_part="$(find_named_file_in_roots "$part_filename" "${search_roots[@]}" || true)"
      if [[ -z "$found_part" ]]; then
        echo "ОШИБКА: не найдена часть образа '$part_filename' (скачайте и распакуйте оба ZIP-архива из релиза)." >&2
        return 2
      fi
      actual_hash="$(sha256_of_file "$found_part")"
      if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "ОШИБКА SHA-256 для '$found_part': ожидалось $expected_hash, получено $actual_hash" >&2
        return 2
      fi
      echo "  [OK] $part_filename" >&2
      part_paths+=("$found_part")
    done < "$parts_sha"
  else
    local suffix p
    for suffix in aa ab ac ad; do
      p="$(find_named_file_in_roots "${DEFAULT_ISO_NAME}.part.${suffix}" "${search_roots[@]}" || true)"
      [[ -n "$p" ]] && part_paths+=("$p")
    done
  fi

  if [[ "${#part_paths[@]}" -eq 0 ]]; then
    return 1
  fi

  echo "[ehot-mac] Склейка ${#part_paths[@]} частей в $target_iso (займёт ~15–30 секунд)..." >&2
  cat "${part_paths[@]}" > "$target_iso"

  local iso_sha=""
  iso_sha="$(find_named_file_in_roots "${DEFAULT_ISO_NAME}.sha256" "${search_roots[@]}" || true)"
  if [[ -n "$iso_sha" && -f "$iso_sha" && ! -f "${target_iso}.sha256" ]]; then
    cp "$iso_sha" "${target_iso}.sha256"
  fi

  printf '%s\n' "$target_iso"
  return 0
}

download_release_zips_to_dir() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  local z1="EHOT-OS-v1.0.0-Part1.zip"
  local z2="EHOT-OS-v1.0.0-Part2-and-Tools.zip"

  echo "[ehot-mac] Скачивание $z1 (~1.8 ГБ) в $dest_dir..."
  curl -fL --retry 3 --progress-bar -o "$dest_dir/$z1" "$RELEASE_BASE_URL/$z1"
  echo "[ehot-mac] Распаковка $z1..."
  unzip -oq "$dest_dir/$z1" -d "$dest_dir"
  rm -f "$dest_dir/$z1"

  echo "[ehot-mac] Скачивание $z2 (~1.85 ГБ) в $dest_dir..."
  curl -fL --retry 3 --progress-bar -o "$dest_dir/$z2" "$RELEASE_BASE_URL/$z2"
  echo "[ehot-mac] Распаковка $z2..."
  unzip -oq "$dest_dir/$z2" -d "$dest_dir"
  rm -f "$dest_dir/$z2"
}

flash_raw_with_sudo() {
  local iso_path="$1"
  local target_id="$2"

  echo
  echo "[3/5] Размонтирование томов на /dev/$target_id..."
  diskutil unmountDisk "/dev/$target_id"

  echo "[4/5] Запись образа в /dev/r$target_id (введите пароль администратора Mac для sudo; Ctrl+T показывает прогресс)..."
  echo "Подсказка: если у вас свой Mac без пароля (пустой пароль), macOS sudo его не примет —"
  echo "временно задайте простой пароль в Системных настройках или перезапустите скрипт в режиме [2] (Без пароля)."
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
}

flash_fat32_uefi_no_sudo() {
  local iso_path="$1"
  local target_id="$2"

  echo
  echo "[3/5] Форматирование /dev/$target_id в FAT32 (MBR) без sudo..."
  local erase_ok=0
  if diskutil eraseDisk FAT32 EHOTUSB MBRFormat "/dev/$target_id"; then
    erase_ok=1
  else
    echo "Предупреждение: diskutil eraseDisk не выполнен без прав администратора." >&2
  fi

  sleep 2
  local part_id="" vol_mount="" part_fs="" candidate_slice
  for candidate_slice in "${target_id}s1" "${target_id}s2"; do
    local p_info
    p_info="$(diskutil info "/dev/$candidate_slice" 2>/dev/null || true)"
    [[ -z "$p_info" ]] && continue
    part_id="$candidate_slice"
    vol_mount="$(parse_diskutil_field "$p_info" "Mount Point")"
    part_fs="$(parse_diskutil_field "$p_info" "File System Personality")"
    if [[ -z "$vol_mount" ]]; then
      diskutil mount "/dev/$part_id" >/dev/null 2>&1 || true
      p_info="$(diskutil info "/dev/$part_id" 2>/dev/null || true)"
      vol_mount="$(parse_diskutil_field "$p_info" "Mount Point")"
      part_fs="$(parse_diskutil_field "$p_info" "File System Personality")"
    fi
    [[ -n "$vol_mount" ]] && break
  done

  if [[ "$erase_ok" -eq 0 ]]; then
    if [[ -n "$vol_mount" ]] && printf '%s' "$part_fs" | grep -qiE "FAT32|MS-DOS"; then
      echo "Найдена существующая файловая система $part_fs ($vol_mount). Очистка содержимого без форматирования..."
      find "$vol_mount" -mindepth 1 -maxdepth 1 ! -name '.Trashes' ! -name '.Spotlight-V100' ! -name '.fseventsd' -exec rm -rf {} + 2>/dev/null || true
    else
      echo "ОШИБКА: macOS требует права администратора для смены файловой системы ($part_fs -> FAT32)." >&2
      echo "Варианты:" >&2
      echo "  1) Если это ваш Mac, но вход без пароля — временно поставьте пароль в Системных настройках (sudo не принимает пустой пароль)." >&2
      echo "  2) Отформатируйте эту флешку в FAT32 на любом Windows/Android/Linux устройстве и запустите этот режим снова." >&2
      exit 3
    fi
  fi

  if [[ -z "$vol_mount" || ! -d "$vol_mount" ]]; then
    echo "ОШИБКА: не удалось смонтировать FAT32-раздел на /dev/$target_id." >&2
    exit 3
  fi

  echo "[4/5] Распаковка EHOT OS ISO на $vol_mount (займёт 2–6 минут, без sudo)..."
  local tar_rc=0
  tar --no-same-owner --no-same-permissions -xf "$iso_path" \
    --exclude 'ubuntu' --exclude './ubuntu' \
    --exclude 'dists' --exclude './dists' \
    -C "$vol_mount" || tar_rc=$?
  if [[ "$tar_rc" -ne 0 ]]; then
    echo "[ehot-mac] tar завершился с кодом $tar_rc (обычно из-за симлинков на FAT32) — проверяем целостность загрузочных файлов..."
  fi
  sync

  echo "[5/5] Проверка загрузочных файлов UEFI и безопасное извлечение..."
  verify_extracted_uefi_tree "$vol_mount"
  diskutil eject "/dev/$target_id"
  echo
  echo "ГОТОВО (UEFI FAT32 без пароля)! Загрузочные файлы проверены, флешка /dev/$target_id безопасно извлечена."
  echo "ВАЖНО при загрузке на Lenovo: в BIOS/UEFI должен быть выбран режим UEFI (и выключен Secure Boot)."
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
    local rc=0
    iso_path="$(find_or_reassemble_iso "$work_dir")" || rc=$?
    if [[ $rc -ne 0 || -z "$iso_path" ]]; then
      if [[ $rc -eq 2 ]]; then
        exit 2
      fi
      echo "Образ $DEFAULT_ISO_NAME или части .part.* локально не найдены."
      local dl_ans
      read -r -p "Скачать автоматически из публичного GitHub Release v1.0.0 (~3.6 ГБ)? [y/N]: " dl_ans
      case "$dl_ans" in
        y|Y|yes|YES|д|Д|да|ДА)
          local dl_dir="$HOME/Downloads/EHOT-OS-v1.0.0"
          download_release_zips_to_dir "$dl_dir"
          iso_path="$(find_or_reassemble_iso "$dl_dir")"
          ;;
        *)
          echo "Скачайте EHOT-OS-v1.0.0-Part1.zip и EHOT-OS-v1.0.0-Part2-and-Tools.zip в Загрузки, распакуйте и запустите скрипт снова." >&2
          exit 1
          ;;
      esac
    fi
  fi

  echo "=== EHOT OS USB Creator (macOS) ==="
  echo "Образ: $iso_path"

  local sha_file="${iso_path}.sha256"
  if [[ -f "$sha_file" ]]; then
    echo "[1/5] Проверка контрольной суммы SHA-256 образа..."
    (cd "$(dirname "$iso_path")" && shasum -a 256 -c "$(basename "$sha_file")")
  else
    echo "[1/5] Файл .sha256 рядом не найден — пропуск автопроверки."
  fi

  local iso_bytes
  iso_bytes="$(get_file_size_bytes "$iso_path")"

  echo
  echo "Выберите режим записи флешки:"
  echo "  [1] Полный режим (UEFI + Legacy BIOS через sudo dd — нужен пароль администратора Mac)"
  echo "  [2] Режим БЕЗ пароля Mac (UEFI FAT32 без sudo — подходит для ноутбуков Lenovo с UEFI)"
  local mode_choice
  read -r -p "Ваш выбор (1 или 2, по умолчанию 1): " mode_choice
  mode_choice="${mode_choice:-1}"
  if [[ "$mode_choice" != "1" && "$mode_choice" != "2" ]]; then
    echo "Неверный выбор режима." >&2
    exit 1
  fi

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

  if [[ "$mode_choice" == "1" ]]; then
    flash_raw_with_sudo "$iso_path" "$target_id"
  else
    flash_fat32_uefi_no_sudo "$iso_path" "$target_id"
  fi

  echo "Вставьте Kingston DataTraveler в выключенный Lenovo и выберите загрузку с USB (F12 / Fn+F12 / кнопка Novo)."
}

case "${1:-}" in
  --self-test-parse)
    shift
    validate_macos_disk_info "$@"
    ;;
  --self-test-verify-uefi)
    shift
    verify_extracted_uefi_tree "$@"
    ;;
  --self-test-reassemble)
    shift
    find_or_reassemble_iso "$@"
    ;;
  *)
    main "$@"
    ;;
esac
