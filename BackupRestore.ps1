# Backup/restore only the Claude-Happ guard. No whole-firewall import is performed.
$script:GuardFiles=@('Common.ps1','HappOnlyWfp.cs','WfpSnapshot.cs','Sync-Guard.ps1','Run-Sync.ps1','Manage-Happ.ps1','DirectDoh.cs','Test-Protected.ps1','Start.ps1','Preflight.ps1','Launch-Checked.ps1','BackupRestore.ps1','Restore-Guard.ps1','Restore-Entry.ps1','config.json','state.json')
$script:GuardRules=@('Happ-Xray-Block-FlClashX','Happ-Xray-Lock-OtherIPv4','Happ-Xray-Lock-OtherTCPPorts','Happ-Xray-Lock-EndpointUDP','Happ-Xray-Lock-IPv6')
function Set-ProtectedDirectory([string]$path){
 New-Item -ItemType Directory -Path $path -Force | Out-Null
 if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Reparse point: '+$path)}
 $acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)');Set-Acl -LiteralPath $path -AclObject $acl
}
function Get-BackupHome {Join-Path $env:ProgramData 'ClaudeHappBackups'}
function Set-ProtectedFile([string]$path){$acl=New-Object Security.AccessControl.FileSecurity;$acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;BU)');Set-Acl -LiteralPath $path -AclObject $acl}
function Assert-ProtectedBackupItem([string]$path){
 $item=Get-Item -LiteralPath $path;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in backup'}
 $acl=Get-Acl -LiteralPath $path;$owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'Backup owner is not SYSTEM/Administrators'}
 $writeMask=2 -bor 4 -bor 16 -bor 64 -bor 256 -bor 65536 -bor 262144 -bor 524288
 foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') -and ([int]$rule.FileSystemRights -band $writeMask)){throw 'Backup writable by a non-administrative identity'}}
}
function Save-JSON($value,[string]$path){ConvertTo-Json -InputObject $value -Depth 14 | Set-Content -LiteralPath $path -Encoding UTF8}
function Read-JSONArray([string]$path){$data=Get-Content -Raw -LiteralPath $path | ConvertFrom-Json;foreach($item in $data){Write-Output $item}}
function Get-MachineBinding {(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid}
function Get-GuardRuleSnapshot {
 foreach($name in $script:GuardRules){
  $rules=@(Get-NetFirewallRule -Name $name -PolicyStore PersistentStore -ErrorAction SilentlyContinue)
  if($rules.Count -gt 1){throw ('Ambiguous guard rule '+$name)}
  if(-not $rules.Count){[pscustomobject]@{Name=$name;Exists=$false;Parameters=$null};continue}
  $r=$rules[0];$a=$r | Get-NetFirewallAddressFilter;$p=$r | Get-NetFirewallPortFilter;$app=$r | Get-NetFirewallApplicationFilter;$svc=$r | Get-NetFirewallServiceFilter;$iface=$r | Get-NetFirewallInterfaceFilter;$itype=$r | Get-NetFirewallInterfaceTypeFilter;$sec=$r | Get-NetFirewallSecurityFilter
  $v=[ordered]@{Name=$name;DisplayName=[string]$r.DisplayName;Enabled=[string]$r.Enabled;Direction=[string]$r.Direction;Action=[string]$r.Action;Profile=[string]$r.Profile;EdgeTraversalPolicy=[string]$r.EdgeTraversalPolicy;LooseSourceMapping=[bool]$r.LooseSourceMapping;LocalOnlyMapping=[bool]$r.LocalOnlyMapping;Program=[string]$app.Program;LocalAddress=@($a.LocalAddress);RemoteAddress=@($a.RemoteAddress);Protocol=[string]$p.Protocol;LocalPort=@($p.LocalPort);RemotePort=@($p.RemotePort);InterfaceAlias=@($iface.InterfaceAlias);InterfaceType=[string]$itype.InterfaceType}
  if($r.Group){$v.Group=[string]$r.Group};if($r.Description){$v.Description=[string]$r.Description};if($r.Owner){$v.Owner=[string]$r.Owner};if($r.PolicyAppId){$v.PolicyAppId=[string]$r.PolicyAppId}
  if($app.Package -and $app.Package -ne 'Any'){$v.Package=[string]$app.Package};if($svc.Service -and $svc.Service -ne 'Any'){$v.Service=[string]$svc.Service}
  if([string]$p.Protocol -in @('ICMPv4','ICMPv6','1','58')){$v.IcmpType=@($p.IcmpType);$v.Remove('LocalPort');$v.Remove('RemotePort')}
  if($p.DynamicTarget -and [string]$p.DynamicTarget -ne 'Any'){$v.DynamicTarget=[string]$p.DynamicTarget}
  foreach($key in @('Authentication','Encryption','OverrideBlockRules','LocalUser','RemoteUser','RemoteMachine')){
   $value=[string]$sec.$key;if($value -and $value -notin @('Any','NotRequired','False')){$v[$key]=$value}
  }
  [pscustomobject]@{Name=$name;Exists=$true;Parameters=[pscustomobject]$v}
 }
}
function Get-RouteSnapshot {
 foreach($store in @('ActiveStore','PersistentStore')){
  Get-NetRoute -AddressFamily IPv4 -PolicyStore $store | Where-Object DestinationPrefix -like '*/32' | ForEach-Object {
   $adapter=Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -IncludeHidden -ErrorAction SilentlyContinue
   [pscustomobject]@{Store=$store;Prefix=$_.DestinationPrefix;InterfaceIndex=$_.InterfaceIndex;InterfaceGuid=[string]$adapter.InterfaceGuid;InterfaceAlias=$_.InterfaceAlias;NextHop=$_.NextHop;Metric=$_.RouteMetric}
  }
 }
}
function New-GuardBackup($Candidate,[string]$TaskXmlBefore,[bool]$TaskExistsBefore,[string]$Reason){
 $backupHome=Get-BackupHome;Set-ProtectedDirectory $backupHome
 $id=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8);$dir=Join-Path $backupHome $id;Set-ProtectedDirectory $dir;Set-ProtectedDirectory "$dir\files"
 $root=Get-GuardRoot;$metadata=[ordered]@{Schema=1;Id=$id;Created=(Get-Date).ToString('o');Machine=(Get-MachineBinding);Reason=$Reason;HadGuard=[bool](Test-Path "$root\state.json");Maintenance=[bool](Test-Path "$root\maintenance.txt");TaskExists=$TaskExistsBefore;Files=@();Shortcuts=@()}
 foreach($name in $script:GuardFiles){$path=Join-Path $root $name;$exists=Test-Path -LiteralPath $path -PathType Leaf
  if($exists){if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in guard files'};Copy-Item -LiteralPath $path -Destination "$dir\files\$name"}
  $metadata.Files+=@([pscustomobject]@{Name=$name;Exists=$exists})
 }
 if($TaskExistsBefore){$TaskXmlBefore | Set-Content "$dir\task.xml" -Encoding Unicode}
 Save-JSON @(Get-GuardRuleSnapshot) "$dir\firewall-rules.json"
 Get-NetFirewallRule -PolicyStore PersistentStore | Where-Object Name -in $script:GuardRules | Export-Clixml "$dir\firewall-raw.xml" -Depth 8
 Save-JSON @(Get-NetFirewallProfile -PolicyStore PersistentStore | Select-Object Name,@{n='Enabled';e={[string]$_.Enabled}}) "$dir\firewall-profiles.json"
 & "$env:SystemRoot\System32\netsh.exe" advfirewall export "$dir\firewall-full.wfw" | Out-File "$dir\firewall-export.log"
 if($LASTEXITCODE -ne 0 -or -not(Test-Path "$dir\firewall-full.wfw")){throw 'Whole-firewall reference export failed; no repair will proceed'}
 Save-JSON @(Get-RouteSnapshot) "$dir\routes-before.json"
 Save-JSON @() "$dir\route-journal.json"
 if(-not('GuardWfpSnapshot' -as [type])){Add-Type -Path "$PSScriptRoot\WfpSnapshot.cs"};$native=[GuardWfpSnapshot]::new()
 try{Save-JSON @($native.ExportOwned()) "$dir\wfp-owned.json"}finally{$native.Dispose()}
 $paths=@($Candidate.ShortcutPath)
 if(Test-Path "$root\config.json"){$previous=Get-Content -Raw "$root\config.json" | ConvertFrom-Json;$paths+=@($previous.ShortcutPath)}
 $index=0;foreach($path in @($paths | Where-Object {$_} | Sort-Object -Unique)){
  $exists=Test-Path -LiteralPath $path -PathType Leaf;$file='shortcut-'+$index+'.lnk'
  if($exists){Copy-Item -LiteralPath $path -Destination (Join-Path $dir $file)}
  $metadata.Shortcuts+=@([pscustomobject]@{Path=$path;Exists=$exists;File=$file});$index++
 }
 Save-JSON $metadata "$dir\metadata.json"
 $hashes=@(Get-ChildItem -LiteralPath $dir -File -Recurse | Where-Object Name -ne 'route-journal.json' | ForEach-Object {[pscustomobject]@{Path=$_.FullName.Substring($dir.Length+1);SHA256=(Get-FileHash $_.FullName).Hash}})
 Save-JSON $hashes "$dir\manifest.json"
 'COMPLETE' | Set-Content "$dir\COMPLETE" -Encoding ASCII
 Get-ChildItem -LiteralPath $dir -File -Recurse | ForEach-Object {Set-ProtectedFile $_.FullName}
 Write-Host ('BACKUP: '+$dir)
 return $dir
}
function Add-RouteIntent([string]$backup,[string]$prefix,[int]$index,[string]$hop,[string]$store){
 $p=Join-Path $backup 'route-journal.json';$items=@(Read-JSONArray $p);$items+=@([pscustomobject]@{Prefix=$prefix;InterfaceIndex=$index;NextHop=$hop;Metric=1;Store=$store});Save-JSON $items $p
}
function Read-VerifiedBackup([string]$id){
 if($id -notmatch '^\d{8}-\d{6}-\d{3}-[a-f0-9]{8}$'){throw 'BackupId must be an ID listed by Restore, not an arbitrary path'}
 $dir=Join-Path (Get-BackupHome) $id
 if(-not(Test-Path "$dir\COMPLETE")){throw 'Backup incomplete or missing'}
 Assert-ProtectedBackupItem (Get-BackupHome);Assert-ProtectedBackupItem $dir;Assert-ProtectedBackupItem "$dir\files"
 Get-ChildItem -LiteralPath $dir -File -Recurse | ForEach-Object {Assert-ProtectedBackupItem $_.FullName}
 $manifest=Get-Content -Raw "$dir\manifest.json" | ConvertFrom-Json
 foreach($item in $manifest){$path=[IO.Path]::GetFullPath((Join-Path $dir $item.Path));if(-not $path.StartsWith($dir+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Backup path traversal'};if((Get-FileHash -LiteralPath $path).Hash -ne $item.SHA256){throw ('Backup checksum mismatch: '+$item.Path)}}
 $meta=Get-Content -Raw "$dir\metadata.json" | ConvertFrom-Json
 if($meta.Machine -ne (Get-MachineBinding) -or $meta.Id -ne $id -or $meta.Schema -ne 1){throw 'Backup belongs to another Windows installation or has an unsupported format'}
 foreach($f in $meta.Files){if($f.Name -notin $script:GuardFiles){throw 'Unknown managed backup file'}}
 [pscustomobject]@{Directory=$dir;Metadata=$meta}
}
function Convert-SavedFilter($saved){
 $f=[GuardWfpSnapshot+SavedFilter]::new();$f.Key=$saved.Key;$f.Name=$saved.Name;$f.Layer=$saved.Layer;$f.Flags=$saved.Flags;$f.Weight=$saved.Weight
 $f.Conditions=@($saved.Conditions | ForEach-Object {$c=[GuardWfpSnapshot+SavedCondition]::new();$c.Key=$_.Key;$c.Match=$_.Match;$c.Type=$_.Type;$c.Number=$_.Number;$c.Data=$_.Data;$c})
 return $f
}
function Clear-RestoreGate($configuration){
 $inventory=Get-ClaudeInventory $configuration
 if(-not('GuardWfpSnapshot' -as [type])){Add-Type -Path "$PSScriptRoot\WfpSnapshot.cs"}
 $n=[GuardWfpSnapshot]::new()
 try{$n.Begin();foreach($f in $inventory.Files){$base=@($n.RestrictProgram($f.FullName,'127.0.0.1',[int]$configuration.ProxyPort,$true));$fault=@($n.RestrictProgram($f.FullName,'127.0.0.1',([int]$configuration.ProxyPort+1),$true));foreach($key in @($fault | Where-Object {$_ -notin $base})){$n.Delete($key)}};$n.Commit()}finally{$n.Dispose()}
}
