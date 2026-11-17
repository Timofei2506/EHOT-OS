# 09 — Публичная редакция MfiSerli OS (EHOT_EDITION=public)

## Зачем

EHOT OS изначально собиралась как личная сборка для конкретного ноутбука (Lenovo, пользователь
Regzen) с модулями удалённого доступа и родительских функций. Публичная редакция **MfiSerli OS**
— та же оптимизированная система, но полностью очищенная от личных компонентов и с собственным
дизайном. Обе редакции собираются из одного репозитория одной командой.

## Редакции

| | **kent** (по умолчанию) | **public** |
|---|---|---|
| Имя ОС | EHOT OS | MfiSerli OS |
| ISO | `ehot-os-22.3-xfce-amd64.iso` | `mfiserli-os-22.3-xfce-amd64.iso` |
| Volume ID | `EHOT_OS_22_3` | `MFISERLI_22_3` |
| Пользователь по умолчанию | `Regzen` | `user` |
| Hostname по умолчанию | `ehot-lenovo` | `mfiserli-pc` |
| Разделы/метки | `EHOT_ROOT` / `EHOTEFI` | `MFISERLI_ROOT` / `MFISERLIEFI` |
| GRUB bootloader-id | `EHOT_OS` | `MFISERLI_OS` |
| Файл релиза | `/etc/ehot-os-release` | `/etc/mfiserli-os-release` |
| Конфиг редакции | — | `/etc/ehot-edition.conf` |
| Удалённый доступ и родительские функции | да (ehot-remote + личный агент) | **нет, модули не устанавливаются** |
| Тема | EHOT Dark-Violet (чёрно-фиолетовая, панель сверху) | **MfiSerli Dark Glass** (навy + бирюза, dock снизу) |
| Загрузка | Plymouth EHOT | Plymouth MfiSerli (стекло + плитка-логотип) |

Общее у обеих редакций: Linux Mint 22.3 «Zena» XFCE, ZRAM(zstd) + 4 ГБ swapfile, earlyoom,
автодрайверы NVIDIA/Intel, Steam/Wine/Lutris/GameMode/MangoHud, LibreOffice, Firefox,
безопасный установщик `ehot-install` (защита USB-флешки, UEFI + Legacy BIOS), первый запуск
`ehot-firstboot` (драйверы + ufw; напоминание о личной настройке — только в редакции kent).

## Сборка

```bash
# Публичная редакция MfiSerli OS
sudo bash build/scripts/build-iso.sh --edition public
# -> output/mfiserli-os-22.3-xfce-amd64.iso (+ .sha256)

# Личная редакция EHOT OS (поведение v1.0.0 не изменилось)
sudo bash build/scripts/build-iso.sh            # то же, что --edition kent
```

Проверка собранного ISO в QEMU:

```bash
bash build/scripts/test-iso-qemu.sh output/mfiserli-os-22.3-xfce-amd64.iso
```

GitHub Actions: workflow **Build EHOT OS ISO & Release** → `workflow_dispatch` → поле
*edition* (`kent` / `public`); имена артефактов и ZIP подставляются автоматически
(`MfiSerli-OS-vX.Y.Z-*.zip` для публичной редакции).

## Как это устроено

- `build/config/edition-public.conf` — идентичность редакции (имя ОС, ISO, volume, префикс
  разделов, пользователь). `build-iso.sh --edition public` подгружает его, переопределяет
  `EHOT_ISO_FILENAME`/`EHOT_VOLUME_ID` и пишет `edition-active.conf` в chroot.
- `build/chroot/customize-rootfs.sh` — читает редакцию; шаги установки личных модулей
  выполняются **только** при `EDITION=kent`; брендинг — `mfiserli-apply-branding.sh` для
  public и `ehot-apply-branding.sh` для kent; релиз-файл и `/etc/ehot-edition.conf`
  генерируются по редакции.
- `modules/ehot-installer/ehot-edition.py` — в рантайме установщика читает
  `/etc/ehot-edition.conf` и подставляет имя ОС, метки разделов, bootloader-id и имя
  пользователя. Без конфига поведение полностью идентично EHOT OS v1.0.0.
- `modules/ehot-branding/public/` — тема `MfiSerli-Dark-Glass` (GTK + xfwm4), иконки
  `mfiserli`, обои «Aurora Glass» 4K (`wallpaper.jpg` + затемнённый `wallpaper-login.jpg`
  для экрана входа), Plymouth-тема, dock-конфиг XFCE (панель снизу `p=12`, иконки без
  подписей) и запись `install-mfiserli.desktop`.

## Дизайн «Dark Glass»

- Палитра: фон `#0B1420`, панели `rgba(9,18,29,.86)`, акцент `#22D3EE` (бирюза),
  вторичный `#38BDF8`, фиолетовый штрих `#8B5CF6`.
- Обои: сгенерированы ИИ (аврора + стеклянные пластины), 3840×2160, JPEG ~400 КБ.
- Логотип: стеклянная плитка с «M» (512 PNG + SVG + Plymouth 320 + иконки 48).
- Композитинг XFWM намеренно выключен (слабые ПК), «стекло» достигается цветами,
  а не блюром — интерфейс остаётся быстрым.

## Ограничения

- Редакция kent продолжает собираться бит-в-бит прежней командой; все 29+ тестов
  запускаются для обеих редакций (`tests/run_all_tests.sh`).
- Публичная редакция наследует политику запрета (Steam-клоны, мессенджер-десктоп и пр.
  не устанавливаются автоматически — список в `tests/test_manifests_and_policy.py`).
