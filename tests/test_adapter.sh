#!/bin/bash
# Real-Reminders round-trip. LOCAL-ONLY release gate — requires macOS + Reminders permission.
set -uo pipefail
cd "$(dirname "$0")/.."
export CUEBIRD_LIST="Codex Projects Test"
A="plugins/cuebird/scripts/adapters/apple-reminders.sh"
fail() { echo "FAIL: $1"; exit 1; }

out=$("$A" health) || fail "health exited nonzero: $out"
case "$out" in ok\ */"$CUEBIRD_LIST"|ok-local\ */"$CUEBIRD_LIST") ;; *) fail "unexpected health output: $out";; esac
acct_part="${out#ok }"; acct_part="${acct_part#ok-local }"; acct_part="${acct_part%%/*}"
[ -n "$acct_part" ] || fail "empty account segment in health output: $out"
echo "PASS: health"

Y=$(date -v+1d +%Y); M=$(date -v+1d +%m); D=$(date -v+1d +%d)
rid=$("$A" add "$Y" "$M" "$D" 10 30 "Cuebird selftest" "body line 1
line 2 — created by Cuebird test") || fail "add failed"
[ -n "$rid" ] || fail "add printed empty id"
echo "PASS: add ($rid)"

[ "$("$A" status "$rid")" = "pending" ] || fail "status != pending"
"$A" list | grep -qF "$rid" || fail "list does not contain new reminder"
echo "PASS: status+list"

"$A" complete "$rid" || fail "complete failed"
[ "$("$A" status "$rid")" = "completed" ] || fail "status != completed"
"$A" delete "$rid" || fail "delete failed"
[ "$("$A" status "$rid")" = "missing" ] || fail "status != missing after delete"
echo "PASS: complete+delete round-trip"
echo "ALL ADAPTER TESTS PASSED"
