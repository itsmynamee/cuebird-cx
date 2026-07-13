#!/bin/bash
# In-memory adapter for tests. State: $MOCK_DB (tsv: id \t status \t title)
set -uo pipefail
DB="${MOCK_DB:?set MOCK_DB}"
touch "$DB"
cmd="$1"; shift
case "$cmd" in
  health) echo "ok Mock/Test" ;;
  add) # y m d H M title body
    id="mock-$RANDOM$RANDOM"
    printf '%s\tpending\t%s\n' "$id" "$6" >> "$DB"
    echo "$id" ;;
  status)
    line=$(grep "^$1"$'\t' "$DB" | tail -1) || { echo missing; exit 0; }
    [ -z "$line" ] && { echo missing; exit 0; }
    echo "$line" | cut -f2 ;;
  complete) printf '%s\tcompleted\t-\n' "$1" >> "$DB" ;;
  delete)   printf '%s\tmissing\t-\n'   "$1" >> "$DB" ;;
  list)
    awk -F'\t' '{ s[$1]=$2; t[$1]=($3=="-"?t[$1]:$3) } END { for (i in s) if (s[i]=="pending") printf "%s\t%s\n", i, t[i] }' "$DB" ;;
  *) echo "unknown: $cmd" >&2; exit 2 ;;
esac
