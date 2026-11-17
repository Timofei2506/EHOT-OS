# Редакция MfiSerli OS (public)

Публичная редакция той же оптимизированной сборки на базе Linux Mint 22.3 «Zena» XFCE,
что и EHOT OS, но полностью свободная от личных/родительских модулей Кента:

- **Убрано:** модули удалённого доступа и родительских функций не устанавливаются вовсе
  (в образе нет их пакетов, сервисов, скриптов настройки и иконок первого запуска).
- **Сохранено:** ZRAM + swapfile, earlyoom, авторазметка sysctl, драйверы NVIDIA/Intel,
  Steam/Wine/Lutris/GameMode/MangoHud, LibreOffice, Firefox, безопасный установщик
  с защитой USB-флешки, UEFI + Legacy BIOS.
- **Дизайн «Dark Glass»:** тема GTK/xfwm4 `MfiSerli-Dark-Glass` (глубокий навy + бирюзовый
  акцент #22D3EE), dock-панель снизу (`p=12`, иконки без подписей), обои «Aurora Glass» 4K,
  логотип-плитка с буквой «M», стеклянный экран загрузки Plymouth и фон входа LightDM.

## Сборка

```bash
sudo bash build/scripts/build-iso.sh --edition public
# -> output/mfiserli-os-22.3-xfce-amd64.iso
```

Редакция по умолчанию — `kent` (EHOT OS), поведение сборки v1.0.0 не меняется.
