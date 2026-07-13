#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
export CUEBIRD_STATE_DIR=$(mktemp -d) MOCK_DB=$(mktemp)
export CUEBIRD_ADAPTER="$PWD/tests/mock-adapter.sh"
N="plugins/cuebird-cx/scripts/cuebird-cx.sh"
fail() { echo "FAIL: $1"; exit 1; }

id1=$(CUEBIRD_PROJECT="ProjA" "$N" log declined "skip me" "2026-08-01T09:00") || fail "log declined"
CUEBIRD_PROJECT="ProjB" CUEBIRD_REOFFER_AT="2020-01-01T00:00" "$N" log deferred "ask me later" "2026-09-01T09:00" >/dev/null || fail "log deferred"

out=$("$N" list declined); echo "$out" | grep -q '"skip me"' || fail "list declined misses entry"
out=$("$N" list declined ProjB); echo "$out" | grep -q '"skip me"' && fail "project filter leaked"
out=$("$N" get "$id1"); echo "$out" | grep -q '"declined"' || fail "get by id"
out=$("$N" get "nm_nope" 2>&1); [ $? -eq 3 ] || fail "get missing should exit 3"

# past reoffer_at → due
out=$("$N" due-deferrals); echo "$out" | grep -q '"ask me later"' || fail "due-deferrals misses due entry"
# status transition: same id, new status wins
CUEBIRD_ID="$id1" "$N" log accepted "skip me" "2026-08-01T09:00" >/dev/null
out=$("$N" list declined); echo "$out" | grep -q '"skip me"' && fail "transition did not supersede"

cnt=$("$N" prune deferred) || fail "prune"
out=$("$N" list deferred); echo "$out" | grep -q '"ask me later"' && fail "prune left entry"

# exit-code contract for degenerate inputs
"$N" log "" "t" - >/dev/null 2>&1; [ $? -eq 2 ] || fail "empty status must exit 2"
"$N" log accepted "" - >/dev/null 2>&1; [ $? -eq 2 ] || fail "empty title must exit 2"
# concurrent appends must not lose entries
CONC_DIR=$(mktemp -d)
for i in $(seq 1 20); do CUEBIRD_STATE_DIR="$CONC_DIR" "$N" log declined "conc $i" - >/dev/null & done
wait
cnt=$(wc -l < "$CONC_DIR/journal.jsonl" | tr -d ' ')
[ "$cnt" -eq 20 ] || fail "concurrent appends lost entries: $cnt/20"

# realistic-payload concurrency: 4KB resume prompts must not tear
BIG=$(head -c 4096 /dev/zero | tr '\0' 'x')
CONC2=$(mktemp -d)
for i in $(seq 1 40); do CUEBIRD_STATE_DIR="$CONC2" CUEBIRD_RESUME_PROMPT="$BIG" "$N" log declined "big $i" - >/dev/null & done
wait
cnt2=$(CUEBIRD_STATE_DIR="$CONC2" "$N" list declined | wc -l | tr -d ' ')
[ "$cnt2" -eq 40 ] || fail "4KB concurrent appends torn/lost: $cnt2/40"
# malformed line must not poison the journal
echo '{broken json' >> "$CONC2/journal.jsonl"
CUEBIRD_STATE_DIR="$CONC2" "$N" list declined | wc -l | grep -q '40' || fail "malformed line poisoned list"
# degenerate args
"$N" get >/dev/null 2>&1; [ $? -eq 2 ] || fail "get without id must exit 2"
"$N" prune >/dev/null 2>&1; [ $? -eq 2 ] || fail "prune without status must exit 2"
# due-deferrals empty → zero bytes
DD=$(mktemp -d); [ -z "$(CUEBIRD_STATE_DIR="$DD" "$N" due-deferrals)" ] || fail "empty due-deferrals must print nothing"

# log: unwritable journal must surface as exit 12, not a silent false success
RO_DIR=$(mktemp -d)
CUEBIRD_STATE_DIR="$RO_DIR" "$N" log declined "seed" - >/dev/null || fail "seed log for read-only test"
chmod 444 "$RO_DIR/journal.jsonl"
err=$(CUEBIRD_STATE_DIR="$RO_DIR" "$N" log declined "should fail" - 2>&1 >/dev/null)
rc=$?
chmod 644 "$RO_DIR/journal.jsonl"
[ "$rc" -eq 12 ] || fail "log with unwritable journal must exit 12, got $rc"
echo "$err" | grep -q "journal write failed" || fail "log unwritable-journal failure must say 'journal write failed'"


# transition preserves rich fields (carry-forward merge)
CF=$(mktemp -d)
cfid=$(CUEBIRD_STATE_DIR="$CF" CUEBIRD_PROJECT='ProjCF' CUEBIRD_RESUME_PROMPT='resume me' "$N" log deferred 'carry' '2026-12-01T09:00') || fail "cf log"
CUEBIRD_STATE_DIR="$CF" CUEBIRD_ID="$cfid" "$N" log declined 'carry' '2026-12-01T09:00' >/dev/null || fail "cf transition"
CUEBIRD_STATE_DIR="$CF" "$N" get "$cfid" | grep -q '"resume_prompt":"resume me"' || fail "transition dropped resume_prompt"
CUEBIRD_STATE_DIR="$CF" "$N" get "$cfid" | grep -q '"project":"ProjCF"' || fail "transition dropped project"

# empty journal list must exit 0 with no output
EMPTY=$(mktemp -d)
CUEBIRD_STATE_DIR="$EMPTY" "$N" list all >/dev/null 2>&1 || fail "list all on empty journal must exit 0"
[ -z "$(CUEBIRD_STATE_DIR="$EMPTY" "$N" list all)" ] || fail "list all on empty journal must print nothing"

# Old 0.2 state is moved once to the renamed project directory.
MIG_HOME=$(mktemp -d)
mkdir -p "$MIG_HOME/.codex/cuebird"
printf '%s\n' '{"id":"nm_migrate","status":"declined","title":"migrate me","created_at":"2026-07-13T00:00:00Z"}' > "$MIG_HOME/.codex/cuebird/journal.jsonl"
HOME="$MIG_HOME" CUEBIRD_STATE_DIR= "$N" list declined | grep -q '"migrate me"' || fail "legacy state not readable after migration"
[ -d "$MIG_HOME/.codex/cuebird-cx" ] || fail "renamed state directory missing after migration"
[ ! -e "$MIG_HOME/.codex/cuebird" ] || fail "legacy state directory remained after migration"

echo "ALL JOURNAL TESTS PASSED"
