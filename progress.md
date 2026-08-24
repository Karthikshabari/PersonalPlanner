# Progress Log

Last updated: 2026-08-24 — Chunk 2 complete; 76/76 tests pass, analyze clean

## Status Legend
- 🔲 Not started
- 🟨 In progress
- ✅ Done
- ⚠️ Done with deviations — see notes

## Chunks

Chunks are strictly sequential — each depends on the one before it. Do not start a
chunk until the previous one is ✅ (or ⚠️ with deviations noted and accepted).

| # | Chunk | Depends on | Status | Notes |
|---|---|---|---|---|
| 1 | Foundation + Day View | — | ⚠️ | All features implemented & verified via automated tests; Linux desktop build + live launch verified; Android launch still pending (see Deviations #1) |
| 2 | Drag, Resize, Undo, Conflict Detection | 1 | ✅ | All features implemented & verified via automated tests (14 interaction tests + unit suites); see Chunk 2 verification record |
| 3 | Inbox, Categories, Tags, Subtasks | 2 | 🔲 | |
| 4 | Recurring Tasks + Task Templates | 3 | 🔲 | |
| 5 | Reviews + Week View | 4 | 🔲 | |
| 6 | Timer + Daily Review Reminder | 5 | 🔲 | |
| 7 | Analytics | 6 | 🔲 | |
| 8 | Supabase Sync | 7 | 🔲 | |
| 9 | Keyboard Shortcuts + Platform Polish | 8 | 🔲 | |
| 10 | Polish, Performance, Testing | 9 | 🔲 | |

## Deviations From Plan

1. **(Chunk 1) Android launch not verified yet.** Linux desktop is now fully verified
   (2026-08-21): `flutter build linux --debug` succeeds and the built binary was
   launched on the real display for 12s with no errors (clean exit via timeout;
   only Impeller/VM-service logs). Android remains open: installing the Android SDK
   requires writing outside this project folder, which is currently out of bounds.
   When allowed: install cmdline-tools + SDK user-level (~1–1.5GB), accept licenses,
   then `flutter build apk --debug`; with a USB device attached, `flutter run`.
   Flutter SDK itself was installed user-level at `~/development/flutter` (PATH added
   to `~/.bashrc`), version 3.47.1 stable.
2. **(Chunk 1) `getTaskById` returns soft-deleted rows.** Deliberate: undo (Chunk 2)
   and sync (Chunk 8) need access to soft-deleted records. Day queries filter
   `deleted_at IS NULL` as specified.
3. **(Chunk 1) Task editor uses an explicit Save button** (planner allowed choosing
   between auto-save debounce and explicit save).
4. **(Chunk 2) Overlap blocks render with square corners.** Flutter forbids
   `borderRadius` on a non-uniform `Border` (paint crash), so "Keep Overlap"
   blocks (category-color left edge + amber outline) drop the 8px corner
   radius; stripes + warning icon still mark them.
5. **(Chunk 2) Compact task blocks hide the badge row.** Blocks shorter than
   ~38px of content height (15-min grid slots, live shrink-resize) render the
   title only — a RenderFlex overflow otherwise. Badge/duration return at ≥1
   grid slot of height.
6. **(Chunk 2) Test bug fixed: infinite recursion in `finish()`**
   (`timeline_interactions_test.dart`) called itself, producing an endless async
   microtask chain — this was the cause of the multi-GB RAM runaway during
   verification. Fixed to pump one final frame. If a future run ever grows past
   ~1–2 GB again, treat as runaway and use
   `systemd-run --user --scope -p MemoryMax=4G flutter test` while diagnosing;
   the normal suite completes in ~8s well under that.

## Open Issues / Follow-ups

1. **(Chunk 1)** Android launch verification (see Deviation #1). Desktop is done.
2. **(Chunk 1)** ~~Overlapping blocks render stacked at full width~~ RESOLVED in
   Chunk 2: conflict detection, resolution dialog, overlap offset + indicator
   implemented.
3. **(Chunk 1) Test-infra note:** calling Drift `close()` inside widget tests
   (FakeAsync zone) deadlocks while stream queries are active, and disposing the
   Riverpod container leaves a pending zero-duration Drift timer that fails the
   test. Widget tests therefore use throwaway in-memory DBs and skip close/dispose
   (`teardownApp` helper). Unit/file-based tests close explicitly in the real async
   zone where it works (and must call `setupSqliteForTests()` — see Chunk 2).
   Keep this pattern for future chunks' widget tests.
4. **(Chunk 1) RESOLVED (2026-08-21):** `libsqlite3-dev` installed, so
   `libsqlite3.so` now exists; the loader override in
   `test/helpers/sqlite_setup.dart` resolves on its first attempt now. Kept as a
   harmless fallback for machines without the dev package.

## Final Verification

(Fill this in only once all 10 chunks above are ✅. Go through every item in every
chunk's Verification Checklist in planner.md and record pass/fail against the
*current* code — later chunks can silently break earlier ones, so re-check each
item rather than trusting old checkmarks from when a chunk first shipped.)

### Chunk 1 verification record (2026-08-21)

`flutter analyze`: No issues found. `flutter test`: 19/19 pass (3 consecutive runs).

| Checklist item | Result | Method |
|---|---|---|
| App launches without errors on desktop AND Android | ⚠️ partial | Desktop: ✅ `flutter build linux --debug` succeeds; binary launched on real display 12s, no errors (2026-08-21). Android: pending SDK install (out-of-folder write) — full app does boot headlessly in widget tests |
| Timeline shows 24 hours with grid lines | ✅ | Widget test: all 24 hour labels + per-row divider lines |
| Current time red line visible and accurate | ✅ | Widget test: indicator rendered on today; position = minutes-since-midnight × px/min; refreshes every 15s |
| Create task via double-tap quick create | ✅ | Widget test: double-tap empty slot → inline field → Enter → task persisted (start=slot, end=+60min, planned, not inbox) |
| Block renders title, category border, status badge, duration | ✅ | Widget tests: truncated title, exact #4285F4 left border for Work, "Planned" badge, "1h" duration label |
| Tap task opens editor panel | ✅ | Widget test: desktop side panel opens ("Edit Task") |
| Edit fields and save | ✅ | Widget test: title + notes edited, saved, re-read from DB |
| Status cycles Planned → In Progress → Completed | ✅ | Widget test: badge taps cycle UI + DB value |
| Navigate days ← → Today | ✅ | Widget test: header date changes for prev/next/today ("MMM d, yyyy") |
| 4 default categories exist | ✅ | Unit test + categories screen test (names + hex colors; seeding idempotent) |
| Data persists across restarts (SQLite) | ✅ | Unit test: write → close → reopen same file → task + categories intact |
| Dark theme applied by default | ✅ | Widget test: brightness dark + background #121212 |
| Adaptive layout (rail / bottom nav) | ✅ | Widget tests at 1400px and 600px; navigation between destinations |
| Timeline auto-scrolls to current time on launch | ✅ | Widget test: initial offset equals anchor math (now −90min) clamped to real maxScrollExtent |

### Chunk 2 verification record (2026-08-24)

`flutter analyze`: No issues found. `flutter test`: 76/76 pass (run under
`systemd-run --user --scope -p MemoryMax=4G`; completes in ~8s, memory bounded —
the earlier multi-GB growth was the `finish()` recursion bug, now fixed, see
Deviations #6).

| Checklist item | Result | Method |
|---|---|---|
| Drag a task block to a new slot (snaps to grid) | ✅ | Widget test: mouse drag −64px → start 07:00, end 08:00 (60-min grid) |
| Ghost preview shows during drag | ✅ | Widget test: `GhostPreview` present mid-drag; original block dimmed via Opacity 0.35 (subtree stays mounted so the gesture survives) |
| Resize by dragging bottom edge | ✅ | Widget test: handle +64px → duration 2h, start unchanged |
| Minimum duration enforced (1 grid slot) | ✅ | Widget test: drag handle −300px → still 1h |
| Conflict detection on overlapping drop | ✅ | Widget test: dialog appears when drop overlaps Beta |
| Resolution dialog with 4 options | ✅ | All four actions exercised across tests: cancel / shift-all / shift-overlapping / keep-overlap |
| "Shift All Following" moves subsequent blocks | ✅ | Widget test: B shifts into A's vacated+overlap slot; C shifts across its gap (+60min each) |
| "Shift Only Overlapping" adjusts only conflicting blocks | ✅ | Widget test: B shifts by own overlap; untouched C stays put |
| "Keep Overlap" renders indicator | ✅ | Widget test: both blocks flagged `hasOverlap` after resolve; paint crash (non-uniform border + radius) fixed |
| Undo works (Ctrl+Z) | ✅ | Widget test: move reverts to 08:00; toast "Undo: Move …" |
| Redo works (Ctrl+Shift+Z) | ✅ | Widget test: move reapplied to 07:00; toast "Redo: Move …" |
| Can duplicate a task | ✅ | Widget test: D key copies into next free slot (10:00), same duration; toast shown |
| Delete with confirmation | ✅ | Widget test: Delete key → dialog → soft-deleted (`deleted_at` set via raw `getTaskById`, which intentionally sees deleted rows); Ctrl+Z restores |
| Context menu on right-click / long-press | ✅ | Widget tests: Edit/Duplicate/Delete/Change Status submenu (desktop right-click); Android long-press variant |
| Grid interval changeable in settings (15/30/60) | ✅ | Unit tests: default 60, loads stored 15, upsert writes, out-of-range falls back to 60. Widget test: dropdown → 15 min → quick-create makes a 15-min block |

Bugs found & fixed during verification:
- `finish()` infinite recursion (test infra) — root cause of RAM runaway.
- Overlap border paint crash (`task_block_widget.dart`): non-uniform Border +
  borderRadius → removed radius for overlap blocks.
- RenderFlex overflow (~19–39px) in short blocks → compact mode below ~38px.
- `grid_settings_test.dart` missed `setupSqliteForTests()` → libsqlite3 load failure.
- Test finders: 'Undo' matched task title "Undoable" → tightened to 'Undo:'/'Redo:'.
