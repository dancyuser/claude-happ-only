# AppID-политика: подготовка, установка и проверка охвата

AppID tagging позволяет поставить процессу тег `ClaudeProxyOnly=Protected`. WFP-фильтры комплекта применяются к процессам с этим тегом независимо от пути EXE. Политика **AppID Tagging Policy** не является политикой запрета запуска программ. Она также не перенаправляет сокеты в прокси: Desktop/Code должны использовать Happ своими настройками.

Microsoft: [создание](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appidtagging/design-create-appid-tagging-policies), [развертывание](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appidtagging/deploy-appid-tagging-policies), [CiTool](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/operations/citool-commands).

## Что автоматизировано

- `Install-ConfigCI.ps1` находит уже имеющийся компонент Microsoft в WinSxS, проверяет действительную подпись Microsoft Windows, копирует модуль в каталог **текущего пользователя**, сверяет хеши и проверяет импорт. Системные каталоги не изменяет, DLL из Интернета не скачивает. Имеющийся проверенный модуль повторно не устанавливает.
- `Prepare-AppIdPolicy.ps1` генерирует узкую XML-политику для указанного MSIX-семейства и компилирует ее официальным ConfigCI в CIP. По умолчанию семейство Claude — `Claude_pzs8sxrjxfjjc`. Результат содержит XML/CIP и SHA256. **Не применяет политику и не вызывает CiTool.**
- `Test-AppIdCoverage.ps1` читает тег у уже работающих Claude/Code и найденных потомков. Не запускает процессы, не закрывает их и не меняет токены.
- WFP-условие тега использует настроенный ProxyPort, включая пользовательский порт новой установки. Старый метод для 10808 сохранен для совместимости. Это не миграция уже закрепленного порта.

Остались явные ручные шаги с UAC: применение политики и включение ее WFP-условия в установленной защите. Подготовка компилятора не означает установку политики.

## Уже настроенный компьютер

Если у вас уже действует прежняя `Claude-Network-Identity` с ID `{C0E85E51-F842-4969-BD74-36506B26A5B1}` и тег подтвержден у нужных процессов, повторно устанавливать другую политику не требуется. Комплект не заменяет и не удаляет эту прежнюю политику. На исходной машине она сохранена; новая политика в ходе подготовки не активировалась.

## 1. Установить компилятор

Используйте **64-разрядный Windows PowerShell 5.1** (`powershell.exe`), обычного целевого пользователя. Из распакованного комплекта:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ConfigCI.ps1 -Mode Check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ConfigCI.ps1 -Mode Install
```

Установка CurrentUser не требует UAC. В новом Windows PowerShell проверьте:

```powershell
Import-Module ConfigCI
Get-Command ConvertFrom-CIPolicy, New-CIPolicy
```

Путь обычно `%USERPROFILE%\Documents\WindowsPowerShell\Modules\ConfigCI\1.0`, но определяется через системный каталог документов, в том числе при перенаправлении. Сохраненные файлы и источник указаны в `installation-receipt.json`. Если папка уже есть, но модуль не обнаруживается, скрипт откажется затирать ее. Поддерживается источник x64 из локального WinSxS; наличие пакета в каждой редакции Windows не гарантируется.

Если подписанного компонента нет, используйте [официальный App Control Wizard](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appidtagging/design-create-appid-tagging-policies). Комплект не подменяет ConfigCI одноименным неизвестным пакетом PowerShell Gallery и не меняет редакцию Windows. PowerShell 7 не является целевой средой этих команд.

## 2. Подготовить политику

Этот шаг безопасен при открытом Claude: он только пишет файлы подготовки и выполняет компиляцию.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Prepare-AppIdPolicy.ps1 -InstallCompiler -OutputDirectory .\AppIdPrepared
```

Выберите новый каталог, если AppIdPrepared уже существует. Для другого MSIX-семейства передайте `-PackageFamily ИМЯ_СЕМЕЙСТВА`; его можно посмотреть через `Get-AppxPackage -Name Claude`. Для отдельной установки без MSIX этот PFN-шаблон неприменим: нужны отдельно проверенные правила издателя/файла.

Вы получите:

- `Claude-Happ-Only-AppId.xml` — PolicyType=AppID Tagging Policy, Audit Mode, только семейство Claude и правило `*.dll`, необходимое для оптимизации оценки DLL;
- `{3E5E5A48-7D87-49E0-A12A-CC2C17689A73}.cip` — новый собственный ID, отличный от прежней политики исходного ПК;
- `prepared.json` — SHA256, семейство и **Applied=false**.

Просмотрите XML. В нем нет правила `*` для EXE, нет тега для всех powershell.exe/python.exe и нет запретов запуска. Сверьте бинарный файл с BinarySHA256 из prepared.json. Компиляция подтверждает корректность схемы, но не доказывает фактический охват процессов или активность политики.

## 3. Включить WFP-фильтры тега

Самостоятельно полностью закройте Claude. Защита Happ должна быть уже установлена и рабочая. В **обычном** PowerShell из комплекта:

```powershell
$config = Get-Content "$env:ProgramData\ClaudeHappOnly\config.json" -Raw | ConvertFrom-Json
$config.UseLegacyTag = $true
$config | ConvertTo-Json -Depth 20 | Set-Content .\this-computer.json -Encoding UTF8
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -ConfigurationFile .\this-computer.json
```

Историческое имя поля UseLegacyTag означает включение WFP-условия ClaudeProxyOnly; оно не устанавливает саму AppID-политику. Setup сохранит административный снимок, обновит совместимые исходники, добавит фильтры и завершится CheckOnly без запуска Claude. Этот CheckOnly подтверждает фильтры и туннель, но еще не активность AppID-политики. Нужен комплект v3.4.0 или новее для произвольного ProxyPort. Не меняйте заодно закрепленные порты/путь ядра: их миграция по-прежнему отдельно не реализована.

Файл this-computer.json содержит параметры этого ПК и SID. Он исключен из Git; не публикуйте его. Не запускайте весь Setup от администратора: пользовательские настройки должны оставаться в профиле обычного пользователя.

## 4. Применить CIP — только на новом/целевом ПК

Нужны права администратора и CiTool, включенный в Windows 11 начиная с 22H2. Клиент остается закрытым. В административном PowerShell сначала сохраните список политик в локальный файл и проверьте, нет ли уже нашей новой политики с тем же ID или прежней Claude-Network-Identity:

```powershell
& "$env:SystemRoot\System32\CiTool.exe" --list-policies --json
```

Если новый ID уже занят неизвестной политикой, остановитесь: команда update-policy заменяет политику с тем же ID. Прежнюю политику Microsoft/организации/Claude не удаляйте.

Вместо ПОЛНЫЙ_ПУТЬ ниже подставьте полный путь Binary из подготовленного пакета:

```powershell
$binary = 'ПОЛНЫЙ_ПУТЬ\AppIdPrepared\{3E5E5A48-7D87-49E0-A12A-CC2C17689A73}.cip'
Get-FileHash -LiteralPath $binary -Algorithm SHA256
& "$env:SystemRoot\System32\CiTool.exe" --update-policy $binary --json
if ($LASTEXITCODE -ne 0) { throw 'AppID policy installation failed' }

$list = & "$env:SystemRoot\System32\CiTool.exe" --list-policies --json | ConvertFrom-Json
$list.Policies | Where-Object { $_.PolicyID.Trim('{}') -ieq '3E5E5A48-7D87-49E0-A12A-CC2C17689A73' } |
    Select-Object PolicyID, FriendlyName, IsOnDisk, IsAuthorized, IsEnforced, PolicyOptions
```

Ожидаются FriendlyName=Claude-Happ-Only-AppId, одна соответствующая запись и активные IsOnDisk/IsAuthorized/IsEnforced. IsEnforced описывает состояние политики в CI; сама политика имеет тип AppID Tagging и Audit Mode, а не запрет запуска всего ПО. Если политика ожидает перезагрузки, не считайте ее уже действующей; сохраните отчет и перезагрузитесь самостоятельно, когда будете готовы. Скрипты компьютер не перезагружают.

## 5. Проверить реальные процессы

Теги относятся к новым запускам. Уже открытые процессы нельзя считать обновленными после установки политики. Пользователь сам открывает Claude через проверяемый ярлык и создает новую Code-сессию. Затем в обычном PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-AppIdCoverage.ps1
```

Rows содержит HasClaudeTag, NonInheritable и Error для наблюдаемых PID. AllObservedTagged=true относится только к текущему снимку. Ноль наблюдаемых процессов не считается PASS. Ошибка доступа/уже завершившийся процесс учитывается как Unknown, а не как доказанный тег.

Отдельно повторите сетевой WFP-захват или испытание нужной программы. Наличие тега не доказывает, что конкретное соединение блокировалось нужным фильтром.

## Почему это не гарантия всех потомков

На исходном ПК при чтении уже работающих процессов были найдены теги у Desktop/Code и части потомков, но один conhost.exe был без тега. Атрибуты с флагом NonInheritable также встречались. Это наблюдение охвата, не доказательство сетевой утечки.

Штатная схема AppIDTag в ConfigCI содержит Key и Value; переключателя «наследовать всеми потомками навсегда» в ней нет. Не добавляйте неизвестный Flags в XML. Процесс может получать тег повторной оценкой политики в контексте пакета; службы, WSL/VM/SSH и выход из контекста пакета могут вести себя иначе.

Чтобы охватить конкретную дополнительную утилиту, нужны отдельные узкие правила, отдельный тест и понимание, что тег повлияет на все ее совпавшие запуски, а не только на один родительский PID. Глобальное тегирование всех powershell.exe/python.exe может сломать сеть других приложений. Периодический поиск новых PID тоже не закрывает гонку первого соединения. Полный контроль произвольного дерева требует отдельного механизма изоляции/перехвата и пока не реализован этим комплектом.

## Откат

Только если вы сами установили именно новую политику из этого комплекта и ее ID/имя проверены, при закрытом клиенте выполните в административном PowerShell:

```powershell
& "$env:SystemRoot\System32\CiTool.exe" --remove-policy '{3E5E5A48-7D87-49E0-A12A-CC2C17689A73}' --json
if ($LASTEXITCODE -ne 0) { throw 'AppID policy removal failed' }
```

Проверьте список политик повторно. Это не удаляет прежнюю Claude-Network-Identity, системные/корпоративные политики или WFP-фильтры. Изменение UseLegacyTag и остальные настройки защиты откатываются штатным Restore по административному снимку шага 3. Настройки Code — отдельным пользовательским Restore. Уже выданные теги текущих процессов не считайте мгновенно снятыми: клиент закрывается/открывается пользователем.

ConfigCI — отдельный пользовательский инструмент. Его копия установлена без перезаписи прежнего модуля; для удаления можно убрать только созданный каталог версии после проверки installation-receipt.json. Никакие системные компоненты WinSxS удалять не требуется.
