# Рекомендации для игр на 4 ГБ RAM + HDD в EHOT OS

1. **Закрывайте Firefox перед игрой**: браузер легко потребляет 1–2 ГБ RAM. При 4 ГБ RAM это сразу освободит память для игры и ZRAM.
2. **Параметры запуска в Steam**:
   - Только оптимизация CPU/I/O: `gamemoderun %command%`
   - Оптимизация + счётчик FPS (вкл/выкл `Right Shift + F12`): `MANGOHUD=1 gamemoderun %command%`
3. **Запуск старых игр Proton на слабом GPU**:
   - Если видеокарта NVIDIA слишком старая и не поддерживает Vulkan (например, работает на `nouveau` или старом Intel HD), используйте OpenGL-рендер Proton: `PROTON_USE_WINED3D=1 gamemoderun %command%`.
4. **Minecraft (после самостоятельной установки лаунчера)**:
   - Ограничьте память JVM в настройках профиля: `-Xmx2048M -Xms512M`.
