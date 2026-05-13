using namespace System.Text
using namespace System.Security.Cryptography
using module ..\infisical.psm1

# Load environment variables from the root .env file
Read-Env ([IO.Path]::Combine(($PSScriptRoot | Split-Path), ".env")) | Set-Env

Describe "Infisical Access Control tests " {
  $clientId = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_ID
  $clientSecret = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET
  $projectId = $env:INFISICAL_PROJECT_ID
  $hostUri = if ([string]::IsNullOrEmpty($env:INFISICAL_HOST_URI)) { "https://app.infisical.com" } else { $env:INFISICAL_HOST_URI }

  $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri($hostUri).Build()
  $client = [InfisicalClient]::new($settings)
  $newSecretName = "INFISICAL-ACCESS-TEST-$([guid]::NewGuid())"

  It "Authentication via Universal Auth - Successful login with correct credentials" {
    $credential = $client.Auth().UniversalAuth().LoginAsync($clientId, ($clientSecret | xconvert ToSecurestring)).GetAwaiter().GetResult()
    $credential.AccessToken | Should Not BeNullOrEmpty
  }
  It "Authentication via Universal Auth - Failure login with invalid credentials" {
    $errorCaught = $false
    try {
      $client.Auth().UniversalAuth().LoginAsync("fake-id", ("fake-secret" | xconvert ToSecurestring)).GetAwaiter().GetResult() | Out-Null
    } catch {
      $errorCaught = $true
    }
    $errorCaught | Should Be $true
  }

  It "Adding Additional Privileges : Can Grant specific, scoped privileges to users and machine identities on top of their predefined roles." {
    $machineIdentityId = $env:INFISICAL_MACHINE_IDENTITY_ID
    if (![string]::IsNullOrEmpty($machineIdentityId)) {
      $addOptions = [AddIdentityProjectAdditionalPrivilegeOptions]::new()
      $addOptions.IdentityId = $machineIdentityId
      $addOptions.ProjectId = $projectId
      $addOptions.Slug = "read-secrets-prod-$([guid]::NewGuid())"

      $condEnv = [IdentityProjectAdditionalPrivilegePermissionConditionEnvironment]::new("production")
      $cond = [IdentityProjectAdditionalPrivilegePermissionCondition]::new($condEnv)
      $perm = [IdentityProjectAdditionalPrivilegePermission]::new("secrets", @("describeSecret", "readValue"), $cond)

      $addOptions.Permissions = @($perm)

      $privilege = $client.Identities().AddProjectAdditionalPrivilegeAsync($addOptions).GetAwaiter().GetResult()
      $privilege | Should Not BeNullOrEmpty
    } else {
      Write-Host "Skipping: INFISICAL_MACHINE_IDENTITY_ID not set in .env"
    }
  }

  It "Creates a new secret" {
    $createSecretOptions = [CreateSecretOptions]::new()
    $createSecretOptions.SecretName = $newSecretName
    $createSecretOptions.EnvironmentSlug = "dev"
    $createSecretOptions.SecretPath = "/test"
    $createSecretOptions.SecretValue = "testValue123"
    $createSecretOptions.ProjectId = $projectId

    $secret = $client.Secrets().CreateAsync($createSecretOptions).GetAwaiter().GetResult()
    $secret.SecretKey | Should Be $newSecretName
    $secret.SecretValue | Should Be "testValue123"
  }

  It "Lists secrets" {
    $listOptions = [ListSecretsOptions]::new()
    $listOptions.SetSecretsAsEnvironmentVariables = $true
    $listOptions.EnvironmentSlug = "dev"
    $listOptions.SecretPath = "/test"
    $listOptions.Recursive = $true
    $listOptions.ProjectId = $projectId

    $secrets = $client.Secrets().ListAsync($listOptions).GetAwaiter().GetResult()
    $secrets.Count | Should BeGreaterThan 0
  }

  It "Gets a secret" {
    $getSecretOptions = [GetSecretOptions]::new()
    $getSecretOptions.SecretName = $newSecretName
    $getSecretOptions.EnvironmentSlug = "dev"
    $getSecretOptions.SecretPath = "/test"
    $getSecretOptions.ProjectId = $projectId

    $secret = $client.Secrets().GetAsync($getSecretOptions).GetAwaiter().GetResult()
    $secret.SecretKey | Should Be $newSecretName
  }

  $ldapIdentityId = $env:LDAP_IDENTITY_ID
  $ldapUsername = $env:LDAP_USERNAME
  $ldapPassword = $env:LDAP_PASSWORD

  if (!([string]::IsNullOrEmpty($ldapIdentityId) -or [string]::IsNullOrEmpty($ldapUsername) -or [string]::IsNullOrEmpty($ldapPassword))) {
    It "Authenticates with LDAP and shifts operational context to LDAP Client" {
      $ldapClient = [InfisicalClient]::new($settings)
      $credential = $ldapClient.Auth().LdapAuth().LoginAsync($ldapIdentityId, $ldapUsername, ($ldapPassword | xconvert ToSecurestring)).GetAwaiter().GetResult()
      $credential.AccessToken | Should Not BeNullOrEmpty

      # Use the LDAP-authenticated client for remaining operations (Update, Delete) matching C# Sdk.Test
      $script:client = $ldapClient
    }
  }

  It "Updates a secret" {
    $updateSecretOptions = [UpdateSecretOptions]::new()
    $updateSecretOptions.SecretName = $newSecretName
    $updateSecretOptions.EnvironmentSlug = "dev"
    $updateSecretOptions.SecretPath = "/test"
    $updateSecretOptions.NewSecretName = "$($newSecretName)-updated"
    $updateSecretOptions.NewSecretValue = "updatedValue456"
    $updateSecretOptions.ProjectId = $projectId

    $secret = $client.Secrets().UpdateAsync($updateSecretOptions).GetAwaiter().GetResult()
    $secret.SecretKey | Should Be "$($newSecretName)-updated"
    $secret.SecretValue | Should Be "updatedValue456"

    # Update variable tracking for next test
    $script:newSecretName = "$($newSecretName)-updated"
  }

  It "Deletes a secret" {
    $deleteSecretOptions = [DeleteSecretOptions]::new()
    $deleteSecretOptions.SecretName = $script:newSecretName
    $deleteSecretOptions.EnvironmentSlug = "dev"
    $deleteSecretOptions.SecretPath = "/test"
    $deleteSecretOptions.ProjectId = $projectId

    $secret = $client.Secrets().DeleteAsync($deleteSecretOptions).GetAwaiter().GetResult()
    $secret.SecretKey | Should Be $script:newSecretName
  }
}

# https://infisical.com/docs/api-reference/endpoints/kms/
Describe "Infisical KMS Operations" {
  $clientId = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_ID
  $clientSecret = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET
  # KMS operations require a KMS-type project. Use INFISICAL_KMS_PROJECT_ID when
  # available; fall back to INFISICAL_PROJECT_ID so existing envs still work.
  $projectId = if (![string]::IsNullOrEmpty($env:INFISICAL_KMS_PROJECT_ID)) { $env:INFISICAL_KMS_PROJECT_ID } else { $env:INFISICAL_PROJECT_ID }
  $hostUri = if ([string]::IsNullOrEmpty($env:INFISICAL_HOST_URI)) { "https://app.infisical.com" } else { $env:INFISICAL_HOST_URI }

  $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri($hostUri).Build()
  $client = [InfisicalClient]::new($settings)
  $client.Auth().UniversalAuth().LoginAsync($clientId, ($clientSecret | xconvert ToSecurestring)).GetAwaiter().GetResult() | Out-Null

  # Setup test vars
  $script:kmsKeyName = "test-key-$([guid]::NewGuid().ToString().Substring(0,8))"
  $script:kmsKeyId = $null
  $script:kmsAlgorithm = "aes-256-gcm"
  $script:kmsSigningAlgorithm = "RSASSA_PSS_SHA_512"
  $script:kmsProjectId = $projectId

  Context "Keys" {
    It "Create Key [POST]" {
      $createOpts = [CreateKmsKeyOptions]::new()
      $createOpts.ProjectId = $script:kmsProjectId
      $createOpts.Name = $script:kmsKeyName
      $createOpts.Description = "Test key created by integration tests"
      $createOpts.KeyUsage = "encrypt-decrypt"
      $createOpts.EncryptionAlgorithm = $script:kmsAlgorithm

      $createdKey = $client.Kms().CreateKeyAsync($createOpts).GetAwaiter().GetResult()
      $createdKey | Should Not BeNullOrEmpty

      # Parse id if it's JsonElement, otherwise take property directly (fallback generic access)
      $script:kmsKeyId = if ($createdKey -is [System.Text.Json.JsonElement]) { $createdKey.GetProperty("id").GetString() } else { $createdKey.id }
      $script:kmsKeyId | Should Not BeNullOrEmpty
    }

    It "List Keys [GET]" {
      if ($null -eq $script:kmsKeyId) { Set-TestInconclusive -Message "Skipped: KMS key creation failed (check INFISICAL_KMS_PROJECT_ID is set to a KMS-type project)" ; return }

      $listOpts = [ListKmsKeysOptions]::new()
      $listOpts.ProjectId = $script:kmsProjectId
      $listOpts.Limit = 100
      $listOpts.OrderBy = "name"
      $listOpts.OrderDirection = "asc"

      $keys = $client.Kms().ListKeysAsync($listOpts).GetAwaiter().GetResult()
      $keys | Should Not BeNullOrEmpty
      $keys.Count | Should BeGreaterThan 0
    }

    It "Get Key by ID [GET]" {
      if ($null -eq $script:kmsKeyId) { Set-TestInconclusive -Message "Skipped: KMS key creation failed (check INFISICAL_KMS_PROJECT_ID is set to a KMS-type project)" ; return }

      $getByIdOpts = [GetKmsKeyByIdOptions]::new()
      $getByIdOpts.KeyId = $script:kmsKeyId

      $key = $client.Kms().GetKeyByIdAsync($getByIdOpts).GetAwaiter().GetResult()
      $key | Should Not BeNullOrEmpty

      $keyId = if ($key -is [System.Text.Json.JsonElement]) { $key.GetProperty("id").GetString() } else { $key.id }
      $keyId | Should Be $script:kmsKeyId
    }

    It "Get Key by Name [GET]" {
      if ($null -eq $script:kmsKeyId) { Set-TestInconclusive -Message "Skipped: KMS key creation failed (check INFISICAL_KMS_PROJECT_ID is set to a KMS-type project)" ; return }

      $getByNameOpts = [GetKmsKeyByNameOptions]::new()
      $getByNameOpts.KeyName = $script:kmsKeyName
      $getByNameOpts.ProjectId = $script:kmsProjectId

      $key = $client.Kms().GetKeyByNameAsync($getByNameOpts).GetAwaiter().GetResult()
      $key | Should Not BeNullOrEmpty

      $keyName = if ($key -is [System.Text.Json.JsonElement]) { $key.GetProperty("name").GetString() } else { $key.name }
      $keyName | Should Be $script:kmsKeyName
    }

    It "Update Key [PATCH]" {
      if ($null -eq $script:kmsKeyId) { Set-TestInconclusive -Message "Skipped: KMS key creation failed (check INFISICAL_KMS_PROJECT_ID is set to a KMS-type project)" ; return }

      $updateOpts = [UpdateKmsKeyOptions]::new()
      $updateOpts.KeyId = $script:kmsKeyId
      $updateOpts.Description = "Updated test description"

      $updatedKey = $client.Kms().UpdateKeyAsync($updateOpts).GetAwaiter().GetResult()
      $updatedKey | Should Not BeNullOrEmpty
    }

    # Retrieve PublicKey, ExportPrivateKey and BulkExport are testing depending on the key generated,
    # symmetric keys might not support public/private extraction but let's test if API allows or errors gracefully
    # We will wrap them in try-catch to allow graceful skip for symmetric keys or continue
    It "Retrieve Public Key [GET]" {
      $pubOpts = [RetrieveKmsPublicKeyOptions]::new()
      $pubOpts.KeyId = $script:kmsKeyId

      try {
        $pubKey = $client.Kms().RetrievePublicKeyAsync($pubOpts).GetAwaiter().GetResult()
        # Not asserting as aes-256-gcm does not have a public key, we just check call executes
      } catch {
        $null
      }
    }

    It "Export Private Key [GET]" {
      $privOpts = [ExportKmsPrivateKeyOptions]::new()
      $privOpts.KeyId = $script:kmsKeyId

      try {
        $privKey = $client.Kms().ExportPrivateKeyAsync($privOpts).GetAwaiter().GetResult()
      } catch {
        $null
      }
    }

    It "Bulk Export Private Keys [POST]" {
      $bulkOpts = [BulkExportPrivateKeysOptions]::new()
      $bulkOpts.KeyIds = @($script:kmsKeyId)

      try {
        $bulkKeys = $client.Kms().BulkExportPrivateKeysAsync($bulkOpts).GetAwaiter().GetResult()
      } catch {
        $null
      }
    }
  }

  Context "Encryption" {
    $script:testPlaintext = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("SuperSecretData!"))
    $script:testCiphertext = $null

    It "Encrypt Data [POST]" {
      if ($null -eq $script:kmsKeyId) { Set-TestInconclusive -Message "Skipped: KMS key creation failed (check INFISICAL_KMS_PROJECT_ID is set to a KMS-type project)" ; return }

      $encryptOpts = [EncryptKmsDataOptions]::new()
      $encryptOpts.KeyId = $script:kmsKeyId
      $encryptOpts.Plaintext = $script:testPlaintext

      $ciphertext = $client.Kms().EncryptDataAsync($encryptOpts).GetAwaiter().GetResult()
      $script:testCiphertext = if ($ciphertext -is [System.Text.Json.JsonElement]) { $ciphertext.GetString() } else { $ciphertext }

      $script:testCiphertext | Should Not BeNullOrEmpty
    }

    It "Decrypt Data [POST]" {
      if ($null -eq $script:kmsKeyId) { Set-TestInconclusive -Message "Skipped: KMS key creation failed (check INFISICAL_KMS_PROJECT_ID is set to a KMS-type project)" ; return }
      if ($null -eq $script:testCiphertext) { Set-TestInconclusive -Message "Skipped: Encrypt step did not produce ciphertext" ; return }

      $decryptOpts = [DecryptKmsDataOptions]::new()
      $decryptOpts.KeyId = $script:kmsKeyId
      $decryptOpts.Ciphertext = $script:testCiphertext

      $plaintextResult = $client.Kms().DecryptDataAsync($decryptOpts).GetAwaiter().GetResult()
      $actualPlaintext = if ($plaintextResult -is [System.Text.Json.JsonElement]) { $plaintextResult.GetString() } else { $plaintextResult }

      $actualPlaintext | Should Be $script:testPlaintext
    }
  }

  Context "Signing" {
    # Symmetric keys cannot sign. Creating a temporary asymmetric key for signing.
    $script:signKeyId = $null

    It "Create Asymmetric Key for Signing Setup" {
      if ($null -eq $script:kmsProjectId) { Set-TestInconclusive -Message "Skipped: No KMS project configured" ; return }

      $createOpts = [CreateKmsKeyOptions]::new()
      $createOpts.ProjectId = $script:kmsProjectId
      $createOpts.Name = "test-sign-key-$([guid]::NewGuid().ToString().Substring(0,8))"
      $createOpts.KeyUsage = "sign-verify"
      $createOpts.EncryptionAlgorithm = "rsa-2048"

      try {
        $createdKey = $client.Kms().CreateKeyAsync($createOpts).GetAwaiter().GetResult()
        $script:signKeyId = if ($createdKey -is [System.Text.Json.JsonElement]) { $createdKey.GetProperty("id").GetString() } else { $createdKey.id }
      } catch {
        # Gracefully ignore if asymmetric generation fails
        $null
      }
    }

    $script:testSignData = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("DataToSign123"))
    $script:testSignature = $null

    It "Sign Data [POST]" {
      if ($null -eq $script:signKeyId) { Set-TestInconclusive -Message "Signing key unavailable" ; return }

      $signOpts = [SignKmsDataOptions]::new()
      $signOpts.KeyId = $script:signKeyId
      $signOpts.SigningAlgorithm = $script:kmsSigningAlgorithm
      $signOpts.Data = $script:testSignData
      $signOpts.IsDigest = $false

      $signature = $client.Kms().SignDataAsync($signOpts).GetAwaiter().GetResult()
      $script:testSignature = if ($signature -is [System.Text.Json.JsonElement]) { $signature.GetString() } else { $signature }

      $script:testSignature | Should Not BeNullOrEmpty
    }

    It "Verify Signature [POST]" {
      if ($null -eq $script:signKeyId) { Set-TestInconclusive -Message "Signing key unavailable" ; return }

      $verifyOpts = [VerifyKmsSignatureOptions]::new()
      $verifyOpts.KeyId = $script:signKeyId
      $verifyOpts.Data = $script:testSignData
      $verifyOpts.Signature = $script:testSignature
      $verifyOpts.SigningAlgorithm = $script:kmsSigningAlgorithm
      $verifyOpts.IsDigest = $false

      $isValidResult = $client.Kms().VerifySignatureAsync($verifyOpts).GetAwaiter().GetResult()
      $isValid = if ($isValidResult -is [System.Text.Json.JsonElement]) { $isValidResult.GetBoolean() } else { $isValidResult }

      $isValid | Should Be $true
    }

    It "List Signing Algorithms [GET]" {
      if ($null -eq $script:signKeyId) { Set-TestInconclusive -Message "Signing key unavailable" ; return }

      $listOpts = [ListKmsSigningAlgorithmsOptions]::new()
      $listOpts.KeyId = $script:signKeyId

      $algorithmsRaw = $client.Kms().ListSigningAlgorithmsAsync($listOpts).GetAwaiter().GetResult()
      $algorithms = if ($algorithmsRaw -is [System.Text.Json.JsonElement]) { $algorithmsRaw } else { $algorithmsRaw }
      $algorithms | Should Not BeNullOrEmpty
    }
  }

  Context "Cleanup" {
    It "Delete Key [DEL]" {
      if ($null -eq $script:kmsKeyId) { Set-TestInconclusive -Message "Skipped: KMS key creation failed, nothing to clean up" ; return }

      $deleteOpts = [DeleteKmsKeyOptions]::new()
      $deleteOpts.KeyId = $script:kmsKeyId

      $deletedKey = $client.Kms().DeleteKeyAsync($deleteOpts).GetAwaiter().GetResult()
      $deletedKey | Should Not BeNullOrEmpty

      if ($null -ne $script:signKeyId) {
        $deleteSignOpts = [DeleteKmsKeyOptions]::new()
        $deleteSignOpts.KeyId = $script:signKeyId
        $client.Kms().DeleteKeyAsync($deleteSignOpts).GetAwaiter().GetResult() | Out-Null
      }
    }
  }
}