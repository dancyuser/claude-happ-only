#requires -Version 5.1
function Invoke-CiTool([string[]]$Arguments){
 $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=Join-Path $env:SystemRoot 'System32\CiTool.exe'
 if(-not(Test-Path -LiteralPath $si.FileName)){throw 'CiTool requires Windows 11 22H2 or later'}
 $si.Arguments=($Arguments -join ' ');$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$si
 try{$null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(45000)){$p.Kill();$p.WaitForExit();throw 'CITOOL_TIMEOUT'};if($p.ExitCode -ne 0){throw ('CiTool failed '+$p.ExitCode+': '+$e.Result.Trim())};return $o.Result}finally{$p.Dispose()}
}
function Get-AppIdPolicies {
 $data=Invoke-CiTool @('--list-policies','--json') | ConvertFrom-Json
 if(-not $data.PSObject.Properties['Policies']){throw 'Malformed CiTool policy inventory'}
 foreach($policy in @($data.Policies)){
  $id=([string]$policy.PolicyID).Trim('{}')
  if($id -notin @('3E5E5A48-7D87-49E0-A12A-CC2C17689A73','C0E85E51-F842-4969-BD74-36506B26A5B1')){continue}
  $path=Join-Path $env:SystemRoot ('System32\CodeIntegrity\CiPolicies\Active\{'+$id+'}.cip')
  $hash=if(Test-Path -LiteralPath $path){(Get-FileHash -LiteralPath $path).Hash}else{''}
  [pscustomobject]@{Id=$id;Name=[string]$policy.FriendlyName;Hash=$hash;Active=([string]$policy.IsEnforced -ieq 'True' -and [string]$policy.IsAuthorized -ieq 'True');OnDisk=([string]$policy.IsOnDisk -ieq 'True');Raw=$policy}
 }
}
function Assert-ActiveAppId($Configuration){
 if(-not $Configuration.AppIdRequired){return}
 $path=Join-Path (Get-GuardRoot) 'AppId-state.json'
 if(-not(Test-Path -LiteralPath $path)){throw 'APPID_STATE_MISSING: run automated AppID setup'}
 $state=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
 if($state.Machine -ne (Get-MachineBinding) -or $state.PackageFamily -ne $Configuration.PackageFamily -or [int]$state.ProxyPort -ne [int]$Configuration.ProxyPort){throw 'APPID_STATE_MISMATCH'}
 $policy=@(Get-AppIdPolicies | Where-Object {$_.Id -ieq $state.PolicyId})
 if($policy.Count -ne 1 -or -not $policy[0].Active -or $policy[0].Hash -ne $state.BinaryHash){throw 'APPID_NOT_ACTIVE_OR_CHANGED'}
}
function Invoke-PreflightWorker([guid]$RequestId){
 $root=Get-GuardRoot;$si=New-Object Diagnostics.ProcessStartInfo
 $si.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
 $si.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$root+'\Preflight.ps1" -RequestId '+$RequestId
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$si
 try{$null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(180000)){$p.Kill();$p.WaitForExit();throw 'PREFLIGHT_TIMEOUT: no launch approval'};if($p.ExitCode -ne 0){throw ('Preflight failed: '+$o.Result+$e.Result)}}finally{$p.Dispose()}
}
