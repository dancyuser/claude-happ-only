#requires -Version 5.1
function Get-UniversalRoot {Join-Path $env:ProgramData 'UniversalNetworkGuard'}
function Assert-UniversalPlainPath([string]$Path){
 $p=[IO.Path]::GetFullPath($Path)
 while($p){if(Test-Path -LiteralPath $p){if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Reparse point: '+$p)}};$n=Split-Path $p -Parent;if($n -eq $p){break};$p=$n}
}
function ConvertTo-UniversalProfile($InputProfile){
 if($null -eq $InputProfile -or $InputProfile.GetType() -ne [Management.Automation.PSCustomObject]){throw 'Profile must be a JSON object'}
 $c=$InputProfile
 if($c.Schema -ne 1 -or $c.Mode -notin @('TunProxy','TunOnly')){throw 'Schema=1 and Mode=TunProxy or TunOnly required'}
 $c.ProfileId=([guid]$c.ProfileId).ToString()
 if([guid]$c.ProfileId -eq [guid]::Empty){throw 'ProfileId cannot be empty'}
 if([string]::IsNullOrWhiteSpace([string]$c.Name) -or $c.Name.Length -gt 100){throw 'Profile name required, maximum 100 characters'}
 $files=@($c.Programs)
 if($files.Count -lt 1 -or $files.Count -gt 128){throw 'Select 1..128 exact executable paths'}
 $c.Programs=@($files | ForEach-Object {
  if($_ -isnot [string] -or -not [IO.Path]::IsPathRooted($_) -or $_ -match '[*?]'){throw 'Programs must contain absolute paths without wildcards'}
  $p=[IO.Path]::GetFullPath($_);if([IO.Path]::GetExtension($p) -ine '.exe'){throw 'Select an EXE file'};Assert-UniversalPlainPath $p;$p
 } | Sort-Object -Unique)
 if(-not $c.PSObject.Properties['ExpectedCountry']){$c|Add-Member NoteProperty ExpectedCountry ''}
 if($c.ExpectedCountry -and $c.ExpectedCountry -cnotmatch '^[A-Z]{2}$'){throw 'ExpectedCountry must be empty or an uppercase ISO country code'}
 if(-not $c.PSObject.Properties['AllowIPv6']){$c|Add-Member NoteProperty AllowIPv6 $false}
 if($c.AllowIPv6 -isnot [bool]){throw 'AllowIPv6 must be boolean'}
 if($c.Mode -eq 'TunOnly'){
  $c.TunnelInterfaceGuid=([guid]$c.TunnelInterfaceGuid).ToString()
  if([guid]$c.TunnelInterfaceGuid -eq [guid]::Empty){throw 'Select an actual tunnel interface GUID'}
  if(-not $c.PSObject.Properties['KillSwitchScope']){throw 'Choose KillSwitchScope explicitly: InterfaceAndCore or InterfaceOnly'}
  if($c.KillSwitchScope -notin @('InterfaceOnly','InterfaceAndCore')){throw 'Unknown KillSwitchScope'}
  if($c.KillSwitchScope -eq 'InterfaceAndCore'){
   $core=$c.VpnCore
   if($null -eq $core -or $core.GetType() -ne [Management.Automation.PSCustomObject]){throw 'Strict TUN mode requires VpnCore'}
   if(-not [IO.Path]::IsPathRooted([string]$core.Executable) -or [IO.Path]::GetExtension([string]$core.Executable) -ine '.exe' -or $core.Executable -match '[*?]'){throw 'VpnCore requires one exact EXE path'}
   $core.Executable=[IO.Path]::GetFullPath($core.Executable);Assert-UniversalPlainPath $core.Executable
   if($core.Executable -in $c.Programs){throw 'VPN core cannot also be a protected client'}
   $ip=$null;if(-not [Net.IPAddress]::TryParse([string]$core.ServerAddress,[ref]$ip) -or [Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){throw 'Pin VpnCore.ServerAddress to a non-loopback IP'}
   $core.ServerAddress=$ip.ToString()
   if([string]$core.ServerPort -notmatch '^\d+$' -or [int]$core.ServerPort -lt 1 -or [int]$core.ServerPort -gt 65535 -or $core.ServerProtocol -notin @('TCP','UDP')){throw 'Invalid VPN server port/protocol'}
  }
 }else{
  $c.TransportInterfaceGuid=([guid]$c.TransportInterfaceGuid).ToString()
  if([guid]$c.TransportInterfaceGuid -eq [guid]::Empty){throw 'Select an actual transport interface GUID'}
  if($null -eq $c.Proxy -or $c.Proxy.GetType() -ne [Management.Automation.PSCustomObject]){throw 'Proxy object required'}
  if($c.Proxy.Scheme -notin @('http','socks5h') -or $c.Proxy.Address -ne '127.0.0.1'){throw 'Proxy must use http or socks5h on 127.0.0.1'}
  foreach($key in @('Port','ServerPort')){if($c.Proxy.$key -is [bool] -or [string]$c.Proxy.$key -notmatch '^\d+$' -or [int]$c.Proxy.$key -lt 1 -or [int]$c.Proxy.$key -gt 65535){throw ('Invalid proxy '+$key)}}
  $ip=$null;if(-not [Net.IPAddress]::TryParse([string]$c.Proxy.ServerAddress,[ref]$ip) -or [Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){throw 'Proxy.ServerAddress must be a pinned non-loopback IPv4/IPv6 address, not a hostname'}
  $c.Proxy.ServerAddress=$ip.ToString()
  if($c.Proxy.ServerProtocol -notin @('TCP','UDP')){throw 'Proxy.ServerProtocol must be TCP or UDP'}
  if(-not [IO.Path]::IsPathRooted([string]$c.Proxy.Executable) -or [IO.Path]::GetExtension([string]$c.Proxy.Executable) -ine '.exe' -or $c.Proxy.Executable -match '[*?]'){throw 'Select exact proxy network-core EXE path'}
  $c.Proxy.Executable=[IO.Path]::GetFullPath($c.Proxy.Executable);Assert-UniversalPlainPath $c.Proxy.Executable
  if($c.Proxy.Executable -in $c.Programs){throw 'Proxy network core cannot also be a protected client'}
 }
 return $c
}
function Resolve-UniversalBinding($Configuration,$Adapters){
 $guid=if($Configuration.Mode -eq 'TunOnly'){$Configuration.TunnelInterfaceGuid}else{$Configuration.TransportInterfaceGuid}
 $matches=@($Adapters | Where-Object {([string]$_.InterfaceGuid).Trim('{}') -ieq $guid})
 if($matches.Count -gt 1){throw 'Ambiguous interface GUID; no adapter guessed'}
 if(-not $matches.Count){return [pscustomobject]@{Guid=$guid;Present=$false;Up=$false;Name='';Index=0;Luid='0'}}
 $a=$matches[0]
 if($Configuration.Mode -eq 'TunOnly' -and $a.HardwareInterface){throw 'TunOnly requires an explicitly selected virtual tunnel, not a physical adapter'}
 return [pscustomobject]@{Guid=$guid;Present=$true;Up=([string]$a.Status -eq 'Up');Name=[string]$a.Name;Index=[int]$a.ifIndex;Luid='0'}
}
function New-UniversalPlan($Configuration,$Binding,[string]$Probe){
 $programs=@(@($Configuration.Programs)+@($Probe)|Sort-Object -Unique)
 $rules=@()
 foreach($p in $programs){
  if($Configuration.Mode -eq 'TunOnly'){
   if(-not $Binding.Present){$rules+=@([pscustomobject]@{Kind='Block';Path=$p})}
   else{$rules+=@([pscustomobject]@{Kind='Interface';Path=$p;Luid=[string]$Binding.Luid;IPv6=[bool]$Configuration.AllowIPv6})}
  }else{$rules+=@([pscustomobject]@{Kind='Endpoint';Path=$p;Address='127.0.0.1';Port=[int]$Configuration.Proxy.Port;Protocol=6})}
 }
 if($Configuration.Mode -eq 'TunProxy'){
  $p=$Configuration.Proxy.Executable
  if(-not $Binding.Present){$rules+=@([pscustomobject]@{Kind='Block';Path=$p})}
  else{$rules+=@([pscustomobject]@{Kind='Interface';Path=$p;Luid=[string]$Binding.Luid;IPv6=($Configuration.Proxy.ServerAddress -match ':')})}
  $rules+=@([pscustomobject]@{Kind='Endpoint';Path=$p;Address=$Configuration.Proxy.ServerAddress;Port=[int]$Configuration.Proxy.ServerPort;Protocol=$(if($Configuration.Proxy.ServerProtocol -eq 'TCP'){6}else{17})})
  $rules+=@([pscustomobject]@{Kind='ReservePort';Path=$p;Port=[int]$Configuration.Proxy.Port})
 }
 if($Configuration.Mode -eq 'TunOnly' -and $Configuration.KillSwitchScope -eq 'InterfaceAndCore'){
  $core=$Configuration.VpnCore
  $rules+=@([pscustomobject]@{Kind='Endpoint';Path=$core.Executable;Address=$core.ServerAddress;Port=[int]$core.ServerPort;Protocol=$(if($core.ServerProtocol -eq 'TCP'){6}else{17})})
 }
 return @($rules)
}
function Set-UniversalRules($Engine,$Plan){
 $keys=@(foreach($r in $Plan){switch($r.Kind){
  'Block' {$Engine.BlockProgram($r.Path,$true)}
  'Interface' {$Engine.LockInterface($r.Path,[uint64]$r.Luid,[bool]$r.IPv6,$true)}
  'Endpoint' {$Engine.LockEndpoint($r.Path,$r.Address,[int]$r.Port,[int]$r.Protocol,$true)}
  'ReservePort' {$Engine.ReservePort($r.Path,[int]$r.Port,$true)}
  default {throw ('Unknown rule kind: '+$r.Kind)}
 }})
 return @($keys | Sort-Object -Unique)
}
function Assert-UniversalClientsClosed($Configuration){
 $paths=@($Configuration.Programs)
 # Conservative fallback for inaccessible process paths: same image name blocks maintenance.
 $names=@($paths|ForEach-Object {[IO.Path]::GetFileName($_)})
 $running=@(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {($_.ExecutablePath -and $_.ExecutablePath -in $paths) -or (-not $_.ExecutablePath -and $_.Name -in $names)})
 if($running.Count){throw ('Close protected clients yourself before maintenance: '+(($running|ForEach-Object {$_.Name+' PID='+$_.ProcessId}) -join ', '))}
}
function Invoke-UniversalCurl([string]$Executable,[string[]]$Arguments){
 if($Arguments|Where-Object {$_ -match '["\r\n]'}){throw 'Unsafe diagnostic argument'}
 $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=$Executable
 $si.Arguments=(@('-q','--silent','--show-error','--fail','--connect-timeout','5','--max-time','12')+@($Arguments)|ForEach-Object {'"'+$_+'"'}) -join ' '
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 foreach($k in @($si.EnvironmentVariables.Keys|Where-Object {$_ -match '^(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)$'})){$si.EnvironmentVariables.Remove($k)}
 $p=New-Object Diagnostics.Process;$p.StartInfo=$si
 try{$null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(15000)){$p.Kill();$p.WaitForExit();throw 'Diagnostic curl timed out'};return [pscustomobject]@{Code=$p.ExitCode;Body=$o.Result.Trim();Error=$e.Result.Trim()}}finally{$p.Dispose()}
}
