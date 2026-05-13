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

  static [InfisicalClient] DefaultClient() {
    $domain = if ($env:INFISICAL_API_URL) { $env:INFISICAL_API_URL } else { "https://app.infisical.com" }
    return [Infisical]::GetClient($domain, $null)
  }

  static [AuthClient] Auth() { return [Infisical]::DefaultClient().Auth() }
  static [SecretsClient] Secrets() { return [Infisical]::DefaultClient().Secrets() }
  static [PkiClient] Pki() { return [Infisical]::DefaultClient().Pki() }
  static [IdentitiesClient] Identities() { return [Infisical]::DefaultClient().Identities() }
  static [KmsClient] Kms() { return [Infisical]::DefaultClient().Kms() }

  static hidden [void] ParseArgs([string[]]$InputArgs) {
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
        "login" { [Infisical]::Login($subArgs); break }
        "secrets" { [Infisical]::Secrets($subArgs); break }
        "export" { [Infisical]::Export($subArgs); break }
        "run" { [Infisical]::Run($subArgs); break }
        "init" { [Infisical]::Init($subArgs); break }
        "reset" { [Infisical]::Reset($subArgs); break }
        "token" { [Infisical]::Token($subArgs); break }
        "user" { [Infisical]::User($subArgs); break }
        "vault" { [Infisical]::Vault($subArgs); break }
        "scan" { [Infisical]::Scan($subArgs); break }
        "help" { [Infisical]::ShowHelp(); break }
        "version" { [Infisical]::ShowVersion(); break }
        "upgrade" { [Infisical]::UpdateModule(); break }
        "events" {
          $params = ConvertTo-Params $subArgs -schema @{
            id     = [string], $null
            limit  = [int], 20
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

  static [void] Login([string[]]$InputArgs) {
    $params = ConvertTo-Params $InputArgs -schema @{
      method                = [string], 'user'
      domain                = [string], 'https://app.infisical.com'
      'client-id'           = [string], $env:INFISICAL_UNIVERSAL_AUTH_CLIENT_ID
      'client-secret'       = [string], $env:INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET
      email                 = [string], $env:INFISICAL_EMAIL
      password              = [string], $env:INFISICAL_PASSWORD
      'organization-id'     = [string], $env:INFISICAL_ORGANIZATION_ID
      interactive           = [switch], $false
      plain                 = [switch], $false
      silent                = [switch], $false
      'machine-identity-id' = [string], $env:INFISICAL_MACHINE_IDENTITY_ID
      'organization-slug'   = [string], $env:INFISICAL_AUTH_ORGANIZATION_SLUG
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

  static [void] Secrets([string[]]$InputArgs) {
    if ($InputArgs.Count -eq 0 -or $InputArgs[0] -match '^-') {
      # No subcommand, this means 'infisical secrets'
      $subCommand = "list"
      $remArgs = $InputArgs
    } else {
      $subCommand = $InputArgs[0]
      $remArgs = if ($InputArgs.Count -gt 1) { $InputArgs[1..($InputArgs.Count - 1)] } else { @() }
    }

    $params = ConvertTo-Params $remArgs -schema @{
      projectId = [string], $null
      env       = [string], 'dev'
      path      = [string], '/'
      plain     = [switch], $false
      silent    = [switch], $false
      expand    = [switch], $true
      domain    = [string], 'https://app.infisical.com'
      token     = [string], $null
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

  static [void] Export([string[]]$InputArgs) {
    $params = ConvertTo-Params $InputArgs -schema @{
      format        = [string], 'dotenv'
      'output-file' = [string], $null
      env           = [string], 'dev'
      projectId     = [string], $null
      path          = [string], '/'
      domain        = [string], 'https://app.infisical.com'
      token         = [string], $null
      expand        = [switch], $true
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

  static [void] Run([string[]]$InputArgs) {
    $dashDashIndex = [Array]::IndexOf($InputArgs, "--")
    $infisicalArgs = @()
    $cmdArgs = @()

    if ($dashDashIndex -ge 0) {
      if ($dashDashIndex -gt 0) { $infisicalArgs = $InputArgs[0..($dashDashIndex - 1)] }
      if ($dashDashIndex -lt ($InputArgs.Count - 1)) { $cmdArgs = $InputArgs[($dashDashIndex + 1)..($InputArgs.Count - 1)] }
    } else {
      $infisicalArgs = $InputArgs
    }

    $params = ConvertTo-Params $infisicalArgs -schema @{
      projectId = [string], $null
      env       = [string], 'dev'
      path      = [string[]], @('/')
      command   = [string], $null
      expand    = [switch], $true
      domain    = [string], 'https://app.infisical.com'
      token     = [string], $null
      watch     = [switch], $false
    }

    $domain = if ($params.domain.Value) { $params.domain.Value } else { "https://app.infisical.com" }
    if (![string]::IsNullOrEmpty($env:INFISICAL_API_URL)) { $domain = $env:INFISICAL_API_URL }

    $projectId = $params.projectId.Value
    if ([string]::IsNullOrEmpty($projectId)) {
      $config = [Infisical]::GetProjectConfig()
      if ($null -ne $config -and $null -ne $config.workspaceId) {
        $projectId = $config.workspaceId
      }
    }

    if ([string]::IsNullOrEmpty($projectId) -and [string]::IsNullOrEmpty($params.token.Value) -and [string]::IsNullOrEmpty($env:INFISICAL_TOKEN)) {
      Write-Error "Project ID is required. Use --projectId or run 'infisical init' first."
      return
    }

    $client = [Infisical]::GetClient($domain, $params.token.Value)

    $opts = [ListSecretsOptions]::new()
    $opts.ProjectId = $projectId
    $opts.EnvironmentSlug = $params.env.Value
    $opts.ExpandSecretReferences = $params.expand.Value
    $opts.SetSecretsAsEnvironmentVariables = $true

    $paths = if ($params.path.Value -is [string[]]) { $params.path.Value } else { @($params.path.Value) }

    # Fetch secrets and set as env vars for each path
    # Note: ListAsync only sets environment variables if they are not already set,
    # ensuring that the first path provided takes precedence.
    foreach ($p in $paths) {
      $opts.SecretPath = $p
      $client.Secrets().ListAsync($opts).GetAwaiter().GetResult() | Out-Null
    }

    $finalCmd = if (![string]::IsNullOrEmpty($params.command.Value)) { $params.command.Value } else { $cmdArgs -join " " }

    if ([string]::IsNullOrEmpty($finalCmd)) {
      Write-Error "No command provided to run."
      return
    }

    if ($params.watch.Value) {
      Write-Warning "Watch mode is not yet implemented in this PowerShell module."
    }

    try {
      [scriptblock]::Create("$finalCmd").Invoke()
    } catch {
      Write-Error $_.Exception.Message
    }
  }

  static [void] Scan([string[]]$InputArgs) {
    Write-Warning "Secret scanning is not yet implemented in this PowerShell module."
  }

  # static [void] Init([string]$projectId) {
  #   [Infisical]::Init(@("--projectId", $projectId))
  # }

  static [void] Init([string[]]$InputArgs) {
    $params = ConvertTo-Params $InputArgs -schema @{
      projectId = [string], $null
    }

    $projectId = $params.projectId.Value
    if ([string]::IsNullOrEmpty($projectId)) {
      $projectId = Read-Host "Enter your Infisical Project ID"
    }

    if ([string]::IsNullOrEmpty($projectId)) {
      Write-Error "Project ID is required."
      return
    }

    $config = @{
      workspaceId = $projectId
    }

    [Infisical]::SetProjectConfig($config)
    Write-Host "Initialized project in .infisical.json" -ForegroundColor Green
  }

  static [void] Reset([string[]]$InputArgs) {
    $configFile = Join-Path (Get-Location) ".infisical.json"
    if (Test-Path $configFile) {
      Remove-Item $configFile
      Write-Host "Reset Infisical configuration." -ForegroundColor Green
    } else {
      Write-Host "No Infisical configuration found to reset."
    }
  }

  static [void] Token([string[]]$InputArgs) {
    if ($InputArgs.Count -eq 0) {
      Write-Host "Usage: infisical token <renew> [options]"
      return
    }

    $subCommand = $InputArgs[0]
    switch ($subCommand) {
      "renew" {
        Write-Warning "Token renewal is not yet implemented."
      }
      default {
        Write-Error "Unknown token subcommand: $subCommand"
      }
    }
  }

  static [void] User([string[]]$InputArgs) {
    if ($InputArgs.Count -eq 0) {
      Write-Host "Usage: infisical user <get|switch|update> [options]"
      return
    }

    $subCommand = $InputArgs[0]
    $remArgs = if ($InputArgs.Count -gt 1) { $InputArgs[1..($InputArgs.Count - 1)] } else { @() }

    switch ($subCommand) {
      "get" {
        if ($remArgs.Count -gt 0 -and $remArgs[0] -eq "token") {
          $params = ConvertTo-Params $remArgs[1..($remArgs.Count - 1)] -schema @{
            plain = [switch], $false
          }
          $token = $env:INFISICAL_TOKEN
          if ([string]::IsNullOrEmpty($token)) {
            Write-Error "Not logged in. No INFISICAL_TOKEN found."
            return
          }
          if ($params.plain.Value) {
            [Console]::WriteLine($token)
          } else {
            Write-Host "Token: $token"
          }
        }
      }
      default {
        Write-Warning "User subcommand $subCommand is not yet implemented."
      }
    }
  }

  static [void] Vault([string[]]$InputArgs) {
    Write-Warning "Vault management is not yet implemented."
  }

  static [object] GetProjectConfig() {
    $configFile = Join-Path (Get-Location) ".infisical.json"
    if (Test-Path $configFile) {
      return Get-Content $configFile | ConvertFrom-Json
    }
    return $null
  }

  static [void] SetProjectConfig([object]$Config) {
    $configFile = Join-Path (Get-Location) ".infisical.json"
    $Config | ConvertTo-Json | Set-Content $configFile
  }
  #endregion CLI Engine
  static [void] ShowHelp() {
    [Infisical]::WriteBanner()
    Write-Host ([Infisical]::GetHelp())
  }

  static [void] ShowVersion() {
    $version = ([PsModuleBase]::ReadModuledata("infisical")["ModuleVersion"])
    Write-Host "Infisical CLI version $version"
  }

  static [void] UpdateModule() {
    Write-Host "Updating Infisical module..." -ForegroundColor Cyan
    Update-Module -Name infisical -ErrorAction SilentlyContinue
    Write-Host "Update check complete." -ForegroundColor Green
  }

  static [string] GetEvent([string]$id, [int]$limit, [string]$output) {
    # TODO: Implement event retrieval in the API client
    return "Event retrieval ($id) is not yet implemented in this PowerShell module wrapper."
  }

  static [void] WriteBanner() {
    Write-Host ([PsModuleBase]::ReadModuledata("infisical").BannerAscii) -f Green
  }
  static [string] GetHelp() {
    return [PsModuleBase]::ReadModuledata("Infisical").HelpMessage
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
