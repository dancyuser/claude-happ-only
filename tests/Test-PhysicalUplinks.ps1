#requires -Version 5.1
# Pure fixtures and fake route stores; no adapter/route changes or target launch.
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\Common.ps1"
$a=[guid]::NewGuid().ToString();$b=[guid]::NewGuid().ToString()
$c=[pscustomobject]@{PhysicalUplinks=@([pscustomobject]@{InterfaceGuid=$a;Gateway='192.168.1.1';RouteMetric=1},[pscustomobject]@{InterfaceGuid=$b;Gateway='192.168.1.1';RouteMetric=1001})}
$nics=@([pscustomobject]@{InterfaceGuid=$a;Name='Any wired name';Status='Up';HardwareInterface=$true;ifIndex=19},[pscustomobject]@{InterfaceGuid=$b;Name='Any wireless name';Status='Up';HardwareInterface=$true;ifIndex=24})
$rows=@(Resolve-GuardPhysicalUplinks $c $nics)
if($rows.Count -ne 2 -or (@($rows|Where-Object Up)[0].InterfaceGuid -ne $a)){throw 'Wrong primary'}
$nics[0].Status='Disconnected';$rows=@(Resolve-GuardPhysicalUplinks $c $nics)
if(@($rows|Where-Object Up)[0].InterfaceGuid -ne $b){throw 'Cable loss did not select approved backup'}
$nics[1].Name='Renamed Wi-Fi';if((@(Resolve-GuardPhysicalUplinks $c $nics))[1].Name -ne 'Renamed Wi-Fi'){throw 'Name was used instead of GUID'}
$script:fixtureRoutes=@([pscustomobject]@{InterfaceIndex=19;NextHop='192.168.1.1';RouteMetric=1},[pscustomobject]@{InterfaceIndex=24;NextHop='192.168.1.1';RouteMetric=1001})
function Get-NetRoute {param($DestinationPrefix,$PolicyStore,$ErrorAction);return $script:fixtureRoutes}
Assert-GuardUplinkRoutes $c '192.0.2.1' $rows
$nics[1].Status='Disconnected';$down=@(Resolve-GuardPhysicalUplinks $c $nics)
$bad=$false;try{Assert-GuardUplinkRoutes $c '192.0.2.1' $down}catch{$bad=$true};if(-not $bad){throw 'Both down accepted'}
$script:fixtureRoutes+=@([pscustomobject]@{InterfaceIndex=50;NextHop='198.18.0.1';RouteMetric=1})
$bad=$false;try{Assert-GuardUplinkRoutes $c '192.0.2.1' $rows}catch{$bad=$true};if(-not $bad){throw 'Foreign exact route accepted'}
$nics[1].HardwareInterface=$false;$bad=$false;try{$null=Resolve-GuardPhysicalUplinks $c $nics}catch{$bad=$true};if(-not $bad){throw 'Virtual interface selected as backup'}
$c.PhysicalUplinks[1].InterfaceGuid=$a;$bad=$false;try{$null=Resolve-GuardPhysicalUplinks $c $nics}catch{$bad=$true};if(-not $bad){throw 'Duplicate identity accepted'}
$script:stores=@{ActiveStore=@([pscustomobject]@{InterfaceIndex=19;NextHop='192.168.1.1';RouteMetric=1});PersistentStore=@([pscustomobject]@{InterfaceIndex=19;NextHop='192.168.1.1';RouteMetric=1})};$script:intents=@();$script:created=0
function Get-NetRoute {param($DestinationPrefix,$PolicyStore,$ErrorAction);return @($script:stores[$PolicyStore])}
function Add-RouteIntent {param($Backup,$Prefix,$Index,$Hop,$Store,$Metric);$script:intents+=@($Store)}
function New-NetRoute {param($DestinationPrefix,$InterfaceIndex,$NextHop,$RouteMetric,$PolicyStore,$ErrorAction)
 if($PolicyStore -eq 'PersistentStore'){throw 'Invalid parameter PolicyStore PersistentStore'}
 $r=[pscustomobject]@{InterfaceIndex=$InterfaceIndex;NextHop=$NextHop;RouteMetric=$RouteMetric};$script:created++
 if($PolicyStore -eq 'ActiveStore'){$script:stores.ActiveStore+=@($r)}else{$script:stores.ActiveStore+=@($r);$script:stores.PersistentStore+=@($r)}
}
Ensure-GuardUplinkRoutes $null '192.0.2.1' $rows 'fixture'
if($script:created -ne 1 -or $script:intents.Count -ne 2){throw 'Backup route was not created atomically in both stores'}
Ensure-GuardUplinkRoutes $null '192.0.2.1' $rows 'fixture';if($script:created -ne 1){throw 'Route setup is not idempotent'}
'PASS: wired-first and Wi-Fi fallback, renamed GUID binding, both-down/virtual/foreign-route refusal. All OS operations mocked.'

$nics[0].InterfaceGuid="{"+$a+"}";$nics[0].HardwareInterface=$true;$c.PhysicalUplinks[1].InterfaceGuid=$b;$nics[1].HardwareInterface=$true;$null=Resolve-GuardPhysicalUplinks $c $nics
