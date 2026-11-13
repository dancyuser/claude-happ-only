#requires -Version 5.1
# User-requested parameter change; backup and UAC handled by Setup/Manage-Happ.
[CmdletBinding()]param([string]$Server,[string]$PhysicalInterface,[string[]]$PhysicalInterfaces,[ValidatePattern('^[A-Za-z]{2}$')][string]$ExpectedCountry,[switch]$Preview)
$ErrorActionPreference='Stop';$temp=$null;$code=1
try{
 . "$PSScriptRoot\Common.ps1"
 if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run Reconfigure as the ordinary target user; UAC is requested separately'}
 $c=Read-GuardConfig (Join-Path (Get-GuardRoot) 'config.json')
 if(-not $Server -and -not $PhysicalInterface -and -not $PhysicalInterfaces -and -not $ExpectedCountry){throw 'Specify Server, PhysicalInterface, PhysicalInterfaces (ordered failover), and/or ExpectedCountry. Add Preview for no-change validation.'}
 if($PhysicalInterface -and $PhysicalInterfaces){throw 'Choose single PhysicalInterface or ordered PhysicalInterfaces, not both'}
 if($Server){
  $ip=$null
  if([Net.IPAddress]::TryParse($Server,[ref]$ip)){$c.EndpointMode='PinnedIPv4';$c.UpstreamHostname='';$c.UpstreamAddress=$ip.ToString()}
  else{$c.EndpointMode='Hostname';$c.UpstreamHostname=$Server}
 }
 if($PhysicalInterface){$c.PhysicalInterface=$PhysicalInterface;$c.PhysicalUplinks=@()}
 if($PhysicalInterfaces){
  $entries=@();$index=0
  foreach($name in $PhysicalInterfaces){
   $nic=@(Get-NetAdapter -Name $name -ErrorAction Stop);if($nic.Count -ne 1 -or -not $nic[0].HardwareInterface){throw 'Select exact physical adapters only'}
   $net=Get-NetIPConfiguration -InterfaceIndex $nic[0].ifIndex;$gateway=@($net.IPv4DefaultGateway.NextHop)
   if($gateway.Count -ne 1){throw 'Connect each physical uplink once so its IPv4 gateway can be recorded'}
   $entries+=@([pscustomobject]@{InterfaceGuid=([guid]$nic[0].InterfaceGuid).ToString();Gateway=[string]$gateway[0];RouteMetric=(1+1000*$index)});$index++
  }
  $c.PhysicalUplinks=$entries;$c.PhysicalInterface=$PhysicalInterfaces[0];$c|Add-Member NoteProperty Gateway $entries[0].Gateway -Force
 }
 if($ExpectedCountry){$c.ExpectedCountry=$ExpectedCountry.ToUpperInvariant()}
 if(-not $Preview){Assert-NoClaudeClient}
 $temp=Join-Path $env:TEMP ('ClaudeHapp-Reconfigure-'+[guid]::NewGuid().ToString('N')+'.json')
 $c | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temp -Encoding UTF8
 if($Preview){& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Setup.ps1" -ConfigurationFile $temp -Preview}
 else{& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Setup.ps1" -ConfigurationFile $temp}
 $code=$LASTEXITCODE
}catch{Write-Host ('RECONFIGURE FAILED: '+$_.Exception.Message) -ForegroundColor Red;$code=1}
finally{if($temp -and (Test-Path -LiteralPath $temp)){try{Remove-Item -LiteralPath $temp -Force}catch{Write-Warning ('Temporary configuration retained: '+$temp)}}}
exit $code
