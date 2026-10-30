function Get-GuardRoot {Join-Path $env:ProgramData 'ClaudeHappOnly'}
function Read-GuardConfig([string]$path){
 $c=Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
 $defaults=@{Schema=3;ProxyPort=10808;UpstreamPort=443;ExpectedCountry='DE';XrayPath=(Join-Path $env:ProgramFiles 'FlyFrogLLC\Happ\core\xray.exe');PackageFamily='Claude_pzs8sxrjxfjjc';ClaudeRoot='';ClaudeExe='';BlockedInterfaces=@('FlClashX');UseLegacyTag=$true;LaunchUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
 foreach($key in $defaults.Keys){if(-not $c.PSObject.Properties[$key]){$c | Add-Member NoteProperty $key $defaults[$key]}}
 if(-not $c.PSObject.Properties['CodeRoot']){$c | Add-Member NoteProperty CodeRoot ''}
 if(-not $c.PSObject.Properties['EndpointMode']){$c | Add-Member NoteProperty EndpointMode 'Hostname'}
 if(-not $c.PhysicalInterface){throw 'PhysicalInterface is required'}
 if($c.EndpointMode -notin @('Hostname','PinnedIPv4')){throw 'EndpointMode must be Hostname or PinnedIPv4'}
 if($c.EndpointMode -eq 'Hostname'){
  if([string]$c.UpstreamHostname -notmatch '^(?=.{1,253}$)[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$'){throw 'Invalid server hostname'}
  $literal=$null;if([Net.IPAddress]::TryParse([string]$c.UpstreamHostname,[ref]$literal)){throw 'Use EndpointMode=PinnedIPv4 and UpstreamAddress for a literal server IP'}
 }elseif(-not(Test-GuardPublicIPv4 ([string]$c.UpstreamAddress))){throw 'PinnedIPv4 requires a canonical public IPv4 UpstreamAddress'}
 if($c.ExpectedCountry -notmatch '^[A-Z]{2}$'){throw 'ExpectedCountry must be a two-letter country code'}
 if([int]$c.ProxyPort -lt 1024 -or [int]$c.ProxyPort -gt 65534){throw 'ProxyPort must be 1024..65534'}
 if([int]$c.UpstreamPort -lt 1 -or [int]$c.UpstreamPort -gt 65535){throw 'UpstreamPort must be 1..65535'}
 if(-not(Test-Path -LiteralPath $c.XrayPath -PathType Leaf) -or [IO.Path]::GetFileName($c.XrayPath) -ne 'xray.exe'){throw 'XrayPath must point to Happ core xray.exe'}
 if([string]$c.ShortcutPath -notlike '*.lnk' -or -not [IO.Path]::IsPathRooted($c.ShortcutPath)){throw 'Absolute ShortcutPath .lnk required'}
 $sid=[Security.Principal.SecurityIdentifier]::new([string]$c.LaunchUserSid)
 return $c
}
function Test-GuardPublicIPv4([string]$Address){
 if($Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$'){return $false}
 $ip=$null;if(-not [Net.IPAddress]::TryParse($Address,[ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork' -or $ip.ToString() -cne $Address){return $false}
 $b=$ip.GetAddressBytes()
 if($b[0] -in @(0,10,127) -or $b[0] -ge 224){return $false}
 if(($b[0] -eq 169 -and $b[1] -eq 254) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) -or ($b[0] -eq 198 -and $b[1] -in @(18,19))){return $false}
 if(($b[0] -eq 192 -and $b[1] -eq 0 -and $b[2] -in @(0,2)) -or ($b[0] -eq 198 -and $b[1] -eq 51 -and $b[2] -eq 100) -or ($b[0] -eq 203 -and $b[1] -eq 0 -and $b[2] -eq 113)){return $false}
 return $true
}
function Get-ClaudeInventory($c){
 if($c.ClaudeRoot){
  $dir=[IO.Path]::GetFullPath([string]$c.ClaudeRoot).TrimEnd('\');$exe=[IO.Path]::GetFullPath([string]$c.ClaudeExe)
  if(-not $exe.StartsWith($dir+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($exe) -ne 'claude.exe' -or -not(Test-Path -LiteralPath $exe)){throw 'Standalone ClaudeExe must be claude.exe inside ClaudeRoot'}
  if((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ClaudeRoot must not be a junction'}
  $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.exe' -File -Recurse);$packages=@();$target=$exe
 }else{
  $p=@(Get-AppxPackage -AllUsers -Name Claude | Where-Object PackageFamilyName -eq $c.PackageFamily | Sort-Object InstallLocation -Unique)
  if(-not $p.Count){throw 'Claude MSIX not found. Install Claude first or configure standalone ClaudeRoot/ClaudeExe.'}
  $files=@($p | ForEach-Object {Get-ChildItem -LiteralPath $_.InstallLocation -Filter '*.exe' -File -Recurse} | Sort-Object FullName -Unique)
  $latest=$p | Sort-Object Version -Descending | Select-Object -First 1;$target=Join-Path $latest.InstallLocation 'app\claude.exe';$packages=@($p.PackageFullName)
 }
 # Desktop downloads Code outside WindowsApps. Protect existing cache EXEs too.
 if($c.CodeRoot){$files+=@(Get-CodeCacheExecutables ([string]$c.CodeRoot));$files=@($files | Sort-Object FullName -Unique)}
 if($files.Count -lt 1 -or $files.Count -gt 100 -or -not(Test-Path -LiteralPath $target)){throw 'Abnormal Claude executable inventory'}
 [pscustomobject]@{Files=$files;Packages=$packages;Executable=$target}
}
function Get-CodeCacheExecutables([string]$Path){
 if(-not [IO.Path]::IsPathRooted($Path)){throw 'CodeRoot must be absolute'}
 $pathFull=[IO.Path]::GetFullPath($Path).TrimEnd('\')
 if([IO.Path]::GetFileName($pathFull) -ne 'claude-code'){throw 'CodeRoot must be the dedicated claude-code cache directory'}
 # Inspect all existing ancestors before traversal; never follow cache junctions.
 $ancestor=$pathFull
 while($ancestor){if(Test-Path -LiteralPath $ancestor){if((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in CodeRoot'}};$next=Split-Path $ancestor -Parent;if($next -eq $ancestor){break};$ancestor=$next}
 if(-not(Test-Path -LiteralPath $pathFull)){return}
 $pending=New-Object 'Collections.Generic.Queue[string]';$pending.Enqueue($pathFull);$visited=0
 while($pending.Count){
  $directory=$pending.Dequeue();$visited++;if($visited -gt 1000){throw 'Abnormal Code cache directory count'}
  foreach($item in @(Get-ChildItem -LiteralPath $directory -Force)){
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point inside CodeRoot'}
   if($item.PSIsContainer){$pending.Enqueue($item.FullName)}elseif($item.Extension -ieq '.exe'){$item}
  }
 }
}
function Test-VerifiedCoworkService($Process,$Services,[string[]]$AllowedServicePaths){
 if($Process.Name -ne 'cowork-svc.exe'){return $false}
 $matching=@($Services | Where-Object {$_.Name -eq 'CoworkVMService' -and $_.State -eq 'Running' -and $_.StartName -in @('LocalSystem','NT AUTHORITY\SYSTEM') -and [int]$_.ProcessId -eq [int]$Process.ProcessId})
 if($matching.Count -ne 1){return $false}
 $command=[string]$matching[0].PathName;$path=''
 if($command -match '^"([^"]+\\cowork-svc\.exe)"(?:\s.*)?$'){$path=$matches[1]}
 elseif($command -match '^([^"\r\n]+\\cowork-svc\.exe)(?:\s.*)?$'){$path=$matches[1]}
 else{return $false}
 if($path -notin $AllowedServicePaths){return $false}
 if($Process.ExecutablePath -and $Process.ExecutablePath -ne $path){return $false}
 return $true
}
function Assert-NoClaudeClient {
 # Unelevated entry points must not query Get-AppxPackage -AllUsers.
 # Full package/service verification remains mandatory in elevated Manage-Happ.
 $clients=@(Get-Process -ErrorAction Stop | Where-Object {$_.ProcessName -ieq 'claude'})
 if($clients.Count){throw ('Close Claude yourself before maintenance; client PIDs: '+(($clients | ForEach-Object {$_.Id}) -join ', '))}
}
function Assert-NoClaude($Configuration=$null){
 $found=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^(claude|cowork-svc)\.exe$' -or $_.ExecutablePath -match '\\WindowsApps\\Claude_[^\\]+\\'})
 if(-not $found.Count){return}
 $services=@();$allowed=@()
 if(@($found | Where-Object Name -eq 'cowork-svc.exe').Count){
  if(-not $Configuration){$cfgPath=Join-Path (Get-GuardRoot) 'config.json';if(Test-Path -LiteralPath $cfgPath){$Configuration=Read-GuardConfig $cfgPath}}
  if($Configuration){$inventory=Get-ClaudeInventory $Configuration;$allowed=@($inventory.Files | Where-Object Name -eq 'cowork-svc.exe' | Select-Object -ExpandProperty FullName);$services=@(Get-CimInstance Win32_Service -Filter "Name='CoworkVMService'")}
 }
 $blocking=@($found | Where-Object {-not(Test-VerifiedCoworkService $_ $services $allowed)})
 if($blocking.Count){throw ('Claude client or unverified package process is already running: '+(($blocking | ForEach-Object {$_.Name+':'+$_.ProcessId}) -join ', ')+'. Close it yourself; no process was started or stopped.')}
 Write-Verbose 'Only the registered LocalSystem CoworkVMService is running; client is closed. Network filters remain unchanged.'
}
function Get-OtherPorts([int]$port){if($port -gt 1){'1-'+($port-1)};if($port -lt 65535){($port+1).ToString()+'-65535'}}
function Invoke-ElevatedPowerShell([string]$arguments){
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe";$info.Arguments=$arguments;$info.UseShellExecute=$true;$info.Verb='runas'
 $process=[Diagnostics.Process]::Start($info);$null=$process.Handle;$process.WaitForExit();$code=$process.ExitCode;$process.Dispose();return [int]$code
}
