#requires -Version 5.1
# Offline generation/compilation only: never calls CiTool or activates a policy.
[CmdletBinding()]param([string]$PackageFamily='Claude_pzs8sxrjxfjjc',[string]$OutputDirectory,[switch]$InstallCompiler)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop'){throw 'Use Windows PowerShell 5.1, powershell.exe'}
. "$PSScriptRoot\AppId.Common.ps1"
$xml=New-ClaudeAppIdXml $PackageFamily
if($InstallCompiler){$null=& "$PSScriptRoot\Install-ConfigCI.ps1" -Mode Install}
Import-Module ConfigCI -ErrorAction Stop
$null=Get-Command ConvertFrom-CIPolicy -ErrorAction Stop
if(-not $OutputDirectory){$OutputDirectory=Join-Path $env:LOCALAPPDATA ('ClaudeHappOnly\AppIdPrepared\'+[guid]::NewGuid().ToString('N'))}
$out=(New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop).FullName
$xmlPath=Join-Path $out 'Claude-Happ-Only-AppId.xml'
$binary=Join-Path $out '{3E5E5A48-7D87-49E0-A12A-CC2C17689A73}.cip'
[IO.File]::WriteAllText($xmlPath,$xml,[Text.UTF8Encoding]::new($false))
ConvertFrom-CIPolicy -XmlFilePath $xmlPath -BinaryFilePath $binary | Out-Null
if(-not(Test-Path -LiteralPath $binary) -or (Get-Item $binary).Length -lt 100){throw 'Policy compilation failed'}
$result=[pscustomobject]@{Prepared=$true;Applied=$false;PolicyID='{3E5E5A48-7D87-49E0-A12A-CC2C17689A73}';PolicyType='AppID Tagging Policy';PackageFamily=$PackageFamily;Xml=$xmlPath;Binary=$binary;XmlSHA256=(Get-FileHash $xmlPath).Hash;BinarySHA256=(Get-FileHash $binary).Hash;ClaudeLaunched=$false;NextStep='Read APPID-ru.md before manual CiTool installation; existing policies are not replaced automatically'}
$result | ConvertTo-Json | Set-Content (Join-Path $out 'prepared.json') -Encoding UTF8
return $result
