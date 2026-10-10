Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CameraRepositoryRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Add-CameraPath {
  param([Parameter(Mandatory)][string] $Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Directory does not exist: $Path"
  }
  $env:PATH = "$Path$([System.IO.Path]::PathSeparator)$env:PATH"
}

function Invoke-CameraCommand {
  param([Parameter(Mandatory)][string] $FilePath, [Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$FilePath failed with exit code $LASTEXITCODE" }
}
