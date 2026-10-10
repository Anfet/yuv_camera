Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$root = Get-CameraRepositoryRoot
Push-Location (Join-Path $root 'example')
try {
  Invoke-CameraCommand flutter 'pub', 'get'
  Invoke-CameraCommand flutter 'analyze'
  Invoke-CameraCommand flutter 'build', 'web'
} finally { Pop-Location }
