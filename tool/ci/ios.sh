#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
cd "$repository_root/example"
flutter pub get
cd ios
LANG=en_US.UTF-8 pod install
cd ..
flutter build ios --simulator --debug --no-codesign
simulator_id="$(xcrun simctl list devices available -j | jq -r '[.devices | to_entries | .[] | select(.key | startswith("com.apple.CoreSimulator.SimRuntime.iOS-18-")) | .value[] | select(.name | startswith("iPhone"))][0].udid // empty')"
if [[ -z "$simulator_id" ]]; then echo 'No available iPhone simulator with an iOS 18.x runtime was found.' >&2; exit 1; fi
bash "$repository_root/tool/ci/drive.sh" integration_test/camera_capture_native_test.dart "$simulator_id" --no-pub
bash "$repository_root/tool/ci/drive.sh" integration_test/shape_crop_test.dart "$simulator_id" --no-pub
bash "$repository_root/tool/ci/drive.sh" integration_test/orchestrator_cycles_test.dart "$simulator_id" --no-pub
