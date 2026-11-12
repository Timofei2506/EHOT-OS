#!/usr/bin/env bash
set -euo pipefail

# Downloads official Linux Mint 22.3 XFCE 64-bit ISO and verifies both SHA-256 and GPG signature.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$BUILD_DIR/config/build.conf"

OUT_DIR="${1:-$BUILD_DIR/cache}"
mkdir -p "$OUT_DIR"

ISO_PATH="$OUT_DIR/$MINT_ISO_FILENAME"
SUM_PATH="$OUT_DIR/sha256sum.txt"
GPG_PATH="$OUT_DIR/sha256sum.txt.gpg"

download_with_mirrors() {
  local rel_file="$1"
  local dest="$2"
  for base in "${MINT_MIRRORS[@]}"; do
    echo "[download] Пробуем зеркало: $base/$rel_file"
    if curl -fL --retry 3 --connect-timeout 15 -o "$dest.tmp" "$base/$rel_file"; then
      mv -f "$dest.tmp" "$dest"
      return 0
    fi
    rm -f "$dest.tmp"
  done
  return 1
}

if [[ ! -f "$SUM_PATH" ]]; then
  download_with_mirrors "sha256sum.txt" "$SUM_PATH"
fi
if [[ ! -f "$GPG_PATH" ]]; then
  download_with_mirrors "sha256sum.txt.gpg" "$GPG_PATH"
fi

echo "[verify] Проверка SHA-256 файла sha256sum.txt по встроенному эталону..."
EXPECTED_LINE="$(grep " \*${MINT_ISO_FILENAME}$" "$SUM_PATH" || true)"
if [[ -z "$EXPECTED_LINE" ]]; then
  echo "ОШИБКА: запись для $MINT_ISO_FILENAME не найдена в sha256sum.txt" >&2
  exit 1
fi
ACTUAL_HASH_IN_SUM="$(printf '%s\n' "$EXPECTED_LINE" | awk '{print $1}')"
if [[ "$ACTUAL_HASH_IN_SUM" != "$MINT_ISO_SHA256" ]]; then
  echo "ОШИБКА: несовпадение SHA-256 с эталоном build.conf ($ACTUAL_HASH_IN_SUM != $MINT_ISO_SHA256)" >&2
  exit 1
fi

if command -v gpg >/dev/null 2>&1; then
  echo "[verify] Проверка GPG-подписи Linux Mint ($MINT_GPG_FINGERPRINT)..."
  GNUPGHOME_TMP="$(mktemp -d)"
  trap 'rm -rf "$GNUPGHOME_TMP"' EXIT
  export GNUPGHOME="$GNUPGHOME_TMP"
  if gpg --batch --keyserver hkp://keys.openpgp.org:80 --recv-keys "$MINT_GPG_FINGERPRINT" 2>/dev/null || \
     gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$MINT_GPG_FINGERPRINT" 2>/dev/null; then
    gpg --batch --verify "$GPG_PATH" "$SUM_PATH"
    echo "[verify] GPG-подпись sha256sum.txt подтверждена."
  else
    echo "[verify] Предупреждение: не удалось связаться с keyserver для GPG; проверка продолжается по жёсткому SHA-256."
  fi
fi

if [[ -f "$ISO_PATH" ]]; then
  echo "[download] Найден кэшированный образ $ISO_PATH, проверка контрольной суммы..."
  if printf '%s  %s\n' "$MINT_ISO_SHA256" "$ISO_PATH" | sha256sum -c -; then
    echo "[verify] Кэшированный ISO полностью валиден."
    exit 0
  fi
  echo "[download] Кэшированный ISO повреждён, перекачиваем..."
  rm -f "$ISO_PATH"
fi

download_with_mirrors "$MINT_ISO_FILENAME" "$ISO_PATH"
printf '%s  %s\n' "$MINT_ISO_SHA256" "$ISO_PATH" | sha256sum -c -
echo "[verify] Официальный Linux Mint 22.3 XFCE ISO успешно скачан и проверен."
