#requires -Version 5.1
# This script never starts Claude, its services, or its shortcut.
[CmdletBinding()]param([ValidateSet('Install','Diagnose','Fix')][string]$Mode='Diagnose',[string]$SetupConfigFile,[string]$ReportDirectory)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\BackupRestore.ps1"
$root=Get-GuardRoot
$configPath="$root\config.json";if($SetupConfigFile){$configPath=$SetupConfigFile}
$config=Read-GuardConfig $configPath;$xray=$config.XrayPath;$port=[int]$config.ProxyPort
$previousPin=[string]$config.UpstreamAddress
if($SetupConfigFile -and (Test-Path "$root\state.json")){
 $previous=Read-GuardConfig "$root\config.json"
 $previousPin=[string]$previous.UpstreamAddress
 if($previous.ProxyPort -ne $port -or $previous.XrayPath -ne $xray -or $previous.UpstreamPort -ne $config.UpstreamPort){throw 'Existing guard uses another port/core path. Migration requires reviewing old filters; fresh installs support configurable values.'}
}
$out=Join-Path $env:ProgramData ('ClaudeHappReports\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
if($ReportDirectory){$allowed=[IO.Path]::GetFullPath((Join-Path $env:ProgramData 'ClaudeHappReports'))+'\';if(-not [IO.Path]::GetFullPath($ReportDirectory).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Report path outside reports root'};$out=$ReportDirectory}
New-Item -ItemType Directory -Path $out -Force | Out-Null
Start-Transcript -Path "$out\run.log" | Out-Null
$issues=New-Object 'Collections.Generic.List[string]';$mutex=$null;$locked=$false;$task=$null;$resumeTask=$false;$taskBeforeXml='';$backup=$null
$result=[ordered]@{Time=(Get-Date).ToString('o');Mode=$Mode;Status='FAIL';ClaudeLaunched=$false;Issues=@();Report=$out}
function No-Claude {Assert-NoClaude -Configuration $config}
function Verify-GuardBounded {
 $si=New-Object Diagnostics.ProcessStartInfo
 $si.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
 $si.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$root+'\Sync-Guard.ps1" -Mode Verify'
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$si
 Write-Host 'Checking static WFP/firewall state (45 second limit)...'
 try{
  $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(45000)){$p.Kill();$p.WaitForExit();throw 'STATIC_VERIFY_TIMEOUT after 45 seconds; only the verification worker was stopped. No launch approval.'}
  $stdout.Result | Set-Content "$out\verify.log" -Encoding UTF8
  $stderr.Result | Set-Content "$out\verify-error.log" -Encoding UTF8
  if($p.ExitCode -ne 0 -or $stdout.Result -notmatch 'STATIC VERIFY PASS'){throw ('Static verification failed. '+$stderr.Result.Trim())}
 }finally{$p.Dispose()}
}
function Register-GuardTask {
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$root+'\Run-Sync.ps1"')
 $triggers=@((New-ScheduledTaskTrigger -AtStartup),(New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)))
 $principal=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
 Register-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
}
function Firewall-Rule($name,$addresses,$protocol='Any',$ports=@('Any'),$interfaces=@('Any')) {
 # Only our five named Happ rules are replaced. No global firewall reset.
 $r=Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
 if($r){$r | Remove-NetFirewallRule}
 New-NetFirewallRule -Name $name -DisplayName $name -Group 'Claude Happ Only' -Program $xray -Direction Outbound -Action Block -Enabled True -Profile Any -RemoteAddress $addresses -Protocol $protocol -RemotePort $ports -InterfaceAlias $interfaces | Out-Null
}
function Outside-IPv4([string]$ip) {
 $n=[HappOnlyWfp]::IPv4($ip)
 function Format-IP([uint64]$v){'{0}.{1}.{2}.{3}' -f (($v -shr 24)-band 255),(($v -shr 16)-band 255),(($v -shr 8)-band 255),($v-band 255)}
 if($n -lt 2147483648){@(('0.0.0.0-'+(Format-IP ($n-1))),((Format-IP ($n+1))+'-126.255.255.255'),'128.0.0.0-255.255.255.255')}
 else{@('0.0.0.0-126.255.255.255',('128.0.0.0-'+(Format-IP ($n-1))),((Format-IP ($n+1))+'-255.255.255.255'))}
}
try {
 No-Claude
 if(-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator required. Run Start.ps1 or a CMD launcher.'}
 if(-not [Environment]::Is64BitProcess){throw '64-bit Windows PowerShell required'}
 $mutex=[Threading.Mutex]::new($false,'Global\ClaudeHappSetupV3');$locked=$mutex.WaitOne(0);if(-not $locked){throw 'Another installer/repair is running'}
 if(-not(Test-Path $xray)){throw 'Happ is not installed at the expected path. Install Happ first.'}
 $null=Get-ClaudeInventory $config
 if($Mode -ne 'Diagnose'){
  $task=Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -ErrorAction SilentlyContinue
  if($task){$taskBeforeXml=Export-ScheduledTask -InputObject $task;Disable-ScheduledTask -InputObject $task | Out-Null;$resumeTask=$true;for($i=0;$i -lt 15;$i++){if((Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync).State -ne 'Running'){break};Start-Sleep -Seconds 1};if((Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync).State -eq 'Running'){throw 'Sync task busy. Retry later.'}}
  $backup=New-GuardBackup $config $taskBeforeXml ([bool]$task) ('Before-'+$Mode)
  $result['Backup']=$backup;$result['BackupId']=Split-Path $backup -Leaf
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  if((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Protected installation directory must not be a reparse point'}
  if(@(Get-ChildItem -LiteralPath $root -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Reparse point inside protected installation; inspect before repair'}
  $acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)');Set-Acl -LiteralPath $root -AclObject $acl
  foreach($name in @('config.json','state.json','Sync-Guard.ps1','HappOnlyWfp.cs','Run-Sync.ps1')){if(Test-Path "$root\$name"){Copy-Item "$root\$name" "$out\before-$name"}}
  if($PSScriptRoot -ne $root){
   $manifest=Get-Content -Raw "$PSScriptRoot\payload-hashes.json" | ConvertFrom-Json
   foreach($item in $manifest){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $item.Name)).Hash -ne $item.SHA256){throw ('Kit checksum mismatch: '+$item.Name)}}
   foreach($name in @('HappOnlyWfp.cs','Sync-Guard.ps1','Run-Sync.ps1','DirectDoh.cs','Manage-Happ.ps1','Test-Protected.ps1','Start.ps1','Common.ps1','Preflight.ps1','Launch-Checked.ps1','BackupRestore.ps1','WfpSnapshot.cs','Restore-Guard.ps1','Restore-Entry.ps1','CodeProxy.Common.ps1','Configure-CodeProxy.ps1')){Copy-Item -LiteralPath "$PSScriptRoot\$name" -Destination "$root\$name" -Force}
   $config | ConvertTo-Json -Depth 5 | Set-Content "$root\config.json" -Encoding UTF8
  }
  # Remove explicit writable ACLs from files left by an earlier/manual installation.
  $fileAcl=New-Object Security.AccessControl.FileSecurity;$fileAcl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;BU)')
  Get-ChildItem -LiteralPath $root -File | ForEach-Object {Set-Acl -LiteralPath $_.FullName -AclObject $fileAcl}
  if(Test-Path "$root\LaunchTickets"){
   Set-Acl -LiteralPath "$root\LaunchTickets" -AclObject $acl
   Get-ChildItem -LiteralPath "$root\LaunchTickets" -File | ForEach-Object {if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in tickets'};Set-Acl -LiteralPath $_.FullName -AclObject $fileAcl}
  }
 }
 if(-not(Test-Path "$root\config.json")){throw 'Guard not installed. Run Install.cmd first.'}
 $nic=Get-NetAdapter -Name $config.PhysicalInterface
 if($nic.Status -ne 'Up' -or -not $nic.HardwareInterface){throw 'Configured physical network adapter is not Up. Restore its connection; virtual adapters are not selected.'}
 $network=Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex
 $gateway=@($network.IPv4DefaultGateway.NextHop);$local=@($network.IPv4Address.IPAddress | Where-Object {$_ -notlike '169.254.*'})
 if($gateway.Count -ne 1 -or $local.Count -ne 1){throw 'Ethernet needs exactly one IPv4 address and gateway. Check Windows adapter settings.'}
 Add-Type -Path "$PSScriptRoot\DirectDoh.cs"
 Add-Type -Path "$root\HappOnlyWfp.cs"
 $answers=@();$dnsOK=$false;$endpointOK=$false
 if($config.EndpointMode -eq 'PinnedIPv4'){
  $ip=[string]$config.UpstreamAddress;$endpointOK=$true
 }else{try{
  foreach($dns in @(@('1.1.1.1','cloudflare-dns.com','/dns-query?name='),@('8.8.8.8','dns.google','/resolve?name='))){
   $j=[DirectDoh]::Query($dns[0],$dns[1],($dns[2]+$config.UpstreamHostname+'&type=A'),$nic.ifIndex,$local[0]) | ConvertFrom-Json
   $a=@($j.Answer | Where-Object type -eq 1 | Select-Object -ExpandProperty data -Unique)
   if($j.Status -ne 0 -or $a.Count -ne 1){throw 'DNS response is not one unique IPv4 address'}
   $answers+=@([string]$a[0])
  }
  $ip=$answers[0]
  if($answers[0] -ne $answers[1] -or -not(Test-GuardPublicIPv4 $ip)){throw 'DNS disagreement or unsupported/non-public answer; no pin update'}
  $dnsOK=$true;$endpointOK=$true
 }catch{$issues.Add('DNS_UNVERIFIED: '+$_.Exception.Message+'. Keep current pin; check physical DNS HTTPS and retry Fix.cmd.');$ip=[string]$config.UpstreamAddress}}
 $result['EndpointMode']=$config.EndpointMode;$result['EndpointVerified']=$endpointOK
 $result['DNSVerified']=$dnsOK;$result['ResolvedAddress']=$ip;$result['PreviousPin']=$previousPin
 if($Mode -ne 'Diagnose'){
  if(-not $endpointOK -and -not $config.UpstreamAddress){throw 'First install needs verified endpoint: agreeing DNS answers or explicit public PinnedIPv4'}
  if($config.UpstreamAddress){& "$root\Sync-Guard.ps1" -Mode Sync | Out-File "$out\sync-before.log"}
  Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True
  $routes=@(Get-NetRoute -DestinationPrefix ($ip+'/32') -ErrorAction SilentlyContinue)
  foreach($r in $routes){if($r.InterfaceIndex -ne $nic.ifIndex -or $r.NextHop -ne $gateway[0]){throw 'Conflicting exact route. Inspect route print; this script will not delete routes owned by other software.'}}
  if(-not $routes.Count){Add-RouteIntent $backup ($ip+'/32') $nic.ifIndex $gateway[0] 'ActiveStore';if(-not @(Get-NetRoute -DestinationPrefix ($ip+'/32') -PolicyStore PersistentStore -ErrorAction SilentlyContinue).Count){Add-RouteIntent $backup ($ip+'/32') $nic.ifIndex $gateway[0] 'PersistentStore'};New-NetRoute -DestinationPrefix ($ip+'/32') -InterfaceIndex $nic.ifIndex -NextHop $gateway[0] -RouteMetric 1 | Out-Null}
  $persistent=@(Get-NetRoute -DestinationPrefix ($ip+'/32') -PolicyStore PersistentStore -ErrorAction SilentlyContinue)
  if(-not $persistent.Count){Add-RouteIntent $backup ($ip+'/32') $nic.ifIndex $gateway[0] 'PersistentStore';New-NetRoute -DestinationPrefix ($ip+'/32') -InterfaceIndex $nic.ifIndex -NextHop $gateway[0] -RouteMetric 1 -PolicyStore PersistentStore | Out-Null}
  if(@($config.BlockedInterfaces).Count){Firewall-Rule 'Happ-Xray-Block-FlClashX' @('Any') 'Any' @('Any') @($config.BlockedInterfaces)}
  Firewall-Rule 'Happ-Xray-Lock-OtherIPv4' (Outside-IPv4 $ip)
  Firewall-Rule 'Happ-Xray-Lock-OtherTCPPorts' @($ip) 'TCP' @(Get-OtherPorts $config.UpstreamPort)
  Firewall-Rule 'Happ-Xray-Lock-EndpointUDP' @($ip) 'UDP'
  Firewall-Rule 'Happ-Xray-Lock-IPv6' @('::/1','8000::/1')
  $config | Add-Member NoteProperty UpstreamAddress $ip -Force
  $config | Add-Member NoteProperty PhysicalInterface $nic.Name -Force
  $config | Add-Member NoteProperty Gateway $gateway[0] -Force
  $config | ConvertTo-Json | Set-Content "$root\config.json.pending" -Encoding UTF8;Move-Item "$root\config.json.pending" "$root\config.json" -Force
  & "$root\Sync-Guard.ps1" -Mode Sync | Out-File "$out\sync-after.log"
  Register-GuardTask;$resumeTask=$false
 }
 if($dnsOK -and $ip -ne $config.UpstreamAddress){$issues.Add('PIN_CHANGED: DNS='+$ip+'; configured='+$config.UpstreamAddress+'. Run Fix.cmd to update route and both restriction layers.')}
 try{Verify-GuardBounded}catch{$issues.Add('GUARD: '+$_.Exception.Message+'. Inspect verify logs before another Fix.')}
 $expectedRules=@(
  $(if(@($config.BlockedInterfaces).Count){@{Name='Happ-Xray-Block-FlClashX';Address=@('Any');Protocol='Any';Port=@('Any');Interface=@($config.BlockedInterfaces)}}),
  @{Name='Happ-Xray-Lock-OtherIPv4';Address=@(Outside-IPv4 $config.UpstreamAddress);Protocol='Any';Port=@('Any');Interface=@('Any')},
  @{Name='Happ-Xray-Lock-OtherTCPPorts';Address=@($config.UpstreamAddress);Protocol='TCP';Port=@(Get-OtherPorts $config.UpstreamPort);Interface=@('Any')},
  @{Name='Happ-Xray-Lock-EndpointUDP';Address=@($config.UpstreamAddress);Protocol='UDP';Port=@('Any');Interface=@('Any')},
  @{Name='Happ-Xray-Lock-IPv6';Address=@('::/1','8000::/1');Protocol='Any';Port=@('Any');Interface=@('Any')}
 )
 foreach($expected in @($expectedRules | Where-Object {$_})){try{
  $r=Get-NetFirewallRule -Name $expected.Name -PolicyStore ActiveStore
  $address=$r | Get-NetFirewallAddressFilter;$firewallPort=$r | Get-NetFirewallPortFilter;$interface=$r | Get-NetFirewallInterfaceFilter;$app=$r | Get-NetFirewallApplicationFilter
  if($r.Enabled -ne 'True' -or $r.Action -ne 'Block' -or $r.Direction -ne 'Outbound' -or $r.Profile -ne 'Any' -or $app.Program -ne $xray -or $r.PolicyAppId){throw 'rule scope/action mismatch'}
  if((@($address.RemoteAddress | Sort-Object)-join ',') -ne (@($expected.Address | Sort-Object)-join ',') -or [string]$firewallPort.Protocol -ne $expected.Protocol -or (@($firewallPort.RemotePort | Sort-Object)-join ',') -ne (@($expected.Port | Sort-Object)-join ',') -or (@($interface.InterfaceAlias | Sort-Object)-join ',') -ne (@($expected.Interface | Sort-Object)-join ',')){throw 'address/port/interface mismatch'}
 }catch{$issues.Add('FIREWALL_RULE: '+$expected.Name+': '+$_.Exception.Message+'. Run Fix.cmd.')}}
 $taskNow=Get-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -ErrorAction SilentlyContinue
 if(-not $taskNow -or $taskNow.State -eq 'Disabled'){$issues.Add('TASK: synchronization missing/disabled. Run Fix.cmd.')}else{
  $info=$taskNow | Get-ScheduledTaskInfo;$result['TaskLastResult']=$info.LastTaskResult
  $taskIdentity=[string]$taskNow.Principal.UserId
  try{if($taskIdentity -notmatch '^S-1-'){$taskIdentity=([Security.Principal.NTAccount]::new($taskIdentity)).Translate([Security.Principal.SecurityIdentifier]).Value}}catch{}
  $taskSnapshot=[pscustomobject]@{Identity=$taskIdentity;OriginalIdentity=$taskNow.Principal.UserId;Actions=@($taskNow.Actions | Select-Object Execute,Arguments);TriggerCount=@($taskNow.Triggers).Count}
  $taskSnapshot | ConvertTo-Json -Depth 4 | Set-Content "$out\task-check.json" -Encoding UTF8
  if(@($taskNow.Actions).Count -ne 1 -or $taskNow.Actions[0].Execute -ne "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -or $taskNow.Actions[0].Arguments -ne ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$root+'\Run-Sync.ps1"') -or $taskIdentity -ne 'S-1-5-18' -or @($taskNow.Triggers).Count -ne 2){$issues.Add('TASK_CONFIGURATION: unexpected task action/principal/triggers. Run Fix.cmd. Details: task-check.json')}
  if($info.LastTaskResult -notin @(0,267011,267009)){$issues.Add('TASK_LAST_FAILURE: '+$info.LastTaskResult+'. Inspect sync-latest.log; run Fix.cmd.')}
 }
 $listen=@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
 if($listen.Count -ne 1 -or $listen[0].LocalAddress -ne '127.0.0.1'){$issues.Add('HAPP_LISTENER: connect the configured server in Happ proxy mode on 127.0.0.1:'+$port+'; then run Diagnose.cmd.')}
 else{
  $owner=Get-CimInstance Win32_Process -Filter ('ProcessId='+$listen[0].OwningProcess)
  if($owner.ExecutablePath -ne $xray){$issues.Add('WRONG_PROXY_OWNER: port 10808 belongs to another executable. Do not launch Claude; inspect the port owner.')}
  else{try{
   $connections=@(Get-NetTCPConnection -OwningProcess $owner.ProcessId -State Established -ErrorAction SilentlyContinue | Where-Object {$_.RemoteAddress -notin @('127.0.0.1','::1')})
   if(@($connections | Where-Object {$_.RemoteAddress -ne $config.UpstreamAddress -or $_.RemotePort -ne $config.UpstreamPort -or $_.LocalAddress -notin $local}).Count){throw 'Happ core has a connection outside the pinned physical path. Reconnect the configured server in Happ.'}
   Write-Host 'Checking protected SOCKS/HTTP proxy and blocked bypass paths...'
   $probeResult=& "$PSScriptRoot\Test-Protected.ps1" -Root $root -OutputDirectory $out -Upstream $config.UpstreamAddress -ProxyPort $port -Country $config.ExpectedCountry -UpstreamPort $config.UpstreamPort;$result['Experiment']=$probeResult
   if(-not $probeResult.OverallOK){$issues.Add('NETWORK_TEST_FAILED: see experiment.json. Reconnect the SAME server in Happ and rerun Diagnose.cmd. If it persists, check the provider/server; do not relax firewall.')}
  }catch{$issues.Add('PROBE: '+$_.Exception.Message+'. See run.log and experiment.json.')}}
 }
 No-Claude
 $result['Issues']=@($issues.ToArray());if($issues.Count -eq 0){$result.Status='OK'}
 if($Mode -ne 'Diagnose' -and $result.Status -eq 'OK' -and (Test-Path "$root\maintenance.txt")){Clear-RestoreGate $config;Remove-Item -LiteralPath "$root\maintenance.txt" -Force}
}catch{$issues.Add($_.Exception.Message);$result['Issues']=@($issues.ToArray());throw}
finally{
 if($resumeTask){try{Register-ScheduledTask -TaskPath '\ClaudeHappOnly\' -TaskName Sync -Xml $taskBeforeXml -Force | Out-Null}catch{$result.Status='FAIL';$issues.Add('Could not restore original Sync task: '+$_.Exception.Message)}}
 $result['Issues']=@($issues.ToArray());$result | ConvertTo-Json -Depth 10 | Set-Content "$out\result.json" -Encoding UTF8
 @(('STATUS: '+$result.Status),'Claude was NOT launched.',('Report: '+$out),'',($issues -join "`r`n")) | Set-Content "$out\SUMMARY.txt" -Encoding UTF8
 Write-Host ('STATUS: '+$result.Status+' | Report: '+$out);foreach($issue in $issues){Write-Host $issue -ForegroundColor Yellow}
 if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()};Stop-Transcript | Out-Null
}
if($result.Status -ne 'OK'){throw ('Checks incomplete. Concrete findings: '+$out+'\SUMMARY.txt')}
