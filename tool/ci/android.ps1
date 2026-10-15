[CmdletBinding()]
param(
  [ValidateSet('Debug', 'Release')][string] $BuildMode = 'Debug',
  [ValidateSet('all', 'camera_capture_native_test.dart', 'orchestrator_cycles_test.dart', 'shape_crop_test.dart')][string] $TargetName = 'all'
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

& $adb start-server
if ($LASTEXITCODE -ne 0) {
  throw 'adb start-server failed'
}

$deviceLines = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() })
$authorized = @($deviceLines | Where-Object { $_ -match '^(\S+)\tdevice$' } | ForEach-Object { ($_ -split "`t")[0] })
if ($env:ANDROID_SERIAL) {
  $serial = if ($authorized -contains $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL } else { $null }
} else {
  $serial = if ($authorized.Count -eq 1) { $authorized[0] } else { $null }
}
if (-not $serial) {
  throw "BLOCKED: connect exactly one authorized Android device (adb state 'device') or set ANDROID_SERIAL; adb devices: $($deviceLines -join ' | ')"
}

function Invoke-AdbShell([string] $Command) {
  $text = (& $adb -s $serial shell $Command 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
  if ($LASTEXITCODE -ne 0) {
    throw "adb shell '$Command' failed on ${serial}: $text"
  }
  $text
}

if ((Invoke-AdbShell 'dumpsys power') -notmatch 'mWakefulness=Awake' -or
    (Invoke-AdbShell 'dumpsys window') -notmatch '(?i)(mKeyguardShowing=false|isStatusBarKeyguard=false|mShowingLockscreen=false|isKeyguardShowing=false)') {
  throw "BLOCKED: turn on and unlock the screen of $serial"
}

$abilist = (Invoke-AdbShell 'getprop ro.product.cpu.abilist').Trim()
if ($abilist -notmatch 'arm64-v8a') {
  throw "BLOCKED: $serial does not support arm64-v8a ($abilist)"
}
$model = (Invoke-AdbShell 'getprop ro.product.model').Trim()
$androidRelease = (Invoke-AdbShell 'getprop ro.build.version.release').Trim()
Write-Output "Android device: $serial; model=$model; android=$androidRelease; abis=$abilist"

$packageName = 'dev.yuv.yuv_camera_example'
$targets = @(
  'integration_test/camera_capture_native_test.dart',
  'integration_test/orchestrator_cycles_test.dart',
  'integration_test/shape_crop_test.dart'
)
if ($TargetName -ne 'all') {
  $targets = @("integration_test/$TargetName")
}
$buildModeArgument = "--$($BuildMode.ToLowerInvariant())"
$apk = "build/app/outputs/flutter-apk/app-$($BuildMode.ToLowerInvariant()).apk"

$repositoryRoot = Get-CameraRepositoryRoot
Push-Location (Join-Path $repositoryRoot 'example')
try {
  Invoke-CameraCommand flutter 'pub', 'get'
} finally {
  Pop-Location
}

foreach ($target in $targets) {
  # One APK per target: its versionCode is the installed one plus one, so `adb install -r` always upgrades.
  Push-Location (Join-Path $repositoryRoot 'example')
  try {
    $packageInfo = (& $adb -s $serial shell dumpsys package $packageName 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to read installed package information (adb exit code $LASTEXITCODE)."
    }
    if ($packageInfo -match '(?im)^\s*Unable to find package:') {
      $installed = [long]0
    } else {
      $versionMatches = [regex]::Matches($packageInfo, '(?m)^\s*versionCode=(\d+)(?:\s|$)')
      if ($versionMatches.Count -ne 1) {
        throw "Unable to determine one installed versionCode; found $($versionMatches.Count) versionCode entries."
      }
      $installed = [long]$versionMatches[0].Groups[1].Value
    }
    $buildNumber = $installed + 1
    Write-Output "Android target: $target; mode=$BuildMode; installed versionCode=$installed; building versionCode=$buildNumber"
    Invoke-CameraCommand flutter 'build', 'apk', $buildModeArgument, "--target=$target", '--target-platform', 'android-arm64', "--build-number=$buildNumber"

    $installOutput = @(& $adb -s $serial install -r (Resolve-Path -LiteralPath $apk).Path 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0 -or -not ($installOutput | Where-Object { $_ -match 'Success' })) {
      throw "BLOCKED: adb install -r failed on $serial for ${packageName}: $($installOutput | Select-Object -Last 1). The script never removes apps or clears data; Engineer decides."
    }
  } finally {
    Pop-Location
  }

  try {
    & (Join-Path $PSScriptRoot 'drive.ps1') $target $serial '--no-pub' '--keep-app-running' "--use-application-binary=$apk"
  } finally {
    & $adb -s $serial shell am force-stop $packageName
  }
  Write-Output "PASS $target on $model ($serial), mode=$BuildMode, abi=arm64-v8a."
}
