#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
export CUEBIRD_STATE_DIR=$(mktemp -d) MOCK_DB=$(mktemp)
export CUEBIRD_ADAPTER="$PWD/tests/mock-adapter.sh"
N="plugins/cuebird/scripts/cuebird.sh"
fail() { echo "FAIL: $1"; exit 1; }
DUE=$(date -v+7d +%Y-%m-%dT09:00)

out=$(CUEBIRD_BODY="Що: перевірити гейт" CUEBIRD_PROJECT="MedSearch" \
      CUEBIRD_PROJECT_PATH="/tmp/med" CUEBIRD_RESUME_PROMPT="resume: check gate 2" \
      "$N" add "$DUE" "перевірити гейт 2") || fail "add failed"
echo "$out" | grep -q '"ok":true' || fail "add output: $out"
nmid=$(echo "$out" | sed 's/.*"id":"\([^"]*\)".*/\1/')
rid=$(echo  "$out" | sed 's/.*"reminder_id":"\([^"]*\)".*/\1/')

"$N" list active | grep -q "$nmid" || fail "active list misses new entry"
"$N" get "$nmid" | grep -q '"resume_prompt":"resume: check gate 2"' || fail "resume_prompt not journaled"

# user completes it in the Reminders app → reconcile marks done
"$PWD/tests/mock-adapter.sh" complete "$rid"
"$N" list active | grep -q "$nmid" && fail "reconcile kept completed entry active"
"$N" get "$nmid" | grep -q '"done"' || fail "reconcile did not journal done"
"$N" get "$nmid" | grep -q '"resume_prompt":"resume: check gate 2"' || fail "reconcile transition dropped resume_prompt"

# cancel flow on a fresh one
out2=$("$N" add "$DUE" "друге нагадування") || fail "second add"
nmid2=$(echo "$out2" | sed 's/.*"id":"\([^"]*\)".*/\1/')
"$N" cancel "$nmid2" || fail "cancel"
"$N" get "$nmid2" | grep -q '"cancelled"' || fail "cancel not journaled"

# complete flow (direct command, not via reconcile) on a fresh one
out4=$("$N" add "$DUE" "четверте нагадування") || fail "fourth add"
nmid4=$(echo "$out4" | sed 's/.*"id":"\([^"]*\)".*/\1/')
rid4=$(echo  "$out4" | sed 's/.*"reminder_id":"\([^"]*\)".*/\1/')
out5=$("$N" complete "$nmid4") || fail "complete"
echo "$out5" | grep -q '"ok":true' || fail "complete output: $out5"
"$N" get "$nmid4" | grep -q '"done"' || fail "complete not journaled"
[ "$("$PWD/tests/mock-adapter.sh" status "$rid4")" = "completed" ] || fail "mock adapter status not completed after complete"

# reconcile: reminder removed directly in Reminders (not via cancel/complete) → missing → reconcile marks cancelled
out3=$("$N" add "$DUE" "третє нагадування") || fail "third add"
nmid3=$(echo "$out3" | sed 's/.*"id":"\([^"]*\)".*/\1/')
rid3=$(echo  "$out3" | sed 's/.*"reminder_id":"\([^"]*\)".*/\1/')
"$PWD/tests/mock-adapter.sh" delete "$rid3"
"$N" list active | grep -q "$nmid3" && fail "reconcile kept missing entry active"
"$N" get "$nmid3" | grep -q '"cancelled"' || fail "reconcile did not journal cancelled for missing reminder"

# exit-code contract for degenerate inputs
"$N" cancel >/dev/null 2>&1; [ $? -eq 2 ] || fail "cancel without id must exit 2"
"$N" complete >/dev/null 2>&1; [ $? -eq 2 ] || fail "complete without id must exit 2"
"$N" cancel "nm_nope" >/dev/null 2>&1; [ $? -eq 3 ] || fail "cancel on missing id must exit 3"

# list_name from config.json is wired into CUEBIRD_LIST when the env var is unset
lncfg_dir=$(mktemp -d)
printf '{"list_name":"Custom List","default_hour":9}\n' > "$lncfg_dir/config.json"
lncfg_seen=$(mktemp)
lncfg_wrapper=$(mktemp)
cat > "$lncfg_wrapper" <<EOF
#!/bin/bash
echo "\$CUEBIRD_LIST" >> "$lncfg_seen"
exec "$PWD/tests/mock-adapter.sh" "\$@"
EOF
chmod +x "$lncfg_wrapper"
(
  unset CUEBIRD_LIST
  CUEBIRD_STATE_DIR="$lncfg_dir" MOCK_DB=$(mktemp) CUEBIRD_ADAPTER="$lncfg_wrapper" \
    "$N" add "$DUE" "list name test" >/dev/null
) || fail "list_name test: add failed"
grep -qx "Custom List" "$lncfg_seen" \
  || fail "list_name from config.json not wired into CUEBIRD_LIST (got: $(cat "$lncfg_seen"))"

echo "ALL ORCHESTRATION TESTS PASSED"
