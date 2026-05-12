$MODULE_DATA = PsModuleBase\Read-ModuleData -File ./en-US/infisical.strings.psd1
$currentbuildPath = Resolve-Path "$PSScriptRoot/../BuildOutput/$ModuleName" -ea Ignore | Get-Item -ea Ignore
$script:ModuleName = $MODULE_DATA.ModuleName
$script:ModulePath = [IO.Directory]::Exists("$currentbuildPath") ? $currentbuildPath : (Get-Item $PSScriptRoot).Parent
$script:moduleVersion = $MODULE_DATA.ModuleVersion ? $MODULE_DATA.ModuleVersion : (((Get-ChildItem $ModulePath).Where({ $_.Name -as 'version' -is 'version' }).Name -as 'version[]' | Sort-Object -Descending)[0].ToString())
$script:currentbuildPath = [IO.Directory]::Exists("$currentbuildPath") ? "$ModulePath/$moduleVersion" : $ModulePath

Write-Host "[+] Testing the latest built module:" -ForegroundColor Green
Write-Host "      ModuleName    $ModuleName"
Write-Host "      ModulePath    $ModulePath"
Write-Host "      Version       $moduleVersion`n"

Get-Module -Name $ModuleName | Remove-Module | Out-Null # Make sure no versions of the module are loaded

Write-Host "[+] Reading module information ..." -ForegroundColor Green
$script:ModuleInformation = Import-Module -Name "$ModulePath" -PassThru
$script:ModuleInformation | Format-List

Write-Host "[+] Verify all Eported functions and classes ..." -ForegroundColor Green
$script:ExportedFunctions = $ModuleInformation.ExportedFunctions.Values.Name
Write-Host "      ExportedFunctions: " -ForegroundColor DarkGray -NoNewline
Write-Host $($ExportedFunctions -join ', ')
$script:PS1Functions = Get-ChildItem -Path "$currentbuildPath/Public/*.ps1" -Recurse
Write-Host ""
Write-Host "      ExportedClasses: " -ForegroundColor DarkGray
$missing = @(); $TypeAccelerators = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Get.Keys
$classes = [IO.File]::ReadAllLines([IO.Path]::Combine($ModulePath, "infisical.psm1")).Where({ $_.StartsWith("class") -or $_.StartsWith("enum ") }).ForEach({ $_.Replace("class ", '').Replace("enum ", '') }).ForEach({ ($_ -like "* : *") ? $_.split(" : ")[0] + '' : $_.Replace(' {', '') })

foreach ($cls in $classes) {
  try {
    if ($TypeAccelerators.Contains("$cls")) {
      Write-Host "      ✓ $cls" -ForegroundColor Green
    } else {
      $missing += $cls
      Write-Host "      ✗ $cls - NOT EXPORTED" -ForegroundColor Red
    }
  } catch {
    $missing += $cls
    Write-Host "      ✗ $cls - ERROR: $_" -ForegroundColor Red
  }
}

if ($missing.Count -gt 0) {
  Write-Host ""
  Write-Host "  WARNING: $($missing.Count) classes not exported" -ForegroundColor Yellow
  Write-Host "  Missing: $($missing -join ', ')" -ForegroundColor Yellow
}

Describe "Module tests for $($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')))" {
  Context " Confirm valid Manifest file" {
    It "Should contain RootModule" {
      ![string]::IsNullOrWhiteSpace($ModuleInformation.RootModule) | Should Be $true
    }

    It "Should contain ModuleVersion" {
      ![string]::IsNullOrWhiteSpace($ModuleInformation.Version) | Should Be $true
    }

    It "Should contain GUID" {
      ![string]::IsNullOrWhiteSpace($ModuleInformation.Guid) | Should Be $true
    }

    It "Should contain Author" {
      ![string]::IsNullOrWhiteSpace($ModuleInformation.Author) | Should Be $true
    }

    It "Should contain Description" {
      ![string]::IsNullOrWhiteSpace($ModuleInformation.Description) | Should Be $true
    }
  }
  Context " Should export all public functions " {
    It "Compare the number of Function Exported and the PS1 files found in the public folder" {
      $status = $ExportedFunctions.Count -eq $PS1Functions.Count
      $status | Should Be $true
    }

    It "The number of missing functions should be 0 " {
      if ($ExportedFunctions.count -ne $PS1Functions.count) {
        $Compare = Compare-Object -ReferenceObject $ExportedFunctions -DifferenceObject $PS1Functions.Basename
        $($Compare.InputObject -join '').Trim() | Should -BeNullOrEmpty
      }
    }
  }
  Context " Confirm files are valid Powershell syntax " {
    $_scripts = $(Get-Item -Path "$currentbuildPath").GetFiles(
      "*", [System.IO.SearchOption]::AllDirectories
    ).Where({ $_.Extension -in ('.ps1', '.psd1', '.psm1') })
    $testCase = $_scripts | ForEach-Object { @{ file = $_ } }
    function Test-ScriptSyntax {
      [CmdletBinding(DefaultParameterSetName = 'ByPath')]
      param (
        # Use this parameter to pass a file path directly
        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath', Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })][Alias('FullName', 'Path')]
        [string]$FilePath,

        # Use this parameter to pass raw script text
        [Parameter(Mandatory = $true, ParameterSetName = 'ByContent')]
        [string]$FileContent
      )

      process {
        $tokens = $null
        $errors = $null

        if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
          Write-Host "        Checking $FilePath ..." -ForegroundColor DarkGray
          # The modern AST Parser can parse a file directly
          $null = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$errors)
        } else {
          # Or it can parse a string of script content
          $null = [System.Management.Automation.Language.Parser]::ParseInput($FileContent, [ref]$tokens, [ref]$errors)
        }

        if ($errors.Count -gt 0) {
          # Format the errors nicely so you know exactly where the issue is
          foreach ($err in $errors) {
            [PSCustomObject]@{
              File    = if ($FilePath) { $FilePath } else { "Raw Content" }
              Line    = $err.Extent.StartLineNumber
              Column  = $err.Extent.StartColumnNumber
              Message = $err.Message
              Code    = $err.Extent.Text
            }
          }
        } else {
          Write-Host "        No syntax errors found in $([IO.Path]::GetFileName($FilePath))"
        }
        return $errors
      }
    }
    It "Each .Ps1/.Psd1/.Psm1 file should have valid Powershell sysntax" -TestCases $testCase {
      param($file)
      $syntaxErrors = Test-ScriptSyntax -FilePath $file.FullName
      $syntaxErrors.Count | Should Be 0
    }
  }
  Context "Confirm there are no duplicate function names in private and public folders" {
    It 'Module should have no duplicate functions' {
      $Publc_Dir = Get-Item -Path ([IO.Path]::Combine("$currentbuildPath", 'Public'))
      $Privt_Dir = Get-Item -Path ([IO.Path]::Combine("$currentbuildPath", 'Private'))
      $funcNames = @(); Test-Path -Path ([string[]]($Publc_Dir, $Privt_Dir)) -PathType Container -ErrorAction Stop
      $Publc_Dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories) + $Privt_Dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories) | Where-Object { $_.Extension -eq '.ps1' } | ForEach-Object { $funcNames += $_.BaseName }
      $($funcNames | Group-Object | Where-Object { $_.Count -gt 1 }).Count | Should Be 0
    }
  }
}
