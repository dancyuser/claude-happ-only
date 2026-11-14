#requires -Version 5.1
$ErrorActionPreference='Stop'
Write-Host '1. Universal: chosen Windows EXEs, any named TUN / local proxy'
Write-Host '2. Existing Claude Desktop + Happ preset'
Write-Host '3. Claude TUN Only: automatic Claude/Happ detection, no server IP required'
$choice=Read-Host 'Setup type [1]';if(-not $choice){$choice='1'}
switch($choice){
 '1' {& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Universal-Guard.ps1" -Mode Setup}
 '2' {& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Setup.ps1"}
 '3' {& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Setup-ClaudeTun.ps1"}
 default {throw 'Select 1, 2 or 3'}
}
exit $LASTEXITCODE
