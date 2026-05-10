#!/usr/bin/env pwsh
using namespace System

class InfisicalException : Exception {
  InfisicalException([string]$Message) : base($Message) {}
  InfisicalException([string]$Message, [Exception]$InnerException) : base($Message, $InnerException) {}
}