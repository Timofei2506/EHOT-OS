# Расширение Firefox: EHOT OS Monitor (`ehot-monitor@ehotos.local`)

## Почему требуется подпись Mozilla (AMO)
Стандартная версия Firefox в Linux Mint (Release) разрешает постоянную установку расширений только с цифровой подписью Mozilla.
Бесплатная **unlisted-подпись** через AMO позволяет подписать `.xpi` для самостоятельного распространения (без публикации в открытом каталоге дополнений) и развернуть его через `/etc/firefox/policies/policies.json`.

## Как подписать `.xpi` (однократно)
1. Зарегистрируйте бесплатный аккаунт на [addons.mozilla.org](https://addons.mozilla.org/) и получите API ключи (`JWT issuer` и `JWT secret`) в Developer Hub -> API Keys.
2. Установите `web-ext` (Node.js) и выполните в каталоге `modules/ehot-control/extension/`:
   ```bash
   npx web-ext sign \
     --channel=unlisted \
     --api-key="$AMO_JWT_ISSUER" \
     --api-secret="$AMO_JWT_SECRET"
   ```
3. Полученный подписанный файл `ehot_os_monitor-1.0.0.xpi` скопируйте в `/usr/local/lib/ehot-control/ehot_os_monitor.xpi` (либо укажите URL релиза) и пропишите в `/etc/firefox/policies/policies.json`:
   ```json
   {
     "policies": {
       "ExtensionSettings": {
         "ehot-monitor@ehotos.local": {
           "installation_mode": "force_installed",
           "install_url": "file:///usr/local/lib/ehot-control/ehot_os_monitor.xpi"
         }
       }
     }
   }
   ```
4. Проверьте работу интеграции в Firefox на странице `about:policies` и `about:addons`.

> **Временная отладка без подписи**: только для тестирования можно открыть `about:debugging#/runtime/this-firefox` -> *Загрузить временное дополнение* -> выбрать `manifest.json` (действует до закрытия Firefox).
