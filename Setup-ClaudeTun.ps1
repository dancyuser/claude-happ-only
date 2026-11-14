#requires -Version 5.1
[CmdletBinding()]param([guid]$InterfaceGuid=[guid]::Empty,[string]$ClaudeExecutable,[switch]$Preview)
$ErrorActionPreference='Stop'
& "$PSScriptRoot\Initialize-Payload.ps1"
. "$PSScriptRoot\Common.ps1";. "$PSScriptRoot\Universal.Common.ps1"
try{
 if($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell 5.1'}
 if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Start as the ordinary user; setup requests UAC itself'}
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $packages=@(Get-AppxPackage -Name Claude -ErrorAction Stop)
 $desktop=if($ClaudeExecutable){[IO.Path]::GetFullPath($ClaudeExecutable)}else{$latest=@($packages|Sort-Object Version -Descending|Select-Object -First 1);if($latest.Count){Join-Path $latest[0].InstallLocation 'app\claude.exe'}else{''}}
 if(-not $desktop -or [IO.Path]::GetFileName($desktop) -ine 'claude.exe' -or -not(Test-Path -LiteralPath $desktop -PathType Leaf)){throw 'Claude Desktop executable not found; pass -ClaudeExecutable explicitly'}
 $files=@();foreach($package in $packages){$files+=@(Get-ChildItem -LiteralPath $package.InstallLocation -Filter '*.exe' -File -Recurse|Select-Object -ExpandProperty FullName)}
 if($ClaudeExecutable){$rootPath=Split-Path ([IO.Path]::GetFullPath($ClaudeExecutable)) -Parent;$files+=@(Get-ChildItem -LiteralPath $rootPath -Filter '*.exe' -File -Recurse|Select-Object -ExpandProperty FullName)}
 if(-not $files.Count){throw 'Claude not found. Install Claude first or pass -ClaudeExecutable with the standalone claude.exe path'}
 foreach($package in $packages){
  $cache=Join-Path $env:LOCALAPPDATA ('Claude-Data\'+$package.PackageFamilyName+'\claude-code')
  if(Test-Path -LiteralPath $cache){$files+=@(Get-CodeCacheExecutables $cache|Select-Object -ExpandProperty FullName)}
 }
 $cli=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local\bin\claude.exe'
 if(Test-Path -LiteralPath $cli){$exact=Get-StandaloneCliExecutable $cli;if($exact){$files+=@($exact)}}
 $files=@($files|Sort-Object -Unique)
 $adapters=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
 $choices=@($adapters|Where-Object {-not $_.HardwareInterface -and $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch '^WAN Miniport' -and ($_.InterfaceDescription -match 'Tunnel|TUN' -or $_.Name -match 'Happ|VPN|TUN|FlClash|Snow')})
 if($InterfaceGuid -eq [guid]::Empty){
  $happ=@($choices|Where-Object {$_.InterfaceDescription -eq 'Happ Tunnel'})
  if($happ.Count -eq 1){$InterfaceGuid=[guid]$happ[0].InterfaceGuid}
  elseif($choices.Count -eq 1){$InterfaceGuid=[guid]$choices[0].InterfaceGuid}
  else{
   if($Preview){throw 'No unique active TUN. Connect VPN and pass -InterfaceGuid explicitly'}
   for($i=0;$i -lt $choices.Count;$i++){Write-Host (($i+1).ToString()+') '+$choices[$i].Name+' | '+$choices[$i].InterfaceDescription)}
   $pick=0;if(-not [int]::TryParse((Read-Host 'Select TUN number'),[ref]$pick) -or $pick -lt 1 -or $pick -gt $choices.Count){throw 'Select an active virtual VPN interface'}
   $InterfaceGuid=[guid]$choices[$pick-1].InterfaceGuid
  }
 }
 $found=@($adapters|Where-Object {[guid]$_.InterfaceGuid -eq $InterfaceGuid})
 if($found.Count -ne 1 -or $found[0].HardwareInterface -or $found[0].Status -ne 'Up'){throw 'The selected virtual TUN must be present and Up'};$tun=$found[0]
 $profileId=[guid]::NewGuid().ToString()
 $existing=@(Get-ChildItem (Join-Path (Get-UniversalRoot) 'Profiles') -Directory -ErrorAction SilentlyContinue|ForEach-Object {if(Test-Path "$($_.FullName)\config.json"){Get-Content "$($_.FullName)\config.json" -Raw|ConvertFrom-Json}}|Where-Object {$_.Name -eq 'Claude TUN Only' -and $_.LaunchUserSid -eq $sid})
 if($existing.Count -gt 1){throw 'Multiple Claude TUN profiles found; update the chosen profile explicitly'}
 if($existing.Count -eq 1){$profileId=$existing[0].ProfileId}
 $c=New-ClaudeTunProfile $files $InterfaceGuid $sid ([guid]$profileId) $desktop
 if($Preview){$c|ConvertTo-Json -Depth 12;exit 0}
 Assert-NoClaudeClient
 Write-Host ('TUN: '+$tun.Name+' | '+$tun.InterfaceDescription+' | GUID='+$InterfaceGuid)
 Write-Host ('Local TUN IPv4: '+((@(Get-NetIPAddress -InterfaceIndex $tun.ifIndex -AddressFamily IPv4).IPAddress) -join ', '))
 Write-Host ('Claude executable paths: '+$files.Count);foreach($file in $files){Write-Host ('  '+$file)}
 Write-Host 'Claude is locked to this TUN. IPv6 and connections through other interfaces are blocked. No VPN server IP is required.'
 Write-Host 'VPN routing inside a still-active TUN remains controlled by the VPN. Select the intended VPN route there.'
 if((Read-Host 'Install this Claude TUN protection? y/N') -notmatch '^(?i:y|yes)$'){throw 'Setup cancelled'}
 $configDir=Join-Path $env:LOCALAPPDATA 'UniversalNetworkGuard\Profiles';Assert-UniversalPlainPath $configDir;New-Item -ItemType Directory -Path $configDir -Force|Out-Null
 $configPath=Join-Path $configDir ($c.ProfileId+'.json');$c|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $configPath -Encoding UTF8
 & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Universal-Guard.ps1" -Mode Install -ConfigurationFile $configPath
 exit $LASTEXITCODE
}catch{Write-Host ('CLAUDE TUN SETUP FAILED: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
