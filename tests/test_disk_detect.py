import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "modules" / "ehot-installer"))

from disk_detect import evaluate_lsblk_json, select_target_disk  # noqa: E402


def test_never_picks_usb_kingston_even_if_sda():
    """When booting from USB, Kingston DataTraveler often becomes /dev/sda while HDD is /dev/sdb."""
    fake_lsblk = {
        "blockdevices": [
            {
                "name": "sda",
                "path": "/dev/sda",
                "size": 62_000_000_000,
                "type": "disk",
                "tran": "usb",
                "rm": True,
                "hotplug": True,
                "ro": False,
                "rota": False,
                "model": "Kingston DataTraveler 3.0",
                "serial": "USB12345",
            },
            {
                "name": "sdb",
                "path": "/dev/sdb",
                "size": 1_000_204_886_016,
                "type": "disk",
                "tran": "sata",
                "rm": False,
                "hotplug": False,
                "ro": False,
                "rota": True,
                "model": "WDC WD10SPZX-24Z10",
                "serial": "WD-LENOVO-1TB",
            },
        ]
    }
    candidates = evaluate_lsblk_json(fake_lsblk, protected_devices={"sda"})
    by_path = {c.path: c for c in candidates}

    assert not by_path["/dev/sda"].eligible
    assert any("USB" in r or "usb" in r.lower() for r in by_path["/dev/sda"].rejection_reasons)
    assert by_path["/dev/sdb"].eligible

    chosen, warnings = select_target_disk(candidates)
    assert chosen is not None
    assert chosen.path == "/dev/sdb"
    assert not warnings


def test_blocks_explicit_selection_of_usb_or_live_device():
    fake_lsblk = {
        "blockdevices": [
            {
                "name": "sda",
                "path": "/dev/sda",
                "size": 64_000_000_000,
                "type": "disk",
                "tran": "usb",
                "rm": True,
                "hotplug": True,
                "ro": False,
                "rota": False,
                "model": "DataTraveler",
                "serial": "111",
            },
            {
                "name": "nvme0n1",
                "path": "/dev/nvme0n1",
                "size": 512_000_000_000,
                "type": "disk",
                "tran": "nvme",
                "rm": False,
                "hotplug": False,
                "ro": False,
                "rota": False,
                "model": "SAMSUNG MZVLQ512",
                "serial": "NVME1",
            },
        ]
    }
    candidates = evaluate_lsblk_json(fake_lsblk, protected_devices={"sda"})
    with pytest.raises(ValueError):
        select_target_disk(candidates, preferred_path="/dev/sda")

    chosen, _ = select_target_disk(candidates)
    assert chosen is not None
    assert chosen.path == "/dev/nvme0n1"


def test_blocks_live_backing_device_even_if_not_usb_flagged():
    """Protects virtual/unusual drives backing /cdrom."""
    fake_lsblk = {
        "blockdevices": [
            {
                "name": "vda",
                "path": "/dev/vda",
                "size": 250_000_000_000,
                "type": "disk",
                "tran": "virtio",
                "rm": False,
                "hotplug": False,
                "ro": False,
                "rota": False,
                "model": "LiveMedium",
                "serial": "V1",
            }
        ]
    }
    candidates = evaluate_lsblk_json(fake_lsblk, protected_devices={"vda"})
    assert not candidates[0].eligible
    chosen, warnings = select_target_disk(candidates)
    assert chosen is None
    assert warnings
