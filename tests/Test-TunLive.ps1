#requires -Version 5.1
param([string]$SourceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$ReportPath,[Parameter(Mandatory)][guid]$TunnelGuid,[switch]$DisconnectTunnel,[string]$ScratchDirectory=(Join-Path $env:TEMP 'ClaudeTunLiveTests'))
$ErrorActionPreference='Stop'
$report=[ordered]@{StartedUTC=[DateTime]::UtcNow.ToString('o');Status='FAIL';Tests=@();TunnelRestored=$false;FiltersRemoved=$false}
$engine=$null;$keys=@();$removedRoutes=@();$disabled=$false;$adapter=$null
function Record($Name,$Pass,$Detail){$report.Tests+=@([pscustomobject]@{Name=$Name;Pass=[bool]$Pass;Detail=$Detail});$report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $ReportPath -Encoding UTF8;if(-not $Pass){throw ('Test failed: '+$Name)}}
function Invoke-TunTestCurl([string]$Exe,[string[]]$Extra=@()){
 $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=$Exe;$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $resolveArgs=@();foreach($item in $Extra){if($item -match '^https://([^/]+)'){$hostName=$matches[1];if($script:resolved.ContainsKey($hostName)){$resolveArgs+=@('--resolve',($hostName+':443:'+$script:resolved[$hostName]))}}};$all=@('-q','--silent','--show-error','--noproxy','*','--connect-timeout','3','--max-time','6')+@($resolveArgs)+@($Extra)
 if([IO.Path]::GetFileName($Exe) -eq 'SocketProbe.exe'){$all=@($Extra)}
 $si.Arguments=($all|ForEach-Object {'"'+$_+'"'}) -join ' '
 foreach($k in @($si.EnvironmentVariables.Keys|Where-Object {$_ -match '^(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)$'})){$si.EnvironmentVariables.Remove($k)}
 $p=[Diagnostics.Process]::Start($si);try{$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(10000)){$p.Kill();throw 'Invoke-TunTestCurl timed out'};return [pscustomobject]@{Code=$p.ExitCode;Body=$o.Result;Error=$e.Result}}finally{$p.Dispose()}
}
try{
 if(-not $DisconnectTunnel){throw 'Pass -DisconnectTunnel explicitly: this live test temporarily disconnects the selected VPN interface'};New-Item -ItemType Directory -Path $ScratchDirectory -Force|Out-Null
 if(-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrative test worker required'}
 Add-Type -Path (Join-Path $SourceRoot 'Universal.Wfp.cs')
 $adapter=@(Get-NetAdapter -IncludeHidden|Where-Object {([guid]$_.InterfaceGuid) -eq $TunnelGuid})
 if($adapter.Count -ne 1 -or $adapter[0].HardwareInterface -or $adapter[0].Status -ne 'Up'){throw 'Expected one active virtual TUN'};$adapter=$adapter[0]
 $physical=@(Get-NetAdapter|Where-Object {$_.HardwareInterface -and $_.Status -eq 'Up'}|Sort-Object ifIndex|Select-Object -First 1)
 if($physical.Count -ne 1){throw 'Physical control adapter missing'}
 $physicalIP=(Get-NetIPAddress -InterfaceIndex $physical[0].ifIndex -AddressFamily IPv4|Where-Object {$_.IPAddress -notlike '169.254.*'}|Select-Object -First 1).IPAddress
 $report.Tunnel=[pscustomobject]@{Guid=$TunnelGuid.ToString();Name=$adapter.Name;Index=$adapter.ifIndex};$report.Physical=$physical[0].Name
 $testHome=Join-Path $ScratchDirectory ('tun-test-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $testHome|Out-Null
 $probe=Join-Path $testHome 'Guarded-curl.exe';Copy-Item "$env:SystemRoot\System32\curl.exe" $probe
 $testCurlExe="$env:SystemRoot\System32\curl.exe";$url='https://api.ipify.org';$api='https://api.anthropic.com/'
 $script:resolved=@{};foreach($dnsName in @('api.anthropic.com','api.ipify.org')){$script:resolved[$dnsName]=[string](Resolve-DnsName $dnsName -Type A -ErrorAction Stop|Where-Object IPAddress|Select-Object -First 1).IPAddress};$baseline=Invoke-TunTestCurl $testCurlExe @('--ipv4','--interface',$physicalIP,$url);Record 'Unprotected physical Internet control' ($baseline.Code -eq 0) $baseline
 $id=[guid]::NewGuid().ToString();$report.TestProfileId=$id;$engine=[UniversalWfp]::new($id)
 $luid=[UniversalWfp]::InterfaceLuid($TunnelGuid.ToString());$report.LuidBefore=[string]$luid;$engine.Begin();$keys=@($engine.LockInterface($probe,$luid,$false,$true));$engine.Commit()
 $positive=Invoke-TunTestCurl $probe @('--ipv4',$api);Record 'Protected Anthropic HTTPS through TUN' ($positive.Code -eq 0) $positive
 $negative=Invoke-TunTestCurl $probe @('--ipv4','--interface',$physicalIP,$url);Record 'Physical-interface bypass blocked' ($negative.Code -ne 0) $negative
 $negative=Invoke-TunTestCurl $probe @('--ipv4','--proxy','http://127.0.0.1:10808','--noproxy','invalid.invalid',$url);Record 'Loopback proxy bypass rejected' ($negative.Code -ne 0) $negative
 $socketProbe=Join-Path $testHome 'SocketProbe.exe';Add-Type -Path (Join-Path $SourceRoot 'tests\SocketProbe.cs') -OutputAssembly $socketProbe -OutputType ConsoleApplication
 $null=[Reflection.Assembly]::LoadFile($socketProbe);$udpEcho=[UdpProbeEcho]::new($physicalIP)
 $v6Listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::IPv6Loopback,0);$v6Listener.Start();$v6Port=$v6Listener.LocalEndpoint.Port
 try{
  $udpControl=Invoke-TunTestCurl $socketProbe @('udp',$physicalIP,([string]$udpEcho.Port),$physicalIP);Record 'Unprotected UDP echo control' ($udpControl.Code -eq 0) $udpControl
  $v6Control=Invoke-TunTestCurl $socketProbe @('tcp','::1',([string]$v6Port));if($v6Control.Code -eq 0){Record 'Unprotected IPv6 socket control' $true $v6Control}else{$report.Tests+=@([pscustomobject]@{Name='IPv6 positive control unavailable';Pass=$null;Skipped=$true;Detail=$v6Control})}
  $engine.Begin();$keys+=@($engine.LockInterface($socketProbe,$luid,$false,$true));$engine.Commit()
  $udpBlocked=Invoke-TunTestCurl $socketProbe @('udp',$physicalIP,([string]$udpEcho.Port),$physicalIP);Record 'UDP outside TUN receives no echo under protection' ($udpBlocked.Code -ne 0) $udpBlocked
  $v6Blocked=Invoke-TunTestCurl $socketProbe @('tcp','::1',([string]$v6Port));Record 'IPv6 socket denied (control availability reported separately)' ($v6Blocked.Code -eq 13) $v6Blocked
  $udpAllowed=Invoke-TunTestCurl $socketProbe @('udp-send','1.1.1.1','53');Record 'UDP send through default TUN accepted' ($udpAllowed.Code -eq 0) $udpAllowed
 }finally{$v6Listener.Stop();$udpEcho.Dispose()}
 $engine.Dispose();$engine=[UniversalWfp]::new($id);$engine.VerifyOnly=$true;$check=@($engine.LockInterface($probe,$luid,$false,$true));Record 'Persistent rules survive engine close' (@($check|Where-Object {$_ -notin $keys}).Count -eq 0) $check;$engine.VerifyOnly=$false
 $defaults=@(Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore|Where-Object {$_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1')})
 if(-not $defaults.Count){throw 'TUN default routes not found; cannot test route loss'}
 foreach($route in $defaults){$removedRoutes+=@([pscustomobject]@{DestinationPrefix=$route.DestinationPrefix;NextHop=$route.NextHop;RouteMetric=$route.RouteMetric});$route|Remove-NetRoute -Confirm:$false -ErrorAction Stop}
 $control=Invoke-TunTestCurl $testCurlExe @('--ipv4','--interface',$physicalIP,$url);Record 'Physical Internet works with TUN route removed' ($control.Code -eq 0) $control
 $negative=Invoke-TunTestCurl $probe @('--ipv4',$api);Record 'TUN still Up but fallback route blocked' ($negative.Code -ne 0) $negative
 $adapter|Disable-NetAdapter -Confirm:$false -ErrorAction Stop;$disabled=$true
 $negative=Invoke-TunTestCurl $probe @('--ipv4',$api);Record 'Actual disabled TUN blocks new connections' ($negative.Code -ne 0) $negative
 $control=Invoke-TunTestCurl $testCurlExe @('--ipv4','--interface',$physicalIP,$url);Record 'Unprotected Internet still works while TUN disabled' ($control.Code -eq 0) $control
 $report.Status='PASS'
}catch{$report.Error=$_.Exception.ToString();$report.ErrorPosition=$_.InvocationInfo.PositionMessage}
finally{
 try{
  if($disabled){$adapter|Enable-NetAdapter -Confirm:$false -ErrorAction Stop;$disabled=$false};for($retry=0;$retry -lt 90;$retry++){if(@(Get-NetAdapter -IncludeHidden|Where-Object {$_.ifIndex -eq $adapter.ifIndex -and $_.Status -eq 'Up'}).Count){break};Start-Sleep -Seconds 1}
  foreach($r in $removedRoutes){$existing=@(Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix $r.DestinationPrefix -PolicyStore ActiveStore -ErrorAction SilentlyContinue|Where-Object {$_.NextHop -eq $r.NextHop});if(-not $existing.Count){New-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix $r.DestinationPrefix -NextHop $r.NextHop -RouteMetric $r.RouteMetric -PolicyStore ActiveStore -ErrorAction Stop|Out-Null}}
  $report.LuidAfter=[string][UniversalWfp]::InterfaceLuid($TunnelGuid.ToString());$report.AdapterAfter=@(Get-NetAdapter -IncludeHidden|Where-Object {([guid]$_.InterfaceGuid) -eq $TunnelGuid}|Select-Object Name,Status,ifIndex)
  $report.TunnelRestored=([string](@(Get-NetAdapter -IncludeHidden|Where-Object {$_.ifIndex -eq $adapter.ifIndex}))[0].Status -eq 'Up')
  if($probe -and $keys.Count){for($attempt=0;$attempt -lt 5;$attempt++){$recovered=Invoke-TunTestCurl $probe @('--ipv4',$api);if($recovered.Code -eq 0){break};Start-Sleep -Seconds 1};$report.Tests+=@([pscustomobject]@{Name='Protected HTTPS recovers after TUN restoration';Pass=($recovered.Code -eq 0);Detail=$recovered});if($recovered.Code -ne 0){$report.Status='FAIL'}}
 }catch{$report.RestoreError=$_.Exception.ToString();$report.Status='FAIL'}
 try{if($engine){$engine.VerifyOnly=$false;$engine.Begin();foreach($key in $keys){$engine.DeleteOwned($key)};$engine.Commit();$engine.DeleteEmptySubLayer();$report.FiltersRemoved=$true}}catch{$report.CleanupError=$_.Exception.ToString();$report.Status='FAIL'}
 if($engine){$engine.Dispose()};$report.FinishedUTC=[DateTime]::UtcNow.ToString('o');$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
if($report.Status -ne 'PASS'){exit 1}
