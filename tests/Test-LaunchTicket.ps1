#requires -Version 5.1
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\Common.ps1"
$script:fixture=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ('Happ-Ticket-Fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $script:fixture 'LaunchTickets') -Force | Out-Null
function Get-GuardRoot {return $script:fixture}
$exe=Join-Path $fixture 'claude.exe';[IO.File]::WriteAllText($exe,'NONEXECUTABLE TICKET FIXTURE')
$c=[pscustomobject]@{LaunchUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;AppIdRequired=$false}
$c | ConvertTo-Json | Set-Content "$fixture\config.json" -Encoding UTF8
[pscustomobject]@{LaunchExecutable=$exe;Executables=@($exe)} | ConvertTo-Json | Set-Content "$fixture\state.json" -Encoding UTF8
$id=[guid]::NewGuid();$path=Join-Path $fixture ('LaunchTickets\'+$id+'.json')
$ticket=[pscustomobject]@{OK=$true;RequestId=$id.ToString();UserSid=$c.LaunchUserSid;Executable=$exe;FinishedUTC=[DateTime]::UtcNow.ToString('o');ConfigSHA256=(Get-FileHash "$fixture\config.json").Hash}
function Write-Ticket {$ticket | ConvertTo-Json | Set-Content $path -Encoding UTF8}
Write-Ticket;$null=Read-ValidatedLaunchTicket $id $c
$ticket.FinishedUTC=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');Write-Ticket
$rejected=$false;try{$null=Read-ValidatedLaunchTicket $id $c}catch{$rejected=$true};if(-not $rejected){throw 'Stale ticket accepted'}
$ticket.FinishedUTC=[DateTime]::UtcNow.ToString('o');$ticket.UserSid='S-1-5-18';Write-Ticket
$rejected=$false;try{$null=Read-ValidatedLaunchTicket $id $c}catch{$rejected=$true};if(-not $rejected){throw 'Wrong user accepted'}
$ticket.UserSid=$c.LaunchUserSid;$c.AppIdRequired=$true
$c | ConvertTo-Json | Set-Content "$fixture\config.json" -Encoding UTF8
$ticket.ConfigSHA256=(Get-FileHash "$fixture\config.json").Hash
[IO.File]::WriteAllText("$fixture\AppId-state.json",'{"fixture":true}')
$ticket | Add-Member NoteProperty AppIdSHA256 (Get-FileHash "$fixture\AppId-state.json").Hash
Write-Ticket;$null=Read-ValidatedLaunchTicket $id $c
[IO.File]::AppendAllText("$fixture\AppId-state.json",' ')
$rejected=$false;try{$null=Read-ValidatedLaunchTicket $id $c}catch{$rejected=$true};if(-not $rejected){throw 'Changed AppID state accepted'}
'PASS: shared installer/launcher ticket validation, stale/user refusal and AppID-state fingerprint binding. No target launch.'
