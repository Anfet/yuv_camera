#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  printf 'usage: bash tool/ci/scope_guard.sh <base-sha>\n' >&2
  exit 2
fi
base="$1"
git rev-parse --verify "$base^{commit}" >/dev/null
path_keys() {
  case "$1" in
    *.md|doc/*|tasks/*) ;;
    tool/ci/_common.ps1|tool/ci/drive.ps1|tool/ci/drive.sh|tool/ci/scope_guard.sh) printf 'all\n' ;;
    tool/ci/vm.*) printf 'vm\n' ;;
    tool/ci/windows.*) printf 'windows\n' ;;
    tool/ci/android.*) printf 'android\n' ;;
    tool/ci/web.*) printf 'web\n' ;;
    tool/ci/example.*) printf 'example\n' ;;
    tool/ci/macos.*) printf 'macos\n' ;;
    tool/ci/ios.*) printf 'ios\n' ;;
    tool/ci/linux.*) printf 'linux\n' ;;
    .github/workflows/*) printf 'all\n' ;;
    example/integration_test/*|example/pubspec.yaml|pubspec.yaml|pubspec.lock) printf 'all\n' ;;
    example/lib/*) printf 'vm example windows android web\n' ;;
    tool/ci/*) printf 'all\n' ;;
    example/test_driver/*) printf 'all\n' ;;
    example/test/*) printf 'vm\n' ;;
    example/windows/*) printf 'windows\n' ;;
    example/android/*) printf 'android\n' ;;
    example/web/*) printf 'web\n' ;;
    example/macos/*) printf 'macos\n' ;;
    example/ios/*) printf 'ios\n' ;;
    example/linux/*) printf 'linux\n' ;;
    lib/*|test/*) printf 'vm windows web\n' ;;
    *) printf 'all\n' ;;
  esac
}
keys=()
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  while IFS= read -r key; do [[ -n "$key" ]] && keys+=("$key"); done < <(path_keys "$path")
done < <({ git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)
if ((${#keys[@]} == 0)); then printf 'none\n'; exit 0; fi
printf '%s\n' "${keys[@]}" | sort -u | while IFS= read -r key; do
  if [[ "$key" == all ]]; then printf 'vm windows android web example macos ios linux\n'; else printf '%s\n' "$key"; fi
done | tr ' ' '\n' | sed '/^$/d' | sort -u
