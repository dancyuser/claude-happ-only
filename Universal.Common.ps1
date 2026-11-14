#requires -Version 5.1
function Get-UniversalRoot {Join-Path $env:ProgramData 'UniversalNetworkGuard'}
function New-ClaudeTunProfile([string[]]$Programs,[guid]$TunnelGuid,[string]$UserSid,[guid]$ProfileId=[guid]::NewGuid(),[string]$DesktopExecutable){
 $profile=[pscustomobject]@{Schema=1;ProfileId=$ProfileId.ToString();Name='Claude TUN Only';Mode='TunOnly';Programs=$Programs;DesktopExecutable=$DesktopExecutable;TunnelInterfaceGuid=$TunnelGuid.ToString();ExpectedCountry='';AllowIPv6=$false;KillSwitchScope='InterfaceOnly';LaunchUserSid=$UserSid}
 ConvertTo-UniversalProfile $profile
}
function Get-UniversalLaunchArguments($Configuration,[string]$Executable,[string[]]$Arguments){
 $result=@($Arguments)
 if($Configuration.Mode -eq 'TunOnly' -and $Configuration.Name -eq 'Claude TUN Only' -and $Configuration.PSObject.Properties['DesktopExecutable'] -and $Executable -ieq $Configuration.DesktopExecutable -and [IO.Path]::GetFileName($Executable) -ieq 'claude.exe'){$result+=@('--no-proxy-server')}
 return $result
}
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
 if($c.PSObject.Properties['DesktopExecutable']){
  if([string]::IsNullOrWhiteSpace([string]$c.DesktopExecutable) -or -not [IO.Path]::IsPathRooted([string]$c.DesktopExecutable)){throw 'DesktopExecutable must be an absolute Claude EXE path'}
  $c.DesktopExecutable=[IO.Path]::GetFullPath([string]$c.DesktopExecutable)
  if([IO.Path]::GetFileName($c.DesktopExecutable) -ine 'claude.exe' -or $c.DesktopExecutable -notin $c.Programs){throw 'DesktopExecutable must be claude.exe in Programs'}
 }
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

function Get-UniversalProbeResolveArguments([string[]]$Hostnames){
 # curl's threaded resolver uses loopback socket pairs on Windows. A strict
 # TUN-only process cannot use those. Resolve in the worker, retaining TLS/SNI.
 foreach($hostname in $Hostnames){
  if($hostname -notmatch '^[a-zA-Z0-9.-]+$'){throw 'Invalid probe hostname'}
  $answers=@(Resolve-DnsName -Name $hostname -Type A -ErrorAction Stop|Where-Object {$_.IPAddress})
  $address=$null
  foreach($answer in $answers){$ip=$null;if([Net.IPAddress]::TryParse([string]$answer.IPAddress,[ref]$ip) -and $ip.AddressFamily -eq 'InterNetwork' -and -not [Net.IPAddress]::IsLoopback($ip) -and -not $ip.Equals([Net.IPAddress]::Any)){$address=$ip.ToString();break}}
  if(-not $address){throw ('No IPv4 address for probe: '+$hostname)}
  '--resolve';$hostname+':443:'+$address
 }
}

function Test-UniversalProbeConsistency($Configuration,[string]$TraceIP,[string]$Country,[string]$OtherIP){
 foreach($address in @($TraceIP,$OtherIP)){
  $parsed=$null;if(-not [Net.IPAddress]::TryParse($address,[ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork' -or $parsed.ToString() -cne $address -or [Net.IPAddress]::IsLoopback($parsed) -or $parsed.Equals([Net.IPAddress]::Any)){return $false}
 }
 if($Country -cnotmatch '^[A-Z]{2}$'){return $false}
 $sameExitRequired=($Configuration.Mode -eq 'TunProxy' -or $Configuration.KillSwitchScope -eq 'InterfaceAndCore' -or [bool]$Configuration.ExpectedCountry)
 if($sameExitRequired -and $TraceIP -ne $OtherIP){return $false}
 if($Configuration.ExpectedCountry -and $Country -ne $Configuration.ExpectedCountry){return $false}
 return $true
}

# Setup discovery only: observations are candidates, never an automatic policy.
function ConvertTo-UniversalEndpointCandidates([string]$Executable,$Processes,$Connections,$Addresses,$Adapters){
 $full=[IO.Path]::GetFullPath($Executable);$name=[IO.Path]::GetFileName($full)
 $owners=@{}
 foreach($p in $Processes){
  if($p.ExecutablePath -and [string]$p.ExecutablePath -ieq $full){$owners[[int]$p.ProcessId]=$true}
  elseif(-not $p.ExecutablePath -and [string]$p.Name -ieq $name){$owners[[int]$p.ProcessId]=$false}
 }
 $seen=@{}; $rows=@()
 foreach($connection in $Connections){
  $ownerId=[int]$connection.OwningProcess
  if(-not $owners.ContainsKey($ownerId) -or [string]$connection.State -ne 'Established'){continue}
  $ip=$null
  if(-not [Net.IPAddress]::TryParse([string]$connection.RemoteAddress,[ref]$ip)){continue}
  if($ip.IsIPv4MappedToIPv6){$ip=$ip.MapToIPv4()}
  if([Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any) -or $ip.IsIPv6LinkLocal -or $ip.IsIPv6Multicast){continue}
  if($ip.AddressFamily -eq 'InterNetwork'){
   $b=$ip.GetAddressBytes()
   if($b[0] -eq 0 -or $b[0] -ge 224 -or ($b[0] -eq 169 -and $b[1] -eq 254)){continue}
  }
  $port=[int]$connection.RemotePort;if($port -lt 1 -or $port -gt 65535){continue}
  $local=[string]$connection.LocalAddress
  $interfaces=@($Addresses|Where-Object {$_.IPAddress -eq $local}|ForEach-Object { $index=$_.InterfaceIndex; $Adapters|Where-Object {$_.ifIndex -eq $index} })
  $interface=($interfaces|ForEach-Object {$_.Name+' (#'+$_.ifIndex+')'}|Sort-Object -Unique) -join ', '
  if(-not $interface){$interface='Unknown (local '+$local+')'}
  $key=$ip.ToString()+'|'+$port+'|'+$local+'|'+$ownerId
  if($seen.ContainsKey($key)){continue};$seen[$key]=$true
  $rows+=@([pscustomobject]@{ServerAddress=$ip.ToString();ServerPort=$port;ServerProtocol='TCP';LocalAddress=$local;Interface=$interface;ProcessId=$ownerId;PathVerified=[bool]$owners[$ownerId]})
 }
 return @($rows|Sort-Object ServerAddress,ServerPort,Interface,ProcessId)
}
function Get-UniversalEndpointCandidates([string]$Executable){
 $processes=@(Get-CimInstance Win32_Process -ErrorAction Stop)
 $connections=@(Get-NetTCPConnection -State Established -ErrorAction Stop)
 $addresses=@(Get-NetIPAddress -ErrorAction Stop)
 $adapters=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
 ConvertTo-UniversalEndpointCandidates $Executable $processes $connections $addresses $adapters
}
function Get-UniversalAddressCountry([string]$Address){
 $unknown=[pscustomobject]@{Name='Unknown / lookup unavailable';Code=''}
 $ip=$null;if(-not [Net.IPAddress]::TryParse($Address,[ref]$ip)){return $unknown}
 # Do not query a service for local/private addresses.
 if($ip.AddressFamily -eq 'InterNetwork'){
  $b=$ip.GetAddressBytes()
  if($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) -or ($b[0] -eq 169 -and $b[1] -eq 254)){return $unknown}
 }elseif($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal -or $ip.IsIPv6Multicast -or [Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::IPv6Any) -or (($ip.GetAddressBytes()[0] -band 254) -eq 252)){return $unknown}
 try{
  $uri='https://ipwho.is/'+$ip.ToString()+'?fields=success,ip,country,country_code'
  $r=Invoke-UniversalCurl "$env:SystemRoot\System32\curl.exe" @('--noproxy','*','--max-time','4',$uri)
  if($r.Code -ne 0){return $unknown}
  $data=$r.Body|ConvertFrom-Json;$returned=$null
  if($data.success -ne $true -or -not [Net.IPAddress]::TryParse([string]$data.ip,[ref]$returned) -or -not $returned.Equals($ip) -or [string]$data.country_code -cnotmatch '^[A-Z]{2}$'){return $unknown}
  $country=([string]$data.country -replace '[\p{C}]','').Trim()
  if(-not $country -or $country.Length -gt 100){return $unknown}
  return [pscustomobject]@{Name=$country;Code=[string]$data.country_code}
 }catch{return $unknown}
}
function Read-UniversalVpnEndpoint([string]$Executable,[string]$TunnelGuid){
 Write-Host 'Detecting server connections of the selected VPN core...'
 Write-Host 'Server IP is not the local TUN address or the public exit IP. Country lookup uses ipwho.is for candidate IPs.'
 $candidates=@();try{$candidates=@(Get-UniversalEndpointCandidates $Executable)}catch{Write-Warning 'Connection discovery unavailable; enter the server manually.'}
 $cache=@{}; $display=@($candidates|Select-Object -First 16)
 if($candidates.Count -gt 16){Write-Warning 'More than 16 connections found. Only the first 16 are shown; manual entry is available.'}
 for($i=0;$i -lt $display.Count;$i++){
  $row=$display[$i]
  if(-not $cache.ContainsKey($row.ServerAddress)){$cache[$row.ServerAddress]=Get-UniversalAddressCountry $row.ServerAddress}
  $country=$cache[$row.ServerAddress]
  $trust=if($row.PathVerified){'EXE path verified'}else{'EXE path unavailable; process name only'}
  Write-Host (($i+1).ToString()+') '+$row.ServerAddress+':'+$row.ServerPort+' '+$row.ServerProtocol+' | '+$country.Name+' '+$country.Code+' | '+$row.Interface+' | PID '+$row.ProcessId+' | '+$trust)
 }
 Write-Host 'An observed connection can also be DIRECT traffic or DNS. Confirm the VPN endpoint using your VPN settings.'
 Write-Host 'UDP remote peers cannot be inferred from Windows UDP sockets; use manual entry for UDP.'
 $selected=$null
 if($display.Count){
  $default=if($display.Count -eq 1 -and $display[0].PathVerified){'1'}else{'M'}
  $pick=Read-Host ('Server candidate number, M = manual, Q = cancel ['+$default+']')
  if([string]::IsNullOrWhiteSpace($pick)){$pick=$default}
  if($pick -ieq 'Q'){throw 'Setup cancelled'}
  if($pick -ine 'M'){
   $number=0;if(-not [int]::TryParse($pick,[ref]$number) -or $number -lt 1 -or $number -gt $display.Count){throw 'Invalid server candidate'}
   $selected=$display[$number-1]
  }
 }
 if(-not $selected){
  $address=Read-Host 'Pinned VPN server IPv4/IPv6 (from VPN settings, not the TUN or exit IP)'
  $ip=$null;if(-not [Net.IPAddress]::TryParse($address,[ref]$ip) -or [Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){throw 'A non-loopback server IP is required'}
  $port=Read-Host 'VPN server port [443]';if(-not $port){$port='443'}
  $protocol=Read-Host 'VPN upstream protocol TCP or UDP [TCP]';if(-not $protocol){$protocol='TCP'};$protocol=$protocol.ToUpperInvariant()
  if($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535 -or $protocol -notin @('TCP','UDP')){throw 'Invalid server port/protocol'}
  $interface='Unknown (manual entry)'
  try{$route=@(Find-NetRoute -RemoteIPAddress $ip.ToString() -ErrorAction Stop|Where-Object {$_.PSObject.Properties['InterfaceAlias']});if($route.Count){$interface=([string[]]@($route.InterfaceAlias|Sort-Object -Unique)) -join ', '}}catch{}
  $selected=[pscustomobject]@{ServerAddress=$ip.ToString();ServerPort=[int]$port;ServerProtocol=$protocol;Interface=$interface;PathVerified=$false}
 }
 if(-not $cache.ContainsKey($selected.ServerAddress)){$cache[$selected.ServerAddress]=Get-UniversalAddressCountry $selected.ServerAddress}
 $country=$cache[$selected.ServerAddress]
 Write-Host ('Server IP: '+$selected.ServerAddress+' | port: '+$selected.ServerPort+' | '+$selected.ServerProtocol)
 Write-Host ('Server country (IP geolocation, not exit country): '+$country.Name+' '+$country.Code)
 Write-Host ('Server transport interface: '+$selected.Interface)
 $tun='GUID='+$TunnelGuid
 try{$adapter=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop|Where-Object {([string]$_.InterfaceGuid).Trim('{}') -ieq $TunnelGuid});if($adapter.Count -eq 1){$tun=$adapter[0].Name+' | '+$adapter[0].InterfaceDescription+' | '+$tun}}catch{}
 Write-Host ('Selected client TUN: '+$tun)
 if(-not $selected.PathVerified){Write-Warning 'The core EXE path could not be verified for this endpoint. Check the VPN settings before approving.'}
 if((Read-Host 'Use this IP, port and protocol for the VPN core lock? y/N') -notmatch '^(?i:y|yes)$'){throw 'Server endpoint not approved; setup cancelled'}
 return [pscustomobject]@{Executable=$Executable;ServerAddress=$selected.ServerAddress;ServerPort=[int]$selected.ServerPort;ServerProtocol=$selected.ServerProtocol}
}
