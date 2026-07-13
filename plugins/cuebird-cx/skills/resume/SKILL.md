---
name: resume
description: "Continue work from a fired Cuebird CX reminder. Use when the user says a reminder arrived / mentions «нагадування: …» / references a notification about a deadline or checkpoint, and wants to pick the work back up."
---

# Cuebird CX: resume

Below, `$CUEBIRD` denotes the resolved absolute path to the CLI — it is
notation, not a shell variable: each bash command you run is its own fresh
shell, so substitute the literal path directly into every command below (or,
if you do assign a shell variable, only rely on it within one single bash
invocation, never across separate tool calls).

Resolve `$CUEBIRD` using these methods, in order — never guess beyond them:
1. If your skill invocation provides a "Base directory for this skill" (or
   equivalent), use it directly:
   `CUEBIRD=<that-base>/../../scripts/cuebird-cx.sh`
2. Otherwise, if the environment variable `PLUGIN_ROOT` is set in your Bash
   environment, use `"$PLUGIN_ROOT/scripts/cuebird-cx.sh"`.
3. If neither is available, stop and tell the user Cuebird CX must be reinstalled;
   do not guess an internal Codex installation path.

The journal stored everything a fresh session needs. Your job: restore
context so completely that the weeks-long gap is invisible.

### Shell safety (read before running any command below)

Every value you interpolate into these commands — the id you pick — either
comes from the user's free-text description or from journal content you
don't fully control. Double-quoted shell strings still expand backticks,
`$(...)`, and `$VAR` inside them, so free text containing any of those is
command-substituted or executed. That is a shell-injection risk, not a
theoretical one.

**ALWAYS wrap every interpolated value in SINGLE quotes, no exceptions —
including ids. Escape any embedded single quote as `'\''`. NEVER use double
quotes around interpolated text.** (Same rule as skills/remind and
skills/reminders; repeated here in full because every command below
interpolates an id chosen from journal content.)

Example: an id containing `It's` becomes `'It'\''s'` (close the quote,
escaped literal `'`, reopen the quote).

## Flow

1. `"$CUEBIRD" list all` — match the user's phrase against titles/context
   semantically. The reminder body told them a short key phrase (the line
   «Відкрий Codex у проєкті й скажи: «нагадування: <short key>»») but
   that literal body text isn't stored in the journal — journal entries only
   ever carry `title`/`context` (never `body`), so match the user's phrase
   against those two fields.

   Match across **every** status `list all` returns, not only active ones.
   Reason: `list all` (like `list active`) auto-reconciles active entries
   with the Reminders app first — so if the user already completed or
   swiped away the reminder on their phone before coming back to Codex
   Code, that entry may already show `status: "done"` (or `"cancelled"` if
   deleted) by the time you see it here. The work context in it is exactly
   as valuable as if it were still active, and resume must still work for
   it — don't filter it out just because it's not `accepted`.
   - **One clear match** → proceed to step 2.
   - **Several plausible** → ask which one, showing title + human date (never
     raw `YYYY-MM-DDTHH:MM`) + status for each (active / done / etc.), so the
     user can tell them apart. On ambiguity between otherwise-equal matches,
     prefer an `accepted` (active) entry — a still-open reminder is the more
     likely thing someone means when they say a reminder "arrived" — but a
     clearly better title/context match on a `done`/`cancelled` entry still
     wins over a weaker-matching active one.
   - **None** → show recent active and done entries (title + human date) and
     ask the user to point at one or describe it in a sentence.
   - **Journal genuinely empty** (`list all` returns nothing at all, not just
     no match) → be honest there's nothing to resume from: «У журналі
     Cuebird CX ще немає жодного нагадування — тож підхопити нема що. Розкажи,
     про що йшлося, і продовжимо просто з розмови.»

2. `"$CUEBIRD" get '<id>'` → read `resume_prompt`, `project_path`, `context`.
   These fields survive status transitions (cancel/complete/reconcile all
   carry them forward from the entry's prior state), so an entry that moved
   from `accepted` to `done` via reconcile — or one you `complete`/`cancel`
   yourself later in this flow — still has them. If `get` reports the id as
   not found (exit 3 — the journal changed between `list` and `get`, or you
   mistyped it), re-run `"$CUEBIRD" list all` rather than guessing at
   another id.

3. If the current working directory is not `project_path`, say so plainly
   and work against `project_path` explicitly: read/write files there with
   absolute paths, and suggest the user reopen Codex in that directory
   if the session's own tooling (build, tests, git) needs to run there.

4. Follow `resume_prompt`: re-verify the CURRENT state first (things may
   have changed since it was written — files may have moved on, the
   checkpoint may already be past), then explain where things stand in
   plain language, then continue the planned next steps.
   - **Condition check-in**: if the resume_prompt or context describes a
     threshold condition (the reminder body's Критерій content — restated
     there per the remind skill's instructions) — e.g. "10+ унікальних
     відвідувачів", "9 сторінок в індексі 14+ днів" — rather than a plain
     deadline, check that condition FIRST, against current reality, before
     anything else in `resume_prompt`.
     - **Met** → say so plainly, then proceed with the planned next steps
       from `resume_prompt` and continue to step 5 (offer complete).
     - **Unmet** → report the actual current value honestly (e.g. «Зараз
       відвідуваність ~4 на день, поки не 10» — never vague, never "ще не
       готово" without the number) and offer to re-arm: propose a fresh
       estimated date per skills/remind's condition-based-waits guidance
       (re-estimate from current pace, state it as an estimate, propose the
       one concrete date), wait for yes/no/defer, and record the answer
       exactly as skills/remind's "Recording the user's answer" section
       specifies. Never say or imply the wait is over when it isn't. When
       re-arming, also offer to close the superseded fired entry
       (`"$CUEBIRD" complete '<old-id>'` — it did its job: it brought you
       back) so the journal doesn't accumulate stale accepted entries.

5. Close the loop:
   - If the checkpoint is now passed/irrelevant, offer
     `"$CUEBIRD" complete '<id>'` and wait for the user's consent before
     running it — same non-negotiable consent rule as skills/remind's
     stale-awareness etiquette. If the entry already shows `status: "done"`
     (already reconciled from the phone), don't re-offer `complete` — there's
     nothing left to close.
   - If `complete` fails, use the exact same user-facing messages as
     skills/remind's Failure table for exits 10/12 — don't invent new
     wording. If it reports the id unexpectedly not found (exit 3 — the
     journal changed between your `get` and this `complete` call), say
     plainly you couldn't find that entry and re-run `"$CUEBIRD" list all`
     rather than guessing at another id.
   - If continuing the work implies a natural next checkpoint, offer the
     next reminder per skills/remind's etiquette (propose the one meaningful
     date, one line, wait for yes/no/defer, record whichever answer the
     user gives exactly as that skill's "Recording the user's answer"
     section specifies).

## If the entry has no resume_prompt (old/manual entry)

Be honest: «Контекст цього нагадування не зберігся — розкажи двома словами,
про що воно, і я підхоплю.» Then proceed from the `title`/`context` fields
alone.
