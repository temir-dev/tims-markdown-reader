#!/bin/zsh
set -euo pipefail
project_root=${0:A:h:h}
# Override this to keep transient compiler output outside a synced source folder.
test_root=${READER_TEST_ROOT:-$(mktemp -d "${TMPDIR:-/tmp/}markdown-reader-tests.XXXXXX")}
test_configuration=${READER_TEST_CONFIGURATION:-debug}
[[ "$test_configuration" == debug || "$test_configuration" == release ]] || { print -u2 'READER_TEST_CONFIGURATION must be debug or release'; exit 2; }
test_root=${test_root:A}
[[ "$test_root/" != "$project_root/"* ]] || { print -u2 'READER_TEST_ROOT must be outside the source folder.'; exit 1; }
mkdir -p "$test_root"
export CLANG_MODULE_CACHE_PATH="$test_root/ModuleCache"
print "Test workspace: $test_root"
python3 "$project_root/scripts/check-privacy.py" --source "$project_root"
python3 "$project_root/scripts/verify-notices.py"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$project_root/Tests/ToolingTests"

run_suite() {
  local suite=$1 package=$2
  # pipefail preserves compiler/test failures; the verifier also catches early
  # zero-status exits observed in the AppKit command-line test harness.
  xcrun swift test --build-system native --package-path "$package" \
    --scratch-path "$test_root/$suite" --configuration "$test_configuration" --force-resolved-versions --skip-update \
    2>&1 | tee "$test_root/$suite-test.log"
  python3 "$project_root/scripts/verify-test-log.py" "$test_root/$suite-test.log"
}
run_suite core "$project_root/ReaderCore"
run_suite app "$project_root"
