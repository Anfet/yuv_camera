[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$root = Get-CameraRepositoryRoot
$log = Join-Path ([IO.Path]::GetTempPath()) "yuv-camera-audit-coverage-$([guid]::NewGuid().ToString('N')).log"
Start-Transcript -LiteralPath $log -Force | Out-Null
try {
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$driver = 'D:\.projects\.tools\chromedriver-win64\chromedriver.exe'
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
  if ([int]$evidence.frameCloseCount -lt 3 -or [int]$evidence.lateDeliveryCount -ne 0) { throw 'Fallback frame cleanup/delivery evidence is invalid.' }
  Write-Output "PASS Web fallback harness: processor=$($evidence.processorUnavailable), bgra=$($evidence.bgraRejected), visibleRect=$($evidence.visibleRectMismatch), closed=$($evidence.frameCloseCount), late=$($evidence.lateDeliveryCount); log=$log"
} finally { if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
} finally { Stop-Transcript | Out-Null }
