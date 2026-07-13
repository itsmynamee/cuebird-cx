---
name: remind
description: Set a phone reminder via Apple Reminders. Use PROACTIVELY when a concrete future deadline, checkpoint, waiting period, or "check back in N days/weeks" moment emerges in conversation — from the user's words OR from your own analysis and plans. Also when work enters a waiting period whose duration you can estimate (a condition with no stated date — estimate the timeframe from context). Also when the user explicitly asks to be reminded of something. Do not trigger for incidental/past dates with no action attached.
---

# Cuebird CX: remind

You create Apple Reminders that sync to the user's iPhone via iCloud and fire
there even when this Mac is off. Below, `$CUEBIRD` denotes the resolved
absolute path to the CLI — it is notation, not a shell variable: each bash
command you run is its own fresh shell, so substitute the literal path
directly into every command below (or, if you do assign a shell variable,
only rely on it within one single bash invocation, never across separate
tool calls).

Resolve `$CUEBIRD` using these methods, in order — never guess beyond them:
1. If your skill invocation provides a "Base directory for this skill" (or
   equivalent), use it directly:
   `CUEBIRD=<that-base>/../../scripts/cuebird-cx.sh`
2. Otherwise, if the environment variable `PLUGIN_ROOT` is set in your Bash
   environment, use `"$PLUGIN_ROOT/scripts/cuebird-cx.sh"`.
3. If neither is available, stop and tell the user Cuebird CX must be reinstalled;
   do not guess an internal Codex installation path.

## When to offer (etiquette — non-negotiable)

- Trigger on concrete, future, actionable dates/checkpoints from EITHER side
  of the conversation: the user's words ("здати до 26-го") or your own
  conclusions ("раніше кінця липня перевіряти немає сенсу" → offer a reminder
  for the decision point). Never for incidental dates ("у 2024 цей API
  змінився").
- **Condition-based waits** (no stated date): trigger when a genuine project
  checkpoint hides behind a condition rather than a date — "почекати, поки
  набереться 10 відвідувачів" has no timeframe, but it's still a real
  checkpoint. Estimate the realistic timeframe yourself from whatever the
  conversation actually gives you — current traffic/cadence, external SLAs,
  historical rate, anything on the table — and offer with the estimate
  stated honestly as an estimate AND the concrete date it maps to, e.g. «За
  моєю оцінкою, з поточним трафіком це десь 1–2 тижні. Поставити нагадування
  на 26 липня — перевірити відвідуваність?». This reminder is a check-in, not
  a deadline: the title says what to check («перевірити відвідуваність»),
  the body's `Критерій` line carries the threshold condition itself («10+
  унікальних відвідувачів»), and `Далі` says what happens next if the
  condition is met vs. still unmet. The `resume_prompt` must instruct
  future-you to verify the condition FIRST on resume and, if it's still
  unmet, re-arm for another estimated period — never assume the wait is over
  just because the date arrived. If you genuinely have zero signal to
  estimate from, don't invent a date — ask the user one short question
  instead (e.g. «Яка зараз приблизно відвідуваність на день, щоб оцінити
  термін?») and offer the reminder once they answer.
- Offer ONCE per distinct deadline, at a natural pause — never interrupt the
  primary task mid-flow. One short sentence, e.g.:
  «До речі — поставити нагадування на 24 липня перевірити GSC Coverage?
  Прийде на iPhone.»
- Propose the MEANINGFUL date — the decision point, not the mention date.
  "14+ днів від 10.07" → offer 24.07. Exactly one option; the user adjusts.
- Before offering, check for duplicates: run `$CUEBIRD list all '<project>'`
  (the project argument scopes the check to this project) and skip the offer
  if an entry with the same intent and date already exists (any status). If
  it exists as active, you may briefly confirm it's already set.
- Time of day: if the user gave none, use the default hour from
  `~/.codex/cuebird-cx/config.json` (`default_hour`, default 9 → 09:00). Read
  it with:
  ```bash
  default_hour=$(osascript -l JavaScript -e 'function run(a){try{var v=JSON.parse(a[0]).default_hour;return String(typeof v==="number"?v:9)}catch(e){return "9"}}' "$(cat ~/.codex/cuebird-cx/config.json 2>/dev/null || echo '{}')")
  ```
- For periodic needs ("перевіряти раз на кілька днів") do NOT create several
  reminders — one reminder at the earliest meaningful date. If the user wants
  true recurrence, tell them: open the just-created reminder in Apple
  Reminders and add a repeat there (one tap; this adapter does not set
  recurrence).
- **Stale awareness**: if the conversation reveals a tracked reminder became
  irrelevant or already happened («гейт ми вже пройшли», «реліз скасували»),
  offer once to close it. First find its id — run `$CUEBIRD list all
  '<project>'` and match the entry by title/intent to read its `id` field —
  then, only after the user agrees: `$CUEBIRD complete <id>` (it already
  happened) or `$CUEBIRD cancel <id>` (it never will). Offer — never close
  anything without consent. If the id turns out stale (the command reports
  the entry as not found), re-run `list all` to get the current id rather
  than guessing.

## Recording the user's answer — every answer, always

- **Yes** → create (below).
- **No** → run the command, then move on with no extra ceremony — the
  user's "no" already closes the topic, it needs no separate confirmation:
  `CUEBIRD_PROJECT='<project>' $CUEBIRD log declined '<title>' '<YYYY-MM-DDTHH:MM>'`
  Never re-offer this deadline; it stays reversible via the reminders skill.
- **"Not now / ask closer to the date"** → agree on a re-offer date, run the
  command below, then acknowledge in one short sentence (their language),
  e.g. «Гаразд, нагадаю ближче до дати.»:
  `CUEBIRD_PROJECT='<project>' CUEBIRD_REOFFER_AT='<YYYY-MM-DDTHH:MM>' $CUEBIRD log deferred '<title>' '<due>'`
- Declining one deadline NEVER mutes other or future deadlines.
- If a `log` command itself fails (non-zero exit, no id printed), that's a
  local bookkeeping failure only — nothing was promised in Reminders — so
  just tell the user plainly the note didn't save and continue the
  conversation. The Failure table below is about `add`/`complete`/`cancel`,
  not `log`.

## Creating

### Shell safety (read before running any command below)

Every value you interpolate into these commands — title, body, resume
prompt, project name — is free text: the user's own words, or text you
composed from them. Double-quoted shell strings still expand backticks,
`$(...)`, and `$VAR` inside them, so free text containing any of those is
command-substituted or executed. That is a shell-injection risk, not a
theoretical one.

**ALWAYS wrap user-derived/composed values in SINGLE quotes. Escape any
embedded single quote as `'\''`. NEVER use double quotes around interpolated
text.**

Example: a title of `It's done` becomes `'It'\''s done'` (close the quote,
escaped literal `'`, reopen the quote).

Compose:
- **title** — the user's own words, short, their language, no prefixes.
- **body** — the fixed template (their language), plain words a person who
  forgot everything will understand:
  ```
  Що: <what to do, one line>
  Проєкт: <name> — <one-line human description> (<path>)
  Критерій: <how to tell it's done/passed>
  Далі: <what happens after, one line>

  ▶ Відкрий Codex у проєкті й скажи: «нагадування: <short key>»

  — Cuebird CX
  ```
- **resume_prompt** — a SELF-CONTAINED continuation prompt for a future
  session with zero context: project path, state of things right now, what
  exactly to check and how, planned next steps. Write it as instructions to
  a future you.

Then run as ONE bash invocation exactly as shown (env vars carry the long
fields safely — don't split this across separate tool calls):
```bash
CUEBIRD_BODY='<body — single-quoted, embedded '\'' escaped>' \
CUEBIRD_PROJECT='<project name>' \
CUEBIRD_PROJECT_PATH='<absolute path>' \
CUEBIRD_CONTEXT='<one-line context>' \
CUEBIRD_RESUME_PROMPT='<resume prompt — single-quoted, embedded '\'' escaped>' \
"$CUEBIRD" add '<YYYY-MM-DDTHH:MM>' '<title>'
```
Success prints `{"ok":true,...}` (exit 0). Confirm in ONE line:
«✓ Нагадування: «<title>» — <людська дата>. З'явиться на всіх твоїх
Apple-пристроях.»
Any non-zero exit → see Failure table below; don't say the line above.

**First use only** (no `~/.codex/cuebird-cx/journal.jsonl` yet, or it's
empty): run `"$CUEBIRD" health` first, before composing anything else.
- Exit 0, prints `ok …` → proceed straight to creating.
- Exit 0, prints `ok-local …` → this is the `ok-local` row in the Failure
  table below: warn and ask before proceeding. If the user says yes, continue
  to create anyway (it will just stay Mac-only); if no, stop — don't create
  anything.
- Non-zero exit (10 or 12 — `health` never returns 11; that code is
  `add`-specific) → the SAME Failure table below applies to `health`'s own
  exit code exactly as it would to `add`'s. Don't attempt to create anything
  until the user has acted on the fix.

After the first successful create, add one extra sentence: «Керувати
нагадуваннями можна у застосунку Нагадування — список 'Codex Projects'.»

## Failures — exact user-facing messages (never show raw errors)

| Signal | Say (user's language, this content) |
|---|---|
| exit 10 (from `add`, `health`, `complete`, or `cancel`) | «macOS заборонив доступ до Нагадувань. Увімкни: System Settings → Privacy & Security → Automation → (Codex або твій термінал) → Reminders — і повтори.» |
| `health` → `ok-local` | «Нагадування створиться лише на цьому Mac — iPhone його не побачить. Увімкни Reminders в iCloud (System Settings → Apple ID → iCloud). Створити локально все одно?» |
| exit 11 (from `add`) | «Не зміг підтвердити створення — перевір список Codex Projects у Нагадуваннях. Запусти Cuebird CX doctor, якщо повториться.» (the reminder may or may not actually exist — that's exactly why this points at the list instead of asserting failure either way) |
| exit 12 | Look at stderr first, for the substrings `journal write failed` or `reminder created:`. If either appears, the Reminders-side action already succeeded (a reminder was created by `add`, or its state was changed by `complete`/`cancel`) and only the local tracking write failed — say so honestly, e.g. «Нагадування створено, але я не зберіг запис локально — перевір список Codex Projects; спробую дозаписати пізніше.» Never call this an outright failure when either substring is present. If neither substring appears, it's a genuine failure: «Щось пішло не так із застосунком Нагадування. Запусти Cuebird CX doctor.» |
| exit 2 (past date, calendar-invalid date like Feb 30, empty title) | Composition error on your side, never the user's — fix and retry silently, don't surface raw text. For an impossible date, stderr names the normalized date it tried (e.g. "did you mean 2026-03-02T09:00?"); use that, or otherwise recompute a valid future date yourself, and retry. Ask the user only if their intent was genuinely ambiguous. |
