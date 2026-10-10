[CmdletBinding()]
param(
  [string] $Device = 'emulator-5554'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
  throw "Android adb is missing: $adb"
}
Add-CameraPath (Split-Path -Parent $adb)

$devices = @(& $adb devices)
$adbExitCode = $LASTEXITCODE
$deviceReady = @($devices | Where-Object { $_ -match "^$([regex]::Escape($Device))\s+device(?:\s|$)" }).Count -gt 0
if ($adbExitCode -ne 0 -or -not $deviceReady) {
  throw "Start the Tablet AVD and connect it as $Device before running the camera capture target."
}

$avdOutput = @(& $adb -s $Device emu avd name)
$avdExitCode = $LASTEXITCODE
if ($avdExitCode -ne 0 -or [string]($avdOutput | Select-Object -First 1) -ne 'Tablet') {
  throw "$Device must be the configured Tablet AVD."
}

$repositoryRoot = Get-CameraRepositoryRoot
Push-Location (Join-Path $repositoryRoot 'example')
try {
  Invoke-CameraCommand flutter 'pub', 'get'
} finally {
  Pop-Location
}

& (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/camera_capture_native_test.dart' $Device '--no-pub'
if ($LASTEXITCODE -ne 0) {
  throw "Android camera capture target failed with exit code $LASTEXITCODE"
}
Write-Output "PASS integration_test/camera_capture_native_test.dart on Tablet ($Device)."
