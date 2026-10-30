#requires -Version 5.1
# Bounded read-only observer; never starts, stops or modifies a target process.
param([ValidateRange(1,600)][int]$DurationSeconds=600,[switch]$Once)
$ErrorActionPreference='Stop';. "$PSScriptRoot\AppId.Deployment.ps1";. "$PSScriptRoot\CodeProxy.Common.ps1"
$homePath=Join-Path $env:LOCALAPPDATA 'ClaudeHappOnly\Coverage'
Assert-CodeProxyPlainPath $homePath;New-Item -ItemType Directory -Path $homePath -Force | Out-Null
$run=[guid]::NewGuid().ToString('N');$clock=[Diagnostics.Stopwatch]::StartNew();$last='';$firstSeen=$null
do{
 try{
  $snapshot=& "$PSScriptRoot\Test-AppIdCoverage.ps1"
  $status=Get-CoverageSummary $snapshot
  if($snapshot.ObservedProcesses -gt 0 -and $null -eq $firstSeen){$firstSeen=$clock.Elapsed.TotalSeconds}
  $report=[pscustomobject]@{Run=$run;TimeUTC=[DateTime]::UtcNow.ToString('o');Status=$status;Tunnel='Not checked by observer';Observed=$snapshot.ObservedProcesses;Untagged=$snapshot.Untagged;Unknown=$snapshot.Unknown;Rows=$snapshot.Rows;Scope=$snapshot.Scope;ClaudeLaunched=$false}
 }catch{$status='ObserverError';$report=[pscustomobject]@{Run=$run;TimeUTC=[DateTime]::UtcNow.ToString('o');Status=$status;Error=$_.Exception.Message;ClaudeLaunched=$false}}
 $report | ConvertTo-Json -Depth 7 | Set-Content "$homePath\latest.json" -Encoding UTF8
 $key=$status+':'+($report.Rows | ConvertTo-Json -Depth 7 -Compress)
 if($key -ne $last){$report | ConvertTo-Json -Depth 7 -Compress | Add-Content "$homePath\$run.jsonl" -Encoding UTF8;$last=$key}
 if($Once){$report;break}
 if($null -ne $firstSeen -and $clock.Elapsed.TotalSeconds-$firstSeen -ge 120){break}
 Start-Sleep -Seconds 2
}while($clock.Elapsed.TotalSeconds -lt $DurationSeconds)
