#requires -Version 5.1
param([string]$BackupId,[switch]$List,[switch]$Elevated)
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1"
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){
 $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Elevated'
 if($List){$args+=' -List'};if($BackupId){if($BackupId -notmatch '^\d{8}-\d{6}-\d{3}-[a-f0-9]{8}$'){throw 'Invalid BackupId'};$args+=' -BackupId '+$BackupId}
 try{exit (Invoke-ElevatedPowerShell $args)}catch{Write-Host $_.Exception.Message;exit 2}
}
$code=1
try{
 . "$PSScriptRoot\BackupRestore.ps1"
 if(-not $BackupId){
  $rows=@(Get-ChildItem -LiteralPath (Get-BackupHome) -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {if(Test-Path (Join-Path $_.FullName 'COMPLETE')){$m=Get-Content -Raw (Join-Path $_.FullName 'metadata.json') | ConvertFrom-Json;[pscustomobject]@{BackupId=$_.Name;Created=$m.Created;Reason=$m.Reason;HadGuard=$m.HadGuard}}})
  $rows | Format-Table -AutoSize | Out-Host
  if($List){$code=0}else{$BackupId=Read-Host 'Enter exact BackupId to restore (blank = cancel)';if(-not $BackupId){throw 'Restore cancelled; nothing changed'}}
 }
 if(-not $List){& "$PSScriptRoot\Restore-Guard.ps1" -BackupId $BackupId;$code=0}
}catch{Write-Host ('RESTORE FAILED: '+$_.Exception.Message) -ForegroundColor Red}
if($Elevated){Read-Host 'Press Enter to close'}
exit $code
