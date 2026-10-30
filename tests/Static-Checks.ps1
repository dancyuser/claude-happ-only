#requires -Version 5.1
# No UAC, target launch, firewall changes, or network requests.
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$errorsFound=@()
Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse | ForEach-Object {
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
 foreach($errorItem in $errors){$errorsFound+=($_.Name+': '+$errorItem.Message)}
}
if($errorsFound.Count){throw ($errorsFound -join "`r`n")}
Add-Type -Path "$root\HappOnlyWfp.cs";Add-Type -Path "$root\WfpSnapshot.cs";Add-Type -Path "$root\DirectDoh.cs"
# Compile P/Invoke declarations only; never construct a WFP engine or send a query.
. "$root\Common.ps1"
if((@(Get-OtherPorts 443)-join ',') -ne '1-442,444-65535'){throw 'Port complement mismatch'}
if((@(Get-OtherPorts 1)-join ',') -ne '2-65535'){throw 'Lower port bound mismatch'}
if((@(Get-OtherPorts 65535)-join ',') -ne '1-65534'){throw 'Upper port bound mismatch'}
& "$PSScriptRoot\Test-ServiceGuard.ps1"
& "$PSScriptRoot\Test-CodeProxy.ps1"
& "$PSScriptRoot\Test-CodeCache.ps1"
& "$PSScriptRoot\Test-UserMaintenanceGuard.ps1"
& "$PSScriptRoot\Test-SetupConfiguration.ps1"
& "$PSScriptRoot\Test-AppId.ps1"
foreach($item in (Get-Content -Raw "$root\payload-hashes.json" | ConvertFrom-Json)){
 $path=Join-Path $root $item.Name;if((Get-FileHash -LiteralPath $path).Hash -ne $item.SHA256){throw ('Payload checksum mismatch: '+$item.Name)}
}
'PASS: syntax, C# compilation, port boundaries, service guard and payload hashes. No UAC or Claude launch.'
