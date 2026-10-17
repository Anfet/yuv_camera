#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/drive-contract.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin" "$work/tmp"
cat > "$work/bin/flutter" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$@" > "$CONTRACT_WORK/argv"
cat "$CONTRACT_WORK/stdout"
cat "$CONTRACT_WORK/stderr" >&2
exit "$(cat "$CONTRACT_WORK/exit")"
MOCK
chmod +x "$work/bin/flutter"
export CONTRACT_WORK="$work"
export PATH="$work/bin:$PATH"
export TMPDIR="$work/tmp"
count=0
failures=0
run_case() {
  local name="$1" code="$2" expected="$3" stdout="$4" stderr="${5:-}" actual=0 verdict=0
  printf '%s\n' "$stdout" > "$work/stdout"
  printf '%s\n' "$stderr" > "$work/stderr"
  printf '%s\n' "$code" > "$work/exit"
  bash "$repo_root/tool/ci/drive.sh" 'integration_test/mock target.dart' contract-device '--dart-define=VALUE=two words' > "$work/output" 2>&1 || actual=$?
  grep -q '^PASS integration_test/mock target.dart on contract-device$' "$work/output" && verdict=1
  count=$((count + 1))
  if { [[ "$expected" == pass ]] && { (( actual != 0 )) || (( verdict != 1 )); }; } || { [[ "$expected" == fail ]] && { (( actual == 0 )) || (( verdict != 0 )); }; }; then
    echo "FAIL $name: expected=$expected actual exit=$actual wrapper PASS=$verdict" >&2
    failures=$((failures + 1))
  fi
  printf '%s\n' "$repo_root/example" drive --driver=test_driver/integration_test.dart '--target=integration_test/mock target.dart' -d contract-device '--dart-define=VALUE=two words' > "$work/expected"
  if ! diff -q "$work/expected" "$work/argv" >/dev/null || [[ -n "$(ls -A "$work/tmp")" ]]; then
    echo "FAIL $name: argv/cwd mismatch or temporary log leaked" >&2
    failures=$((failures + 1))
  fi
}
run_case success 0 pass 'All tests passed; Error is harmless'
run_case exit7 7 fail 'All tests passed'
run_case missing 0 fail 'Finished'
run_case some-after 0 fail $'All tests passed\nSome tests failed'
run_case some-before 0 fail $'Some tests failed\nAll tests passed'
run_case details-after 0 fail $'All tests passed\nFailure Details:'
run_case details-before 0 fail $'Failure Details:\nAll tests passed'
run_case stderr 0 fail 'All tests passed' 'Some tests failed'
run_case recovery 0 pass 'All tests passed'
if (( failures > 0 )); then echo "drive_contract bash: $failures failures / $count cases" >&2; exit 1; fi
echo "drive_contract bash: $count cases PASS"
