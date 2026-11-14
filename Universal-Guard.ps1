#requires -Version 5.1
# User-facing setup and maintenance. Does not execute protected applications.
[CmdletBinding()]param([ValidateSet('Setup','List','Install','Verify','Test','Restore')][string]$Mode='Setup',[string]$ConfigurationFile,[guid]$ProfileId,[guid]$BackupId,[switch]$Preview)
$ErrorActionPreference='Stop';. "$PSScriptRoot\Common.ps1";. "$PSScriptRoot\Universal.Common.ps1"
$temp=$null;$code=1
function Ask-U($Label,$Default){$v=Read-Host ($Label+$(if($Default){' ['+$Default+']'}));if([string]::IsNullOrWhiteSpace($v)){return $Default};return $v}
function Choose-UInterface($Label){
 $script:choices=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop|Sort-Object ifIndex)
 for($i=0;$i -lt $script:choices.Count;$i++){$a=$script:choices[$i];Write-Host (($i+1).ToString()+') '+$a.Name+' | '+$a.InterfaceDescription+' | '+$a.Status+' | GUID='+$a.InterfaceGuid)}
 $pick=0;if(-not [int]::TryParse((Read-Host $Label),[ref]$pick) -or $pick -lt 1 -or $pick -gt $script:choices.Count){throw 'Select one interface number; no interface guessed'}
 return ([guid]$script:choices[$pick-1].InterfaceGuid).ToString()
}
try{
 if($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell 5.1'}
 if($Mode -eq 'List'){
  Get-NetAdapter -IncludeHidden|Select-Object Name,InterfaceDescription,Status,InterfaceGuid,ifIndex
  Get-ChildItem (Join-Path (Get-UniversalRoot) 'Profiles') -Directory -ErrorAction SilentlyContinue|ForEach-Object {if(Test-Path "$($_.FullName)\config.json"){$c=Get-Content "$($_.FullName)\config.json" -Raw|ConvertFrom-Json;[pscustomobject]@{ProfileId=$c.ProfileId;Name=$c.Name;Mode=$c.Mode}}}
  exit 0
 }
 if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Start as the ordinary target user; this tool requests UAC'}
 if($Mode -eq 'Setup'){
  Write-Host 'Universal Windows network guard. Configure VPN/proxy externally first. This wizard does not launch applications.'
  $name=Ask-U 'Profile name' 'My network profile'
  $choice=Ask-U '1 = TUN + independent local proxy; 2 = TUN only with own interface kill switch' '1'
  if($choice -notin @('1','2')){throw 'Choose 1 or 2'}
  $files=@();do{$file=Read-Host 'Full protected EXE path (blank finishes list)';if($file){$files+=@($file.Trim('"'))}}while($file)
  $c=[pscustomobject]@{Schema=1;ProfileId=[guid]::NewGuid().ToString();Name=$name;Mode=$(if($choice -eq '1'){'TunProxy'}else{'TunOnly'});Programs=$files;ExpectedCountry=(Ask-U 'Expected exit country (two letters; - = accept any)' '-').ToUpperInvariant();AllowIPv6=$false}
  if($c.ExpectedCountry -eq '-'){$c.ExpectedCountry=''}
  if($c.Mode -eq 'TunOnly'){
   $c|Add-Member NoteProperty TunnelInterfaceGuid (Choose-UInterface 'Select the virtual TUN adapter')
   $c.AllowIPv6=((Ask-U 'Permit IPv6 through this TUN? y/N' 'N') -match '^[yY]')
   Write-Host 'Interface-only locks client connections to the selected TUN; no VPN server IP is needed.'
   Write-Host 'Optional core endpoint lock also affects every other application using that VPN core.'
   $strict=Ask-U '1 = interface + VPN core endpoint; 2 = interface only (VPN controls routing inside the TUN)' '2'
   if($strict -notin @('1','2')){throw 'Choose 1 or 2'}
   $c|Add-Member NoteProperty KillSwitchScope $(if($strict -eq '1'){'InterfaceAndCore'}else{'InterfaceOnly'})
   if($strict -eq '1'){
    $corePath=(Read-Host 'VPN network-core EXE path (not necessarily the GUI)').Trim('"')
    if(-not [IO.Path]::IsPathRooted($corePath) -or [IO.Path]::GetExtension($corePath) -ine '.exe' -or $corePath -match '[*?]' -or -not (Test-Path -LiteralPath $corePath -PathType Leaf)){throw 'Select the existing VPN network-core EXE'}
    $c|Add-Member NoteProperty VpnCore (Read-UniversalVpnEndpoint $corePath $c.TunnelInterfaceGuid)
   }
  }else{
   $c|Add-Member NoteProperty TransportInterfaceGuid (Choose-UInterface 'Select the underlying adapter for the independent proxy core (usually Ethernet/Wi-Fi)')
   $scheme=Ask-U 'Local proxy protocol: http or socks5h' 'http'
   $proxy=[pscustomobject]@{Address='127.0.0.1';Port=(Ask-U 'Local proxy port' '10808');Scheme=$scheme;Executable=((Read-Host 'Full EXE path of the process owning the proxy socket (network core)').Trim('"'));ServerAddress=(Read-Host 'Pinned proxy server IPv4/IPv6 address');ServerPort=(Ask-U 'Proxy server port' '443');ServerProtocol=(Ask-U 'Proxy upstream protocol: TCP or UDP' 'TCP').ToUpperInvariant()}
   $c|Add-Member NoteProperty Proxy $proxy
  }
  $c=ConvertTo-UniversalProfile $c
  if($Preview){$c|ConvertTo-Json -Depth 12;exit 0}
  $homeDir=Join-Path $env:LOCALAPPDATA 'UniversalNetworkGuard\Profiles';Assert-UniversalPlainPath $homeDir;New-Item -ItemType Directory $homeDir -Force|Out-Null
  $ConfigurationFile=Join-Path $homeDir ($c.ProfileId+'.json');$c|ConvertTo-Json -Depth 12|Set-Content $ConfigurationFile -Encoding UTF8
  Write-Host ('User configuration: '+$ConfigurationFile);$Mode='Install'
 }
 if($Mode -eq 'Install'){
  if(-not $ConfigurationFile){throw 'Install requires ConfigurationFile'}
  $c=ConvertTo-UniversalProfile (Get-Content -LiteralPath $ConfigurationFile -Raw|ConvertFrom-Json);$ProfileId=[guid]$c.ProfileId
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if($c.PSObject.Properties['LaunchUserSid'] -and $c.LaunchUserSid -ne $sid){throw 'Profile belongs to another user; use Setup on this PC'}
  $c|Add-Member NoteProperty LaunchUserSid $sid -Force
  $binding=Resolve-UniversalBinding $c @(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
  if($Preview){[pscustomobject]@{Profile=$c;Binding=$binding;Changes=$false;ApplicationsLaunched=$false}|ConvertTo-Json -Depth 14;exit 0}
  $temp=Join-Path $env:TEMP ('UniversalGuard-'+[guid]::NewGuid().ToString('N')+'.json');$c|ConvertTo-Json -Depth 14|Set-Content $temp -Encoding UTF8
 }else{
  if($ProfileId -eq [guid]::Empty){throw 'ProfileId required'}
  if($Preview){throw 'Preview is available for Setup or Install'}
 }
 $id=[guid]::NewGuid();$args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Universal.Worker.ps1" -Mode '+$Mode+' -ProfileId '+$ProfileId+' -RequestId '+$id
 $manifestPath=Join-Path $PSScriptRoot 'payload-hashes.json'
 if(Test-Path -LiteralPath $manifestPath){foreach($entry in (Get-Content $manifestPath -Raw|ConvertFrom-Json)){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $entry.Name)).Hash -ne $entry.SHA256){throw ('Source payload changed: '+$entry.Name)}}}
 if($Mode -eq 'Install'){
  $preparedEngine=& "$PSScriptRoot\Prepare-UniversalEngine.ps1"
  $args+=' -EngineLibrary "'+$preparedEngine.Path+'" -EngineSHA256 '+$preparedEngine.SHA256
 }
 if($temp){$args+=' -ConfigurationFile "'+$temp+'" -ConfigSHA256 '+(Get-FileHash $temp).Hash}
 if($Mode -eq 'Restore'){if($BackupId -eq [guid]::Empty){throw 'Restore requires a BackupId listed in the installation report'};$args+=' -BackupId '+$BackupId}
 Write-Host 'UAC: scoped network profile maintenance/test only. Protected applications are not launched.'
 $code=Invoke-ElevatedPowerShell $args
 $resultPath=Join-Path (Get-UniversalRoot) ('Reports\'+$id+'\result.json')
 if(-not(Test-Path -LiteralPath $resultPath)){throw ('Administrative worker ended without a report (exit '+$code+'). Restrictions may already be installed. Review antivirus/system event history before retrying.')}
 Write-Host ('Report: '+$resultPath)
 if($Mode -eq 'Install' -and $code -eq 0){
  Write-Host ('Profile installed and tested. ProfileId='+$ProfileId)
  try{
   $shortcutName=if($c.Name -eq 'Claude TUN Only'){'Claude - TUN Only.lnk'}else{'Network Guard - '+$ProfileId+'.lnk'}
   $shortcutPath=Join-Path ([Environment]::GetFolderPath('Desktop')) $shortcutName
   $shell=New-Object -ComObject WScript.Shell;$shortcut=$shell.CreateShortcut($shortcutPath)
   $target="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
   $profileRoot=Join-Path (Get-UniversalRoot) ('Profiles\'+$ProfileId)
   $launchArguments='-NoProfile -ExecutionPolicy Bypass -File "'+$profileRoot+'\Start-Universal.ps1" -ProfileId '+$ProfileId
   if((Test-Path -LiteralPath $shortcutPath) -and ($shortcut.TargetPath -ine $target -or $shortcut.Arguments -cne $launchArguments)){throw 'Existing unrelated shortcut preserved'}
   $shortcut.TargetPath=$target;$shortcut.Arguments=$launchArguments;$shortcut.WorkingDirectory=$profileRoot;$shortcut.Description=$c.Name+' - network test, then explicit user launch';$shortcut.Save()
   Write-Host ('Checked-launch shortcut: '+$shortcutPath)
  }catch{Write-Warning ('Profile installed/tested; shortcut not created: '+$_.Exception.Message)}
 }
}catch{Write-Host ('UNIVERSAL GUARD INCOMPLETE: '+$_.Exception.Message) -ForegroundColor Red;$code=1}
finally{if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Force}}
exit $code
