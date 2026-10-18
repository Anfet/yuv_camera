# M2 — VideoFrame warning investigation

Investigation date: 2026-10-18. This evidence preserves a completed diagnostic task in Git; it does not establish that the warning was fixed.

**Ownership remains unknown:** the warning cannot be conclusively attributed to YUV, Flutter or its dependencies, or Chrome. No functional failure was observed in the physical camera scenarios. Observed camera-source frames were closed. This does not prove the absence of a defect in our packages or a resource leak.

## Environment and provenance

Windows with a physical Integrated Webcam, without fake video. Chrome 155.0.8059.84, ChromeDriver 155.0.8059.39; Flutter 3.44.9 / Dart 3.12.2, debug JS/CanvasKit. Resolved dependencies: camera 0.12.1, camera_web 0.3.5+6, web 1.1.1.

Local path overrides resolved the packages to clean dev checkouts:

- yuv_camera: `c0e9988dbaa3a4e82f31af04241b6795ad50464f`;
- yuv_ffi: `5bb3ce4b74ac0c3bb4e3291a9ec2cda0e5c4b0bf`.

Package sources were unchanged. The consumer, instrumentation, and builds were temporary. Source inspection covered the camera probe/read/process/stop/cancel paths, fallback/lifecycle tests, and the FFI decoder and presenter. The consumer automatically selected the first available camera; OBS Virtual Camera was enumerated but was not selected.

## Checks performed

| Run | Scenario | Result | VideoFrame warnings |
| --- | --- | --- | ---: |
| baseline | Physical start → capture720×480 → stop/dispose source and controller → reopen → stop/dispose | SCENARIO PASS | 1 |
| instrumented | Same scenario, tracking constructor/clone/read/close by identity | SCENARIO PASS; 2 probe and 3 reader frames closed exactly once | 1 |
| instrumented2 | Additional ImageDecoder.decode tracking | SCENARIO PASS; camera frames closed, one of 2 decoder frames closed | 1 |
| instrumented3 | Additional WeakRef/FinalizationRegistry tracking | SCENARIO PASS; camera frames closed before collection; the unclosed decoder frame remained alive, codedWidth=720, with the snapshot still displayed | 1 |
| control | Browser MediaStreamTrackProcessor without YUV/Flutter, 2×10 frames | 20/20 received frames closed, errors=[], tracks ended | 0 |
| control-paced | Processor/copyTo without YUV/Flutter, 2×30 frames with 50 ms simulated processing | 60/60 received frames closed, errors=[], tracks ended | 0 |
| flutter-control | No camera or YUV calls, 4 raw image decode/dispose operations | CONTROL PASS, 4/4 decoder frames closed | 0 |
| gap10 | Full physical consumer with an additional 10 s between dispose and reopen | SCENARIO PASS, actual gap 10013 ms | 1 |

All eight runners exited with code 0 and no runner exception. Functional outcomes were checked using markers/results, rather than exit codes alone. SCENARIO PASS checks errors, late/unhandled callbacks, and ended tracks. Browser warnings were recorded separately. Observation continued for another 30 s after the main console collection; no forced GC or warning suppression was used. Total runtime was 541.96 s; the investigation stayed within its assigned 4 h limit.

Instrumentation was injected through CDP before page load and did not retain strong references to frames. It changes promise microtiming; the baseline ran separately without instrumentation. Negative controls do not reproduce the complete original pipeline and do not rule out a race.

Gap10 timings, first opening / reopening:

| Operation | First | Reopening |
| --- | ---: | ---: |
| controller.initialize Future | 874 ms | 695 ms |
| source.start Future | 128 ms | 49 ms |
| Full start to first frame | 3136 ms | 1933 ms |
| Full source/controller release | 21 ms | 1 ms |

The normal 1 s quiet period preceded the additional 10 s gap: approximately 11.02 s elapsed between API release completion and reopening. These timings describe API completion and frame delivery, not the physical camera indicator. Delayed warning output does not measure dispose duration. Other platforms and compiler modes were not checked in this investigation.

## Search for a known cause

Search performed on 2026-10-18: the exact warning text, MediaStreamTrackProcessor/cancel, and Flutter/CanvasKit/ImageDecoder. **No issue conclusively explaining our case, or confirmed ready-to-apply fix, was found.** This describes a limited search, not proof that no such issue exists.

- [Chromium WebCodecsLogger](https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/modules/webcodecs/webcodecs_logger.cc): warnings are published by a timer with a 10 s interval. Console timing therefore does not identify when close was missed. Upstream main was inspected; byte-for-byte equivalence with the installed Chrome155 was not verified.
- [Chromium VideoFrameHandle](https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/modules/webcodecs/video_frame_handle.cc): the destructor notifies the auditor if the handle was not invalidated. Tracking JS wrappers does not guarantee coverage of all internal handles; this is an observation limit, not a proven browser bug.
- [GetStream #2384](https://github.com/GetStream/stream-video-js/issues/2384): the author attributes a similar teardown warning to queued TransformStream output frames and abort during an async transform. That pipeline differs from ours, so its proposed fix was neither applied nor treated as a YUV diagnosis.
- [Rerun #7327](https://github.com/rerun-io/rerun/issues/7327): a similar warning despite reported closure of all delivered frames. The report provides neither an established cause for our case nor a confirmed Chromium fix.

## Preserved evidence

[results.json](results.json) contains selected original console messages, timestamps, frame counters, and outcomes from all eight runs. Selected message text is unchanged. This is an **excerpt**, not the complete browser logs: device enumeration identifiers, session/profile parameters, network/debug messages, and unrelated stacks were omitted. The SHA-256 of each complete local raw JSON permits provenance checks. [source-hashes.json](source-hashes.json) identifies the contents of three inspected modules.

Complete raw results, argv, package resolution, and reports remain local under the group path `tasks/release-audit-followup/evidence/M2/`; scratch consumers/runners are under `Z:/.ai/claude-work/yuv/m2/`. They are not included in this Git bundle. The bundle preserves inspectable investigation results but is not a standalone executable reproducer. Replaying the scenario requires the consumer/runner or their reconstruction against the recorded package pair.

## Disposition

The Engineer closed the diagnostic task while retaining the known observation: no functional failure manifested, but ownership and cause remain unknown. No claim is made that YUV is defect-free, that Chrome is at fault, that the warning is harmless, or that a leak was fixed. Permanent decision record: [known observations](../../known-observations.md#m2--chrome-videoframe-without-explicit-close).
