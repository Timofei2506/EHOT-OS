#!/usr/bin/env python3
"""
EHOT OS Safe Target Disk Detector.
Parses `lsblk --json --bytes --nodeps` and live-boot mount sources to safely
identify candidate internal hard drives / SSDs while strictly excluding USB
flash drives (such as Kingston DataTraveler 64 GB), removable media, read-only
devices, and the live boot medium itself.
"""

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

GIB = 1024 ** 3
GB = 1000 ** 3
DEFAULT_MIN_TARGET_BYTES = 80 * GB  # Strictly larger than 64 GB USB sticks


@dataclass
class DiskCandidate:
    name: str
    path: str
    size_bytes: int
    model: str
    serial: str
    tran: str
    rm: bool
    hotplug: bool
    ro: bool
    rota: bool
    eligible: bool
    rejection_reasons: List[str]

    @property
    def size_gb(self) -> float:
        return round(self.size_bytes / GB, 1)

    @property
    def size_gib(self) -> float:
        return round(self.size_bytes / GIB, 1)

    @property
    def disk_kind(self) -> str:
        if self.tran.lower() == "nvme":
            return "NVMe SSD"
        return "HDD" if self.rota else "SSD"

    def summary_line(self) -> str:
        return (
            f"{self.path} | {self.model or 'Неизвестная модель'} | "
            f"{self.size_gb} ГБ ({self.size_gib} ГиБ) | {self.disk_kind} | "
            f"Шины: {self.tran or 'n/a'} | S/N: {self.serial or 'n/a'}"
        )

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["size_gb"] = self.size_gb
        d["size_gib"] = self.size_gib
        d["disk_kind"] = self.disk_kind
        return d


def _to_bool(val: Any) -> bool:
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return bool(val)
    return str(val).strip().lower() in {"1", "true", "yes"}


def _base_block_name(dev_path: str) -> Optional[str]:
    """Normalize partition/device path like /dev/sda1 or /dev/nvme0n1p2 -> sda / nvme0n1."""
    if not dev_path or not dev_path.startswith("/dev/"):
        return None
    name = Path(dev_path).name
    m_nvme = re.match(r"^(nvme\d+n\d+)p\d+$", name)
    if m_nvme:
        return m_nvme.group(1)
    m_mmc = re.match(r"^(mmcblk\d+)p\d+$", name)
    if m_mmc:
        return m_mmc.group(1)
    m_sd = re.match(r"^([a-zA-Z]+)\d+$", name)
    if m_sd:
        return m_sd.group(1)
    return name


def detect_live_backing_devices() -> Set[str]:
    """Return kernel device names (e.g., {'sda', 'sdb'}) backing live OS mounts."""
    protected: Set[str] = set()
    mountpoints = ["/cdrom", "/run/live/medium", "/lib/live/mount/medium", "/rofs"]
    for mp in mountpoints:
        if not Path(mp).exists():
            continue
        try:
            res = subprocess.run(
                ["findmnt", "-n", "-o", "SOURCE", mp],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            src = res.stdout.strip()
            if src.startswith("/dev/"):
                # Resolve parent disk via lsblk PKNAME if available
                pk = subprocess.run(
                    ["lsblk", "-no", "PKNAME", src],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=False,
                ).stdout.strip()
                if pk:
                    protected.add(pk)
                base = _base_block_name(src)
                if base:
                    protected.add(base)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    return protected


def evaluate_lsblk_json(
    lsblk_data: Dict[str, Any],
    protected_devices: Optional[Set[str]] = None,
    min_size_bytes: int = DEFAULT_MIN_TARGET_BYTES,
) -> List[DiskCandidate]:
    protected = protected_devices or set()
    candidates: List[DiskCandidate] = []

    for dev in lsblk_data.get("blockdevices", []):
        dev_type = str(dev.get("type", "")).lower()
        name = str(dev.get("name", ""))
        path = str(dev.get("path") or f"/dev/{name}")

        if dev_type != "disk":
            continue
        if name.startswith(("loop", "zram", "sr", "ram", "fd")):
            continue

        size_bytes = int(dev.get("size") or 0)
        model = str(dev.get("model") or "").strip()
        serial = str(dev.get("serial") or "").strip()
        tran = str(dev.get("tran") or "").strip().lower()
        rm = _to_bool(dev.get("rm", False))
        hotplug = _to_bool(dev.get("hotplug", False))
        ro = _to_bool(dev.get("ro", False))
        rota = _to_bool(dev.get("rota", False))

        reasons: List[str] = []
        if name in protected or path in protected:
            reasons.append("является текущим загрузочным носителем Live OS")
        if tran == "usb":
            reasons.append("подключён по USB (съёмный носитель)")
        if rm:
            reasons.append("помечен как съёмный носитель (RM=1)")
        if hotplug:
            reasons.append("помечен как hotplug-носитель (HOTPLUG=1)")
        if ro:
            reasons.append("доступен только для чтения (RO=1)")
        if size_bytes < min_size_bytes:
            reasons.append(
                f"размер {round(size_bytes / GB, 1)} ГБ меньше минимального порога "
                f"{round(min_size_bytes / GB, 1)} ГБ"
            )

        candidates.append(
            DiskCandidate(
                name=name,
                path=path,
                size_bytes=size_bytes,
                model=model,
                serial=serial,
                tran=tran,
                rm=rm,
                hotplug=hotplug,
                ro=ro,
                rota=rota,
                eligible=(len(reasons) == 0),
                rejection_reasons=reasons,
            )
        )

    # Prefer ~1TB internal SATA/NVMe disks first
    candidates.sort(key=lambda c: (c.eligible, c.size_bytes), reverse=True)
    return candidates


def select_target_disk(
    candidates: List[DiskCandidate],
    preferred_path: Optional[str] = None,
) -> Tuple[Optional[DiskCandidate], List[str]]:
    eligible = [c for c in candidates if c.eligible]
    warnings: List[str] = []

    if preferred_path:
        for c in candidates:
            if c.path == preferred_path:
                if not c.eligible:
                    raise ValueError(
                        f"Устройство {preferred_path} заблокировано проверкой безопасности: "
                        + "; ".join(c.rejection_reasons)
                    )
                return c, warnings
        raise ValueError(f"Устройство {preferred_path} не найдено в списке дисков.")

    if not eligible:
        warnings.append("Не найден ни один безопасный внутренний диск (исключая USB/съёмные/малые диски).")
        return None, warnings

    if len(eligible) > 1:
        warnings.append(
            f"Найдено несколько внутренних дисков ({len(eligible)}). Выберите целевой диск вручную или подтвердите первый (~{eligible[0].size_gb} ГБ)."
        )
    return eligible[0], warnings


def scan_system_disks(min_size_bytes: int = DEFAULT_MIN_TARGET_BYTES) -> List[DiskCandidate]:
    cmd = [
        "lsblk",
        "--json",
        "--bytes",
        "--nodeps",
        "--output",
        "NAME,PATH,SIZE,TYPE,TRAN,RM,HOTPLUG,RO,ROTA,MODEL,SERIAL",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=True)
    data = json.loads(res.stdout)
    protected = detect_live_backing_devices()
    return evaluate_lsblk_json(data, protected_devices=protected, min_size_bytes=min_size_bytes)


if __name__ == "__main__":
    disks = scan_system_disks()
    print(json.dumps([d.to_dict() for d in disks], ensure_ascii=False, indent=2))
