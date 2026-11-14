#requires -Version 5.1
param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
& "$PSScriptRoot\Initialize-Payload.ps1"
$files=@(& git -C $PSScriptRoot ls-files --cached --others --exclude-standard)
if($LASTEXITCODE -ne 0){throw 'Cannot enumerate source files'}
$files=@($files|Sort-Object -Unique)
$stage=Join-Path $env:TEMP ('ClaudeHappPackage-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $stage 'claude-happ-only';New-Item -ItemType Directory -Path $package -Force|Out-Null
foreach($relative in $files){$target=Join-Path $package $relative;New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relative) -Destination $target}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$zip=Join-Path $OutputDirectory 'Claude-Happ-Universal.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
if(Test-Path -LiteralPath $zip){[IO.File]::Delete($zip)}
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($relative in $files){$entry='claude-happ-only/'+$relative.Replace('\','/');$null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $package $relative),$entry,[IO.Compression.CompressionLevel]::Optimal)}}finally{$archive.Dispose()}
$hash=(Get-FileHash -LiteralPath $zip).Hash
($hash+'  Claude-Happ-Universal.zip')|Set-Content (Join-Path $OutputDirectory 'Claude-Happ-Universal.zip.sha256') -Encoding ASCII
[pscustomobject]@{Path=$zip;SHA256=$hash;Files=$files.Count}
