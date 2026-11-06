#requires -Version 5.1
# Synthetic fixtures only; no UAC, adapters changed, firewall writes or Claude launch.
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\Common.ps1"
function New-FixtureNic([string]$name,[string]$status,[string]$description) {
 return [pscustomobject]@{Name=$name;Status=$status;InterfaceDescription=$description}
}
$config=[pscustomobject]@{BlockedInterfaces=@('FlClashX')}
$snow=@((New-FixtureNic 'FlClashX' 'Disconnected' 'Meta Tunnel'),(New-FixtureNic 'SnowVPN Tun V2' 'Up' 'Meta Tunnel'),(New-FixtureNic 'Wintun' 'Disconnected' 'Wintun'))
$result=Resolve-GuardBlockedInterfaces $config $snow
if($result.SelectedTun -ne 'SnowVPN Tun V2' -or (@($result.Aliases)-join ',') -ne 'SnowVPN Tun V2'){throw 'SnowVPN selection failed'}
$fl=@((New-FixtureNic 'FlClashX' 'Up' 'Meta Tunnel'),(New-FixtureNic 'SnowVPN Tun V2' 'Disconnected' 'Meta Tunnel'))
$result=Resolve-GuardBlockedInterfaces $config $fl
if($result.SelectedTun -ne 'FlClashX' -or (@($result.Aliases)-join ',') -ne 'FlClashX'){throw 'FlClashX selection failed'}
$unsafeCases=@(
 [pscustomobject]@{Nics=@((New-FixtureNic 'FlClashX' 'Up' 'Meta Tunnel'),(New-FixtureNic 'SnowVPN Tun V2' 'Up' 'Meta Tunnel'))},
 [pscustomobject]@{Nics=@((New-FixtureNic 'FlClashX' 'Disconnected' 'Meta Tunnel'),(New-FixtureNic 'SnowVPN Tun V2' 'Disconnected' 'Meta Tunnel'))},
 [pscustomobject]@{Nics=@((New-FixtureNic 'Unknown VPN' 'Up' 'Meta Tunnel'),(New-FixtureNic 'SnowVPN Tun V2' 'Up' 'Meta Tunnel'))},
 [pscustomobject]@{Nics=@((New-FixtureNic 'SnowVPN Tun V2' 'Up' 'Other Driver'))}
)
foreach($case in $unsafeCases){
 $rejected=$false
 try{$null=Resolve-GuardBlockedInterfaces $config $case.Nics}catch{$rejected=$true}
 if(-not $rejected){throw 'Unsafe active tunnel configuration accepted'}
}
$config.BlockedInterfaces=@('FlClashX','Radmin VPN')
$result=Resolve-GuardBlockedInterfaces $config @((New-FixtureNic 'SnowVPN Tun V3' 'Up' 'Meta Tunnel'),(New-FixtureNic 'Radmin VPN' 'Up' 'Famatech VPN'))
if((@($result.Aliases | Sort-Object)-join ',') -ne 'Radmin VPN,SnowVPN Tun V3'){throw 'Additional configured interface was lost'}
$config.BlockedInterfaces=@()
$result=Resolve-GuardBlockedInterfaces $config @()
if(@($result.Aliases).Count -ne 0 -or $result.Automatic){throw 'Empty blocked interface list changed semantics'}
'PASS: SnowVPN/FlClashX choice, extra blocks, ambiguity and unknown Meta Tunnel rejected; no runtime changes.'
