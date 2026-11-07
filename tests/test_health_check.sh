#!/usr/bin/env bash
# Basic smoke tests; no external test framework required.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/health_check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

"$SCRIPT" --help > "$TMP/help.txt" || fail "help exits successfully"
grep -q "Usage:" "$TMP/help.txt" || fail "help contains usage"
pass "help output"

report="$TMP/report.txt"
set +e
"$SCRIPT" --config "$ROOT/config/thresholds.conf" --report "$report" >/dev/null
rc=$?
set -e
[[ "$rc" -eq 0 || "$rc" -eq 1 || "$rc" -eq 2 ]] || fail "valid config returns a documented status"
[[ -s "$report" ]] || fail "report created"
grep -q "Linux Server Health Report" "$report" || fail "report title present"
grep -q "Overall status:" "$report" || fail "overall status present"
pass "report generation"

printf 'DISK_WARN=invalid\n' > "$TMP/bad.conf"
if "$SCRIPT" --config "$TMP/bad.conf" --report "$TMP/bad-report.txt" >/dev/null 2>&1; then
  fail "invalid threshold should be rejected"
fi
pass "invalid threshold rejected"

echo "All tests passed."
