param([Parameter(Mandatory)][string]$ConfigurationFile)
$ErrorActionPreference='Stop';$code=1
try{& "$PSScriptRoot\Manage-Happ.ps1" -Mode Install -SetupConfigFile $ConfigurationFile;$code=0}catch{Write-Host $_.Exception.Message -ForegroundColor Red}
exit $code
