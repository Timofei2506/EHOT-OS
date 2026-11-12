#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Branding Deployment & Hot-Swap Script (`ehot-apply-branding`)
# Applies XFCE config, GTK/XFWM4 theme, icon slots, wallpaper, Plymouth, LightDM.
# Does NOT invent fake logos if designer assets are not yet present.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="${1:-$MODULE_DIR/assets}"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите от имени root: sudo $0 [путь_к_assets]" >&2
  exit 1
fi

echo "[ehot-branding] Применение темы и конфигурации XFCE из: $ASSETS_DIR"

# 1. Install GTK3 & XFWM4 black-violet theme
if [[ -d "$ASSETS_DIR/theme/EHOT-Dark-Violet" ]]; then
  install -d -m 755 /usr/share/themes/EHOT-Dark-Violet
  cp -r "$ASSETS_DIR/theme/EHOT-Dark-Violet/"* /usr/share/themes/EHOT-Dark-Violet/
fi

# 2. Install Icon theme + designer overrides (menu icon, custom app icons)
install -d -m 755 /usr/share/icons/ehot-os/scalable/apps /usr/share/icons/ehot-os/48x48/apps
if [[ -f "$ASSETS_DIR/icons/index.theme" ]]; then
  install -m 644 "$ASSETS_DIR/icons/index.theme" /usr/share/icons/ehot-os/index.theme
fi
if compgen -G "$ASSETS_DIR/icons/*" >/dev/null 2>&1; then
  cp -rn "$ASSETS_DIR/icons/"* /usr/share/icons/ehot-os/ 2>/dev/null || cp -r "$ASSETS_DIR/icons/"* /usr/share/icons/ehot-os/
fi

# Menu icon slot (Whisker menu)
for candidate in "$ASSETS_DIR/menu-icon/ehot-menu.svg" "$ASSETS_DIR/menu-icon/ehot-menu.png"; do
  if [[ -f "$candidate" ]]; then
    ext="${candidate##*.}"
    if [[ "$ext" == "svg" ]]; then
      install -m 644 "$candidate" /usr/share/icons/ehot-os/scalable/apps/ehot-menu.svg
    else
      install -m 644 "$candidate" /usr/share/icons/ehot-os/48x48/apps/ehot-menu.png
    fi
    echo "[ehot-branding] Иконка меню приложений обновлена: $candidate"
  fi
done
gtk-update-icon-cache -f /usr/share/icons/ehot-os 2>/dev/null || true

# 3. Logo & Wallpaper slots (copied only when provided by designer)
install -d -m 755 /usr/share/ehot-os/branding /usr/share/backgrounds/ehot-os
for f in "$ASSETS_DIR"/logo/*.png "$ASSETS_DIR"/logo/*.svg; do
  [[ -e "$f" ]] && install -m 644 "$f" /usr/share/ehot-os/branding/
done

WALLPAPER_DEST="/usr/share/backgrounds/ehot-os/wallpaper.png"
for wp in "$ASSETS_DIR/wallpaper/wallpaper.png" "$ASSETS_DIR/wallpaper/wallpaper.jpg"; do
  if [[ -f "$wp" ]]; then
    install -m 644 "$wp" "/usr/share/backgrounds/ehot-os/$(basename "$wp")"
    if [[ "$wp" == *.jpg ]]; then
      WALLPAPER_DEST="/usr/share/backgrounds/ehot-os/wallpaper.jpg"
    fi
    echo "[ehot-branding] Обои установлены: $WALLPAPER_DEST"
  fi
done

# Update LightDM background if wallpaper exists
if [[ -f "$WALLPAPER_DEST" ]] && [[ -f /etc/lightdm/slick-greeter.conf ]]; then
  sed -i '/^background=/d' /etc/lightdm/slick-greeter.conf
  echo "background=$WALLPAPER_DEST" >> /etc/lightdm/slick-greeter.conf
fi

# 4. Plymouth boot splash theme
if [[ -d "$MODULE_DIR/plymouth" ]]; then
  install -d -m 755 /usr/share/plymouth/themes/ehot-os
  install -m 644 "$MODULE_DIR/plymouth/ehot-os.plymouth" /usr/share/plymouth/themes/ehot-os/ehot-os.plymouth
  install -m 644 "$MODULE_DIR/plymouth/ehot-os.script" /usr/share/plymouth/themes/ehot-os/ehot-os.script
  if [[ -f "$ASSETS_DIR/plymouth/logo.png" ]]; then
    install -m 644 "$ASSETS_DIR/plymouth/logo.png" /usr/share/plymouth/themes/ehot-os/logo.png
    echo "[ehot-branding] Графика экрана загрузки Plymouth обновлена."
  fi
  if command -v update-alternatives >/dev/null 2>&1; then
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
      /usr/share/plymouth/themes/ehot-os/ehot-os.plymouth 150 || true
    update-alternatives --set default.plymouth /usr/share/plymouth/themes/ehot-os/ehot-os.plymouth || true
  fi
fi

# 5. XFCE defaults in /etc/skel + /etc/xdg + existing user Regzen if present
XFCE_SRC="$MODULE_DIR/xfce"
if [[ -d "$XFCE_SRC" ]]; then
  for base in /etc/skel/.config/xfce4 /etc/xdg/xfce4; do
    install -d -m 755 "$base/xfconf/xfce-perchannel-xml" "$base/panel" "$base/terminal"
    install -m 644 "$XFCE_SRC/xfwm4.xml" "$base/xfconf/xfce-perchannel-xml/xfwm4.xml"
    install -m 644 "$XFCE_SRC/xsettings.xml" "$base/xfconf/xfce-perchannel-xml/xsettings.xml"
    install -m 644 "$XFCE_SRC/xfce4-desktop.xml" "$base/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
    install -m 644 "$XFCE_SRC/xfce4-panel.xml" "$base/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    install -m 644 "$XFCE_SRC/whiskermenu-1.rc" "$base/panel/whiskermenu-1.rc"
    install -m 644 "$XFCE_SRC/terminalrc" "$base/terminal/terminalrc"
  done

  if [[ "$WALLPAPER_DEST" != "/usr/share/backgrounds/ehot-os/wallpaper.png" ]]; then
    sed -i "s|/usr/share/backgrounds/ehot-os/wallpaper.png|$WALLPAPER_DEST|g" \
      /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml \
      /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
  fi
fi

# Install helper binary so branding can be re-applied cleanly later
install -Dm755 "$SCRIPT_DIR/ehot-apply-branding.sh" /usr/local/sbin/ehot-apply-branding

echo "[ehot-branding] Фирменный стиль EHOT OS применён."
