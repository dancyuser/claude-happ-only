#requires -Version 5.1
# Normal-user parent. A single UAC worker deploys AppID/guard and runs preflight.
[CmdletBinding()]param([Parameter(Mandatory)][string]$ConfigurationFile,[ValidateSet('Install','Fix')][string]$Mode='Install',[ValidateSet('Auto','Off','Require')][string]$AppIdMode,[switch]$Preview,[switch]$NoWatch,[switch]$PreserveExistingPolicyOnly)
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1"
$configTemp=$null;$applied=$null;$success=$false
try{
 if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Start as ordinary target user; this script requests UAC itself'}
 $c=Read-GuardConfig $ConfigurationFile
 if($c.LaunchUserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Wrong configured user'}
 if(-not $AppIdMode){$AppIdMode=$c.AppIdMode}
 $enabled=($AppIdMode -ne 'Off' -and -not $c.ClaudeRoot)
 if($AppIdMode -eq 'Require' -and $c.ClaudeRoot){throw 'AppID PFN provisioning requires MSIX; standalone needs separately reviewed rules'}
 if($Preview){return [pscustomobject]@{AppIdMode=$AppIdMode;AppIdEnabled=$enabled;PolicyChoice='Checked after UAC; existing configured legacy preserved';UACWorkers=1;ClaudeLaunched=$false;Changes=$false}}
 Assert-NoClaudeClient
 $manifest=Get-Content "$PSScriptRoot\payload-hashes.json" -Raw | ConvertFrom-Json
 foreach($item in $manifest){if((Get-FileHash (Join-Path $PSScriptRoot $item.Name)).Hash -ne $item.SHA256){throw ('Payload changed: '+$item.Name)}}
 $prepared=$null
 if($enabled){$prepared=& "$PSScriptRoot\Prepare-AppIdPolicy.ps1" -PackageFamily $c.PackageFamily -InstallCompiler}
 $applied=& "$PSScriptRoot\Configure-CodeProxy.ps1" -Mode Apply -ProxyPort ([int]$c.ProxyPort) -ExpectedCountry $c.ExpectedCountry
 if(-not $applied.SettingsOK){throw 'User Code settings failed'}
 Write-Host ('USER SETTINGS BACKUP: '+$applied.BackupDirectory)
 $c.AppIdMode=$AppIdMode;$c.AppIdRequired=[bool]$enabled;$c.UseLegacyTag=[bool]$enabled
 $id=[guid]::NewGuid();$configTemp=Join-Path $env:TEMP ('ClaudeHapp-Automated-'+$id+'.json')
 $c | ConvertTo-Json -Depth 20 | Set-Content $configTemp -Encoding UTF8
 $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Install-Automated.Elevated.ps1" -RequestId '+$id+' -ConfigurationFile "'+$configTemp+'" -ConfigSHA256 '+(Get-FileHash $configTemp).Hash+' -Mode '+$Mode
 if($PreserveExistingPolicyOnly){$arguments+=' -PreserveExistingPolicyOnly'}
 if($enabled){$preparedDir=Split-Path $prepared.Xml -Parent;$arguments+=' -PreparedDirectory "'+$preparedDir+'" -PreparedSHA256 '+(Get-FileHash (Join-Path $preparedDir 'prepared.json')).Hash}
 Write-Host 'UAC: policy inventory, scoped deployment/rollback, guard backup and final preflight. Claude will not start.'
 $status=Invoke-ElevatedPowerShell $arguments
 $resultPath=Join-Path $env:ProgramData ('ClaudeHappTransactions\'+$id+'\result.json')
 if($status -ne 0){throw ('Administrative phase incomplete, code '+$status+'. Report: '+$resultPath)}
 $installed=Read-GuardConfig (Join-Path (Get-GuardRoot) 'config.json')
 $null=Read-ValidatedLaunchTicket $id $installed
 $success=$true
 Write-Host ('AUTOMATED CHECK ONLY PASS. Claude NOT started. Report: '+$resultPath)
 if(-not $NoWatch){try{Start-CoverageObserver;Write-Host ('Coverage observer waiting for your manual launch; report: '+(Join-Path $env:LOCALAPPDATA 'ClaudeHappOnly\Coverage\latest.json'))}catch{Write-Warning ('Coverage observer unavailable; policy/tunnel passed: '+$_.Exception.Message)}}
}catch{
 Write-Host ('AUTOMATED SETUP INCOMPLETE: '+$_.Exception.Message) -ForegroundColor Red
 if($applied -and -not $success){try{$null=& "$PSScriptRoot\Configure-CodeProxy.ps1" -Mode Restore -SettingsPath $applied.SettingsPath -BackupId $applied.BackupId;Write-Host 'User Code settings restored.'}catch{Write-Host ('User settings rollback needs review. BackupId='+$applied.BackupId+'; '+$_.Exception.Message) -ForegroundColor Yellow}}
 exit 1
}finally{if($configTemp -and (Test-Path $configTemp)){Remove-Item -LiteralPath $configTemp -Force}}
