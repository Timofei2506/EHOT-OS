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
RESUME_WORKDIR="${RESUME_WORKDIR:-0}"

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

BASE_ISO="$CACHE_DIR/$MINT_ISO_FILENAME"
ISO_EXTRACT="$WORK_DIR/iso_extract"
SQUASH_ROOT="$WORK_DIR/squashfs-root"
ELTORITO_ARGS_FILE="$WORK_DIR/xorriso_boot_args.txt"

if [[ "$RESUME_WORKDIR" == "1" && -d "$ISO_EXTRACT" && -d "$SQUASH_ROOT" && -f "$ELTORITO_ARGS_FILE" ]]; then
  echo "[1-3/7] Продолжение сборки из существующего каталога $WORK_DIR..."
else
  echo "[1/7] Получение и проверка официального ISO Linux Mint $MINT_VERSION XFCE..."
  bash "$SCRIPT_DIR/download-mint-iso.sh" "$CACHE_DIR"

  rm -rf "$ISO_EXTRACT" "$SQUASH_ROOT"
  mkdir -p "$ISO_EXTRACT"

  echo "[2/7] Извлечение файлов ISO через xorriso..."
  xorriso -osirrox on -indev "$BASE_ISO" -extract / "$ISO_EXTRACT"
  chmod -R u+w "$ISO_EXTRACT"

  echo "[3/7] Распаковка casper/filesystem.squashfs..."
  unsquashfs -d "$SQUASH_ROOT" "$ISO_EXTRACT/casper/filesystem.squashfs"
  # Free ~2.9 GB immediately since filesystem.squashfs will be rebuilt in step 5
  rm -f "$ISO_EXTRACT/casper/filesystem.squashfs"

  # Extract El Torito boot params BEFORE optionally deleting BASE_ISO to save ~2.9 GB
  xorriso -indev "$BASE_ISO" -report_el_torito as_mkisofs 2>/dev/null > "$ELTORITO_ARGS_FILE"
  if [[ "$KEEP_BASE_ISO" == "0" ]] && ! grep -q -- "-append_partition" "$ELTORITO_ARGS_FILE"; then
    dd if="$BASE_ISO" of="$WORK_DIR/mbr_header.bin" bs=2048 count=16 status=none
    python3 - "$ELTORITO_ARGS_FILE" "$BASE_ISO" "$WORK_DIR/mbr_header.bin" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(txt.replace(old, new))
PY
    rm -f "$BASE_ISO"
  fi
fi

echo "[4/7] Подготовка chroot-окружения и кастомизация EHOT OS..."
RESOLV_ORIG_TARGET=""
if [[ -L "$SQUASH_ROOT/etc/resolv.conf" ]]; then
  RESOLV_ORIG_TARGET="$(readlink "$SQUASH_ROOT/etc/resolv.conf")"
fi

restore_chroot_resolv() {
  if [[ -n "${RESOLV_ORIG_TARGET:-}" && -d "$SQUASH_ROOT/etc" ]]; then
    rm -f "$SQUASH_ROOT/etc/resolv.conf" 2>/dev/null || true
    ln -snf "$RESOLV_ORIG_TARGET" "$SQUASH_ROOT/etc/resolv.conf" 2>/dev/null || true
  elif [[ -d "$SQUASH_ROOT/etc" ]]; then
    : > "$SQUASH_ROOT/etc/resolv.conf" 2>/dev/null || true
  fi
}

cleanup_chroot() {
  set +e
  umount -lf "$SQUASH_ROOT/dev/pts" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/dev" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/proc" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/sys" 2>/dev/null || true
  umount -lf "$SQUASH_ROOT/run" 2>/dev/null || true
  rm -f "$SQUASH_ROOT/usr/sbin/policy-rc.d"
  restore_chroot_resolv
}
trap cleanup_chroot EXIT

# Prevent service daemons from starting during apt install inside chroot
cat > "$SQUASH_ROOT/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 "$SQUASH_ROOT/usr/sbin/policy-rc.d"

# Remove Mint's dangling symlink (../run/systemd/resolve/stub-resolv.conf) before copying host DNS
rm -f "$SQUASH_ROOT/etc/resolv.conf"
cp -L /etc/resolv.conf "$SQUASH_ROOT/etc/resolv.conf"
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

# Keep original casper /casper/vmlinuz & /casper/initrd.lz intact so casper-uuid stays 100% synced
# with /.disk/casper-uuid-generic, grub.cfg, and isolinux/live.cfg (target HDD rebuilds initramfs in ehot-install).

echo "[5/7] Обновление манифестов, упаковка filesystem.squashfs (zstd)..."
# shellcheck disable=SC2016
chroot "$SQUASH_ROOT" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO_EXTRACT/casper/filesystem.manifest"
rm -f "$ISO_EXTRACT/casper/filesystem.squashfs"
MEM_TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
MKSQ_OPTS=(-comp zstd -Xcompression-level 12 -noappend)
if (( MEM_TOTAL_MB < 3200 )); then
  MKSQ_OPTS+=(-processors 1 -mem 512M)
fi
mksquashfs "$SQUASH_ROOT" "$ISO_EXTRACT/casper/filesystem.squashfs" "${MKSQ_OPTS[@]}"
printf '%s' "$(du -sx --block-size=1 "$SQUASH_ROOT" | cut -f1)" > "$ISO_EXTRACT/casper/filesystem.size"

# Free space early if requested (e.g. on CI runners)
rm -rf "$SQUASH_ROOT"

# Customize GRUB & ISOLINUX live menu labels safely (ASCII-only in GRUB to guarantee readable fonts in UEFI/BIOS)
for cfg in "$ISO_EXTRACT/boot/grub/grub.cfg" "$ISO_EXTRACT/boot/grub/loopback.cfg"; do
  if [[ -f "$cfg" ]]; then
    sed -i 's/Start Linux Mint .* (compatibility mode)/EHOT OS 22.3 (Safe Graphics - nomodeset)/g' "$cfg"
    sed -i 's/Start Linux Mint [^"]*/EHOT OS 22.3 (Live \& Install)/g' "$cfg"
  fi
done
if [[ -f "$ISO_EXTRACT/isolinux/live.cfg" ]]; then
  sed -i 's/Welcome to Linux Mint .*/Welcome to EHOT OS 22.3 (Linux Mint XFCE Base)/g' "$ISO_EXTRACT/isolinux/live.cfg"
  sed -i 's/menu label Start Linux Mint in compatibility mode/menu label Start EHOT OS (Safe Graphics \/ nomodeset)/g' "$ISO_EXTRACT/isolinux/live.cfg"
  sed -i 's/menu label Start Linux Mint$/menu label Start EHOT OS (Live + Install)/g' "$ISO_EXTRACT/isolinux/live.cfg"
fi
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

# Parse saved El Torito + GPT/MBR boot parameters from official base ISO

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
