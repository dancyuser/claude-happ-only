#requires -Version 5.1
# GitHub source ZIPs may use LF while the Windows payload is hashed as CRLF.
# Repair only that exact difference; never accept arbitrary changed content.
$ErrorActionPreference='Stop'
$manifest=Get-Content "$PSScriptRoot\payload-hashes.json" -Raw|ConvertFrom-Json
foreach($entry in $manifest){
 if($entry.Name -notmatch '^[A-Za-z0-9_.-]+$' -or $entry.SHA256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Invalid payload manifest entry'}
 $path=Join-Path $PSScriptRoot $entry.Name
 $item=Get-Item -LiteralPath $path -ErrorAction Stop
 if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in payload'}
 if((Get-FileHash -LiteralPath $path).Hash -eq $entry.SHA256){continue}
 if($item.Extension -notin @('.ps1','.cmd','.cs','.json')){throw ('Payload changed: '+$entry.Name)}
 $bytes=[IO.File]::ReadAllBytes($path);$bom=($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
 $encoding=New-Object Text.UTF8Encoding($bom)
 $text=[IO.File]::ReadAllText($path) -replace '\r?\n',"`r`n"
 [byte[]]$candidate=@($encoding.GetPreamble())+@($encoding.GetBytes($text))
 $sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash($candidate))).Replace('-','')}finally{$sha.Dispose()}
 if($hash -ne $entry.SHA256){throw ('Payload changed beyond line endings: '+$entry.Name)}
 [IO.File]::WriteAllBytes($path,$candidate)
}
