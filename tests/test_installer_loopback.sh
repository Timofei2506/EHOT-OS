#!/usr/bin/env bash
set -euo pipefail

export PATH="$PATH:/usr/sbin:/sbin"

# Integration test for GPT partitioning logic using a sparse temporary image file
# (NO physical block device is touched!).

TMP_IMG="$(mktemp --suffix=.img)"
trap 'rm -f "$TMP_IMG"' EXIT

truncate -s 700M "$TMP_IMG"

sgdisk --zap-all "$TMP_IMG" >/dev/null
sgdisk --clear "$TMP_IMG" >/dev/null
sgdisk -n "1:2048:+1M" -t "1:EF02" -c "1:BIOS_GRUB" "$TMP_IMG" >/dev/null
sgdisk -n "2:0:+512M" -t "2:EF00" -c "2:EFI_SYS" "$TMP_IMG" >/dev/null
sgdisk -n "3:0:0" -t "3:8300" -c "3:EHOT_ROOT" "$TMP_IMG" >/dev/null

PART_OUT="$(sgdisk -p "$TMP_IMG")"
echo "$PART_OUT" | grep -q "EF02"
echo "$PART_OUT" | grep -q "EF00"
echo "$PART_OUT" | grep -q "8300"
echo "$PART_OUT" | grep -q "EHOT_ROOT"
echo "[test_installer_loopback] GPT hybrid UEFI+BIOS partition layout verified OK."
