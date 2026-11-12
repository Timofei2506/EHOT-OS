# Сборка загрузочного ISO-образа EHOT OS

Скрипты в этом каталоге собирают воспроизводимый гибридный (UEFI + Legacy BIOS) образ **EHOT OS** на основе официального **Linux Mint 22.3 «Zena» XFCE 64-bit**.

## Этапы сборки (`scripts/build-iso.sh`)
1. `download-mint-iso.sh` скачивает официальный `linuxmint-22.3-xfce-64bit.iso`, `sha256sum.txt` и `sha256sum.txt.gpg` с официального зеркала.
2. Проверяет **SHA-256** (`45a835b5dddaf40e84d776549e9f0b19b3fbd49673b6cc6434ebddbfcd217df76`) и **GPG-подпись** ключом Linux Mint (`27DEB15644C6B3CF3BD7D291300F846BA25BAE09`).
3. Распаковывает содержимое ISO и `casper/filesystem.squashfs`.
4. В изолированном `chroot` запускает `build/chroot/customize-rootfs.sh`, устанавливающий модули `ehot-core`, `ehot-gaming`, `ehot-remote`, `ehot-control`, `ehot-branding`, `ehot-installer`.
5. Очищает кэши `apt` и временные файлы, пересобирает `filesystem.squashfs` (`zstd`), обновляет `filesystem.size`, `filesystem.manifest` и `md5sum.txt`.
6. Воспроизводит точную гибридную загрузочную структуру UEFI + BIOS оригинального образа через `xorriso -report_el_torito as_mkisofs` и записывает финальный `ehot-os-22.3-xfce-amd64.iso` + `.sha256`.
7. `test-iso-qemu.sh` проверяет загрузку ISO в QEMU (Legacy BIOS и UEFI OVMF).
