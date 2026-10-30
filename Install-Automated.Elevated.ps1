#requires -Version 5.1
# One elevated transaction, no application launch. Policy mutations are journaled.
param([Parameter(Mandatory)][guid]$RequestId,[Parameter(Mandatory)][string]$ConfigurationFile,[Parameter(Mandatory)][string]$ConfigSHA256,[string]$PreparedDirectory,[string]$PreparedSHA256,[ValidateSet('Install','Fix')][string]$Mode='Install',[switch]$PreserveExistingPolicyOnly)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1";. "$PSScriptRoot\BackupRestore.ps1";. "$PSScriptRoot\CodeProxy.Common.ps1"
. "$PSScriptRoot\AppId.Runtime.ps1";. "$PSScriptRoot\AppId.Deployment.ps1";. "$PSScriptRoot\AppId.Common.ps1"
$dir=$null;$createdDir=$false;$code=1;$deployment=$null;$mutex=$null;$locked=$false;$context=[pscustomobject]@{GuardReport='';OldAppIdExists=$false;StateWritten=$false}
try{
 if(-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator worker required'}
 if((Get-FileHash -LiteralPath $ConfigurationFile).Hash -ne $ConfigSHA256){throw 'Configuration changed during elevation'}
 $mutex=[Threading.Mutex]::new($false,'Global\ClaudeHappAppIdProvision');$locked=$mutex.WaitOne(0);if(-not $locked){throw 'Another AppID provisioner is running'}
 $c=Read-GuardConfig $ConfigurationFile
 $transactions=Join-Path $env:ProgramData 'ClaudeHappTransactions';Assert-CodeProxyPlainPath $transactions;Set-ProtectedDirectory $transactions
 $dir=Join-Path $transactions $RequestId.ToString();if(Test-Path -LiteralPath $dir){throw 'Transaction ID already used'};Set-ProtectedDirectory $dir;$createdDir=$true
 Copy-Item -LiteralPath $ConfigurationFile -Destination "$dir\candidate.json"
 if((Get-FileHash "$dir\candidate.json").Hash -ne $ConfigSHA256){throw 'Protected config copy mismatch'}
 $c=Read-GuardConfig "$dir\candidate.json"
 Assert-NoClaude -Configuration $c
 $root=Get-GuardRoot
 if(Test-Path "$root\AppId-state.json"){$context.OldAppIdExists=$true;Copy-Item "$root\AppId-state.json" "$dir\AppId-state.before.json"}
 $legacyAllowed=$false
 if(Test-Path "$root\config.json"){$old=Read-GuardConfig "$root\config.json";$legacyAllowed=[bool]($old.UseLegacyTag -and $old.PackageFamily -eq $c.PackageFamily -and (Test-Path "$root\state.json"))}
 $plan=[pscustomobject]@{Enabled=[bool]$c.AppIdRequired;ManagedId='3E5E5A48-7D87-49E0-A12A-CC2C17689A73';LegacyId='C0E85E51-F842-4969-BD74-36506B26A5B1';BinaryHash='';AllowLegacyReuse=$legacyAllowed;PreserveExistingOnly=[bool]$PreserveExistingPolicyOnly}
 if($plan.Enabled){
  $preparedPath=Join-Path $PreparedDirectory 'prepared.json'
  if((Get-FileHash -LiteralPath $preparedPath).Hash -ne $PreparedSHA256){throw 'Prepared manifest changed during elevation'}
  $prepared=Get-Content -LiteralPath $preparedPath -Raw | ConvertFrom-Json
  if($prepared.PackageFamily -ne $c.PackageFamily -or $prepared.PolicyType -ne 'AppID Tagging Policy' -or $prepared.Applied -or $prepared.PolicyID.Trim('{}') -ne $plan.ManagedId){throw 'Unexpected prepared policy'}
  $xml=Join-Path $PreparedDirectory 'Claude-Happ-Only-AppId.xml';$binary=Join-Path $PreparedDirectory ('{'+$plan.ManagedId+'}.cip')
  if((Get-FileHash $xml).Hash -ne $prepared.XmlSHA256 -or (Get-FileHash $binary).Hash -ne $prepared.BinarySHA256){throw 'Prepared payload checksum mismatch'}
  if(([IO.File]::ReadAllText($xml).Replace("`r`n","`n").Trim()) -cne ((New-ClaudeAppIdXml $c.PackageFamily).Replace("`r`n","`n").Trim())){throw 'XML differs from narrow generated policy'}
  Copy-Item $xml "$dir\policy.xml";Copy-Item $binary "$dir\policy.cip";$plan.BinaryHash=$prepared.BinarySHA256
  if((Get-FileHash "$dir\policy.cip").Hash -ne $prepared.BinarySHA256 -or (Get-FileHash "$dir\policy.xml").Hash -ne $prepared.XmlSHA256){throw 'Protected policy copy mismatch'}
 }
 Save-JSON $plan "$dir\plan.json"
 $ops=@{}
 $ops.List={Get-AppIdPolicies}
 $ops.Install={Write-Host 'Installing new AppID tagging policy...';$null=Invoke-CiTool @('--update-policy',('"'+$dir+'\policy.cip"'),'--json')}
 $ops.Remove={$null=Invoke-CiTool @('--remove-policy',('{'+$plan.ManagedId+'}'),'--json')}
 $ops.Journal={param($state) Save-JSON $state "$dir\journal.json"}
 $ops.ApplyGuard={param($policy,$kind)
  if($plan.Enabled){
   $existingBinary=Join-Path $env:SystemRoot ('System32\CodeIntegrity\CiPolicies\Active\{'+$policy.Id+'}.cip')
   Copy-Item -LiteralPath $existingBinary -Destination "$dir\active-policy.cip"
   if((Get-FileHash "$dir\active-policy.cip").Hash -ne $policy.Hash){throw 'Active policy backup mismatch'}
   Assert-CodeProxyPlainPath $root;Set-ProtectedDirectory $root
   $state=[pscustomobject]@{Schema=1;Machine=(Get-MachineBinding);PackageFamily=$c.PackageFamily;ProxyPort=[int]$c.ProxyPort;PolicyId=$policy.Id;BinaryHash=$policy.Hash;Kind=$kind;Transaction=$RequestId.ToString();Status='ActivePolicy';VerifiedUTC=[DateTime]::UtcNow.ToString('o');FutureChildrenVerified=$false}
   Save-JSON $state "$root\AppId-state.json";Set-ProtectedFile "$root\AppId-state.json";$context.StateWritten=$true
  }
  $context.GuardReport=Join-Path $env:ProgramData ('ClaudeHappReports\automated-'+$RequestId)
  $null=& "$PSScriptRoot\Manage-Happ.ps1" -Mode $Mode -SetupConfigFile "$dir\candidate.json" -ReportDirectory $context.GuardReport
 }
 $ops.RollbackGuard={
  try{if($context.GuardReport -and (Test-Path "$($context.GuardReport)\result.json")){
   $report=Get-Content "$($context.GuardReport)\result.json" -Raw | ConvertFrom-Json
   if($report.BackupId){
    $meta=Get-Content (Join-Path (Get-BackupHome) ($report.BackupId+'\metadata.json')) -Raw | ConvertFrom-Json
    if($meta.HadGuard){$null=& "$PSScriptRoot\Restore-Guard.ps1" -BackupId $report.BackupId}
    else{'Initial guard restrictions retained; no automatic uninstall.' | Set-Content "$dir\guard-retained.txt" -Encoding UTF8}
   }
  }}finally{if($context.StateWritten){
   if($context.OldAppIdExists){Copy-Item "$dir\AppId-state.before.json" "$root\AppId-state.json" -Force;Set-ProtectedFile "$root\AppId-state.json"}
   elseif(Test-Path "$root\AppId-state.json"){Remove-Item -LiteralPath "$root\AppId-state.json"}
  }}
 }
 $ops.Preflight={Write-Host 'Final preflight, no new UAC and no Claude launch...';Invoke-PreflightWorker $RequestId}
 $deployment=Invoke-AppIdDeployment $plan $ops
 if(Test-Path "$dir\guard-retained.txt"){$deployment | Add-Member NoteProperty GuardDisposition 'Initial restrictions retained; manual review required';$deployment.Rollback='NeedsReview: initial guard retained'}
 if($deployment.Status -eq 'OK'){$code=0}
 elseif($deployment.Status -eq 'PendingActivation'){Write-Host 'APPID PENDING ACTIVATION. No launch approval. Reboot manually if Windows requires it, then rerun setup.' -ForegroundColor Yellow;$code=3}
 else{throw ($deployment.Error+'; rollback='+$deployment.Rollback)}
}catch{Write-Host ('AUTOMATED INSTALL FAILED: '+$_.Exception.Message) -ForegroundColor Red;if(-not $deployment){$deployment=[pscustomobject]@{Status='FAIL';Stage='Preparation';Error=$_.Exception.Message;ClaudeLaunched=$false}};$code=1}
finally{if($createdDir){Save-JSON $deployment "$dir\result.json"};if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
exit $code
