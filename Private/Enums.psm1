#!/usr/bin/env pwsh
using namespace System.Text.Json.Serialization

enum SecretType {
  Shared
  Personal
}

enum InfisicalAuthMethod {
  Universal
  Token
}