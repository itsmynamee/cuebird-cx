# Changelog

## [0.2.1] — 2026-07-13

- Renamed the repository, marketplace, plugin id, package directory, and CLI
  consistently to `cuebird-cx`.
- Added one-time migration from `~/.codex/cuebird/` to
  `~/.codex/cuebird-cx/` so existing reminder context is preserved.
- Fixed invalid YAML quoting in the `resume` skill metadata.

## [0.2.0] — 2026-07-13

Initial Codex release.

- Four focused skills: reminder creation, journal management, context resume,
  and end-to-end diagnostics.
- Trusted `SessionStart` hook for proactive checkpoint detection and deferred
  reminder offers.
- Verified Apple Reminders adapter with iCloud account detection and read-back.
- Append-only local decision journal with concurrency-safe writes and
  corruption-tolerant reads.
- Strict rejection of past and calendar-invalid dates before external writes.
- Native Codex plugin manifest and marketplace packaging.
- Real-device release gate verified from Codex through iCloud to iPhone and
  back through completion and deletion.
