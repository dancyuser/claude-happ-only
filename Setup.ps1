#requires -Version 5.1
param([string]$ConfigurationFile,[switch]$InstallBrowserTamer)
$ErrorActionPreference='Stop'
function Ask($label,$default){$answer=Read-Host ($label+$(if($default){' ['+$default+']'}));if([string]::IsNullOrWhiteSpace($answer)){return $default};return $answer}
$temp=$null;$code=1
try{
 if(-not [Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell'}
 if($ConfigurationFile){$c=Get-Content -Raw -LiteralPath $ConfigurationFile | ConvertFrom-Json}
 else{
  Write-Host 'Windows x64 Happ + Claude installer. Claude will NEVER be started during setup.'
  Write-Host 'Happ and Claude must already be installed. Enter the HOSTNAME of the selected Happ server, not a subscription URL.'
  $c=[ordered]@{Schema=3;UpstreamHostname=(Ask 'Selected Happ server hostname' '');UpstreamAddress='';PhysicalInterface=(Ask 'Physical network adapter name (Ethernet or Wi-Fi)' 'Ethernet');ProxyPort=[int](Ask 'Happ SOCKS port' '10808');ExpectedCountry=(Ask 'Required two-letter exit country' 'DE').ToUpperInvariant();XrayPath=(Ask 'Happ core xray.exe path' (Join-Path $env:ProgramFiles 'FlyFrogLLC\Happ\core\xray.exe'));PackageFamily=(Ask 'Claude MSIX package family (leave default for Store version)' 'Claude_pzs8sxrjxfjjc');ClaudeRoot='';ClaudeExe='';BlockedInterfaces=@();UseLegacyTag=$false;LaunchUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;ShortcutPath=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude - Happ Only.lnk')}
  if((Ask 'Standalone installation instead of MSIX? y/N' 'N') -match '^[yY]'){$c.ClaudeRoot=Ask 'Claude installation root (only its EXEs will be protected)' '';$c.ClaudeExe=Ask 'Full path to claude.exe' (Join-Path $c.ClaudeRoot 'claude.exe')}
  $c['UpstreamPort']=[int](Ask 'Selected remote server TCP port' '443')
  $blocked=Ask 'Virtual adapter names to explicitly block, comma separated; blank = none' ''
  if($blocked){$c.BlockedInterfaces=@($blocked.Split(',') | ForEach-Object {$_.Trim()} | Where-Object {$_})}
 }
 $temp=Join-Path $env:TEMP ('ClaudeHapp-Setup-'+[Guid]::NewGuid()+'.json');$c | ConvertTo-Json -Depth 5 | Set-Content $temp -Encoding UTF8
 . "$PSScriptRoot\Common.ps1";$null=Read-GuardConfig $temp
 $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Install-Elevated.ps1" -ConfigurationFile "'+$temp+'"'
 $code=Invoke-ElevatedPowerShell $arguments
 if($code -eq 0){
  $installBT=$InstallBrowserTamer.IsPresent
  if(-not $ConfigurationFile -and -not $installBT){$installBT=(Ask 'Download/install optional Browser Tamer Latest release? y/N' 'N') -match '^[yY]'}
  if($installBT){& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Install-BrowserTamer.ps1";$code=$LASTEXITCODE}
 }
}catch{Write-Host ('SETUP FAILED: '+$_.Exception.Message) -ForegroundColor Red}
finally{if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Force}}
exit $code
