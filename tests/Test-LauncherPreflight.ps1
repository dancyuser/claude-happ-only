#requires -Version 5.1
# Real launcher, fake guard/UAC, mandatory CheckOnly. No target execution.
$ErrorActionPreference='Stop';$source=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path (Split-Path $source -Parent) ('Launcher-Fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$utf8=[Text.UTF8Encoding]::new($true)
$common=@'
function Get-GuardRoot { return $PSScriptRoot }
function Read-GuardConfig { return [pscustomobject]@{LaunchUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;ProxyPort=10808;ExpectedCountry='DE'} }
function Get-Process { param($Name,$ErrorAction); return @() }
function Invoke-ElevatedPowerShell { param($arguments)
 Add-Content "$PSScriptRoot\events.txt" 'Preflight'
 $id=[regex]::Match($arguments,'-RequestId ([a-f0-9-]+)').Groups[1].Value
 New-Item -ItemType Directory "$PSScriptRoot\LaunchTickets" -Force | Out-Null
 '{}' | Set-Content "$PSScriptRoot\LaunchTickets\$id.json"
 return 0
}
function Read-ValidatedLaunchTicket {
 param($id,$c)
 Add-Content "$PSScriptRoot\events.txt" 'Ticket'
 return [pscustomobject]@{Executable=(Join-Path $PSScriptRoot 'claude.exe')}
}
'@
$proxy=@'
param($Mode,[switch]$SettingsOnly,$ProxyPort,$ExpectedCountry)
if(-not $SettingsOnly){throw 'Transport was probed outside protected preflight'}
Add-Content "$PSScriptRoot\events.txt" 'Settings'
$bad=Test-Path "$PSScriptRoot\bad-settings.txt"
return [pscustomobject]@{SettingsOK=(-not $bad);TransportChecked=$false}
'@
[IO.File]::WriteAllText("$fixture\Common.ps1",$common,$utf8)
[IO.File]::WriteAllText("$fixture\Configure-CodeProxy.ps1",$proxy,$utf8)
Copy-Item "$source\Launch-Checked.ps1" "$fixture\Launch-Checked.ps1"
[IO.File]::WriteAllText("$fixture\claude.exe",'inert fixture - not an executable')
$exe=Join-Path $fixture 'claude.exe'
@{LaunchExecutable=$exe;Executables=@($exe)} | ConvertTo-Json | Set-Content "$fixture\state.json"
$out=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$fixture\Launch-Checked.ps1" -CheckOnly -NoPause
if($LASTEXITCODE -ne 0 -or ($out -join '') -notmatch 'CHECK ONLY PASS'){throw ('CheckOnly failed: '+($out -join ' '))}
if(((Get-Content "$fixture\events.txt") -join ',') -ne 'Settings,Preflight,Settings,Ticket'){throw 'Wrong check/repair ordering'}
'bad' | Set-Content "$fixture\bad-settings.txt"
Clear-Content "$fixture\events.txt"
$out=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$fixture\Launch-Checked.ps1" -CheckOnly -NoPause
if($LASTEXITCODE -eq 0 -or ($out -join '') -notmatch 'Code settings do not match'){throw 'Bad settings were not rejected'}
if(((Get-Content "$fixture\events.txt") -join ',') -ne 'Settings'){throw 'Bad settings reached UAC or approval'}
# Check the actual configuration script without a proxy/listener.
. "$source\CodeProxy.Common.ps1"
[IO.File]::WriteAllText("$fixture\settings.json",(ConvertTo-CodeProxySettings '' 65534),$utf8)
$r=& "$source\Configure-CodeProxy.ps1" -Mode Diagnose -SettingsOnly -SettingsPath "$fixture\settings.json" -ProxyPort 65534
if(-not $r.SettingsOK -or $r.TransportChecked -or $null -ne $r.Transport -or $r.PSObject.Properties['OverallOK']){throw 'Settings-only diagnosis pretended transport approval'}
'PASS: launcher reaches protected preflight without an early transport probe, rechecks settings, rejects invalid settings; settings-only grants no transport approval. No real UAC or target launch.'
