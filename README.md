# Настраиваемая сетевая защита — Windows 11 x64

**Стабильный v3.6.0 (Latest):** универсальный мастер для выбранных EXE и любых названий VPN/адаптеров, а также отдельный проверяемый запуск Claude Code CLI. Откройте `Install.cmd` и выберите **1 — Universal**, либо сразу `Install-Universal.cmd`. Два режима: **TUN + локальный Proxy** и **TUN с собственной блокировкой обхода**, включая отдельную настройку ограничения сетевого ядра VPN. Параметры выбираются на каждом ПК; интерфейсы сохраняются по GUID/NET_LUID. [Полная инструкция → UNIVERSAL-ru.md](UNIVERSAL-ru.md).

Скачайте [ZIP стабильного Latest](https://github.com/dancyuser/claude-happ-only/releases/latest/download/Claude-Happ-Universal.zip) или используйте Install-Latest.ps1. Поддержка произвольных EXE не означает автоматической защиты всего дерева потомков. Реальные разрыв VPN и перезагрузка нового модуля еще не испытаны.

**В v3.6.0 включены:** основной Ethernet и резервный Wi-Fi для одного сервера Happ, постоянные маршруты по GUID, проверка обоих одобренных выходов и исправление восстановления маршрутов. Настройка: [SETUP-ru.md — Основной проводной выход и резервный Wi-Fi](SETUP-ru.md#основной-проводной-выход-и-резервный-wi-fi). На исходном ПК проверено реальное отключение Ethernet, HTTPS через Wi-Fi с тем же IP и возврат провода. Перезагрузка и чистая установка этого сценария пока не испытаны.

Ниже описан сохраненный вариант Claude/Happ: в меню `Install.cmd` выберите **2 — Existing Claude Desktop + Happ preset**. Его работающая конфигурация автоматически не переводится в новый режим.

Отдельный Claude Code CLI `%USERPROFILE%\.local\bin\claude.exe` обнаруживается при обновлении варианта Claude/Happ, включается в WFP-инвентаризацию и получает проверяемый запуск `-Target Cli` и отдельный ярлык. Подробности и функция для терминала: [CODE-PROXY-ru.md](CODE-PROXY-ru.md).

Автоматическое применение AppID и наблюдение покрытия описаны в [AUTOMATION-ru.md](AUTOMATION-ru.md). На существующей установке подтвержден прогон Fix с UAC и сохранением прежней AppID-политики. Установка новой политики на чистом ПК еще не проверена. Подробности: [VALIDATION-ru.md](VALIDATION-ru.md).

Установщик настраивает проверяемый запуск Claude Desktop, HTTP-прокси встроенного Code и сетевые ограничения, допускающие защищенные процессы только к локальному Happ. Для самого Happ закрепляются сервер и физический интерфейс. При ошибке проверки запуск через ярлык запрещается.

**Install, Update, Diagnose, Fix, Restore и CheckOnly не запускают и не завершают Claude.** Реальный запуск происходит только по действию пользователя через созданный ярлык. Это не универсальный перехватчик трафика всех произвольных дочерних программ; границы защиты описаны ниже.

## Быстрый старт

1. Установите [Happ](https://happ.info/) и [Claude Desktop](https://claude.com/download). Добавьте свою подписку в Happ и подключите выбранный сервер. Happ и сервер не входят в этот комплект.
2. В Happ используйте режим прокси, выключите TUN. Один локальный порт на `127.0.0.1` должен принимать **SOCKS и HTTP CONNECT**. Обычный пример — `10808`; мастер позволяет другой порт.
3. Полностью закройте Claude самостоятельно. Скачайте [готовый ZIP из Latest release](https://github.com/dancyuser/claude-happ-only/releases/latest/download/Claude-Happ-Universal.zip), распакуйте его целиком и откройте `Install.cmd` обычным двойным щелчком.
4. Укажите домен или публичный IPv4 выбранного сервера, его TCP-порт, локальный порт Happ, страну выхода и физический адаптер. Пути, SID и ярлык заполняются на этом компьютере. Подтвердите UAC для установки защиты и итогового CheckOnly.
5. Дождитесь **SETUP PASS / CHECK ONLY PASS**. Затем вы сами можете пользоваться ярлыком **Claude - Happ Only**.

**[Полная установка с пояснением каждого поля → SETUP-ru.md](SETUP-ru.md)**

Можно скачать только [Install-Latest.ps1](https://github.com/dancyuser/claude-happ-only/releases/latest/download/Install-Latest.ps1), просмотреть файл и выполнить из обычного Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Latest.ps1
```

Загрузчик получает стабильный Latest release, проверяет SHA256 ZIP по GitHub API и запускает мастер. На компьютере с установленной защитой он автоматически выбирает обновление с сохранением параметров и итоговым CheckOnly. Он не загружает чужие настройки сервера и подписки.

```powershell
# Только скачать и проверить комплект: без установки и UAC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Latest.ps1 -DownloadOnly
```

## Как работает соединение

```text
Claude Desktop ── SOCKS ─────┐
                            ├─ 127.0.0.1:порт Happ ── выбранный сервер ── сайты/API
Встроенный Code ── HTTP ─────┘                        через физический адаптер
```

Desktop получает явный SOCKS-аргумент запуска. Code получает HTTP-прокси в пользовательском `settings.json`; то же окружение передается процессу Desktop для наследования обычными дочерними программами. SOCKS сам по себе Code не поддерживает: [документация Claude Code](https://code.claude.com/docs/en/network-config).

WFP блокирует защищенным EXE альтернативные IPv4-адреса, порты, UDP и IPv6. Happ разрешен только закрепленный сервер по TCP; точный маршрут направляет его через выбранный физический адаптер. Указанные виртуальные интерфейсы, например FlClashX, дополнительно запрещаются для ядра Happ. Остальные приложения не переводятся на Happ.

Happ использует внутренний `xray.exe` и в режиме прокси. Это название движка, а не требование включать TUN.

При запуске через ярлык сначала проверяются пользовательские настройки Code и HTTP CONNECT, затем с UAC — фильтры, маршрут, задача, EXE, владелец порта и защищенный curl. При сбое допускается один Fix и повторная диагностика. Запуск разрешен только после свежего успешного результата. В режиме CheckOnly выполнение останавливается до запуска Claude.

## Параметры и обслуживание

| Задача | Команда / документ |
|---|---|
| Установка или обновление из ZIP | `Install.cmd` — существующая защита определяется автоматически |
| Обновление с сохранением параметров | `Update-CodeSupport.ps1`; завершается CheckOnly |
| Просмотр настроек до установки | `Setup.ps1 -ConfigurationFile my-settings.json -Preview` |
| Смена домена / фиксированного IPv4 сервера | `Reconfigure.ps1 -Server …`; сначала можно добавить `-Preview` |
| Полная диагностика без запуска Claude | `Diagnose.cmd` |
| Исправление установленных правил и маршрута | `Fix.cmd`, с резервной копией |
| Проверка пользовательского прокси Code | `Configure-CodeProxy.ps1 -Mode Diagnose` |
| Откат защиты | `Restore.cmd -List`, затем `Restore.cmd -BackupId ID` |
| Откат настроек Code | `Configure-CodeProxy.ps1 -Mode Restore -BackupId ID` |
| Отдельный профиль Chrome для внешних ссылок | [Browser Tamer](BROWSER-TAMER-ru.md), необязателен |
| AppID на новом ПК: компилятор, политика, проверка потомков | [APPID-ru.md](APPID-ru.md); автоматическая установка: [AUTOMATION-ru.md](AUTOMATION-ru.md); ручной путь сохранен |
| Ошибка подключения / UAC / ожидание проверки | [TROUBLESHOOTING-ru.md](TROUBLESHOOTING-ru.md) |

Локальный порт, TCP-порт сервера, пути и адаптер выбираются для новой установки. Смена портов/пути ядра в уже установленной защите автоматически не выполняется: старые фильтры иначе конфликтуют с новыми. Смена физического интерфейса может потребовать разбора закрепленного маршрута. Ограничения и безопасные действия — в [SETUP-ru.md](SETUP-ru.md).

Рабочие файлы: `%ProgramData%\ClaudeHappOnly`; отчеты: `%ProgramData%\ClaudeHappReports`; административные снимки: `%ProgramData%\ClaudeHappBackups`. Настройки Code и их отдельные резервные копии находятся в его пользовательском каталоге. [Состав копий и Restore](RESTORE-ru.md).

## Что поддерживается и что проверено

- Целевая система: **Windows 11 x64**, Windows PowerShell 5.1, системный curl, работающий Firewall/WFP, Happ с внутренним Xray, Claude Desktop MSIX или указанная отдельная установка.
- Сервер: один публичный IPv4 и TCP-транспорт. Режим домена требует согласованного ответа двух DNS-сервисов. Режим фиксированного IPv4 не использует DNS для адреса сервера и не меняет его автоматически.
- Подписку, ключи и авторизацию Claude пользователь настраивает в самих приложениях. Установщик их не переносит. ARM64, IPv6-only/UDP-серверы и другие ядра в этом выпуске не поддерживаются.
- На исходном Windows 11 ПК пройдены административные проверки, исправление зависания Verify, HTTP/SOCKS и отрицательные curl-тесты, CheckOnly. После настройки владелец **вручную подтвердил работу встроенного Code**. Агент Claude не запускал.
- Новые варианты мастера и конфигурации проверены тестами и Preview. **Чистая установка на другой машине и все сочетания сетей/провайдеров пока не испытаны.** [Подробности доказательств](VALIDATION.md).

Предварительная проверка действует в созданном ярлыке. «Пуск», прямой EXE и протоколы приложения ее не выполняют, хотя ограничения защищенных EXE остаются. Старый открытый процесс не получает новые аргументы от Reload.

Sync добавляет ограничения уже обнаруженных EXE пакета Desktop и кэша Code. На исходной машине дополнительно действует ранее установленный тег `ClaudeProxyOnly`. На новом ПК политику можно подготовить и явно установить по инструкции ниже; обычный мастер ее скрыто не активирует. Тег и охват произвольных дочерних процессов нельзя считать автоматически перенесенными. У нового EXE до очередной синхронизации, а также у программ через WSL/SSH/службы нет заявленной общей гарантии защиты. Приложение, игнорирующее прокси, может не работать. [Подробная схема и ограничения](GUIDE-ru.md).

Для MSIX новый Setup автоматизирует компиляцию и применение AppID с одним UAC, проверкой активности, резервными копиями и компенсирующим откатом. Подробности и границы проверки — [AUTOMATION-ru.md](AUTOMATION-ru.md). Ручная процедура сохранена в [APPID-ru.md](APPID-ru.md). Наблюдатель проверяет текущие процессы после ручного запуска; универсальная защита произвольных потомков пока не реализована.

IP сервера Happ и внешний IP выхода — разные параметры. Комплект проверяет одинаковый текущий выход у нескольких HTTPS-сервисов и нужную страну; неизменный IP провайдера навсегда он не обеспечивает.

В публичном комплекте нет личных конфигураций, SID, подписок, ключей, резервных копий или журналов. SHA256 подтверждает совпадение файлов, но не заменяет цифровую подпись. Browser Tamer загружается только с официального upstream; его настройки, браузер по умолчанию и Chrome proxy extensions автоматически не меняются.


## SnowVPN / FlClashX: automatic active TUN selection (unreleased fix)

Happ must remain running and connected in proxy mode. SnowVPN/FlClashX carries other applications' traffic; it does not replace the local Happ proxy. The checked launcher validates Code settings without a preliminary network probe, then delegates SOCKS/HTTP CONNECT, exit-country and bypass-rejection tests to the protected Preflight. This lets Preflight diagnose/repair a changed TUN rule before testing transport. It rechecks Code settings after Preflight and still requires a fresh valid launch ticket.

If the proxy is unavailable, inspect the Preflight report (including `HAPP_LISTENER`) rather than rewriting already-correct Code settings. To separate settings from transport in ordinary PowerShell:

```powershell
$guard = Join-Path $env:ProgramData 'ClaudeHappOnly'
$c = Get-Content (Join-Path $guard 'config.json') -Raw | ConvertFrom-Json
& "$guard\Configure-CodeProxy.ps1" -Mode Diagnose -SettingsOnly -ProxyPort $c.ProxyPort -ExpectedCountry $c.ExpectedCountry
& "$guard\Configure-CodeProxy.ps1" -Mode Diagnose -ProxyPort $c.ProxyPort -ExpectedCountry $c.ExpectedCountry
```

`SettingsOnly` performs no network test and issues no transport or launch approval. Apply still requires a successful proxy/country test. A failed transport test with `SettingsOK=true` indicates a proxy/connectivity/country problem; it is not evidence of invalid settings.

When `BlockedInterfaces` contains `FlClashX` or `SnowVPN Tun V2`, the guard resolves the interface on every Diagnose/Fix. It requires exactly one **Up** adapter with a matching name (`FlClashX` or `SnowVPN Tun Vn`) and driver description `Meta Tunnel`. The old config value need not be edited when switching VPN clients. Other explicitly listed blocked adapters remain covered.

The existing rule name `Happ-Xray-Block-FlClashX` is intentionally retained for backup/restore compatibility, even when its interface filter now matches `SnowVPN Tun V2`. Fix installs and verifies a temporary overlapping block before replacing the old rule. If replacement fails, the staging BLOCK remains active and Preflight fails; inspect the reported `Happ-Xray-Block-TUN-Stage-*` rule before further changes.

**No continuous failover monitoring**: close Claude before switching between SnowVPN and FlClashX and launch it again through the checked shortcut. Do not switch VPNs while Claude is running. Existing pinned upstream routing and other WFP policies remain unchanged. An existing-machine Fix/Preflight with SnowVPN Tun V2 passed on 2026-11-06; see [validation scope](VALIDATION-ru.md). Switching between both clients during a session and clean-machine installation remain untested.
