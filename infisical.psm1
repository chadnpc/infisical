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
#Requires -Modules PsModuleBase, cliHelper.env, clihelper.xconvert, clihelper.logger, argparser

#region    Classes

# .SYNOPSIS
#  Main class of the module
class InfisicalClient {
  hidden [ApiClient] $_apiClient
  hidden [AuthClient] $_authClient
  hidden [SecretsClient] $_secretsClient
  hidden [PkiClient] $_pkiClient
  hidden [IdentitiesClient] $_identitiesClient
  hidden [KmsClient] $_kmsClient

  InfisicalClient([InfisicalSdkSettings]$settings) {
    $this._apiClient = [ApiClient]::new($settings.HostUri)
    $this._secretsClient = [SecretsClient]::new($this._apiClient)
    $this._authClient = [AuthClient]::new($this._apiClient, { param($accessToken) $this._apiClient.SetAccessToken($accessToken) })
    $this._pkiClient = [PkiClient]::new($this._apiClient)
    $this._identitiesClient = [IdentitiesClient]::new($this._apiClient)
    $this._kmsClient = [KmsClient]::new($this._apiClient)
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

  [IdentitiesClient] Identities() {
    return $this._identitiesClient
  }

  [KmsClient] Kms() {
    return $this._kmsClient
  }
}


# .SYNOPSIS
#  CLASS used in the public function Invoke-InfisicalCli
# .DESCRIPTION
#  Main entry class. has convinience static methods that makes it easy to use many features of thew module.
class Infisical {
  static [Type[]] $ReturnTypes = ([Infisical]::Methods.ReturnType | Sort-Object -Unique Name)
  static [MethodInfo[]] $Methods = ([Infisical].GetMethods().Where({ $_.IsStatic -and !$_.IsHideBySig }))
  #region CLI Engine
  static [InfisicalClient] GetClient([string]$domain, [string]$token) {
    $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri($domain).Build()
    $client = [InfisicalClient]::new($settings)
    if (![string]::IsNullOrEmpty($token)) {
      $client._apiClient.SetAccessToken($token)
    } elseif (![string]::IsNullOrEmpty($env:INFISICAL_TOKEN)) {
      $client._apiClient.SetAccessToken($env:INFISICAL_TOKEN)
    }
    return $client
  }

  static [void] Run([string[]]$InputArgs) {
    if ($InputArgs.Count -eq 0) {
      Write-Host ([Infisical]::WriteBanner()) -ForegroundColor Cyan
      Write-Host "Usage: infisical <command> [subcommand] [options]"
      return
    }

    $command = $InputArgs[0]
    $subArgs = @()
    if ($InputArgs.Count -gt 1) {
      $subArgs = $InputArgs[1..($InputArgs.Count - 1)]
    }

    try {
      switch ($command) {
        "login" { [Infisical]::RunLogin($subArgs); break }
        "secrets" { [Infisical]::RunSecrets($subArgs); break }
        "export" { [Infisical]::RunExport($subArgs); break }
        "help" { [Infisical]::ShowHelp(); break }
        "version" { [Infisical]::ShowVersion(); break }
        "upgrade" { [Infisical]::UpdateModule(); break }
        "events" {
          $params = ConvertTo-Params $subArgs -schema @{
            id    = [string], $null
            limit = [int], 20
            output = [string], 'table'
          }
          Write-Host ([Infisical]::GetEvent($params.id.Value, $params.limit.Value, $params.output.Value))
          break
        }
        default {
          [Infisical]::ShowHelp()
          break
        }
      }
    } catch {
      Write-Error "Execution failed: $_"
    }
  }

  static [void] RunLogin([string[]]$args) {
    $params = ConvertTo-Params $args -schema @{
      method = [string], 'user'
      domain = [string], 'https://app.infisical.com'
      'client-id' = [string], $env:INFISICAL_UNIVERSAL_AUTH_CLIENT_ID
      'client-secret' = [string], $env:INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET
      email = [string], $env:INFISICAL_EMAIL
      password = [string], $env:INFISICAL_PASSWORD
      'organization-id' = [string], $env:INFISICAL_ORGANIZATION_ID
      interactive = [switch], $false
      plain = [switch], $false
      silent = [switch], $false
      'machine-identity-id' = [string], $env:INFISICAL_MACHINE_IDENTITY_ID
      'organization-slug' = [string], $env:INFISICAL_AUTH_ORGANIZATION_SLUG
    }

    $domain = if ($params.domain.Value) { $params.domain.Value } else { "https://app.infisical.com" }
    if (![string]::IsNullOrEmpty($env:INFISICAL_API_URL)) { $domain = $env:INFISICAL_API_URL }

    $client = [Infisical]::GetClient($domain, $null)

    if ($params.method.Value -eq 'universal-auth') {
       $clientId = $params.'client-id'.Value
       $clientSecretStr = $params.'client-secret'.Value
       if ([string]::IsNullOrEmpty($clientId) -or [string]::IsNullOrEmpty($clientSecretStr)) {
         throw "client-id and client-secret are required for universal-auth."
       }
       $clientSecret = $clientSecretStr | xconvert ToSecurestring
       $res = $client.Auth().UniversalAuth().LoginAsync($clientId, $clientSecret).GetAwaiter().GetResult()
       
       if ($params.plain.Value) {
           if (!$params.silent.Value) { Write-Host $res.AccessToken } else { [Console]::WriteLine($res.AccessToken) }
       } else {
           Write-Host "Successfully logged in via Universal Auth." -ForegroundColor Green
           Write-Host "Token: $($res.AccessToken)"
       }
    } else {
       Write-Warning "Method $($params.method.Value) is currently not fully implemented in this CLI engine wrapper. Only universal-auth is supported via CLI args so far."
    }
  }

  static [void] RunSecrets([string[]]$args) {
    if ($args.Count -eq 0 -or $args[0] -match '^-') {
      # No subcommand, this means 'infisical secrets'
      $subCommand = "list"
      $remArgs = $args
    } else {
      $subCommand = $args[0]
      $remArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
    }

    $params = ConvertTo-Params $remArgs -schema @{
      projectId = [string], $null
      env = [string], 'dev'
      path = [string], '/'
      plain = [switch], $false
      silent = [switch], $false
      expand = [switch], $true
      domain = [string], 'https://app.infisical.com'
      token = [string], $null
    }

    $domain = if ($params.domain.Value) { $params.domain.Value } else { "https://app.infisical.com" }
    if (![string]::IsNullOrEmpty($env:INFISICAL_API_URL)) { $domain = $env:INFISICAL_API_URL }
    $client = [Infisical]::GetClient($domain, $params.token.Value)

    switch ($subCommand) {
      "get" {
         $secretNames = @()
         foreach ($arg in $remArgs) {
             if ($arg -notmatch '^-') { $secretNames += $arg } else { break }
         }
         foreach ($s in $secretNames) {
             $opts = [GetSecretOptions]::new()
             $opts.ProjectId = $params.projectId.Value
             $opts.EnvironmentSlug = $params.env.Value
             $opts.SecretPath = $params.path.Value
             $opts.SecretName = $s
             $opts.ExpandSecretReferences = $params.expand.Value
             $secret = $client.Secrets().GetAsync($opts).GetAwaiter().GetResult()
             if ($params.plain.Value) {
                 [Console]::WriteLine($secret.SecretValue)
             } else {
                 Write-Host "$s`: $($secret.SecretValue)"
             }
         }
      }
      "set" {
          # Partially implemented set
          $opts = [CreateSecretOptions]::new()
          $opts.ProjectId = $params.projectId.Value
          $opts.EnvironmentSlug = $params.env.Value
          $opts.SecretPath = $params.path.Value

          $kvPairs = @()
          foreach ($arg in $remArgs) {
             if ($arg -notmatch '^-' -and $arg -match '=') { $kvPairs += $arg } else { break }
          }
          foreach ($kv in $kvPairs) {
             $split = $kv.Split('=', 2)
             $opts.SecretName = $split[0]
             $opts.SecretValue = $split[1]
             # Update if exists, else create
             try {
                $client.Secrets().CreateAsync($opts).GetAwaiter().GetResult() | Out-Null
                if (!$params.silent.Value) { Write-Host "Set secret $($opts.SecretName)" -f Green }
             } catch {
                $upd = [UpdateSecretOptions]::new()
                $upd.ProjectId = $opts.ProjectId
                $upd.EnvironmentSlug = $opts.EnvironmentSlug
                $upd.SecretPath = $opts.SecretPath
                $upd.SecretName = $opts.SecretName
                $upd.NewSecretValue = $opts.SecretValue
                $client.Secrets().UpdateAsync($upd).GetAwaiter().GetResult() | Out-Null
                if (!$params.silent.Value) { Write-Host "Updated secret $($opts.SecretName)" -f Green }
             }
          }
      }
      "delete" {
          $secretNames = @()
          foreach ($arg in $remArgs) {
             if ($arg -notmatch '^-') { $secretNames += $arg } else { break }
          }
          foreach ($s in $secretNames) {
             $opts = [DeleteSecretOptions]::new()
             $opts.ProjectId = $params.projectId.Value
             $opts.EnvironmentSlug = $params.env.Value
             $opts.SecretPath = $params.path.Value
             $opts.SecretName = $s
             $client.Secrets().DeleteAsync($opts).GetAwaiter().GetResult() | Out-Null
             if (!$params.silent.Value) { Write-Host "Deleted secret $s" -f Green }
          }
      }
      "list" {
         $opts = [ListSecretsOptions]::new()
         $opts.ProjectId = $params.projectId.Value
         $opts.EnvironmentSlug = $params.env.Value
         $opts.SecretPath = $params.path.Value
         $opts.ExpandSecretReferences = $params.expand.Value
         $secrets = $client.Secrets().ListAsync($opts).GetAwaiter().GetResult()
         
         if ($params.plain.Value) {
            foreach ($s in $secrets) { [Console]::WriteLine("$($s.SecretKey)=$($s.SecretValue)") }
         } else {
            $secrets | Format-Table SecretKey, SecretValue, SecretPath, Environment
         }
      }
      default {
         Write-Host "Unknown secrets subcommand: $subCommand"
      }
    }
  }

  static [void] RunExport([string[]]$args) {
    $params = ConvertTo-Params $args -schema @{
      format = [string], 'dotenv'
      'output-file' = [string], $null
      env = [string], 'dev'
      projectId = [string], $null
      path = [string], '/'
      domain = [string], 'https://app.infisical.com'
      token = [string], $null
      expand = [switch], $true
    }

    $domain = if ($params.domain.Value) { $params.domain.Value } else { "https://app.infisical.com" }
    if (![string]::IsNullOrEmpty($env:INFISICAL_API_URL)) { $domain = $env:INFISICAL_API_URL }
    $client = [Infisical]::GetClient($domain, $params.token.Value)

    $opts = [ListSecretsOptions]::new()
    $opts.ProjectId = $params.projectId.Value
    $opts.EnvironmentSlug = $params.env.Value
    $opts.SecretPath = $params.path.Value
    $opts.ExpandSecretReferences = $params.expand.Value
    $secrets = $client.Secrets().ListAsync($opts).GetAwaiter().GetResult()

    $output = @()
    if ($params.format.Value -eq 'json') {
       $hash = @{}
       foreach ($s in $secrets) { $hash[$s.SecretKey] = $s.SecretValue }
       $output = $hash | ConvertTo-Json -Depth 10
    } elseif ($params.format.Value -eq 'yaml') {
       foreach ($s in $secrets) { $output += "$($s.SecretKey): `"$($s.SecretValue)`"" }
       $output = $output -join "`n"
    } elseif ($params.format.Value -eq 'csv') {
       $output += "Key,Value"
       foreach ($s in $secrets) { $output += "$($s.SecretKey),$($s.SecretValue)" }
       $output = $output -join "`n"
    } elseif ($params.format.Value -eq 'dotenv-export') {
       foreach ($s in $secrets) { $output += "export $($s.SecretKey)=`"$($s.SecretValue)`"" }
       $output = $output -join "`n"
    } else {
       # Default dotenv
       foreach ($s in $secrets) { $output += "$($s.SecretKey)=`"$($s.SecretValue)`"" }
       $output = $output -join "`n"
    }

    if (![string]::IsNullOrEmpty($params.'output-file'.Value)) {
       [System.IO.File]::WriteAllText($params.'output-file'.Value, $output)
       Write-Host "Exported secrets to $($params.'output-file'.Value)" -f Green
    } else {
       [Console]::WriteLine($output)
    }
  }
  #endregion CLI Engine
  static [void] WriteBanner() {
    Write-Host ([PsModuleBase]::ReadModuledata("infisical")["BannerAscii"]) -f Green
  }
  static [string] GetHelp() {
    return [PsModuleBase]::ReadModuledata("infisical")["HelpMessage"]
  }
}
#endregion Classes

# Types that will be available to users when they import the module.
# Hint: To automatically generate typestoexport variable you can use this one liner to generate types to export variable
# (Get-ChildItem *.psm1 -Recurse -File | ForEach-Object { [IO.File]::ReadAllLines((Get-Item $_.FullName)).Where({ $_.StartsWith("class") -or $_.StartsWith("enum ") }).ForEach({ $_.Replace("class ", '[').Replace("enum ", '[') }).ForEach({ ($_ -like "* : *") ? $_.split(" : ")[0] + ']' : $_.Replace(' {', ']') }) }) -join ', '

$typestoExport = @(
  [ApiClient], [QueryBuilder], [UniversalAuth], [LdapAuth], [AuthClient], [Subscribers], [PkiClient], [SecretsClient], [IdentitiesClient], [SecretType], [InfisicalAuthMethod], [InfisicalException], [IdentityProjectAdditionalPrivilegePermissionConditionEnvironment], [IdentityProjectAdditionalPrivilegePermissionCondition],
  [IdentityProjectAdditionalPrivilegePermission], [IdentityProjectAdditionalPrivilegeType], [AddIdentityProjectAdditionalPrivilegeOptions], [IdentityProjectAdditionalPrivilegeResponse], [MachineIdentityCredential], [UniversalAuthLoginRequest], [LdapAuthLoginRequest], [ListSecretsOptions], [GetSecretOptions], [SecretMetadata],
  [CreateSecretOptions], [UpdateSecretOptions], [DeleteSecretOptions], [IssueCertificateOptions], [SubscriberIssuedCertificate], [RetrieveLatestCertificateBundleOptions], [CertificateBundle], [InfisicalSecret], [SecretImport], [ListSecretsResponse], [GetSecretResponse], [CreateSecretResponse], [UpdateSecretResponse],
  [DeleteSecretResponse], [InfisicalUniversalAuth], [InfisicalTokenAuth], [InfisicalAuth], [InfisicalSdkSettings], [InfisicalSdkSettingsBuilder], [ObjectToDictionaryConverter], [SecretsUtil], [InfisicalClient], [Infisical],
  [KmsClient], [KmsKey], [ListKmsKeysOptions], [GetKmsKeyByIdOptions], [GetKmsKeyByNameOptions], [CreateKmsKeyOptions], [UpdateKmsKeyOptions], [DeleteKmsKeyOptions], [RetrieveKmsPublicKeyOptions], [ExportKmsPrivateKeyOptions], [BulkExportPrivateKeysOptions], [EncryptKmsDataOptions], [DecryptKmsDataOptions], [SignKmsDataOptions], [VerifyKmsSignatureOptions], [ListKmsSigningAlgorithmsOptions], [KmsKeyResponse], [KmsKeysResponse], [KmsEncryptResponse], [KmsDecryptResponse], [KmsSignResponse], [KmsVerifyResponse], [KmsPublicKeyResponse], [KmsPrivateKeyResponse], [KmsBulkExportPrivateKeysResponse], [KmsSigningAlgorithmsResponse]
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
