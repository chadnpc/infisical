#!/usr/bin/env pwsh

using module ./Enums.psm1
using module ./Exceptions.psm1
using namespace System
using namespace System.Text.Json.Serialization

#Requires -Modules clihelper.xconvert

#region apimodels

class MachineIdentityCredential {
  [JsonPropertyName("accessToken")]
  [string] $AccessToken
  [JsonPropertyName("expiresIn")]
  [decimal] $ExpiresIn
  [JsonPropertyName("accessTokenMaxTTL")]
  [decimal] $AccessTokenMaxTTL
  [JsonPropertyName("tokenType")]
  [string] $TokenType

  MachineIdentityCredential([string]$accessToken, [decimal]$expiresIn, [decimal]$accessTokenMaxTTL, [string]$tokenType) {
    $this.AccessToken = $accessToken
    $this.ExpiresIn = $expiresIn
    $this.AccessTokenMaxTTL = $accessTokenMaxTTL
    $this.TokenType = $tokenType
  }

  MachineIdentityCredential() {}
}

class UniversalAuthLoginRequest {
  [JsonPropertyName("clientId")]
  [string] $ClientId
  [JsonPropertyName("clientSecret")]
  [string] $ClientSecret

  UniversalAuthLoginRequest([string]$clientId, [securestring]$clientSecret) {
    $this.ClientId = $clientId
    $this.ClientSecret = ($clientSecret | xconvert Tostring)
  }
}

class LdapAuthLoginRequest {
  [JsonPropertyName("identityId")]
  [string] $IdentityId
  [JsonPropertyName("username")]
  [string] $Username
  [JsonPropertyName("password")]
  [string] $Password

  LdapAuthLoginRequest([string]$identityId, [string]$username, [securestring]$password) {
    $this.IdentityId = $identityId
    $this.Username = $username
    $this.Password = ($password | xconvert Tostring)
  }
}

class ListSecretsOptions {
  [bool] $SetSecretsAsEnvironmentVariables = $false
  [JsonPropertyName("workspaceId")]
  [string] $ProjectId = $null
  [JsonPropertyName("environment")]
  [string] $EnvironmentSlug = $null
  [JsonPropertyName("secretPath")]
  [string] $SecretPath = "/"
  [JsonPropertyName("viewSecretValue")]
  [System.Nullable[bool]] $ViewSecretValue = $null
  [JsonPropertyName("expandSecretReferences")]
  [System.Nullable[bool]] $ExpandSecretReferences = $true
  [JsonPropertyName("recursive")]
  [System.Nullable[bool]] $Recursive = $false
  [JsonPropertyName("tagSlugs")]
  [string[]] $TagSlugs = $null
  [JsonPropertyName("include_imports")]
  [bool] $IncludeImports = $true

  [void] Validate() {
    if ([string]::IsNullOrEmpty($this.ProjectId)) { throw [InfisicalException]::new("ProjectId is required") }
    if ([string]::IsNullOrEmpty($this.EnvironmentSlug)) { throw [InfisicalException]::new("EnvironmentSlug is required") }
    if ([string]::IsNullOrEmpty($this.SecretPath)) { throw [InfisicalException]::new("SecretPath is required") }
  }
}

class GetSecretOptions {
  [JsonPropertyName("workspaceId")]
  [string] $ProjectId = $null
  [JsonPropertyName("environment")]
  [string] $EnvironmentSlug = $null
  [JsonPropertyName("secretPath")]
  [string] $SecretPath = "/"
  [JsonPropertyName("secretName")]
  [string] $SecretName = [string]::Empty
  [JsonPropertyName("version")]
  [System.Nullable[int]] $Version = $null
  [JsonPropertyName("type")]
  [System.Nullable[SecretType]] $Type = $null
  [JsonPropertyName("viewSecretValue")]
  [System.Nullable[bool]] $ViewSecretValue = $null
  [JsonPropertyName("expandSecretReferences")]
  [System.Nullable[bool]] $ExpandSecretReferences = $true
  [JsonPropertyName("include_imports")]
  [bool] $IncludeImports = $true

  [void] Validate() {
    if ([string]::IsNullOrEmpty($this.ProjectId)) { throw [InfisicalException]::new("ProjectId is required") }
    if ([string]::IsNullOrEmpty($this.EnvironmentSlug)) { throw [InfisicalException]::new("EnvironmentSlug is required") }
    if ([string]::IsNullOrEmpty($this.SecretPath)) { throw [InfisicalException]::new("SecretPath is required") }
    if ([string]::IsNullOrEmpty($this.SecretName)) { throw [InfisicalException]::new("SecretName is required") }
  }
}

class SecretMetadata {
  [JsonPropertyName("key")]
  [string] $Key = [string]::Empty
  [JsonPropertyName("value")]
  [string] $Value = [string]::Empty
}

class CreateSecretOptions {
  [JsonPropertyName("secretName")]
  [string] $SecretName = [string]::Empty
  [JsonPropertyName("workspaceId")]
  [string] $ProjectId = $null
  [JsonPropertyName("environment")]
  [string] $EnvironmentSlug = $null
  [JsonPropertyName("secretValue")]
  [string] $SecretValue = [string]::Empty
  [JsonPropertyName("secretPath")]
  [string] $SecretPath = "/"
  [JsonPropertyName("secretComment")]
  [string] $SecretComment = $null
  [JsonPropertyName("secretMetadata")]
  [SecretMetadata[]] $Metadata = $null
  [JsonPropertyName("skipMultilineEncoding")]
  [System.Nullable[bool]] $SkipMultilineEncoding = $null
  [JsonPropertyName("type")]
  [System.Nullable[SecretType]] $Type = $null
  [JsonPropertyName("secretReminderRepeatDays")]
  [System.Nullable[int]] $SecretReminderRepeatDays = $null
  [JsonPropertyName("secretReminderNote")]
  [string] $SecretReminderNote = $null

  [void] Validate() {
    if ([string]::IsNullOrEmpty($this.ProjectId)) { throw [InfisicalException]::new("ProjectId is required") }
    if ([string]::IsNullOrEmpty($this.EnvironmentSlug)) { throw [InfisicalException]::new("EnvironmentSlug is required") }
    if ([string]::IsNullOrEmpty($this.SecretName)) { throw [InfisicalException]::new("SecretName is required") }
    if ([string]::IsNullOrEmpty($this.SecretValue)) { throw [InfisicalException]::new("SecretValue is required") }
    if ([string]::IsNullOrEmpty($this.SecretPath)) { throw [InfisicalException]::new("SecretPath is required") }
  }
}

class UpdateSecretOptions {
  [JsonPropertyName("secretName")]
  [string] $SecretName = [string]::Empty
  [JsonPropertyName("newSecretName")]
  [string] $NewSecretName = $null
  [JsonPropertyName("workspaceId")]
  [string] $ProjectId = $null
  [JsonPropertyName("environment")]
  [string] $EnvironmentSlug = $null
  [JsonPropertyName("type")]
  [System.Nullable[SecretType]] $Type = $null
  [JsonPropertyName("secretPath")]
  [string] $SecretPath = "/"
  [JsonPropertyName("skipMultilineEncoding")]
  [System.Nullable[bool]] $NewSkipMultilineEncoding = $null
  [JsonPropertyName("secretValue")]
  [string] $NewSecretValue = $null
  [JsonPropertyName("secretComment")]
  [string] $NewSecretComment = $null
  [JsonPropertyName("secretMetadata")]
  [SecretMetadata[]] $NewMetadata = $null
  [JsonPropertyName("secretReminderNote")]
  [string] $NewSecretReminderNote = $null
  [JsonPropertyName("secretReminderRepeatDays")]
  [System.Nullable[int]] $NewSecretReminderRepeatDays = $null

  [void] Validate() {
    if ([string]::IsNullOrEmpty($this.ProjectId)) { throw [InfisicalException]::new("ProjectId is required") }
    if ([string]::IsNullOrEmpty($this.SecretName)) { throw [InfisicalException]::new("SecretName is required") }
    if ([string]::IsNullOrEmpty($this.SecretPath)) { throw [InfisicalException]::new("SecretPath is required") }
    if ([string]::IsNullOrEmpty($this.EnvironmentSlug)) { throw [InfisicalException]::new("EnvironmentSlug is required") }
  }
}

class DeleteSecretOptions {
  [JsonPropertyName("secretName")]
  [string] $SecretName = [string]::Empty
  [JsonPropertyName("workspaceId")]
  [string] $ProjectId = $null
  [JsonPropertyName("environment")]
  [string] $EnvironmentSlug = $null
  [JsonPropertyName("secretPath")]
  [string] $SecretPath = "/"

  [void] Validate() {
    if ([string]::IsNullOrEmpty($this.ProjectId)) { throw [InfisicalException]::new("ProjectId is required") }
    if ([string]::IsNullOrEmpty($this.SecretName)) { throw [InfisicalException]::new("SecretName is required") }
    if ([string]::IsNullOrEmpty($this.SecretPath)) { throw [InfisicalException]::new("SecretPath is required") }
    if ([string]::IsNullOrEmpty($this.EnvironmentSlug)) { throw [InfisicalException]::new("EnvironmentSlug is required") }
  }
}

class IssueCertificateOptions {
  [JsonPropertyName("subscriberName")]
  [string] $SubscriberName = [string]::Empty
  [JsonPropertyName("projectId")]
  [string] $ProjectId = [string]::Empty

  [void] Validate() {
    if ([string]::IsNullOrEmpty($this.SubscriberName)) { throw [InfisicalException]::new("SubscriberName is required") }
    if ([string]::IsNullOrEmpty($this.ProjectId)) { throw [InfisicalException]::new("ProjectId is required") }
  }
}

class SubscriberIssuedCertificate {
  [JsonPropertyName("certificate")]
  [string] $Certificate = [string]::Empty
  [JsonPropertyName("issuingCaCertificate")]
  [string] $IssuingCaCertificate = [string]::Empty
  [JsonPropertyName("certificateChain")]
  [string] $CertificateChain = [string]::Empty
  [JsonPropertyName("privateKey")]
  [string] $PrivateKey = [string]::Empty
  [JsonPropertyName("serialNumber")]
  [string] $SerialNumber = [string]::Empty
}

class RetrieveLatestCertificateBundleOptions {
  [JsonPropertyName("subscriberName")]
  [string] $SubscriberName = [string]::Empty
  [JsonPropertyName("projectId")]
  [string] $ProjectId = [string]::Empty

  [void] Validate() {
    if ([string]::IsNullOrEmpty($this.SubscriberName)) { throw [InfisicalException]::new("SubscriberName is required") }
    if ([string]::IsNullOrEmpty($this.ProjectId)) { throw [InfisicalException]::new("ProjectId is required") }
  }
}

class CertificateBundle {
  [JsonPropertyName("certificate")]
  [string] $Certificate = [string]::Empty
  [JsonPropertyName("certificateChain")]
  [string] $CertificateChain = [string]::Empty
  [JsonPropertyName("privateKey")]
  [string] $PrivateKey = [string]::Empty
  [JsonPropertyName("serialNumber")]
  [string] $SerialNumber = [string]::Empty
}

class InfisicalSecret {
  [JsonPropertyName("id")]
  [string] $Id = [string]::Empty
  [JsonPropertyName("workspace")]
  [string] $ProjectId = [string]::Empty
  [JsonPropertyName("environment")]
  [string] $Environment = [string]::Empty
  [JsonPropertyName("version")]
  [int] $Version
  [JsonPropertyName("secretKey")]
  [string] $SecretKey = [string]::Empty
  [JsonPropertyName("secretValue")]
  [string] $SecretValue = [string]::Empty
  [JsonPropertyName("secretComment")]
  [string] $SecretComment = [string]::Empty
  [JsonPropertyName("secretReminderNote")]
  [string] $SecretReminderNote = $null
  [JsonPropertyName("secretReminderRepeatDays")]
  [System.Nullable[int]] $SecretReminderRepeatDays = $null
  [JsonPropertyName("skipMultilineEncoding")]
  [System.Nullable[bool]] $SkipMultilineEncoding = $null
  [JsonPropertyName("isRotatedSecret")]
  [bool] $IsRotatedSecret = $false
  [JsonPropertyName("rotationId")]
  [string] $RotationId = $null
  [JsonPropertyName("secretPath")]
  [string] $SecretPath = [string]::Empty
  [JsonPropertyName("secretMetadata")]
  [SecretMetadata[]] $Metadata = @()
}

class SecretImport {
  [JsonPropertyName("secretPath")]
  [string] $SecretPath = [string]::Empty
  [JsonPropertyName("environment")]
  [string] $Environment = [string]::Empty
  [JsonPropertyName("secrets")]
  [InfisicalSecret[]] $Secrets = @()
}

class ListSecretsResponse {
  [JsonPropertyName("secrets")]
  [InfisicalSecret[]] $Secrets = @()
  [JsonPropertyName("imports")]
  [SecretImport[]] $Imports = @()
}

class GetSecretResponse {
  [JsonPropertyName("secret")]
  [InfisicalSecret] $Secret = [InfisicalSecret]::new()
}

class CreateSecretResponse {
  [JsonPropertyName("secret")]
  [InfisicalSecret] $Secret = [InfisicalSecret]::new()
}

class UpdateSecretResponse {
  [JsonPropertyName("secret")]
  [InfisicalSecret] $Secret = [InfisicalSecret]::new()
}

class DeleteSecretResponse {
  [JsonPropertyName("secret")]
  [InfisicalSecret] $Secret = [InfisicalSecret]::new()
}
#endregion

class InfisicalUniversalAuth {
  hidden [string] $_clientId
  hidden [string] $_clientSecret

  InfisicalUniversalAuth([string]$clientId, [securestring]$clientSecret) {
    $this._clientId = $clientId
    $this._clientSecret = ($clientSecret | xconvert Tostring)
  }
  InfisicalUniversalAuth() {}
}

class InfisicalTokenAuth {
  hidden [string] $_token

  InfisicalTokenAuth([string]$token) {
    $this._token = $token
  }
  InfisicalTokenAuth() {}
}

class InfisicalAuth {
  hidden [InfisicalUniversalAuth] $_universalAuth
  hidden [InfisicalTokenAuth] $_tokenAuth
  hidden [InfisicalAuthMethod] $_authMethod

  InfisicalAuth([InfisicalUniversalAuth]$universalAuth) {
    $this._universalAuth = $universalAuth
    $this._authMethod = [InfisicalAuthMethod]::Universal
  }

  InfisicalAuth([InfisicalTokenAuth]$tokenAuth) {
    $this._tokenAuth = $tokenAuth
    $this._authMethod = [InfisicalAuthMethod]::Token
  }

  InfisicalAuth() {}

  hidden [InfisicalAuthMethod] GetAuthMethod() {
    return $this._authMethod
  }

  hidden [InfisicalUniversalAuth] GetUniversalAuth() {
    if ($this._authMethod -ne [InfisicalAuthMethod]::Universal) {
      throw [Exception]::new("Unable to get universal auth details. Auth method is set to $($this._authMethod)")
    }
    if ($null -eq $this._universalAuth) {
      throw [Exception]::new("Universal auth details are not set")
    }
    return $this._universalAuth
  }

  hidden [InfisicalTokenAuth] GetTokenAuth() {
    if ($this._authMethod -ne [InfisicalAuthMethod]::Token) {
      throw [Exception]::new("Unable to get token auth details. Auth method is set to $($this._authMethod)")
    }
    if ($null -eq $this._tokenAuth) {
      throw [Exception]::new("Token auth details are not set")
    }
    return $this._tokenAuth
  }
}

class InfisicalSdkSettings {
  [string] $HostUri = "https://app.infisical.com"
}

class InfisicalSdkSettingsBuilder {
  hidden [InfisicalSdkSettings] $_settings = [InfisicalSdkSettings]::new()

  [InfisicalSdkSettingsBuilder] WithHostUri([string]$hostUri) {
    $this._settings.HostUri = $hostUri
    return $this
  }

  [InfisicalSdkSettings] Build() {
    $result = [InfisicalSdkSettings]::new()
    $result.HostUri = $this._settings.HostUri
    return $result
  }
}