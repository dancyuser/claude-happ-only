#requires -Version 5.1
# Local recorded state, not a replacement for fresh preflight or a launch permit.
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1"
$root=Get-GuardRoot;$c=Read-GuardConfig "$root\config.json"
$policy=$null;if(Test-Path "$root\AppId-state.json"){$policy=Get-Content "$root\AppId-state.json" -Raw | ConvertFrom-Json}
$coveragePath=Join-Path $env:LOCALAPPDATA 'ClaudeHappOnly\Coverage\latest.json'
$coverage=$null;if(Test-Path -LiteralPath $coveragePath){$coverage=Get-Content -LiteralPath $coveragePath -Raw | ConvertFrom-Json}
[pscustomobject]@{PolicyRequired=$c.AppIdRequired;RecordedPolicyKind=$policy.Kind;RecordedPolicyStatus=$policy.Status;PolicyVerifiedUTC=$policy.VerifiedUTC;Tunnel='Fresh CheckOnly required; this command does not probe';CoverageStatus=$(if($coverage){$coverage.Status}else{'NoReportYet'});CoverageTimeUTC=$coverage.TimeUTC;Observed=$coverage.Observed;Untagged=$coverage.Untagged;Unknown=$coverage.Unknown;CoverageReport=$coveragePath;Scope='Recorded local status; coverage report is user-writable diagnostics, never launch authorization';ClaudeLaunched=$false}
