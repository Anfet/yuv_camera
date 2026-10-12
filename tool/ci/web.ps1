Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$root = Get-CameraRepositoryRoot
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$driver = 'D:\.projects\.tools\chromedriver-win64\chromedriver.exe'
foreach ($path in @($chrome, $driver)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Web executable is missing: $path" } }
$chromeVersion = (Get-Item -LiteralPath $chrome).VersionInfo.ProductVersion
$driverOutput = & $driver --version
$driverExitCode = $LASTEXITCODE
$driverVersion = (($driverOutput | Select-Object -First 1) -replace '^ChromeDriver ', '')
if ($driverExitCode -ne 0 -or $chromeVersion.Split('.')[0] -ne $driverVersion.Split('.')[0]) { throw "Chrome $chromeVersion and ChromeDriver $driverVersion must have matching major versions." }
$env:CHROME_EXECUTABLE = $chrome
$env:CHROMEDRIVER_EXE = $driver
Push-Location (Join-Path $root 'example')
try { Invoke-CameraCommand flutter 'pub', 'get' } finally { Pop-Location }
$server = Start-Process -FilePath $driver -ArgumentList '--port=4444' -WindowStyle Hidden -PassThru
try {
  & (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/camera_source_web_smoke_test.dart' 'web-server' '--browser-name=chrome' '--headless' '--web-browser-flag=--use-fake-device-for-media-stream' '--web-browser-flag=--use-fake-ui-for-media-stream' '--no-pub'
  if ($LASTEXITCODE -ne 0) { throw "Web source smoke failed with exit code $LASTEXITCODE" }
  Write-Output 'PASS Chrome JavaScript camera source smoke.'
  & (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/shape_crop_test.dart' 'web-server' '--browser-name=chrome' '--headless' '--web-browser-flag=--use-fake-device-for-media-stream' '--web-browser-flag=--use-fake-ui-for-media-stream' '--no-pub'
  if ($LASTEXITCODE -ne 0) { throw "Web shape crop target failed with exit code $LASTEXITCODE" }
  Write-Output 'PASS Chrome shape crop target.'
  & (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/orchestrator_cycles_test.dart' 'web-server' '--browser-name=chrome' '--headless' '--web-browser-flag=--use-fake-device-for-media-stream' '--web-browser-flag=--use-fake-ui-for-media-stream' '--no-pub'
  if ($LASTEXITCODE -ne 0) { throw "Web orchestrator cycles target failed with exit code $LASTEXITCODE" }
  Write-Output 'PASS Chrome orchestrator cycles target.'
} finally { if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
