# docs

**[Infisical](https://infisical.com)** is the open source secret management platform that teams use to centralize their secrets like API keys, database credentials, and configurations.

This module provides a native PowerShell interface to interact with the Infisical API using pure PowerShell classes.

## Initialization

First, import the module and initialize the client:

```powershell
Import-Module ./infisical.psm1

$settings = [InfisicalSdkSettingsBuilder]::new().WithHostUri("https://app.infisical.com").Build()
$client = [InfisicalClient]::new($settings)
```

## Authentication

The module supports multiple authentication methods including Universal Auth and LDAP Auth.

### Universal Auth

```powershell
$clientId = "your-client-id"
$clientSecret = "your-client-secret"

# Execute the Task and wait for result synchronously
$credential = $client.Auth().UniversalAuth().LoginAsync($clientId, $clientSecret).GetAwaiter().GetResult()
Write-Host "Logged in successfully. Token type: $($credential.TokenType)"
```

## Managing Secrets

You can create, get, update, delete, and list secrets via `$client.Secrets()`.

### Get a Secret

```powershell
$options = [GetSecretOptions]::new()
$options.ProjectId = "your-project-id"
$options.EnvironmentSlug = "dev"
$options.SecretPath = "/"
$options.SecretName = "DATABASE_URL"

$secret = $client.Secrets().GetAsync($options).GetAwaiter().GetResult()
Write-Host "Retrieved $($secret.SecretKey): $($secret.SecretValue) in $($secret.Environment)"
```

### Create a Secret

```powershell
$createOptions = [CreateSecretOptions]::new()
$createOptions.ProjectId = "your-project-id"
$createOptions.EnvironmentSlug = "dev"
$createOptions.SecretPath = "/"
$createOptions.SecretName = "API_KEY"
$createOptions.SecretValue = "super_secret_value"

$newSecret = $client.Secrets().CreateAsync($createOptions).GetAwaiter().GetResult()
Write-Host "Created Secret: $($newSecret.SecretKey)"
```

### Update a Secret

```powershell
$updateOptions = [UpdateSecretOptions]::new()
$updateOptions.ProjectId = "your-project-id"
$updateOptions.EnvironmentSlug = "dev"
$updateOptions.SecretPath = "/"
$updateOptions.SecretName = "API_KEY"
$updateOptions.NewSecretValue = "new_super_secret_value"

$updatedSecret = $client.Secrets().UpdateAsync($updateOptions).GetAwaiter().GetResult()
```

### Delete a Secret

```powershell
$deleteOptions = [DeleteSecretOptions]::new()
$deleteOptions.ProjectId = "your-project-id"
$deleteOptions.EnvironmentSlug = "dev"
$deleteOptions.SecretPath = "/"
$deleteOptions.SecretName = "API_KEY"

$deletedSecret = $client.Secrets().DeleteAsync($deleteOptions).GetAwaiter().GetResult()
```

### List Secrets (Including Imports)

```powershell
$listOptions = [ListSecretsOptions]::new()
$listOptions.ProjectId = "your-project-id"
$listOptions.EnvironmentSlug = "dev"
$listOptions.SecretPath = "/"
$listOptions.ExpandSecretReferences = $true
$listOptions.SetSecretsAsEnvironmentVariables = $true # Automatically maps to Env

$secrets = $client.Secrets().ListAsync($listOptions).GetAwaiter().GetResult()

foreach ($s in $secrets) {
    Write-Host "$($s.SecretKey) = $($s.SecretValue) (Version $($s.Version))"
}
```

## PKI and Certificates

Use `$client.Pki()` to interact with the Public Key Infrastructure features.

### Issue a Certificate

```powershell
$issueOptions = [IssueCertificateOptions]::new()
$issueOptions.ProjectId = "your-project-id"
$issueOptions.SubscriberName = "my-subscriber"

$cert = $client.Pki().Subscribers().IssueCertificateAsync($issueOptions).GetAwaiter().GetResult()

Write-Host $cert.Certificate
Write-Host $cert.PrivateKey
```

### Retrieve Latest Certificate Bundle

```powershell
$retrieveOptions = [RetrieveLatestCertificateBundleOptions]::new()
$retrieveOptions.ProjectId = "your-project-id"
$retrieveOptions.SubscriberName = "my-subscriber"

$latestCert = $client.Pki().Subscribers().RetrieveLatestCertificateBundleAsync($retrieveOptions).GetAwaiter().GetResult()

Write-Host $latestCert.Certificate
```