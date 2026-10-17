#!/usr/bin/env bash
set -euo pipefail
if (( $# < 2 )); then echo "Usage: $0 <integration-test-target> <device> [flutter-drive-arguments...]" >&2; exit 64; fi
target="$1"; device="$2"; shift 2
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
output_file="$(mktemp "${TMPDIR:-/tmp}/yuv-camera-drive.XXXXXX")"
trap 'rm -f "$output_file"' EXIT
cd "$repo_root/example"
echo "RUN $target on $device"
set +e
flutter drive --driver=test_driver/integration_test.dart --target="$target" -d "$device" "$@" 2>&1 | tee "$output_file" | awk '/^(Running |Building |Xcode build done|Installing and launching|VMServiceFlutterDriver: Connected|flutter: [0-9]+:[0-9]+ )/ { print; fflush(); }'
result=${PIPESTATUS[0]}
set -e
if (( result != 0 )); then tail -n 120 "$output_file"; echo "flutter drive failed for $target on $device with exit code $result" >&2; exit "$result"; fi
if ! grep -Fq 'All tests passed' "$output_file"; then tail -n 120 "$output_file"; echo "flutter drive completed for $target on $device without All tests passed" >&2; exit 1; fi
if grep -Eq 'Some tests failed|Failure Details:' "$output_file"; then tail -n 120 "$output_file"; echo "flutter drive reported test failures for $target on $device" >&2; exit 1; fi
echo "PASS $target on $device"
