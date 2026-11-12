import pathlib
import subprocess

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MAC_SCRIPT = REPO_ROOT / "tools" / "ehot-usb-creator-mac" / "ehot-write-usb-macos.sh"
MAC_COMMAND = REPO_ROOT / "tools" / "ehot-usb-creator-mac" / "EHOT-USB-Creator-macOS.command"


def run_parse_test(disk_id: str, info_text: str, min_bytes: int = 3_741_319_168):
    return subprocess.run(
        ["bash", str(MAC_SCRIPT), "--self-test-parse", disk_id, info_text, str(min_bytes)],
        capture_output=True,
        text=True,
        check=False,
    )


SAMPLE_INTERNAL_APPLE_SSD = """   Device Identifier:         disk0
   Device Node:               /dev/disk0
   Whole:                     Yes
   Part of Whole:             disk0
   Device / Media Name:       APPLE SSD AP0512Q
   Volume Name:               Not applicable (no file system)
   Protocol:                  Apple Fabric
   Internal:                  Yes
   Virtual:                   No
   Removable Media:           Fixed
   Device Location:           Internal
   Disk Size:                 500.3 GB (500277792768 Bytes) (exactly 977105064 512-Byte-Units)
"""

SAMPLE_USB_KINGSTON = """   Device Identifier:         disk4
   Device Node:               /dev/disk4
   Whole:                     Yes
   Part of Whole:             disk4
   Device / Media Name:       DataTraveler 3.0
   Volume Name:               Not applicable (no file system)
   Protocol:                  USB
   Internal:                  No
   Virtual:                   No
   Removable Media:           Removable
   Device Location:           External
   Disk Size:                 62.0 GB (62016946176 Bytes) (exactly 121126848 512-Byte-Units)
"""

SAMPLE_VIRTUAL_DMG = """   Device Identifier:         disk5
   Device Node:               /dev/disk5
   Whole:                     Yes
   Part of Whole:             disk5
   Device / Media Name:       Disk Image
   Protocol:                  Disk Image
   Internal:                  No
   Virtual:                   Yes
   Removable Media:           Removable
   Device Location:           External
   Disk Size:                 10.0 GB (10000000000 Bytes)
"""

SAMPLE_SMALL_USB = """   Device Identifier:         disk3
   Device Node:               /dev/disk3
   Whole:                     Yes
   Part of Whole:             disk3
   Device / Media Name:       Tiny USB 2GB
   Protocol:                  USB
   Internal:                  No
   Virtual:                   No
   Removable Media:           Removable
   Device Location:           External
   Disk Size:                 2.0 GB (2000000000 Bytes)
"""

SAMPLE_THUNDERBOLT_FIXED_EXTERNAL = """   Device Identifier:         disk2
   Device Node:               /dev/disk2
   Whole:                     Yes
   Part of Whole:             disk2
   Device / Media Name:       LaCie Backup SSD
   Protocol:                  Thunderbolt
   Internal:                  No
   Virtual:                   No
   Removable Media:           Fixed
   Device Location:           External
   Disk Size:                 2.0 TB (2000000000000 Bytes)
"""


def test_mac_script_and_command_are_identical():
    assert MAC_SCRIPT.exists()
    assert MAC_COMMAND.exists()
    assert MAC_SCRIPT.read_bytes() == MAC_COMMAND.read_bytes()


def test_mac_curl_uses_http11_and_resume_to_avoid_http2_stream_error():
    txt = MAC_SCRIPT.read_text(encoding="utf-8")
    assert "--http1.1" in txt
    assert "-C -" in txt


def test_accepts_external_usb_flash_drive():
    res = run_parse_test("disk4", SAMPLE_USB_KINGSTON)
    assert res.returncode == 0, res.stdout + res.stderr
    assert res.stdout.strip() == "OK|disk4|DataTraveler 3.0|USB|62.0 GB"


def test_blocks_internal_disk0_and_internal_ssd():
    res0 = run_parse_test("disk0", SAMPLE_INTERNAL_APPLE_SSD)
    assert res0.returncode != 0
    assert "BLOCKED:disk0" in res0.stdout

    res_non_zero = run_parse_test("disk2", SAMPLE_INTERNAL_APPLE_SSD)
    assert res_non_zero.returncode != 0
    assert "BLOCKED:internal drive" in res_non_zero.stdout


def test_blocks_partition_slice_and_virtual_dmg_and_small_usb():
    res_slice = run_parse_test("disk4s1", SAMPLE_USB_KINGSTON)
    assert res_slice.returncode != 0
    assert "BLOCKED:invalid whole disk id" in res_slice.stdout

    res_dmg = run_parse_test("disk5", SAMPLE_VIRTUAL_DMG)
    assert res_dmg.returncode != 0
    assert "BLOCKED:virtual image" in res_dmg.stdout

    res_small = run_parse_test("disk3", SAMPLE_SMALL_USB)
    assert res_small.returncode != 0
    assert "BLOCKED:disk too small" in res_small.stdout


def test_blocks_external_non_usb_fixed_thunderbolt_drive():
    res_tb = run_parse_test("disk2", SAMPLE_THUNDERBOLT_FIXED_EXTERNAL)
    assert res_tb.returncode != 0
    assert "BLOCKED:not USB/removable" in res_tb.stdout


def test_verify_extracted_uefi_tree_checks_required_files_and_size(tmp_path):
    usb_dir = tmp_path / "EHOTUSB"
    (usb_dir / "EFI" / "boot").mkdir(parents=True)
    (usb_dir / "boot" / "grub").mkdir(parents=True)
    (usb_dir / "casper").mkdir(parents=True)
    (usb_dir / ".disk").mkdir(parents=True)

    (usb_dir / "EFI" / "boot" / "bootx64.efi").write_bytes(b"EFI")
    (usb_dir / "boot" / "grub" / "grub.cfg").write_text("menuentry EHOT {}\n", encoding="utf-8")
    (usb_dir / "casper" / "vmlinuz").write_bytes(b"KERNEL")
    (usb_dir / "casper" / "initrd.lz").write_bytes(b"INITRD")
    (usb_dir / ".disk" / "casper-uuid-generic").write_text("1234\n", encoding="utf-8")

    # Small/truncated squashfs must fail
    sq = usb_dir / "casper" / "filesystem.squashfs"
    sq.write_bytes(b"TINY")
    res_small = subprocess.run(
        ["bash", str(MAC_SCRIPT), "--self-test-verify-uefi", str(usb_dir)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert res_small.returncode != 0

    # Sparse 600 MB file simulates intact squashfs (>500 MB threshold)
    with open(sq, "wb") as fh:
        fh.truncate(600_000_000)
    res_ok = subprocess.run(
        ["bash", str(MAC_SCRIPT), "--self-test-verify-uefi", str(usb_dir)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert res_ok.returncode == 0, res_ok.stdout + res_ok.stderr


def test_reassemble_finds_parts_across_unzipped_sibling_folders(tmp_path):
    import hashlib

    dl = tmp_path / "Downloads"
    dir1 = dl / "EHOT-OS-v1.0.0-Part1"
    dir2 = dl / "EHOT-OS-v1.0.0-Part2-and-Tools"
    dir1.mkdir(parents=True)
    dir2.mkdir(parents=True)

    part1 = b"EHOT_PART_1_" * 128
    part2 = b"EHOT_PART_2_" * 128
    full = part1 + part2

    (dir1 / "ehot-os-22.3-xfce-amd64.iso.part.aa").write_bytes(part1)
    (dir2 / "ehot-os-22.3-xfce-amd64.iso.part.ab").write_bytes(part2)
    h1 = hashlib.sha256(part1).hexdigest()
    h2 = hashlib.sha256(part2).hexdigest()
    hfull = hashlib.sha256(full).hexdigest()
    (dir2 / "ehot-os-22.3-xfce-amd64.iso.parts.sha256").write_text(
        f"{h1}  ehot-os-22.3-xfce-amd64.iso.part.aa\n"
        f"{h2}  ehot-os-22.3-xfce-amd64.iso.part.ab\n",
        encoding="utf-8",
    )
    (dir2 / "ehot-os-22.3-xfce-amd64.iso.sha256").write_text(
        f"{hfull}  ehot-os-22.3-xfce-amd64.iso\n",
        encoding="utf-8",
    )

    res = subprocess.run(
        ["bash", str(MAC_SCRIPT), "--self-test-reassemble", str(dir2)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    out_iso = pathlib.Path(res.stdout.strip())
    assert out_iso.exists()
    assert out_iso.read_bytes() == full


def test_reassemble_rejects_lonely_part_aa_without_part_ab(tmp_path):
    dl = tmp_path / "Downloads"
    dl.mkdir(parents=True)
    (dl / "ehot-os-22.3-xfce-amd64.iso.part.aa").write_bytes(b"HALF_ONLY")

    res = subprocess.run(
        ["bash", str(MAC_SCRIPT), "--self-test-reassemble", str(dl)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert res.returncode == 1
    assert not (dl / "ehot-os-22.3-xfce-amd64.iso").exists()

