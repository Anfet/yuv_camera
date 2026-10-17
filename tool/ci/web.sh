#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
: "${CHROME_EXECUTABLE:?Set CHROME_EXECUTABLE to Chrome}"
: "${CHROMEDRIVER_EXE:?Set CHROMEDRIVER_EXE to ChromeDriver}"
"$CHROMEDRIVER_EXE" --port=4444 >/tmp/yuv-camera-chromedriver.log 2>&1 &
driver_pid=$!
trap 'kill "$driver_pid" 2>/dev/null || true; wait "$driver_pid" 2>/dev/null || true' EXIT
cd "$repo_root/example"
flutter pub get
"$script_dir/drive.sh" integration_test/camera_source_web_lifecycle_test.dart web-server --browser-name=chrome --headless --web-browser-flag=--use-fake-device-for-media-stream --web-browser-flag=--use-fake-ui-for-media-stream --no-pub
echo 'PASS Chrome JavaScript camera source lifecycle regression.'
"$script_dir/drive.sh" integration_test/camera_source_web_smoke_test.dart web-server --browser-name=chrome --headless --web-browser-flag=--use-fake-device-for-media-stream --web-browser-flag=--use-fake-ui-for-media-stream --no-pub
echo 'PASS Chrome JavaScript camera source smoke.'
"$script_dir/drive.sh" integration_test/shape_crop_test.dart web-server --browser-name=chrome --headless --web-browser-flag=--use-fake-device-for-media-stream --web-browser-flag=--use-fake-ui-for-media-stream --no-pub
echo 'PASS Chrome shape crop target.'
"$script_dir/drive.sh" integration_test/orchestrator_cycles_test.dart web-server --browser-name=chrome --headless --web-browser-flag=--use-fake-device-for-media-stream --web-browser-flag=--use-fake-ui-for-media-stream --no-pub
echo 'PASS Chrome orchestrator cycles target.'
