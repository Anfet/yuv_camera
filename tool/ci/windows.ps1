Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$root = Get-CameraRepositoryRoot
Push-Location (Join-Path $root 'example')
try {
  Invoke-CameraCommand flutter 'pub', 'get'
  Invoke-CameraCommand flutter 'build', 'windows', '--release'
} finally { Pop-Location }
& (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/camera_capture_native_test.dart' 'windows' '--no-pub'
if ($LASTEXITCODE -ne 0) { throw "Windows capture target failed with exit code $LASTEXITCODE" }
Write-Output 'PASS Windows release build and native camera capture target.'
