param([Parameter(Mandatory)][string]$ConfigurationFile)
$ErrorActionPreference='Stop';$code=1
try{& "$PSScriptRoot\Manage-Happ.ps1" -Mode Install -SetupConfigFile $ConfigurationFile;$code=0}catch{Write-Host $_.Exception.Message -ForegroundColor Red}
Read-Host 'Press Enter to close setup'
exit $code
