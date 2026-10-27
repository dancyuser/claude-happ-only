$ErrorActionPreference='Stop';. "$PSScriptRoot\..\Common.ps1"
$path='C:\Program Files\WindowsApps\Claude_TEST\app\resources\cowork-svc.exe'
$process=[pscustomobject]@{Name='cowork-svc.exe';ProcessId=1234;ExecutablePath=$null}
$service=[pscustomobject]@{Name='CoworkVMService';State='Running';StartName='LocalSystem';ProcessId=1234;PathName=('"'+$path+'"')}
if(-not(Test-VerifiedCoworkService $process @($service) @($path))){throw 'Registered SYSTEM service was rejected'}
foreach($change in @(@{Name='OtherService'},@{State='Stopped'},@{StartName='OtherUser'},@{ProcessId=9999},@{PathName='"C:\Other\cowork-svc.exe"'})){
 $copy=[pscustomobject]@{Name=$service.Name;State=$service.State;StartName=$service.StartName;ProcessId=$service.ProcessId;PathName=$service.PathName}
 foreach($key in $change.Keys){$copy.$key=$change[$key]}
 if(Test-VerifiedCoworkService $process @($copy) @($path)){throw ('Unverified service accepted: '+($change.Keys -join ','))}
}
$process.Name='claude.exe';if(Test-VerifiedCoworkService $process @($service) @($path)){throw 'Claude client was exempted'}
$process.Name='cowork-svc.exe';$process.ExecutablePath='C:\Other\cowork-svc.exe';if(Test-VerifiedCoworkService $process @($service) @($path)){throw 'Mismatched process executable accepted'}
'PASS: registered service accepted; wrong service/account/PID/path, stopped service and Claude client rejected.'
