#requires -Version 5.1
param([Parameter(Mandatory)][Guid]$RequestId)
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1"
$root=Get-GuardRoot;$tickets=Join-Path $root 'LaunchTickets';$ticketPath=Join-Path $tickets ($RequestId.ToString()+'.json')
$ticket=[ordered]@{RequestId=$RequestId.ToString();OK=$false;FinishedUTC=$null;UserSid='';Executable='';ConfigSHA256='';Reports=@();Error='';ClaudeLaunched=$false};$code=1
try{
 Assert-NoClaude
 New-Item -ItemType Directory -Path $tickets -Force | Out-Null
 if(Test-Path -LiteralPath $ticketPath){throw 'Request ID already used'}
 $base=Join-Path (Join-Path $env:ProgramData 'ClaudeHappReports') ('preflight-'+$RequestId)
 $rounds=@('Diagnose','Fix','Diagnose');$passed=$false
 for($i=0;$i -lt $rounds.Count;$i++){
  $dir=Join-Path $base ($i.ToString()+'-'+$rounds[$i]);$ticket.Reports+=@($dir)
  try{& "$root\Manage-Happ.ps1" -Mode $rounds[$i] -ReportDirectory $dir}catch{Write-Host $_.Exception.Message -ForegroundColor Yellow}
  $r=$null;if(Test-Path "$dir\result.json"){$r=Get-Content -Raw "$dir\result.json" | ConvertFrom-Json}
  if($i -eq 0 -and $r.Status -eq 'OK'){$passed=$true;break}
  if($i -eq 2 -and $r.Status -eq 'OK'){$passed=$true}
 }
 if(-not $passed){throw 'Tunnel preflight failed after one repair round. See Reports in this ticket. Claude will NOT start.'}
 if(Test-Path "$root\maintenance.txt"){throw 'Restore/maintenance incomplete; no launch approval issued'}
 Assert-NoClaude
 $c=Read-GuardConfig "$root\config.json";$state=Get-Content -Raw "$root\state.json" | ConvertFrom-Json
 $ticket.UserSid=$c.LaunchUserSid;$ticket.Executable=$state.LaunchExecutable;$ticket.ConfigSHA256=(Get-FileHash "$root\config.json").Hash
 $ticket.OK=$true;$code=0
}catch{$ticket.Error=$_.Exception.Message;Write-Host $ticket.Error -ForegroundColor Red}
finally{
 $ticket.FinishedUTC=[DateTime]::UtcNow.ToString('o')
 if(Test-Path $tickets){$ticket | ConvertTo-Json -Depth 5 | Set-Content ($ticketPath+'.pending') -Encoding UTF8;Move-Item ($ticketPath+'.pending') $ticketPath -Force}
}
exit $code
