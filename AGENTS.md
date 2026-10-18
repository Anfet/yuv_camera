# AGENTS — yuv_camera

Package rules layered on `D:\.projects\AGENTS.md`, `D:\.projects\yuv\AGENTS.md`, `D:\.projects\.tools\skills\engineering-protocol\SKILL.md` and its selected role reference. Shared plan and statuses are in `D:\.projects\yuv\todo.md`. Shared memory: `D:\.projects\yuv\.memory\MEMORY.md`.

## Package boundaries

- This checkout and its remote/package are named `yuv_camera`; work in its existing `dev` branch without worktrees or pool branches.
- `yuv_camera` depends on `yuv_ffi`; `yuv_ffi` never depends on this package. Camera API, implementation boundaries, and transfer inventory are defined by `D:\.projects\yuv\doc\camera-extraction.md` and the active cards.
- Do not add a native plugin, platform channel, FFI layer, or duplicate YUV geometry, presenter, shader, or image operations. ML Kit and desktop camera providers belong in the example unless a card explicitly decides otherwise.
- Keep `pubspec_overrides.yaml` local and ignored. A path override may support local paired development, but published manifests must depend on `yuv_ffi` by version and contain no sibling path.
- Keep `yuv_camera` package metadata and CHANGELOG versions aligned. Public documentation and code comments are English; internal plan and reports are Russian.
- Device/browser support claims must name the verified platform and mode. A scaffold or dependency does not prove capture support. Physical iPhone work requires an Engineer task.

## Checks and workflow

- Probe, validation, and test requirements come from each active card and this package's scripts. Do not call `flutter drive` directly; use the checked-in `drive.ps1` / `drive.sh` wrapper and require exit 0 plus `All tests passed`.
- No CI (D-38): the package has no GitHub Actions workflows; do not add any. Every check runs directly on the own machines (`D:\.projects\.tools\private-skills\machine-use\SKILL.md`). `tool/ci/` keeps its name as the scripts directory.
- Keys for changed paths: `bash tool/ci/scope_guard.sh <base>` (`path_keys()` is the source of truth). Commands, run from the package root:

  | Key | Command | Machine |
  | --- | --- | --- |
  | `vm` | `pwsh -File tool/ci/vm.ps1` | Windows |
  | `windows` | `pwsh -File tool/ci/windows.ps1` | Windows |
  | `android` | `pwsh -File tool/ci/android.ps1` | Windows, physical Pixel 3 over USB (`ANDROID_SERIAL=8B1X11QLW`), screen on and unlocked; emulators are not used |
  | `web` | `pwsh -File tool/ci/web.ps1` (Mac: `bash tool/ci/web.sh`) | Windows, Chrome and ChromeDriver |
  | `example` | `pwsh -File tool/ci/example.ps1` | Windows |
  | `linux` | `bash tool/ci/linux.sh` | Ubuntu VM |
  | `macos` | `bash tool/ci/macos.sh` | Mac |
  | `ios` | `bash tool/ci/ios.sh` | Mac, Xcode and simulator |

  Until `yuv_ffi` is published, the exact pair is checked with `pwsh -File tool/check_pair.ps1 -CameraPath <camera> -CameraSha <full SHA> -YuvPath <yuv> -YuvSha <full SHA>` on clean checkouts.
- [Shared validation policy](../doc/release-validation-policy.md) governs card and release checks. scope_guard keys, including `all`, are conservative impact inventories; the card selects checks for changed behavior and a concrete platform risk. General lease/hub logic uses controlled Future/stream VM regressions; add one matching runtime when real platform resource ownership changes. New support configurations need their own initial scenario.
- Both packages support targeted VM selection: `tool/ci/vm.ps1` accepts `-TestPath`, `-Name`, `-Group`, `-List`. Camera paths are relative to `example/`; groups are `source`, `view`, `navigation`. `-TestPath` and `-Group` are mutually exclusive; `-Name` filters the selected set; `-List` prints without execution. The camera VM wrapper does not run analyze; analyze the changed module separately. Single drive targets and group `-OnlyRow` selection are documented in the shared policy.
- Before release, account for required checks with RUN / CARRIED / NOT_REQUIRED / PENDING and reasons. Run affected checks; carry sufficient unchanged behavior/config/dependency evidence. A version, new SHA or review alone never requires a full runtime rerun or another Pixel run. Reviewer reads sufficient Executor results. Changed publish payload needs inventory/dry-run; publication requires separate Engineer authorization.
- Reports record full `Validated at` of this package and the exact resolved `yuv_ffi` dependency SHA (or published version), machine/SDK, command, exit code and PASS criterion. Carry evidence according to covered behavior/config/dependencies in the shared policy. Windows PASS does not prove Apple/WASM; static linkage requires the affected Apple consumer/mode.
- The agent runs commands, selects cameras, drives capture/stop/restart and collects logs. Ask the Engineer only for an actually required system precondition or visual/physical assessment. Record a missing automation scenario as a concrete gap; M2 starts with real Chrome and the existing diagnostic example, without a preassigned universal runner.
- Preserve unrelated dirty files, check `git status` before edits, and commit only owned paths. The group Git repository owns task cards and shared docs; this child repository owns package implementation and these package rules.