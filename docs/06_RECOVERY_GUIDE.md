# 6. Инструкция восстановления системы EHOT OS

## Сценарий 1. Чёрный экран или проблема после обновления драйвера NVIDIA
1. При включении ноутбука удерживайте `Shift` (BIOS) или нажимайте `Esc` (UEFI), чтобы появилось меню **GRUB**.
2. Выберите строку с `(recovery mode)` или нажмите `e` на основной строке и добавьте параметр **`nomodeset`** после `quiet splash`. Нажмите `F10` для загрузки.
3. После входа в систему откройте терминал и откатите драйвер NVIDIA на безопасный `nouveau`:
   ```bash
   sudo apt purge '*nvidia*'
   sudo apt autoremove -y
   sudo update-initramfs -u
   sudo reboot
   ```
4. Повторно проверьте совместимость карты:
   ```bash
   python3 /usr/local/lib/ehot-os/gpu_detect.py
   ```
   *(Примечание для старых карт NVIDIA Kepler 470xx: если владелец осознанно хочет использовать снятый с поддержки драйвер 470, необходимо переключиться на более старую ветку ядра 6.8 из репозитория Ubuntu 24.04 и применить проверенные патчи; по умолчанию EHOT OS сохраняет безопасный `nouveau`.)*

---

## Сценарий 2. Восстановление из снимка Timeshift
1. Если система загружается: откройте **Timeshift** -> выберите снимок -> **Восстановить**.
2. Если система не загружается: загрузитесь с флешки **Kingston DataTraveler** -> откройте **Timeshift** в Live-среде -> выберите раздел `EHOT_ROOT` на диске 1 ТБ -> восстановите рабочий снимок.

---

## Сценарий 3. Восстановление загрузчика GRUB с Live USB
Если загрузчик был повреждён:
```bash
# 1. Загрузитесь с Kingston DataTraveler
# 2. Определите разделы целевого диска:
lsblk -f

# 3. Смонтируйте корень (например /dev/sda3 или /dev/sdb3) и EFI (/dev/sdX2):
sudo mount /dev/sdX3 /mnt
sudo mount /dev/sdX2 /mnt/boot/efi
for d in dev dev/pts proc sys run; do sudo mount --bind /$d /mnt/$d; done

# 4. Переустановите GRUB:
sudo chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="EHOT_OS" --recheck
sudo chroot /mnt update-grub
```

---

## Сценарий 4. Проверка ZRAM, Swap и сервисов EHOT OS
```bash
zramctl
swapon --show
systemctl status earlyoom anydesk ehot-control ehot-control-boot
```
