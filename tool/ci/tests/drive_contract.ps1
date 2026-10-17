$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('drive-contract-' + [guid]::NewGuid())
$originalPath = $env:PATH
$originalTemp = $env:TEMP
$originalTmp = $env:TMP
$originalContractWork = $env:CONTRACT_WORK
$originalLocation = Get-Location
$count = 0
$failures = 0
try {
  $null = New-Item -ItemType Directory -Path $work, "$work/bin", "$work/tmp"
  @'
@echo off
pwsh -NoProfile -File "%CONTRACT_WORK%\mock.ps1" %*
exit /b %errorlevel%
'@ | Set-Content "$work/bin/flutter.cmd"
  @'
@((Get-Location).Path) + $args | Set-Content "$env:CONTRACT_WORK/argv"
Get-Content "$env:CONTRACT_WORK/stdout" | Write-Output
Get-Content "$env:CONTRACT_WORK/stderr" | ForEach-Object { [Console]::Error.WriteLine($_) }
exit ([int](Get-Content "$env:CONTRACT_WORK/exit"))
'@ | Set-Content "$work/mock.ps1"
  $env:PATH = "$work/bin;$originalPath"
  $env:TEMP = "$work/tmp"
  $env:TMP = "$work/tmp"
  $env:CONTRACT_WORK = $work
  $cases = @(
    @('success', 0, $true, 'All tests passed; Error is harmless', ''),
    @('exit7', 7, $false, 'All tests passed', ''),
    @('missing', 0, $false, 'Finished', ''),
    @('some-after', 0, $false, "All tests passed`nSome tests failed", ''),
    @('some-before', 0, $false, "Some tests failed`nAll tests passed", ''),
    @('details-after', 0, $false, "All tests passed`nFailure Details:", ''),
    @('details-before', 0, $false, "Failure Details:`nAll tests passed", ''),
    @('stderr', 0, $false, 'All tests passed', 'Some tests failed'),
    @('recovery', 0, $true, 'All tests passed', '')
  )
  foreach ($case in $cases) {
    $case[1] | Set-Content "$work/exit"
    $case[3] | Set-Content "$work/stdout"
    $case[4] | Set-Content "$work/stderr"
    $output = @(& pwsh -NoProfile -File "$repositoryRoot/tool/ci/drive.ps1" 'integration_test/mock target.dart' contract-device '--dart-define=VALUE=two words' 2>&1)
    $actualExit = $LASTEXITCODE
    $verdict = @($output | Where-Object { $_.ToString() -eq 'PASS integration_test/mock target.dart on contract-device' }).Count -gt 0
    $count++
    if (($case[2] -and ($actualExit -ne 0 -or -not $verdict)) -or (-not $case[2] -and ($actualExit -eq 0 -or $verdict))) {
      Write-Host "FAIL $($case[0]): expected pass=$($case[2]); actual exit=$actualExit wrapper PASS=$verdict"
      $failures++
    }
    $expected = @((Join-Path $repositoryRoot 'example'), 'drive', '--driver=test_driver/integration_test.dart', '--target=integration_test/mock target.dart', '-d', 'contract-device', '--dart-define=VALUE=two words')
    if (@(Compare-Object $expected @(Get-Content "$work/argv") -SyncWindow 0).Count -gt 0 -or @(Get-ChildItem "$work/tmp").Count -gt 0 -or (Get-Location).Path -ne $originalLocation.Path) {
      Write-Host "FAIL $($case[0]): argv/cwd mismatch or temporary log leaked"
      $failures++
    }
  }
  if ($failures) { throw "drive_contract PowerShell: $failures failures / $count cases" }
  Write-Output "drive_contract PowerShell: $count cases PASS"
} finally {
  $env:PATH = $originalPath
  $env:TEMP = $originalTemp
  $env:TMP = $originalTmp
  $env:CONTRACT_WORK = $originalContractWork
  Set-Location $originalLocation
  Remove-Item -LiteralPath $work -Recurse -Force
}
