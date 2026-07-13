#!/bin/bash
# Cuebird CX CLI façade. Skills call this and never the adapter directly.
# Commands: add | log | list | get | cancel | complete | due-deferrals | prune | health | selftest
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${CUEBIRD_STATE_DIR:-}" ]; then
  STATE_DIR="$CUEBIRD_STATE_DIR"
else
  STATE_DIR="$HOME/.codex/cuebird-cx"
  LEGACY_STATE_DIR="$HOME/.codex/cuebird"
  if [ ! -e "$STATE_DIR" ] && [ -d "$LEGACY_STATE_DIR" ]; then
    mv "$LEGACY_STATE_DIR" "$STATE_DIR" \
      || { echo "failed to migrate state to $STATE_DIR" >&2; exit 2; }
  fi
fi
ADAPTER="${CUEBIRD_ADAPTER:-$SELF_DIR/adapters/apple-reminders.sh}"
JOURNAL="$STATE_DIR/journal.jsonl"
OSA=/usr/bin/osascript

mkdir -p "$STATE_DIR"
[ -f "$STATE_DIR/config.json" ] || printf '{ "list_name": "Codex Projects", "default_hour": 9 }\n' > "$STATE_DIR/config.json"
touch "$JOURNAL"

if [ -z "${CUEBIRD_LIST:-}" ]; then
  CUEBIRD_LIST=$("$OSA" -l JavaScript -e 'function run(a){try{return String(JSON.parse(a[0]).list_name||"Codex Projects")}catch(e){return "Codex Projects"}}' "$(cat "$STATE_DIR/config.json" 2>/dev/null || echo '{}')")
  export CUEBIRD_LIST
fi

die2() { echo "$1" >&2; exit 2; }

journal_append() { # $1: the JSON line to append
  # mkdir lock: bash printf may split >2KB lines into multiple write(2)s; O_APPEND alone is not enough
  local lockdir="$STATE_DIR/.journal.lock" i=0
  until mkdir "$lockdir" 2>/dev/null; do
    i=$((i+1))
    if [ "$i" -ge 100 ]; then  # ~5s: steal stale lock (crashed holder)
      rmdir "$lockdir" 2>/dev/null || true
      i=0
    fi
    sleep 0.05
  done
  printf '%s\n' "$1" >> "$JOURNAL"
  local rc=$?
  rmdir "$lockdir"
  return $rc
}

jxa_journal() { # $1: mode (append|list|get|due|prune), then mode args; env passes fields
  "$OSA" -l JavaScript - "$JOURNAL" "$@" <<'EOF'
ObjC.import('Foundation');
function readLines(p) {
  const s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null);
  if (!s || s.isNil && s.isNil()) return [];
  const out = [];
  ObjC.unwrap(s).split('\n').filter(l => l.trim()).forEach(l => {
    try { out.push(JSON.parse(l)); } catch (e) {}
  });
  return out;
}
function lastState(entries) {
  const m = {};
  entries.forEach(e => { m[e.id] = e; });
  return Object.values(m);
}
function env(k) { const v = $.NSProcessInfo.processInfo.environment.objectForKey(k); return v.isNil() ? "" : ObjC.unwrap(v); }
function run(argv) {
  const path = argv[0], mode = argv[1];
  if (mode === 'append') {
    const idEnv = env('CUEBIRD_ID');
    const e = {
      id: idEnv || 'nm_' + Date.now() + '_' + Math.floor(Math.random()*1e6),
      status: argv[2], title: argv[3], due: argv[4] === '-' ? '' : argv[4],
      project: env('CUEBIRD_PROJECT'), project_path: env('CUEBIRD_PROJECT_PATH'),
      context: env('CUEBIRD_CONTEXT'), resume_prompt: env('CUEBIRD_RESUME_PROMPT'),
      reminder_id: env('CUEBIRD_REMINDER_ID'), reoffer_at: env('CUEBIRD_REOFFER_AT'),
      created_at: new Date().toISOString()
    };
    if (idEnv) {
      // Carry-forward merge: a status transition (cancel/complete/reconcile/
      // re-armed deferral) only supplies the fields relevant to that
      // transition (status/title/due, sometimes reoffer_at) — anything left
      // empty/absent here falls back to the id's current last state, so
      // fields like project/project_path/context/resume_prompt/reminder_id
      // survive across transitions instead of being dropped. New non-empty
      // values still win; status/created_at always come from this event.
      // This read is not covered by the bash-side mkdir lock that guards the
      // eventual append write (see journal_append) — a read-vs-append race
      // is possible but acceptable for a single-user tool.
      const prior = lastState(readLines(path)).find(s => s.id === idEnv);
      if (prior) {
        Object.keys(prior).forEach(k => {
          if (k === 'status' || k === 'created_at') return;
          if (e[k] === '' || e[k] === undefined) e[k] = prior[k];
        });
      }
    }
    Object.keys(e).forEach(k => { if (e[k] === '') delete e[k]; });
    // Build the line here (needs Date/random/env), but do NOT write it from JXA:
    // NSFileHandle seekToEndOfFile+writeData is a TOCTOU race across processes
    // (no O_APPEND at the fd level), so concurrent invocations still clobber each
    // other's entries. The actual disk write is done by the bash caller via
    // journal_append(), which guards the O_APPEND write with an mkdir lock (see
    // that function for why O_APPEND alone isn't sufficient for multi-KB lines).
    return e.id + '\n' + JSON.stringify(e);
  }
  const states = lastState(readLines(path));
  if (mode === 'list') {
    const status = argv[2] || 'all', project = argv[3] || '';
    return states
      .filter(e => status === 'all' || e.status === status)
      .filter(e => !project || e.project === project)
      .map(e => JSON.stringify(e)).join('\n');
  }
  if (mode === 'get') {
    const hit = states.find(e => e.id === argv[2]);
    if (!hit) { return '__NOTFOUND__'; }
    return JSON.stringify(hit);
  }
  if (mode === 'due') {
    const now = new Date();
    // reoffer_at is local naive YYYY-MM-DDTHH:MM — compare as local
    return states.filter(e => e.status === 'deferred' && e.reoffer_at &&
      new Date(e.reoffer_at.replace('T', ' ') + ':00') <= now)
      .map(e => JSON.stringify(e)).join('\n');
  }
  if (mode === 'prune') {
    const drop = new Set(states.filter(e => e.status === argv[2]).map(e => e.id));
    const kept = readLines(path).filter(e => !drop.has(e.id));
    const body = kept.map(e => JSON.stringify(e)).join('\n') + (kept.length ? '\n' : '');
    // prune keeps atomic rewrite: rare, user-invoked — acceptable race window
    $.NSString.alloc.initWithUTF8String(body).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
    return String(drop.size);
  }
  return '';
}
EOF
}

osa_field() { # $1: one JSON object; $2: field name → prints value or ""
  "$OSA" -l JavaScript -e 'function run(a){ return (JSON.parse(a[0])[a[1]]) || "" }' "$1" "$2"
}

validate_due() { # $1: YYYY-MM-DDTHH:MM (local); dies with exit 2, else echoes y m d H M
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})$ ]] \
    || die2 "invalid datetime: '$1' (need YYYY-MM-DDTHH:MM, local time)"
  local y=${BASH_REMATCH[1]} m=${BASH_REMATCH[2]} d=${BASH_REMATCH[3]} H=${BASH_REMATCH[4]} M=${BASH_REMATCH[5]}
  local epoch
  epoch=$(date -j -f "%Y-%m-%dT%H:%M" "$1" +%s 2>/dev/null) || die2 "impossible date: '$1'"
  local roundtrip
  roundtrip=$(date -j -f "%Y-%m-%dT%H:%M" "$1" "+%Y-%m-%dT%H:%M" 2>/dev/null) || die2 "impossible date: '$1'"
  [ "$roundtrip" = "$1" ] || die2 "impossible date: '$1' (did you mean $roundtrip?)"
  [ "$epoch" -gt "$(date +%s)" ] || die2 "date is in the past: '$1'"
  echo "$y $m $d $H $M"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  add)
    due="${1:-}"; title="${2:-}"
    [ -n "$title" ] || die2 "empty title"
    comps=$(validate_due "$due") || exit 2
    read -r y m d H M <<< "$comps"
    rid=$("$ADAPTER" add "$y" "$m" "$d" "$H" "$M" "$title" "${CUEBIRD_BODY:-}") || exit $?
    out=$(CUEBIRD_REMINDER_ID="$rid" jxa_journal append accepted "$title" "$due") \
      || { echo "journal build failed (reminder created: $rid)" >&2; exit 12; }
    nmid="${out%%$'\n'*}"
    line="${out#*$'\n'}"
    journal_append "$line" || { echo "journal write failed (reminder created: $rid)" >&2; exit 12; }
    "$OSA" -l JavaScript -e 'function run(a){return JSON.stringify({ok:true,id:a[0],reminder_id:a[1]})}' "$nmid" "$rid"
    ;;
  cancel|complete)
    nmid="${1:-}"; [ -n "$nmid" ] || die2 "missing id"
    entry=$(jxa_journal get "$nmid"); [ "$entry" = "__NOTFOUND__" ] && exit 3
    rid=$(osa_field "$entry" reminder_id)
    if [ -n "$rid" ]; then
      # TOCTOU between status and delete/complete is accepted: single-user tool,
      # window is ms; worst case reconcile self-heals on next list.
      st=$("$ADAPTER" status "$rid" 2>/dev/null) || exit $?
      if [ "$st" != "missing" ]; then
        if [ "$cmd" = cancel ]; then "$ADAPTER" delete "$rid" || exit $?
        else "$ADAPTER" complete "$rid" || exit $?; fi
      fi
      # missing → nothing to do in Reminders; journaling terminal state below IS the reconcile
    fi
    newst=$([ "$cmd" = cancel ] && echo cancelled || echo done)
    out=$(CUEBIRD_ID="$nmid" jxa_journal append "$newst" "$(osa_field "$entry" title)" "$(osa_field "$entry" due)") || exit 2
    journal_append "${out#*$'\n'}" \
      || { echo "journal write failed — Reminders state WAS changed but not recorded; re-run the command" >&2; exit 12; }
    echo '{"ok":true}'
    ;;
  log) # <status> <title> <due-or->
    st="${1:-}"; ti="${2:-}"; du="${3:--}"
    [ -n "$st" ] || die2 "missing status"
    case "$st" in accepted|declined|deferred|cancelled|done) ;; *) die2 "bad status: $st";; esac
    [ -n "$ti" ] || die2 "empty title"
    out=$(jxa_journal append "$st" "$ti" "$du") || exit 2
    id="${out%%$'\n'*}"
    line="${out#*$'\n'}"
    journal_append "$line" || { echo "journal write failed" >&2; exit 12; }
    echo "$id"
    ;;
  list)
    want="${1:-all}"; proj="${2:-}"
    if [ "$want" = "active" ] || [ "$want" = "all" ]; then
      jxa_journal list accepted "$proj" | while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        rid=$(osa_field "$entry" reminder_id); [ -n "$rid" ] || continue
        eid=$(osa_field "$entry" id)
        st=$("$ADAPTER" status "$rid" 2>/dev/null || echo pending)
        case "$st" in
          completed)
            out=$(CUEBIRD_ID="$eid" jxa_journal append done "$(osa_field "$entry" title)" "$(osa_field "$entry" due)") || continue
            line="${out#*$'\n'}"
            [ -n "$line" ] && { journal_append "$line" || echo "warning: reconcile journal write failed (will retry on next list)" >&2; }
            ;;
          missing)
            out=$(CUEBIRD_ID="$eid" jxa_journal append cancelled "$(osa_field "$entry" title)" "$(osa_field "$entry" due)") || continue
            line="${out#*$'\n'}"
            [ -n "$line" ] && { journal_append "$line" || echo "warning: reconcile journal write failed (will retry on next list)" >&2; }
            ;;
        esac
      done
    fi
    [ "$want" = "active" ] && want="accepted"
    out=$(jxa_journal list "$want" "$proj")
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
    ;;
  get)
    id="${1:-}"; [ -n "$id" ] || die2 "missing id"
    out=$(jxa_journal get "$id")
    [ "$out" = "__NOTFOUND__" ] && exit 3
    echo "$out"
    ;;
  due-deferrals)
    out=$(jxa_journal due)
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
    ;;
  prune)
    st="${1:-}"; [ -n "$st" ] || die2 "missing status"
    jxa_journal prune "$st"
    ;;
  health)
    "$ADAPTER" health
    ;;
  selftest)
    # Self-contained round-trip against a test list (no repo dependency —
    # this must work from an installed plugin). Journal ops in a temp dir.
    st_fail() { echo "SELFTEST FAILED: $1"; exit 1; }
    tdir=$(mktemp -d)
    tid=$(CUEBIRD_STATE_DIR="$tdir" "$SELF_DIR/cuebird-cx.sh" log declined "selftest" "-") || st_fail "journal write"
    CUEBIRD_STATE_DIR="$tdir" "$SELF_DIR/cuebird-cx.sh" get "$tid" >/dev/null || st_fail "journal read"
    export CUEBIRD_LIST="Codex Projects Test"
    y=$(date -v+1d +%Y); m=$(date -v+1d +%m); d=$(date -v+1d +%d)
    rid=$("$ADAPTER" add "$y" "$m" "$d" 10 30 "Cuebird CX selftest" "created and removed by Cuebird CX doctor") || st_fail "adapter add"
    [ "$("$ADAPTER" status "$rid")" = "pending" ] || st_fail "status after add"
    "$ADAPTER" complete "$rid" || st_fail "complete"
    "$ADAPTER" delete "$rid"   || st_fail "delete"
    [ "$("$ADAPTER" status "$rid")" = "missing" ] || st_fail "status after delete"
    echo "SELFTEST PASSED"
    ;;
  *) die2 "unknown command: $cmd" ;;
esac
