#requires -Version 5.1
# Pure orchestration with injected OS operations; used by elevated worker and tests.
function Get-AppIdDeploymentDecision($Plan,$Policies){
 $owned=@($Policies | Where-Object {$_.Id -ieq $Plan.ManagedId})
 $legacy=@($Policies | Where-Object {$_.Id -ieq $Plan.LegacyId})
 if($owned.Count -gt 1 -or $legacy.Count -gt 1){throw 'Duplicate policy IDs'}
 if($owned.Count){
  if($owned[0].Name -ne 'Claude-Happ-Only-AppId' -or $owned[0].Hash -ne $Plan.BinaryHash){throw 'APPID_ID_CONFLICT: managed ID exists with different content; no overwrite'}
  return [pscustomobject]@{Action='Reuse';Policy=$owned[0];Kind='ManagedReused'}
 }
 if($legacy.Count){
  if(-not $Plan.AllowLegacyReuse -or $legacy[0].Name -ne 'Claude-Network-Identity' -or -not $legacy[0].Hash -or -not $legacy[0].Active){throw 'APPID_LEGACY_REVIEW: existing legacy policy cannot be adopted automatically'}
  return [pscustomobject]@{Action='Reuse';Policy=$legacy[0];Kind='LegacyPreserved'}
 }
 return [pscustomobject]@{Action='Create';Policy=$null;Kind='ManagedCreated'}
}
function Invoke-AppIdDeployment($Plan,$Ops){
 $state=[ordered]@{Status='FAIL';Stage='Inspect';InstallIntent=$false;PolicyCreated=$false;PolicyId='';PolicyKind='';GuardAttempted=$false;Rollback='NotNeeded';Error='';ClaudeLaunched=$false}
 try{
  if(-not $Plan.Enabled){
   $state.PolicyKind='Off';$state.Stage='ApplyGuard';$state.GuardAttempted=$true
   & $Ops.Journal ([pscustomobject]$state)
   & $Ops.ApplyGuard $null 'Off';$state.Stage='Preflight';& $Ops.Preflight
   $state.Status='OK';$state.Stage='Complete'
   & $Ops.Journal ([pscustomobject]$state);return [pscustomobject]$state
  }
  $before=@(& $Ops.List)
  $decision=Get-AppIdDeploymentDecision $Plan $before
  if($Plan.PreserveExistingOnly -and $decision.Action -eq 'Create'){throw 'APPID_PRESERVE_ONLY: no reusable policy; installation forbidden by caller'}
  $state.PolicyKind=$decision.Kind
  if($decision.Action -eq 'Create'){
   $state.Stage='InstallPolicy';$state.InstallIntent=$true;$state.PolicyId=$Plan.ManagedId
   & $Ops.Journal ([pscustomobject]$state)
   & $Ops.Install
   $state.PolicyCreated=$true
  }else{$state.PolicyId=$decision.Policy.Id}
  $state.Stage='VerifyPolicy'
  $current=@(& $Ops.List | Where-Object {$_.Id -ieq $state.PolicyId})
  if($current.Count -ne 1){throw 'APPID_NOT_FOUND_AFTER_INSTALL'}
  $expectedHash=if($decision.Action -eq 'Create'){$Plan.BinaryHash}else{$decision.Policy.Hash}
  if($current[0].Hash -ne $expectedHash){throw 'APPID_CONTENT_CHANGED'}
  if(-not $current[0].Active){
   $state.Status='PendingActivation';& $Ops.Journal ([pscustomobject]$state)
   return [pscustomobject]$state
  }
  $state.Stage='ApplyGuard';$state.GuardAttempted=$true
  & $Ops.Journal ([pscustomobject]$state)
  & $Ops.ApplyGuard $current[0] $decision.Kind
  $state.Stage='Preflight'; & $Ops.Preflight
  $state.Status='OK';$state.Stage='Complete'
 }catch{
  $state.Error=$_.Exception.Message;$failures=@()
  if($state.GuardAttempted){try{& $Ops.RollbackGuard}catch{$failures+=('Guard: '+$_.Exception.Message)}}
  # Installation may have partially succeeded even when CiTool returned an error.
  if($state.InstallIntent){try{
   $now=@(& $Ops.List | Where-Object {$_.Id -ieq $Plan.ManagedId})
   if($now.Count -eq 1){
    if($now[0].Hash -ne $Plan.BinaryHash){throw 'Policy changed outside this transaction; refusing removal'}
    & $Ops.Remove
    if(@(& $Ops.List | Where-Object {$_.Id -ieq $Plan.ManagedId}).Count){throw 'Policy still present after rollback'}
   }elseif($now.Count -gt 1){throw 'Duplicate ID during rollback'}
  }catch{$failures+=('Policy: '+$_.Exception.Message)}}
  $state.Rollback=if($failures.Count){'NeedsReview: '+($failures -join '; ')}else{'CompensationComplete'}
  $state.Status='FAIL'
 }
 & $Ops.Journal ([pscustomobject]$state)
 return [pscustomobject]$state
}
function Get-CoverageSummary($Snapshot){
 if($Snapshot.ObservedProcesses -eq 0){return 'WaitingForUserLaunch'}
 if($Snapshot.Untagged -gt 0){return 'CoverageGap'}
 if($Snapshot.Unknown -gt 0){return 'Unknown'}
 return 'ObservedProcessesTagged'
}
