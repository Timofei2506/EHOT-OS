# EHOT OS

**EHOT OS** — воспроизводимая, лёгкая и модульная игровая/учебная сборка на базе **официальной Linux Mint 22.3 «Zena» XFCE (64-bit, LTS до апреля 2029)**, спроектированная специально под ноутбук Lenovo со слабым железом (**4 ГБ RAM, 1 ТБ HDD, неизвестная видеокарта NVIDIA и неизвестный CPU**).

> **Статус безопасности и честность проекта:**
> - Все сборки опираются исключительно на официальный образ Linux Mint 22.3 XFCE с проверкой `SHA-256` и `GPG`.
> - Пароли пользователя `Regzen`, пароль AnyDesk и секреты Telegram (`BOT_TOKEN`, `CHAT_ID`) **никогда не вшиваются в ISO и репозиторий** — они задаются владельцем локально при установке или первоначальной настройке.
> - Minecraft Launcher и Telegram Desktop **не предустанавливаются**.
> - Roblox официально **не поддерживается на Linux** (подробности и статус Sober — в `modules/ehot-gaming/README.md`).

---

## Архитектура проекта

Система разделена на независимые документированные модули:

1. **`modules/ehot-core`** — Базовая система, оптимизация под 4 ГБ RAM + HDD (`systemd-zram-generator` zstd, swapfile 4 ГБ, `earlyoom`, `sysctl`, очистка телеметрии), автоопределение драйверов NVIDIA (с учётом старых поколений и безопасным fallback на `nouveau`), Wi-Fi, Bluetooth, PipeWire/SOF звука, Firefox и LibreOffice (DOCX/PPTX/XLSX/ODT/ODP/ODS).
2. **`modules/ehot-gaming`** — Игровая подсистема: Steam, Proton, Wine (`wine-installer`), Lutris, GameMode, MangoHud (облегчённый пресет), Vulkan и инструмент диагностики совместимости `ehot-game-check`.
3. **`modules/ehot-remote`** — Удалённый доступ на базе AnyDesk (официальный APT-репозиторий `deb.anydesk.com`), автозапуск службы после установки ОС, мастер безопасной настройки постоянного доступа с отдельным паролем, уведомление о подключении и локальный переключатель `ehot-remote-toggle`.
4. **`modules/ehot-control`** — Лёгкий фоновый агент мониторинга и отдельный модуль интеграции с существующим Telegram-ботом. Отправляет **только 4 события**: старт просмотра YouTube (через WebExtension + Native Messaging без сбора истории остальных сайтов), начало загрузки файла (через Firefox Downloads API без чтения содержимого), включение ноутбука и выключение ноутбука (best-effort). Предусмотрено локальное отключение `ehot-control-toggle`.
5. **`modules/ehot-branding`** — Модульный чёрно-фиолетовый фирменный стиль EHOT OS (маскот-енот): GTK/XFWM4 тема, конфиги XFCE без тяжёлых эффектов, LightDM, Plymouth, GRUB2 и пустые документированные слоты `assets/` + утилита `ehot-apply-branding` для замены графики от дизайнерского ИИ-агента.
6. **`modules/ehot-installer`** — Безопасный полуавтоматический установщик с жёсткой проверкой диска (исключение USB-флешки Kingston DataTraveler, проверка модели/размера/интерфейса, явное подтверждение очистки 1 ТБ HDD, создание новой GPT-таблицы и разделов, установка Linux Mint XFCE + модулей EHOT OS, настройка GRUB для UEFI и Legacy BIOS, интерактивное создание пароля для `Regzen`).
7. **`tools/ehot-usb-creator-win`** — Программа для Windows (`.exe`, .NET 8 WinForms) для безопасной записи образа EHOT OS на флешку Kingston DataTraveler 64 ГБ с фильтром только съёмных USB-дисков, проверкой SHA-256, поддержкой многотомных релизных частей и верификацией записи.
8. **`tools/ehot-usb-creator-mac`** — Безопасный инструмент записи флешки для **macOS** (`EHOT-USB-Creator-macOS.command` / `ehot-write-usb-macos.sh`) на штатных утилитах (`diskutil`, `shasum`, `dd`): автосклейка `.part.*`, защита от системного диска Mac (`disk0`) и верификация записи.
9. **`tools/ehot-usb-creator-linux`** — Аналогичная безопасная утилита записи флешки под Linux.
10. **`build/`** — Конфигурация и скрипты воспроизводимой сборки гибридного UEFI+BIOS ISO с проверкой контрольных сумм и автотестом загрузки в QEMU.

---

## Быстрый старт

- Документация и техническая оценка: [`docs/01_TECHNICAL_ASSESSMENT.md`](docs/01_TECHNICAL_ASSESSMENT.md)
- Архитектура модулей: [`docs/02_ARCHITECTURE.md`](docs/02_ARCHITECTURE.md)
- Сборка ISO (локально и GitHub Actions): [`docs/03_ISO_BUILD_GUIDE.md`](docs/03_ISO_BUILD_GUIDE.md)
- Запись флешки из macOS, Windows или Linux (Kingston DataTraveler): [`docs/04_USB_FLASH_GUIDE.md`](docs/04_USB_FLASH_GUIDE.md)
- Установка на пустой Lenovo: [`docs/05_LENOVO_INSTALL_GUIDE.md`](docs/05_LENOVO_INSTALL_GUIDE.md)
- Восстановление и обновление: [`docs/06_RECOVERY_GUIDE.md`](docs/06_RECOVERY_GUIDE.md), [`docs/07_UPDATE_AND_MAINTENANCE.md`](docs/07_UPDATE_AND_MAINTENANCE.md)
- Безопасность б/у ноутбука и прошивки: [`docs/08_SECURITY_AND_FIRMWARE.md`](docs/08_SECURITY_AND_FIRMWARE.md)
