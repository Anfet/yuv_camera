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
simulator_state="$(xcrun simctl list devices available -j | jq -r --arg id "$simulator_id" '.devices[][] | select(.udid == $id) | .state')"
if [[ "$simulator_state" != Booted ]]; then
  xcrun simctl boot "$simulator_id"
  trap 'xcrun simctl shutdown "$simulator_id"' EXIT
fi
xcrun simctl bootstatus "$simulator_id" -b
bash "$repository_root/tool/ci/drive.sh" integration_test/camera_capture_native_test.dart "$simulator_id" --no-pub
bash "$repository_root/tool/ci/drive.sh" integration_test/shape_crop_test.dart "$simulator_id" --no-pub
# The simulator has no camera. Run the real lifecycle separately on a physical iPhone:
# bash tool/ci/drive.sh integration_test/orchestrator_cycles_test.dart <iphone-id> --no-pub
bash "$repository_root/tool/ci/drive.sh" integration_test/ios_bgra_camera_frame_test.dart "$simulator_id" --no-pub
