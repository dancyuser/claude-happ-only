#requires -Version 5.1
# Repairs diagnostic scripts only. Never launches/stops Claude or changes rules.
param([switch]$Worker,[string]$ExpectedSyncSHA256,[string]$ExpectedManageSHA256,[string]$ExpectedCommonSHA256)
$ErrorActionPreference='Stop';$code=1
try{
 . "$PSScriptRoot\Common.ps1"
 $admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 if(-not $Worker){
  if($admin){throw 'Run repair normally; it requests UAC for its worker'}
  Assert-NoClaudeClient
  $syncHash=(Get-FileHash "$PSScriptRoot\Sync-Guard.ps1").Hash
  $manageHash=(Get-FileHash "$PSScriptRoot\Manage-Happ.ps1").Hash
  $commonHash=(Get-FileHash "$PSScriptRoot\Common.ps1").Hash
  $code=Invoke-ElevatedPowerShell ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Worker -ExpectedSyncSHA256 '+$syncHash+' -ExpectedManageSHA256 '+$manageHash+' -ExpectedCommonSHA256 '+$commonHash)
  if($code -ne 0){throw 'Diagnostic repair failed/cancelled; no Claude launch'}
  Write-Host 'REPAIR PASS. Now run the installed Launch-Checked.ps1 with -CheckOnly -NoPause.'
  exit 0
 }
 if(-not $admin){throw 'Administrator worker required'}
 $root=Get-GuardRoot;$configuration=Read-GuardConfig "$root\config.json"
 Assert-NoClaude -Configuration $configuration
 $active=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -ieq 'powershell.exe' -and $_.ProcessId -ne $PID -and $_.CommandLine -like ('*'+$root+'\Preflight.ps1*')})
 if($active.Count){throw 'An old Preflight is still running. Cancel/close that diagnostic window yourself, then retry repair.'}
 if((Get-FileHash "$PSScriptRoot\Sync-Guard.ps1").Hash -ne $ExpectedSyncSHA256 -or (Get-FileHash "$PSScriptRoot\Manage-Happ.ps1").Hash -ne $ExpectedManageSHA256 -or (Get-FileHash "$PSScriptRoot\Common.ps1").Hash -ne $ExpectedCommonSHA256){throw 'Source changed while elevating'}
 $backup=Join-Path $root ('RepairBackups\'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $backup | Out-Null
 $stateBefore=Get-Content "$root\state.json" -Raw | ConvertFrom-Json
 Copy-Item "$root\state.json" "$backup\state-before.json"
 foreach($name in @('Common.ps1','Sync-Guard.ps1','Manage-Happ.ps1')){
  Copy-Item -LiteralPath "$root\$name" -Destination "$backup\$name"
  Copy-Item -LiteralPath "$PSScriptRoot\$name" -Destination "$root\$name.repair-pending"
  Move-Item -LiteralPath "$root\$name.repair-pending" -Destination "$root\$name" -Force
  if((Get-FileHash "$root\$name").Hash -ne (Get-FileHash "$PSScriptRoot\$name").Hash){throw ('Installed checksum mismatch: '+$name)}
 }
 Write-Host ('Diagnostic scripts backed up: '+$backup)
 $si=New-Object Diagnostics.ProcessStartInfo
 $si.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
 $si.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$root+'\Sync-Guard.ps1" -Mode Verify'
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $process=New-Object Diagnostics.Process;$process.StartInfo=$si
 try{
  $null=$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(45000)){$process.Kill();$process.WaitForExit();throw 'Verify worker timed out after 45 seconds'}
  $stdout.Result | Set-Content "$backup\verify.log" -Encoding UTF8
  $stderr.Result | Set-Content "$backup\verify-error.log" -Encoding UTF8
  if($process.ExitCode -ne 0 -or $stdout.Result -notmatch 'STATIC VERIFY PASS'){throw ('Verify failed; see '+$backup)}
  Write-Host $stdout.Result.Trim()
 }finally{$process.Dispose()}
 $stateAfter=Get-Content "$root\state.json" -Raw | ConvertFrom-Json
 if((@($stateBefore.Keys | Sort-Object)-join ',') -ne (@($stateAfter.Keys | Sort-Object)-join ',')){throw 'Filter inventory changed concurrently; review before claiming unchanged state'}
 [pscustomobject]@{VerifyPass=$true;GuardKeysUnchanged=$true;Filters=@($stateAfter.Keys).Count;ClaudeLaunched=$false;Backup=$backup} | ConvertTo-Json | Set-Content "$backup\result.json" -Encoding UTF8
 Write-Host 'REPAIR WORKER PASS: verification completed; filter keys unchanged; Claude not launched.'
 $code=0
}catch{Write-Host ('REPAIR FAILED: '+$_.Exception.Message) -ForegroundColor Red;Write-Host $_.ScriptStackTrace;$code=1}
exit $code
