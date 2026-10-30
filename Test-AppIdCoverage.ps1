#requires -Version 5.1
# Read-only snapshot of already-running processes. Never launches a target.
param([string]$OutputDirectory)
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1"
$root=Get-GuardRoot;$c=Read-GuardConfig "$root\config.json"
$state=Get-Content "$root\state.json" -Raw | ConvertFrom-Json
if(-not ('ReadAppIdToken' -as [type])){Add-Type -Path "$PSScriptRoot\AppIdTokenReader.cs"}
$processes=@(Get-CimInstance Win32_Process)
$seeds=@($processes | Where-Object {$_.Name -ieq 'claude.exe' -and $_.ExecutablePath -and ($_.ExecutablePath -in $state.Executables -or ($c.CodeRoot -and $_.ExecutablePath.StartsWith(([string]$c.CodeRoot).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)))})
$ids=@($seeds.ProcessId)
do{$next=@($processes | Where-Object {$_.ParentProcessId -in $ids -and $_.ProcessId -notin $ids});$ids+=@($next.ProcessId)}while($next.Count)
$rows=@(foreach($process in ($processes | Where-Object {$_.ProcessId -in $ids})){
 $r=[ReadAppIdToken]::Query([int]$process.ProcessId)
 [pscustomobject]@{Name=$process.Name;ProcessId=$process.ProcessId;ParentProcessId=$process.ParentProcessId;HasClaudeTag=$r.HasTag;TagValue=$r.TagValue;AttributeFlags=$r.Flags;NonInheritable=$r.NonInheritable;Error=$r.Error}
})
$unknown=@($rows | Where-Object {$_.Error}).Count
$untagged=@($rows | Where-Object {-not $_.Error -and -not $_.HasClaudeTag}).Count
$result=[pscustomobject]@{ObservedProcesses=$rows.Count;Untagged=$untagged;Unknown=$unknown;AllObservedTagged=[bool]($rows.Count -gt 0 -and $unknown -eq 0 -and $untagged -eq 0);Rows=$rows;Scope='Current snapshot only; not a guarantee for future children, WSL, services or network flow enforcement';PoliciesChanged=$false;ClaudeLaunched=$false}
if($OutputDirectory){$out=(New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop).FullName;$result | ConvertTo-Json -Depth 6 | Set-Content "$out\appid-coverage.json" -Encoding UTF8}
return $result
