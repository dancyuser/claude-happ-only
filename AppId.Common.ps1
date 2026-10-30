#requires -Version 5.1
function New-ClaudeAppIdXml([string]$PackageFamily){
 if($PackageFamily -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}_[0-9a-hjkmnp-tv-z]{13}$'){throw 'Invalid MSIX package family'}
 $family=[Security.SecurityElement]::Escape($PackageFamily)
 return @"
<?xml version="1.0" encoding="utf-8"?>
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy" PolicyType="AppID Tagging Policy">
  <VersionEx>1.0.0.0</VersionEx>
  <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID>
  <PolicyID>{3E5E5A48-7D87-49E0-A12A-CC2C17689A73}</PolicyID>
  <BasePolicyID>{3E5E5A48-7D87-49E0-A12A-CC2C17689A73}</BasePolicyID>
  <Rules>
    <Rule><Option>Enabled:Unsigned System Integrity Policy</Option></Rule>
    <Rule><Option>Enabled:Update Policy No Reboot</Option></Rule>
    <Rule><Option>Enabled:UMCI</Option></Rule>
    <Rule><Option>Enabled:Audit Mode</Option></Rule>
    <Rule><Option>Disabled:Script Enforcement</Option></Rule>
  </Rules>
  <EKUs/>
  <FileRules>
    <Allow ID="ID_ALLOW_CLAUDE_PFN" FriendlyName="Claude MSIX family" PackageFamilyName="$family" MinimumFileVersion="0.0.0.0"/>
    <Allow ID="ID_ALLOW_DLL" FriendlyName="DLL evaluation optimization" FilePath="*.dll" MinimumFileVersion="0.0.0.0"/>
  </FileRules>
  <Signers/>
  <SigningScenarios>
    <SigningScenario Value="12" ID="ID_SIGNINGSCENARIO_USERMODE">
      <ProductSigners><FileRulesRef><FileRuleRef RuleID="ID_ALLOW_CLAUDE_PFN"/><FileRuleRef RuleID="ID_ALLOW_DLL"/></FileRulesRef></ProductSigners>
      <AppIDTags><AppIDTag Key="ClaudeProxyOnly" Value="Protected"/></AppIDTags>
    </SigningScenario>
  </SigningScenarios>
  <UpdatePolicySigners/>
  <Settings>
    <Setting Provider="PolicyInfo" Key="Information" ValueName="Name"><Value><String>Claude-Happ-Only-AppId</String></Value></Setting>
    <Setting Provider="PolicyInfo" Key="Information" ValueName="Id"><Value><String>Claude Happ Only tagging v1</String></Value></Setting>
  </Settings>
</SiPolicy>
"@
}
