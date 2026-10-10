# AGENTS — yuv_camera

Package rules layered on `D:\.projects\AGENTS.md`, `D:\.projects\yuv\AGENTS.md`, `D:\.projects\ENGINEERING_PROTOCOL.md`, and `D:\.projects\.protocol\<role>.md`. Shared plan and statuses are in `D:\.projects\yuv\todo.md`. Shared memory: `D:\.projects\yuv\.memory\MEMORY.md`.

## Package boundaries

- This checkout and its remote/package are named `yuv_camera`; work in its existing `dev` branch without worktrees or pool branches.
- `yuv_camera` depends on `yuv_ffi`; `yuv_ffi` never depends on this package. Camera API, implementation boundaries, and transfer inventory are defined by `D:\.projects\yuv\doc\camera-extraction.md` and the active cards.
- Do not add a native plugin, platform channel, FFI layer, or duplicate YUV geometry, presenter, shader, or image operations. ML Kit and desktop camera providers belong in the example unless a card explicitly decides otherwise.
- Keep `pubspec_overrides.yaml` local and ignored. A path override may support local paired development, but published manifests must depend on `yuv_ffi` by version and contain no sibling path.
- Keep `yuv_camera` package metadata and CHANGELOG versions aligned. Public documentation and code comments are English; internal plan and reports are Russian.
- Device/browser support claims must name the verified platform and mode. A scaffold or dependency does not prove capture support. Physical iPhone work requires an Engineer task.

## Checks and workflow

- Probe, validation, and test requirements come from each active card and this package's scripts. Do not call `flutter drive` directly; use the checked-in `drive.ps1` / `drive.sh` wrapper and require exit 0 plus `All tests passed`.
- No CI (D-38): the package has no GitHub Actions workflows; do not add any. Every check runs directly on the own machines (`D:\.projects\MACHINES.md`). `tool/ci/` keeps its name as the scripts directory.
- Keys for changed paths: `bash tool/ci/scope_guard.sh <base>` (`path_keys()` is the source of truth). Commands, run from the package root:

  | Key | Command | Machine |
  | --- | --- | --- |
  | `vm` | `pwsh -File tool/ci/vm.ps1` | Windows |
  | `windows` | `pwsh -File tool/ci/windows.ps1` | Windows |
  | `android` | `pwsh -File tool/ci/android.ps1` | Windows, AVD `Tablet` (not together with the Linux VM) |
  | `web` | `pwsh -File tool/ci/web.ps1` (Mac: `bash tool/ci/web.sh`) | Windows, Chrome and ChromeDriver |
  | `example` | `pwsh -File tool/ci/example.ps1` | Windows |
  | `linux` | `bash tool/ci/linux.sh` | Ubuntu VM |
  | `macos` | `bash tool/ci/macos.sh` | Mac |
  | `ios` | `bash tool/ci/ios.sh` | Mac, Xcode and simulator |

  Until `yuv_ffi` is published, the exact pair is checked with `pwsh -File tool/check_pair.ps1 -CameraPath <camera> -CameraSha <full SHA> -YuvPath <yuv> -YuvSha <full SHA>` on clean checkouts.
- Card acceptance runs the card's scope keys and Probe. Before every release of every version run the full required set on the clean candidate regardless of the last card's scope: every key above, analyze of the root and example, the full example `flutter test`, the pair check, and the device checks of the release gate in the group `todo.md`. A previous PASS does not replace the run.
- Reports record `Validated at` (full SHA) of this package and the exact `yuv_ffi` dependency SHA (or the published version after `yuv_ffi` is released), the machine and SDK, the command, the exit code, and the script's PASS criterion. Evidence moves to another SHA only when the diff of the covered paths is empty.
- Preserve unrelated dirty files, check `git status` before edits, and commit only owned paths. The group Git repository owns task cards and shared docs; this child repository owns package implementation and these package rules.