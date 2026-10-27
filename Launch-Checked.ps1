#requires -Version 5.1
# ONLY this script contains the user-requested Claude launch branch.
# Agent validation MUST use -CheckOnly. Preflight/Install/Fix never launch Claude.
param([switch]$CheckOnly,[switch]$NoPause)
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1"
$code=1
try{
 $admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 if($admin){throw 'Run this shortcut normally, not as Administrator. Claude must use the ordinary user token.'}
 $root=Get-GuardRoot;$c=Read-GuardConfig "$root\config.json";$userSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($userSid -ne $c.LaunchUserSid){throw 'Shortcut belongs to a different configured user'}
 $id=[Guid]::NewGuid();Write-Host 'Checking tunnel. A UAC request will open for checks/repair only. Claude is not running yet.'
 $exit=Invoke-ElevatedPowerShell ('-NoProfile -ExecutionPolicy Bypass -File "'+$root+'\Preflight.ps1" -RequestId '+$id)
 $path=Join-Path $root ('LaunchTickets\'+$id+'.json')
 if($exit -ne 0 -or -not(Test-Path -LiteralPath $path)){throw ('Preflight failed/cancelled. Claude will NOT start. Ticket: '+$path)}
 $t=Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
 $age=([DateTime]::UtcNow-[DateTime]::Parse($t.FinishedUTC).ToUniversalTime()).TotalSeconds
 if(-not $t.OK -or $t.RequestId -ne $id.ToString() -or $t.UserSid -ne $userSid -or $age -lt 0 -or $age -gt 30 -or $t.ConfigSHA256 -ne (Get-FileHash "$root\config.json").Hash){throw 'Invalid, stale, or mismatched preflight result'}
 $state=Get-Content -Raw "$root\state.json" | ConvertFrom-Json
 if(Test-Path "$root\maintenance.txt"){throw 'Restore/maintenance incomplete. Finish Restore or Fix successfully before launch.'}
 if($t.Executable -ne $state.LaunchExecutable -or $t.Executable -notin $state.Executables -or -not(Test-Path -LiteralPath $t.Executable) -or [IO.Path]::GetFileName($t.Executable) -ne 'claude.exe'){throw 'Claude installation changed after check; run again'}
 # The elevated preflight has verified the background CoworkVMService separately.
 if(@(Get-Process -Name claude -ErrorAction SilentlyContinue).Count){throw 'Claude already started by another action; this launcher will not start another instance'}
 if($CheckOnly){Write-Host ('CHECK ONLY PASS. Claude NOT started. '+$path);$code=0}
 else{
  $arguments='--proxy-server=socks5://127.0.0.1:'+$c.ProxyPort+' --proxy-bypass-list=<-loopback> --disable-quic'
  Start-Process -FilePath $t.Executable -ArgumentList $arguments -WorkingDirectory (Split-Path $t.Executable -Parent)
  $code=0
 }
}catch{Write-Host ('CLAUDE NOT STARTED: '+$_.Exception.Message) -ForegroundColor Red}
if($code -ne 0 -and -not $NoPause){Read-Host 'Press Enter to close'}
exit $code
