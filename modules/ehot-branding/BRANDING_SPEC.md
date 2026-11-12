# Спецификация графических ассетов для дизайнерского ИИ-агента (EHOT OS)

## Цветовая палитра проекта
- **Глубокий чёрно-фиолетовый фон**: `#0B0914`
- **Поверхности / панели**: `#141026`
- **Основной неоновый фиолетовый акцент**: `#8B5CF6`
- **Вторичный яркий фиолетовый / подсветка**: `#A855F7`
- **Холодный технологичный акцент (опционально)**: `#22D3EE`
- **Текст основной / приглушённый**: `#F4F3FF` / `#A7A3C2`

## Куда помещать файлы

| Компонент | Путь в репозитории | Целевой путь в ОС | Рекомендуемый формат и размер |
|---|---|---|---|
| Логотип (полный) | `assets/logo/logo.svg` и `logo.png` | `/usr/share/ehot-os/branding/logo.*` | SVG + PNG с прозрачным фоном, `1024x1024` |
| Обои рабочего стола | `assets/wallpaper/wallpaper.png` (или `.jpg`) | `/usr/share/backgrounds/ehot-os/wallpaper.png` | PNG/JPG `1920x1080` (или `2560x1440`), тёмные тона без перегруза центра |
| Экран загрузки Plymouth | `assets/plymouth/logo.png` | `/usr/share/plymouth/themes/ehot-os/logo.png` | PNG RGBA, `320x320` или `400x400`, прозрачный фон |
| Иконка меню приложений | `assets/menu-icon/ehot-menu.svg` (или `.png`) | `/usr/share/icons/ehot-os/scalable/apps/ehot-menu.svg` | SVG (квадратный viewBox `0 0 64 64`) или PNG `64x64` |
| Набор иконок | `assets/icons/...` (структура freedesktop `apps/`, `places/`) | `/usr/share/icons/ehot-os/` | SVG / PNG по стандарту FreeDesktop Icon Theme |
| Тема оформления GTK/XFWM4 | `assets/theme/EHOT-Dark-Violet/` | `/usr/share/themes/EHOT-Dark-Violet/` | GTK3 `gtk.css` + `xfwm4/themerc` |
