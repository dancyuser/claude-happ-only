#requires -Version 5.1
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\Common.ps1";. "$PSScriptRoot\..\Setup.Common.ps1"
foreach($address in @('1.1.1.1','8.8.8.8')){if(-not(Test-GuardPublicIPv4 $address)){throw 'Public address rejected'}}
foreach($address in @('127.0.0.1','127.1','10.1.2.3','172.16.0.1','192.168.1.1','100.64.0.1','198.18.0.1','169.254.1.1','224.0.0.1','0.0.0.0','::1','01.1.1.1','203.0.113.1','example.com','1.1.1.1:443')){if(Test-GuardPublicIPv4 $address){throw ('Non-public/noncanonical endpoint accepted: '+$address)}}
$defaults=[ordered]@{Schema=3;EndpointMode='Hostname';UpstreamPort=443;ProxyPort=10808;LaunchUserSid='test-user';ShortcutPath='C:\Users\TEST\Desktop\Claude.lnk';PackageFamily='TEST_family';CodeRoot='';CodeDataRoot='C:\Users\TEST\AppData\Local\Claude-Data';UseLegacyTag=$false}
$inputConfig=[pscustomobject]@{UpstreamHostname='server.example.com';ProxyPort=12345;BlockedInterfaces=@('Virtual test');CodeRoot=''}
$completed=Complete-SetupConfiguration $inputConfig $defaults
if($completed.ProxyPort -ne 12345 -or $completed.UpstreamPort -ne 443 -or $completed.LaunchUserSid -ne 'test-user' -or $completed.CodeRoot -ne 'C:\Users\TEST\AppData\Local\Claude-Data\TEST_family\claude-code' -or $completed.BlockedInterfaces[0] -ne 'Virtual test'){throw 'Machine-local defaults or explicit values lost'}
if($completed.PSObject.Properties['CodeDataRoot']){throw 'Internal default leaked into config'}
$rejected=$false;try{$null=Complete-SetupConfiguration ([pscustomobject]@{LaunchUserSid='other-user'}) $defaults}catch{$rejected=$true}
if(-not $rejected){throw 'Cross-user configuration accepted'}
foreach($bad in @('scalar',123,@())){$rejected=$false;try{$null=Complete-SetupConfiguration $bad $defaults}catch{$rejected=$true};if(-not $rejected){throw 'Non-object setup input accepted'}}
$fixture=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ('Happ-Config-Fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$core=Join-Path $fixture 'xray.exe';[IO.File]::WriteAllText($core,'NONEXECUTABLE CONFIG FIXTURE')
$config=[pscustomobject]@{PhysicalInterface='Fixture Ethernet';UpstreamHostname='server.example.com';XrayPath=$core;ShortcutPath=(Join-Path $fixture 'Claude.lnk');LaunchUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;ProxyPort=12345}
$path=Join-Path $fixture 'input.json';$config | ConvertTo-Json | Set-Content $path -Encoding UTF8
$legacy=Read-GuardConfig $path
if($legacy.EndpointMode -ne 'Hostname' -or $legacy.ProxyPort -ne 12345){throw 'Legacy config compatibility failed'}
$config | Add-Member NoteProperty EndpointMode 'PinnedIPv4';$config | Add-Member NoteProperty UpstreamAddress '1.1.1.1';$config.UpstreamHostname=''
$config | ConvertTo-Json | Set-Content $path -Encoding UTF8
if((Read-GuardConfig $path).EndpointMode -ne 'PinnedIPv4'){throw 'Explicit IP config failed'}
$config.UpstreamAddress='127.0.0.1';$config | ConvertTo-Json | Set-Content $path -Encoding UTF8
$rejected=$false;try{$null=Read-GuardConfig $path}catch{$rejected=$true};if(-not $rejected){throw 'Pinned loopback endpoint accepted'}
'PASS: public IPv4 validation, machine-local defaults, custom ports and cross-user rejection; no network or system changes.'
