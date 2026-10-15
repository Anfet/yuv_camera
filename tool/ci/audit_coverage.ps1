[CmdletBinding()]
param(
  [string] $ChromePath = $env:YUV_CAMERA_CHROME,
  [string] $ChromeDriverPath = $env:YUV_CAMERA_CHROMEDRIVER,
  [string] $ExpectedCameraSha = $env:YUV_CAMERA_EXPECTED_SHA,
  [string] $ExpectedFfiSha = $env:YUV_FFI_EXPECTED_SHA,
  [switch] $PreflightOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$root = Get-CameraRepositoryRoot
$cameraSha = (& git -C $root rev-parse HEAD).Trim()
$ffiRoot = (& git -C (Join-Path $root '..\yuv_ffi') rev-parse --show-toplevel).Trim()
$ffiSha = (& git -C $ffiRoot rev-parse HEAD).Trim()
if ($ExpectedCameraSha -and $cameraSha -ne $ExpectedCameraSha) { throw "Camera SHA mismatch: expected $ExpectedCameraSha, actual $cameraSha" }
if ($ExpectedFfiSha -and $ffiSha -ne $ExpectedFfiSha) { throw "yuv_ffi SHA mismatch: expected $ExpectedFfiSha, actual $ffiSha" }
if ($PreflightOnly) { Write-Output "PASS audit_coverage preflight; camera_sha=$cameraSha; yuv_ffi_sha=$ffiSha"; exit 0 }
$log = Join-Path ([IO.Path]::GetTempPath()) "yuv-camera-audit-coverage-$([guid]::NewGuid().ToString('N')).log"
Start-Transcript -LiteralPath $log -Force | Out-Null
try {
if (-not $ChromePath) { $ChromePath = (Get-Command chrome.exe -ErrorAction SilentlyContinue)?.Source }
if (-not $ChromeDriverPath) { $ChromeDriverPath = (Get-Command chromedriver.exe -ErrorAction SilentlyContinue)?.Source }
$chrome = $ChromePath
$driver = $ChromeDriverPath
foreach ($path in @($chrome, $driver)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Web executable is missing: $path" } }
$chromeVersion = (Get-Item -LiteralPath $chrome).VersionInfo.ProductVersion
$driverOutput = @(& $driver --version 2>&1)
$driverSucceeded = $?
$driverVersion = (($driverOutput | Select-Object -First 1) -replace '^ChromeDriver ', '')
if (-not $driverSucceeded -or $chromeVersion.Split('.')[0] -ne $driverVersion.Split('.')[0]) { throw "Chrome $chromeVersion and ChromeDriver $driverVersion must have matching major versions." }
$portProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 4444)
try { $portProbe.Start() } catch { throw 'ChromeDriver port 4444 is already occupied; the harness will not reuse a stale browser session.' } finally { $portProbe.Stop() }
$env:CHROME_EXECUTABLE = $chrome
$env:CHROMEDRIVER_EXE = $driver
$example = Join-Path $root 'example'
Push-Location $example
try { Invoke-CameraCommand flutter 'pub', 'get' } finally { Pop-Location }
$server = Start-Process -FilePath $driver -ArgumentList '--port=4444' -WindowStyle Hidden -PassThru
try {
  & (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/camera_source_web_fallback_test.dart' 'web-server' '--browser-name=chrome' '--headless' '--web-browser-flag=--use-fake-device-for-media-stream=device-count=2' '--web-browser-flag=--use-fake-ui-for-media-stream' '--no-pub'
  if ($LASTEXITCODE -ne 0) { throw "Web fallback target failed with exit code $LASTEXITCODE" }
  $evidencePath = Join-Path $example 'build/integration_response_data.json'
  if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "Fallback evidence missing: $evidencePath" }
  $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
  foreach ($branch in @('processorUnavailable', 'bgraRejected', 'visibleRectMismatch')) {
    if ([int]$evidence.$branch -lt 1) { throw "Fallback branch '$branch' has no execution evidence." }
  }
  if ([int]$evidence.frameCloseCount -lt 3 -or [int]$evidence.lateDeliveryCount -ne 0 -or [int]$evidence.uniqueClosedFrames -ne [int]$evidence.frameCloseCount -or [int]$evidence.exactlyOnceClosedFrames -ne [int]$evidence.frameCloseCount) { throw 'Fallback frame identity/cleanup/delivery evidence is invalid.' }
  Write-Output "PASS Web fallback harness: target=camera_source_web_fallback_test.dart; processor=$($evidence.processorUnavailable), bgra=$($evidence.bgraRejected), visibleRect=$($evidence.visibleRectMismatch), closed=$($evidence.frameCloseCount), unique=$($evidence.uniqueClosedFrames), late=$($evidence.lateDeliveryCount); Chrome=$chromeVersion; ChromeDriver=$driverVersion; camera_sha=$cameraSha; yuv_ffi_sha=$ffiSha; log=$log"
} finally { if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
} finally { Stop-Transcript | Out-Null }
