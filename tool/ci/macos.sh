#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
cd "$repository_root/example"
flutter pub get
flutter build macos --debug
bash "$repository_root/tool/ci/drive.sh" integration_test/camera_capture_native_test.dart macos
