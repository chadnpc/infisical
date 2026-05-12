#!/usr/bin/env pwsh
using namespace System
using namespace System.Threading.Tasks
using namespace System.Collections.Generic

using module ./Api.psm1
using module ./Model.psm1
using module ./Util.psm1
using module ./Exceptions.psm1

#Requires -Modules clihelper.xconvert

class UniversalAuth {
  hidden [ValidateNotNullOrEmpty()][ApiClient] $_apiClient
  hidden [ValidateNotNullOrEmpty()][scriptblock] $_setAccessTokenFunc

  UniversalAuth([ApiClient]$apiClient, [scriptblock]$setAccessTokenFunc) {
    $this._apiClient = $apiClient
    $this._setAccessTokenFunc = $setAccessTokenFunc
  }

  [Task[MachineIdentityCredential]] LoginAsync([string]$clientId) {
    return $this.LoginAsync($clientId, $this._apiClient.clientSecret)
  }
  [Task[MachineIdentityCredential]] LoginAsync([string]$clientId, [securestring]$clientSecret) {
    try {
      $loginRequest = [UniversalAuthLoginRequest]::new($clientId, $clientSecret)
      $responseObject = $this._apiClient.PostAsync([MachineIdentityCredential], "/api/v1/auth/universal-auth/login", $loginRequest).GetAwaiter().GetResult()
      $response = [MachineIdentityCredential]$responseObject
      $this._apiClient.SetAccessToken($response.AccessToken)
      return [Task]::FromResult($response)
    }
    catch {
      throw [InfisicalException]::new("Failed to login", $_.Exception)
    }
  }
}

class LdapAuth {
  hidden [ApiClient] $_apiClient
  hidden [scriptblock] $_setAccessTokenFunc

  LdapAuth([ApiClient]$apiClient, [scriptblock]$setAccessTokenFunc) {
    $this._apiClient = $apiClient
    $this._setAccessTokenFunc = $setAccessTokenFunc
  }

  [Task[MachineIdentityCredential]] LoginAsync([string]$identityId, [string]$username, [securestring]$password) {
    try {
      $loginRequest = [LdapAuthLoginRequest]::new($identityId, $username, $password)
      $responseObject = $this._apiClient.PostAsync([MachineIdentityCredential], "/api/v1/auth/ldap-auth/login", $loginRequest).GetAwaiter().GetResult()
      $response = [MachineIdentityCredential]$responseObject
      $this._apiClient.SetAccessToken($response.AccessToken)
      return [Task]::FromResult($response)
    }
    catch {
      throw [InfisicalException]::new("Failed to login", $_.Exception)
    }
  }
}

class AuthClient {
  hidden [ApiClient] $_apiClient
  hidden [UniversalAuth] $_universalAuth
  hidden [LdapAuth] $_ldapAuth
  hidden [scriptblock] $_setAccessTokenFunc

  AuthClient([ApiClient]$apiClient, [scriptblock]$setAccessTokenFunc) {
    $this._apiClient = $apiClient
    $this._setAccessTokenFunc = $setAccessTokenFunc
    $this._universalAuth = [UniversalAuth]::new($this._apiClient, $this._setAccessTokenFunc)
    $this._ldapAuth = [LdapAuth]::new($this._apiClient, $this._setAccessTokenFunc)
  }

  [UniversalAuth] UniversalAuth() {
    return $this._universalAuth
  }

  [LdapAuth] LdapAuth() {
    return $this._ldapAuth
  }
}

class Subscribers {
  hidden [ApiClient] $_apiClient

  Subscribers([ApiClient]$apiClient) {
    $this._apiClient = $apiClient
  }

  [Task[CertificateBundle]] RetrieveLatestCertificateBundleAsync([RetrieveLatestCertificateBundleOptions]$options) {
    try {
      $options.Validate()
      $dict = [ObjectToDictionaryConverter]::ToDictionary($options, $false)
      $responseObject = $this._apiClient.GetAsync([CertificateBundle], "/api/v1/pki/subscribers/$($options.SubscriberName)/latest-certificate-bundle", $dict).GetAwaiter().GetResult()
      $response = [CertificateBundle]$responseObject
      return [Task]::FromResult($response)
    }
    catch {
      throw [InfisicalException]::new("Failed to retrieve latest certificate bundle", $_.Exception)
    }
  }

  [Task[SubscriberIssuedCertificate]] IssueCertificateAsync([IssueCertificateOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([SubscriberIssuedCertificate], "/api/v1/pki/subscribers/$($options.SubscriberName)/issue-certificate", $options, $true).GetAwaiter().GetResult()
      $response = [SubscriberIssuedCertificate]$responseObject
      return [Task]::FromResult($response)
    }
    catch {
      throw [InfisicalException]::new("Failed to issue certificate", $_.Exception)
    }
  }
}

class PkiClient {
  hidden [ApiClient] $_apiClient
  hidden [Subscribers] $_subscribers

  PkiClient([ApiClient]$apiClient) {
    $this._apiClient = $apiClient
    $this._subscribers = [Subscribers]::new($this._apiClient)
  }

  [Subscribers] Subscribers() {
    return $this._subscribers
  }
}

class SecretsClient {
  hidden [ApiClient] $_apiClient

  SecretsClient([ApiClient]$apiClient) {
    $this._apiClient = $apiClient
  }

  [Task[InfisicalSecret[]]] ListAsync([ListSecretsOptions]$options) {
    try {
      $options.Validate()

      $dict = [ObjectToDictionaryConverter]::ToDictionary($options, $false)
      $dict.Remove("tagSlugs") | Out-Null

      if ($null -ne $options.TagSlugs -and $options.TagSlugs.Length -gt 0) {
        $dict["tagSlugs"] = [string]::Join(",", $options.TagSlugs)
      }

      $responseObject = $this._apiClient.GetAsync([ListSecretsResponse], "/api/v3/secrets/raw", $dict).GetAwaiter().GetResult()
      $response = [ListSecretsResponse]$responseObject

      $secretsList = [System.Collections.Generic.List[InfisicalSecret]]::new()
      if ($null -ne $response.Secrets) {
        foreach ($s in $response.Secrets) { $secretsList.Add($s) }
      }

      if ($options.Recursive -eq $true) {
        [SecretsUtil]::EnsureUniqueSecretsByKey($secretsList)
      }

      if ($options.IncludeImports -eq $true -and $null -ne $response.Imports -and $response.Imports.Length -gt 0) {
        foreach ($import in $response.Imports) {
          if ($null -ne $import.Secrets -and $import.Secrets.Length -gt 0) {
            foreach ($importSecret in $import.Secrets) {
              $found = $false
              foreach ($s in $secretsList) {
                if ($s.SecretKey -eq $importSecret.SecretKey) {
                  $found = $true
                  break
                }
              }
              if (!$found) {
                if ($null -ne $options.ProjectId) {
                  $importSecret.ProjectId = $options.ProjectId
                }
                $importSecret.SecretPath = $import.SecretPath
                $secretsList.Add($importSecret)
              }
            }
          }
        }
      }

      if ($options.SetSecretsAsEnvironmentVariables -eq $true) {
        foreach ($secret in $secretsList) {
          if ($null -eq [Environment]::GetEnvironmentVariable($secret.SecretKey)) {
            [Environment]::SetEnvironmentVariable($secret.SecretKey, $secret.SecretValue)
          }
        }
      }

      return [Task]::FromResult($secretsList.ToArray())
    }
    catch {
      throw [InfisicalException]::new("Failed to list secrets", $_.Exception)
    }
  }

  [Task[InfisicalSecret]] GetAsync([GetSecretOptions]$options) {
    try {
      $options.Validate()
      $dict = [ObjectToDictionaryConverter]::ToDictionary($options, $false)

      $responseObject = $this._apiClient.GetAsync([GetSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $dict).GetAwaiter().GetResult()
      $response = [GetSecretResponse]$responseObject

      if ([string]::IsNullOrEmpty($response.Secret.SecretPath)) {
        $response.Secret.SecretPath = $options.SecretPath
      }

      return [Task]::FromResult($response.Secret)
    }
    catch {
      throw [InfisicalException]::new("Failed to get secret", $_.Exception)
    }
  }

  [Task[InfisicalSecret]] CreateAsync([CreateSecretOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([CreateSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $options, $true).GetAwaiter().GetResult()
      $response = [CreateSecretResponse]$responseObject
      return [Task]::FromResult($response.Secret)
    }
    catch {
      throw [InfisicalException]::new("Failed to create secret", $_.Exception)
    }
  }

  [Task[InfisicalSecret]] UpdateAsync([UpdateSecretOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PatchAsync([UpdateSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $options, $true).GetAwaiter().GetResult()
      $response = [UpdateSecretResponse]$responseObject
      return [Task]::FromResult($response.Secret)
    }
    catch {
      throw [InfisicalException]::new("Failed to update secret", $_.Exception)
    }
  }

  [Task[InfisicalSecret]] DeleteAsync([DeleteSecretOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.DeleteAsync([DeleteSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $options, $true).GetAwaiter().GetResult()
      $response = [DeleteSecretResponse]$responseObject
      return [Task]::FromResult($response.Secret)
    }
    catch {
      throw [InfisicalException]::new("Failed to delete secret", $_.Exception)
    }
  }
}

class IdentitiesClient {
  hidden [ApiClient] $_apiClient

  IdentitiesClient([ApiClient]$apiClient) {
    $this._apiClient = $apiClient
  }

  [Task[System.Text.Json.JsonElement]] AddProjectAdditionalPrivilegeAsync([AddIdentityProjectAdditionalPrivilegeOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([IdentityProjectAdditionalPrivilegeResponse], "/api/v2/identity-project-additional-privilege", $options, $true).GetAwaiter().GetResult()
      $response = [IdentityProjectAdditionalPrivilegeResponse]$responseObject
      return [Task]::FromResult($response.Privilege)
    }
    catch {
      $innerMessage = if ($null -ne $_.Exception) { $_.Exception.Message } else { $_.ToString() }
      throw [InfisicalException]::new("Failed to add additional privilege: $innerMessage", $_.Exception)
    }
  }
}

class KmsClient {
  hidden [ApiClient] $_apiClient

  KmsClient([ApiClient]$apiClient) {
    $this._apiClient = $apiClient
  }

  [Task[object[]]] ListKeysAsync([ListKmsKeysOptions]$options) {
    try {
      $dict = [ObjectToDictionaryConverter]::ToDictionary($options, $false)
      $responseObject = $this._apiClient.GetAsync([KmsKeysResponse], "/api/v1/kms/keys", $dict).GetAwaiter().GetResult()
      $response = [KmsKeysResponse]$responseObject
      return [Task]::FromResult($response.Keys)
    }
    catch {
      throw [InfisicalException]::new("Failed to list KMS keys", $_.Exception)
    }
  }

  [Task[object]] GetKeyByIdAsync([GetKmsKeyByIdOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.GetAsync([KmsKeyResponse], "/api/v1/kms/keys/$($options.KeyId)", @{}).GetAwaiter().GetResult()
      $response = [KmsKeyResponse]$responseObject
      return [Task]::FromResult($response.Key)
    }
    catch {
      throw [InfisicalException]::new("Failed to get KMS key by ID", $_.Exception)
    }
  }

  [Task[object]] GetKeyByNameAsync([GetKmsKeyByNameOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.GetAsync([KmsKeyResponse], "/api/v1/kms/keys/key-name/$($options.KeyName)", @{}).GetAwaiter().GetResult()
      $response = [KmsKeyResponse]$responseObject
      return [Task]::FromResult($response.Key)
    }
    catch {
      throw [InfisicalException]::new("Failed to get KMS key by name", $_.Exception)
    }
  }

  [Task[object]] CreateKeyAsync([CreateKmsKeyOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([KmsKeyResponse], "/api/v1/kms/keys", $options, $true).GetAwaiter().GetResult()
      $response = [KmsKeyResponse]$responseObject
      return [Task]::FromResult($response.Key)
    }
    catch {
      throw [InfisicalException]::new("Failed to create KMS key", $_.Exception)
    }
  }

  [Task[object]] UpdateKeyAsync([UpdateKmsKeyOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PatchAsync([KmsKeyResponse], "/api/v1/kms/keys/$($options.KeyId)", $options, $true).GetAwaiter().GetResult()
      $response = [KmsKeyResponse]$responseObject
      return [Task]::FromResult($response.Key)
    }
    catch {
      throw [InfisicalException]::new("Failed to update KMS key", $_.Exception)
    }
  }

  [Task[object]] DeleteKeyAsync([DeleteKmsKeyOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.DeleteAsync([KmsKeyResponse], "/api/v1/kms/keys/$($options.KeyId)", $options, $true).GetAwaiter().GetResult()
      $response = [KmsKeyResponse]$responseObject
      return [Task]::FromResult($response.Key)
    }
    catch {
      throw [InfisicalException]::new("Failed to delete KMS key", $_.Exception)
    }
  }

  [Task[string]] RetrievePublicKeyAsync([RetrieveKmsPublicKeyOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.GetAsync([KmsPublicKeyResponse], "/api/v1/kms/keys/$($options.KeyId)/public-key", @{}).GetAwaiter().GetResult()
      $response = [KmsPublicKeyResponse]$responseObject
      return [Task]::FromResult($response.PublicKey)
    }
    catch {
      throw [InfisicalException]::new("Failed to retrieve KMS public key", $_.Exception)
    }
  }

  [Task[string]] ExportPrivateKeyAsync([ExportKmsPrivateKeyOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.GetAsync([KmsPrivateKeyResponse], "/api/v1/kms/keys/$($options.KeyId)/private-key", @{}).GetAwaiter().GetResult()
      $response = [KmsPrivateKeyResponse]$responseObject
      return [Task]::FromResult($response.PrivateKey)
    }
    catch {
      throw [InfisicalException]::new("Failed to export KMS private key", $_.Exception)
    }
  }

  [Task[object[]]] BulkExportPrivateKeysAsync([BulkExportPrivateKeysOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([KmsBulkExportPrivateKeysResponse], "/api/v1/kms/keys/bulk-export-private-keys", $options, $true).GetAwaiter().GetResult()
      $response = [KmsBulkExportPrivateKeysResponse]$responseObject
      return [Task]::FromResult($response.Keys)
    }
    catch {
      throw [InfisicalException]::new("Failed to bulk export KMS private keys", $_.Exception)
    }
  }

  [Task[string]] EncryptDataAsync([EncryptKmsDataOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([KmsEncryptResponse], "/api/v1/kms/keys/$($options.KeyId)/encrypt", $options, $true).GetAwaiter().GetResult()
      $response = [KmsEncryptResponse]$responseObject
      return [Task]::FromResult($response.Ciphertext)
    }
    catch {
      throw [InfisicalException]::new("Failed to encrypt KMS data", $_.Exception)
    }
  }

  [Task[string]] DecryptDataAsync([DecryptKmsDataOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([KmsDecryptResponse], "/api/v1/kms/keys/$($options.KeyId)/decrypt", $options, $true).GetAwaiter().GetResult()
      $response = [KmsDecryptResponse]$responseObject
      return [Task]::FromResult($response.Plaintext)
    }
    catch {
      throw [InfisicalException]::new("Failed to decrypt KMS data", $_.Exception)
    }
  }

  [Task[string]] SignDataAsync([SignKmsDataOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([KmsSignResponse], "/api/v1/kms/keys/$($options.KeyId)/sign", $options, $true).GetAwaiter().GetResult()
      $response = [KmsSignResponse]$responseObject
      return [Task]::FromResult($response.Signature)
    }
    catch {
      throw [InfisicalException]::new("Failed to sign KMS data", $_.Exception)
    }
  }

  [Task[bool]] VerifySignatureAsync([VerifyKmsSignatureOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.PostAsync([KmsVerifyResponse], "/api/v1/kms/keys/$($options.KeyId)/verify", $options, $true).GetAwaiter().GetResult()
      $response = [KmsVerifyResponse]$responseObject
      return [Task]::FromResult($response.IsValid)
    }
    catch {
      throw [InfisicalException]::new("Failed to verify KMS signature", $_.Exception)
    }
  }

  [Task[string[]]] ListSigningAlgorithmsAsync([ListKmsSigningAlgorithmsOptions]$options) {
    try {
      $options.Validate()
      $responseObject = $this._apiClient.GetAsync([KmsSigningAlgorithmsResponse], "/api/v1/kms/keys/$($options.KeyId)/signing-algorithms", @{}).GetAwaiter().GetResult()
      $response = [KmsSigningAlgorithmsResponse]$responseObject
      return [Task]::FromResult($response.SigningAlgorithms)
    }
    catch {
      throw [InfisicalException]::new("Failed to list KMS signing algorithms", $_.Exception)
    }
  }
}