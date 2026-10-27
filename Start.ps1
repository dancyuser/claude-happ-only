#requires -Version 5.1
[CmdletBinding()]param([ValidateSet('Install','Diagnose','Fix')][string]$Mode='Diagnose',[switch]$Elevated)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1"
if(-not [Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell.'}
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){
 $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode '+$Mode+' -Elevated'
 try{$code=Invoke-ElevatedPowerShell $args;exit $code}catch{Write-Host ('UAC cancelled or elevation failed: '+$_.Exception.Message);exit 2}
}
$code=1
try{& "$PSScriptRoot\Manage-Happ.ps1" -Mode $Mode;$code=0}catch{Write-Host ('FAILED: '+$_.Exception.Message) -ForegroundColor Red}
if($Elevated){Read-Host 'Press Enter to close'}
exit $code
