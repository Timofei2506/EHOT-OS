# EHOT OS Gaming (`ehot-gaming`)

Игровая подсистема EHOT OS, настроенная с учётом слабого оборудования (**4 ГБ RAM + HDD + неизвестная NVIDIA/CPU**).

## Установленные компоненты
- **Steam + Proton**: `steam-installer` + 32-битные библиотеки `i386`.
- **Wine + Winetricks**: `wine-installer` (официальный метапакет Linux Mint 22.3) + `wine32` + `winetricks`.
- **Lutris**: единая библиотека игр и префиксов.
- **GameMode**: `gamemode` + профиль `/etc/gamemode.ini` (переключение CPU governor в `performance`, приоритет I/O для HDD).
- **MangoHud**: `mangohud` с компактным пресетом (`~/.config/MangoHud/MangoHud.conf` — FPS, frametime, RAM, Swap, CPU/GPU).
- **Vulkan + OpenGL**: `vulkan-tools`, `libvulkan1`, `libvulkan1:i386`, `mesa-vulkan-drivers`, `mesa-vulkan-drivers:i386`.
- **OpenJDK JRE**: `default-jre` для совместимости с Java-играми (в т.ч. Minecraft после самостоятельной установки лаунчера).

> **Примечание по составу ПО**: Minecraft Launcher и Telegram Desktop **не предустанавливаются** согласно ТЗ.

---

## Совместимость целевых игр

### 1. Steam-игры и Proton
- На 4 ГБ RAM рекомендуется запускать инди-игры, классику и лёгкие проекты, закрывая Firefox перед запуском игры (или используя GameMode).
- Рекомендуемые параметры запуска в Steam для тяжёлых/нестабильных игр: `gamemoderun %command%` (или с оверлеем: `MANGOHUD=1 gamemoderun %command%`).
- На HDD при первой загрузке шейдеров возможны паузы; отключать Shader Pre-Caching стоит только при нехватке места, а при 4 ГБ RAM важно не держать параллельно открытым браузер с десятками вкладок.

### 2. Minecraft (Java Edition)
- Работает на Linux нативно при установке пользователем выбранного лаунчера.
- При 4 ГБ RAM выделяйте JVM не более `-Xmx2048M` (2 ГБ), чтобы не вызывать свопинг на HDD.
- На старых GPU NVIDIA (под `nouveau`) может требоваться более лёгкий набор модов оптимизации (Sodium/Lithium) — зависит от версии OpenGL конкретного GPU.

### 3. Roblox (честный статус на 2026 год)
- **Roblox официально НЕ поддерживает Linux.** Гарантированная работа не обещана.
- Классические способы запуска Windows-клиента через Wine/Proton (**Vinegar / Grapejuice**) не работают с марта 2024 года из-за античита Hyperion/Byfron. **Попытки обхода античита в EHOT OS не применяются и не поддерживаются.**
- Актуальный неофициальный способ в 2026 году — проект сообщества **Sober** (`org.vinegarhq.Sober` в Flathub), запускающий официальный Android-клиент Roblox нативно.
- **Требования Sober**: процессор `x86_64` с поддержкой `SSE4.1` и видеокарта с `OpenGL ES 3.0` / желательно `Vulkan 1.1+`.
- **Roblox Studio** на Linux нативно не работает.
- Проверить совместимость конкретного ноутбука можно командой: `ehot-game-check`.
- Если владелец решит попробовать Sober добровольно (на свой риск, так как проект неофициальный и может перестать работать после обновлений Roblox), установка выполняется вручную из Flathub:
  ```bash
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install flathub org.vinegarhq.Sober
  ```
