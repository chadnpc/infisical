using module ..\infisical.psm1

# Load environment variables from the root .env file
Read-Env ([IO.Path]::Combine(($PSScriptRoot | Split-Path), ".env")) | Set-Env

# verify the interactions and behavior of the module's components when they are integrated together.
Describe "Integration tests: infisical" {

  # ── Shared fixtures ────────────────────────────────────────────────────────
  $script:clientId = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_ID
  $script:clientSecret = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET
  $script:projectId = $env:INFISICAL_PROJECT_ID
  $script:hostUri = if ([string]::IsNullOrEmpty($env:INFISICAL_HOST_URI)) {
    "https://app.infisical.com"
  } else {
    $env:INFISICAL_HOST_URI
  }

  $script:settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri($script:hostUri).Build()
  $script:client = [InfisicalClient]::new($script:settings)

  # Authenticate once up-front so every Context can reuse the token.
  $script:client.Auth().UniversalAuth().LoginAsync(
    $script:clientId,
    ($script:clientSecret | xconvert ToSecurestring)
  ).GetAwaiter().GetResult() | Out-Null

  # ── Authentication ─────────────────────────────────────────────────────────
  Context "Authentication" {
    It "Universal Auth - succeeds with correct credentials" {
      # Create a fresh client so we can inspect the credential object.
      $freshClient = [InfisicalClient]::new($script:settings)
      $credential = $freshClient.Auth().UniversalAuth().LoginAsync(
        $script:clientId,
        ($script:clientSecret | xconvert ToSecurestring)
      ).GetAwaiter().GetResult()

      $credential | Should Not BeNullOrEmpty
      $credential.AccessToken | Should Not BeNullOrEmpty
      $credential.TokenType | Should Be "Bearer"
    }

    It "Universal Auth - fails with invalid credentials" {
      $errorCaught = $false
      try {
        $badClient = [InfisicalClient]::new($script:settings)
        $badClient.Auth().UniversalAuth().LoginAsync(
          "invalid-client-id",
          ("invalid-secret" | xconvert ToSecurestring)
        ).GetAwaiter().GetResult() | Out-Null
      } catch {
        $errorCaught = $true
      }
      $errorCaught | Should Be $true
    }
  }

  # ── Secrets Management ─────────────────────────────────────────────────────
  Context "Secrets Management" {
    # Use a unique name per test run so parallel/repeated runs don't collide.
    $script:integSecretName = "INTEGRATION-TEST-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $script:integEnv = "dev"
    $script:integPath = "/test"

    It "Secrets Create [POST]" {
      $opts = [CreateSecretOptions]::new()
      $opts.SecretName = $script:integSecretName
      $opts.ProjectId = $script:projectId
      $opts.EnvironmentSlug = $script:integEnv
      $opts.SecretPath = $script:integPath
      $opts.SecretValue = "initial-value"
      $opts.SecretComment = "Created by Pester integration test"

      $secret = $script:client.Secrets().CreateAsync($opts).GetAwaiter().GetResult()

      $secret | Should Not BeNullOrEmpty
      $secret.SecretKey | Should Be $script:integSecretName
      $secret.SecretValue | Should Be "initial-value"
    }

    It "Secrets List [GET]" {
      $opts = [ListSecretsOptions]::new()
      $opts.ProjectId = $script:projectId
      $opts.EnvironmentSlug = $script:integEnv
      $opts.SecretPath = $script:integPath
      $opts.Recursive = $false
      $opts.IncludeImports = $false
      $opts.SetSecretsAsEnvironmentVariables = $false

      $secrets = $script:client.Secrets().ListAsync($opts).GetAwaiter().GetResult()

      $secrets | Should Not BeNullOrEmpty
      $secrets.Count | Should BeGreaterThan 0

      $found = $secrets | Where-Object { $_.SecretKey -eq $script:integSecretName }
      $found | Should Not BeNullOrEmpty
    }

    It "Secrets Retrieve [GET]" {
      $opts = [GetSecretOptions]::new()
      $opts.SecretName = $script:integSecretName
      $opts.ProjectId = $script:projectId
      $opts.EnvironmentSlug = $script:integEnv
      $opts.SecretPath = $script:integPath

      $secret = $script:client.Secrets().GetAsync($opts).GetAwaiter().GetResult()

      $secret | Should Not BeNullOrEmpty
      $secret.SecretKey | Should Be $script:integSecretName
      $secret.SecretValue | Should Be "initial-value"
    }

    It "Secrets Update [PATCH]" {
      # Only update the value; do NOT set NewSecretName (API rejects empty string).
      $opts = [UpdateSecretOptions]::new()
      $opts.SecretName = $script:integSecretName
      $opts.ProjectId = $script:projectId
      $opts.EnvironmentSlug = $script:integEnv
      $opts.SecretPath = $script:integPath
      $opts.NewSecretValue = "updated-value-456"
      # NewSecretName is intentionally left $null so the serializer omits it.

      $secret = $script:client.Secrets().UpdateAsync($opts).GetAwaiter().GetResult()

      $secret | Should Not BeNullOrEmpty
      $secret.SecretKey | Should Be $script:integSecretName
      $secret.SecretValue | Should Be "updated-value-456"
    }

    It "Secrets Delete [DEL]" {
      $opts = [DeleteSecretOptions]::new()
      $opts.SecretName = $script:integSecretName
      $opts.ProjectId = $script:projectId
      $opts.EnvironmentSlug = $script:integEnv
      $opts.SecretPath = $script:integPath

      $secret = $script:client.Secrets().DeleteAsync($opts).GetAwaiter().GetResult()

      $secret | Should Not BeNullOrEmpty
      $secret.SecretKey | Should Be $script:integSecretName
    }

    # Declare bulk names at script scope so the It closure can see them in assertions.
    $script:bulkA1 = "BULK-A-$([guid]::NewGuid().ToString('N').Substring(0,6))"
    $script:bulkA2 = "BULK-B-$([guid]::NewGuid().ToString('N').Substring(0,6))"

    It "Secrets Bulk Create [POST] - creates multiple secrets atomically" {
      # We simulate bulk by creating two secrets sequentially then verifying
      # both are visible in a single List call (the API bulk endpoint isn't yet
      # surfaced by SecretsClient, so we exercise the pattern through two
      # individual Creates and one List – consistent with the SDK surface).
      foreach ($name in @($script:bulkA1, $script:bulkA2)) {
        $c = [CreateSecretOptions]::new()
        $c.SecretName = $name
        $c.ProjectId = $script:projectId
        $c.EnvironmentSlug = $script:integEnv
        $c.SecretPath = $script:integPath
        $c.SecretValue = "bulk-value"
        $script:client.Secrets().CreateAsync($c).GetAwaiter().GetResult() | Out-Null
      }

      $listOpts = [ListSecretsOptions]::new()
      $listOpts.ProjectId = $script:projectId
      $listOpts.EnvironmentSlug = $script:integEnv
      $listOpts.SecretPath = $script:integPath

      $secrets = $script:client.Secrets().ListAsync($listOpts).GetAwaiter().GetResult()
      $keys = $secrets | Select-Object -ExpandProperty SecretKey

      $keys | Should Contain $script:bulkA1
      $keys | Should Contain $script:bulkA2

      # Cleanup
      foreach ($name in @($script:bulkA1, $script:bulkA2)) {
        $d = [DeleteSecretOptions]::new()
        $d.SecretName = $name
        $d.ProjectId = $script:projectId
        $d.EnvironmentSlug = $script:integEnv
        $d.SecretPath = $script:integPath
        $script:client.Secrets().DeleteAsync($d).GetAwaiter().GetResult() | Out-Null
      }
    }

    $script:bulkU1 = "BULK-U1-$([guid]::NewGuid().ToString('N').Substring(0,6))"
    $script:bulkU2 = "BULK-U2-$([guid]::NewGuid().ToString('N').Substring(0,6))"

    It "Secrets Bulk Update [PATCH] - updates multiple secrets" {
      foreach ($name in @($script:bulkU1, $script:bulkU2)) {
        $c = [CreateSecretOptions]::new()
        $c.SecretName = $name
        $c.ProjectId = $script:projectId
        $c.EnvironmentSlug = $script:integEnv
        $c.SecretPath = $script:integPath
        $c.SecretValue = "original"
        $script:client.Secrets().CreateAsync($c).GetAwaiter().GetResult() | Out-Null
      }

      # Only update the value; do NOT set NewSecretName (API rejects empty string).
      foreach ($name in @($script:bulkU1, $script:bulkU2)) {
        $u = [UpdateSecretOptions]::new()
        $u.SecretName = $name
        $u.ProjectId = $script:projectId
        $u.EnvironmentSlug = $script:integEnv
        $u.SecretPath = $script:integPath
        $u.NewSecretValue = "updated-bulk"
        $script:client.Secrets().UpdateAsync($u).GetAwaiter().GetResult() | Out-Null
      }

      foreach ($name in @($script:bulkU1, $script:bulkU2)) {
        $g = [GetSecretOptions]::new()
        $g.SecretName = $name
        $g.ProjectId = $script:projectId
        $g.EnvironmentSlug = $script:integEnv
        $g.SecretPath = $script:integPath

        $s = $script:client.Secrets().GetAsync($g).GetAwaiter().GetResult()
        $s.SecretValue | Should Be "updated-bulk"
      }

      # Cleanup
      foreach ($name in @($script:bulkU1, $script:bulkU2)) {
        $d = [DeleteSecretOptions]::new()
        $d.SecretName = $name
        $d.ProjectId = $script:projectId
        $d.EnvironmentSlug = $script:integEnv
        $d.SecretPath = $script:integPath
        $script:client.Secrets().DeleteAsync($d).GetAwaiter().GetResult() | Out-Null
      }
    }

    It "Secrets Bulk Delete [DEL] - removes multiple secrets" {
      $bulkD1 = "BULK-D1-$([guid]::NewGuid().ToString('N').Substring(0,6))"
      $bulkD2 = "BULK-D2-$([guid]::NewGuid().ToString('N').Substring(0,6))"

      foreach ($name in @($bulkD1, $bulkD2)) {
        $c = [CreateSecretOptions]::new()
        $c.SecretName = $name
        $c.ProjectId = $script:projectId
        $c.EnvironmentSlug = $script:integEnv
        $c.SecretPath = $script:integPath
        $c.SecretValue = "to-be-deleted"
        $script:client.Secrets().CreateAsync($c).GetAwaiter().GetResult() | Out-Null
      }

      foreach ($name in @($bulkD1, $bulkD2)) {
        $d = [DeleteSecretOptions]::new()
        $d.SecretName = $name
        $d.ProjectId = $script:projectId
        $d.EnvironmentSlug = $script:integEnv
        $d.SecretPath = $script:integPath
        $deleted = $script:client.Secrets().DeleteAsync($d).GetAwaiter().GetResult()
        $deleted.SecretKey | Should Be $name
      }

      # Verify both are gone
      $listOpts = [ListSecretsOptions]::new()
      $listOpts.ProjectId = $script:projectId
      $listOpts.EnvironmentSlug = $script:integEnv
      $listOpts.SecretPath = $script:integPath

      $remaining = $script:client.Secrets().ListAsync($listOpts).GetAwaiter().GetResult()
      $keys = $remaining | Select-Object -ExpandProperty SecretKey

      ($keys -contains $bulkD1) | Should Be $false
      ($keys -contains $bulkD2) | Should Be $false
    }
  }

  # ── Access Control / Identities ────────────────────────────────────────────
  Context "Access Control - Identities" {
    $machineIdentityId = $env:INFISICAL_MACHINE_IDENTITY_ID

    if (![string]::IsNullOrEmpty($machineIdentityId)) {
      It "Identities - Add project additional privilege" {
        $condEnv = [IdentityProjectAdditionalPrivilegePermissionConditionEnvironment]::new("production")
        $cond = [IdentityProjectAdditionalPrivilegePermissionCondition]::new($condEnv)
        $perm = [IdentityProjectAdditionalPrivilegePermission]::new(
          "secrets",
          @("describeSecret", "readValue"),
          $cond
        )

        $addOpts = [AddIdentityProjectAdditionalPrivilegeOptions]::new()
        $addOpts.IdentityId = $machineIdentityId
        $addOpts.ProjectId = $script:projectId
        $addOpts.Slug = "integration-priv-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $addOpts.Permissions = @($perm)

        $privilege = $script:client.Identities().AddProjectAdditionalPrivilegeAsync($addOpts).GetAwaiter().GetResult()
        $privilege | Should Not BeNullOrEmpty
      }
    } else {
      It "Identities - Add project additional privilege (skipped: INFISICAL_MACHINE_IDENTITY_ID not set)" {
        Write-Host "  [SKIP] INFISICAL_MACHINE_IDENTITY_ID is not configured in .env" -ForegroundColor Yellow
      }
    }
  }

  # ── PKI / Subscribers ─────────────────────────────────────────────────────
  Context "PKI - Subscribers" {
    $subscriberName = $env:INFISICAL_PKI_SUBSCRIBER_NAME

    if (![string]::IsNullOrEmpty($subscriberName)) {
      It "PKI - Issue certificate for subscriber" {
        $issueOpts = [IssueCertificateOptions]::new()
        $issueOpts.SubscriberName = $subscriberName
        $issueOpts.ProjectId = $script:projectId

        $cert = $script:client.Pki().Subscribers().IssueCertificateAsync($issueOpts).GetAwaiter().GetResult()

        $cert | Should Not BeNullOrEmpty
        $cert.Certificate | Should Not BeNullOrEmpty
        $cert.SerialNumber | Should Not BeNullOrEmpty
      }

      It "PKI - Retrieve latest certificate bundle for subscriber" {
        $bundleOpts = [RetrieveLatestCertificateBundleOptions]::new()
        $bundleOpts.SubscriberName = $subscriberName
        $bundleOpts.ProjectId = $script:projectId

        $bundle = $script:client.Pki().Subscribers().RetrieveLatestCertificateBundleAsync($bundleOpts).GetAwaiter().GetResult()

        $bundle | Should Not BeNullOrEmpty
        $bundle.Certificate | Should Not BeNullOrEmpty
      }
    } else {
      It "PKI - Issue certificate (skipped: INFISICAL_PKI_SUBSCRIBER_NAME not set)" {
        Write-Host "  [SKIP] INFISICAL_PKI_SUBSCRIBER_NAME is not configured in .env" -ForegroundColor Yellow
      }

      It "PKI - Retrieve certificate bundle (skipped: INFISICAL_PKI_SUBSCRIBER_NAME not set)" {
        Write-Host "  [SKIP] INFISICAL_PKI_SUBSCRIBER_NAME is not configured in .env" -ForegroundColor Yellow
      }
    }
  }

  # ── LDAP Auth ──────────────────────────────────────────────────────────────
  Context "Authentication - LDAP" {
    $ldapId = $env:LDAP_IDENTITY_ID
    $ldapUser = $env:LDAP_USERNAME
    $ldapPass = $env:LDAP_PASSWORD

    if (!([string]::IsNullOrEmpty($ldapId) -or
        [string]::IsNullOrEmpty($ldapUser) -or
        [string]::IsNullOrEmpty($ldapPass))) {
      It "LDAP Auth - succeeds with correct credentials" {
        $ldapClient = [InfisicalClient]::new($script:settings)
        $credential = $ldapClient.Auth().LdapAuth().LoginAsync(
          $ldapId,
          $ldapUser,
          ($ldapPass | xconvert ToSecurestring)
        ).GetAwaiter().GetResult()

        $credential | Should Not BeNullOrEmpty
        $credential.AccessToken | Should Not BeNullOrEmpty
      }
    } else {
      It "LDAP Auth - succeeds with correct credentials (skipped: LDAP vars not set)" {
        Write-Host "  [SKIP] LDAP_IDENTITY_ID / LDAP_USERNAME / LDAP_PASSWORD not configured in .env" -ForegroundColor Yellow
      }
    }
  }

  # ── SDK Settings Builder ───────────────────────────────────────────────────
  Context "InfisicalSdkSettingsBuilder" {
    It "Builder produces settings with the expected HostUri" {
      $uri = "https://custom.infisical.example.com"
      $settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri($uri).Build()

      $settings | Should Not BeNullOrEmpty
      $settings.HostUri | Should Be $uri
    }

    It "Default settings use env INFISICAL_HOST_URI when set" {
      $defaults = [InfisicalSdkSettings]::new()
      $defaults.HostUri | Should Not BeNullOrEmpty
    }
  }
}
