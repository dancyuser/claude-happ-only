#requires -Version 5.1
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\CodeProxy.Common.ps1"
$original='{"permissions":{"allow":["Read","Bash(git status)"]},"env":{"https_proxy":"socks5://127.0.0.1:9999","NO_PROXY":"*","KEEP_ME":"value"},"other":{"a":[1,{"b":true}]}}'
$updated=ConvertTo-CodeProxySettings $original 10808
if(-not(Test-CodeProxySettings $updated 10808)){throw 'Generated settings rejected'}
$parsed=$updated | ConvertFrom-Json
if($parsed.env.KEEP_ME -ne 'value' -or $parsed.permissions.allow.Count -ne 2 -or $parsed.other.a[1].b -ne $true){throw 'Unrelated settings were lost'}
if(@($parsed.env.PSObject.Properties | Where-Object {$_.Name -ceq 'https_proxy'}).Count){throw 'Lower-case conflicting proxy survived'}
if($parsed.env.NO_PROXY -cne '' -or $parsed.env.HTTPS_PROXY -cne 'http://127.0.0.1:10808'){throw 'Proxy bypass or scheme is wrong'}
if(Test-CodeProxySettings $original 10808){throw 'Unsafe original settings accepted'}
if(Test-CodeProxySettings $updated 9999){throw 'Wrong port accepted'}
foreach($bad in @('[]','null','1','{"env":null}','{"env":[]}','{"env":"wrong"}','{malformed')){
 $rejected=$false;try{$null=ConvertTo-CodeProxySettings $bad 10808}catch{$rejected=$true}
 if(-not $rejected){throw ('Malformed/non-object settings accepted: '+$bad)}
}
if(-not(Test-CodeProxySettings (ConvertTo-CodeProxySettings '' 10808) 10808)){throw 'First-install settings failed'}
'PASS: settings preserve permissions/nested data, replace SOCKS and bypass, reject wrong port and malformed input.'
