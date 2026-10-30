#requires -Version 5.1
param([Parameter(Mandatory)][string]$BackupId)
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1";. "$PSScriptRoot\BackupRestore.ps1"
$root=Get-GuardRoot;$mutex=$null;$locked=$false;$taskPaused=$false;$currentTask=$null;$restored=$false;$out=$null;$native=$null;$gated=$false
try{
 Assert-NoClaude
 if(-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator required'}
 $mutex=[Threading.Mutex]::new($false,'Global\ClaudeHappSetupV3');$locked=$mutex.WaitOne(0);if(-not $locked){throw 'Another install/fix/restore is running'}
 $verified=Read-VerifiedBackup $BackupId;$dir=$verified.Directory;$meta=$verified.Metadata
 if(-not $meta.HadGuard){throw 'This snapshot predates guard installation. Automatic restore will not remove the last protection; use a snapshot with HadGuard=True. This is restore, not an uninstaller.'}
 if($meta.Maintenance){throw 'Snapshot was taken during incomplete restore/maintenance. Choose an earlier snapshot with Maintenance=False.'}
 $target=Read-GuardConfig "$dir\files\config.json";$inventory=Get-ClaudeInventory $target
 $current=Read-GuardConfig "$root\config.json";$currentInventory=Get-ClaudeInventory $current
 if($current.ProxyPort -ne $target.ProxyPort -or $current.XrayPath -ne $target.XrayPath){throw 'Cross-port/core migration requires separate review; restore refused before changes'}
 $savedRules=@(Read-JSONArray "$dir\firewall-rules.json");$available=(Get-Command New-NetFirewallRule).Parameters
 foreach($rule in $savedRules){if($rule.Name -notin $script:GuardRules){throw 'Unknown firewall rule in backup'};if($rule.Exists){foreach($p in $rule.Parameters.PSObject.Properties){if(-not $available.ContainsKey($p.Name)){throw ('Unsupported firewall parameter '+$p.Name)}}}}
 $taskXml=$null;if($meta.TaskExists){$taskXml=Get-Content -Raw "$dir\task.xml";[xml]$doc=$taskXml;$exec=$doc.SelectSingleNode('//*[local-name()="Actions"]/*[local-name()="Exec"]');if($exec.Command -ne "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -or $exec.Arguments -notmatch ('-File "'+[regex]::Escape($root+'\Run-Sync.ps1')+'"')){throw 'Snapshot task has an unexpected executable/action'}}
 $raw=@(Read-JSONArray "$dir\wfp-owned.json")
 if(-not('GuardWfpSnapshot' -as [type])){Add-Type -Path "$PSScriptRoot\WfpSnapshot.cs"}
 $saved=@($raw | ForEach-Object {Convert-SavedFilter $_})
 # Validate every native record in an aborted transaction before changing files or policies.
 $native=[GuardWfpSnapshot]::new();$native.Begin();foreach($f in $native.ExportOwned()){$native.Delete($f.Key)};foreach($f in $saved){$native.ImportOwned($f)};$native.Dispose();$native=$null
 $currentTask=Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -ErrorAction SilentlyContinue;$beforeXml='';if($currentTask){$beforeXml=Export-ScheduledTask -InputObject $currentTask;Disable-ScheduledTask -InputObject $currentTask | Out-Null;$taskPaused=$true;for($i=0;$i -lt 15;$i++){if((Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync).State -ne 'Running'){break};Start-Sleep -Seconds 1};if((Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync).State -eq 'Running'){throw 'Sync still running'}}
 $safety=New-GuardBackup $current $beforeXml ([bool]$currentTask) ('Before-Restore-'+$BackupId)
 $out=Join-Path (Join-Path $env:ProgramData 'ClaudeHappReports') ('restore-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'));New-Item -ItemType Directory -Path $out | Out-Null
 Start-Transcript "$out\restore.log" | Out-Null
 Save-JSON @{BackupId=$BackupId;SafetyBackup=$safety;ClaudeLaunched=$false;Status='RESTORING'} "$out\result.json"
 'Restore in progress or incomplete; run Restore/Fix successfully before launch.' | Set-Content "$root\maintenance.txt" -Encoding UTF8
 # Two contradictory proxy-port restrictions temporarily deny all new connections from Claude EXEs.
 $native=[GuardWfpSnapshot]::new();$native.Begin()
 foreach($file in @(@($currentInventory.Files.FullName)+@($inventory.Files.FullName) | Sort-Object -Unique)){$null=$native.RestrictProgram($file,'127.0.0.1',[int]$target.ProxyPort,$true);$null=$native.RestrictProgram($file,'127.0.0.1',([int]$target.ProxyPort+1),$true)}
 $native.Commit();$gated=$true
 foreach($rule in $savedRules){Get-NetFirewallRule -Name $rule.Name -PolicyStore PersistentStore -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  if($rule.Exists){$args=@{};foreach($p in $rule.Parameters.PSObject.Properties){$args[$p.Name]=$p.Value};New-NetFirewallRule @args -PolicyStore PersistentStore | Out-Null}
 }
 $beforeRoutes=@(Read-JSONArray "$dir\routes-before.json");$journal=@(Read-JSONArray "$dir\route-journal.json")
 foreach($route in $journal){
  if($route.Prefix -notmatch '^\d+\.\d+\.\d+\.\d+/32$' -or $route.Store -notin @('ActiveStore','PersistentStore')){throw 'Invalid route journal'}
  $wasPresent=@($beforeRoutes | Where-Object {$_.Store -eq $route.Store -and $_.Prefix -eq $route.Prefix -and $_.InterfaceIndex -eq $route.InterfaceIndex -and $_.NextHop -eq $route.NextHop})
  if(-not $wasPresent.Count){Get-NetRoute -DestinationPrefix $route.Prefix -PolicyStore $route.Store -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceIndex -eq $route.InterfaceIndex -and $_.NextHop -eq $route.NextHop -and $_.RouteMetric -eq $route.Metric} | Remove-NetRoute -Confirm:$false}
 }
 foreach($route in @($beforeRoutes | Where-Object {$_.Prefix -eq ($target.UpstreamAddress+'/32')})){
  $adapter=@(Get-NetAdapter -IncludeHidden | Where-Object {[string]$_.InterfaceGuid -eq $route.InterfaceGuid});if($adapter.Count -ne 1){throw 'Saved physical adapter missing'}
  $existing=@(Get-NetRoute -DestinationPrefix $route.Prefix -PolicyStore $route.Store -ErrorAction SilentlyContinue)
  if(@($existing | Where-Object {$_.InterfaceIndex -ne $adapter[0].ifIndex -or $_.NextHop -ne $route.NextHop}).Count){throw 'Route changed outside this guard; automatic overwrite refused'}
  if(-not $existing.Count){New-NetRoute -DestinationPrefix $route.Prefix -InterfaceIndex $adapter[0].ifIndex -NextHop $route.NextHop -RouteMetric $route.Metric -PolicyStore $route.Store | Out-Null}
  else{$existing | Where-Object RouteMetric -ne $route.Metric | Set-NetRoute -RouteMetric $route.Metric -Confirm:$false | Out-Null}
 }
 foreach($file in $meta.Files){$path=Join-Path $root $file.Name;if($file.Exists){Copy-Item -LiteralPath (Join-Path "$dir\files" $file.Name) -Destination $path -Force;Set-ProtectedFile $path}else{if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}}
 foreach($shortcut in $meta.Shortcuts){if($shortcut.Exists){Copy-Item -LiteralPath (Join-Path $dir $shortcut.File) -Destination $shortcut.Path -Force}else{if(Test-Path -LiteralPath $shortcut.Path){Remove-Item -LiteralPath $shortcut.Path -Force}}}
 foreach($profile in @(Read-JSONArray "$dir\firewall-profiles.json")){Set-NetFirewallProfile -Profile $profile.Name -Enabled $profile.Enabled}
 # Atomically restore old WFP records and include current installed Claude versions under old settings.
 $native.Begin();foreach($f in $native.ExportOwned()){$native.Delete($f.Key)};foreach($f in $saved){$native.ImportOwned($f)}
 $keys=@($saved.Key);foreach($file in $inventory.Files){$keys+=@($native.RestrictProgram($file.FullName,'127.0.0.1',[int]$target.ProxyPort,$true))}
 if($target.UseLegacyTag){$keys+=@($native.RestrictTag([int]$target.ProxyPort,$true))};$keys+=@($native.RestrictProgram($target.XrayPath,$target.UpstreamAddress,[int]$target.UpstreamPort,$true));$keys+=@($native.ReservePort($target.XrayPath,[int]$target.ProxyPort,$true))
 $state=Get-Content -Raw "$root\state.json" | ConvertFrom-Json;$state.Keys=@($keys | Sort-Object -Unique);$state.Executables=@($inventory.Files.FullName);$state | Add-Member NoteProperty LaunchExecutable $inventory.Executable -Force;$state | Add-Member NoteProperty RestoredFrom $BackupId -Force
 Save-JSON $state "$root\state.json.pending";$native.Commit();$gated=$false;Move-Item "$root\state.json.pending" "$root\state.json" -Force
 $native.Dispose();$native=$null
 if($meta.TaskExists){Register-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -Xml $taskXml -Force | Out-Null}else{Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false}
 $taskPaused=$false;$restored=$true
 # All mutations are complete. Release the mutex so the diagnostic child can acquire it.
 $mutex.ReleaseMutex();$locked=$false
 # Use a fresh process: a saved older source may declare older native types.
 $check=Join-Path $out 'diagnose';$info=New-Object Diagnostics.ProcessStartInfo;$info.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe";$info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$root+'\Manage-Happ.ps1" -Mode Diagnose -ReportDirectory "'+$check+'"';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $process=[Diagnostics.Process]::Start($info);$null=$process.Handle;$process.WaitForExit();$exit=$process.ExitCode;$process.Dispose()
 $networkOK=$false;if(Test-Path "$check\result.json"){$networkOK=(Get-Content -Raw "$check\result.json" | ConvertFrom-Json).Status -eq 'OK'}
 if($networkOK){Remove-Item -LiteralPath "$root\maintenance.txt" -Force}
 Save-JSON @{Status='RESTORED';NetworkOK=$networkOK;DiagnosticExit=$exit;BackupId=$BackupId;SafetyBackup=$safety;ClaudeLaunched=$false;CurrentInventoryProtected=$true} "$out\result.json"
 Write-Host ('RESTORED. NetworkOK='+$networkOK+'; report='+$out+'; safety backup='+$safety)
 Assert-NoClaude
 if(-not $networkOK){throw 'Settings restored, but live tunnel check failed. Do not launch Claude; inspect diagnose report. DNS/server may have changed since backup.'}
}catch{
 if($out){Save-JSON @{Status=$(if($restored){'RESTORED_CHECK_FAILED'}else{'RESTORE_FAILED'});Error=$_.Exception.Message;BackupId=$BackupId;SafetyBackup=$safety;GateStillApplied=$gated;ClaudeLaunched=$false} "$out\result.json"}
 throw
}finally{
 if($native){$native.Dispose()}
 if($taskPaused -and $currentTask -and -not $gated){try{Register-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -Xml $beforeXml -Force | Out-Null}catch{Write-Warning $_.Exception.Message}}
 if($out){Stop-Transcript | Out-Null};if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
}
