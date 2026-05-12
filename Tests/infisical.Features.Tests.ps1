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
    }
    catch {
      $errorCaught = $true
    }
    $errorCaught | Should Be $true
  }

  $machineIdentityId = $env:INFISICAL_MACHINE_IDENTITY_ID
  if (![string]::IsNullOrEmpty($machineIdentityId)) {
    It "Adding Additional Privileges : Can Grant specific, scoped privileges to users and machine identities on top of their predefined roles." {
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
    }
  }
  else {
    It "Adding Additional Privileges : Can Grant specific, scoped privileges to users and machine identities on top of their predefined roles." {
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
<#
# https://infisical.com/docs/api-reference/endpoints/kms/
Describe "Infisical KMS Operations" {
  Context "Keys" {
    It "List Keys [GET]" {
      curl --request GET \
      --url 'https://us.infisical.com/api/v1/kms/keys?limit=100&orderBy=name&orderDirection=asc'
    }

    It "Get Key by ID [GET]" {
      curl --request GET \
      --url https://us.infisical.com/api/v1/kms/keys/{keyId}
    }

    It "Get Key by Name [GET]" {
      curl --request GET \
      --url https://us.infisical.com/api/v1/kms/keys/key-name/{keyName}
    }

    It "Create Key [POST]" {
    curl --request POST \
      --url https://us.infisical.com/api/v1/kms/keys \
      --header 'Content-Type: application/json' \
      --data '
      {
        "projectId": "<string>",
        "name": "<string>",
        "description": "<string>",
        "keyUsage": "encrypt-decrypt",
        "encryptionAlgorithm": "aes-256-gcm"
      }
      '
    }

    It "Update Key [PATCH]" {
    curl --request PATCH \
      --url https://us.infisical.com/api/v1/kms/keys/{keyId} \
      --header 'Content-Type: application/json' \
      --data '
      {
        "name": "<string>",
        "isDisabled": true,
        "description": "<string>"
      }
      '
    }

    It "Delete Key [DEL]" {
      curl --request DELETE --url https://us.infisical.com/api/v1/kms/keys/{keyId}

    }

    It "Retrieve Public Key [GET]" {
      curl --request GET --url https://us.infisical.com/api/v1/kms/keys/{keyId}/public-key
    }

    It "Export Private Key [GET]" {
       curl --request GET --url https://us.infisical.com/api/v1/kms/keys/{keyId}/private-key
    }

    It "Bulk Export Private Keys [POST]" {
      curl --request POST \
      --url https://us.infisical.com/api/v1/kms/keys/bulk-export-private-keys \
      --header 'Content-Type: application/json' \
      --data '
      {
        "keyIds": [
          "3c90c3cc-0d44-4b50-8888-8dd25736052a"
        ]
      }
      '
    }
  }

  Context "Encryption" {
    It "Encrypt Data [POST]" {
    curl --request POST \
        --url https://us.infisical.com/api/v1/kms/keys/{keyId}/encrypt \
        --header 'Content-Type: application/json' \
        --data '
      {
        "plaintext": "<string>"
      }
      '
    }

    It "Decrypt Data [POST]" {
    curl --request POST \
        --url https://us.infisical.com/api/v1/kms/keys/{keyId}/decrypt \
        --header 'Content-Type: application/json' \
        --data '
      {
        "ciphertext": "<string>"
      }
      '
    }
  }

  Context "Signing" {
    It "Sign Data [POST]" {
    curl --request POST \
        --url https://us.infisical.com/api/v1/kms/keys/{keyId}/sign \
        --header 'Content-Type: application/json' \
        --data '
      {
        "signingAlgorithm": "RSASSA_PSS_SHA_512",
        "data": "<string>",
        "isDigest": false
      }
      '
    }

    It "Verify Signature [POST]" {
    curl --request POST \
        --url https://us.infisical.com/api/v1/kms/keys/{keyId}/verify \
        --header 'Content-Type: application/json' \
        --data '
      {
        "data": "<string>",
        "signature": "<string>",
        "signingAlgorithm": "RSASSA_PSS_SHA_512",
        "isDigest": false
      }
      '
    }

    It "List Signing Algorithms [GET]" {
      curl --request GET --url https://us.infisical.com/api/v1/kms/keys/{keyId}/signing-algorithms
    }
  }
}

#>