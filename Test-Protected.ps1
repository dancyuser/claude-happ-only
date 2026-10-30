#requires -Version 5.1
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$Upstream,[int]$ProxyPort=10808,[string]$Country='DE',[int]$UpstreamPort=443)
$ErrorActionPreference='Stop'
$g=$null;$keys=@();$fault=@();$listener=$null;$checks=@()
$probe=Join-Path $Root 'HappDiagnostic-curl.exe';$faultPort=$ProxyPort+1
function Probe([string]$name,[string]$arguments){
 $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=$probe;$si.Arguments=$arguments;$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 foreach($e in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY')){$si.EnvironmentVariables.Remove($e)}
 $p=New-Object Diagnostics.Process;$p.StartInfo=$si;$null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
 if(-not $p.WaitForExit(15000)){$p.Kill();$p.WaitForExit();throw ('Probe timeout: '+$name)}
 $r=[pscustomobject]@{Name=$name;Code=$p.ExitCode;Body=$stdout.Result.Trim();Error=$stderr.Result.Trim()};$p.Dispose();$script:checks+=@($r);return $r
}
function Blocked($r){return ($r.Code -eq 7 -and $r.Error -match 'Bad access|Permission denied|WSAEACCES|10013')}
try{
 Copy-Item -LiteralPath "$env:SystemRoot\System32\curl.exe" -Destination $probe -Force
 if((Get-FileHash $probe).Hash -ne (Get-FileHash "$env:SystemRoot\System32\curl.exe").Hash){throw 'curl copy hash mismatch'}
 $g=[HappOnlyWfp]::new();$g.Begin();$keys=@($g.RestrictProgram($probe,'127.0.0.1',$ProxyPort,$true))
 # Remove only the known test fault from an interrupted previous diagnostic run.
 $stale=@($g.RestrictProgram($probe,'127.0.0.1',$faultPort,$true) | Where-Object {$_ -notin $keys});foreach($k in $stale){$g.Delete($k)}
 $g.Commit();$g.Dispose();$g=[HappOnlyWfp]::new()
 foreach($k in $keys){$null=$g.Describe($k)}
 $common='-q --silent --show-error --fail --ipv4 --noproxy localhost --socks5-hostname 127.0.0.1:'+$ProxyPort+' --connect-timeout 5 --max-time 10 '
 $a=Probe 'ipify' ($common+'https://api.ipify.org?format=json')
 $b=Probe 'cloudflare' ($common+'https://www.cloudflare.com/cdn-cgi/trace')
 $c=Probe 'ipinfo' ($common+'https://ipinfo.io/json')
 $httpCommon='-q --silent --show-error --fail --ipv4 --noproxy invalid.invalid --proxy http://127.0.0.1:'+$ProxyPort+' --connect-timeout 5 --max-time 10 '
 $httpTrace=Probe 'http-connect-cloudflare' ($httpCommon+'https://www.cloudflare.com/cdn-cgi/trace')
 $httpIP='';$httpCountry=''
 if($httpTrace.Code -eq 0){foreach($line in ($httpTrace.Body -split '\r?\n')){if($line -match '^ip=(.+)$'){$httpIP=$matches[1]};if($line -match '^loc=(.+)$'){$httpCountry=$matches[1]}}}
 $ipA='';$ipB='';$ipC='';$countryB='';$countryC=''
 if($a.Code -eq 0){$ipA=($a.Body | ConvertFrom-Json).ip}
 if($b.Code -eq 0){foreach($line in ($b.Body -split '\r?\n')){if($line -match '^ip=(.+)$'){$ipB=$matches[1]};if($line -match '^loc=(.+)$'){$countryB=$matches[1]}}}
 if($c.Code -eq 0){$j=$c.Body | ConvertFrom-Json;$ipC=$j.ip;$countryC=$j.country}
 $direct=Probe 'direct-current-server' ('-q --verbose --noproxy * --connect-timeout 2 --max-time 3 https://'+$Upstream+':'+$UpstreamPort+'/')
 $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start();$altPort=$listener.LocalEndpoint.Port
 $alt=Probe 'alternate-local-proxy' ('-q --verbose --noproxy localhost --socks5-hostname 127.0.0.1:'+ $altPort+' --connect-timeout 2 --max-time 3 https://api.ipify.org')
 $altBlocked=(Blocked $alt) -and -not $listener.Pending()
 $g.Begin();$all=@($g.RestrictProgram($probe,'127.0.0.1',$faultPort,$true));$fault=@($all | Where-Object {$_ -notin $keys});$g.Commit()
 if($fault.Count -ne 1){throw 'Fault injection filter count mismatch'}
 $unavailable=Probe 'proxy-unavailable-for-test-exe' ('-q --verbose --noproxy localhost --socks5-hostname 127.0.0.1:'+$ProxyPort+' --connect-timeout 2 --max-time 3 https://api.ipify.org')
 $escape=Probe 'direct-during-proxy-fault' '-q --verbose --noproxy * --connect-timeout 2 --max-time 3 https://1.1.1.1/cdn-cgi/trace'
 $httpUnavailable=Probe 'http-connect-during-proxy-fault' ($httpCommon+'--verbose https://www.cloudflare.com/cdn-cgi/trace')
 foreach($k in $fault){$g.Delete($k)};$fault=@()
 $after=Probe 'ip-after-fault' ($common+'https://api.ipify.org?format=json')
 $afterIP='';if($after.Code -eq 0){$afterIP=($after.Body | ConvertFrom-Json).ip}
 $sameIP=($ipA -and $ipA -eq $ipB -and $ipA -eq $ipC -and $ipA -eq $afterIP)
 $negative=(Blocked $direct) -and $altBlocked -and (Blocked $unavailable) -and (Blocked $escape) -and (Blocked $httpUnavailable)
 $httpOK=[bool]($httpTrace.Code -eq 0 -and $httpIP -eq $ipA -and $httpCountry -eq $Country)
 $summary=[pscustomobject]@{OverallOK=[bool]($sameIP -and $countryB -eq $Country -and $countryC -eq $Country -and $negative -and $httpOK);HttpConnectOK=$httpOK;ExitIP=$ipA;ExitIPAfter=$afterIP;CountryCloudflare=$countryB;CountryIPinfo=$countryC;SameIP=[bool]$sameIP;NegativeChecksPassed=[bool]$negative;PersistentFilters=4;EngineReopened=$true;ClaudeLaunched=$false;ActualHappStopped=$false;Checks=$checks}
 $summary | ConvertTo-Json -Depth 8 | Set-Content "$OutputDirectory\experiment.json" -Encoding UTF8
 return $summary
}finally{
 if($g){foreach($k in $fault){$g.Delete($k)};foreach($k in $keys){$g.Delete($k)};$g.Dispose()}
 if($listener){$listener.Stop()}
 $checks | ConvertTo-Json -Depth 5 | Set-Content "$OutputDirectory\probe-checks.json" -Encoding UTF8
}
