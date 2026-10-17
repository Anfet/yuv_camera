[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Baseline', 'Final')][string] $Mode,
  [Parameter(Mandatory)][string] $EvidenceDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ci\_common.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not [System.IO.Path]::IsPathFullyQualified($EvidenceDirectory)) { throw 'EvidenceDirectory must be absolute.' }
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'EvidenceDirectory already exists; frozen evidence is never overwritten.' }
$null = New-Item -ItemType Directory -Path $EvidenceDirectory
$example = Join-Path $root 'example'
$target = 'integration_test/camera_preview_performance_test.dart'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$driver = 'D:\.projects\.tools\chromedriver-win64\chromedriver.exe'
$server = $null
$override = Join-Path $example 'pubspec_overrides.yaml'
$previousOverride = if (Test-Path -LiteralPath $override) { [System.IO.File]::ReadAllBytes($override) } else { $null }
$response = Join-Path $example 'build/integration_response_data.json'
$scratch = Join-Path 'Z:\.ai\claude-work\yuv' ('preview-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
$log = Join-Path $EvidenceDirectory 'session.log'
$started = [DateTimeOffset]::UtcNow
$verdict = 'FAIL'
$metadata = [ordered]@{ mode = $Mode; started_utc = $started.ToString('o'); machine = $env:COMPUTERNAME; build_mode = 'release' }
try {
  foreach ($path in @($chrome, $driver)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing executable: $path" } }
  $chromeVersion = (Get-Item -LiteralPath $chrome).VersionInfo.ProductVersion
  $driverVersion = (& $driver --version) -replace '^ChromeDriver ', ''
  if ($LASTEXITCODE -ne 0 -or $chromeVersion.Split('.')[0] -ne $driverVersion.Split('.')[0]) { throw "Chrome/Driver major mismatch: $chromeVersion / $driverVersion" }
  $metadata.chrome = $chromeVersion
  $metadata.chromedriver = $driverVersion
  $metadata.flutter = (& flutter --version --machine | Out-String | ConvertFrom-Json)
  if ($LASTEXITCODE -ne 0) { throw 'Unable to identify Flutter SDK.' }
  $metadata.camera_sha = (& git -C $root rev-parse HEAD).Trim()
  $yuv = (Resolve-Path (Join-Path $root '..\yuv_ffi')).Path
  $metadata.yuv_ffi_sha = (& git -C $yuv rev-parse HEAD).Trim()
  # Archive the exact dependency commit; concurrent sibling working changes are excluded.
  Invoke-CameraCommand git '-C' $yuv 'archive' '--format=zip' "--output=$scratch\ffi.zip" $metadata.yuv_ffi_sha
  $dependency = Join-Path $scratch 'yuv_ffi'
  Expand-Archive -LiteralPath (Join-Path $scratch 'ffi.zip') -DestinationPath $dependency
  $dependencyYaml = $dependency.Replace('\', '/')
  [System.IO.File]::WriteAllText($override, "dependency_overrides:`n  yuv_ffi:`n    path: $dependencyYaml`n")
  Push-Location $example
  try { Invoke-CameraCommand flutter 'pub' 'get' } finally { Pop-Location }
  if ((Get-CameraResolvedPackagePath $example 'yuv_ffi') -ne $dependency) { throw 'Example did not resolve the exact archived FFI dependency.' }
  $workload = Join-Path $root "example/$target"
  $runner = $PSCommandPath
  Copy-Item -LiteralPath $workload -Destination (Join-Path $EvidenceDirectory 'camera_preview_performance_test.dart')
  Copy-Item -LiteralPath $runner -Destination (Join-Path $EvidenceDirectory 'web_preview.ps1')
  $metadata.workload_sha256 = (Get-FileHash -LiteralPath $workload -Algorithm SHA256).Hash
  $metadata.runner_sha256 = (Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash
  $metadata.command = "pwsh -File tool/perf/web_preview.ps1 -Mode $Mode -EvidenceDirectory $EvidenceDirectory"
  # Keep the headless benchmark on software rendering: this machine has a recorded
  # Intel-driver/fake-media capture-service failure. Final must use the same flags.
  $metadata.drive_arguments = @($target, 'web-server', '--browser-name=chrome', '--headless', '--release', '--web-browser-flag=--use-fake-device-for-media-stream', '--web-browser-flag=--use-fake-ui-for-media-stream', '--web-browser-flag=--disable-gpu', '--web-browser-flag=--enable-logging', "--web-browser-flag=--log-file=$EvidenceDirectory/chrome.log", '--no-pub')
  if (Test-Path -LiteralPath $response) { Remove-Item -LiteralPath $response }
  if (Get-NetTCPConnection -LocalPort 4444 -State Listen -ErrorAction SilentlyContinue) { throw 'ChromeDriver port 4444 is occupied; stop its owner before benchmarking.' }
  $env:CHROME_EXECUTABLE = $chrome
  $env:CHROMEDRIVER_EXE = $driver
  $server = Start-Process -FilePath $driver -ArgumentList '--port=4444' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory 'driver.stdout.log') -RedirectStandardError (Join-Path $EvidenceDirectory 'driver.stderr.log')
  $driveArguments = $metadata.drive_arguments
  & (Join-Path $root 'tool/ci/drive.ps1') @driveArguments *>&1 | Tee-Object -FilePath $log
  if ($LASTEXITCODE -ne 0) { throw "Drive wrapper failed: $LASTEXITCODE" }
  if (-not (Select-String -LiteralPath $log -SimpleMatch "PASS $target on web-server" -Quiet)) { throw 'Missing owning drive wrapper PASS verdict.' }
  if (-not (Test-Path -LiteralPath $response) -or (Get-Item -LiteralPath $response).LastWriteTimeUtc -lt $started.UtcDateTime) { throw 'No fresh response measurements.' }
  $data = Get-Content -LiteralPath $response -Raw | ConvertFrom-Json
  $measurement = $data.previewPerformance
  if ($measurement.mode -ne 'release' -or @($measurement.rows).Count -ne 6) { throw 'Incomplete Release measurement series.' }
  foreach ($scenario in @('visible', 'offstage')) {
    $rows = @($measurement.rows | Where-Object scenario -eq $scenario)
    if ($rows.Count -ne 3) { throw "Incomplete $scenario series." }
    foreach ($row in $rows) {
      if ($row.source_frames -le 0 -or $row.window_ms -lt 20000) { throw 'Incomplete source window.' }
      if ($scenario -eq 'offstage' -and $row.recovery_drawn_frames_5s -le 0) { throw 'Missing rendered recovery.' }
    }
  }
  if (@($measurement.rows | ForEach-Object { "$($_.width_px)x$($_.height_px)" } | Select-Object -Unique).Count -ne 1) { throw 'Measurement resolutions differ.' }
  Copy-Item -LiteralPath $response -Destination (Join-Path $EvidenceDirectory 'measurements.json')
  if ($Mode -eq 'Final') {
    $baselineDirectory = Join-Path (Split-Path -Parent $EvidenceDirectory) 'baseline'
    $baseline = Get-Content -LiteralPath (Join-Path $baselineDirectory 'metadata.json') -Raw | ConvertFrom-Json
    if ($metadata.workload_sha256 -ne $baseline.workload_sha256 -or $metadata.runner_sha256 -ne $baseline.runner_sha256) { throw 'Final workload/runner differs from frozen baseline.' }
    $baselineData = Get-Content -LiteralPath (Join-Path $baselineDirectory 'measurements.json') -Raw | ConvertFrom-Json
    if ($measurement.rows[0].width_px -ne $baselineData.previewPerformance.rows[0].width_px -or $measurement.rows[0].height_px -ne $baselineData.previewPerformance.rows[0].height_px) { throw 'Final resolution differs from baseline.' }
  }
  $verdict = 'PASS'
} catch {
  $metadata.failure = $_.ToString()
  throw
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  if ($null -eq $previousOverride) { Remove-Item -LiteralPath $override -ErrorAction SilentlyContinue } else { [System.IO.File]::WriteAllBytes($override, $previousOverride) }
  Push-Location $example
  try { Invoke-CameraCommand flutter 'pub' 'get' } finally { Pop-Location }
  $metadata.verdict = $verdict
  $metadata.finished_utc = [DateTimeOffset]::UtcNow.ToString('o')
  $metadata | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'metadata.json')
  if ($verdict -eq 'PASS') {
    Get-ChildItem -LiteralPath $EvidenceDirectory -File | ForEach-Object { $_.IsReadOnly = $true }
    Write-Output "PASS $Mode preview performance evidence frozen at $EvidenceDirectory"
  }
}
