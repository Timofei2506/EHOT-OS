#!/usr/bin/env bash
set -euo pipefail

# MfiSerli OS (public edition) Branding Deployment Script (`mfiserli-apply-branding`)
# Applies the Dark Glass XFCE config, GTK/xfwm4 theme, icons, wallpaper, Plymouth, LightDM
# and the public installer desktop entry.
# Intentionally ships without the personal remote-access or parental-features modules:


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="${1:-$MODULE_DIR/assets}"

THEME_NAME="MfiSerli-Dark-Glass"
ICON_THEME_DIR="/usr/share/icons/mfiserli"
WALLPAPER_DIR="/usr/share/backgrounds/mfiserli-os"
PLYMOUTH_DIR="/usr/share/plymouth/themes/mfiserli-os"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите от имени root: sudo $0 [путь_к_assets]" >&2
  exit 1
fi

echo "[mfiserli-branding] Применение темы Dark Glass и конфигурации XFCE из: $ASSETS_DIR"

# 1. Install GTK3 & XFWM4 glass theme
if [[ -d "$ASSETS_DIR/theme/$THEME_NAME" ]]; then
  install -d -m 755 "/usr/share/themes/$THEME_NAME"
  cp -r "$ASSETS_DIR/theme/$THEME_NAME/"* "/usr/share/themes/$THEME_NAME/"
fi

# 2. Install icon theme + logo/menu/installer overrides
install -d -m 755 "$ICON_THEME_DIR/scalable/apps" "$ICON_THEME_DIR/48x48/apps"
if [[ -f "$ASSETS_DIR/icons/index.theme" ]]; then
  install -m 644 "$ASSETS_DIR/icons/index.theme" "$ICON_THEME_DIR/index.theme"
fi
if [[ -d "$ASSETS_DIR/icons/scalable/apps" ]]; then
  install -m 644 "$ASSETS_DIR/icons/scalable/apps/"*.svg "$ICON_THEME_DIR/scalable/apps/" 2>/dev/null || true
fi
if [[ -d "$ASSETS_DIR/icons/48x48/apps" ]]; then
  install -m 644 "$ASSETS_DIR/icons/48x48/apps/"*.png "$ICON_THEME_DIR/48x48/apps/" 2>/dev/null || true
fi
for candidate in "$ASSETS_DIR/menu-icon/mfiserli-menu.svg" "$ASSETS_DIR/icons/scalable/apps/mfiserli-menu.svg"; do
  if [[ -f "$candidate" ]]; then
    install -m 644 "$candidate" "$ICON_THEME_DIR/scalable/apps/mfiserli-menu.svg"
    break
  fi
done
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f "$ICON_THEME_DIR" 2>/dev/null || true
fi

# 3. Logo & wallpaper slots (Aurora Glass 4K + darker login variant)
install -d -m 755 /usr/share/mfiserli-os/branding "$WALLPAPER_DIR"
for f in "$ASSETS_DIR"/logo/*.png "$ASSETS_DIR"/logo/*.svg; do
  [[ -e "$f" ]] && install -m 644 "$f" /usr/share/mfiserli-os/branding/
done

WALLPAPER_DEST=""
for wp in "$ASSETS_DIR/wallpaper/wallpaper.png" "$ASSETS_DIR/wallpaper/wallpaper.jpg"; do
  if [[ -f "$wp" ]]; then
    install -m 644 "$wp" "$WALLPAPER_DIR/$(basename "$wp")"
    WALLPAPER_DEST="$WALLPAPER_DIR/$(basename "$wp")"
    echo "[mfiserli-branding] Обои установлены: $WALLPAPER_DEST"
  fi
done
for extra in "$ASSETS_DIR"/wallpaper/wallpaper-login.jpg "$ASSETS_DIR"/wallpaper/wallpaper-1920.jpg; do
  [[ -e "$extra" ]] && install -m 644 "$extra" "$WALLPAPER_DIR/"
done

# Update LightDM (slick-greeter) background & greeter theme
if [[ -n "$WALLPAPER_DEST" ]] && [[ -f /etc/lightdm/slick-greeter.conf ]]; then
  sed -i '/^background=/d' /etc/lightdm/slick-greeter.conf
  sed -i '/^theme-name=/d' /etc/lightdm/slick-greeter.conf
  sed -i '/^icon-theme-name=/d' /etc/lightdm/slick-greeter.conf
  {
    echo "background=$WALLPAPER_DIR/wallpaper-login.jpg"
    echo "theme-name=$THEME_NAME"
    echo "icon-theme-name=mfiserli"
  } >> /etc/lightdm/slick-greeter.conf
fi

# 4. Plymouth boot splash theme (glass navy + teal progress + tile logo)
if [[ -d "$MODULE_DIR/plymouth" ]]; then
  install -d -m 755 "$PLYMOUTH_DIR"
  install -m 644 "$MODULE_DIR/plymouth/mfiserli-os.plymouth" "$PLYMOUTH_DIR/mfiserli-os.plymouth"
  install -m 644 "$MODULE_DIR/plymouth/mfiserli-os.script" "$PLYMOUTH_DIR/mfiserli-os.script"
  if [[ -f "$ASSETS_DIR/plymouth/logo.png" ]]; then
    install -m 644 "$ASSETS_DIR/plymouth/logo.png" "$PLYMOUTH_DIR/logo.png"
    echo "[mfiserli-branding] Экран загрузки Plymouth обновлён."
  fi
  if command -v update-alternatives >/dev/null 2>&1; then
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
      "$PLYMOUTH_DIR/mfiserli-os.plymouth" 200 || true
    update-alternatives --set default.plymouth "$PLYMOUTH_DIR/mfiserli-os.plymouth" || true
  fi
fi

# 5. XFCE defaults in /etc/skel + /etc/xdg (+ Mint's xdg-linuxmint if present)
XFCE_SRC="$MODULE_DIR/xfce"
if [[ -d "$XFCE_SRC" ]]; then
  XFCE_TARGETS=(/etc/skel/.config/xfce4 /etc/xdg/xfce4)
  if [[ -d /etc/xdg/xdg-linuxmint/xfce4 ]]; then
    XFCE_TARGETS+=(/etc/xdg/xdg-linuxmint/xfce4)
  fi
  for base in "${XFCE_TARGETS[@]}"; do
    install -d -m 755 "$base/xfconf/xfce-perchannel-xml" "$base/panel" "$base/terminal"
    install -m 644 "$XFCE_SRC/xfwm4.xml" "$base/xfconf/xfce-perchannel-xml/xfwm4.xml"
    install -m 644 "$XFCE_SRC/xsettings.xml" "$base/xfconf/xfce-perchannel-xml/xsettings.xml"
    install -m 644 "$XFCE_SRC/xfce4-desktop.xml" "$base/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
    install -m 644 "$XFCE_SRC/xfce4-panel.xml" "$base/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    install -m 644 "$XFCE_SRC/whiskermenu-1.rc" "$base/panel/whiskermenu-1.rc"
    install -m 644 "$XFCE_SRC/terminalrc" "$base/terminal/terminalrc"
  done
fi

# 6. Public installer desktop entry ("Install MfiSerli OS") on Live desktop & menu
install -d -m 755 /etc/skel/Desktop /usr/share/applications
cat > /usr/share/applications/install-mfiserli.desktop <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Установить MfiSerli OS
Name[en]=Install MfiSerli OS
Comment=Безопасная автоматическая установка MfiSerli OS на внутренний накопитель
Exec=xfce4-terminal -T "Установщик MfiSerli OS" -e "sudo ehot-install; echo 'Нажмите Enter для закрытия...'; read"
Icon=mfiserli-installer
Terminal=false
Categories=System;
StartupNotify=true
EOF
chmod 644 /usr/share/applications/install-mfiserli.desktop
install -m 755 /usr/share/applications/install-mfiserli.desktop /etc/skel/Desktop/install-mfiserli.desktop

# Install helper binary so branding can be re-applied cleanly later
install -Dm755 "$SCRIPT_DIR/mfiserli-apply-branding.sh" /usr/local/sbin/mfiserli-apply-branding

echo "[mfiserli-branding] Фирменный стиль MfiSerli OS (Dark Glass) применён."
