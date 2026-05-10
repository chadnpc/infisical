#!/usr/bin/env pwsh
using namespace System
using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Reflection
using namespace System.Text.Json.Serialization

using module ./Model.psm1

class ObjectToDictionaryConverter {
  static [Dictionary[string, string]] ToDictionary([object]$Obj, [bool]$IncludeNullValues) {
    $result = [Dictionary[string, string]]::new()
    if ($null -eq $Obj) { return $result }

    $type = $Obj.GetType()
    $properties = $type.GetProperties([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance)

    foreach ($property in $properties) {
      $value = $property.GetValue($Obj)

      if (!$IncludeNullValues -and $null -eq $value) { continue }

      $keyName = [ObjectToDictionaryConverter]::GetPropertyKeyName($property)
      $stringValue = [ObjectToDictionaryConverter]::ConvertValueToString($value)

      $result[$keyName] = $stringValue
    }
    return $result
  }

  static [string] GetPropertyKeyName([PropertyInfo]$Property) {
    $jsonPropertyNameAttr = $Property.GetCustomAttribute([JsonPropertyNameAttribute])
    if ($null -ne $jsonPropertyNameAttr) {
      return $jsonPropertyNameAttr.Name
    }
    return $Property.Name
  }

  static [string] ConvertValueToString([object]$Value) {
    if ($null -eq $Value) { return [string]::Empty }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }

    if ($Value -is [IEnumerable]) {
      $items = [System.Collections.Generic.List[string]]::new()
      foreach ($item in $Value) {
        if ($null -ne $item) { $items.Add($item.ToString()) }
      }
      return [string]::Join(",", $items)
    }
    return $Value.ToString()
  }
}

class SecretsUtil {
  static [void] EnsureUniqueSecretsByKey([Collections.Generic.IList[InfisicalSecret]]$Secrets) {
    $secretMap = [Dictionary[string, InfisicalSecret]]::new()
    foreach ($secret in $Secrets) {
      $secretMap[$secret.SecretKey] = $secret
    }

    $Secrets.Clear()
    foreach ($secret in $secretMap.Values) {
      $Secrets.Add($secret)
    }
  }
}