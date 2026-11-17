#!/usr/bin/env bash
set -euo pipefail

# Executed INSIDE unpacked Linux Mint 22.3 XFCE squashfs chroot by build-iso.sh.
# Installs and configures all EHOT OS modules without embedding any secrets or passwords.

SRC_ROOT="/opt/ehot-os-src"
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

if [[ ! -d "$SRC_ROOT/modules" ]]; then
  echo "ОШИБКА: каталог исходников $SRC_ROOT/modules не найден внутри chroot." >&2
  exit 1
fi

echo "[chroot] Начало кастомизации rootfs EHOT OS..."

# Edition selection: kent (EHOT OS personal) or public (MfiSerli OS public edition).
# build-iso.sh exports EHOT_EDITION and writes /opt/ehot-os-src/build/config/edition-active.conf.
EDITION="kent"
PRODUCT_NAME="EHOT OS"
PRODUCT_VERSION="1.0.0"
EDITION_ID="ehot-os"
EDITION_PART_PREFIX="EHOT"
PRODUCT_USERNAME="Regzen"
PRODUCT_HOSTNAME="ehot-lenovo"
EDITION_ACTIVE_CONF="$SRC_ROOT/build/config/edition-active.conf"
if [[ -f "$EDITION_ACTIVE_CONF" ]]; then
  # shellcheck disable=SC1090
  source "$EDITION_ACTIVE_CONF"
fi
if [[ -n "${EHOT_EDITION:-}" ]]; then
  EDITION="$EHOT_EDITION"
fi
echo "[chroot] Редакция: $EDITION ($PRODUCT_NAME $PRODUCT_VERSION, id=$EDITION_ID)"

# Keep official Mint & Ubuntu repos intact; refresh indexes
apt-get update -qq

# 1. Core system (ZRAM, sysctl, earlyoom, LibreOffice, Firefox, drivers helper, grub binaries)
bash "$SRC_ROOT/modules/ehot-core/scripts/setup-core.sh" --mode chroot
apt-get clean

# 2. Gaming subsystem (Steam, Wine, Lutris, GameMode, MangoHud, Vulkan, i386)
bash "$SRC_ROOT/modules/ehot-gaming/scripts/setup-gaming.sh"
apt-get clean

if [[ "$EDITION" == "kent" ]]; then
  # 3. Remote access (AnyDesk from official repo, NO password stored!)
  bash "$SRC_ROOT/modules/ehot-remote/scripts/install-anydesk.sh"

  # 4. Telegram control agent & Firefox integration (NO token/chat_id stored!)
  bash "$SRC_ROOT/modules/ehot-control/scripts/install-control.sh"
else
  # Public edition (MfiSerli OS): personal control/remote modules are intentionally NOT installed.
  echo "[chroot] Публичная редакция: модули удалённого доступа и контроля не устанавливаются."
fi

# 5. Branding (edition-specific theme, XFCE configs, Plymouth, wallpaper slots)
if [[ "$EDITION" == "public" ]]; then
  bash "$SRC_ROOT/modules/ehot-branding/public/scripts/mfiserli-apply-branding.sh" "$SRC_ROOT/modules/ehot-branding/public/assets"
else
  bash "$SRC_ROOT/modules/ehot-branding/scripts/ehot-apply-branding.sh" "$SRC_ROOT/modules/ehot-branding/assets"
fi

# 6. Install EHOT Installer & First-boot service
install -d -m 755 /usr/local/lib/ehot-installer
install -m 755 "$SRC_ROOT/modules/ehot-installer/ehot_edition.py" /usr/local/lib/ehot-installer/ehot_edition.py
install -m 755 "$SRC_ROOT/modules/ehot-installer/disk_detect.py" /usr/local/lib/ehot-installer/disk_detect.py
install -m 755 "$SRC_ROOT/modules/ehot-installer/ehot-install.py" /usr/local/lib/ehot-installer/ehot-install.py
cat > /usr/local/sbin/ehot-install <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/local/lib/ehot-installer/ehot-install.py "$@"
EOF
chmod 755 /usr/local/sbin/ehot-install

install -Dm755 "$SRC_ROOT/modules/ehot-installer/ehot-firstboot.sh" /usr/local/sbin/ehot-firstboot
install -Dm644 "$SRC_ROOT/modules/ehot-installer/ehot-firstboot.service" /etc/systemd/system/ehot-firstboot.service

# Place installer icon on Live desktop & application menu
install -d -m 755 /etc/skel/Desktop /usr/share/applications
if [[ "$EDITION" == "kent" ]]; then
  install -m 755 "$SRC_ROOT/modules/ehot-installer/ehot-install.desktop" /etc/skel/Desktop/ehot-install.desktop
  install -m 644 "$SRC_ROOT/modules/ehot-installer/ehot-install.desktop" /usr/share/applications/ehot-install.desktop
fi
# Public edition: mfiserli-apply-branding.sh already installed install-mfiserli.desktop.

# Ensure forbidden packages are NOT installed
for forbidden in minecraft-launcher prismlauncher multimc telegram-desktop; do
  if dpkg-query -W -f='${Status}' "$forbidden" 2>/dev/null | grep -q "install ok installed"; then
    echo "ОШИБКА: обнаружен запрещённый пакет $forbidden!" >&2
    exit 1
  fi
done

# Brand OS release label nicely while preserving /etc/upstream-release (Ubuntu/Mint compatibility!)
install -d -m 755 "/usr/local/share/$EDITION_ID"
cp -r "$SRC_ROOT/docs" "/usr/local/share/$EDITION_ID/docs"
cat > "/etc/$EDITION_ID-release" <<EOF
NAME="$PRODUCT_NAME"
VERSION="$PRODUCT_VERSION (Mint 22.3 Zena XFCE Base)"
ID=$EDITION_ID
ID_LIKE="linuxmint ubuntu debian"
EOF
cat > /etc/ehot-edition.conf <<EOF
PRODUCT_NAME='$PRODUCT_NAME'
PRODUCT_VERSION='$PRODUCT_VERSION'
EDITION_ID='$EDITION_ID'
EDITION_PART_PREFIX='$EDITION_PART_PREFIX'
PRODUCT_USERNAME='$PRODUCT_USERNAME'
PRODUCT_HOSTNAME='$PRODUCT_HOSTNAME'
EOF

# Rebuild initramfs cleanly for Plymouth + ZRAM inside chroot
update-initramfs -u -k all || true

# Clean caches and temporary build artifacts
apt-get autoremove -y --purge || true
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* "$SRC_ROOT"
truncate -s 0 /etc/machine-id || true

echo "[chroot] Кастомизация rootfs EHOT OS успешно завершена."
