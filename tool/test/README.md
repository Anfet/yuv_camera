# Camera test selections

Run commands from the package root on Windows with the configured Flutter SDK.
Paths passed to `TestPath` are relative to `example/` and must name existing
`test/**/*_test.dart` files. `Group` and `TestPath` are mutually exclusive;
`Name` is Flutter's test name regular expression and can narrow either selection.

```powershell
pwsh -File tool/ci/vm.ps1 -Group source
pwsh -File tool/ci/vm.ps1 -Group view -List
pwsh -File tool/ci/vm.ps1 -Group navigation
pwsh -File tool/ci/vm.ps1 -TestPath test/camera/yuv_camera_frame_source_test.dart -Name 'stops'
pwsh -File tool/ci/vm.ps1
```

| Group | Existing VM/widget target | Related integration coverage |
| --- | --- | --- |
| `source` | `test/camera/yuv_camera_frame_source_test.dart` | `camera_capture_native_test.dart`, `camera_source_web_lifecycle_test.dart`, `camera_source_web_fallback_test.dart` |
| `view` | `test/camera/yuv_camera_view_test.dart` | `shape_crop_test.dart`, `camera_capture_native_test.dart` |
| `navigation` | `test/main_test.dart` | `camera_flow_test.dart`, `orchestrator_cycles_test.dart` |

Groups are useful slices, not the entire example suite. Other files can be selected
with `TestPath`; the command without arguments retains the complete example VM run.
It runs example pub get, the existing native helper and Flutter test. Every execution
prepares the native library once from the example's resolved `yuv_ffi` dependency;
there is no additional cross-process cache or sibling repository assumption.
The native library is Release; Flutter tests retain their default Debug mode.
`List` only validates and describes the selection, without Flutter, build inspection
or setup. Invalid groups, conflicts and missing paths fail before setup. Targeted
runs require successful JSON completion and at least one visible non-skipped test
body; an unmatched `Name` cannot pass.

Integration targets live under `example/integration_test/`. Run them through the
existing drive wrapper, which checks both exit status and `All tests passed`:

```powershell
pwsh -File tool/ci/drive.ps1 integration_test/orchestrator_cycles_test.dart windows --no-pub
pwsh -File tool/ci/drive.ps1 integration_test/camera_source_web_lifecycle_test.dart web-server --no-pub
```

Use the platform scripts for their required preparation, browser flags and devices.
`orchestrator_cycles_test.dart` checks lifecycle correctness separately from any
performance workload; its current frame-count oracle is handled by TEST 1.
It is not an FPS benchmark. `desktop_camera_preview_smoke_test.dart` uses a real
desktop camera and a test-owned preview. It checks capture without unmounting the
preview, presented-frame progress before and after capture on the same open
controller, captured content/geometry and an empty ImageCache. Removing the
preview must close the camera; cleanup always awaits camera disposal. Optional
`SMOKE_OUT` writes `view01b_captured.png` and a short result log into an existing
directory. Run this target when the active task card requires it; it adds no
general mandatory gate.

In PowerShell, pass the define through the wrapper's explicit array parameter so
its Windows drive colon is preserved. Create the output directory before running:

```powershell
& ./tool/ci/drive.ps1 -Target integration_test/desktop_camera_preview_smoke_test.dart -Device windows -FlutterDriveArguments @('--debug', '--dart-define=SMOKE_OUT=Z:/.ai/claude-work/yuv/plat2/smoke')
```

The iOS targets `ios_yuv420_camera_frame_test.dart` and
`ios_bgra_camera_frame_test.dart` belong only to final CHECK 22 with its simulator
and physical-device prerequisites. The shell regression runner belongs to TEST 2
and runs independently of this VM script, pub, native builds and devices.

The complete VM, root/example analysis and Windows/Chrome/Pixel checks are owned
by CHECK 20; remote platform checks by CHECK 22. These targeted commands do not
replace those checks. Existing test assertions are unchanged.
