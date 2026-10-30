#requires -Version 5.1
function Complete-SetupConfiguration($InputConfiguration,$Defaults){
 if($null -eq $InputConfiguration -or ($InputConfiguration -isnot [Collections.IDictionary] -and $InputConfiguration.GetType() -ne [Management.Automation.PSCustomObject])){throw 'Configuration must be a JSON object'}
 $result=[ordered]@{}
 if($InputConfiguration -is [Collections.IDictionary]){foreach($key in $InputConfiguration.Keys){$result[$key]=$InputConfiguration[$key]}}
 else{foreach($property in $InputConfiguration.PSObject.Properties){$result[$property.Name]=$property.Value}}
 foreach($key in $Defaults.Keys){if(-not $result.Contains($key) -or $null -eq $result[$key] -or ($result[$key] -is [string] -and [string]::IsNullOrWhiteSpace($result[$key]))){$result[$key]=$Defaults[$key]}}
 if($result.LaunchUserSid -ne $Defaults.LaunchUserSid){throw 'Configuration belongs to a different user; omit LaunchUserSid for this machine'}
 if(-not $result.CodeRoot){$result.CodeRoot=Join-Path $Defaults.CodeDataRoot ($result.PackageFamily+'\claude-code')}
 $result.Remove('CodeDataRoot')
 return [pscustomobject]$result
}
function Get-SetupNetworkChoices {
 $adapters=@(Get-NetAdapter -ErrorAction Stop)
 foreach($adapter in $adapters){
  if($adapter.HardwareInterface -and $adapter.Status -eq 'Up'){
   $net=Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction Stop
   $addresses=@($net.IPv4Address.IPAddress | Where-Object {$_ -notlike '169.254.*'})
   $gateways=@($net.IPv4DefaultGateway.NextHop)
   if($addresses.Count -eq 1 -and $gateways.Count -eq 1){[pscustomobject]@{Name=$adapter.Name;IPv4=$addresses[0];Gateway=$gateways[0]}}
  }
 }
}
