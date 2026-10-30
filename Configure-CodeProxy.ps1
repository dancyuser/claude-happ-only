#requires -Version 5.1
# User-scope settings only. Never launches/stops Claude or changes WFP/firewall.
[CmdletBinding()]param(
 [ValidateSet('Diagnose','Apply','Restore')][string]$Mode='Diagnose',
 [ValidateRange(1,65535)][int]$ProxyPort=10808,
 [ValidatePattern('^[A-Z]{2}$')][string]$ExpectedCountry='DE',
 [string]$SettingsPath,
 [ValidatePattern('^[a-f0-9]{32}$')][string]$BackupId
)
$ErrorActionPreference='Stop';. "$PSScriptRoot\CodeProxy.Common.ps1"
if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use ordinary PowerShell, not Administrator, for user settings'}
if(-not $SettingsPath){
 $configHome=if($env:CLAUDE_CONFIG_DIR){$env:CLAUDE_CONFIG_DIR}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude'}
 $SettingsPath=Join-Path $configHome 'settings.json'
}
$SettingsPath=[IO.Path]::GetFullPath($SettingsPath);Assert-CodeProxyPlainPath $SettingsPath
$parent=Split-Path $SettingsPath -Parent;$backupRoot=Join-Path $parent 'happ-proxy-backups'
Assert-CodeProxyPlainPath $backupRoot
$exists=Test-Path -LiteralPath $SettingsPath -PathType Leaf
$text=if($exists){Get-Content -LiteralPath $SettingsPath -Raw}else{''}
if($Mode -eq 'Restore'){
 if(-not $BackupId){throw 'Restore requires -BackupId from the Apply result'}
 if(@(Get-Process -Name claude -ErrorAction SilentlyContinue).Count){throw 'Close Claude yourself before restoring settings'}
 $backup=Join-Path $backupRoot $BackupId;Assert-CodeProxyPlainPath $backup
 $meta=Get-Content -LiteralPath "$backup\manifest.json" -Raw | ConvertFrom-Json
 if($meta.SettingsPath -cne $SettingsPath -or $meta.BackupId -cne $BackupId){throw 'Backup target mismatch'}
 if(-not $exists -or (Get-FileHash -LiteralPath $SettingsPath).Hash -ne $meta.AppliedSHA256){throw 'Settings changed since Apply; refusing to overwrite newer changes. Merge the saved copy manually.'}
 if($meta.Existed -and (Get-FileHash -LiteralPath "$backup\settings.before").Hash -ne $meta.BeforeSHA256){throw 'Backup checksum mismatch'}
 Copy-Item -LiteralPath $SettingsPath -Destination "$backup\settings.before-restore" -Force
 if($meta.Existed){Copy-Item -LiteralPath "$backup\settings.before" -Destination $SettingsPath -Force}else{Remove-Item -LiteralPath $SettingsPath}
 return [pscustomobject]@{Mode=$Mode;Restored=$true;SettingsPath=$SettingsPath;ClaudeLaunched=$false}
}
$transport=Test-CodeProxyTransport $ProxyPort $ExpectedCountry
$settingsOK=Test-CodeProxySettings $text $ProxyPort
if($Mode -eq 'Diagnose'){
 return [pscustomobject]@{Mode=$Mode;OverallOK=[bool]($transport.OK -and $settingsOK);SettingsPath=$SettingsPath;SettingsOK=$settingsOK;Transport=$transport;ClaudeLaunched=$false;Scope='User settings + HTTP proxy only; WFP and project/managed overrides require separate checks'}
}
if(-not $transport.OK){throw ('HTTP proxy/country test failed; settings unchanged. '+($transport | ConvertTo-Json -Compress))}
if(@(Get-Process -Name claude -ErrorAction SilentlyContinue).Count){throw 'Close Claude yourself before applying settings. No process was stopped.'}
# Re-read after probes to preserve edits made during the network check.
$exists=Test-Path -LiteralPath $SettingsPath -PathType Leaf
$text=if($exists){Get-Content -LiteralPath $SettingsPath -Raw}else{''}
$updated=ConvertTo-CodeProxySettings $text $ProxyPort
$id=[guid]::NewGuid().ToString('N');$backup=Join-Path $backupRoot $id
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$meta=[ordered]@{BackupId=$id;SettingsPath=$SettingsPath;Existed=[bool]$exists;BeforeSHA256='';AppliedSHA256='';CreatedUTC=[DateTime]::UtcNow.ToString('o')}
if($exists){Copy-Item -LiteralPath $SettingsPath -Destination "$backup\settings.before";$meta.BeforeSHA256=(Get-FileHash -LiteralPath "$backup\settings.before").Hash}
$pending=Join-Path $parent ('settings.happ-'+$id+'.tmp')
try{
 [IO.File]::WriteAllText($pending,$updated,[Text.UTF8Encoding]::new($false))
 if(-not(Test-CodeProxySettings (Get-Content -LiteralPath $pending -Raw) $ProxyPort)){throw 'Generated settings failed validation'}
 $meta.AppliedSHA256=(Get-FileHash -LiteralPath $pending).Hash
 $meta | ConvertTo-Json | Set-Content "$backup\manifest.json" -Encoding UTF8
 # Reject concurrent changes rather than overwriting them.
 if($exists){if((Get-FileHash -LiteralPath $SettingsPath).Hash -ne $meta.BeforeSHA256){throw 'Concurrent settings edit; refusing update'}}elseif(Test-Path -LiteralPath $SettingsPath){throw 'Settings created concurrently; refusing update'}
 Move-Item -LiteralPath $pending -Destination $SettingsPath -Force
}finally{if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending}}
return [pscustomobject]@{Mode=$Mode;SettingsOK=(Test-CodeProxySettings (Get-Content -LiteralPath $SettingsPath -Raw) $ProxyPort);SettingsPath=$SettingsPath;BackupId=$id;BackupDirectory=$backup;Transport=$transport;ClaudeLaunched=$false}
