#requires -Version 5.1
$ErrorActionPreference='Stop';. "$PSScriptRoot\..\AppId.Common.ps1"
[xml]$xml=New-ClaudeAppIdXml 'Claude_pzs8sxrjxfjjc'
$ns=New-Object Xml.XmlNamespaceManager($xml.NameTable);$ns.AddNamespace('s','urn:schemas-microsoft-com:sipolicy')
if($xml.DocumentElement.GetAttribute('PolicyType') -ne 'AppID Tagging Policy'){throw 'Unexpected policy type'}
if($xml.SelectNodes('//s:Allow',$ns).Count -ne 2 -or $xml.SelectNodes('//s:Deny',$ns).Count -ne 0){throw 'Unexpected policy scope'}
$tag=$xml.SelectSingleNode('//s:AppIDTag',$ns)
if($tag.GetAttribute('Key') -ne 'ClaudeProxyOnly' -or $tag.GetAttribute('Value') -ne 'Protected'){throw 'Tag mismatch'}
$rule=$xml.SelectSingleNode('//s:Allow[@ID="ID_ALLOW_CLAUDE_PFN"]',$ns)
if($rule.GetAttribute('PackageFamilyName') -ne 'Claude_pzs8sxrjxfjjc' -or $rule.HasAttribute('FilePath')){throw 'PFN rule broadened'}
if(-not $xml.SelectSingleNode('//s:Option[text()="Enabled:Audit Mode"]',$ns)){throw 'Audit option missing'}
foreach($bad in @('*','bad_family','Claude_pzs8sxrjxfjjc"/><Allow FilePath="*')){$rejected=$false;try{$null=New-ClaudeAppIdXml $bad}catch{$rejected=$true};if(-not $rejected){throw 'Invalid/injected family accepted'}}
Add-Type -Path "$PSScriptRoot\..\AppIdTokenReader.cs"
$flags=[Reflection.BindingFlags]::NonPublic
$sizeMethod=[Runtime.InteropServices.Marshal].GetMethod('SizeOf',[type[]]@([type]))
foreach($pair in @(@('Info',16),@('Unicode',16),@('Attribute',40))){$type=[ReadAppIdToken].GetNestedType($pair[0],$flags);if($sizeMethod.Invoke($null,[object[]]@($type)) -ne $pair[1]){throw 'x64 token ABI layout mismatch'}}
foreach($type in @([HappOnlyWfp],[GuardWfpSnapshot])){if(-not $type.GetMethod('RestrictTag',[type[]]@([int],[bool])) -or -not $type.GetMethod('RestrictTag',[type[]]@([bool]))){throw 'Tag-port API/backward compatibility missing'}}
'PASS: AppID-only narrow PFN XML, invalid input rejection, read-only token ABI and legacy/custom-port API compatibility. No policy activation.'
