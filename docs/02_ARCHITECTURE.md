# 2. Архитектура проекта EHOT OS

Проект построен по модульному принципу: каждый компонент изолирован в собственном каталоге `modules/<имя>`, имеет независимые скрипты установки/настройки и собственную документацию.

```
EHOT-OS/
├── modules/
│   ├── ehot-core/       # Ядро конфигурации: ZRAM, swap, sysctl, earlyoom, драйверы, LibreOffice, Firefox
│   ├── ehot-gaming/     # Игровая подсистема: Steam, Proton, Wine, Lutris, GameMode, MangoHud, Vulkan
│   ├── ehot-remote/     # Удалённое управление: AnyDesk (офиц. репо), настройка пароля, переключатель
│   ├── ehot-control/    # Мониторинг (4 события) + отдельный модуль Telegram + Firefox WebExtension
│   ├── ehot-branding/   # Чёрно-фиолетовый стиль, тема XFCE/Plymouth/LightDM, слоты под графику енота
│   └── ehot-installer/  # Безопасный установщик с защитой от форматирования USB и поддержкой UEFI+BIOS
├── build/               # Воспроизводимая сборка гибридного ISO на базе Mint 22.3 XFCE
├── tools/
│   ├── ehot-usb-creator-win/   # Программа для Windows (.exe) записи флешки Kingston DataTraveler
│   └── ehot-usb-creator-linux/ # Скрипт записи флешки из-под Linux
├── tests/               # Модульные, интеграционные и политические автотесты
└── .github/workflows/   # CI/CD: проверки, сборка Windows .exe, сборка ISO + QEMU-тест
```

## Границы доверия и безопасность между модулями
1. **Изоляция секретов `ehot-control`**:
   - Токен бота и `TELEGRAM_CHAT_ID` хранятся в `/etc/ehot-control/secrets.env` (`chmod 600`, владелец `ehotcontrol`).
   - Расширение Firefox и `ehot_native_host.py` работают от пользователя `Regzen` и передают только разрешённые события (`youtube_start`, `download_start`) в сокет `/run/ehot-control/events.sock` — они **не имеют доступа** к секретам Telegram.
2. **Изоляция пароля AnyDesk**:
   - В `ehot-remote` и в ISO пароль отсутствует. Настройка выполняется локально владельцем через `sudo ehot-remote-setup` (передача пароля напрямую через `stdin` в `anydesk --set-password`).
3. **Изоляция учётной записи `Regzen`**:
   - Пользователь создаётся при установке ОС на целевой диск; пароль задаёт владелец в интерактивном диалоге.
4. **Независимость графики (`ehot-branding`)**:
   - Все ассеты (логотип енота, обои, иконка меню, иконки, Plymouth) хранятся в `modules/ehot-branding/assets/` и применяются командой `ehot-apply-branding` без пересборки скриптов логики.
