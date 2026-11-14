#requires -Version 5.1
# Compile the reviewed WFP source as the ordinary user, before requesting UAC.
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'Universal.Wfp.cs'
$manifest=Get-Content "$PSScriptRoot\payload-hashes.json" -Raw|ConvertFrom-Json
$entry=@($manifest|Where-Object Name -eq 'Universal.Wfp.cs')
if($entry.Count -ne 1 -or (Get-FileHash -LiteralPath $source).Hash -ne $entry[0].SHA256){throw 'WFP source checksum mismatch'}
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $compiler -PathType Leaf)){throw 'Windows .NET Framework x64 compiler required'}
$build=Join-Path $env:TEMP ('UniversalGuardEngine-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $build|Out-Null
$library=Join-Path $build 'Universal.Engine.dll'
$messages=& $compiler /nologo /target:library ('/out:'+$library) $source 2>&1
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $library -PathType Leaf)){throw ('WFP engine compilation failed: '+($messages -join ' '))}
[pscustomobject]@{Path=$library;SHA256=(Get-FileHash -LiteralPath $library).Hash;SourceSHA256=$entry[0].SHA256}
