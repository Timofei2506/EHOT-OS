# EHOT USB Creator (Windows .exe)

Фирменная безопасная утилита на **C# (.NET 8 Windows Forms)** для записи загрузочного образа **EHOT OS** на флешку **Kingston DataTraveler 64 ГБ** из-под Windows 10/11.

## Защита от ошибок
- В списке накопителей отображаются **исключительно съёмные USB-диски** (`InterfaceType = USB`); внутренние SSD/HDD компьютера полностью скрыты и защищены.
- Автоматически выделяет накопители **Kingston DataTraveler** и отображает их объём и буквы томов.
- Проверяет контрольную сумму **SHA-256** образа перед записью (при наличии рядом `.sha256` или введённого хеша).
- Поддерживает как цельный `.iso`, так и многотомные файлы из GitHub Releases (`*.iso.part.aa`, `.part.ab`, …) **напрямую потоком без создания лишней копии на диске**.
- Блокирует/размонтирует тома флешки, очищает старую разметку, записывает образ посекторно (1 МиБ выровненным буфером `WRITE_THROUGH`) и выполняет контрольное чтение первых 8 МиБ после записи.

## Сборка `.exe`
Собирается автоматически в GitHub Actions (`windows-latest`) или вручную на Windows:
```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```
Готовый файл: `EHOT-USB-Creator-win-x64.exe`.
