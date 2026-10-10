<#
.SYNOPSIS
Checks that an exact yuv_camera / yuv_ffi checkout pair works together on this machine.

.DESCRIPTION
Before any `pub get` or test the script compares `git rev-parse HEAD` of both checkouts with the expected full SHAs
and requires clean tracked files. It then creates its own ignored `pubspec_overrides.yaml` files in the camera root
and example that point `yuv_ffi` at the YUV checkout, runs the pair checks, and removes only the overrides it created,
also when a check fails. An existing override is never overwritten: the script stops before any check and says why.
It does not switch branches and does not change either checkout other than the ignored overrides and tool outputs.

Checks: `flutter analyze` in the camera root and in `example`, `flutter test` in `example`, `tool/ci/windows.ps1` and
`tool/ci/web.ps1` of the camera checkout. The unpublished pair resolves `yuv_ffi` only through these overrides; the
published pair (no overrides) is checked in release stage 3.

.EXAMPLE
pwsh -File tool/check_pair.ps1 -CameraPath D:\.projects\yuv\yuv_camera -CameraSha <40-hex> -YuvPath D:\.projects\yuv\yuv_ffi -YuvSha <40-hex>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $CameraPath,
  [Parameter(Mandatory)][string] $CameraSha,
  [Parameter(Mandatory)][string] $YuvPath,
  [Parameter(Mandatory)][string] $YuvSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$createdOverrides = [System.Collections.Generic.List[string]]::new()
$failed = $false

function Get-FullPath {
  param([Parameter(Mandatory)][string] $Path)
  return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Invoke-Git {
  param([Parameter(Mandatory)][string] $Repository, [Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
  & git -C $Repository @Arguments
  if ($LASTEXITCODE -ne 0) { throw "git -C $Repository $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

function Get-PackageField {
  param([Parameter(Mandatory)][string] $Repository, [Parameter(Mandatory)][string] $Field)
  $line = Get-Content -LiteralPath (Join-Path $Repository 'pubspec.yaml') | Where-Object { $_ -match "^${Field}:\s*(.+?)\s*$" } | Select-Object -First 1
  if (-not $line) { throw "pubspec.yaml in $Repository has no top-level '$Field'." }
  return ($line -replace "^${Field}:\s*", '').Trim()
}

function Assert-ExactCheckout {
  param([Parameter(Mandatory)][string] $Label, [Parameter(Mandatory)][string] $Repository, [Parameter(Mandatory)][string] $ExpectedSha, [Parameter(Mandatory)][string] $ExpectedPackage)
  if ($ExpectedSha -cnotmatch '^[0-9a-f]{40}$') { throw "$Label expected SHA must be a full lowercase 40-character SHA: $ExpectedSha" }
  if (-not (Test-Path -LiteralPath (Join-Path $Repository 'pubspec.yaml') -PathType Leaf)) { throw "$Label checkout has no pubspec.yaml: $Repository" }
  $name = Get-PackageField $Repository 'name'
  if ($name -ne $ExpectedPackage) { throw "$Label checkout $Repository is package '$name', expected '$ExpectedPackage'." }
  $head = [string](Invoke-Git $Repository 'rev-parse' 'HEAD')
  if ($head -ne $ExpectedSha) { throw "$Label checkout $Repository is at $head, expected $ExpectedSha." }
  $dirty = @(Invoke-Git $Repository 'status' '--porcelain' '--untracked-files=no')
  if ($dirty.Count -gt 0) { throw "$Label checkout $Repository has modified tracked files:`n$($dirty -join "`n")" }
  Write-Output "$Label ${name} $(Get-PackageField $Repository 'version') at $head (tracked files clean): $Repository"
}

function Get-ResolvedPackagePath {
  param([Parameter(Mandatory)][string] $Directory, [Parameter(Mandatory)][string] $Package)
  $configFile = Join-Path $Directory '.dart_tool\package_config.json'
  $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
  $entry = @($config.packages | Where-Object { $_.name -eq $Package }) | Select-Object -First 1
  if (-not $entry) { throw "$configFile does not list package $Package." }
  $base = [System.Uri]::new((Join-Path $Directory '.dart_tool') + [System.IO.Path]::DirectorySeparatorChar)
  return Get-FullPath ([System.Uri]::new($base, [string]$entry.rootUri).LocalPath)
}

function Assert-ResolvedPath {
  param([Parameter(Mandatory)][string] $Directory, [Parameter(Mandatory)][string] $Package, [Parameter(Mandatory)][string] $Expected)
  $actual = Get-ResolvedPackagePath $Directory $Package
  Write-Output "Dependency path: $Package -> $actual (from $Directory)"
  if ($actual -ine (Get-FullPath $Expected)) { throw "$Package in $Directory resolves to $actual, expected $Expected." }
}

function Invoke-Step {
  param([Parameter(Mandatory)][string] $Title, [Parameter(Mandatory)][string] $Directory, [Parameter(Mandatory)][string] $FilePath, [Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
  Write-Output "== $Title ($Directory): $FilePath $($Arguments -join ' ')"
  Push-Location $Directory
  try {
    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
  } finally { Pop-Location }
  if ($exitCode -ne 0) { throw "$Title failed with exit code $exitCode" }
  Write-Output "PASS $Title"
}

try {
  foreach ($path in @($CameraPath, $YuvPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Checkout directory does not exist: $path" }
  }
  $camera = Get-FullPath (Resolve-Path -LiteralPath $CameraPath).Path
  $yuv = Get-FullPath (Resolve-Path -LiteralPath $YuvPath).Path
  if ($camera -ieq $yuv) { throw 'CameraPath and YuvPath must be different checkouts.' }

  # 1. Exact pair, before anything is written or resolved.
  Assert-ExactCheckout 'Camera' $camera $CameraSha 'yuv_camera'
  Assert-ExactCheckout 'YUV' $yuv $YuvSha 'yuv_ffi'

  # 2. Published manifests must not carry local overrides or sibling path dependencies.
  $trackedOverrides = @(Invoke-Git $camera 'ls-files' '--' 'pubspec_overrides.yaml' 'example/pubspec_overrides.yaml')
  if ($trackedOverrides.Count -gt 0) { throw "Tracked overrides in camera checkout: $($trackedOverrides -join ', ')" }
  if (Select-String -LiteralPath (Join-Path $camera 'pubspec.yaml') -Pattern '^\s+path:' -Quiet) { throw 'Camera pubspec.yaml contains a path dependency.' }

  # 3. Existing overrides are never overwritten: stop before any check.
  $overrideFiles = @((Join-Path $camera 'pubspec_overrides.yaml'), (Join-Path $camera 'example\pubspec_overrides.yaml'))
  $existing = @($overrideFiles | Where-Object { Test-Path -LiteralPath $_ })
  if ($existing.Count -gt 0) {
    throw "Override conflict: these files already exist and were left untouched: $($existing -join ', '). Move or remove them yourself, then rerun; this script only creates and removes its own overrides."
  }

  Write-Output "Flutter: $((& flutter --version 2>&1 | Select-Object -First 1))"
  Write-Output "Dart: $((& dart --version 2>&1 | Select-Object -First 1))"

  # 4. Own overrides, removed in finally.
  $yamlPath = $yuv.Replace('\', '/').Replace("'", "''")
  foreach ($file in $overrideFiles) {
    Set-Content -LiteralPath $file -Value "dependency_overrides:`n  yuv_ffi:`n    path: '$yamlPath'" -Encoding utf8NoBOM
    $createdOverrides.Add($file)
    Write-Output "Created override: $file -> $yuv"
  }

  # 5. Checks.
  Invoke-Step 'pub get (root)' $camera 'flutter' 'pub' 'get'
  Invoke-Step 'pub get (example)' (Join-Path $camera 'example') 'flutter' 'pub' 'get'
  Assert-ResolvedPath $camera 'yuv_ffi' $yuv
  Assert-ResolvedPath (Join-Path $camera 'example') 'yuv_ffi' $yuv
  Assert-ResolvedPath (Join-Path $camera 'example') 'yuv_camera' $camera
  Invoke-Step 'analyze (root)' $camera 'flutter' 'analyze'
  Invoke-Step 'analyze (example)' (Join-Path $camera 'example') 'flutter' 'analyze'
  Invoke-Step 'test (example)' (Join-Path $camera 'example') 'flutter' 'test'
  Invoke-Step 'native capture (windows.ps1)' $camera 'pwsh' '-NoProfile' '-File' 'tool/ci/windows.ps1'
  Invoke-Step 'Web source smoke (web.ps1)' $camera 'pwsh' '-NoProfile' '-File' 'tool/ci/web.ps1'

  # 6. The pair is only proven if the checkouts are still exactly what was named.
  Assert-ExactCheckout 'Camera (after checks)' $camera $CameraSha 'yuv_camera'
  Assert-ExactCheckout 'YUV (after checks)' $yuv $YuvSha 'yuv_ffi'
  Write-Output "PASS yuv_camera $CameraSha with yuv_ffi $YuvSha (local checkout overrides, yuv_ffi -> $yuv)."
} catch {
  Write-Error "check_pair failed: $($_.Exception.Message)" -ErrorAction Continue
  $failed = $true
} finally {
  foreach ($file in $createdOverrides) {
    Remove-Item -LiteralPath $file -Force -ErrorAction Continue
    Write-Output "Removed override: $file"
  }
}
if ($failed) { exit 1 }
exit 0
