#requires -Version 5.1
# Pure policy fixtures + ABI compilation. Does not open WFP or launch applications.
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent;. "$root\Universal.Common.ps1"
if(-not ('UniversalWfp' -as [type])){Add-Type -Path "$root\Universal.Wfp.cs"}
$id=[guid]::NewGuid().ToString();$tun=[guid]::NewGuid().ToString();$physical=[guid]::NewGuid().ToString()
$app=Join-Path $env:TEMP 'arbitrary-client.exe';$core=Join-Path $env:TEMP 'unrelated-core.exe';$probe=Join-Path $env:TEMP 'private-probe.exe'
$base=[pscustomobject]@{Schema=1;ProfileId=$id;Name='Fixture';Mode='TunOnly';Programs=@($app);TunnelInterfaceGuid=$tun;AllowIPv6=$false;KillSwitchScope='InterfaceOnly'}
$c=ConvertTo-UniversalProfile $base
$a=[pscustomobject]@{Name='Arbitrary adapter name';InterfaceGuid=$tun;Status='Up';HardwareInterface=$false;ifIndex=19}
$binding=Resolve-UniversalBinding $c @($a);$binding.Luid='123456'
if(-not $binding.Up -or $binding.Guid -ne $tun){throw 'GUID binding failed'}
$a.Name='Renamed - any language';$a.ifIndex=200
if((Resolve-UniversalBinding $c @($a)).Guid -ne $tun){throw 'Rename/index change broke GUID binding'}
$plan=@(New-UniversalPlan $c $binding $probe)
if($plan.Count -ne 2 -or @($plan|Where-Object {$_.Kind -ne 'Interface' -or $_.Luid -ne '123456' -or $_.IPv6}).Count){throw 'TunOnly policy permits a non-selected interface or IPv6'}
$missing=Resolve-UniversalBinding $c @([pscustomobject]@{Name=$a.Name;InterfaceGuid=$physical;Status='Up';HardwareInterface=$false;ifIndex=200})
$blocked=@(New-UniversalPlan $c $missing $probe)
if($missing.Present -or @($blocked|Where-Object Kind -ne 'Block').Count){throw 'Missing TUN fell back by name or allowed access'}
$strict=$c|ConvertTo-Json -Depth 12|ConvertFrom-Json;$strict.KillSwitchScope='InterfaceAndCore'
$strict|Add-Member NoteProperty VpnCore ([pscustomobject]@{Executable=$core;ServerAddress='192.0.2.1';ServerPort=51820;ServerProtocol='UDP'})
$strict=ConvertTo-UniversalProfile $strict;$strictPlan=@(New-UniversalPlan $strict $binding $probe)
if(-not @($strictPlan|Where-Object {$_.Path -eq $core -and $_.Kind -eq 'Endpoint' -and $_.Address -eq '192.0.2.1' -and $_.Protocol -eq 17}).Count){throw 'Strict VPN core can fall back to arbitrary destinations'}
$noCore=$strict|ConvertTo-Json -Depth 12|ConvertFrom-Json;$noCore.PSObject.Properties.Remove('VpnCore');$rejected=$false;try{$null=ConvertTo-UniversalProfile $noCore}catch{$rejected=$true};if(-not $rejected){throw 'Strict scope silently weakened without VPN core'}
$noScope=$base|ConvertTo-Json -Depth 12|ConvertFrom-Json;$noScope.PSObject.Properties.Remove('KillSwitchScope');$rejected=$false;try{$null=ConvertTo-UniversalProfile $noScope}catch{$rejected=$true};if(-not $rejected){throw 'Missing scope silently selected weaker kill switch'}
$refused=$false;try{$a.HardwareInterface=$true;$null=Resolve-UniversalBinding $c @($a)}catch{$refused=$true};if(-not $refused){throw 'Physical adapter accepted as TUN'};$a.HardwareInterface=$false
$refused=$false;try{$null=Resolve-UniversalBinding $c @($a,$a)}catch{$refused=$true};if(-not $refused){throw 'Ambiguous identity accepted'}
$p=[pscustomobject]@{Schema=1;ProfileId=$id;Name='Proxy fixture';Mode='TunProxy';Programs=@($app);TransportInterfaceGuid=$physical;Proxy=[pscustomobject]@{Address='127.0.0.1';Port=23456;Scheme='socks5h';Executable=$core;ServerAddress='2001:db8::1';ServerPort=8443;ServerProtocol='UDP'}}
$p=ConvertTo-UniversalProfile $p
$b=[pscustomobject]@{Present=$true;Up=$true;Luid='789';Guid=$physical}
$plan=@(New-UniversalPlan $p $b $probe)
$client=@($plan|Where-Object Path -in @($app,$probe));$owner=@($plan|Where-Object Path -eq $core)
if($client.Count -ne 2 -or @($client|Where-Object {$_.Kind -ne 'Endpoint' -or $_.Address -ne '127.0.0.1' -or $_.Port -ne 23456 -or $_.Protocol -ne 6}).Count){throw 'Client can bypass local proxy'}
if($owner.Count -ne 3 -or -not @($owner|Where-Object {$_.Kind -eq 'Endpoint' -and $_.Protocol -eq 17 -and $_.Address -eq '2001:db8::1'}).Count -or -not @($owner|Where-Object {$_.Kind -eq 'Interface' -and $_.Luid -eq '789'}).Count){throw 'Proxy owner upstream or adapter restriction missing'}
$badValues=@(
 @{Field='Mode';Value='Guess'},@{Field='Programs';Value=@('C:\*.exe')},@{Field='ProfileId';Value='not-a-guid'}
)
foreach($bad in $badValues){$copy=$p|ConvertTo-Json -Depth 12|ConvertFrom-Json;$copy.($bad.Field)=$bad.Value;$rejected=$false;try{$null=ConvertTo-UniversalProfile $copy}catch{$rejected=$true};if(-not $rejected){throw ('Invalid field accepted: '+$bad.Field)}}
$copy=$p|ConvertTo-Json -Depth 12|ConvertFrom-Json;$copy.Programs=@($core);$rejected=$false;try{$null=ConvertTo-UniversalProfile $copy}catch{$rejected=$true};if(-not $rejected){throw 'Proxy core accepted as client'}
$copy=$p|ConvertTo-Json -Depth 12|ConvertFrom-Json;$copy.Proxy.ServerAddress='example.org';$rejected=$false;try{$null=ConvertTo-UniversalProfile $copy}catch{$rejected=$true};if(-not $rejected){throw 'Unpinned hostname accepted'}
$size=[Runtime.InteropServices.Marshal].GetMethod('SizeOf',[type[]]@([type])).Invoke($null,@([UniversalWfp+Condition]))
if($size -ne 40){throw 'Unexpected WFP condition ABI'}
'PASS: universal TUN/proxy plans, GUID rename/index resilience, missing-interface quarantine, ambiguity/physical-TUN rejection, custom ports/upstreams and unsafe input rejection. No OS mutation or target launch.'
