# 3. Инструкция по сборке ISO-образа EHOT OS

## Вариант А: Автоматическая сборка в GitHub Actions (рекомендуется)
1. В приватном репозитории `Timofei2506/EHOT-OS` откройте вкладку **Actions** -> **Build EHOT OS ISO**.
2. Нажмите **Run workflow** (укажите тег версии, например `v1.0.0`, и опцию публикации релиза).
3. Pipeline автоматически:
   - скачивает официальный `linuxmint-22.3-xfce-64bit.iso` с зеркал `kernel.org` / `linuxmint.io`;
   - сверяет контрольную сумму **SHA-256** (`45a835b5dddaf40e84d776549e9f0b19b3fbd49673b6cc6434ebddbfcd217df76`) и **GPG-подпись** Linux Mint;
   - распаковывает `filesystem.squashfs`, устанавливает все 6 модулей EHOT OS в изолированном `chroot`;
   - пересобирает гибридный ISO (UEFI + Legacy BIOS) через `xorriso`;
   - тестирует загрузку ISO в **QEMU** (BIOS и UEFI OVMF);
   - так как размер ISO (~3.5 ГБ) превышает лимит GitHub Releases в 2 ГБ на один файл, образ нарезается на части по `1500 МиБ` (`ehot-os-22.3-xfce-amd64.iso.part.aa`, `.part.ab`, ...), сопровождается файлом `ehot-os-22.3-xfce-amd64.iso.sha256` и публикуется в **GitHub Releases** вместе с `EHOT-USB-Creator-win-x64.exe` и `reassemble.bat`.

> **Важно**: программа `EHOT-USB-Creator-win-x64.exe` умеет принимать как цельный `.iso`, так и первый том `.iso.part.aa` напрямую (без ручной склейки). При желании склеить на Windows вручную запустите `reassemble.bat` или `copy /b ehot-os-22.3-xfce-amd64.iso.part.* ehot-os-22.3-xfce-amd64.iso`.

---

## Вариант Б: Локальная сборка на машине с Ubuntu / Debian / Linux Mint
Требования: x86_64 Linux, `>= 25 ГБ` свободного места на диске, `>= 4 ГБ` RAM, root-доступ.

1. Установите зависимости сборки:
   ```bash
   sudo apt update
   sudo apt install -y xorriso squashfs-tools curl gnupg python3 jq qemu-system-x86 ovmf
   ```
2. (Опционально) Положите финальную графику от дизайнера в `modules/ehot-branding/assets/` согласно `modules/ehot-branding/BRANDING_SPEC.md`.
3. (Опционально) Подпишите расширение Firefox через AMO unlisted и вставьте URL/путь XPI в `modules/ehot-core/config/firefox-policies.json`.
4. Запустите сборку:
   ```bash
   sudo bash build/scripts/build-iso.sh
   ```
5. Результат появится в `build/output/ehot-os-22.3-xfce-amd64.iso` и `build/output/ehot-os-22.3-xfce-amd64.iso.sha256`.
6. Запустите проверку образа в виртуальной машине QEMU:
   ```bash
   bash build/scripts/test-iso-qemu.sh build/output/ehot-os-22.3-xfce-amd64.iso
   ```
