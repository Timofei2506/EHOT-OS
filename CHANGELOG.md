# Changelog

## [Unreleased]
### Added
- Вторая редакция сборки: **MfiSerli OS (public)** через `build-iso.sh --edition public` — та же оптимизированная база Linux Mint 22.3 XFCE, но без личных модулей контроля/удалённого доступа и с новым дизайном «Dark Glass» (тема GTK/xfwm4 `MfiSerli-Dark-Glass`, dock-панель снизу `p=12`, обои «Aurora Glass» 3840×2160 + вариант для экрана входа, логотип-плитка «M», стеклянная Plymouth-тема, фон LightDM).
- `build/config/edition-public.conf` + проброс редакции в chroot (`edition-active.conf`, `EHOT_EDITION`), редакционно-осведомлённые GRUB/ISOLINUX метки и `.disk/info`.
- `modules/ehot-installer/ehot-edition.py` — редакционная идентичность установщика в рантайме (имя ОС, метки разделов `MFISERLI_ROOT`/`MFISERLIEFI`, bootloader-id, имя пользователя `user`, hostname `mfiserli-pc`); без конфига поведение идентично EHOT OS v1.0.0.
- `ehot-firstboot.sh` создаёт напоминание о личной настройке только при наличии соответствующих helper-скриптов (публичная редакция их не содержит).
- CI workflow `build-iso.yml`: поле `edition` (kent/public) с автоматической подстановкой имён ISO/ZIP (`MfiSerli-OS-vX.Y.Z-*.zip`).
- `tests/test_public_edition.py` (10 тестов): публичная редакция не ссылается на личные модули, kent-only ветки в chroot, 4K-обои и все ассеты темы, стабильные дефолты установщика, dock снизу и брендинг установщика MfiSerli.

### Changed
- `build/scripts/build-iso.sh`: флаг `--edition kent|public` (по умолчанию kent, поведение v1.0.0 не изменилось).
- `build/chroot/customize-rootfs.sh`: редакционные ветки установки модулей, брендинга, релиз-файла (`/etc/ehot-os-release` либо `/etc/mfiserli-os-release`) и `/etc/ehot-edition.conf`.

## [MfiSerli OS 1.0.0] - 2026-11-17
### Released
- Первый публичный релиз MfiSerli OS 1.0.0 (public edition): https://github.com/Timofei2506/EHOT-OS/releases/tag/mfiserli-os-v1.0.0
- ISO `mfiserli-os-22.3-xfce-amd64.iso` (SHA-256 `6d57cf7e…5662d7f`), 2 части + `reassemble.{bat,sh}` + `EHOT-USB-Creator-macOS-MfiSerli.command`.
- Проверено в QEMU: BIOS + UEFI загрузка, volume `MFISERLI_22_3`.
- `download-mint-iso.sh`: докачка с `-C -`, HTTP/1.1, детект stall и ротация зеркал.

## [1.0.0] - 2026-11-12
### Added
- Полная модульная архитектура EHOT OS на базе официальной Linux Mint 22.3 «Zena» XFCE (64-bit).
- Модуль `ehot-core`: ZRAM (`zstd`), 4 ГБ swapfile, `earlyoom`, оптимизация `sysctl`, автоподбор драйверов NVIDIA (включая обработку legacy-серий) и периферии, LibreOffice + Firefox.
- Модуль `ehot-gaming`: Steam, Proton, Wine (`wine-installer`), Lutris, GameMode, MangoHud, Vulkan и утилита диагностики `ehot-game-check`.
- Модуль `ehot-remote`: официальный AnyDesk + безопасная настройка постоянного доступа без хранения паролей в образе + локальный выключатель.
- Модуль `ehot-control`: Python-агент + отдельный модуль Telegram + Firefox MV3 WebExtension + Native Messaging для 4 событий (YouTube, загрузка файла, включение, выключение).
- Модуль `ehot-branding`: чёрно-фиолетовая тема XFCE/Plymouth/LightDM и слоты для графики маскота-енота с утилитой `ehot-apply-branding`.
- Модуль `ehot-installer`: безопасный установщик с защитой от форматирования USB-флешки и поддержкой UEFI + Legacy BIOS.
- Утилиты записи флешки `EHOT-USB-Creator` для Windows (`.exe`), macOS (`.command` / `.sh`) и Linux.
- GitHub Actions CI/CD: автопроверки, сборка Windows `.exe`, полная сборка ISO + smoke-тест в QEMU.
