#!/usr/bin/env pwsh
using namespace System
using namespace System.Collections.Generic

using module ./Api.psm1
using module ./Model.psm1
using module ./Util.psm1
using module ./Exceptions.psm1

#Requires -Modules clihelper.xconvert

class UniversalAuth {
  hidden [ApiClient] $_apiClient
  hidden [scriptblock] $_setAccessTokenFunc

  UniversalAuth([ApiClient]$apiClient, [scriptblock]$setAccessTokenFunc) {
    $this._apiClient = $apiClient
    $this._setAccessTokenFunc = $setAccessTokenFunc
  }

  [System.Threading.Tasks.Task[MachineIdentityCredential]] LoginAsync([string]$clientId, [securestring]$clientSecret) {
    $task = [System.Threading.Tasks.Task[MachineIdentityCredential]]::Run({
        try {
          $loginRequest = [UniversalAuthLoginRequest]::new($clientId, $clientSecret)

          $response = $this._apiClient.PostAsync([MachineIdentityCredential], "/api/v1/auth/universal-auth/login", $loginRequest).GetAwaiter().GetResult()

          & $this._setAccessTokenFunc $response.AccessToken

          return $response
        } catch {
          throw [InfisicalException]::new("Failed to login", $_.Exception)
        }
      })
    return $task
  }
}

class LdapAuth {
  hidden [ApiClient] $_apiClient
  hidden [scriptblock] $_setAccessTokenFunc

  LdapAuth([ApiClient]$apiClient, [scriptblock]$setAccessTokenFunc) {
    $this._apiClient = $apiClient
    $this._setAccessTokenFunc = $setAccessTokenFunc
  }

  [System.Threading.Tasks.Task[MachineIdentityCredential]] LoginAsync([string]$identityId, [string]$username, [securestring]$password) {
    $task = [System.Threading.Tasks.Task[MachineIdentityCredential]]::Run({
        try {
          $loginRequest = [LdapAuthLoginRequest]::new($identityId, $username, $password)

          $response = $this._apiClient.PostAsync([MachineIdentityCredential], "/api/v1/auth/ldap-auth/login", $loginRequest).GetAwaiter().GetResult()

          & $this._setAccessTokenFunc $response.AccessToken
          return $response
        } catch {
          throw [InfisicalException]::new("Failed to login", $_.Exception)
        }
      })
    return $task
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

  [System.Threading.Tasks.Task[CertificateBundle]] RetrieveLatestCertificateBundleAsync([RetrieveLatestCertificateBundleOptions]$options) {
    $task = [System.Threading.Tasks.Task[CertificateBundle]]::Run({
        try {
          $options.Validate()
          $dict = [ObjectToDictionaryConverter]::ToDictionary($options, $false)

          $response = $this._apiClient.GetAsync([CertificateBundle], "/api/v1/pki/subscribers/$($options.SubscriberName)/latest-certificate-bundle", $dict).GetAwaiter().GetResult()
          return $response
        } catch {
          throw [InfisicalException]::new("Failed to retrieve latest certificate bundle", $_.Exception)
        }
      })
    return $task
  }

  [System.Threading.Tasks.Task[SubscriberIssuedCertificate]] IssueCertificateAsync([IssueCertificateOptions]$options) {
    $task = [System.Threading.Tasks.Task[SubscriberIssuedCertificate]]::Run({
        try {
          $options.Validate()
          $response = $this._apiClient.PostAsync([SubscriberIssuedCertificate], "/api/v1/pki/subscribers/$($options.SubscriberName)/issue-certificate", $options, $true).GetAwaiter().GetResult()
          return $response
        } catch {
          throw [InfisicalException]::new("Failed to issue certificate", $_.Exception)
        }
      }
    )
    return $task
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

  [System.Threading.Tasks.Task[InfisicalSecret[]]] ListAsync([ListSecretsOptions]$options) {
    $task = [System.Threading.Tasks.Task[InfisicalSecret[]]]::Run({
        try {
          $options.Validate()

          $dict = [ObjectToDictionaryConverter]::ToDictionary($options, $false)
          $dict.Remove("tagSlugs") | Out-Null

          if ($null -ne $options.TagSlugs -and $options.TagSlugs.Length -gt 0) {
            $dict["tagSlugs"] = [string]::Join(",", $options.TagSlugs)
          }

          $responseObject = $this._apiClient.GetAsync([ListSecretsResponse], "/api/v3/secrets/raw", $dict).GetAwaiter().GetResult()
          # Need to cast it since it's an object returning from GetAsync
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

          return $secretsList.ToArray()
        } catch {
          throw [InfisicalException]::new("Failed to list secrets", $_.Exception)
        }
      }
    )
    return $task
  }

  [System.Threading.Tasks.Task[InfisicalSecret]] GetAsync([GetSecretOptions]$options) {
    $task = [System.Threading.Tasks.Task[InfisicalSecret]]::Run({
        try {
          $options.Validate()
          $dict = [ObjectToDictionaryConverter]::ToDictionary($options, $false)

          $responseObject = $this._apiClient.GetAsync([GetSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $dict).GetAwaiter().GetResult()
          $response = [GetSecretResponse]$responseObject

          if ([string]::IsNullOrEmpty($response.Secret.SecretPath)) {
            $response.Secret.SecretPath = $options.SecretPath
          }

          return $response.Secret
        } catch {
          throw [InfisicalException]::new("Failed to get secret", $_.Exception)
        }
      })
    return $task
  }

  [System.Threading.Tasks.Task[InfisicalSecret]] CreateAsync([CreateSecretOptions]$options) {
    $task = [System.Threading.Tasks.Task[InfisicalSecret]]::Run({
        try {
          $options.Validate()
          $responseObject = $this._apiClient.PostAsync([CreateSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $options, $true).GetAwaiter().GetResult()
          $response = [CreateSecretResponse]$responseObject
          return $response.Secret
        } catch {
          throw [InfisicalException]::new("Failed to create secret", $_.Exception)
        }
      }
    )
    return $task
  }

  [System.Threading.Tasks.Task[InfisicalSecret]] UpdateAsync([UpdateSecretOptions]$options) {
    $task = [System.Threading.Tasks.Task[InfisicalSecret]]::Run({
        try {
          $options.Validate()
          $responseObject = $this._apiClient.PatchAsync([UpdateSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $options, $true).GetAwaiter().GetResult()
          $response = [UpdateSecretResponse]$responseObject
          return $response.Secret
        } catch {
          throw [InfisicalException]::new("Failed to update secret", $_.Exception)
        }
      }
    )
    return $task
  }

  [System.Threading.Tasks.Task[InfisicalSecret]] DeleteAsync([DeleteSecretOptions]$options) {
    $task = [System.Threading.Tasks.Task[InfisicalSecret]]::Run({
        try {
          $options.Validate()
          $responseObject = $this._apiClient.DeleteAsync([DeleteSecretResponse], "/api/v3/secrets/raw/$($options.SecretName)", $options, $true).GetAwaiter().GetResult()
          $response = [DeleteSecretResponse]$responseObject
          return $response.Secret
        } catch {
          throw [InfisicalException]::new("Failed to delete secret", $_.Exception)
        }
      }
    )
    return $task
  }
}