import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "modules" / "ehot-core" / "drivers"))

from gpu_detect import choose_driver_plan  # noqa: E402


def test_modern_nvidia_optimus_selects_official_driver_and_prime():
    lspci = """
00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics 620 [8086:5917] (rev 07)
01:00.0 3D controller [0302]: NVIDIA Corporation GP108M [GeForce MX150] [10de:1d10] (rev a1)
"""
    ud = """
driver   : nvidia-driver-550 - distro non-free recommended
driver   : nvidia-driver-535 - distro non-free
driver   : xserver-xorg-video-nouveau - distro free builtin
"""
    plan = choose_driver_plan(lspci, ud, kernel_release="6.14.0-20-generic", secure_boot_enabled=False)
    assert plan.is_optimus is True
    assert plan.recommended_action == "install_official_nvidia"
    assert plan.recommended_package == "nvidia-driver-550"
    assert plan.prime_mode == "on-demand"


def test_legacy_fermi_falls_back_to_nouveau_safely():
    lspci = """
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GF116 [GeForce GTX 550 Ti] [10de:1244] (rev a1)
"""
    plan = choose_driver_plan(lspci, "", kernel_release="6.14.0-20-generic")
    assert plan.nvidia_generation == "tesla_or_fermi"
    assert plan.recommended_action == "keep_nouveau_fallback"
    assert plan.recommended_package is None
    assert plan.fallback_driver == "nouveau"


def test_legacy_kepler_avoids_retired_470_on_kernel_614():
    lspci = """
00:02.0 VGA compatible controller [0300]: Intel Corporation 4th Gen Core Processor Integrated Graphics [8086:0416]
01:00.0 3D controller [0302]: NVIDIA Corporation GK208M [GeForce GT 740M] [10de:1292] (rev a1)
"""
    ud = """
driver   : nvidia-driver-470 - distro non-free recommended
"""
    plan = choose_driver_plan(lspci, ud, kernel_release="6.14.0-20-generic")
    assert plan.nvidia_generation == "kepler"
    assert plan.recommended_action == "keep_nouveau_fallback"
    assert plan.recommended_package is None
    assert any("Kepler" in w or "470" in w for w in plan.warnings)


def test_secure_boot_adds_mok_warning():
    lspci = "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117M [GeForce GTX 1650 Mobile] [10de:1f91]\n"
    ud = "driver   : nvidia-driver-570-open - distro non-free recommended\n"
    plan = choose_driver_plan(lspci, ud, kernel_release="6.14.0", secure_boot_enabled=True)
    assert plan.recommended_action == "install_official_nvidia"
    assert any("Secure Boot" in w for w in plan.warnings)


def test_intel_only_uses_mesa():
    lspci = "00:02.0 VGA compatible controller [0300]: Intel Corporation Iris Xe Graphics [8086:9a49]\n"
    plan = choose_driver_plan(lspci, "")
    assert plan.recommended_action == "non_nvidia_mesa"
    assert plan.recommended_package is None
