#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
export CUEBIRD_STATE_DIR=$(mktemp -d) MOCK_DB=$(mktemp)
export CUEBIRD_ADAPTER="$PWD/tests/mock-adapter.sh"
N="plugins/cuebird/scripts/cuebird.sh"
fail() { echo "FAIL: $1"; exit 1; }
expect_rc2() { "$N" "$@" >/dev/null 2>&1; [ $? -eq 2 ] || fail "expected exit 2: $N $*"; }

expect_rc2 add "not-a-date" "title"
expect_rc2 add "2026-13-01T09:00" "title"          # impossible month
expect_rc2 add "2020-01-01T09:00" "in the past"    # past date
expect_rc2 add "$(date -v+1d +%Y-%m-%dT09:00)" ""  # empty title
expect_rc2 add "$(date -v+1d +%Y-%m-%d)" "title"   # missing time part
expect_rc2 add "2027-02-30T09:00" "feb 30 does not exist"
expect_rc2 add "2027-04-31T09:00" "april has 30 days"
expect_rc2 add "2027-02-29T09:00" "2027 is not a leap year"
out=$("$N" add "2028-02-29T09:00" "real leap day" 2>&1)
[ $? -eq 0 ] || fail "2028-02-29 (valid leap day) should pass validation and succeed: $out"
echo "$out" | grep -q '"ok":true' || fail "valid leap day add did not report ok: $out"
echo "ALL VALIDATION TESTS PASSED"
