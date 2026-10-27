#requires -Version 5.1
[CmdletBinding()]param(
 [ValidatePattern('^(latest|v?\d+\.\d+\.\d+)$')][string]$Version='latest',
 [ValidateSet('Install','DownloadOnly','VerifyOnly')][string]$Mode='Install',
 [string]$CacheDirectory=(Join-Path $env:LOCALAPPDATA 'ClaudeHappOnly\Downloads\BrowserTamer')
)
$ErrorActionPreference='Stop'
try{
 if(-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){throw 'Windows x64 required; ARM64 is unsupported'}
 [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
 $api='https://api.github.com/repos/aloneguid/bt/releases/latest';if($Version -ne 'latest'){$api='https://api.github.com/repos/aloneguid/bt/releases/tags/'+[Uri]::EscapeDataString($Version)}
 $headers=@{'User-Agent'='Claude-Happ-Only-Installer';Accept='application/vnd.github+json'};$release=Invoke-RestMethod -Uri $api -Headers $headers
 if($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v?(\d+\.\d+\.\d+)$'){throw 'Unsupported upstream release'}
 $number=$matches[1];$name='BrowserTamer-'+$number+'-win64.msi';$assets=@($release.assets | Where-Object name -eq $name)
 if($assets.Count -ne 1 -or [string]$assets[0].digest -notmatch '^sha256:([a-fA-F0-9]{64})$'){throw 'One Windows x64 MSI with a GitHub SHA256 digest is required'}
 $expected=$matches[1].ToUpperInvariant();$uri=[Uri]$assets[0].browser_download_url
 if($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or -not $uri.AbsolutePath.StartsWith('/aloneguid/bt/releases/download/')){throw 'Unexpected upstream download host/path'}
 $CacheDirectory=[IO.Path]::GetFullPath($CacheDirectory);New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null;$path=Join-Path $CacheDirectory $name
 $cached=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $expected)
 if(-not $cached){
  if($Mode -eq 'VerifyOnly'){throw 'Verified cached MSI absent; use DownloadOnly first'}
  $pending=Join-Path $CacheDirectory ([Guid]::NewGuid().ToString('N')+'.download')
  try{Invoke-WebRequest -Uri $uri.AbsoluteUri -Headers $headers -OutFile $pending -UseBasicParsing;if((Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash -ne $expected){throw 'MSI checksum mismatch'};Move-Item -LiteralPath $pending -Destination $path -Force}finally{if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending -Force}}
 }
 $sig=Get-AuthenticodeSignature -LiteralPath $path
 $record=[ordered]@{Repository='aloneguid/bt';Version=$release.tag_name;ReleaseURL=$release.html_url;SHA256=$expected;DigestMatched=$true;AuthenticodeStatus=[string]$sig.Status;InstallerExecuted=$false;File=$path;CheckedUTC=[DateTime]::UtcNow.ToString('o')}
 $record | ConvertTo-Json | Set-Content (Join-Path $CacheDirectory 'verified-release.json') -Encoding UTF8
 Write-Host ('VERIFIED: Browser Tamer '+$release.tag_name+'; SHA256='+$expected+'; signature='+$sig.Status)
 if($Mode -ne 'Install'){Write-Host ('Installer NOT executed. '+$path);exit 0}
 Write-Host 'Opening official MSI. Browser default/profile rules and proxy extensions are not changed by this script.'
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=Join-Path $env:SystemRoot 'System32\msiexec.exe';$info.Arguments='/i "'+$path+'" /norestart';$info.UseShellExecute=$true;$info.Verb='runas'
 $process=[Diagnostics.Process]::Start($info);$null=$process.Handle;$process.WaitForExit();$code=$process.ExitCode;$process.Dispose()
 if($code -notin @(0,3010)){throw ('MSI did not finish successfully, code '+$code)}
 $record.InstallerExecuted=$true;$record['MsiExitCode']=$code;$record | ConvertTo-Json | Set-Content (Join-Path $CacheDirectory 'verified-release.json') -Encoding UTF8
 if($code -eq 3010){Write-Host 'Windows reports a reboot may be needed; no reboot is performed.'};exit 0
}catch{Write-Host ('BROWSER TAMER NOT INSTALLED: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
