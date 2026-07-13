#!/bin/bash
# Cuebird CX SessionStart: one sentence of awareness + any due deferred offers.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Cuebird CX is installed: when a concrete future deadline, checkpoint, or dateless waiting condition emerges, offer once to set a phone reminder with the remind skill. If the user mentions a reminder that fired, use the resume skill."
"$DIR/../scripts/cuebird-cx.sh" due-deferrals 2>/dev/null | while IFS= read -r line; do
  [ -n "$line" ] && echo "Cuebird CX: a previously deferred reminder offer is now due — re-offer it once at a natural pause: $line"
done
exit 0
