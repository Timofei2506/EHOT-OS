# 7. Документация по обновлению и сопровождению сборки

## Обновление установленной системы (на ноутбуке Lenovo)
EHOT OS полностью сохраняет официальные каналы обновлений Linux Mint 22.3 и Ubuntu 24.04 LTS (поддержка до апреля 2029 года):
- Графический способ: **Менеджер обновлений (`mintupdate`)** на панели.
- Консольный способ:
  ```bash
  sudo apt update && sudo apt upgrade
  ```
- Официальные обновления AnyDesk приходят через `deb.anydesk.com` автоматически вместе с `apt upgrade`.

## Обновление фирменной графики без пересборки ISO
Когда дизайнерский ИИ-агент подготовит логотип енота, обои, иконки, иконку меню и картинку Plymouth:
1. Поместите файлы в `modules/ehot-branding/assets/` по инструкции `BRANDING_SPEC.md`.
2. Выполните на ноутбуке (или в образе перед пересборкой):
   ```bash
   sudo ehot-apply-branding /путь/к/modules/ehot-branding/assets
   sudo update-initramfs -u
   ```

## Выпуск новой версии ISO EHOT OS (для сопровождающего)
1. Внесите изменения в модули `modules/` или обновите версию в `build/config/build.conf`.
2. Обязательно прогоните локальный набор проверок перед пушем:
   ```bash
   bash tests/run_all_tests.sh
   ```
3. Отправьте изменения в ветку `main` и запустите workflow **Build EHOT OS ISO** (либо создайте тег `v1.x.y`).
4. При выходе новых точечных релизов Linux Mint (при изменении ISO) обновите `MINT_VERSION`, `MINT_ISO_FILENAME`, `MINT_ISO_SHA256` и `build/config/sha256sum.txt` в соответствии с официальным `sha256sum.txt.gpg` Linux Mint.
