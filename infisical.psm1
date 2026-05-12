#!/usr/bin/env pwsh
using namespace System
using namespace System.IO
using namespace System.Web
using namespace System.Text
using namespace System.Net.Http
using namespace System.Reflection
using namespace System.Threading.Tasks
# Load all sub-modules :
# (Get-ChildItem ./Private).Name.ForEach({ "using module Private/" + $_ })

using module Private/Enums.psm1
using module Private/Exceptions.psm1
using module Private/Model.psm1
using module Private/Api.psm1
using module Private/Util.psm1
using module Private/Client.psm1

#Requires -PSEdition Core
#Requires -Modules PsModuleBase, cliHelper.env, clihelper.xconvert

#region    Classes

# .SYNOPSIS
#  Main class of the module
class InfisicalClient {
  hidden [ApiClient] $_apiClient
  hidden [AuthClient] $_authClient
  hidden [SecretsClient] $_secretsClient
  hidden [PkiClient] $_pkiClient

  InfisicalClient([InfisicalSdkSettings]$settings) {
    $this._apiClient = [ApiClient]::new($settings.HostUri)
    $this._secretsClient = [SecretsClient]::new($this._apiClient)
    $this._authClient = [AuthClient]::new($this._apiClient, { param($accessToken) $this._apiClient.SetAccessToken($accessToken) })
    $this._pkiClient = [PkiClient]::new($this._apiClient)
  }

  [AuthClient] Auth() {
    return $this._authClient
  }

  [SecretsClient] Secrets() {
    return $this._secretsClient
  }

  [PkiClient] Pki() {
    return $this._pkiClient
  }
}


# .SYNOPSIS
#  CLASS used in the public function Invoke-InfisicalCli
# .DESCRIPTION
#  Main entry class. has convinience static methods that makes it easy to use many features of thew module.
class Infisical {
  static [Type[]] $ReturnTypes = ([Infisical]::Methods.ReturnType | Sort-Object -Unique Name)
  static [MethodInfo[]] $Methods = ([Infisical].GetMethods().Where({ $_.IsStatic -and !$_.IsHideBySig }))

  static [string] GetHelp() {
    return [PsModuleBase]::ReadModuledata("infisical")["HelpMessage"]
  }
}
#endregion Classes

# Types that will be available to users when they import the module.
# Hint: To automatically generate typestoexport variable you can use this one liner to generate types to export variable
# (Get-ChildItem *.psm1 -Recurse -File | ForEach-Object { [IO.File]::ReadAllLines((Get-Item $_.FullName)).Where({ $_.StartsWith("class") -or $_.StartsWith("enum ") }).ForEach({ $_.Replace("class ", '[').Replace("enum ", '[') }).ForEach({ ($_ -like "* : *") ? $_.split(" : ")[0] + ']' : $_.Replace(' {', ']') }) }) -join ', '

$typestoExport = @(
  [ApiClient], [QueryBuilder], [UniversalAuth], [LdapAuth], [AuthClient], [Subscribers], [PkiClient], [SecretsClient], [SecretType], [InfisicalAuthMethod], [InfisicalException], [MachineIdentityCredential], [UniversalAuthLoginRequest], [LdapAuthLoginRequest], [ListSecretsOptions], [GetSecretOptions], [SecretMetadata],
  [CreateSecretOptions], [UpdateSecretOptions], [DeleteSecretOptions], [IssueCertificateOptions], [SubscriberIssuedCertificate], [RetrieveLatestCertificateBundleOptions], [CertificateBundle], [InfisicalSecret], [SecretImport], [ListSecretsResponse], [GetSecretResponse], [CreateSecretResponse], [UpdateSecretResponse],
  [DeleteSecretResponse], [InfisicalUniversalAuth], [InfisicalTokenAuth], [InfisicalAuth], [InfisicalSdkSettings], [InfisicalSdkSettingsBuilder], [ObjectToDictionaryConverter], [SecretsUtil], [InfisicalClient], [Infisical]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  try {
    [void]$TypeAcceleratorsClass::Add($Type.FullName, $Type)
  } catch {
    # Ignore if already exists
    $null
  }
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
