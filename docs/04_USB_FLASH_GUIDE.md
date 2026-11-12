# 4. Инструкция записи ISO на Kingston DataTraveler 64 ГБ (на Windows)

## Способ 1: Фирменная утилита `EHOT-USB-Creator-win-x64.exe` (рекомендуется)
Утилита собирается автоматически в GitHub Actions / Releases вместе с образом.

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

---

## Способ 2: Альтернатива через Rufus (если используется Windows без нашей утилиты)
1. При необходимости склейте многотомный ISO в папке с частями:
   ```cmd
   copy /b ehot-os-22.3-xfce-amd64.iso.part.* ehot-os-22.3-xfce-amd64.iso
   certutil -hashfile ehot-os-22.3-xfce-amd64.iso SHA256
   ```
   Сравните полученный хеш со значением в файле `ehot-os-22.3-xfce-amd64.iso.sha256`.
2. Откройте **Rufus**, выберите устройство **Kingston DataTraveler**, выберите `ehot-os-22.3-xfce-amd64.iso`.
3. При вопросе Rufus выберите режим **«Записать в режиме DD-образа» (DD Image mode)** — это гарантирует гибридную загрузку и на UEFI, и на старом Legacy BIOS Lenovo.

---

## Способ 3: Запись из-под Linux
```bash
sudo bash tools/ehot-usb-creator-linux/ehot-write-usb.sh build/output/ehot-os-22.3-xfce-amd64.iso
```
Скрипт проверяет `TRAN=usb`, `RM=1` и `SHA-256` перед записью.
