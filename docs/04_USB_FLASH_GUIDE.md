# 4. Инструкция записи ISO на Kingston DataTraveler 64 ГБ (macOS, Windows, Linux)

---

## Запись на macOS (MacBook / iMac / Mac mini)

> **Важно про многотомный образ:** в GitHub Release файл ISO разбит на 3 части (`part.aa`, `part.ab`, `part.ac`), чтобы уложиться в лимит GitHub 2 ГБ на файл. Не пытайтесь записывать `.part.aa` напрямую — части нужно сначала склеить (наш скрипт для macOS делает это сам!).

### Способ A: Фирменный безопасный скрипт `EHOT-USB-Creator-macOS.command` (рекомендуется)
Работает на **Apple Silicon (M1/M2/M3/M4)** и **Intel Mac** без установки сторонних программ (использует только встроенные `diskutil`, `shasum`, `dd`, `cat`).

1. Скачайте из **GitHub Releases** (или получите от друга) в **одну папку** (например `Загрузки` / `Downloads`):
   - `EHOT-USB-Creator-macOS.command`
   - `ehot-os-22.3-xfce-amd64.iso.part.aa`
   - `ehot-os-22.3-xfce-amd64.iso.part.ab`
   - `ehot-os-22.3-xfce-amd64.iso.part.ac`
   - `ehot-os-22.3-xfce-amd64.iso.sha256`
   - `ehot-os-22.3-xfce-amd64.iso.parts.sha256`
2. Вставьте флешку **Kingston DataTraveler 64 ГБ** в Mac (через USB-A или переходник USB-C -> USB-A). Если macOS спросит «Разрешить подключение аксессуара?» — нажмите **Разрешить**.
3. Откройте программу **Терминал** (`Cmd + Пробел` -> `Terminal`) и выполните:
   ```bash
   cd ~/Downloads
   bash EHOT-USB-Creator-macOS.command
   ```
   *(Альтернативно: правый клик по `EHOT-USB-Creator-macOS.command` в Finder -> **Открыть**, чтобы обойти предупреждение Gatekeeper.)*
4. Скрипт автоматически:
   - проверит SHA-256 всех 3 частей, склеит их в `ehot-os-22.3-xfce-amd64.iso` и сверит SHA-256 итогового образа;
   - покажет **только внешние физические USB-флешки** (внутренний SSD Mac `disk0` и виртуальные `.dmg` заблокированы жёстко);
   - попросит выбрать номер вашей флешки Kingston DataTraveler и подтвердить очистку словом **`YES`**;
   - запросит пароль от учётной записи Mac (для `sudo` — при вводе звёздочки не отображаются, просто введите пароль и нажмите Enter);
   - запишет образ через быстрый `/dev/rdiskN` (`bs=4m`), сверит первые **8 МиБ** и безопасно извлечёт флешку (`diskutil eject`).
   *(Во время записи в Терминале можно нажимать `Ctrl + T`, чтобы увидеть сколько мегабайт уже записалось — запись 3.5 ГБ занимает обычно 2–5 минут.)*

### Способ B: Графический способ на macOS через BalenaEtcher
Если удобнее кликать в окне:
1. Скачайте 3 части `.part.*` и `.sha256` в `~/Downloads`, откройте **Терминал** и склейте образ:
   ```bash
   cd ~/Downloads
   shasum -a 256 -c ehot-os-22.3-xfce-amd64.iso.parts.sha256
   cat ehot-os-22.3-xfce-amd64.iso.part.* > ehot-os-22.3-xfce-amd64.iso
   shasum -a 256 -c ehot-os-22.3-xfce-amd64.iso.sha256
   ```
   Убедитесь, что в конце написано `ehot-os-22.3-xfce-amd64.iso: OK`.
2. Установите бесплатную программу **BalenaEtcher** для macOS (есть версии под Apple Silicon и Intel).
3. В BalenaEtcher выберите **Flash from file** -> `ehot-os-22.3-xfce-amd64.iso`, выберите **Select target** -> `Kingston DataTraveler` -> **Flash!**.

---

## Запись на Windows

### Способ 1: Фирменная утилита `EHOT-USB-Creator-win-x64.exe` (рекомендуется)
1. Скачайте из **GitHub Releases**:
   - `EHOT-USB-Creator-win-x64.exe`
   - либо цельный `ehot-os-22.3-xfce-amd64.iso`, либо все части `ehot-os-22.3-xfce-amd64.iso.part.*` + файл `ehot-os-22.3-xfce-amd64.iso.sha256` в **одну папку**.
2. Вставьте флешку **Kingston DataTraveler 64 ГБ** в USB-порт компьютера на Windows.
3. Запустите `EHOT-USB-Creator-win-x64.exe` (подтвердите запрос прав администратора UAC).
4. Нажмите **«Выбрать ISO...»** и укажите `.iso` (или первый файл `.iso.part.aa` — остальные части и `.sha256` подхватятся автоматически).
5. В выпадающем списке USB-накопителей выберите ваш **Kingston DataTraveler** (внутренние диски Windows скрыты защитой и не могут быть выбраны).
6. Отметьте галочку подтверждения полного удаления данных на флешке и нажмите **«Записать EHOT OS на флешку»**.
7. Дождитесь завершения проверки SHA-256, записи и контрольного чтения первых 8 МиБ.
8. Нажмите «Безопасное извлечение устройства» в трее Windows и вытащите флешку.

### Способ 2: Альтернатива через Rufus (Windows)
1. При необходимости склейте многотомный ISO в папке с частями:
   ```cmd
   copy /b ehot-os-22.3-xfce-amd64.iso.part.* ehot-os-22.3-xfce-amd64.iso
   certutil -hashfile ehot-os-22.3-xfce-amd64.iso SHA256
   ```
   Сравните полученный хеш со значением в файле `ehot-os-22.3-xfce-amd64.iso.sha256`.
2. Откройте **Rufus**, выберите устройство **Kingston DataTraveler**, выберите `ehot-os-22.3-xfce-amd64.iso`.
3. При вопросе Rufus выберите режим **«Записать в режиме DD-образа» (DD Image mode)** — это гарантирует гибридную загрузку и на UEFI, и на старом Legacy BIOS Lenovo.

---

## Запись на Linux
```bash
bash reassemble.sh
sudo bash tools/ehot-usb-creator-linux/ehot-write-usb.sh ehot-os-22.3-xfce-amd64.iso
```
Скрипт проверяет `TRAN=usb`, `RM=1` и `SHA-256` перед записью.
