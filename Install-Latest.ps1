#requires -Version 5.1
# Downloads the public release. No elevation/install occurs with -DownloadOnly.
[CmdletBinding()]param([switch]$DownloadOnly,[string]$CacheDirectory=(Join-Path $env:LOCALAPPDATA 'ClaudeHappOnly\Downloads\Releases'))
$ErrorActionPreference='Stop'
try{
 [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
 $headers=@{'User-Agent'='Claude-Happ-Only-Bootstrap';Accept='application/vnd.github+json'}
 $release=Invoke-RestMethod 'https://api.github.com/repos/dancyuser/claude-happ-only/releases/latest' -Headers $headers
 if($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v?\d+\.\d+\.\d+$'){throw 'Expected a stable installer release'}
 $assets=@($release.assets | Where-Object name -eq 'Claude-Happ-Universal.zip')
 if($assets.Count -ne 1 -or [string]$assets[0].digest -notmatch '^sha256:([a-fA-F0-9]{64})$'){throw 'Release ZIP with GitHub SHA256 digest missing'}
 $expected=$matches[1].ToUpperInvariant();$uri=[Uri]$assets[0].browser_download_url
 if($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or -not $uri.AbsolutePath.StartsWith('/dancyuser/claude-happ-only/releases/download/')){throw 'Unexpected installer download host/path'}
 $CacheDirectory=[IO.Path]::GetFullPath($CacheDirectory);New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
 $zip=Join-Path $CacheDirectory ('Claude-Happ-'+$release.tag_name+'.zip');$pending=Join-Path $CacheDirectory ([Guid]::NewGuid().ToString('N')+'.download')
 try{Invoke-WebRequest -Uri $uri.AbsoluteUri -Headers $headers -OutFile $pending -UseBasicParsing;if((Get-FileHash -LiteralPath $pending).Hash -ne $expected){throw 'Release ZIP checksum mismatch'};Move-Item -LiteralPath $pending -Destination $zip -Force}finally{if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending -Force}}
 $extract=Join-Path $CacheDirectory ('unpacked-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $extract | Out-Null
 Add-Type -AssemblyName System.IO.Compression.FileSystem;$archive=[IO.Compression.ZipFile]::OpenRead($zip)
 try{foreach($entry in $archive.Entries){$dest=[IO.Path]::GetFullPath((Join-Path $extract $entry.FullName));if(-not $dest.StartsWith($extract+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe ZIP entry'}}}finally{$archive.Dispose()}
 Expand-Archive -LiteralPath $zip -DestinationPath $extract
 $setup=Join-Path $extract 'claude-happ-only\Setup.ps1';if(-not(Test-Path -LiteralPath $setup)){throw 'Setup missing in release'}
 @{Version=$release.tag_name;SHA256=$expected;DigestMatched=$true;Extracted=$extract;SetupExecuted=$false;CheckedUTC=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $CacheDirectory 'verified-release.json') -Encoding UTF8
 Write-Host ('VERIFIED: '+$release.tag_name+'; '+$setup)
 if($DownloadOnly){Write-Host 'Download only; setup NOT executed.';exit 0}
 & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $setup
 exit $LASTEXITCODE
}catch{Write-Host ('INSTALLER NOT RUN: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
