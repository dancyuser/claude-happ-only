#requires -Version 5.1
# Elevated worker. Only its private diagnostic curl can be executed here.
param([ValidateSet('Install','Verify','Test','Restore')][string]$Mode,[Parameter(Mandatory)][guid]$ProfileId,[Parameter(Mandatory)][guid]$RequestId,[string]$ConfigurationFile,[string]$ConfigSHA256,[guid]$BackupId,[string]$EngineLibrary,[string]$EngineSHA256)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1";. "$PSScriptRoot\BackupRestore.ps1";. "$PSScriptRoot\Universal.Common.ps1"
$engine=$null;$mutex=$null;$locked=$false;$report=$null;$result=[ordered]@{Status='FAIL';Mode=$Mode;ProfileId=$ProfileId.ToString();ClaudeLaunched=$false;ApplicationsLaunched=$false;Error=''}
$committed=$false;$old=$null;$newKeys=@();$profile=$null;$maintenanceStarted=$false
function Save-U($Value,$Path){$Value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $Path -Encoding UTF8}
function Backup-U {
 $id=[guid]::NewGuid().ToString();$dir=Join-Path $profile ('Backups\'+$id);Set-ProtectedDirectory $dir
 $entries=@();foreach($name in @('config.json','state.json','Diagnostic-curl.exe','Universal.Common.ps1','Universal.Worker.ps1','Universal.Wfp.cs','Universal.Engine.dll','Universal-Guard.ps1','Start-Universal.ps1','Common.ps1','BackupRestore.ps1')){
  $path=Join-Path $profile $name;if(Test-Path -LiteralPath $path){Assert-UniversalPlainPath $path;Copy-Item -LiteralPath $path -Destination (Join-Path $dir $name);$entries+=@([pscustomobject]@{Name=$name;SHA256=(Get-FileHash -LiteralPath $path).Hash})}
 }
 Save-U ([pscustomobject]@{ProfileId=$ProfileId.ToString();Machine=(Get-MachineBinding);HadState=[bool]$old;Files=$entries}) "$dir\manifest.json"
 $result['BackupId']=$id;return $dir
}
function Read-UBackup([string]$Dir){
 Assert-UniversalPlainPath $Dir;Assert-ProtectedBackupItem $Dir;Assert-ProtectedBackupItem "$Dir\manifest.json"
 $meta=Get-Content "$Dir\manifest.json" -Raw|ConvertFrom-Json
 if($meta.ProfileId -ne $ProfileId.ToString() -or $meta.Machine -ne (Get-MachineBinding)){throw 'Backup machine/profile mismatch'}
 $allowed=@('config.json','state.json','Diagnostic-curl.exe','Universal.Common.ps1','Universal.Worker.ps1','Universal.Wfp.cs','Universal.Engine.dll','Universal-Guard.ps1','Start-Universal.ps1','Common.ps1','BackupRestore.ps1')
 foreach($f in $meta.Files){if($f.Name -notin $allowed){throw 'Unexpected backup entry'};$p=Join-Path $Dir $f.Name;Assert-ProtectedBackupItem $p;if((Get-FileHash -LiteralPath $p).Hash -ne $f.SHA256){throw 'Backup checksum mismatch'}}
 return $meta
}
function Restore-UFiles($Dir,$Meta){foreach($f in $Meta.Files){Copy-Item -LiteralPath (Join-Path $Dir $f.Name) -Destination (Join-Path $profile $f.Name) -Force;Set-ProtectedFile (Join-Path $profile $f.Name)}}
try{
 if(-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator required'}
 if(-not [Environment]::Is64BitProcess){throw '64-bit Windows PowerShell required'}
 $root=Get-UniversalRoot;Assert-UniversalPlainPath $root;Set-ProtectedDirectory $root
 $profile=Join-Path $root ('Profiles\'+$ProfileId.ToString());Assert-UniversalPlainPath $profile
 $mutex=[Threading.Mutex]::new($false,('Global\UniversalNetworkGuard-'+$ProfileId));$locked=$mutex.WaitOne(0);if(-not $locked){throw 'Profile maintenance is already running'}
 $report=Join-Path $root ('Reports\'+$RequestId);Assert-UniversalPlainPath $report;if(Test-Path $report){throw 'Request ID already used'};Set-ProtectedDirectory $report
 if($Mode -eq 'Install'){
  if((Get-FileHash -LiteralPath $ConfigurationFile).Hash -ne $ConfigSHA256){throw 'Config changed during elevation'}
  Copy-Item -LiteralPath $ConfigurationFile -Destination "$report\candidate.json"
  if((Get-FileHash "$report\candidate.json").Hash -ne $ConfigSHA256){throw 'Protected config copy mismatch'}
  $c=ConvertTo-UniversalProfile (Get-Content "$report\candidate.json" -Raw|ConvertFrom-Json)
 }else{$c=ConvertTo-UniversalProfile (Get-Content "$profile\config.json" -Raw|ConvertFrom-Json)}
 if($c.ProfileId -ne $ProfileId.ToString()){throw 'Wrong profile ID'}
 if($Mode -in @('Install','Restore')){Assert-UniversalClientsClosed $c}
 if(Test-Path "$profile\state.json"){$old=Get-Content "$profile\state.json" -Raw|ConvertFrom-Json;if($old.Machine -ne (Get-MachineBinding) -or $old.ProfileId -ne $ProfileId.ToString()){throw 'Installed state machine/profile mismatch'}}
 # Compile as the ordinary user; only load a checksum-bound library after UAC.
 $enginePath=Join-Path $profile 'Universal.Engine.dll'
 if($Mode -eq 'Install'){
  if(-not $EngineLibrary -or $EngineSHA256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Prepared WFP engine required'}
  Assert-UniversalPlainPath $EngineLibrary
  if((Get-FileHash -LiteralPath $EngineLibrary).Hash -ne $EngineSHA256){throw 'Prepared WFP engine changed during elevation'}
  $enginePath=Join-Path $report 'Universal.Engine.dll';Copy-Item -LiteralPath $EngineLibrary -Destination $enginePath
  if((Get-FileHash -LiteralPath $enginePath).Hash -ne $EngineSHA256){throw 'Protected WFP engine copy mismatch'}
 }else{
  $savedEngine=@($old.Runtime|Where-Object Name -eq 'Universal.Engine.dll')
  if($savedEngine.Count -ne 1 -or (Get-FileHash -LiteralPath $enginePath).Hash -ne $savedEngine[0].SHA256){throw 'Prepared WFP engine absent/changed; reinstall with the current installer'}
 }
 $null=[Reflection.Assembly]::LoadFrom($enginePath)
 $engine=[UniversalWfp]::new($ProfileId.ToString())
 if($Mode -eq 'Restore'){
  $dir=Join-Path $profile ('Backups\'+$BackupId.ToString());$meta=Read-UBackup $dir
  $safety=Backup-U;Save-U @{Reason='Restore';Request=$RequestId.ToString()} "$profile\maintenance.json";$maintenanceStarted=$true
  $before=$old;$restore=$null;if($meta.HadState){$restore=Get-Content "$dir\state.json" -Raw|ConvertFrom-Json}
  $engine.Begin();$keep=@();if($restore){$keep=@(Set-UniversalRules $engine $restore.Plan)}
  foreach($key in @($old.Keys)){if($key -and $key -notin $keep){$engine.DeleteOwned($key)}}
  $engine.Commit();$committed=$true;$newKeys=$keep
  if($restore){Restore-UFiles $dir $meta}else{foreach($name in @('config.json','state.json')){if(Test-Path "$profile\$name"){Remove-Item -LiteralPath "$profile\$name"}}}
  Remove-Item -LiteralPath "$profile\maintenance.json";$maintenanceStarted=$false
  $result.Status='RESTORED';$result['Installed']=[bool]$restore;$result['NetworkTest']='Not performed; Test required before launch';$result['SafetyBackup']=$result.BackupId
 }else{
  $binding=Resolve-UniversalBinding $c @(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
  if($binding.Present){$binding.Luid=[string][UniversalWfp]::InterfaceLuid($binding.Guid)}
  $probe=Join-Path $profile 'Diagnostic-curl.exe';$plan=@(New-UniversalPlan $c $binding $probe)
  if($Mode -eq 'Install'){
   $legacyState=Join-Path $env:ProgramData 'ClaudeHappOnly\state.json'
   if(Test-Path $legacyState){$legacy=Get-Content $legacyState -Raw|ConvertFrom-Json;if(@($c.Programs|Where-Object {$_ -in $legacy.Executables}).Count){throw 'Client is already covered by the Claude/Happ preset. Restore/remove its old restrictions deliberately before migration; no automatic weakening.'}}
   foreach($other in @(Get-ChildItem (Join-Path $root 'Profiles') -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -ne $ProfileId.ToString()})){
    if(Test-Path "$($other.FullName)\config.json"){$oc=Get-Content "$($other.FullName)\config.json" -Raw|ConvertFrom-Json;if(@($c.Programs|Where-Object {$_ -in $oc.Programs}).Count){throw 'An EXE is already protected by another universal profile. Update that profile instead of stacking conflicting policies.'}}
   }
   foreach($p in @($c.Programs)+$(if($c.Mode -eq 'TunProxy'){@($c.Proxy.Executable)}elseif($c.KillSwitchScope -eq 'InterfaceAndCore'){@($c.VpnCore.Executable)}else{@()})){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('EXE missing: '+$p)}}
   Set-ProtectedDirectory $profile;$backup=Backup-U
   Save-U @{Reason='Install';Request=$RequestId.ToString();Plan=$plan} "$profile\maintenance.json";$maintenanceStarted=$true
   $runtime=@('Universal.Common.ps1','Universal.Worker.ps1','Universal.Wfp.cs','Universal.Engine.dll','Universal-Guard.ps1','Start-Universal.ps1','Common.ps1','BackupRestore.ps1')
   foreach($name in $runtime){$from=if($name -eq 'Universal.Engine.dll'){$enginePath}else{Join-Path $PSScriptRoot $name};$to=Join-Path $profile $name;if($from -ine $to){Copy-Item -LiteralPath $from -Destination $to -Force};Set-ProtectedFile $to}
   Copy-Item -LiteralPath "$env:SystemRoot\System32\curl.exe" -Destination $probe -Force;Set-ProtectedFile $probe
   Save-U $c "$profile\config.json";Set-ProtectedFile "$profile\config.json"
   $engine.Begin();$newKeys=@(Set-UniversalRules $engine $plan)
   foreach($key in @($old.Keys)){if($key -and $key -notin $newKeys){$engine.DeleteOwned($key)}}
   $state=[pscustomobject]@{Schema=1;ProfileId=$ProfileId.ToString();Machine=(Get-MachineBinding);InstalledUTC=[DateTime]::UtcNow.ToString('o');Keys=$newKeys;Plan=$plan;Binding=$binding;ConfigSHA256=(Get-FileHash "$profile\config.json").Hash;ProbeSHA256=(Get-FileHash $probe).Hash;Runtime=@($runtime|ForEach-Object {[pscustomobject]@{Name=$_;SHA256=(Get-FileHash (Join-Path $profile $_)).Hash}})}
   Save-U $state "$profile\state.json.pending";$engine.Commit();$committed=$true
   Move-Item -LiteralPath "$profile\state.json.pending" -Destination "$profile\state.json" -Force;Set-ProtectedFile "$profile\state.json"
   Remove-Item -LiteralPath "$profile\maintenance.json";$maintenanceStarted=$false
   $result.Status='PROTECTED';$result['Ready']=$false;$result['NetworkTest']='Run Test before launch';$result['Binding']=$binding
   }
   if($Mode -in @('Install','Verify','Test')){
   if($Mode -eq 'Install'){$old=$state}
   if(-not $old -or (Test-Path "$profile\maintenance.json")){throw 'Profile absent or maintenance incomplete'}
   if((Get-FileHash "$profile\config.json").Hash -ne $old.ConfigSHA256 -or (Get-FileHash $probe).Hash -ne $old.ProbeSHA256){throw 'Installed config/probe checksum mismatch'}
   foreach($f in $old.Runtime){if($f.Name -notin @('Universal.Common.ps1','Universal.Worker.ps1','Universal.Wfp.cs','Universal.Engine.dll','Universal-Guard.ps1','Start-Universal.ps1','Common.ps1','BackupRestore.ps1') -or (Get-FileHash (Join-Path $profile $f.Name)).Hash -ne $f.SHA256){throw 'Installed runtime checksum mismatch'}}
   $engine.VerifyOnly=$true;$keys=@(Set-UniversalRules $engine $plan)
   if((@($keys|Sort-Object)-join ',') -ne (@($old.Keys|Sort-Object)-join ',')){throw 'Interface or policy changed: reinstall this profile; no adapter selected by name'}
   if(-not $binding.Up){throw 'Selected interface is absent/down; restrictions retained'}
   $result.Status='VERIFIED';$result['Ready']=$false
   if($Mode -in @('Install','Test')){
    $resolveArguments=@();if($c.Mode -eq 'TunOnly'){$resolveArguments=@(Get-UniversalProbeResolveArguments @('www.cloudflare.com','api.ipify.org'))}
    $arguments=@('--ipv4','--noproxy','*')+@($resolveArguments)
    if($c.Mode -eq 'TunProxy'){
     $listen=@(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort ([int]$c.Proxy.Port) -State Listen -ErrorAction SilentlyContinue)
     if($listen.Count -ne 1){throw 'Configured loopback proxy is not listening'}
     $owner=Get-CimInstance Win32_Process -Filter ('ProcessId='+$listen[0].OwningProcess)
     if($owner.ExecutablePath -ine $c.Proxy.Executable){throw 'Loopback proxy listener belongs to another EXE'}
     $arguments=@('--ipv4','--proxy',($c.Proxy.Scheme+'://127.0.0.1:'+$c.Proxy.Port),'--noproxy','invalid.invalid')
    }
    $a=Invoke-UniversalCurl $probe (@($arguments)+@('https://www.cloudflare.com/cdn-cgi/trace'))
    $b=Invoke-UniversalCurl $probe (@($arguments)+@('https://api.ipify.org'))
    $ip='';$country='';foreach($line in ($a.Body -split '\r?\n')){if($line -match '^ip=(.+)$'){$ip=$matches[1]};if($line -match '^loc=(.+)$'){$country=$matches[1]}}
    $result['Transport']=[pscustomobject]@{Trace=$a;Ipify=$b;IP=$ip;Country=$country;SplitRoutingObserved=($ip -ne $b.Body)}
    if($a.Code -ne 0 -or $b.Code -ne 0 -or -not (Test-UniversalProbeConsistency $c $ip $country $b.Body)){throw 'Protected probe failed IP/country consistency check'}
    if($c.Mode -eq 'TunProxy'){$negative=Invoke-UniversalCurl $probe @('--ipv4','--noproxy','*','https://api.ipify.org')}
    else{
     $other=@(Get-NetAdapter -IncludeHidden | Where-Object {$_.Status -eq 'Up' -and $_.HardwareInterface -and ([string]$_.InterfaceGuid).Trim('{}') -ine $binding.Guid}|Sort-Object ifIndex|Select-Object -First 1)
     if(-not $other.Count){throw 'No other physical adapter available for bypass test; no launch approval'}
     $addr=@(Get-NetIPAddress -InterfaceIndex $other[0].ifIndex -AddressFamily IPv4|Where-Object {$_.IPAddress -notlike '169.254.*'}|Select-Object -First 1)
     if(-not $addr.Count){throw 'No physical IPv4 for bypass test'}
     $negative=Invoke-UniversalCurl $probe (@('--ipv4','--interface',$addr[0].IPAddress,'--noproxy','*')+@($resolveArguments)+@('https://api.ipify.org'))
    }
    $result['BypassTest']=$negative;if($negative.Code -eq 0){throw 'BYPASS DETECTED: no launch approval'}
    $engine.VerifyOnly=$false;$faultKeys=@()
    try{$engine.Begin();$faultKeys=@($engine.BlockProgram($probe,$false));$engine.Commit();$fault=Invoke-UniversalCurl $probe (@($arguments)+@('https://api.ipify.org'));if($fault.Code -eq 0){throw 'Fault block failed'}}finally{if($faultKeys.Count){$engine.Begin();foreach($key in $faultKeys){$engine.DeleteOwned($key)};$engine.Commit()}}
    $result['FaultTest']=$fault;$result['ActualTunnelDisconnected']=$false
    $result.Status='TESTED';$result['Ready']=$true;$result['NetworkTest']='Passed';$result['KillSwitchScope']=$(if($c.Mode -eq 'TunOnly'){$c.KillSwitchScope}else{'ProxyEndpointAndInterface'});$result['CoreTrafficTest']='Not separately tested; endpoint filters verified';$result['ConfigSHA256']=$old.ConfigSHA256;$result['StateSHA256']=(Get-FileHash "$profile\state.json").Hash
   }
  }
 }
}catch{
  $result.Error=$_.Exception.Message;$result.Status='FAIL';$result['Ready']=$false;if($committed){$result['RestrictionsRetained']=$true}
 if($maintenanceStarted -and $Mode -eq 'Install'){
  try{if($engine){$engine.Dispose();$engine=[UniversalWfp]::new($ProfileId.ToString());$engine.Begin();$keep=@();if($old){$keep=@(Set-UniversalRules $engine $old.Plan)};foreach($key in $newKeys){if($key -notin $keep){$engine.DeleteOwned($key)}};$engine.Commit()};$meta=Read-UBackup $backup;Restore-UFiles $backup $meta;if(-not $old){foreach($name in @('config.json','state.json')){if(Test-Path "$profile\$name"){Remove-Item -LiteralPath "$profile\$name"}}};Remove-Item -LiteralPath "$profile\maintenance.json";$result['Rollback']='Complete'}catch{$result['Rollback']='NeedsReview: '+$_.Exception.Message}
 }
}finally{
 $result['FinishedUTC']=[DateTime]::UtcNow.ToString('o');if($report){Save-U $result "$report\result.json"};if($engine){$engine.Dispose()};if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
}
if($result.Status -eq 'FAIL'){Write-Host ('UNIVERSAL GUARD FAILED: '+$result.Error) -ForegroundColor Red;Write-Host ('Report: '+$report);exit 1}
Write-Host ('UNIVERSAL GUARD '+$result.Status+'; report: '+$report+'\result.json');exit 0
