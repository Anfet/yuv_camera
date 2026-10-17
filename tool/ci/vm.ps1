param(
  [AllowEmptyCollection()]
  [string[]] $TestPath,
  [string] $Name,
  [string] $Group,
  [switch] $List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$root = Get-CameraRepositoryRoot
$example = Join-Path $root 'example'
$groups = @{
  source = 'test/camera/yuv_camera_frame_source_test.dart'
  view = 'test/camera/yuv_camera_view_test.dart'
  navigation = 'test/main_test.dart'
}
$hasPaths = $PSBoundParameters.ContainsKey('TestPath')
$hasGroup = $PSBoundParameters.ContainsKey('Group')
$targeted = $hasPaths -or $hasGroup -or $PSBoundParameters.ContainsKey('Name')
if ($hasPaths -and $hasGroup) { throw 'Group and TestPath are mutually exclusive.' }
if ($hasGroup -and -not $groups.ContainsKey($Group)) { throw "Unknown group: $Group" }
if ($hasPaths -and ($null -eq $TestPath -or $TestPath.Count -eq 0)) { throw 'TestPath must not be empty.' }
$selectedPaths = @(if ($hasGroup) { $groups[$Group] } elseif ($hasPaths) { $TestPath })
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $example 'test'))
foreach ($path in $selectedPaths) {
  if ([string]::IsNullOrWhiteSpace($path)) { throw 'TestPath must not contain an empty path.' }
  if ([System.IO.Path]::IsPathRooted($path)) { throw "TestPath must be relative to example/: $path" }
  if (($path -split '[/\\]') -contains '..') { throw "Parent traversal is not allowed: $path" }
  $fullPath = [System.IO.Path]::GetFullPath($path, $example)
  if (-not $fullPath.StartsWith($testRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
      -not $fullPath.EndsWith('_test.dart', [System.StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Expected an existing *_test.dart inside example/test/: $path"
  }
  $entry = Get-Item -LiteralPath $fullPath -Force
  while ($null -ne $entry -and $entry.FullName -ne $root) {
    if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Reparse traversal is not allowed: $path"
    }
    $entry = if ($entry -is [System.IO.DirectoryInfo]) { $entry.Parent } else { $entry.Directory }
  }
}
$testArguments = @($selectedPaths)
if ($PSBoundParameters.ContainsKey('Name')) { $testArguments += @('--name', $Name) }
$selection = if ($targeted) { $testArguments -join ' ' } else { 'all example/test/' }
Write-Output "VM selection: $selection; preparation: example pub get; resolved yuv_ffi native Release; Flutter test Debug"
if ($List) { return }

Push-Location $example
try {
  Invoke-CameraCommand flutter 'pub', 'get'
  Add-CameraYuvFfiLibrary (Get-Location).Path
  if (-not $targeted) {
    Invoke-CameraCommand flutter 'test'
  } else {
    # Count only completed, visible, non-skipped test bodies, never loading or setUpAll events.
    $output = @(& flutter test --no-pub --reporter json @testArguments 2>&1)
    $testExitCode = $LASTEXITCODE
    $passed = 0
    $failed = 0
    $completed = $false
    foreach ($line in $output) {
      if ($line.ToString() -notmatch '^\s*\{') { continue }
      try {
        $event = $line.ToString() | ConvertFrom-Json -AsHashtable
      } catch {
        Write-Warning "Invalid Flutter JSON event: $_"
        $failed++
        continue
      }
      if ($event.type -eq 'testDone' -and $event.hidden -eq $false -and $event.skipped -eq $false) {
        if ($event.result -eq 'success') { $passed++ } else { $failed++ }
      }
      if ($event.type -eq 'done') { $completed = $event.success -eq $true }
    }
    if ($testExitCode -ne 0 -or -not $completed -or $failed -gt 0 -or $passed -eq 0) {
      $output | Select-Object -Last 40 | Write-Output
      throw "VM selection failed: exit=$testExitCode; completed=$completed; passed=$passed; failed=$failed (requires real executed tests)."
    }
    Write-Output "PASS VM selection: $passed passed, $failed failed ($selection)"
  }
} finally { Pop-Location }
