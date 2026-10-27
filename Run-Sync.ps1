$ErrorActionPreference='Stop'
Start-Transcript -Path "$PSScriptRoot\sync-latest.log" -Force | Out-Null
try{& "$PSScriptRoot\Sync-Guard.ps1" -Mode Sync; exit 0}
catch{Write-Output ($_ | Out-String);exit 1}
finally{Stop-Transcript | Out-Null}
