Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CameraRepositoryRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Add-CameraPath {
  param([Parameter(Mandatory)][string] $Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Directory does not exist: $Path"
  }
  $env:PATH = "$Path$([System.IO.Path]::PathSeparator)$env:PATH"
}

function Invoke-CameraCommand {
  param([Parameter(Mandatory)][string] $FilePath, [Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$FilePath failed with exit code $LASTEXITCODE" }
}

function Get-CameraResolvedPackagePath {
  param([Parameter(Mandatory)][string] $Directory, [Parameter(Mandatory)][string] $Package)
  $configFile = Join-Path $Directory '.dart_tool\package_config.json'
  $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
  $entry = @($config.packages | Where-Object { $_.name -eq $Package }) | Select-Object -First 1
  if (-not $entry) { throw "$configFile does not list package $Package." }
  $base = [System.Uri]::new((Join-Path $Directory '.dart_tool') + [System.IO.Path]::DirectorySeparatorChar)
  return [System.IO.Path]::GetFullPath([System.Uri]::new($base, [string]$entry.rootUri).LocalPath).TrimEnd('\', '/')
}

function Get-CameraCmake {
  $onPath = Get-Command cmake -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  $androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
  $candidate = @(Get-ChildItem -LiteralPath (Join-Path $androidSdk 'cmake') -Directory -ErrorAction SilentlyContinue |
      Sort-Object { [version]$_.Name } -Descending | ForEach-Object { Join-Path $_.FullName 'bin\cmake.exe' } | Where-Object { Test-Path -LiteralPath $_ }) |
    Select-Object -First 1
  if (-not $candidate) { throw 'cmake was not found on PATH or in the Android SDK cmake directory.' }
  return $candidate
}

# The example's native tests call YuvFfi.initialize(), which loads yuv_ffi.dll from PATH on Windows. The library is built
# from src/ of the yuv_ffi that the example resolves (a local override or the published package), so the tests always
# use the native code of that exact yuv_ffi.
function Add-CameraYuvFfiLibrary {
  param([Parameter(Mandatory)][string] $ExampleDirectory)
  $yuv = Get-CameraResolvedPackagePath $ExampleDirectory 'yuv_ffi'
  $cmake = Get-CameraCmake
  $key = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($yuv.ToLowerInvariant()))).Substring(0, 12)
  $build = Join-Path ([System.IO.Path]::GetTempPath()) "yuv-camera-vm-yuv-ffi-$key"
  Invoke-CameraCommand $cmake '-S' (Join-Path $yuv 'src') '-B' $build '-A' 'x64' '-DCMAKE_BUILD_TYPE=Release'
  Invoke-CameraCommand $cmake '--build' $build '--config' 'Release' '--parallel'
  $libraryDirectory = Join-Path $build 'Release'
  if (-not (Test-Path -LiteralPath (Join-Path $libraryDirectory 'yuv_ffi.dll') -PathType Leaf)) { throw "yuv_ffi.dll was not produced in $libraryDirectory" }
  Add-CameraPath $libraryDirectory
  Write-Output "yuv_ffi.dll built from $yuv in $libraryDirectory"
}
