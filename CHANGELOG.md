# Changelog

## [1.0.0] - 2026-11-12
### Added
- Полная модульная архитектура EHOT OS на базе официальной Linux Mint 22.3 «Zena» XFCE (64-bit).
- Модуль `ehot-core`: ZRAM (`zstd`), 4 ГБ swapfile, `earlyoom`, оптимизация `sysctl`, автоподбор драйверов NVIDIA (включая обработку legacy-серий) и периферии, LibreOffice + Firefox.
- Модуль `ehot-gaming`: Steam, Proton, Wine (`wine-installer`), Lutris, GameMode, MangoHud, Vulkan и утилита диагностики `ehot-game-check`.
- Модуль `ehot-remote`: официальный AnyDesk + безопасная настройка постоянного доступа без хранения паролей в образе + локальный выключатель.
- Модуль `ehot-control`: Python-агент + отдельный модуль Telegram + Firefox MV3 WebExtension + Native Messaging для 4 событий (YouTube, загрузка файла, включение, выключение).
- Модуль `ehot-branding`: чёрно-фиолетовая тема XFCE/Plymouth/LightDM и слоты для графики маскота-енота с утилитой `ehot-apply-branding`.
- Модуль `ehot-installer`: безопасный установщик с защитой от форматирования USB-флешки и поддержкой UEFI + Legacy BIOS.
- Утилиты записи флешки `EHOT-USB-Creator` для Windows (`.exe`) и Linux.
- GitHub Actions CI/CD: автопроверки, сборка Windows `.exe`, полная сборка ISO + smoke-тест в QEMU.
