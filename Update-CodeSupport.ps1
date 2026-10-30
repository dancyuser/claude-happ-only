#requires -Version 5.1
# Explicit user maintenance entry point; ends with CheckOnly and never launches Claude.
param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$setupConfig=$null;$stage='Load common helpers'
try{
 . "$PSScriptRoot\Common.ps1"
 $stage='Check ordinary user token'
 $admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 if($admin){throw 'Start this updater in ordinary PowerShell; it requests UAC for guard maintenance only'}
 $stage='Read installed guard configuration'
 $root=Get-GuardRoot;$c=Read-GuardConfig "$root\config.json"
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $c.LaunchUserSid){throw 'Wrong configured user'}
 $stage='Check client is closed (ordinary user; no AllUsers package query)'
 Assert-NoClaudeClient
 $stage='Verify source payload checksums'
 $manifest=Get-Content -LiteralPath "$PSScriptRoot\payload-hashes.json" -Raw | ConvertFrom-Json
 foreach($item in $manifest){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $item.Name)).Hash -ne $item.SHA256){throw ('Kit checksum mismatch: '+$item.Name)}}
 if($ValidateOnly){Write-Host 'VALIDATE ONLY PASS: user token, config read, client-closed check, payload hashes. No settings changed, no UAC, no Claude launch.';return}
 $stage='Apply user Code proxy settings and save user backup'
 $applied=& "$PSScriptRoot\Configure-CodeProxy.ps1" -Mode Apply -ProxyPort ([int]$c.ProxyPort) -ExpectedCountry $c.ExpectedCountry
 if(-not $applied.SettingsOK){throw 'Code settings update failed'}
 Write-Host ('USER SETTINGS BACKUP: '+$applied.BackupDirectory)
 Write-Host ('RESTORE ID: '+$applied.BackupId)
 $stage='Prepare guard update configuration'
 if(-not $c.CodeRoot){$c.CodeRoot=Join-Path $env:LOCALAPPDATA ('Claude-Data\'+$c.PackageFamily+'\claude-code')}
 $setupConfig=Join-Path $env:TEMP ('Happ-CodeSupport-'+[guid]::NewGuid().ToString('N')+'.json')
 $c | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $setupConfig -Encoding UTF8
 Write-Host 'UAC: guard backup, update, and protected HTTP/SOCKS tests. Claude will not be launched.'
 $stage='UAC guard Fix (full package and Cowork service verification)'
 $status=Invoke-ElevatedPowerShell ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Manage-Happ.ps1" -Mode Fix -SetupConfigFile "'+$setupConfig+'"')
 if($status -ne 0){throw 'Guard update failed/cancelled. See ProgramData\ClaudeHappReports. User settings backup ID is printed above.'}
 $stage='Checked launcher in CheckOnly mode'
 & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-Checked.ps1" -CheckOnly -NoPause
 if($LASTEXITCODE -ne 0){throw 'CheckOnly failed. Do not start Claude; inspect the reported findings.'}
 Write-Host 'UPDATE AND CHECKONLY PASS. Claude has not been launched. Keep it closed until you choose to test manually.'
}catch{
 Write-Host ('UPDATE INCOMPLETE at step: '+$stage) -ForegroundColor Red
 Write-Host $_.Exception.Message -ForegroundColor Red
 Write-Host ('ErrorId: '+$_.FullyQualifiedErrorId)
 Write-Host $_.ScriptStackTrace
 exit 1
}finally{
 if($setupConfig -and (Test-Path -LiteralPath $setupConfig)){try{Remove-Item -LiteralPath $setupConfig -Force}catch{Write-Warning ('Could not remove temporary config: '+$setupConfig)}}
}
