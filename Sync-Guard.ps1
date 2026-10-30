#requires -Version 5.1
param([ValidateSet('Sync','Verify')][string]$Mode='Verify')
$ErrorActionPreference='Stop';$root=$PSScriptRoot
. "$root\Common.ps1"
$config=Read-GuardConfig "$root\config.json";$endpoint=[string]$config.UpstreamAddress;$port=[int]$config.ProxyPort
$parsed=$null;if(-not [Net.IPAddress]::TryParse($endpoint,[ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork'){throw 'Verified pinned IPv4 required'}
if(-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator required'}
Add-Type -Path "$root\HappOnlyWfp.cs"
$old=$null;if(Test-Path "$root\state.json"){$old=Get-Content -Raw "$root\state.json" | ConvertFrom-Json}
$inventory=Get-ClaudeInventory $config;$wfp=[HappOnlyWfp]::new();$keys=@();$obsolete=@()
try{
 if($Mode -eq 'Verify'){
  if(-not $old){throw 'Guard is not installed'}
  foreach($key in $old.Keys){$null=$wfp.Describe($key)}
  $wfp.VerifyOnly=$true
 }
 if($old){foreach($key in $old.Keys){try{$description=$wfp.Describe($key)}catch{if($_.Exception.Message -match '0x80320003' -and $Mode -eq 'Sync'){continue};throw}
  $marker='name=Claude-Happ-Only: program:'+$config.XrayPath.ToLowerInvariant()+'|v4-address|'
  if($description.Contains($marker) -and -not $description.EndsWith('|'+$endpoint)){$obsolete+=@($key)}else{$keys+=@($key)}
 }}
 # Verification must not hold a WFP write transaction while querying Firewall
 # through CIM: the provider may wait for the same transaction to finish.
 # VerifyOnly makes Restrict*/ReservePort read-only and rejects missing filters.
 if($Mode -eq 'Sync'){$wfp.Begin()}
 foreach($key in $obsolete){if($Mode -eq 'Verify'){throw 'Stale Xray upstream filter'};$wfp.Delete($key)}
 foreach($file in $inventory.Files){$keys+=@($wfp.RestrictProgram($file.FullName,'127.0.0.1',$port,$true))}
 if($config.UseLegacyTag){$keys+=@($wfp.RestrictTag($port,$true))}
 $keys+=@($wfp.RestrictProgram($config.XrayPath,$endpoint,[int]$config.UpstreamPort,$true));$keys+=@($wfp.ReservePort($config.XrayPath,$port,$true));$keys=@($keys | Sort-Object -Unique)
 if($Mode -eq 'Verify'){
  if(@(Get-NetFirewallProfile -PolicyStore ActiveStore | Where-Object {[string]$_.Enabled -ne 'True'}).Count){throw 'Firewall profile disabled'}
  $route=@(Get-NetRoute -DestinationPrefix ($endpoint+'/32') -PolicyStore ActiveStore)
  if($route.Count -ne 1 -or $route[0].InterfaceAlias -ne $config.PhysicalInterface -or $route[0].NextHop -ne $config.Gateway){throw 'Pinned endpoint route mismatch'}
  if($old.LaunchExecutable -ne $inventory.Executable){throw 'Package changed since last synchronization'}
  'STATIC VERIFY PASS';return
 }
 $state=[ordered]@{Schema=3;Updated=(Get-Date).ToString('o');PackageFamily=$config.PackageFamily;Packages=$inventory.Packages;Executables=@($inventory.Files.FullName);LaunchExecutable=$inventory.Executable;Proxy=('127.0.0.1:'+$port+'/TCP');Upstream=($endpoint+':'+$config.UpstreamPort+'/TCP');Keys=$keys;ClaudeLaunched=$false}
 $state | ConvertTo-Json -Depth 6 | Set-Content "$root\state.json.pending" -Encoding UTF8
 $wfp.Commit();Move-Item "$root\state.json.pending" "$root\state.json" -Force
 $shell=New-Object -ComObject WScript.Shell;$shortcut=$shell.CreateShortcut($config.ShortcutPath)
 $shortcut.TargetPath="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
 $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$root+'\Launch-Checked.ps1"'
 $shortcut.WorkingDirectory=$root;$shortcut.Description='Check tunnel, repair once, recheck, then start Claude as signed-in user. Installer never executes this shortcut.';$shortcut.Save()
 'SYNC PASS: '+$inventory.Files.Count+' EXEs, '+$keys.Count+' persistent filters; checked-launch shortcut saved, NOT executed.'
}finally{$wfp.Dispose()}
