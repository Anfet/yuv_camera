[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)][string] $Target,
  [Parameter(Mandatory, Position = 1)][string] $Device,
  [Parameter(ValueFromRemainingArguments)][string[]] $FlutterDriveArguments
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$safeTarget = [System.IO.Path]::GetFileNameWithoutExtension($Target) -replace '[^A-Za-z0-9._-]', '_'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$outputFile = Join-Path ([System.IO.Path]::GetTempPath()) "yuv-camera-drive-$safeTarget-$Device-$timestamp.log"
$applicationBinaryArgument = @($FlutterDriveArguments | Where-Object { $_ -like '--use-application-binary=*' })
if ($applicationBinaryArgument.Count -gt 1) {
  throw 'Only one --use-application-binary argument is supported.'
}

if ($applicationBinaryArgument.Count -eq 1 -and [System.IO.Path]::GetFileName(($applicationBinaryArgument[0] -split '=', 2)[1]) -ieq 'app-release.apk') {
  if ($FlutterDriveArguments -notcontains '--keep-app-running') {
    throw 'Release APK execution requires --keep-app-running so the caller can collect the device result before cleanup.'
  }
  if ($Target -notmatch '^integration_test[/\\][^/\\]+\.dart$') {
    throw "Release APK execution requires an integration_test target; got $Target."
  }

  $androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
  $adb = Join-Path $androidSdk 'platform-tools\adb.exe'
  if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw "Android adb is missing: $adb"
  }
  $exampleDirectory = Join-Path $repositoryRoot 'example'
  $binaryPath = [System.IO.Path]::GetFullPath(($applicationBinaryArgument[0] -split '=', 2)[1], $exampleDirectory)
  if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
    throw "Release application binary is missing: $binaryPath"
  }
  $buildTools = Get-ChildItem -LiteralPath (Join-Path $androidSdk 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending
  $aapt = $buildTools | ForEach-Object { Join-Path $_.FullName 'aapt.exe' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if (-not $aapt) {
    throw 'Android build-tools aapt.exe is missing; cannot verify the installed release binary.'
  }
  $badging = @(& $aapt dump badging $binaryPath 2>&1 | ForEach-Object { $_.ToString() })
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read release APK metadata: $binaryPath"
  }
  $packageLine = $badging | Where-Object { $_ -match '^package:' } | Select-Object -First 1
  if ($packageLine -notmatch "name='([^']+)'\s+versionCode='(\d+)'") {
    throw "Unable to read package/versionCode from release APK metadata: $packageLine"
  }
  $packageName = $Matches[1]
  $apkVersionCode = [long]$Matches[2]
  $deviceState = (& $adb -s $Device get-state 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $deviceState.Trim() -ne 'device') {
    throw "Android device $Device is not authorized and connected: $deviceState"
  }
  $installedInfo = (& $adb -s $Device shell dumpsys package $packageName 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $installedInfo -notmatch '(?m)^\s*versionCode=(\d+)') {
    throw "Cannot verify installed package $packageName on $Device."
  }
  $installedVersionCode = [long]$Matches[1]
  if ($installedVersionCode -ne $apkVersionCode) {
    throw "Installed $packageName versionCode $installedVersionCode does not match release APK versionCode $apkVersionCode."
  }

  $logcatErrorFile = "$outputFile.stderr.log"
  $logcatProcess = $null
  $watcher = $null
  try {
    Write-Output "RUN release integration target $Target on $Device; package=$packageName; versionCode=$apkVersionCode"
    Write-Output "FULL DEVICE LOG $outputFile"
    Write-Output "DEVICE LOGCAT ERROR LOG $logcatErrorFile"
    $logcatProcess = Start-Process -FilePath $adb -ArgumentList @('-s', $Device, 'logcat', '-v', 'time', '-T', '1') `
      -RedirectStandardOutput $outputFile -RedirectStandardError $logcatErrorFile -PassThru -WindowStyle Hidden
    $null = & $adb -s $Device shell am force-stop $packageName 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to force-stop $packageName before the release test."
    }
    $launchOutput = @(& $adb -s $Device shell am start -W -n "$packageName/.MainActivity" 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0 -or ($launchOutput -join "`n") -notmatch 'Status:\s*ok') {
      throw "Release app failed to start on ${Device}: $($launchOutput -join ' ')"
    }
    $pidOutput = (& $adb -s $Device shell pidof $packageName 2>&1 | ForEach-Object { $_.ToString() }) -join ' '
    if ($LASTEXITCODE -ne 0 -or $pidOutput -notmatch '\d+') {
      throw "Release app process did not start on ${Device}: $pidOutput"
    }
    $applicationPid = $Matches[0]
    $watcher = [System.IO.FileSystemWatcher]::new([System.IO.Path]::GetDirectoryName($outputFile), [System.IO.Path]::GetFileName($outputFile))
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
    $watcher.EnableRaisingEvents = $true
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(20)
    $passed = $false
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
      if ($logcatProcess.HasExited) {
        throw "Device logcat stopped before target completion (exit $($logcatProcess.ExitCode))."
      }
      $deviceLog = if (Test-Path -LiteralPath $outputFile) { Get-Content -LiteralPath $outputFile -Raw } else { '' }
      $appLines = @($deviceLog -split "`r?`n" | Where-Object { $_ -match "I/flutter\s+\(\s*$applicationPid\s*\):" })
      if (($appLines -join "`n") -match 'Some tests failed\.?|Failure Details:') {
        Get-Content -LiteralPath $outputFile -Tail 120 | Write-Output
        throw "Release integration target failed on $Device; full device log: $outputFile"
      }
      if (($appLines -join "`n") -match 'All tests passed!?') {
        $passed = $true
        break
      }
      $remaining = [int][Math]::Max(1, [Math]::Min(1000, ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds))
      $null = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed, $remaining)
    }
    if (-not $passed) {
      Get-Content -LiteralPath $outputFile -Tail 120 | Write-Output
      throw "Timed out waiting for the app's integration_test result on $Device; full device log: $outputFile"
    }
    Write-Output 'All tests passed'
    Write-Output "PASS $Target on $Device from installed Release APK versionCode=$apkVersionCode (process $applicationPid remains running)."
  } finally {
    if ($watcher) { $watcher.Dispose() }
    if ($logcatProcess -and -not $logcatProcess.HasExited) { Stop-Process -Id $logcatProcess.Id -Force }
  }
  return
}

try {
  Push-Location (Join-Path $repositoryRoot 'example')
  Write-Output "RUN $Target on $Device"
  Write-Output "FULL LOG $outputFile"
  & flutter drive --driver=test_driver/integration_test.dart "--target=$Target" -d $Device @FlutterDriveArguments 2>&1 |
    Tee-Object -FilePath $outputFile |
    Where-Object { $_ -match '^(Running |Building |Xcode build done|Installing and launching|VMServiceFlutterDriver: Connected|flutter: [0-9]+:[0-9]+ )' }
  $driveExitCode = $LASTEXITCODE
  if ($driveExitCode -ne 0) {
    Get-Content -LiteralPath $outputFile -Tail 120 | Write-Output
    throw "flutter drive failed for $Target on $Device with exit code $driveExitCode"
  }
  if (-not (Select-String -LiteralPath $outputFile -SimpleMatch 'All tests passed' -Quiet)) {
    Get-Content -LiteralPath $outputFile -Tail 120 | Write-Output
    throw "flutter drive completed for $Target on $Device without All tests passed"
  }
  Write-Output "PASS $Target on $Device"
} finally {
  if ((Get-Location).Path -eq (Join-Path $repositoryRoot 'example')) { Pop-Location }
}
