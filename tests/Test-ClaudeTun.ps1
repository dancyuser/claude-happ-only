#requires -Version 5.1
& {
 $ErrorActionPreference='Stop';. "$PSScriptRoot\..\Universal.Common.ps1"
 $id=[guid]::NewGuid();$tun=[guid]::NewGuid();$programs=@('C:\Fixture\A-helper.exe','C:\Fixture\app\claude.exe','C:\Fixture\z-cli\claude.exe');$desktop=$programs[1]
 $profile=New-ClaudeTunProfile $programs $tun 'fixture-sid' $id $desktop
 if($profile.Mode -ne 'TunOnly' -or $profile.KillSwitchScope -ne 'InterfaceOnly' -or $profile.AllowIPv6 -or $profile.ProfileId -ne $id.ToString() -or $profile.TunnelInterfaceGuid -ne $tun.ToString() -or $profile.Programs.Count -ne 3 -or $profile.DesktopExecutable -ine $desktop -or $profile.PSObject.Properties['VpnCore']){throw 'Claude preset needs a server or changed interface scope'}
 $binding=[pscustomobject]@{Present=$true;Up=$true;Luid='12345'}
 $plan=@(New-UniversalPlan $profile $binding 'C:\Fixture\probe.exe')
 if($plan.Count -ne 4 -or @($plan|Where-Object {$_.Kind -ne 'Interface' -or $_.IPv6}).Count){throw 'Claude preset allows an endpoint/proxy/IPv6 bypass'}
 $launch=@(Get-UniversalLaunchArguments $profile $desktop @('--fixture=value'))
 if(($launch -join '|') -ne '--fixture=value|--no-proxy-server'){throw 'Claude Desktop still inherits the system loopback proxy'}
 $helperArgs=@(Get-UniversalLaunchArguments $profile $programs[0] @('--fixture=value'))
 if(($helperArgs -join '|') -ne '--fixture=value'){throw 'Desktop proxy switch applied to a non-Desktop helper'}
 $cliArgs=@(Get-UniversalLaunchArguments $profile $programs[2] @('--fixture=value'))
 if(($cliArgs -join '|') -ne '--fixture=value'){throw 'Desktop proxy switch applied to CLI'}
 $bad=$profile|ConvertTo-Json -Depth 12|ConvertFrom-Json;$bad.DesktopExecutable='C:\Fixture\other\claude.exe';$rejected=$false;try{$null=ConvertTo-UniversalProfile $bad}catch{$rejected=$true};if(-not $rejected){throw 'Desktop outside Programs accepted'}
 if(-not(Test-UniversalProbeConsistency $profile '1.1.1.1' 'DE' '8.8.8.8')){throw 'Interface-only mode incorrectly rejects split routing'}
 $strict=$profile|ConvertTo-Json -Depth 12|ConvertFrom-Json;$strict.KillSwitchScope='InterfaceAndCore'
 if(Test-UniversalProbeConsistency $strict '1.1.1.1' 'DE' '8.8.8.8'){throw 'Strict core mode no longer checks consistent egress'}
 $country=$profile|ConvertTo-Json -Depth 12|ConvertFrom-Json;$country.ExpectedCountry='DE'
 if(Test-UniversalProbeConsistency $country '1.1.1.1' 'RU' '1.1.1.1'){throw 'Expected country ignored'}
 if(Test-UniversalProbeConsistency $profile '' 'DE' 'invalid'){throw 'Invalid IP probe accepted'}
 function Resolve-DnsName { [pscustomobject]@{IPAddress='8.8.8.8'} }
 $arguments=@(Get-UniversalProbeResolveArguments @('www.cloudflare.com','api.ipify.org'))
 if(($arguments -join '|') -ne '--resolve|www.cloudflare.com:443:8.8.8.8|--resolve|api.ipify.org:443:8.8.8.8'){throw 'DNS pre-resolution loses TLS hostname or argument boundaries'}
 function Resolve-DnsName { [pscustomobject]@{IPAddress='127.0.0.1'} }
 $rejected=$false;try{$null=Get-UniversalProbeResolveArguments @('api.ipify.org')}catch{$rejected=$true};if(-not $rejected){throw 'Loopback DNS answer accepted for an external probe'}
 function Resolve-DnsName { throw 'DNS unavailable' }
 $rejected=$false;try{$null=Get-UniversalProbeResolveArguments @('api.ipify.org')}catch{$rejected=$true};if(-not $rejected){throw 'DNS failure silently accepted'}
 'PASS: Claude TUN preset has no server dependency; IPv6/proxy exclusion and DNS pre-resolution/failure handling.'
}
