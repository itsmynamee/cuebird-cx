#!/bin/bash
# Cuebird CX delivery adapter: Apple Reminders. ALL AppleScript lives here.
# Contract (spec §12): add | list | status | complete | delete | health
set -uo pipefail
LIST="${CUEBIRD_LIST:-Codex Projects}"
OSA=/usr/bin/osascript

# Exit codes: 10 permission denied, 11 verify failed (used by add, Task 3), 12 other failure
run_osa() { # stdin: applescript; args: argv for the script
  local out
  out=$("$OSA" - "$@" 2>&1)
  local rc=$?
  if [ $rc -ne 0 ]; then
    case "$out" in
      *-1743*|*"Not authorized"*) echo "permission" >&2; exit 10 ;;
      *-600*) echo "reminders-app-unavailable" >&2; exit 12 ;;
      *) echo "$out" >&2; exit 12 ;;
    esac
  fi
  printf '%s' "$out"
}

resolve_account() { # prints "<flag>\t<account>": flag=icloud|local
  run_osa <<'EOF'
on run argv
  tell application "Reminders"
    set accNames to name of every account
    if accNames contains "iCloud" then return "icloud" & tab & "iCloud"
    return "local" & tab & (item 1 of accNames)
  end tell
end run
EOF
}

ensure_list() { # $1 account
  run_osa "$1" "$LIST" <<'EOF' >/dev/null
on run argv
  tell application "Reminders"
    tell account (item 1 of argv)
      if not (exists list (item 2 of argv)) then
        make new list with properties {name:(item 2 of argv)}
      end if
    end tell
  end tell
end run
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  health)
    acct_info=$(resolve_account) || exit $?
    flag="${acct_info%%$'\t'*}"; acct="${acct_info#*$'\t'}"
    ensure_list "$acct"
    if [ "$flag" = "icloud" ]; then echo "ok $acct/$LIST"; else echo "ok-local $acct/$LIST"; fi
    ;;
  add) # yyyy mm dd HH MM title body → prints reminder id
    acct_info=$(resolve_account) || exit $?   # $(...) swallows exit codes — always guard
    acct="${acct_info#*$'\t'}"
    ensure_list "$acct"
    rid=$(run_osa "$acct" "$LIST" "$1" "$2" "$3" "$4" "$5" "$6" "$7" <<'EOF'
on run argv
  set d to current date
  set day of d to 1 -- avoid month-overflow while re-targeting
  set year of d to (item 3 of argv) as integer
  set month of d to (item 4 of argv) as integer
  set day of d to (item 5 of argv) as integer
  set time of d to ((item 6 of argv) as integer) * 3600 + ((item 7 of argv) as integer) * 60
  tell application "Reminders"
    tell list (item 2 of argv) of account (item 1 of argv)
      set r to make new reminder with properties {name:(item 8 of argv), body:(item 9 of argv), remind me date:d}
    end tell
    return id of r
  end tell
end run
EOF
) || exit $?
    # Read-back semantics: permission loss (10) propagates; ANY other read-back
    # failure is a verification failure (11) by design — see spec §10.
    # Verification (spec §6): read the reminder back before claiming success.
    name=$(run_osa "$rid" <<'EOF'
on run argv
  tell application "Reminders" to return name of reminder id (item 1 of argv)
end run
EOF
) || { rc=$?; [ "$rc" -eq 10 ] && exit 10; echo "verify failed" >&2; exit 11; }
    [ "$name" = "$6" ] || { echo "verify failed" >&2; exit 11; }
    echo "$rid"
    ;;
  status) # <id> → pending|completed|missing
    run_osa "$1" <<'EOF'
on run argv
  tell application "Reminders"
    try
      if completed of reminder id (item 1 of argv) then return "completed"
      return "pending"
    on error
      return "missing"
    end try
  end tell
end run
EOF
    echo ""
    ;;
  complete) # <id>
    run_osa "$1" <<'EOF' >/dev/null
on run argv
  tell application "Reminders" to set completed of reminder id (item 1 of argv) to true
end run
EOF
    ;;
  delete) # <id>
    run_osa "$1" <<'EOF' >/dev/null
on run argv
  tell application "Reminders" to delete reminder id (item 1 of argv)
end run
EOF
    ;;
  list) # id<TAB>title per pending reminder
    acct_info=$(resolve_account) || exit $?
    acct="${acct_info#*$'\t'}"
    ensure_list "$acct"
    out=$(run_osa "$acct" "$LIST" <<'EOF'
on run argv
  set out to ""
  tell application "Reminders"
    tell list (item 2 of argv) of account (item 1 of argv)
      repeat with r in (every reminder whose completed is false)
        set out to out & (id of r) & tab & (name of r) & linefeed
      end repeat
    end tell
  end tell
  return out
end run
EOF
) || exit $?
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
    ;;
  *)
    echo "unknown command: $cmd" >&2; exit 2 ;;
esac
