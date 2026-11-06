#requires -Version 5.1
# Explicit user launch only. Agent tests MUST NOT invoke this entry point.
param([Parameter(Mandatory)][guid]$ProfileId,[string]$Executable,[string[]]$ApplicationArguments=@())
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1";. "$PSScriptRoot\Universal.Common.ps1"
try{
 if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Start as ordinary configured user'}
 $profile=Join-Path (Get-UniversalRoot) ('Profiles\'+$ProfileId)
 $c=ConvertTo-UniversalProfile (Get-Content "$profile\config.json" -Raw|ConvertFrom-Json)
 if($c.LaunchUserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Wrong configured user'}
 if(-not $Executable){$Executable=$c.Programs[0]};$Executable=[IO.Path]::GetFullPath($Executable)
 if($Executable -notin $c.Programs){throw 'Executable is not in protected profile'}
 $id=[guid]::NewGuid()
 $exit=Invoke-ElevatedPowerShell ('-NoProfile -ExecutionPolicy Bypass -File "'+$profile+'\Universal.Worker.ps1" -Mode Test -ProfileId '+$ProfileId+' -RequestId '+$id)
 if($exit -ne 0){throw 'Network test failed; application not started'}
 $r=Get-Content (Join-Path (Get-UniversalRoot) ('Reports\'+$id+'\result.json')) -Raw|ConvertFrom-Json
 $age=([DateTime]::UtcNow-[DateTime]::Parse($r.FinishedUTC).ToUniversalTime()).TotalSeconds
 if($r.Status -ne 'TESTED' -or -not $r.Ready -or $r.ProfileId -ne $ProfileId.ToString() -or $age -lt 0 -or $age -gt 30 -or $r.ConfigSHA256 -ne (Get-FileHash "$profile\config.json").Hash -or $r.StateSHA256 -ne (Get-FileHash "$profile\state.json").Hash -or (Test-Path "$profile\maintenance.json")){throw 'Stale or mismatched launch check'}
 $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=$Executable;$si.UseShellExecute=$false;$si.WorkingDirectory=Split-Path $Executable -Parent
 # Quote individual native arguments using Windows CommandLineToArgvW rules.
 $quoted=@(foreach($a in $ApplicationArguments){'"'+[regex]::Replace([regex]::Replace($a,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'})
 $si.Arguments=$quoted -join ' '
 foreach($k in @($si.EnvironmentVariables.Keys|Where-Object {$_ -match '^(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)$'})){$si.EnvironmentVariables.Remove($k)}
 if($c.Mode -eq 'TunProxy'){$url=$c.Proxy.Scheme+'://127.0.0.1:'+$c.Proxy.Port;foreach($k in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){$si.EnvironmentVariables[$k]=$url};$si.EnvironmentVariables['NO_PROXY']=''}
 $p=[Diagnostics.Process]::Start($si);$p.Dispose()
}catch{Write-Host ('APPLICATION NOT STARTED: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
