[CmdletBinding()]
param([ValidateSet('0.11.0+2', '0.12.1')][string] $CameraVersion = '0.11.0+2')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$root = Get-CameraRepositoryRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter is required on PATH.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required on PATH.' }
$cameraSha = (& git -C $root rev-parse HEAD).Trim()
$ffiPath = (Resolve-Path -LiteralPath (Join-Path $root '..\yuv_ffi')).Path
$ffiPath = (& git -C $ffiPath rev-parse --show-toplevel).Trim()
$ffiSha = (& git -C $ffiPath rev-parse HEAD).Trim()
if ($ffiSha -ne 'b2f03afa2869b103af8cc46f2f050e0805b9c866') { throw "Unexpected exact yuv_ffi SHA: $ffiSha" }
$work = Join-Path ([IO.Path]::GetTempPath()) "yuv-camera-audit-dependency-$CameraVersion-$([guid]::NewGuid().ToString('N'))"
$log = Join-Path ([IO.Path]::GetTempPath()) "yuv-camera-audit-dependency-$CameraVersion-$([guid]::NewGuid().ToString('N')).log"
New-Item -ItemType Directory -Path $work | Out-Null
$copyDirectories = @('lib', 'tool/ci', 'example/lib', 'example/test')
$copyFiles = @('pubspec.yaml', 'analysis_options.yaml', 'example/pubspec.yaml', 'example/analysis_options.yaml')
foreach ($relative in $copyDirectories) {
  $source = Join-Path $root $relative
  if (Test-Path -LiteralPath $source -PathType Container) {
    $destination = Join-Path $work $relative
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $destination -Recurse -Force
  }
}
foreach ($relative in $copyFiles) {
  $source = Join-Path $root $relative
  if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $work $relative) -Force }
}
$example = Join-Path $work 'example'
$rootOverride = "dependency_overrides:`n  yuv_ffi:`n    path: '$($ffiPath.Replace('\','/'))'`n"
Set-Content -LiteralPath (Join-Path $work 'pubspec_overrides.yaml') -Value $rootOverride
$pubspec = Join-Path $example 'pubspec.yaml'
$yaml = Get-Content -LiteralPath $pubspec -Raw
$yaml = [regex]::Replace($yaml, '(?m)^  camera: .*?$', "  camera: '$CameraVersion'")
Set-Content -LiteralPath $pubspec -Value $yaml -NoNewline
$override = "dependency_overrides:`n  yuv_ffi:`n    path: '$($ffiPath.Replace('\','/'))'`n"
Set-Content -LiteralPath (Join-Path $example 'pubspec_overrides.yaml') -Value $override
Push-Location $work
try {
  "camera=$CameraVersion camera_sha=$cameraSha yuv_ffi_sha=$ffiSha" | Set-Content -LiteralPath $log
  & flutter pub get *>> $log
  if ($LASTEXITCODE -ne 0) { throw "Root dependency resolution failed ($LASTEXITCODE). See $log" }
  & flutter analyze --no-fatal-infos lib *>> $log
  if ($LASTEXITCODE -ne 0) { throw "Root package analyze failed ($LASTEXITCODE). See $log" }
  Push-Location $example
  try {
    & flutter pub get *>> $log
    if ($LASTEXITCODE -ne 0) { throw "Example dependency resolution failed ($LASTEXITCODE). See $log" }
    & flutter analyze --no-fatal-infos lib test *>> $log
    if ($LASTEXITCODE -ne 0) { throw "Example analyze failed ($LASTEXITCODE). See $log" }
  } finally { Pop-Location }
  & pwsh -NoProfile -File (Join-Path $work 'tool/ci/vm.ps1') *>> $log
  $vmExitCode = $LASTEXITCODE
  $lock = Get-Content -LiteralPath (Join-Path $example 'pubspec.lock') -Raw
  $cameraLock = [regex]::Match($lock, '(?ms)^  camera:\r?\n(.*?)(?=^  [A-Za-z0-9_]+:\r?$)')
  if (-not $cameraLock.Success -or $cameraLock.Groups[1].Value -notmatch "(?m)^    version: `"$([regex]::Escape($CameraVersion))`"") { throw "Resolved lockfile does not prove camera $CameraVersion. See $log" }
  $pluginVersions = foreach ($plugin in @('camera_android_camerax', 'camera_avfoundation', 'camera_platform_interface', 'camera_web')) {
    $entry = [regex]::Match($lock, "(?ms)^  $plugin`:\r?\n(.*?)(?=^  [A-Za-z0-9_]+:\r?$)")
    if (-not $entry.Success -or $entry.Groups[1].Value -notmatch '(?m)^    version: "?([^"\r\n]+)') { throw "Lockfile has no resolved version for $plugin. See $log" }
    "$plugin=$($Matches[1])"
  }
  $status = if ($vmExitCode -eq 0) { 'PASS' } else { 'FAIL' }
  $summary = "$status audit_dependency camera=$CameraVersion; analyze=PASS (--no-fatal-infos); VM exit=$vmExitCode; resolved=$($pluginVersions -join ', '); camera_sha=$cameraSha; yuv_ffi_sha=$ffiSha; work=$work; log=$log"
  Add-Content -LiteralPath $log -Value $summary
  Get-Content -LiteralPath $log -Tail 16
  Write-Output $summary
  if ($vmExitCode -ne 0) { throw "Exact camera dependency VM suite failed ($vmExitCode). See $log" }
} finally { Pop-Location }
