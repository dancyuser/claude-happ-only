# Isolated route restore fixtures: execute the production restore route block only.
$ErrorActionPreference='Stop'
$a=[guid]::NewGuid().ToString();$b=[guid]::NewGuid().ToString();$target=[pscustomobject]@{UpstreamAddress='192.0.2.1'}
$beforeRoutes=@(foreach($id in @($a,$b)){foreach($store in @('ActiveStore','PersistentStore')){[pscustomobject]@{Prefix='192.0.2.1/32';InterfaceGuid=$id;Store=$store;NextHop='192.168.1.1';Metric=$(if($id -eq $a){1}else{1001})}}})
$script:fixture=@{ActiveStore=@([pscustomobject]@{InterfaceIndex=19;NextHop='192.168.1.1';RouteMetric=1});PersistentStore=@()}
function Get-NetAdapter {param([switch]$IncludeHidden);@([pscustomobject]@{InterfaceGuid="{$a}";ifIndex=19},[pscustomobject]@{InterfaceGuid="{$b}";ifIndex=24})}
function Get-NetRoute {param($DestinationPrefix,$PolicyStore,$ErrorAction);@($script:fixture[$PolicyStore])|ForEach-Object {$_|Add-Member NoteProperty FixtureStore $PolicyStore -Force;$_}}
function New-NetRoute {param($DestinationPrefix,$InterfaceIndex,$NextHop,$RouteMetric,$PolicyStore)
 if($PolicyStore -eq 'PersistentStore'){throw 'Invalid creation store'}
 foreach($store in $(if($PolicyStore){@($PolicyStore)}else{@('ActiveStore','PersistentStore')})){$script:fixture[$store]+=@([pscustomobject]@{InterfaceIndex=$InterfaceIndex;NextHop=$NextHop;RouteMetric=$RouteMetric})}
}
function Remove-NetRoute {param([Parameter(ValueFromPipeline)]$InputObject,[switch]$Confirm);process{$script:fixture[$InputObject.FixtureStore]=@($script:fixture[$InputObject.FixtureStore]|Where-Object {$_ -ne $InputObject})}}
function Set-NetRoute {param([Parameter(ValueFromPipeline)]$InputObject,$RouteMetric,[switch]$Confirm);process{$InputObject.RouteMetric=$RouteMetric}}
$s=Get-Content "$PSScriptRoot\..\Restore-Guard.ps1" -Raw;$start=$s.IndexOf(' $routeAdapters=@(');$end=$s.IndexOf(' foreach($file in $meta.Files)', $start)
if($start -lt 0 -or $end -le $start){throw 'Restore fixture production block missing'}
& ([scriptblock]::Create($s.Substring($start,$end-$start)))
foreach($store in @('ActiveStore','PersistentStore')){if($script:fixture[$store].Count -ne 2 -or @($script:fixture[$store]|Where-Object {$_.InterfaceIndex -eq 24 -and $_.RouteMetric -eq 1001}).Count -ne 1){throw 'Two-uplink restore failed'}}
'PASS: missing persistent and active routes restored for two physical GUIDs, including braced GUIDs; NetTCPIP mocked.'
