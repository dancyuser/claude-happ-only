#requires -Version 5.1
param([string]$ConfigurationFile,[switch]$InstallBrowserTamer,[switch]$Preview,[ValidateSet('Auto','Off','Require')][string]$AppIdMode,[switch]$NoWatch)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1";. "$PSScriptRoot\Setup.Common.ps1"
function Ask($Label,$Default){$answer=Read-Host ($Label+$(if($Default){' ['+$Default+']'}));if([string]::IsNullOrWhiteSpace($answer)){return $Default};return $answer}
$temp=$null;$code=1
try{
 $admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 if($admin){throw 'Запустите мастер обычным пользователем. Для установки защиты он сам запросит UAC.'}
 if(-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){throw 'Требуется Windows 11 x64 и 64-разрядный Windows PowerShell 5.1.'}
 $installed=Join-Path (Get-GuardRoot) 'config.json'
 if(-not $ConfigurationFile -and -not $Preview -and (Test-Path -LiteralPath $installed)){
  Write-Host 'Обнаружена установленная защита. Обновление сохранит ее параметры и завершится CheckOnly.'
  $updateArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\Update-CodeSupport.ps1")
  if($AppIdMode){$updateArgs+=@('-AppIdMode',$AppIdMode)};if($NoWatch){$updateArgs+='-NoWatch'}
  & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @updateArgs
  exit $LASTEXITCODE
 }
 $networks=@();try{$networks=@(Get-SetupNetworkChoices)}catch{Write-Host 'Автоопределение адаптера недоступно; укажите его имя вручную.'}
 $nicDefault=if($networks.Count -eq 1){$networks[0].Name}else{''}
 $family='Claude_pzs8sxrjxfjjc';try{$package=Get-AppxPackage -Name Claude | Sort-Object Version -Descending | Select-Object -First 1;if($package){$family=$package.PackageFamilyName}}catch{}
 $xrayDefault=Join-Path $env:ProgramFiles 'FlyFrogLLC\Happ\core\xray.exe'
 $defaults=[ordered]@{Schema=3;EndpointMode='Hostname';UpstreamHostname='';UpstreamAddress='';UpstreamPort=443;ProxyPort=10808;ExpectedCountry='DE';PhysicalInterface=$nicDefault;XrayPath=$xrayDefault;PackageFamily=$family;ClaudeRoot='';ClaudeExe='';BlockedInterfaces=@();UseLegacyTag=$false;LaunchUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;ShortcutPath=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude - Happ Only.lnk');CodeRoot='';CodeDataRoot=(Join-Path $env:LOCALAPPDATA 'Claude-Data')}
 if($ConfigurationFile){$inputConfig=Get-Content -LiteralPath $ConfigurationFile -Raw | ConvertFrom-Json}
 elseif($Preview -and (Test-Path -LiteralPath $installed)){$inputConfig=Get-Content -LiteralPath $installed -Raw | ConvertFrom-Json}
 else{
  Write-Host 'Claude Desktop + Code через Happ. Claude не будет запущен.'
  Write-Host 'Сначала установите Happ и Claude. В Happ подключите нужный сервер, используйте прокси, выключите TUN.'
  Write-Host 'Локальный порт Happ должен принимать SOCKS и HTTP CONNECT. Подписка и ключи не нужны этому мастеру.'
  Write-Host '';Write-Host '1/3. Сервер и локальный прокси'
  $server=Ask 'Домен или публичный IPv4 выбранного сервера Happ (НЕ URL подписки)' ''
  if([string]::IsNullOrWhiteSpace($server)){throw 'Адрес сервера обязателен.'}
  $parsed=$null;$mode='Hostname';$hostname=$server;$address=''
  if([Net.IPAddress]::TryParse($server,[ref]$parsed)){$mode='PinnedIPv4';$hostname='';$address=$parsed.ToString()}
  $inputConfig=[ordered]@{EndpointMode=$mode;UpstreamHostname=$hostname;UpstreamAddress=$address;UpstreamPort=[int](Ask 'TCP-порт сервера Happ' '443');ProxyPort=[int](Ask 'Локальный общий SOCKS/HTTP-порт Happ' '10808');ExpectedCountry=(Ask 'Требуемая страна выхода, двухбуквенный код' 'DE').ToUpperInvariant()}
  Write-Host '';Write-Host '2/3. Физическое подключение'
  foreach($net in $networks){Write-Host ('  '+$net.Name+' | IPv4 '+$net.IPv4+' | шлюз '+$net.Gateway)}
  $inputConfig['PhysicalInterface']=Ask 'Имя физического адаптера (как в списке; не VPN/TUN)' $nicDefault
  $blockedDefault='';try{if(Get-NetAdapter -Name FlClashX -ErrorAction SilentlyContinue){$blockedDefault='FlClashX'}}catch{}
  $blocked=Ask 'Запретить Happ эти виртуальные адаптеры (имена через запятую; минус = нет)' $blockedDefault
  $inputConfig['BlockedInterfaces']=if($blocked -and $blocked -ne '-'){@($blocked.Split(',') | ForEach-Object {$_.Trim()} | Where-Object {$_})}else{@()}
  Write-Host '';Write-Host '3/3. Приложения'
  $inputConfig['XrayPath']=Ask 'Путь к внутреннему xray.exe Happ' $xrayDefault
  $inputConfig['PackageFamily']=Ask 'Семейство MSIX Claude (для обычной установки оставьте найденное)' $family
  if((Ask 'Claude установлен отдельно от MSIX? y/N' 'N') -match '^[yY]'){
   $inputConfig['ClaudeRoot']=Ask 'Каталог отдельной установки Claude' ''
   $inputConfig['ClaudeExe']=Ask 'Полный путь к claude.exe' (Join-Path $inputConfig.ClaudeRoot 'claude.exe')
  }
 }
 $c=Complete-SetupConfiguration $inputConfig $defaults
 if($AppIdMode){$c | Add-Member NoteProperty AppIdMode $AppIdMode -Force}
 $temp=Join-Path $env:TEMP ('ClaudeHapp-Setup-'+[guid]::NewGuid().ToString('N')+'.json')
 $c | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temp -Encoding UTF8
 $c=Read-GuardConfig $temp
 if($Preview){$c | ConvertTo-Json -Depth 20;$code=0}
 else{
  Assert-NoClaudeClient
  Write-Host ('Установка: '+$c.EndpointMode+'; '+$c.PhysicalInterface+'; прокси 127.0.0.1:'+$c.ProxyPort+'; AppID='+$c.AppIdMode)
  $installArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\Install-Automated.ps1",'-ConfigurationFile',$temp,'-Mode','Install','-AppIdMode',$c.AppIdMode)
  if($NoWatch){$installArgs+='-NoWatch'}
  & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @installArgs
  $code=$LASTEXITCODE
  if($code -ne 0){throw 'Автоматическая установка не завершена; смотрите указанный отчет транзакции.'}
  $installBT=$InstallBrowserTamer.IsPresent
  if(-not $ConfigurationFile -and -not $installBT){$installBT=(Ask 'Установить необязательный Browser Tamer для ссылок в отдельный профиль? y/N' 'N') -match '^[yY]'}
  if($installBT){& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Install-BrowserTamer.ps1";if($LASTEXITCODE -ne 0){throw 'Защита установлена, но установка Browser Tamer не завершена.'}}
  Write-Host 'SETUP PASS. Защита и CheckOnly проверены. Claude не запускался.';$code=0
 }
}catch{$code=1;Write-Host ('SETUP FAILED: '+$_.Exception.Message) -ForegroundColor Red}
finally{if($temp -and (Test-Path -LiteralPath $temp)){try{Remove-Item -LiteralPath $temp -Force}catch{Write-Warning ('Не удалось удалить временную конфигурацию: '+$temp)}}}
exit $code
