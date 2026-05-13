using namespace System.Management.Automation
function Invoke-InfisicalCli {
  #.DESCRIPTION
  #  One cmdlet to use the module's cli engine
  # .NOTES
  #  If you want more control you can directly use the [Infisical] class :)
  # .OUTPUTS
  #  [PSCustomObject]
  #.LINK
  #  https://github.com/chadnpc/infisical/blob/main/Public/Invoke-InfisicalCli.ps1
  [CmdletBinding()]
  [Alias('Infisical', 'InfisicalCli')]
  [OutputType({ [Infisical]::ReturnTypes })]
  param(
    [Parameter(Mandatory = $false, Position = 0)]
    [Alias('m')][AllowEmptyString()]
    [ArgumentCompleter({
        [OutputType([System.Management.Automation.CompletionResult])]
        param(
          [string] $CommandName,
          [string] $ParameterName,
          [string] $WordToComplete,
          [System.Management.Automation.Language.CommandAst] $CommandAst,
          [System.Collections.IDictionary] $FakeBoundParameters
        )
        $CompletionResults = [System.Collections.Generic.List[CompletionResult]]::new()
        $matchingMethods = [Infisical]::Methods.Where({ $_.Name -like "$WordToComplete*" -and $_.CustomAttributes.AttributeType.Name -notcontains "HiddenAttribute" })
        foreach ($method in $matchingMethods) {
          $paramst = ($method.GetParameters() | Select-Object @{l = '_'; e = { "[$($_.ParameterType.Name)]`$$($_.Name)" } })._ -join ', '
          $toolTip = "[{0}] {1}({2})" -f $method.ReturnType.Name, $method.Name, $paramst
          $CompletionResults.Add([System.Management.Automation.CompletionResult]::new($method.Name, $toolTip, 'Method', $toolTip))
        }
        return $CompletionResults
      })]
    [string]$Method,

    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('i')][ValidateNotNullOrEmpty()]
    $InputObject
  )
  begin {
    $buff = [System.Collections.Generic.List[byte]]::new()
    $meth = [string]::IsNullOrWhiteSpace($Method) ? "GetHelp" : $Method
    if ($meth -notin [Infisical]::Methods.Name) {
      throw "Method '$meth' not found in Infisical."
    }
  }
  process {
    if ($PSBoundParameters.ContainsKey('InputObject')) {
      if ($InputObject -is [byte]) { [void]$buff.Add($InputObject) }
      else {
        $r = [Infisical]::$meth($InputObject)
        if ($null -ne $r) { Write-Output -NoEnumerate -InputObject $r }
      }
    }
  }
  end {
    if ($buff.Count -gt 0) {
      $r = [Infisical]::$meth($buff.ToArray())
      if ($null -ne $r) { Write-Output -NoEnumerate -InputObject $r }
    } elseif (!$PSBoundParameters.ContainsKey('InputObject')) {
      $r = [Infisical]::$meth()
      if ($null -ne $r) { Write-Output $r }
    }
  }
}
