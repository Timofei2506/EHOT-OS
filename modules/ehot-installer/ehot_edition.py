"""Edition-aware product identity for EHOT OS (kent) / MfiSerli OS (public).

Reads /etc/ehot-edition.conf (written at ISO build time by customize-rootfs.sh).
Without that file the defaults preserve the original EHOT OS v1.0.0 behavior.
"""
from __future__ import annotations

from pathlib import Path

EDITION_CONF = Path("/etc/ehot-edition.conf")

_DEFAULTS = {
    "PRODUCT_NAME": "EHOT OS",
    "PRODUCT_VERSION": "1.0.0",
    "EDITION_ID": "ehot-os",
    "EDITION_PART_PREFIX": "EHOT",
    "PRODUCT_USERNAME": "Regzen",
    "PRODUCT_HOSTNAME": "ehot-lenovo",
}


def load_edition_identity(conf_path=None) -> dict:
    """Parse KEY='value' lines from the edition conf; unknown keys are ignored."""
    path = Path(conf_path) if conf_path is not None else EDITION_CONF
    values = dict(_DEFAULTS)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return values
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        key = key.strip()
        value = raw.strip().strip("'\"").strip()
        if key in values and value:
            values[key] = value
    return values


IDENTITY = load_edition_identity()

PRODUCT_NAME = IDENTITY["PRODUCT_NAME"]
PRODUCT_VERSION = IDENTITY["PRODUCT_VERSION"]
EDITION_ID = IDENTITY["EDITION_ID"]
ROOT_LABEL = f"{IDENTITY['EDITION_PART_PREFIX']}_ROOT"
EFI_LABEL = f"{IDENTITY['EDITION_PART_PREFIX']}EFI"
BOOTLOADER_ID = IDENTITY["EDITION_ID"].replace("-", "_").upper()
TARGET_USERNAME = IDENTITY["PRODUCT_USERNAME"]
DEFAULT_HOSTNAME = IDENTITY["PRODUCT_HOSTNAME"]
