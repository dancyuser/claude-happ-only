#requires -Version 5.1
# Registers an existing signed Microsoft Windows component for CurrentUser only.
# Never downloads DLLs, applies policies, changes Windows features or launches Claude.
[CmdletBinding()]param([ValidateSet('Check','Install')][string]$Mode='Check')
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell 5.1: powershell.exe -File Install-ConfigCI.ps1'}
. "$PSScriptRoot\CodeProxy.Common.ps1"
function Assert-MicrosoftConfigCI([string]$Directory){
 $dll=Join-Path $Directory 'Microsoft.ConfigCI.Commands.dll'
 $signature=Get-AuthenticodeSignature -LiteralPath $dll
 if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Windows, O=Microsoft Corporation'){throw 'ConfigCI DLL is not a verified Microsoft Windows component'}
 if(-not(Test-Path -LiteralPath (Join-Path $Directory 'ConfigCI.psd1'))){throw 'Native module manifest missing'}
 return $dll
}
$existing=Get-Module -ListAvailable -Name ConfigCI | Sort-Object Version -Descending | Select-Object -First 1
if($existing){
 $dll=Assert-MicrosoftConfigCI $existing.ModuleBase
 Import-Module $existing.Path -ErrorAction Stop
 $null=Get-Command ConvertFrom-CIPolicy -ErrorAction Stop
 return [pscustomobject]@{Available=$true;AlreadyPresent=$true;ModulePath=$existing.ModuleBase;ComponentVersion=(Get-Item $dll).VersionInfo.FileVersion;PoliciesChanged=$false}
}
$candidates=@(Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'WinSxS') -Directory -Filter 'amd64_microsoft.configci.commands_31bf3856ad364e35_*' | Where-Object {$_.Name -match '_\d+\.\d+\.\d+\.\d+_none_'})
$candidates=@($candidates | Sort-Object {if($_.Name -match '_(\d+\.\d+\.\d+\.\d+)_none_'){[version]$matches[1]}else{[version]'0.0'}} -Descending)
$source=$null
foreach($candidate in $candidates){try{$null=Assert-MicrosoftConfigCI $candidate.FullName;$source=$candidate.FullName;break}catch{}}
if(-not $source){throw 'Signed inbox ConfigCI not found. Use Microsoft App Control Wizard; do not install a same-named third-party module or change Windows edition.'}
if($Mode -eq 'Check'){return [pscustomobject]@{Available=$false;SignedInboxSource=$source;NextStep='Install-ConfigCI.ps1 -Mode Install';PoliciesChanged=$false}}
$moduleRoot=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules\ConfigCI'
$destination=Join-Path $moduleRoot '1.0';Assert-CodeProxyPlainPath $destination
if(Test-Path -LiteralPath $destination){throw 'Target exists but is not discoverable; refusing overwrite. Inspect existing files.'}
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
$stage=Join-Path $moduleRoot ('.staging-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$files=@()
foreach($file in (Get-ChildItem -LiteralPath $source -File)){
 $target=Join-Path $stage $file.Name;Copy-Item -LiteralPath $file.FullName -Destination $target
 $hash=(Get-FileHash -LiteralPath $file.FullName).Hash
 if((Get-FileHash -LiteralPath $target).Hash -ne $hash){throw 'Copy checksum mismatch'}
 $files+=[pscustomobject]@{Name=$file.Name;SHA256=$hash}
}
# Both resolved directory paths must remain inside this explicitly named module root.
$allowed=[IO.Path]::GetFullPath($moduleRoot).TrimEnd('\')+'\'
foreach($path in @($stage,$destination)){if(-not [IO.Path]::GetFullPath($path).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Module move escaped target root'}}
Move-Item -LiteralPath $stage -Destination $destination
$dll=Assert-MicrosoftConfigCI $destination
Import-Module (Join-Path $destination 'ConfigCI.psd1') -ErrorAction Stop
$null=Get-Command ConvertFrom-CIPolicy -ErrorAction Stop
$receipt=[pscustomobject]@{Available=$true;Scope='CurrentUser';Module='ConfigCI';ComponentVersion=(Get-Item $dll).VersionInfo.FileVersion;Source=$source;ModulePath=$destination;Files=$files;PoliciesChanged=$false;ClaudeLaunched=$false}
$receipt | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $destination 'installation-receipt.json') -Encoding UTF8
return $receipt
