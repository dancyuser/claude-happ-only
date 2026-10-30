#requires -Version 5.1
# Fixture-only lifecycle test. Uses real HTTP proxy probes, never launches Claude.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. "$root\CodeProxy.Common.ps1"
$fixture=Join-Path (Split-Path $root -Parent) ('Happ-CodeProxy-Fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$target=Join-Path $fixture 'settings.json'
# Only process-presence is mocked so the isolated fixture can be tested while the
# user's application stays untouched. This is not production/Code runtime proof.
function Get-Process {param([string[]]$Name,$ErrorAction) if(($Name -join ',') -ne 'claude'){throw 'Unexpected process query in fixture'};return @()}
try{
 $original=[Text.Encoding]::UTF8.GetBytes('{"permissions":{"allow":["Read"]},"env":{"KEEP":"safe"}}')
 [IO.File]::WriteAllBytes($target,$original);$before=(Get-FileHash $target).Hash
 $apply=& "$root\Configure-CodeProxy.ps1" -Mode Apply -SettingsPath $target
 if(-not $apply.SettingsOK -or -not $apply.Transport.OK){throw 'Fixture Apply failed'}
 [IO.File]::AppendAllText($target,' ')
 $refused=$false;try{$null=& "$root\Configure-CodeProxy.ps1" -Mode Restore -SettingsPath $target -BackupId $apply.BackupId}catch{$refused=$true}
 if(-not $refused){throw 'Restore overwrote a newer edit'}
 $appliedText=ConvertTo-CodeProxySettings ([Text.Encoding]::UTF8.GetString($original)) 10808
 [IO.File]::WriteAllText($target,$appliedText,[Text.UTF8Encoding]::new($false))
 $restored=& "$root\Configure-CodeProxy.ps1" -Mode Restore -SettingsPath $target -BackupId $apply.BackupId
 if(-not $restored.Restored -or (Get-FileHash $target).Hash -ne $before){throw 'Original bytes not restored'}
 $absent=Join-Path $fixture 'new\settings.json'
 $created=& "$root\Configure-CodeProxy.ps1" -Mode Apply -SettingsPath $absent
 $null=& "$root\Configure-CodeProxy.ps1" -Mode Restore -SettingsPath $absent -BackupId $created.BackupId
 if(Test-Path -LiteralPath $absent){throw 'First-install rollback did not remove the created file'}
 'PASS: fixture Apply, backup, exact-byte restore, conflict refusal, and initially absent file rollback; real HTTP probes passed. Claude untouched.'
}finally{
 # Keep fixtures and backups available for inspection; no recursive delete.
 Write-Host ('Fixture retained: '+$fixture)
}
