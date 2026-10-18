# Accepted observations

This register records Engineer decisions on observations that are not retained as active fix tasks. An entry does not mean that a warning was fixed or its cause established.

## M2 — Chrome: VideoFrame without explicit close

**Engineer decision, 2026-10-18:** the diagnostic task was closed while retaining the known observation. No functional failure manifested in the checks performed. **Ownership remains unknown: YUV, Flutter/dependencies, and Chrome have not been ruled out.** No additional fix is currently assigned; the absence of a defect in our packages has not been established.

Chrome 155 / Windows, Flutter 3.44.9, JS/CanvasKit reproduces a warning about a VideoFrame collected without explicit close. The physical open/capture/stop/reopen/dispose scenario passes. Observed probe/reader frames are closed; an additional 10-second gap before reopening did not remove the warning. Eight diagnostic runs were preserved, including separate browser/Flutter controls.

The cause and owner of the unclosed frame **remain unknown** (diagnostic outcome A3). The warning is not classified as false or harmless; absence of a leak is unproven. A browser or dependency defect has not been established either. Closure records the Engineer's decision based on observed behavior, rather than a claim that the warning was fixed.

Investigated pair: yuv_camera `c0e9988dbaa3a4e82f31af04241b6795ad50464f`, yuv_ffi `5bb3ce4b74ac0c3bb4e3291a9ec2cda0e5c4b0bf`. Package sources were unchanged during the investigation.

[Report and evidence in Git](evidence/M2/README.md): environment and exact SHAs, eight checks, console excerpts/counters, related issue searches, and limits of the conclusions. No issue conclusively explaining our case was found; this does not establish that no such issue exists. Complete local group materials remain under `tasks/release-audit-followup/evidence/M2/` and are not included in Git.

Reasons to revisit the observation include a reproducible capture failure or stall, confirmed resource accumulation, or a proven missed-close path in our packages. Recurrence of the already accepted warning alone does not reopen the task.
