using namespace System.Text
using namespace System.Security.Cryptography
using module ..\infisical.psm1

Describe "Infisical DeadlockTest" {
  It "Does not deadlock when using synchronous blocking (.GetAwaiter().GetResult())" {
    $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri("https://app.infisical.com").Build()
    $client = [InfisicalClient]::new($settings)

    # In PowerShell, calling .GetAwaiter().GetResult() on the main thread
    # could cause deadlocks if SynchronizationContext is tricky.
    # Here we expect it to fail gracefully with an auth error, NOT freeze.
    $errorCaught = $false
    try {
      $client.Auth().UniversalAuth().LoginAsync("fake-id", "fake-secret").GetAwaiter().GetResult() | Out-Null
    } catch {
      $errorCaught = $true
    }
    $errorCaught | Should Be $true
  }
}

Describe "Infisical PSMODULE Feature tests" {
  $clientId = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_ID
  $clientSecret = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET
  $projectId = $env:INFISICAL_PROJECT_ID
  $hostUri = "http://localhost:8080"

  $runTests = (![string]::IsNullOrEmpty($clientId)) -and (![string]::IsNullOrEmpty($clientSecret)) -and (![string]::IsNullOrEmpty($projectId))

  if (!$runTests) {
    Write-Warning "Skipping Feature tests due to missing INFISICAL environment variables."
    # Fake test just to not skip completely if we're not running them via Context
    It "Skipped Integration Tests" {
      $true | Should Be $true
    }
    return
  }

  $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri($hostUri).Build()
  $client = [InfisicalClient]::new($settings)
  $newSecretName = "INFISICAL-PSMODULE-TEST-$([guid]::NewGuid())"

  It "Authenticates with Universal Auth" {
    $credential = $client.Auth().UniversalAuth().LoginAsync($clientId, ($clientSecret | xconvert ToSecurestring)).GetAwaiter().GetResult()
    $credential.AccessToken | Should Not BeNullOrEmpty
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

  $ldapIdentityId = $env:LDAP_IDENTITY_ID
  $ldapUsername = $env:LDAP_USERNAME
  $ldapPassword = $env:LDAP_PASSWORD

  if (!([string]::IsNullOrEmpty($ldapIdentityId) -or [string]::IsNullOrEmpty($ldapUsername) -or [string]::IsNullOrEmpty($ldapPassword))) {
    It "Authenticates with LDAP (if env setup)" {
      $ldapClient = [InfisicalClient]::new($settings)
      $credential = $ldapClient.Auth().LdapAuth().LoginAsync($ldapIdentityId, $ldapUsername, ($ldapPassword | xconvert ToSecurestring)).GetAwaiter().GetResult()
      $credential.AccessToken | Should Not BeNullOrEmpty
      # Reassign for deletion
      $script:client = $ldapClient
    }
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
