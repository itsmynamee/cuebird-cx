#!/bin/bash
# Machine-independent suite (no Reminders access needed).
set -e
cd "$(dirname "$0")"
for t in test_validation.sh test_journal.sh test_orchestration.sh; do
  [ -f "$t" ] && { echo "== $t"; bash "$t"; }
done
echo "SUITE PASSED"
