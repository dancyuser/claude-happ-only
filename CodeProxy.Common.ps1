#requires -Version 5.1
function Get-CodeProxyEnvironment([int]$Port) {
 if($Port -lt 1 -or $Port -gt 65535){throw 'Invalid proxy port'}
 $url='http://127.0.0.1:'+$Port
 return [ordered]@{HTTP_PROXY=$url;HTTPS_PROXY=$url;ALL_PROXY=$url;NO_PROXY=''}
}
function ConvertTo-CodeProxySettings([string]$Text,[int]$Port) {
 $settings=if([string]::IsNullOrWhiteSpace($Text)){[pscustomobject]@{}}else{ConvertFrom-Json -InputObject $Text}
 if($null -eq $settings -or $settings.GetType() -ne [Management.Automation.PSCustomObject]){throw 'Settings must be a JSON object'}
 if(-not $settings.PSObject.Properties['env']){$settings | Add-Member NoteProperty env ([pscustomobject]@{})}
 if($null -eq $settings.env -or $settings.env.GetType() -ne [Management.Automation.PSCustomObject]){throw 'settings.env must be a JSON object'}
 $expected=Get-CodeProxyEnvironment $Port
 foreach($key in $expected.Keys){
  # Canonicalize case: lower-case HTTPS proxy has higher priority in Claude Code.
  foreach($name in @($settings.env.PSObject.Properties.Name | Where-Object {$_ -ieq $key})){$settings.env.PSObject.Properties.Remove($name)}
  $settings.env | Add-Member NoteProperty $key $expected[$key]
 }
 return ($settings | ConvertTo-Json -Depth 100)
}
function Test-CodeProxySettings([string]$Text,[int]$Port) {
 if([string]::IsNullOrWhiteSpace($Text)){return $false}
 $settings=ConvertFrom-Json -InputObject $Text
 if($null -eq $settings -or $null -eq $settings.env -or $settings.env.GetType() -ne [Management.Automation.PSCustomObject]){return $false}
 $expected=Get-CodeProxyEnvironment $Port
 foreach($key in $expected.Keys){
  $property=@($settings.env.PSObject.Properties | Where-Object {$_.Name -ieq $key})
  if($property.Count -ne 1 -or $property[0].Name -cne $key -or $property[0].Value -isnot [string] -or $property[0].Value -cne $expected[$key]){return $false}
 }
 return $true
}
function Assert-CodeProxyPlainPath([string]$Path) {
 $item=[IO.Path]::GetFullPath($Path)
 while($item){
  if(Test-Path -LiteralPath $item){if((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in settings/backup path'}}
  $parent=Split-Path $item -Parent;if($parent -eq $item){break};$item=$parent
 }
}
function Invoke-CodeProxyCurl([int]$Port,[string]$Url) {
 $si=New-Object Diagnostics.ProcessStartInfo
 $si.FileName=Join-Path $env:SystemRoot 'System32\curl.exe'
 # Only constant HTTPS test URLs supplied by this kit are accepted.
 if($Url -notin @('https://www.cloudflare.com/cdn-cgi/trace','https://api.ipify.org')){throw 'Unsupported diagnostic URL'}
 $si.Arguments='-q --silent --show-error --fail --ipv4 --proxy http://127.0.0.1:'+$Port+' --noproxy invalid.invalid --connect-timeout 5 --max-time 12 '+$Url
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 foreach($key in @($si.EnvironmentVariables.Keys | Where-Object {$_ -match '^(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)$'})){$si.EnvironmentVariables.Remove($key)}
 $process=New-Object Diagnostics.Process;$process.StartInfo=$si
 try{
  $null=$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(15000)){$process.Kill();$process.WaitForExit();throw 'HTTP proxy test timed out'}
  return [pscustomobject]@{Code=$process.ExitCode;Body=$stdout.Result.Trim();Error=$stderr.Result.Trim()}
 }finally{$process.Dispose()}
}
function Test-CodeProxyTransport([int]$Port,[string]$Country) {
 $trace=Invoke-CodeProxyCurl $Port 'https://www.cloudflare.com/cdn-cgi/trace'
 $ip=Invoke-CodeProxyCurl $Port 'https://api.ipify.org'
 $traceIP='';$location=''
 if($trace.Code -eq 0){foreach($line in ($trace.Body -split '\r?\n')){if($line -match '^ip=(.+)$'){$traceIP=$matches[1]};if($line -match '^loc=(.+)$'){$location=$matches[1]}}}
 return [pscustomobject]@{OK=[bool]($trace.Code -eq 0 -and $ip.Code -eq 0 -and $traceIP -and $traceIP -eq $ip.Body -and $location -eq $Country);ExitIP=$traceIP;Country=$location;CloudflareCode=$trace.Code;IpifyCode=$ip.Code;Errors=@($trace.Error,$ip.Error)}
}
