# Изменения

## v3.6.0-rc.2 — отдельный Claude Code CLI

- Обнаружение стандартного .local/bin/claude.exe обычного пользователя; сохраненный CliExecutable включается в WFP и SYSTEM-синхронизацию без замены Desktop-цели.
- Проверяемый запуск -Target Cli и отдельный ярлык; тот же Preflight и прокси, сохранение текущей папки/потоков/кода завершения, восстановление окружения оболочки.
- Отдельная цель и SHA256 CLI в билете, запрет подмены Desktop/CLI, резервное копирование CLI-ярлыка. Проверки на фикстурах без исполнения Claude.

## v3.6.0-rc.1 — универсальные профили

- Отдельный мастер для любых выбранных Windows EXE: TUN + HTTP/SOCKS5-прокси или TUN с собственной постоянной WFP-блокировкой обхода интерфейса.
- Выбор адаптера по GUID/NET_LUID вместо имени; отсутствующий интерфейс не заменяется по догадке. Порты, IP, транспорт и путь сетевого ядра задаются пользователем.
- Для строгого TUN предусмотрено ограничение VPN-ядра до одного серверного endpoint; отдельно обозначен InterfaceOnly, который не предотвращает DIRECT внутри VPN.
- Собственные профили, атомарная смена WFP-фильтров, резервные копии, Restore, Verify/Test и явный пользовательский запуск после свежей проверки. Работающая установка Claude/Happ сохраняется отдельно.
- Проверены конфигурационные сценарии и реальные TUN InterfaceOnly/HTTP Proxy на диагностических копиях curl, включая блокировку обхода и Restore. Реальное отключение VPN, перезагрузка, чистая Windows и строгий режим с настоящим VPN-ядром пока не испытаны.

## Unreleased - Auto SnowVPN/FlClashX TUN

- Fix checked-launch ordering: validate Code settings separately, run protected Preflight with its repair round, then recheck settings before accepting the fresh ticket. An unavailable Happ proxy no longer produces misleading instructions to rewrite valid settings or prevents Preflight from running.
- Add Diagnose -SettingsOnly without transport/launch approval; Apply retains mandatory HTTP proxy/country checks. Add isolated launcher regression checks for check/repair ordering and rejection of invalid settings.

- Auto-select an active Meta Tunnel named SnowVPN Tun Vn or FlClashX when existing BlockedInterfaces uses either family.
- Stage and verify an Xray BLOCK rule before changing the legacy named firewall rule; keep staging protection on failure.
- Add synthetic fail-closed tunnel selection tests, retain existing config and backup/restore format.


## v3.4.0

- Добавлена установка пользовательского ConfigCI из подписанного штатного компонента WinSxS, без загрузки DLL с посторонних сайтов и без применения политик.
- Подготовка узкого XML/CIP AppID Tagging для MSIX-семейства Claude с проверкой схемы официальным компилятором, манифестом SHA256 и Applied=false.
- Пошаговая инструкция явной установки, проверки и удаления только новой собственной политики; прежняя политика исходного ПК не заменяется.
- Read-only проверка реальных тегов у работающих Desktop/Code и потомков с отдельным учетом неизвестных/нетегированных процессов. Подтверждено, что не все наблюдаемые потомки имеют тег.
- WFP-тег поддерживает выбранный ProxyPort, старый API 10808 сохранен. Автоматическая миграция существующего порта не добавляется.
- Проверены установка/импорт ConfigCI и офлайн-компиляция, тесты XML/ABI/API. Новая политика на исходном ПК не активировалась; универсальное покрытие всех потомков не заявляется.

## v3.3.0

- Настройка отдельного HTTP-прокси встроенного Code с сохранением остальных параметров, резервной копией и hash-checked Restore.
- Проверка Code перед запуском, proxy-окружение для Desktop и обычных дочерних процессов; защита известных EXE кэша claude-code вне WindowsApps.
- Защищенный HTTP CONNECT-тест вместе с SOCKS и отрицательными проверками обхода.
- Исправлены непривилегированный AllUsers-запрос, зависание Verify из-за WFP-транзакции и неверный успешный код Setup после ошибки.
- Static Verify вынесен в процесс с лимитом 45 секунд. Есть отдельный Repair-VerifyWait для старой установленной диагностики.
- Русский мастер с выбором физического адаптера, заполнением локальных путей/SID, доменом или фиксированным публичным IPv4 и пользовательскими портами для новой установки.
- Latest-загрузчик и Install.cmd различают новую установку и обновление, сохраняют параметры существующей защиты. Setup заканчивается CheckOnly без запуска Claude и без ожидания Enter в административном рабочем процессе.
- Небольшие JSON-примеры, Preview и Reconfigure, полные инструкции установки, устройства защиты, диагностики и отката. Границы переносимости и охвата дочерних процессов указаны явно.
- На исходном ПК пройдены административное обновление, ремонт, HTTP/SOCKS, отрицательные проверки и CheckOnly; владелец подтвердил успешную работу Code. Чистая установка другого ПК не объявляется испытанной.

## v3.2.0

- Публичный универсальный комплект с документацией установки, диагностики, восстановления и выбора браузерного профиля.
- Install-Latest скачивает и проверяет ZIP актуального стабильного выпуска этого репозитория.
- Необязательный загрузчик Browser Tamer получает официальный Latest release Windows x64, проверяет GitHub SHA256 и поддерживает DownloadOnly/VerifyOnly. MSI в репозитории не хранится.
- Резервные копии перед Install/Fix/Restore, проверяемый ярлык и узкая проверка зарегистрированной фоновой CoworkVMService.
- После первоначальной публикации точного v3.2.0 пройдены административные Install/Fix/Restore и CheckOnly на существующей системе; см. VALIDATION.md.
