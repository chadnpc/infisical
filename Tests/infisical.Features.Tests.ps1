using namespace System.Text
using namespace System.Security.Cryptography
using module ..\infisical.psm1

# Load environment variables from the root .env file
Read-Env ([IO.Path]::Combine(($PSScriptRoot | Split-Path), ".env")) | Set-Env

Describe "Infisical Login tests " {
  $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri("https://app.infisical.com").Build()
  $client = [InfisicalClient]::new($settings)
  It "Fails to login when we use invalid credentials" {
    $errorCaught = $false
    try {
      $client.Auth().UniversalAuth().LoginAsync("fake-id", ("fake-secret" | xconvert ToSecurestring)).GetAwaiter().GetResult() | Out-Null
    } catch {
      $errorCaught = $true
    }
    $errorCaught | Should Be $true
  }
  It "Successfuly login when we use correct credentials" {
    $credential = $client.Auth().UniversalAuth().LoginAsync($env:INFISICAL_MACHINE_IDENTITY_CLIENT_ID, ($env:INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET | xconvert ToSecurestring)).GetAwaiter().GetResult()
    $credential.AccessToken | Should Not BeNullOrEmpty
  }
}

Describe "Infisical Access Control tests " {
  $clientId = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_ID
  $clientSecret = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET
  $projectId = $env:INFISICAL_PROJECT_ID
  $hostUri = if ([string]::IsNullOrEmpty($env:INFISICAL_HOST_URI)) { "https://app.infisical.com" } else { $env:INFISICAL_HOST_URI }

  $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri($hostUri).Build()
  $client = [InfisicalClient]::new($settings)
  $newSecretName = "INFISICAL-ACCESS-TEST-$([guid]::NewGuid())"

  It "Authenticates with Universal Auth" {
    $credential = $client.Auth().UniversalAuth().LoginAsync($clientId, ($clientSecret | xconvert ToSecurestring)).GetAwaiter().GetResult()
    $credential.AccessToken | Should Not BeNullOrEmpty
    Write-Host "Sleeping for 5 seconds"
    Start-Sleep -Seconds 5
    Write-Host "Done sleeping"
  }

  It "Adding Additional Privileges : Can Grant specific, scoped privileges to users and machine identities on top of their predefined roles." {
    $addOptions = [AddIdentityProjectAdditionalPrivilegeOptions]::new()
    $addOptions.IdentityId = $clientId
    $addOptions.ProjectId = $projectId
    $addOptions.Slug = "read-secrets-prod-$([guid]::NewGuid())"

    $condEnv = [IdentityProjectAdditionalPrivilegePermissionConditionEnvironment]::new("production")
    $cond = [IdentityProjectAdditionalPrivilegePermissionCondition]::new($condEnv)
    $perm = [IdentityProjectAdditionalPrivilegePermission]::new("secrets", @("read", "readValue"), $cond)

    $addOptions.Permissions = @($perm)

    $privilege = $client.Identities().AddProjectAdditionalPrivilegeAsync($addOptions).GetAwaiter().GetResult()
    $privilege | Should Not BeNullOrEmpty
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
