#!/usr/bin/env python3
"""
EHOT OS GPU & Driver Compatibility Classifier.
Safely inspects PCI graphics hardware (including unknown NVIDIA models on used
Lenovo laptops) and recommends ONLY compatible official Ubuntu/Mint drivers,
never forcing broken legacy branches onto modern kernels.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from typing import Iterable, List, Optional, Sequence, Tuple


PCI_GPU_RE = re.compile(
    r"^(?:[0-9a-fA-F]{4}:)?([0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F])\s+"
    r"(?:VGA compatible controller|3D controller|Display controller)\s+\[[0-9a-fA-F]{4}\]:\s+"
    r"(.+?)\s+\[([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\]"
)

DRIVER_VER_RE = re.compile(r"(nvidia-driver-(\d+)(?:-open)?(?:-server)?)")

# Patterns indicating older NVIDIA architectures unsupported on Mint 22.x (kernel 6.14+)
FERMI_TESLA_PATTERNS = (
    r"\bG8[046]\b",
    r"\bG9[2468]\b",
    r"\bGT2\d{2}\b",
    r"\bGF1\d{2}\b",
    r"\bGeForce\s+(?:8\d{3}|9\d{3}|1\d0|2\d0|3\d0|4\d0|5\d0)\b",
    r"\bGeForce\s+(?:610|620|630|705|710A|810M|820M)\b",
    r"\bQuadro\s+(?:FX|NVS\s+[23]10|[123456]000M?)\b",
    r"\bNVS\s+(?:2100|3100|4200M|5200M|5400M)\b",
)

KEPLER_PATTERNS = (
    r"\bGK1\d{2}\b",
    r"\bGK208\b",
    r"\bGeForce\s+GTX\s+(?:6[56789]0|7[678]\d|780\s*Ti)M?\b",
    r"\bGeForce\s+GT\s+(?:6[345678]0|7[2345]0)M?\b",
    r"\bGeForce\s+(?:730M|740M|745M|750M|825M)\b",
    r"\bQuadro\s+K\d{3,4}M?\b",
)


@dataclass
class GpuDevice:
    slot: str
    vendor_id: str
    device_id: str
    description: str

    @property
    def vendor(self) -> str:
        mapping = {
            "10de": "nvidia",
            "8086": "intel",
            "1002": "amd",
            "1234": "qemu",
            "15ad": "vmware",
            "80ee": "virtualbox",
            "1af4": "virtio",
        }
        return mapping.get(self.vendor_id.lower(), f"unknown:{self.vendor_id}")


@dataclass
class DriverPlan:
    gpus: List[GpuDevice]
    is_optimus: bool
    nvidia_generation: str
    recommended_action: str  # install_official_nvidia | keep_nouveau_fallback | non_nvidia_mesa
    recommended_package: Optional[str]
    fallback_driver: str
    prime_mode: Optional[str]
    kernel_major_minor: Tuple[int, int]
    secure_boot_enabled: Optional[bool]
    warnings: List[str]
    notes: List[str]

    def to_dict(self) -> dict:
        data = asdict(self)
        data["kernel_version"] = f"{self.kernel_major_minor[0]}.{self.kernel_major_minor[1]}"
        return data


def parse_lspci(output: str) -> List[GpuDevice]:
    devices: List[GpuDevice] = []
    for line in output.splitlines():
        match = PCI_GPU_RE.search(line.strip())
        if not match:
            continue
        slot, desc, vid, did = match.groups()
        devices.append(
            GpuDevice(
                slot=slot,
                vendor_id=vid.lower(),
                device_id=did.lower(),
                description=desc.strip(),
            )
        )
    return devices


def parse_ubuntu_drivers_devices(output: str) -> List[Tuple[str, int, bool]]:
    """
    Returns list of (package_name, major_branch, is_recommended) from `ubuntu-drivers devices`
    or `ubuntu-drivers list`.
    """
    candidates: dict[str, Tuple[int, bool]] = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        m = DRIVER_VER_RE.search(line)
        if not m:
            continue
        pkg = m.group(1)
        branch = int(m.group(2))
        recommended = "recommended" in line.lower()
        prev = candidates.get(pkg)
        if prev is None or (recommended and not prev[1]):
            candidates[pkg] = (branch, recommended)
    return sorted(
        [(pkg, br, rec) for pkg, (br, rec) in candidates.items()],
        key=lambda item: (item[2], item[1], "-open" not in item[0]),
        reverse=True,
    )


def classify_nvidia_generation(description: str, available_branches: Sequence[int]) -> str:
    for pat in FERMI_TESLA_PATTERNS:
        if re.search(pat, description, re.IGNORECASE):
            return "tesla_or_fermi"
    for pat in KEPLER_PATTERNS:
        if re.search(pat, description, re.IGNORECASE):
            return "kepler"
    if available_branches:
        max_branch = max(available_branches)
        if max_branch <= 390:
            return "tesla_or_fermi"
        if max_branch <= 470:
            return "kepler"
        return "maxwell_or_newer"
    return "unknown_nvidia"


def parse_kernel_version(uname_r: str) -> Tuple[int, int]:
    m = re.match(r"^(\d+)\.(\d+)", uname_r.strip())
    if not m:
        return (6, 14)
    return (int(m.group(1)), int(m.group(2)))


def choose_driver_plan(
    lspci_output: str,
    ubuntu_drivers_output: str = "",
    kernel_release: str = "6.14.0",
    secure_boot_enabled: Optional[bool] = None,
) -> DriverPlan:
    gpus = parse_lspci(lspci_output)
    nvidia_gpus = [g for g in gpus if g.vendor == "nvidia"]
    igpus = [g for g in gpus if g.vendor in ("intel", "amd")]
    is_optimus = bool(nvidia_gpus and igpus)
    kver = parse_kernel_version(kernel_release)

    warnings: List[str] = []
    notes: List[str] = []

    if not nvidia_gpus:
        return DriverPlan(
            gpus=gpus,
            is_optimus=False,
            nvidia_generation="none",
            recommended_action="non_nvidia_mesa",
            recommended_package=None,
            fallback_driver="modesetting",
            prime_mode=None,
            kernel_major_minor=kver,
            secure_boot_enabled=secure_boot_enabled,
            warnings=warnings,
            notes=["NVIDIA GPU не обнаружена. Используются стандартные открытые драйверы ядра и Mesa."],
        )

    candidates = parse_ubuntu_drivers_devices(ubuntu_drivers_output)
    branches = [br for _, br, _ in candidates]
    primary_nv = nvidia_gpus[0]
    generation = classify_nvidia_generation(primary_nv.description, branches)

    if generation == "tesla_or_fermi":
        warnings.append(
            f"Обнаружен старый GPU NVIDIA ({primary_nv.description}) поколения Tesla/Fermi. "
            "Драйверы 340xx/390xx сняты с поддержки в Linux Mint 22.x / Ubuntu 24.04."
        )
        notes.append(
            "Безопасный выбор: оставить открытый драйвер nouveau (и iGPU при наличии Optimus) "
            "без принудительной установки несовместимого драйвера."
        )
        return DriverPlan(
            gpus=gpus,
            is_optimus=is_optimus,
            nvidia_generation=generation,
            recommended_action="keep_nouveau_fallback",
            recommended_package=None,
            fallback_driver="nouveau",
            prime_mode=None,
            kernel_major_minor=kver,
            secure_boot_enabled=secure_boot_enabled,
            warnings=warnings,
            notes=notes,
        )

    if generation == "kepler":
        warnings.append(
            f"Обнаружен GPU NVIDIA поколения Kepler ({primary_nv.description}). "
            "Ветка драйвера 470xx завершена (EOL) в Ubuntu 24.04 и несовместима со штатным ядром 6.14+."
        )
        notes.append(
            "Во избежание чёрного экрана система сохранит рабочий графический режим (nouveau/modesetting). "
            "При необходимости 470xx требуется ручной переход на LTS-ядро 6.8 (см. docs/06_RECOVERY_GUIDE.md)."
        )
        return DriverPlan(
            gpus=gpus,
            is_optimus=is_optimus,
            nvidia_generation=generation,
            recommended_action="keep_nouveau_fallback",
            recommended_package=None,
            fallback_driver="nouveau",
            prime_mode=None,
            kernel_major_minor=kver,
            secure_boot_enabled=secure_boot_enabled,
            warnings=warnings,
            notes=notes,
        )

    # Filter only supported modern branches (>= 535)
    modern_candidates = [c for c in candidates if c[1] >= 535]
    if not modern_candidates:
        warnings.append(
            f"Для GPU NVIDIA ({primary_nv.description}) официальный утилитой ubuntu-drivers не найден "
            "подходящий драйвер >= 535 в текущих репозиториях."
        )
        notes.append("Система сохранена на безопасном открытом драйвере nouveau.")
        return DriverPlan(
            gpus=gpus,
            is_optimus=is_optimus,
            nvidia_generation=generation,
            recommended_action="keep_nouveau_fallback",
            recommended_package=None,
            fallback_driver="nouveau",
            prime_mode=None,
            kernel_major_minor=kver,
            secure_boot_enabled=secure_boot_enabled,
            warnings=warnings,
            notes=notes,
        )

    chosen_pkg, chosen_branch, is_rec = modern_candidates[0]
    notes.append(
        f"Выбран официальный совместимый драйвер {chosen_pkg} "
        f"({'recommended' if is_rec else 'supported'}, ветка {chosen_branch})."
    )
    if secure_boot_enabled:
        warnings.append(
            "В UEFI включён Secure Boot: при установке проприетарного модуля NVIDIA потребуется "
            "регистрация MOK-ключа при перезагрузке либо отключение Secure Boot."
        )
    prime_mode = "on-demand" if is_optimus else None
    if is_optimus:
        notes.append(
            "Обнаружена гибридная графика (Optimus): рекомендуется режим prime-select on-demand "
            "для экономии 4 ГБ RAM и снижения нагрева на рабочем столе."
        )

    return DriverPlan(
        gpus=gpus,
        is_optimus=is_optimus,
        nvidia_generation=generation,
        recommended_action="install_official_nvidia",
        recommended_package=chosen_pkg,
        fallback_driver="nouveau",
        prime_mode=prime_mode,
        kernel_major_minor=kver,
        secure_boot_enabled=secure_boot_enabled,
        warnings=warnings,
        notes=notes,
    )


def _run_cmd(cmd: Iterable[str]) -> str:
    try:
        res = subprocess.run(list(cmd), capture_output=True, text=True, timeout=20, check=False)
        return (res.stdout or "") + "\n" + (res.stderr or "")
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""


def detect_live_system() -> DriverPlan:
    lspci_out = _run_cmd(["lspci", "-nn"])
    ud_out = _run_cmd(["ubuntu-drivers", "devices"])
    if not ud_out.strip():
        ud_out = _run_cmd(["ubuntu-drivers", "list"])
    uname_r = _run_cmd(["uname", "-r"]).strip() or "6.14.0"
    sb_out = _run_cmd(["mokutil", "--sb-state"]).lower()
    sb_enabled: Optional[bool] = None
    if "secureboot enabled" in sb_out:
        sb_enabled = True
    elif "secureboot disabled" in sb_out:
        sb_enabled = False
    return choose_driver_plan(lspci_out, ud_out, uname_r, sb_enabled)


def main() -> int:
    parser = argparse.ArgumentParser(description="EHOT OS GPU compatibility detector")
    parser.add_argument("--json", action="store_true", help="Output result as JSON")
    args = parser.parse_args()
    plan = detect_live_system()
    if args.json:
        print(json.dumps(plan.to_dict(), ensure_ascii=False, indent=2))
    else:
        print(f"GPU count: {len(plan.gpus)} | Optimus: {plan.is_optimus}")
        for g in plan.gpus:
            print(f"  - [{g.slot}] {g.vendor.upper()}: {g.description} [{g.vendor_id}:{g.device_id}]")
        print(f"Action: {plan.recommended_action} | Package: {plan.recommended_package or 'none'} | Fallback: {plan.fallback_driver}")
        for w in plan.warnings:
            print(f"WARNING: {w}")
        for n in plan.notes:
            print(f"NOTE: {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
