#!/usr/bin/env pwsh
using namespace System
using namespace System.Web
using namespace System.Text
using namespace System.Net.Http
using namespace System.Threading.Tasks
using namespace System.Text.Json
using namespace System.Text.Json.Serialization
using namespace System.Collections.Generic

using module ./Exceptions.psm1
using module ./Enums.psm1

class ApiClient : IDisposable {
  hidden [HttpClient] $_httpClient
  hidden [AllowNull()][string] $_accessToken
  hidden [ValidateNotNullOrWhiteSpace()][string] $_baseUrl
  hidden [ValidateNotNullOrEmpty()][securestring]$_clientSecret

  ApiClient([string]$baseUrl) {
    $this.Initialize($baseUrl, $null, $null)
  }
  ApiClient([string]$baseUrl, [string]$accessToken) {
    $this.Initialize($baseUrl, $null, $accessToken)
  }

  hidden [void] Initialize([string]$baseUrl, [securestring]$clientSecret, [string]$accessToken) {
    $this._httpClient = [HttpClient]::new()
    $this._baseUrl = $baseUrl;
    $this.SetAccessToken($accessToken)
    if ($null -eq $clientSecret) {
      $client_secret_env = $env:INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET
      if (![string]::IsNullOrWhiteSpace($client_secret_env)) {
        $this.SetClientSecret(($client_secret_env | xconvert ToSecurestring))
      }
    } else {
      $this.SetClientSecret($clientSecret)
    }
    $this.FormatBaseUrl()
  }

  [void] SetAccessToken([string]$accessToken) {
    $this._accessToken = $accessToken
  }

  [void] SetClientSecret([securestring]$clientSecret) {
    $this._clientSecret = $clientSecret
  }

  hidden [void] FormatBaseUrl() {
    if ($this._baseUrl.EndsWith("/")) {
      $this._baseUrl = $this._baseUrl.Substring(0, $this._baseUrl.Length - 1)
    }
    if (![RegularExpressions.Regex]::IsMatch($this._baseUrl, "^[a-zA-Z]+://.*")) {
      $this._baseUrl = "https://" + $this._baseUrl
    }
    if ($this._baseUrl.EndsWith("/api")) {
      $this._baseUrl = $this._baseUrl.Substring(0, $this._baseUrl.Length - 4)
    }
  }

  [string] GetBaseUrl() {
    return $this._baseUrl
  }

  [HttpClient] GetClient() {
    return $this._httpClient
  }

  hidden [Task[string]] FormatErrorMessageAsync([HttpResponseMessage]$response) {
    $message = "Unexpected response: $([int]$response.StatusCode) $($response.ReasonPhrase)"
    try {
      $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      if (![string]::IsNullOrEmpty($content)) {
        $message += " - $content"
      }
    } catch {
      $null
    }
    return [Task]::FromResult([string]$message)
  }

  hidden [JsonSerializerOptions] GetJsonOptions() {
    $options = [JsonSerializerOptions]::new()
    $options.PropertyNameCaseInsensitive = $true
    return $options
  }

  hidden [JsonSerializerOptions] GetJsonOptionsNullOmit() {
    $options = [JsonSerializerOptions]::new()
    $options.PropertyNameCaseInsensitive = $true
    $options.DefaultIgnoreCondition = [JsonIgnoreCondition]::WhenWritingDefault
    return $options
  }

  [Task[object]] PostAsync([Type]$responseType, [string]$url, [object]$requestBody) {
    return $this.PostAsync($responseType, $url, $requestBody, $false)
  }

  [Task[object]] PostAsync([Type]$responseType, [string]$url, [object]$requestBody, [bool]$omitNullValues) {
    try {
      $options = if ($omitNullValues) { $this.GetJsonOptionsNullOmit() } else { $this.GetJsonOptions() }
      $jsonContent = [JsonSerializer]::Serialize($requestBody, $options)
      $content = [StringContent]::new($jsonContent, [Encoding]::UTF8, "application/json")

      $request = [HttpRequestMessage]::new([HttpMethod]::Post, [Uri]::new([Uri]::new($this._baseUrl), $url))
      $request.Content = $content
      $request.Headers.Add("Accept", "application/json")

      if (![string]::IsNullOrEmpty($this._accessToken)) {
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $this._accessToken)
      }

      $response = $this._httpClient.SendAsync($request).GetAwaiter().GetResult()

      if (!$response.IsSuccessStatusCode) {
        $errorMessage = $this.FormatErrorMessageAsync($response).GetAwaiter().GetResult()
        throw [HttpRequestException]::new($errorMessage)
      }

      $responseContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

      if ([string]::IsNullOrEmpty($responseContent)) {
        throw [HttpRequestException]::new("Response body is null or empty")
      }

      $result = [JsonSerializer]::Deserialize($responseContent, $responseType, $this.GetJsonOptions())

      if ($null -eq $result) {
        throw [InfisicalException]::new("Failed to deserialize response content")
      }

      return [Task]::FromResult([object]$result)
    } catch [InfisicalException] { throw }
    catch {
      throw [InfisicalException]::new("Error during POST request: $($_.Exception.Message)", $_.Exception)
    }
  }

  [Task[object]] GetAsync([Type]$responseType, [string]$url) {
    return $this.GetAsync($responseType, $url, $null)
  }

  [Task[object]] GetAsync([Type]$responseType, [string]$url, [Dictionary[string, string]]$queryParams) {
    try {
      $uriBuilder = [UriBuilder]::new([Uri]::new([Uri]::new($this._baseUrl), $url))

      if ($null -ne $queryParams -and $queryParams.Count -gt 0) {
        $query = [HttpUtility]::ParseQueryString([string]::Empty)
        foreach ($param in $queryParams.GetEnumerator()) {
          $query[$param.Key] = $param.Value
        }
        $uriBuilder.Query = $query.ToString()
      }

      $maxRetries = 3
      $attempt = 1
      $response = $null
      while ($attempt -le $maxRetries) {
        $request = [HttpRequestMessage]::new([HttpMethod]::Get, $uriBuilder.Uri)
        $request.Headers.Add("Accept", "application/json")

        if (![string]::IsNullOrEmpty($this._accessToken)) {
          $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $this._accessToken)
        }

        try {
          $response = $this._httpClient.SendAsync($request).GetAwaiter().GetResult()
          if ($response.IsSuccessStatusCode) { break }
          else {
            $code = [int]$response.StatusCode
            if ($code -lt 500 -and $code -ne 408) { break }
          }
        } catch {
          if ($attempt -eq $maxRetries) { throw }
        }
        [System.Threading.Thread]::Sleep([TimeSpan]::FromSeconds([Math]::Pow(2, $attempt)))
        $attempt++
      }

      if (!$response.IsSuccessStatusCode) {
        $errorMessage = $this.FormatErrorMessageAsync($response).GetAwaiter().GetResult()
        throw [HttpRequestException]::new($errorMessage)
      }

      $responseContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

      if ([string]::IsNullOrEmpty($responseContent)) {
        throw [HttpRequestException]::new("Response body is null or empty")
      }

      $result = [JsonSerializer]::Deserialize($responseContent, $responseType, $this.GetJsonOptions())

      if ($null -eq $result) {
        throw [InfisicalException]::new("Failed to deserialize response content")
      }

      return [Task]::FromResult([object]$result)
    } catch [InfisicalException] { throw }
    catch {
      throw [InfisicalException]::new("Error during GET request: $($_.Exception.Message)", $_.Exception)
    }
  }

  [Task[object]] PatchAsync([Type]$responseType, [string]$url, [object]$requestBody, [bool]$omitNullValues = $false) {
    try {
      $options = if ($omitNullValues) { $this.GetJsonOptionsNullOmit() } else { $this.GetJsonOptions() }
      $jsonContent = [JsonSerializer]::Serialize($requestBody, $options)
      $content = [StringContent]::new($jsonContent, [Encoding]::UTF8, "application/json")

      $request = [HttpRequestMessage]::new([HttpMethod]::new("PATCH"), [Uri]::new([Uri]::new($this._baseUrl), $url))
      $request.Content = $content
      $request.Headers.Add("Accept", "application/json")

      if (![string]::IsNullOrEmpty($this._accessToken)) {
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $this._accessToken)
      }

      $response = $this._httpClient.SendAsync($request).GetAwaiter().GetResult()

      if (!$response.IsSuccessStatusCode) {
        $errorMessage = $this.FormatErrorMessageAsync($response).GetAwaiter().GetResult()
        throw [HttpRequestException]::new($errorMessage)
      }

      $responseContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

      if ([string]::IsNullOrEmpty($responseContent)) {
        throw [HttpRequestException]::new("Response body is null or empty")
      }

      $result = [JsonSerializer]::Deserialize($responseContent, $responseType, $this.GetJsonOptions())

      if ($null -eq $result) {
        throw [InfisicalException]::new("Failed to deserialize response content")
      }

      return [Task]::FromResult([object]$result)
    } catch [InfisicalException] { throw }
    catch {
      throw [InfisicalException]::new("Error during PATCH request: $($_.Exception.Message)", $_.Exception)
    }
  }

  [Task[object]] DeleteAsync([Type]$responseType, [string]$url, [object]$requestBody, [bool]$omitNullValues = $false) {
    try {
      $options = if ($omitNullValues) { $this.GetJsonOptionsNullOmit() } else { $this.GetJsonOptions() }
      $jsonContent = [JsonSerializer]::Serialize($requestBody, $options)
      $content = [StringContent]::new($jsonContent, [Encoding]::UTF8, "application/json")

      $request = [HttpRequestMessage]::new([HttpMethod]::Delete, [Uri]::new([Uri]::new($this._baseUrl), $url))
      $request.Content = $content
      $request.Headers.Add("Accept", "application/json")

      if (![string]::IsNullOrEmpty($this._accessToken)) {
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $this._accessToken)
      }

      $response = $this._httpClient.SendAsync($request).GetAwaiter().GetResult()

      if (!$response.IsSuccessStatusCode) {
        $errorMessage = $this.FormatErrorMessageAsync($response).GetAwaiter().GetResult()
        throw [HttpRequestException]::new($errorMessage)
      }

      $responseContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

      if ([string]::IsNullOrEmpty($responseContent)) {
        throw [HttpRequestException]::new("Response body is null or empty")
      }

      $result = [JsonSerializer]::Deserialize($responseContent, $responseType, $this.GetJsonOptions())

      if ($null -eq $result) {
        throw [InfisicalException]::new("Failed to deserialize response content")
      }

      return [Task]::FromResult([object]$result)
    } catch [InfisicalException] { throw }
    catch {
      throw [InfisicalException]::new("Error during DELETE request: $($_.Exception.Message)", $_.Exception)
    }
  }

  [void] Dispose() {
    if ($null -ne $this._httpClient) {
      $this._httpClient.Dispose()
    }
  }
}

class QueryBuilder {
  hidden [Dictionary[string, string]] $_params = [Dictionary[string, string]]::new()

  [QueryBuilder] Add([string]$key, [object]$value) {
    [ValidateNotNullOrWhiteSpace()][string]$key = $key
    if ($null -ne $value) {
      $this._params[$key] = $value.ToString()
    }
    return $this
  }

  [Dictionary[string, string]] Build() {
    return [Dictionary[string, string]]::new($this._params)
  }
}