[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)][string] $Target,
  [Parameter(Mandatory, Position = 1)][string] $Device,
  [Parameter(ValueFromRemainingArguments)][string[]] $FlutterDriveArguments
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outputFile = Join-Path ([System.IO.Path]::GetTempPath()) "yuv-camera-drive-$([guid]::NewGuid()).log"
try {
  Push-Location (Join-Path $repositoryRoot 'example')
  Write-Output "RUN $Target on $Device"
  & flutter drive --driver=test_driver/integration_test.dart "--target=$Target" -d $Device @FlutterDriveArguments 2>&1 | Tee-Object -FilePath $outputFile | Where-Object { $_ -match '^(Running |Building |Xcode build done|Installing and launching|VMServiceFlutterDriver: Connected|flutter: [0-9]+:[0-9]+ )' }
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
  Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
}
