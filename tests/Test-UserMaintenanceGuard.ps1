#requires -Version 5.1
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\Common.ps1"
$script:fixtureProcesses=@([pscustomobject]@{ProcessName='cowork-svc';Id=1234})
function Get-Process {param($ErrorAction);return $script:fixtureProcesses}
function Get-CimInstance {throw 'Unelevated client check must not use CIM'}
function Get-AppxPackage {throw 'Unelevated client check must not query packages'}
Assert-NoClaudeClient
$script:fixtureProcesses+= [pscustomobject]@{ProcessName='claude';Id=5678}
$refused=$false;try{Assert-NoClaudeClient}catch{if($_.Exception.Message -match '5678'){$refused=$true}else{throw}}
if(-not $refused){throw 'Running Claude client was not rejected'}
'PASS: user check accepts background service alone, rejects client, and does not query CIM/Appx.'
