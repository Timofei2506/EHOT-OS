import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_forbidden_apps_not_installed():
    forbidden = ("minecraft-launcher", "prismlauncher", "multimc", "telegram-desktop")
    install_scripts = [
        REPO_ROOT / "modules" / "ehot-core" / "scripts" / "setup-core.sh",
        REPO_ROOT / "modules" / "ehot-gaming" / "scripts" / "setup-gaming.sh",
        REPO_ROOT / "modules" / "ehot-remote" / "scripts" / "install-anydesk.sh",
        REPO_ROOT / "modules" / "ehot-control" / "scripts" / "install-control.sh",
        REPO_ROOT / "build" / "chroot" / "customize-rootfs.sh",
    ]
    for script in install_scripts:
        text = script.read_text(encoding="utf-8")
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("#") or "dpkg-query" in stripped or "for forbidden" in stripped:
                continue
            for pkg in forbidden:
                assert pkg not in stripped, f"Forbidden package {pkg} referenced in {script}"


def test_no_secrets_or_tokens_in_repo():
    secret_patterns = (
        re.compile(r"ghp_[A-Za-z0-9]{20,}"),
        re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
        re.compile(r"TELEGRAM_BOT_TOKEN=\d{6,}:[A-Za-z0-9_-]{20,}"),
        re.compile(r"ad\.security\.unattended_password=\S+"),
    )
    for path in REPO_ROOT.rglob("*"):
        if not path.is_file():
            continue
        if ".git" in path.parts or path.suffix in {".png", ".jpg", ".ico"}:
            continue
        content = path.read_text(encoding="utf-8", errors="ignore")
        for pat in secret_patterns:
            assert not pat.search(content), f"Potential secret leaked in {path}"


def test_firefox_extension_manifest_strictly_privacy_scoped():
    manifest = json.loads(
        (REPO_ROOT / "modules" / "ehot-control" / "extension" / "manifest.json").read_text(encoding="utf-8")
    )
    assert manifest["manifest_version"] == 3
    perms = set(manifest["permissions"])
    assert perms == {"downloads", "webNavigation", "nativeMessaging"}
    assert "history" not in perms
    assert "<all_urls>" not in manifest.get("host_permissions", [])
    assert set(manifest["host_permissions"]) == {"*://*.youtube.com/*", "*://youtu.be/*"}


def test_all_json_and_xml_files_are_valid():
    for jf in REPO_ROOT.rglob("*.json"):
        if ".git" in jf.parts:
            continue
        json.loads(jf.read_text(encoding="utf-8"))

    for xf in REPO_ROOT.rglob("*.xml"):
        if ".git" in xf.parts:
            continue
        ET.parse(xf)


def test_branding_has_no_fake_placeholder_images():
    branding_assets = REPO_ROOT / "modules" / "ehot-branding" / "assets"
    for slot in ("logo", "wallpaper", "plymouth", "menu-icon"):
        files = [p for p in (branding_assets / slot).iterdir() if p.name != ".gitkeep"]
        assert files == [], f"Unexpected placeholder graphic in {slot}: {files}"
