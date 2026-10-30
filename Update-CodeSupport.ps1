#requires -Version 5.1
# Normal-user updater. One elevated worker, final preflight, no Claude launch.
param([switch]$ValidateOnly,[ValidateSet('Auto','Off','Require')][string]$AppIdMode,[switch]$NoWatch)
$ErrorActionPreference='Stop';$temp=$null
try{
 . "$PSScriptRoot\Common.ps1"
 if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Start updater as ordinary target user'}
 $c=Read-GuardConfig (Join-Path (Get-GuardRoot) 'config.json')
 if($c.LaunchUserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Wrong configured user'}
 Assert-NoClaudeClient
 $manifest=Get-Content "$PSScriptRoot\payload-hashes.json" -Raw | ConvertFrom-Json
 foreach($item in $manifest){if((Get-FileHash (Join-Path $PSScriptRoot $item.Name)).Hash -ne $item.SHA256){throw ('Payload mismatch: '+$item.Name)}}
 if($ValidateOnly){Write-Host 'VALIDATE ONLY PASS. No changes, no UAC, no Claude launch.';return}
 if(-not $c.CodeRoot){$c.CodeRoot=Join-Path $env:LOCALAPPDATA ('Claude-Data\'+$c.PackageFamily+'\claude-code')}
 if($AppIdMode){$c.AppIdMode=$AppIdMode}
 $temp=Join-Path $env:TEMP ('ClaudeHapp-Update-'+[guid]::NewGuid().ToString('N')+'.json')
 $c | ConvertTo-Json -Depth 20 | Set-Content $temp -Encoding UTF8
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\Install-Automated.ps1",'-ConfigurationFile',$temp,'-Mode','Fix','-AppIdMode',$c.AppIdMode)
 if($NoWatch){$arguments+='-NoWatch'}
 & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @arguments
 if($LASTEXITCODE -ne 0){throw 'Automated update incomplete; inspect transaction report'}
 Write-Host 'UPDATE AND CHECKONLY PASS. Claude was not launched.'
}catch{Write-Host ('UPDATE INCOMPLETE: '+$_.Exception.Message) -ForegroundColor Red;Write-Host $_.ScriptStackTrace;exit 1}
finally{if($temp -and (Test-Path $temp)){Remove-Item -LiteralPath $temp -Force}}
