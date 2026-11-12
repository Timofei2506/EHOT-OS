#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Reproducible ISO Builder
# Produces a hybrid UEFI + Legacy BIOS bootable ISO based on official Linux Mint 22.3 XFCE.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$BUILD_DIR/config/build.conf"

WORK_DIR="${EHOT_BUILD_WORKDIR:-$BUILD_DIR/work}"
CACHE_DIR="${EHOT_BUILD_CACHEDIR:-$BUILD_DIR/cache}"
OUT_DIR="${EHOT_BUILD_OUTDIR:-$BUILD_DIR/output}"
KEEP_BASE_ISO="${KEEP_BASE_ISO:-1}"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: сборка squashfs/chroot требует root (запустите через sudo $0)." >&2
  exit 1
fi

for cmd in xorriso mksquashfs unsquashfs curl sha256sum python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Ошибка: не найдена утилита '$cmd'. Установите: apt install xorriso squashfs-tools curl" >&2
    exit 1
  fi
done

mkdir -p "$WORK_DIR" "$CACHE_DIR" "$OUT_DIR"

echo "[1/7] Получение и проверка официального ISO Linux Mint $MINT_VERSION XFCE..."
bash "$SCRIPT_DIR/download-mint-iso.sh" "$CACHE_DIR"
BASE_ISO="$CACHE_DIR/$MINT_ISO_FILENAME"

ISO_EXTRACT="$WORK_DIR/iso_extract"
SQUASH_ROOT="$WORK_DIR/squashfs-root"
rm -rf "$ISO_EXTRACT" "$SQUASH_ROOT"
mkdir -p "$ISO_EXTRACT"

echo "[2/7] Извлечение файлов ISO через xorriso..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$ISO_EXTRACT"
chmod -R u+w "$ISO_EXTRACT"

echo "[3/7] Распаковка casper/filesystem.squashfs..."
unsquashfs -d "$SQUASH_ROOT" "$ISO_EXTRACT/casper/filesystem.squashfs"

echo "[4/7] Подготовка chroot-окружения и кастомизация EHOT OS..."
cleanup_chroot() {
  set +e
  umount -lf "$SQUASH_ROOT/dev/pts" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/dev" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/proc" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/sys" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/run" 2>/dev/null || true
  rm -f "$SQUASH_ROOT/usr/sbin/policy-rc.d"
}
trap cleanup_chroot EXIT

# Prevent service daemons from starting during apt install inside chroot
cat > "$SQUASH_ROOT/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 "$SQUASH_ROOT/usr/sbin/policy-rc.d"

cp /etc/resolv.conf "$SQUASH_ROOT/etc/resolv.conf"
mkdir -p "$SQUASH_ROOT/opt/ehot-os-src"
cp -r "$REPO_ROOT/modules" "$REPO_ROOT/docs" "$REPO_ROOT/build" "$SQUASH_ROOT/opt/ehot-os-src/"

mount --bind /dev "$SQUASH_ROOT/dev"
mount --bind /dev/pts "$SQUASH_ROOT/dev/pts"
mount -t proc proc "$SQUASH_ROOT/proc"
mount -t sysfs sys "$SQUASH_ROOT/sys"
mount --bind /run "$SQUASH_ROOT/run"

chroot "$SQUASH_ROOT" /bin/bash /opt/ehot-os-src/build/chroot/customize-rootfs.sh

cleanup_chroot
trap - EXIT
: > "$SQUASH_ROOT/etc/resolv.conf"

# Copy updated kernel/initrd to ISO casper if initramfs changed
if compgen -G "$SQUASH_ROOT/boot/vmlinuz-*" >/dev/null; then
  LATEST_VMLINUZ="$(find "$SQUASH_ROOT/boot" -maxdepth 1 -name 'vmlinuz-*' | sort -V | tail -n1)"
  cp -f "$LATEST_VMLINUZ" "$ISO_EXTRACT/casper/vmlinuz"
fi
if compgen -G "$SQUASH_ROOT/boot/initrd.img-*" >/dev/null; then
  LATEST_INITRD="$(find "$SQUASH_ROOT/boot" -maxdepth 1 -name 'initrd.img-*' | sort -V | tail -n1)"
  if [[ -f "$ISO_EXTRACT/casper/initrd.lz" ]]; then
    cp -f "$LATEST_INITRD" "$ISO_EXTRACT/casper/initrd.lz"
  else
    cp -f "$LATEST_INITRD" "$ISO_EXTRACT/casper/initrd"
  fi
fi

echo "[5/7] Обновление манифестов, упаковка filesystem.squashfs (zstd)..."
# shellcheck disable=SC2016
chroot "$SQUASH_ROOT" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO_EXTRACT/casper/filesystem.manifest"
rm -f "$ISO_EXTRACT/casper/filesystem.squashfs"
mksquashfs "$SQUASH_ROOT" "$ISO_EXTRACT/casper/filesystem.squashfs" \
  -comp zstd -Xcompression-level 15 -noappend
printf '%s' "$(du -sx --block-size=1 "$SQUASH_ROOT" | cut -f1)" > "$ISO_EXTRACT/casper/filesystem.size"

# Free space early if requested (e.g. on CI runners)
rm -rf "$SQUASH_ROOT"

# Customize GRUB live menu labels safely while preserving original casper parameters
for cfg in "$ISO_EXTRACT/boot/grub/grub.cfg" "$ISO_EXTRACT/boot/grub/loopback.cfg"; do
  if [[ -f "$cfg" ]]; then
    sed -i 's/Start Linux Mint [^"]*/EHOT OS 22.3 (Запуск и установка)/g' "$cfg"
    sed -i 's/(compatibility mode)/(Безопасный режим графики)/g' "$cfg"
  fi
done
if [[ -f "$ISO_EXTRACT/.disk/info" ]]; then
  echo "EHOT OS 1.0.0 (Linux Mint 22.3 Zena XFCE amd64)" > "$ISO_EXTRACT/.disk/info"
fi

echo "[6/7] Обновление md5sum.txt внутри ISO..."
(
  cd "$ISO_EXTRACT"
  rm -f md5sum.txt md5sum.txt.tmp
  find . -type f ! -name md5sum.txt -print0 | xargs -0 md5sum > md5sum.txt.tmp
  mv -f md5sum.txt.tmp md5sum.txt
)

echo "[7/7] Сборка гибридного UEFI + Legacy BIOS ISO через xorriso..."
OUTPUT_ISO="$OUT_DIR/$EHOT_ISO_FILENAME"
rm -f "$OUTPUT_ISO" "$OUTPUT_ISO.sha256"

# Extract exact El Torito + GPT/MBR boot parameters from official base ISO
ELTORITO_ARGS_FILE="$WORK_DIR/xorriso_boot_args.txt"
xorriso -indev "$BASE_ISO" -report_el_torito as_mkisofs 2>/dev/null > "$ELTORITO_ARGS_FILE"

# Build python-parsed argument list replacing -V and removing -modification-date / old -part_like_isohybrid quirk
mapfile -d '' XORRISO_ARGS < <(python3 - "$ELTORITO_ARGS_FILE" "$EHOT_VOLUME_ID" <<'PY'
import shlex, sys
raw = open(sys.argv[1], encoding="utf-8").read()
vol_id = sys.argv[2]
tokens = shlex.split(raw)
out = []
i = 0
while i < len(tokens):
    t = tokens[i]
    if t == "-V" and i + 1 < len(tokens):
        out.extend(["-V", vol_id])
        i += 2
        continue
    if t.startswith("--modification-date="):
        i += 1
        continue
    out.append(t)
    i += 1
sys.stdout.buffer.write(b"\0".join(x.encode("utf-8") for x in out) + b"\0")
PY
)

xorriso -as mkisofs \
  -r -J -joliet-long -l \
  "${XORRISO_ARGS[@]}" \
  -o "$OUTPUT_ISO" \
  "$ISO_EXTRACT"

if [[ "$KEEP_BASE_ISO" == "0" ]]; then
  rm -f "$BASE_ISO"
fi
rm -rf "$ISO_EXTRACT"

(
  cd "$OUT_DIR"
  sha256sum "$EHOT_ISO_FILENAME" > "$EHOT_ISO_FILENAME.sha256"
)

echo "[build-iso] Готово! Образ: $OUTPUT_ISO"
ls -lh "$OUTPUT_ISO" "$OUTPUT_ISO.sha256"
