#requires -Version 5.1
# OS mutations are injected fakes. No CiTool, WFP, UAC, or target launch.
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\AppId.Deployment.ps1"
function Test-Scenario([string]$Name,[object[]]$Initial,[string]$Failure='', [bool]$LegacyAllowed=$false,[bool]$Enabled=$true,[bool]$PreserveOnly=$false){
 $managed='3E5E5A48-7D87-49E0-A12A-CC2C17689A73';$legacy='C0E85E51-F842-4969-BD74-36506B26A5B1'
 $db=[pscustomobject]@{Rows=@($Initial);Failure=$Failure;Events=(New-Object 'Collections.Generic.List[string]')}
 $plan=[pscustomobject]@{Enabled=$Enabled;ManagedId=$managed;LegacyId=$legacy;BinaryHash='expected';AllowLegacyReuse=$LegacyAllowed;PreserveExistingOnly=$PreserveOnly}
 $ops=@{}
 $ops.List={@($db.Rows)}.GetNewClosure()
 $ops.Journal={param($state) $db.Events.Add('Journal:'+$state.Stage)}.GetNewClosure()
 $ops.Install={
  $db.Events.Add('Install');$db.Rows+= [pscustomobject]@{Id=$managed;Name='Claude-Happ-Only-AppId';Hash='expected';Active=($db.Failure -ne 'Pending')}
  if($db.Failure -eq 'Install'){throw 'Partial CiTool failure'}
 }.GetNewClosure()
 $ops.Remove={$db.Events.Add('Remove');if($db.Failure -eq 'Remove'){throw 'Remove failed'};$db.Rows=@($db.Rows | Where-Object {$_.Id -ne $managed})}.GetNewClosure()
 $ops.ApplyGuard={param($policy,$kind)
  $db.Events.Add('Guard')
  if($db.Failure -eq 'External'){$db.Rows[0].Hash='changed-by-other-admin';throw 'Guard failed'}
  if($db.Failure -in @('Guard','Remove')){throw 'Guard failed'}
 }.GetNewClosure()
 $ops.RollbackGuard={$db.Events.Add('RollbackGuard')}.GetNewClosure()
 $ops.Preflight={$db.Events.Add('Preflight');if($db.Failure -eq 'Preflight'){throw 'Tunnel failed'}}.GetNewClosure()
 $result=Invoke-AppIdDeployment $plan $ops
 switch($Name){
  'new' {if($result.Status -ne 'OK' -or -not $result.PolicyCreated -or $db.Rows.Count -ne 1){throw 'New policy not committed'};if($db.Events.IndexOf('Journal:InstallPolicy') -gt $db.Events.IndexOf('Install')){throw 'Mutation preceded intent journal'}}
  'managed-reuse' {if($result.Status -ne 'OK' -or 'Install' -in $db.Events -or 'Remove' -in $db.Events){throw 'Existing policy changed'}}
  'legacy-reuse' {if($result.Status -ne 'OK' -or $result.PolicyKind -ne 'LegacyPreserved' -or 'Install' -in $db.Events){throw 'Configured legacy not preserved'}}
  'collision' {if($result.Status -ne 'FAIL' -or 'Guard' -in $db.Events -or 'Remove' -in $db.Events -or 'Install' -in $db.Events){throw 'Collision mutated system'}}
  'legacy-refuse' {if($result.Status -ne 'FAIL' -or 'Install' -in $db.Events -or 'Remove' -in $db.Events){throw 'Unconfigured legacy adopted'}}
  'preserve-only' {if($result.Status -ne 'FAIL' -or 'Install' -in $db.Events -or 'Guard' -in $db.Events){throw 'Preserve-only created policy'}}
  'legacy-guard-failure' {if($result.Status -ne 'FAIL' -or 'Remove' -in $db.Events -or 'Install' -in $db.Events){throw 'Legacy policy changed during compensation'}}
  'pending' {if($result.Status -ne 'PendingActivation' -or 'Guard' -in $db.Events -or 'Preflight' -in $db.Events -or 'Remove' -in $db.Events){throw 'Pending policy treated as ready'}}
  'external' {if($result.Status -ne 'FAIL' -or $result.Rollback -notlike 'NeedsReview*' -or 'Remove' -in $db.Events){throw 'Externally changed policy removed'}}
  'off' {if($result.Status -ne 'OK' -or 'Install' -in $db.Events -or $result.PolicyKind -ne 'Off'){throw 'Off mode provisioned policy'}}
  'remove-failure' {if($result.Status -ne 'FAIL' -or $result.Rollback -notlike 'NeedsReview*'){throw 'Rollback failure hidden'}}
  default {if($result.Status -ne 'FAIL' -or $result.Rollback -ne 'CompensationComplete' -or $db.Rows.Count -ne 0 -or 'Remove' -notin $db.Events){throw ('Failed operation was not compensated: '+$Name)}}
 }
}
$same=[pscustomobject]@{Id='3E5E5A48-7D87-49E0-A12A-CC2C17689A73';Name='Claude-Happ-Only-AppId';Hash='expected';Active=$true}
$other=[pscustomobject]@{Id=$same.Id;Name='Other';Hash='foreign';Active=$true}
$old=[pscustomobject]@{Id='C0E85E51-F842-4969-BD74-36506B26A5B1';Name='Claude-Network-Identity';Hash='old-hash';Active=$true}
Test-Scenario 'new' @()
Test-Scenario 'managed-reuse' @($same)
Test-Scenario 'legacy-reuse' @($old) '' $true
Test-Scenario 'collision' @($other)
Test-Scenario 'legacy-refuse' @($old)
Test-Scenario 'guard-failure' @() 'Guard'
Test-Scenario 'preflight-failure' @() 'Preflight'
Test-Scenario 'partial-install' @() 'Install'
Test-Scenario 'pending' @() 'Pending'
Test-Scenario 'external' @() 'External'
Test-Scenario 'remove-failure' @() 'Remove'
Test-Scenario 'off' @() '' $false $false
Test-Scenario 'preserve-only' @() '' $false $true $true
Test-Scenario 'legacy-guard-failure' @($old) 'Guard' $true
foreach($case in @(@(0,0,0,'WaitingForUserLaunch'),@(1,1,0,'CoverageGap'),@(1,0,1,'Unknown'),@(2,0,0,'ObservedProcessesTagged'))){
 $snapshot=[pscustomobject]@{ObservedProcesses=$case[0];Untagged=$case[1];Unknown=$case[2]}
 if((Get-CoverageSummary $snapshot) -ne $case[3]){throw 'Coverage status overclaimed readiness'}
}
'PASS: 14 deployment/failure/rollback scenarios and 4 honest coverage states. All OS operations mocked.'
