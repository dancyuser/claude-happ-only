#requires -Version 5.1
# File inventory fixture only; the .exe files contain plain text and are never run.
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\Common.ps1"
$fixture=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ('Happ-Inventory-Fixture-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $fixture 'app';$cache=Join-Path $fixture 'claude-code'
New-Item -ItemType Directory -Path $app,(Join-Path $cache 'v1\hash'),(Join-Path $cache 'v2\hash') | Out-Null
foreach($name in @('app\claude.exe','claude-code\v1\hash\claude.exe','claude-code\v2\hash\claude.exe','claude-code\notes.txt')){[IO.File]::WriteAllText((Join-Path $fixture $name),'NONEXECUTABLE INVENTORY FIXTURE')}
$config=[pscustomobject]@{ClaudeRoot=$app;ClaudeExe=(Join-Path $app 'claude.exe');CodeRoot=$cache}
$inventory=Get-ClaudeInventory $config
if($inventory.Files.Count -ne 3 -or $inventory.Executable -ne $config.ClaudeExe){throw 'Cache inventory changed launch target or omitted Code versions'}
$config.CodeRoot=Join-Path $fixture 'missing\claude-code'
if((Get-ClaudeInventory $config).Files.Count -ne 1){throw 'Absent cache rejected'}
$rejected=$false;try{$null=Get-CodeCacheExecutables $fixture}catch{$rejected=$true}
if(-not $rejected){throw 'Broad non-cache root accepted'}
'PASS: both cached Code versions included, launch target unchanged, absent cache supported, broad root rejected; no EXEs executed.'
Write-Host ('Inventory fixture retained: '+$fixture)
