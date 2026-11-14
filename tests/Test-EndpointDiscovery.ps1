#requires -Version 5.1
# Mocked discovery and prompts: no network requests, UAC or policy changes.
& {
 $ErrorActionPreference='Stop';. "$PSScriptRoot\..\Universal.Common.ps1"
 $core='C:\VPN\core.exe'
 $processes=@(
  [pscustomobject]@{ProcessId=10;Name='core.exe';ExecutablePath=$core},
  [pscustomobject]@{ProcessId=11;Name='core.exe';ExecutablePath='C:\Other\core.exe'},
  [pscustomobject]@{ProcessId=12;Name='core.exe';ExecutablePath=$null},
  [pscustomobject]@{ProcessId=13;Name='browser.exe';ExecutablePath=$null}
 )
 function Connection($owner,$address,$local='192.168.1.7',$state='Established'){
  [pscustomobject]@{OwningProcess=$owner;RemoteAddress=$address;RemotePort=443;LocalAddress=$local;State=$state}
 }
 $connections=@((Connection 10 '8.8.8.8'),(Connection 10 '8.8.8.8'),(Connection 11 '1.1.1.1'),(Connection 12 '9.9.9.9'),(Connection 13 '4.2.2.2'),(Connection 10 '127.0.0.1'),(Connection 10 '::1'),(Connection 10 '0.0.0.0'),(Connection 10 '224.0.0.1'),(Connection 10 '1.0.0.1' '172.19.0.1' 'SynSent'),(Connection 10 '2606:4700:4700::1111' '2001:db8::10'))
 $addresses=@([pscustomobject]@{IPAddress='192.168.1.7';InterfaceIndex=14},[pscustomobject]@{IPAddress='2001:db8::10';InterfaceIndex=14})
 $adapters=@([pscustomobject]@{ifIndex=14;Name='Wi-Fi renamed'})
 $rows=@(ConvertTo-UniversalEndpointCandidates $core $processes $connections $addresses $adapters)
 if($rows.Count -ne 3){throw 'Wrong owners, states, duplicate or local endpoints included'}
 if(@($rows|Where-Object {$_.ServerAddress -eq '8.8.8.8' -and $_.PathVerified -and $_.Interface -eq 'Wi-Fi renamed (#14)' -and $_.ServerProtocol -eq 'TCP'}).Count -ne 1){throw 'Verified endpoint/interface mapping lost'}
 if(@($rows|Where-Object {$_.ServerAddress -eq '9.9.9.9' -and -not $_.PathVerified}).Count -ne 1){throw 'Inaccessible process path silently trusted'}
 if(@(ConvertTo-UniversalEndpointCandidates $core @() $connections $addresses $adapters).Count){throw 'No matching process should produce no candidates'}
 function Invoke-UniversalCurl { [pscustomobject]@{Code=0;Body=$script:body} }
 $script:body='{"success":true,"ip":"8.8.8.8","country":"United States","country_code":"US"}'
 if((Get-UniversalAddressCountry '8.8.8.8').Code -ne 'US'){throw 'Country response rejected'}
 $script:body='{"success":true,"ip":"1.1.1.1","country":"Wrong","country_code":"US"}'
 if((Get-UniversalAddressCountry '8.8.8.8').Code){throw 'Country for a different address accepted'}
 $script:body='invalid JSON'
 if((Get-UniversalAddressCountry '8.8.8.8').Code -or (Get-UniversalAddressCountry '192.168.1.7').Code){throw 'Lookup failure/private address should show unknown'}
 function Get-UniversalAddressCountry { [pscustomobject]@{Name='Fixture country';Code='ZZ'} }
 function Get-UniversalEndpointCandidates { $script:fixtures }
 function Get-NetAdapter { @() }
 function Find-NetRoute { throw 'No route fixture' }
 function Read-Host { if(-not $script:answers.Count){throw 'Unexpected prompt'}; $script:answers.Dequeue() }
 $script:fixtures=@($rows|Where-Object ServerAddress -eq '8.8.8.8')
 $script:answers=New-Object 'Collections.Generic.Queue[string]';$script:answers.Enqueue('');$script:answers.Enqueue('yes')
 $result=Read-UniversalVpnEndpoint $core ([guid]::NewGuid().ToString())
 if($result.ServerAddress -ne '8.8.8.8' -or $result.ServerPort -ne 443 -or $result.ServerProtocol -ne 'TCP' -or $script:answers.Count){throw 'Approved discovery not transferred to configuration'}
 $script:answers.Enqueue('');$script:answers.Enqueue('')
 $rejected=$false;try{$null=Read-UniversalVpnEndpoint $core 'test'}catch{$rejected=$true}
 if(-not $rejected){throw 'Blank approval accepted'}
 $script:fixtures=@();foreach($answer in @('2001:db8::1','51820','UDP','y')){$script:answers.Enqueue($answer)}
 $result=Read-UniversalVpnEndpoint $core 'test'
 if($result.ServerAddress -ne '2001:db8::1' -or $result.ServerPort -ne 51820 -or $result.ServerProtocol -ne 'UDP'){throw 'Manual UDP/IPv6 fallback failed'}
 $script:fixtures=@($rows);$script:answers.Enqueue('Q')
 $rejected=$false;try{$null=Read-UniversalVpnEndpoint $core 'test'}catch{$rejected=$true}
 if(-not $rejected){throw 'Ambiguous endpoint cancellation ignored'}
 'PASS: endpoint ownership, IPv4/IPv6, interface mapping, country failure, confirmation/cancel and UDP manual fallback.'
}
