# EHOT USB Creator для macOS (`ehot-write-usb-macos.sh` / `EHOT-USB-Creator-macOS.command`)

Безопасный скрипт записи загрузочной флешки **Kingston DataTraveler 64 ГБ** с компьютера на **macOS** (Apple Silicon M1/M2/M3/M4 и Intel Mac), не требующий установки Homebrew, Xcode или сторонних утилит.

## Возможности безопасности
- При наличии томов `ehot-os-22.3-xfce-amd64.iso.part.aa`, `.part.ab`, `.part.ac` в той же папке автоматически проверяет `ehot-os-22.3-xfce-amd64.iso.parts.sha256` (через встроенный `shasum -a 256`), склеивает их в `.iso` и проверяет `ehot-os-22.3-xfce-amd64.iso.sha256`.
- Получает список устройств **строго** через `diskutil list external physical` и проверяет через `diskutil info`:
  - `Whole: Yes`
  - `Internal: No` и `Device Location: External`
  - `Virtual: No` (исключает `.dmg` / образы дисков)
  - `Protocol: USB` или съёмный носитель
  - объём диска `>= размеру ISO`
  - системный диск Mac `/dev/disk0` заблокирован жёстко.
- Запрашивает явное текстовое подтверждение **`YES`** с показом модели и объёма флешки.
- Размонтирует флешку через `diskutil unmountDisk`, записывает напрямую в быстрый raw-девайс `/dev/r<disk>` (`bs=4m`), сверяет контрольную сумму первых **8 МиБ** и безопасно извлекает (`diskutil eject`).

## Использование на macOS

### Вариант 1: Через Терминал (самый надёжный, без предупреждений Gatekeeper)
Скачайте в **одну папку** (например `Загрузки`) файлы релиза `v1.0.0`:
- `EHOT-USB-Creator-macOS.command`
- `ehot-os-22.3-xfce-amd64.iso.part.aa`, `.part.ab`, `.part.ac`
- `ehot-os-22.3-xfce-amd64.iso.sha256`, `ehot-os-22.3-xfce-amd64.iso.parts.sha256`

Затем откройте **Терминал** и выполните:
```bash
cd ~/Downloads
bash EHOT-USB-Creator-macOS.command
```

### Вариант 2: Двойной клик в Finder
1. Сделайте `chmod +x ~/Downloads/EHOT-USB-Creator-macOS.command` (или нажмите правой кнопкой мыши -> **Открыть** -> подтвердите запуск в окне macOS Gatekeeper).
2. При вопросе введите пароль пользователя Mac (символы при вводе `sudo` на экране не отображаются — это нормально) и подтвердите флешку вводом `YES`.

### Альтернатива с графическим интерфейсом на macOS: BalenaEtcher
1. Сначала склейте тома и проверьте контрольную сумму в Терминале:
   ```bash
   cd ~/Downloads
   shasum -a 256 -c ehot-os-22.3-xfce-amd64.iso.parts.sha256
   cat ehot-os-22.3-xfce-amd64.iso.part.* > ehot-os-22.3-xfce-amd64.iso
   shasum -a 256 -c ehot-os-22.3-xfce-amd64.iso.sha256
   ```
2. Откройте **BalenaEtcher** для macOS, выберите `ehot-os-22.3-xfce-amd64.iso`, выберите `Kingston DataTraveler` и нажмите **Flash!**.
