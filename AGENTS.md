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

- Probe, validation, CI, and test requirements come from each active card and this package's scripts. Do not call `flutter drive` directly; use the checked-in `drive.ps1` / `drive.sh` wrapper and require exit 0 plus `All tests passed`.
- CI has no automatic push trigger. Use only the group's accepted explicit CI process when authorized; external candidate checks and publication are release-stage work.
- Preserve unrelated dirty files, check `git status` before edits, and commit only owned paths. The group Git repository owns task cards and shared docs; this child repository owns package implementation and these package rules.