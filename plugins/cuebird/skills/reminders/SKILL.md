---
name: reminders
description: Review and manage every Cuebird decision — active phone reminders, past ones, declined and deferred offers. Use when the user asks what reminders exist, wants to change/cancel/re-enable one, revisit a "no", or clean up history.
---

# Cuebird: reminders (the journal)

The journal records every decision ever made about a reminder — accepted,
declined, deferred, done, cancelled. The Reminders app owns notification
content; the journal owns history. Nothing here is final: every past "no"
can become a "yes". Below, `$CUEBIRD` denotes the resolved absolute path to
the CLI — it is notation, not a shell variable: each bash command you run is
its own fresh shell, so substitute the literal path directly into every
command below (or, if you do assign a shell variable, only rely on it within
one single bash invocation, never across separate tool calls).

Resolve `$CUEBIRD` using these methods, in order — never guess beyond them:
1. If your skill invocation provides a "Base directory for this skill" (or
   equivalent), use it directly:
   `CUEBIRD=<that-base>/../../scripts/cuebird.sh`
2. Otherwise, if the environment variable `PLUGIN_ROOT` is set in your Bash
   environment, use `"$PLUGIN_ROOT/scripts/cuebird.sh"`.
3. If neither is available, stop and tell the user Cuebird must be reinstalled;
   do not guess an internal Codex installation path.

### Shell safety (read before running any command below)

Every value you interpolate into these commands — id, title, due date,
status, project name — is either free text or came from journal content you
don't fully control. Double-quoted shell strings still expand backticks,
`$(...)`, and `$VAR` inside them, so free text containing any of those is
command-substituted or executed. That is a shell-injection risk, not a
theoretical one.

**ALWAYS wrap every interpolated value in SINGLE quotes, no exceptions —
including ids and dates, not only obviously free-text fields. Escape any
embedded single quote as `'\''`. NEVER use double quotes around interpolated
text.** (Same rule as skills/remind; repeated here in full because every
command template below interpolates something.)

Example: an id or title containing `It's` becomes `'It'\''s'` (close the
quote, escaped literal `'`, reopen the quote).

## Showing the journal

Default to the whole journal across all projects (that's the point of this
skill); scope to one project only if the user asks for that or the context
makes it obvious:
```bash
"$CUEBIRD" list all
"$CUEBIRD" list all '<project>'   # optional project scope
```
Each output line is a JSON object. `list all` (like `list active`)
auto-reconciles active entries with the Reminders app first (completed there
→ `done`; deleted there → `cancelled`), so what you see is current, not
stale. Read the printed JSON yourself to get each entry's `status` field —
no separate call per status is needed unless the user asks to see only one
bucket (e.g. "show me just what I declined"), in which case use
`"$CUEBIRD" list '<status>' '<project>'` directly.

Present as a compact table grouped by status, in the user's language: active
first (title — human date — project), then deferred (with re-offer dates),
then declined, then done/cancelled only if the user asked for history. The
journal's own `status` field spells the active bucket `accepted`, never
`active` — `active` is only the CLI's display/filter label (`list active`
maps to `accepted` internally); group by `accepted` when reading raw JSON,
but still label it "active" to the user.
Convert dates to human form («24 лип») yourself — never show raw
`YYYY-MM-DDTHH:MM` or raw JSON on screen. Skip any status group with no
entries silently — don't print an empty "declined: (none)" row. If the
journal has entries but none for a bucket the user explicitly asked about,
say so in one line instead of a table.

## Actions (always confirm the target entry first by title)

- **Cancel active**: `"$CUEBIRD" cancel '<id>'` — deletes from Reminders
  too. Success prints `{"ok":true}`. Unknown id → exit 3, say plainly you
  couldn't find that entry and re-run `list all` rather than guessing at
  another id. `cancel` works on any id regardless of current status — it
  only touches the Reminders app when the entry actually has a live
  `reminder_id` (accepted entries do; declined/deferred ones don't). So it
  doubles as "give up on this deferred/declined entry" without waiting for a
  history cleanup — offer it if the user wants a specific deferred re-offer
  to simply stop, rather than pointing them at bulk history cleaning below.
- **Mark done** (user says it's no longer needed because it happened):
  `"$CUEBIRD" complete '<id>'`. Same exit-code handling as cancel.
- Both `cancel` and `complete` are status-first: they check the Reminders
  app before touching the journal, so if the Reminders-side action fails
  (exit 10 — automation permission denied, or 12 — other Reminders failure),
  nothing is journaled and the entry's status is unchanged. Use the same
  user-facing messages as skills/remind's Failure table for exits 10/12 —
  don't invent new wording.
- **Re-enable a declined/deferred/cancelled one**: run `"$CUEBIRD" get
  '<id>'` and read whatever fields the printed JSON actually has. Status
  transitions (`cancel`/`complete`/reconcile) carry every prior field forward
  automatically, so `title`, `due`, `project`, `project_path`, `context`, and
  `resume_prompt` all survive as long as they were captured at some point in
  the entry's history. The one honest fallback: a genuinely old entry, or one
  written by something other than this CLI, may still lack a field it never
  had to begin with — if so, ask the user for it (or reconstruct it from
  conversation context) rather than fabricating it.
  Agree the new date with the user, then create exactly per skills/remind's
  Creating section (single-quoted env vars, first-use `health` check if
  applicable, same confirmation line). The old entry stays in the journal
  as history unchanged; the new one gets a new id from `add`.
- **Change a deferral date**: re-arming reuses the same journal id; fields
  you don't re-supply (e.g. `CUEBIRD_PROJECT`) carry forward automatically
  from the id's current state, so you only need to pass what's actually
  changing:
  ```bash
  CUEBIRD_ID='<id>' \
  CUEBIRD_REOFFER_AT='<new-YYYY-MM-DDTHH:MM>' \
  "$CUEBIRD" log deferred '<title>' '<due>'
  ```
  Use the same `<title>` and `<due>` a prior `get '<id>'` showed — don't
  rephrase them. Acknowledge in one short sentence once done.
- **Change an active reminder's date/text**: don't — there is no `edit`
  command. Say honestly that editing content lives in the Reminders app
  itself (one tap there), and offer cancel-then-recreate here if the user
  prefers doing it through this journal.
- **Clean history**: ask which statuses to purge — only `done`, `cancelled`,
  or `declined` are ever eligible. **Never prune `accepted` or `deferred`**,
  even if the user asks: those are live (an active phone reminder, or a
  promise to re-offer later) and pruning is a permanent journal rewrite, not
  a status change — there is no undo. If the user wants an active or
  deferred entry gone, cancel it first (making it eligible), or just leave it
  as-is. Confirm the exact statuses before running anything, then per chosen
  status:
  ```bash
  "$CUEBIRD" prune '<status>'
  ```
  Each call prints the number of entries it removed — report those counts
  back to the user (e.g. "removed 3 declined, 1 cancelled").

## Empty journal

«Поки що жодних нагадувань — я запропоную, щойно в розмові з'явиться
дедлайн. Або скажи "нагадай мені..." будь-коли.»
