"""Structural guarantees for the MfiSerli OS public edition (EHOT_EDITION=public)."""
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
PUBLIC = REPO / "modules" / "ehot-branding" / "public"
ROOTFS_SH = REPO / "build" / "chroot" / "customize-rootfs.sh"
BUILD_ISO_SH = REPO / "build" / "scripts" / "build-iso.sh"
EDITION_CONF = REPO / "build" / "config" / "edition-public.conf"
INSTALL_PY = REPO / "modules" / "ehot-installer" / "ehot-install.py"
FIRSTBOOT_SH = REPO / "modules" / "ehot-installer" / "ehot-firstboot.sh"
APPLY_SH = PUBLIC / "scripts" / "mfiserli-apply-branding.sh"

BANNED_TOKENS = ("ehot-control", "ehot-remote", "anydesk", "telegram")

TEXT_SUFFIXES = {
    ".sh", ".py", ".xml", ".rc", ".md", ".theme", ".css", ".conf",
    ".script", ".plymouth", ".desktop", ".yml", ".svg",
}


def test_public_edition_has_no_control_or_remote_references():
    """The public edition tree must not reference personal control/remote modules at all."""
    for path in PUBLIC.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        text = path.read_text(encoding="utf-8", errors="replace").lower()
        for token in BANNED_TOKENS:
            assert token not in text, f"{path.relative_to(REPO)} references banned token '{token}'"


def test_customize_rootfs_public_branch_skips_personal_modules():
    """install-anydesk/install-control must live only inside the kent-only branch."""
    lines = ROOTFS_SH.read_text(encoding="utf-8").splitlines()
    guard_seen = False
    for i, line in enumerate(lines):
        if 'if [[ "$EDITION" == "kent" ]]; then' in line:
            guard_seen = True
        if "install-anydesk.sh" in line or "install-control.sh" in line:
            window = "\n".join(lines[max(0, i - 10):i + 1])
            assert '== "kent"' in window, f"personal module call outside kent branch near line {i + 1}"
    assert guard_seen, "kent edition guard missing in customize-rootfs.sh"
    text = ROOTFS_SH.read_text(encoding="utf-8")
    assert "mfiserli-apply-branding.sh" in text
    assert "Публичная редакция" in text
    assert "/etc/ehot-edition.conf" in text


def test_build_iso_supports_edition_flag_and_public_identity():
    build = BUILD_ISO_SH.read_text(encoding="utf-8")
    assert "--edition" in build
    assert "edition-public.conf" in build
    assert "edition-active.conf" in build
    conf = EDITION_CONF.read_text(encoding="utf-8")
    assert 'EDITION_ID="mfiserli-os"' in conf
    assert 'PRODUCT_NAME="MfiSerli OS"' in conf
    assert 'EDITION_ISO_FILENAME="mfiserli-os-22.3-xfce-amd64.iso"' in conf
    assert 'EDITION_VOLUME_ID="MFISERLI_22_3"' in conf
    assert 'EDITION_PART_PREFIX="MFISERLI"' in conf
    assert 'PRODUCT_USERNAME="user"' in conf
    assert 'PRODUCT_HOSTNAME="mfiserli-pc"' in conf


def test_public_theme_assets_present_and_wallpaper_4k():
    from PIL import Image

    wp = PUBLIC / "assets" / "wallpaper" / "wallpaper.jpg"
    login = PUBLIC / "assets" / "wallpaper" / "wallpaper-login.jpg"
    assert wp.exists() and wp.stat().st_size > 100_000
    assert login.exists()
    with Image.open(wp) as im:
        assert im.size == (3840, 2160)
    with Image.open(login) as im:
        assert im.size == (3840, 2160)

    theme_dir = PUBLIC / "assets" / "theme" / "MfiSerli-Dark-Glass"
    gtk_css = (theme_dir / "gtk-3.0" / "gtk.css").read_text(encoding="utf-8")
    assert "Mint-Y-Dark" in gtk_css
    assert "#22D3EE" in gtk_css or "0.86" in gtk_css
    themerc = (theme_dir / "xfwm4" / "themerc").read_text(encoding="utf-8")
    assert "#22D3EE" in themerc
    assert "MfiSerli Dark Glass" in (theme_dir / "index.theme").read_text(encoding="utf-8")
    icons_theme = (PUBLIC / "assets" / "icons" / "index.theme").read_text(encoding="utf-8")
    assert "Name=mfiserli" in icons_theme


def test_logo_and_plymouth_assets_present():
    from PIL import Image

    logo = PUBLIC / "assets" / "logo" / "mfiserli-logo.png"
    ply_logo = PUBLIC / "assets" / "plymouth" / "logo.png"
    menu = PUBLIC / "assets" / "icons" / "48x48" / "apps" / "mfiserli-menu.png"
    with Image.open(logo) as im:
        assert im.size == (512, 512)
    with Image.open(ply_logo) as im:
        assert im.size == (320, 320)
    with Image.open(menu) as im:
        assert im.size == (48, 48)
    assert (PUBLIC / "assets" / "logo" / "mfiserli-logo.svg").exists()
    assert (PUBLIC / "assets" / "icons" / "scalable" / "apps" / "mfiserli-menu.svg").exists()

    plymouth = (PUBLIC / "plymouth" / "mfiserli-os.plymouth").read_text(encoding="utf-8")
    assert "Name=MfiSerli OS" in plymouth
    assert "ModuleName=script" in plymouth
    script = (PUBLIC / "plymouth" / "mfiserli-os.script").read_text(encoding="utf-8")
    assert "MfiSerli OS" in script
    assert "logo.png" in script


def test_installer_edition_defaults_preserve_ehot_behavior():
    sys.path.insert(0, str(REPO / "modules" / "ehot-installer"))
    import ehot_edition

    assert ehot_edition.PRODUCT_NAME == "EHOT OS"
    assert ehot_edition.PRODUCT_VERSION == "1.0.0"
    assert ehot_edition.EDITION_ID == "ehot-os"
    assert ehot_edition.TARGET_USERNAME == "Regzen"
    assert ehot_edition.DEFAULT_HOSTNAME == "ehot-lenovo"
    assert ehot_edition.ROOT_LABEL == "EHOT_ROOT"
    assert ehot_edition.EFI_LABEL == "EHOTEFI"
    assert ehot_edition.BOOTLOADER_ID == "EHOT_OS"

    # Simulated public edition conf flips identity while keeping the API stable
    tmp_conf = REPO / "build" / "config" / "edition-public.conf"
    identity = ehot_edition.load_edition_identity(tmp_conf)
    assert identity["PRODUCT_NAME"] == "MfiSerli OS"
    assert identity["EDITION_PART_PREFIX"] == "MFISERLI"
    assert identity["PRODUCT_USERNAME"] == "user"


def test_install_py_is_edition_aware():
    text = INSTALL_PY.read_text(encoding="utf-8")
    assert "from ehot_edition import" in text
    assert '"3:EHOT_ROOT"' not in text
    assert "f\"3:{ROOT_LABEL}\"" in text
    assert '"EHOTEFI"' not in text
    assert '"EHOT_OS"' not in text
    assert 'GRUB_DISTRIBUTOR="{PRODUCT_NAME}"' in text
    assert 'УСТАНОВКА {PRODUCT_NAME} УСПЕШНО' in text
    assert 'description=f"{PRODUCT_NAME} Safe Installer"' in text


def test_firstboot_skips_personal_setup_without_modules():
    text = FIRSTBOOT_SH.read_text(encoding="utf-8")
    guard_idx = text.find('if command -v ehot-remote-setup >/dev/null 2>&1 || command -v ehot-control-setup >/dev/null 2>&1; then')
    block_idx = text.find("ehot-finish-setup.desktop")
    assert guard_idx != -1, "firstboot must guard the personal-setup reminder by helper presence"
    assert block_idx > guard_idx
    assert "/etc/ehot-edition.conf" in text
    assert 'PRODUCT_NAME="EHOT OS"' in text
    assert 'TARGET_USERNAME="Regzen"' in text


def test_public_desktop_entry_uses_mfiserli_branding():
    text = APPLY_SH.read_text(encoding="utf-8")
    assert "Установить MfiSerli OS" in text
    assert "install-mfiserli.desktop" in text
    assert "Icon=mfiserli-installer" in text
    assert "sudo ehot-install" in text


def test_panel_dock_at_bottom_with_glass_theme():
    panel = (PUBLIC / "xfce" / "xfce4-panel.xml").read_text(encoding="utf-8")
    assert 'value="p=12;x=0;y=0"' in panel
    assert '<property name="size" type="uint" value="42"/>' in panel
    assert '"show-labels" type="bool" value="false"' in panel
    xsettings = (PUBLIC / "xfce" / "xsettings.xml").read_text(encoding="utf-8")
    assert 'value="MfiSerli-Dark-Glass"' in xsettings
    assert 'value="mfiserli"' in xsettings
    whisker = (PUBLIC / "xfce" / "whiskermenu-1.rc").read_text(encoding="utf-8")
    assert "button-icon=mfiserli-menu" in whisker
    assert "show-button-title=false" in whisker
