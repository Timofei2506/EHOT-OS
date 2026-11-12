# EHOT OS Core (`ehot-core`)

Базовый модуль операционной системы EHOT OS на основе **Linux Mint 22.3 «Zena» XFCE (64-bit)**.

## Состав модуля
- **Официальная база и обновления**: сохраняет стандартные репозитории Linux Mint (`zena`) и Ubuntu 24.04 (`noble`), обновления через `apt` / `mintupdate`, AppArmor и UFW.
- **Память (4 ГБ RAM + 1 ТБ HDD)**:
  - `systemd-zram-generator`: сжатый swap в RAM (`zram0`, `zstd`, размер `= RAM`, приоритет `100`).
  - Дисковый `/swapfile` 4 ГБ с низким приоритетом (`10`) — создаётся на целевом HDD при установке (не вшивается в ISO).
  - `earlyoom`: предотвращает многоминутные зависания при исчерпании 4 ГБ RAM.
  - `sysctl` (`99-ehot-sysctl.conf`): `vm.swappiness=100`, `vm.page-cluster=0`, ограничение буфера грязных страниц на HDD (`16M`/`64M`) для плавного интерфейса.
- **Оптимизация служб (`optimize-services.sh`)**: ограничивает размер журнала systemd до `50M`, отключает сбор телеметрии/отчётов о сбоях (`apport`, `whoopsie`, если присутствуют) без отключения защиты и обновлений.
- **Оборудование и драйверы (`drivers/`)**:
  - `gpu_detect.py` — детерминированный классификатор NVIDIA/Intel/AMD/Optimus с проверкой совместимости драйверов и защитой старых поколений GPU (Fermi/Tesla/Kepler) от принудительной установки несовместимого драйвера.
  - `ehot-driver-setup.sh` — установка официальных прошивок и драйверов (GPU, Wi-Fi, Bluetooth, звук PipeWire + SOF) без сомнительных PPA.
- **Предустановленное ПО**: Mozilla Firefox (шаблон `policies.json`), LibreOffice (DOCX, PPTX, XLSX, ODT, ODP, ODS + русский пакет).

## Что НЕ устанавливается
Minecraft Launcher и Telegram Desktop жёстко исключены (контролируется автотестами и `manifest.json`).
