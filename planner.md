# Personal Planner — Implementation Planner

> **Purpose**: This file contains **all implementation instructions** broken into chunks. Each chunk is a self-contained unit of related work. There are no timelines — the agent works through chunks sequentially until complete.
>
> **How to use**: Tell the agent which chunk to work on (e.g., "Work on Chunk 1"). The agent should read `architecture.md` for full context, follow the instructions here, and update `progress.md` after completing each chunk.

---

## Chunk Overview

| Chunk | Name | Dependencies | Status |
|---|---|---|---|
| 1 | Foundation + Day View | None | 🔲 Not Started |
| 2 | Drag, Resize, Undo, Conflict Detection | Chunk 1 | 🔲 Not Started |
| 3 | Inbox, Categories, Tags, Subtasks | Chunk 2 | 🔲 Not Started |
| 4 | Recurring Tasks + Task Templates | Chunk 3 | 🔲 Not Started |
| 5 | Reviews + Week View | Chunk 4 | 🔲 Not Started |
| 6 | Timer + Daily Review Reminder | Chunk 5 | 🔲 Not Started |
| 7 | Analytics | Chunk 6 | 🔲 Not Started |
| 8 | Supabase Sync | Chunk 7 | 🔲 Not Started |
| 9 | Keyboard Shortcuts + Platform Polish | Chunk 8 | 🔲 Not Started |
| 10 | Polish, Performance, Testing | Chunk 9 | 🔲 Not Started |

---

## Chunk 1: Foundation + Day View

**Goal**: A working Flutter app where you can open the app, see today's timeline, create tasks, edit them, change statuses, and navigate between days. All data persisted in SQLite.

### Instructions

1. **Flutter project init**
   - Run `flutter create personal_planner` with the org `com.personalplanner`
   - Set up the folder structure as defined in `architecture.md` Section 5

2. **Dependencies setup** — Add to `pubspec.yaml`:
   - `drift`, `drift_dev`, `sqlite3_flutter_libs`, `sqlite3` (for desktop)
   - `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`
   - `freezed`, `freezed_annotation`, `json_annotation`, `json_serializable`
   - `build_runner`
   - `go_router`
   - `uuid`
   - `intl`
   - `path_provider`
   - Configure `build.yaml` for Drift + Freezed code generation

3. **Drift database** — Define tables for this chunk:
   - `tasks` table (full schema from `architecture.md` Section 3, including `sync_status` and `revision` columns even though sync isn't active yet)
   - `categories` table (full schema including `is_focus`)
   - `app_settings` table
   - Set up migration framework (v1)
   - Create DAOs: `TaskDao`, `CategoryDao`

4. **Domain models** — Create Freezed models:
   - `Task` model with all fields
   - `Category` model with all fields
   - Enums: `TaskStatus` (planned, inProgress, completed, skipped, cancelled, rescheduled), `Priority` (none, low, medium, high, urgent), `SyncStatus` (synced, pending, conflict)

5. **Core providers** — Set up Riverpod providers:
   - `appDatabaseProvider` (singleton)
   - `taskRepositoryProvider`
   - `categoryRepositoryProvider`
   - `selectedDateProvider` (StateProvider<DateTime>)

6. **TaskRepository** — Implement:
   - `insertTask(task)` — Insert a new task
   - `updateTask(task)` — Update existing task
   - `deleteTask(taskId)` — Soft delete (set `deleted_at`)
   - `watchTasksForDay(date)` — Stream query: all tasks for a given date where `deleted_at IS NULL` and `is_inbox = 0`
   - `getTaskById(taskId)` — Single fetch

7. **CategoryRepository** — Implement:
   - CRUD operations
   - `watchAllCategories()` — Stream query for all active categories

8. **Dark theme** — Implement:
   - `AppTheme` class with `darkTheme` and `lightTheme` static getters
   - `AppColors` — Define color palette (primary: #7C5CFC, background dark: #121212, surface dark: #1E1E1E, etc.)
   - `AppTypography` — TextStyles using Inter font (or system sans-serif)
   - `AppSpacing` — Spacing scale constants (4, 8, 12, 16, 20, 24, 32, 48)
   - Dark mode is the default

9. **GoRouter setup** — Configure routes:
   - `/day` — Day View screen (default/home route)
   - `/settings` — Settings screen
   - `/categories` — Categories management screen

10. **Day View screen** — Implement:
    - Scrollable `TimelineWidget` with hour grid lines (00:00–23:59)
    - Each hour row has a label on the left and a horizontal line
    - `CurrentTimeIndicator` — A red horizontal line showing the current time, updates every minute
    - Tasks from `watchTasksForDay(selectedDate)` rendered as colored blocks at their scheduled positions

11. **Task block rendering** — `TaskBlockWidget`:
    - Title text (truncated if too long)
    - Left border colored by category color
    - Status badge (small chip showing status)
    - Duration label (e.g., "1h", "2h 30m")
    - Tap to select (highlight border)

12. **Quick create** — On double-tap of an empty timeline slot:
    - Show an inline text field at that position
    - User types title, presses Enter
    - Task created with: `start_time` = tapped slot, `end_time` = +1 grid slot (60 min default), `status` = planned, `is_inbox` = 0

13. **Task editor panel** — Side panel (desktop) / bottom sheet (mobile):
    - Fields: title, description, category picker (dropdown of categories), priority selector, status selector, time range (start/end time pickers), estimated duration (minutes), notes (multiline text)
    - Save button to persist changes
    - Auto-save on field change (debounced 500ms) OR explicit save button — choose one approach

14. **Status cycling** — Tap the status badge on a task block:
    - Cycles through: Planned → In Progress → Completed
    - Visual feedback: color change on the status badge

15. **Date navigation** — In the header:
    - `←` button → previous day
    - `→` button → next day
    - "Today" button → jump to today
    - Display current date: "Jul 23, 2026" format

16. **Adaptive layout** — `AdaptiveLayout` widget:
    - Desktop (width ≥ 900px): Navigation rail (left) + timeline (center) + optional task editor panel (right)
    - Mobile (width < 900px): Single column with bottom navigation bar

17. **Scroll to now** — On app launch:
    - Auto-scroll the timeline so the current hour is visible (centered or near the top of the visible area)

18. **Seed data** — On first launch, pre-create 4 default categories:
    - Work (#4285F4, blue)
    - Personal (#34A853, green)
    - Health (#EA4335, red)
    - Learning (#FBBC04, yellow)

### Verification Checklist
- [ ] App launches without errors on desktop AND Android
- [ ] Timeline shows 24 hours with grid lines
- [ ] Current time red line is visible and accurate
- [ ] Can create a task via double-tap quick create
- [ ] Task block renders with title, category color border, status badge, duration
- [ ] Can tap a task to open the editor panel
- [ ] Can edit task fields and save
- [ ] Status cycles on tap: Planned → In Progress → Completed
- [ ] Can navigate between days using ← → and Today button
- [ ] 4 default categories exist
- [ ] Data persists across app restarts (SQLite)
- [ ] Dark theme is applied by default
- [ ] Adaptive layout works (nav rail on desktop, bottom nav on mobile)
- [ ] Timeline auto-scrolls to current time on launch

---

## Chunk 2: Drag, Resize, Undo, Conflict Detection

**Goal**: Fully interactive timeline. Drag to move, resize to change duration, conflicts detected and resolved, full undo/redo.

### Instructions

1. **Snap-to-grid utility**
   - Implement `snapToGrid(DateTime dateTime, int gridMinutes)` as described in `architecture.md` Section 8
   - Store grid interval in `app_settings` table (key: `grid_interval_minutes`, default: `60`)
   - Support values: 15, 30, 60

2. **Grid settings UI**
   - Add grid interval selector to Settings screen (dropdown or radio buttons: 15 / 30 / 60 min)
   - Changing this setting should immediately update the timeline rendering

3. **Draggable task blocks**
   - Desktop: click + drag to move a task block up/down on the timeline
   - Mobile: long-press + drag
   - `DraggableTaskBlock` wrapper widget that handles gesture detection
   - On drop: snap to nearest grid boundary, update `start_time` and `end_time`

4. **Ghost preview**
   - During drag, show a translucent preview of the task block at the current drop position
   - The original block should remain visible in its original position (dimmed)

5. **Resizable task blocks**
   - Bottom-edge drag handle (`ResizableHandle` widget)
   - Drag the bottom edge down to extend duration, up to shrink
   - Minimum duration = 1 grid slot
   - On release: snap to grid, update `end_time`

6. **Conflict detector** — Implement `ConflictDetector`:
   - Method: `detect(Task task, List<Task> dayTasks) → List<Task>`
   - Algorithm: as described in `architecture.md` Section 8 (interval overlap check)
   - Skip self, skip cancelled/rescheduled tasks

7. **Conflict resolution dialog** — Modal dialog with 4 options:
   - "Shift All Following" — shift all subsequent blocks forward
   - "Shift Only Overlapping" — shift only the conflicting blocks (cascade up to depth 10)
   - "Keep Overlap" — allow overlap, mark with visual indicator
   - "Cancel" — discard the operation

8. **Shift All Following** — Implement:
   - Compute `overlapDuration = droppedTask.endTime - firstConflict.startTime`
   - Shift all tasks with `startTime >= firstConflict.startTime` (excluding the dropped task) forward by `overlapDuration`
   - Wrap all shifts into a `BatchCommand`

9. **Shift Only Overlapping** — Implement:
   - For each conflicting task, compute individual overlap and shift forward
   - Re-check for new conflicts after each shift (cascade)
   - Max cascade depth = 10, then fall back to "keep overlap"

10. **Keep Overlap** — Implement:
    - Set a runtime flag `hasOverlap = true` on both blocks (not persisted)
    - Render overlapping blocks with a striped/dashed border and slight horizontal offset

11. **Command pattern** — Implement all commands as described in `architecture.md` Section 8:
    - `SchedulingCommand` abstract class with `execute()` and `undo()`
    - `CreateTaskCommand` — execute: INSERT, undo: DELETE
    - `MoveTaskCommand` — stores old/new start/end, execute: UPDATE to new, undo: UPDATE to old
    - `ResizeTaskCommand` — stores old/new end_time
    - `DeleteTaskCommand` — stores snapshot, execute: soft-delete, undo: restore
    - `BatchCommand` — holds List<SchedulingCommand>, execute: run all, undo: run all undo() in REVERSE

12. **CommandHistory** — Implement undo/redo stack:
    - Max 50 items in undo stack
    - New commands clear the redo stack
    - Expose `canUndo`, `canRedo` booleans
    - `undoStackProvider` (Riverpod Notifier)

13. **Undo/Redo** — Wire up:
    - Desktop: `Ctrl+Z` for undo, `Ctrl+Shift+Z` for redo
    - Visual feedback: brief toast showing what was undone/redone

14. **Duplicate task** — `D` key or context menu:
    - Create a copy of the selected task at the next available slot after the original
    - Copy all fields except: new ID, new `created_at`/`updated_at`

15. **Delete task** — `Delete` key → confirmation dialog → soft delete:
    - Set `deleted_at = NOW()`
    - Task disappears from timeline
    - Wrapped in `DeleteTaskCommand` for undo support

16. **Context menu** — Right-click (desktop) / long-press menu (mobile):
    - Edit, Duplicate, Delete, Change Status (submenu)

### Verification Checklist
- [ ] Can drag a task block to a new time slot (snaps to grid)
- [ ] Ghost preview shows during drag
- [ ] Can resize a task block by dragging bottom edge
- [ ] Minimum duration enforced (1 grid slot)
- [ ] Conflict detection works when blocks overlap
- [ ] Conflict resolution dialog appears with 4 options
- [ ] "Shift All Following" correctly moves subsequent blocks
- [ ] "Shift Only Overlapping" correctly adjusts only conflicting blocks
- [ ] "Keep Overlap" renders overlapping blocks with visual indicator
- [ ] Undo works (Ctrl+Z) — reverts last operation
- [ ] Redo works (Ctrl+Shift+Z)
- [ ] Can duplicate a task
- [ ] Can delete a task with confirmation
- [ ] Context menu appears on right-click/long-press
- [ ] Grid interval can be changed in settings (15/30/60 min)

---

## Chunk 3: Inbox, Categories, Tags, Subtasks

**Goal**: Tasks have subtasks, categories with colors, tags. Inbox captures ideas. Overdue tasks auto-surface in inbox for rescheduling.

### Instructions

1. **Drift migration v2** — Add tables:
   - `subtasks` (full schema from `architecture.md`)
   - `tags` (full schema)
   - `task_tags` (join table)
   - Create DAOs: `SubtaskDao`, `TagDao`

2. **Subtask model** — Freezed `Subtask`:
   - Fields: id, taskId, title, isCompleted, sortOrder, createdAt, updatedAt

3. **SubtaskRepository** — Implement:
   - `insertSubtask(subtask)`, `updateSubtask(subtask)`, `deleteSubtask(id)`
   - `watchSubtasksForTask(taskId)` — Stream query ordered by sortOrder
   - `toggleSubtask(id)` — Toggle `isCompleted`
   - `reorderSubtasks(taskId, List<String> orderedIds)` — Update sortOrder for all subtasks of a task

4. **Subtask editor widget** — In task editor panel:
   - List of subtasks with checkboxes
   - Text field at bottom: type title, press Enter to add new subtask
   - Drag handles to reorder subtasks
   - Swipe or X button to delete a subtask

5. **Subtask display on task block** — Show completion count on the block:
   - e.g., "2/4" in small text at the bottom-right of the block
   - Only shown if the task has subtasks

6. **Categories CRUD UI** — Settings → Categories screen:
   - List of all categories with color dots
   - Create: name + color picker (predefined palette or custom hex)
   - Edit: name and color
   - Delete: confirmation dialog (what happens to tasks in this category? → set to null)
   - Reorder: drag to reorder
   - Toggle `is_focus` flag per category

7. **Category color on blocks** — Task block left border uses the category's `color_hex`

8. **Tags CRUD** — Implement:
   - `Tag` Freezed model
   - `TagRepository` with CRUD + `watchAllTags()`
   - Create tags inline from the task editor (type new tag name, press Enter)
   - Manage tags in settings

9. **Tag picker widget** — In task editor:
   - Multi-select chip selector
   - Show existing tags as chips, tap to toggle
   - Type to filter/create new tag

10. **Inbox — Database support**
    - Tasks with `is_inbox = 1` and `start_time = NULL`, `end_time = NULL`
    - `InboxRepository`:
      - `watchInboxItems()` — Stream: explicit inbox items (`is_inbox = 1`) UNION overdue tasks (`DATE(start_time) < today AND status IN ('planned', 'in_progress') AND is_inbox = 0`)
      - `addToInbox(title)` — Create task with `is_inbox = 1`, `start_time = NULL`

11. **Inbox sidebar (desktop)** — Collapsible bottom strip:
    - Shows all inbox items + overdue tasks
    - Each item shows title and optional overdue badge
    - "+" button or `I` shortcut to quick-add

12. **Inbox tab (mobile)** — Dedicated bottom nav tab:
    - Full-screen list of inbox items
    - Quick-add at top

13. **Inbox quick-add** — Text field:
    - Type title, press Enter → inbox item created
    - Keyboard shortcut: `I` (desktop)

14. **Overdue detection** — Query-time detection:
    - When inbox is queried, include tasks where `DATE(start_time) < today AND status IN ('planned', 'in_progress') AND deleted_at IS NULL AND is_inbox = 0`
    - First time detected: stamp `missed_at` with current datetime (format: `YYYY-MM-DDTHH:mm`)

15. **Overdue badge** — On inbox items that are overdue:
    - Amber badge showing original date: "Jul 21"
    - If `missed_at` is set, show "Missed Jul 21 14:00"

16. **Drag inbox → timeline** — Drag an inbox item onto the timeline:
    - Update: `is_inbox = 0`, set `start_time`/`end_time` based on drop position
    - Item disappears from inbox, appears on timeline

17. **Reschedule from inbox** — Drag an overdue item to the timeline:
    - Original task: `status → rescheduled`, `rescheduled_to_id → new task's ID`
    - New task created at drop time with `rescheduled_from_id → original task's ID`
    - Original task remains visible on its original date's calendar as "Rescheduled"

### Verification Checklist
- [ ] Can add subtasks to a task in the editor
- [ ] Subtask checkboxes toggle completion
- [ ] Subtask count shows on task block ("2/4")
- [ ] Can drag to reorder subtasks
- [ ] Categories CRUD works (create, edit, delete, reorder)
- [ ] Category colors appear as left border on task blocks
- [ ] Can create and assign tags to tasks
- [ ] Tag picker works with multi-select
- [ ] Inbox shows explicit inbox items
- [ ] Inbox shows overdue tasks with amber badge
- [ ] Can quick-add items to inbox
- [ ] Can drag inbox item to timeline (schedules it)
- [ ] Rescheduling overdue task creates linked copy
- [ ] Original rescheduled task shows "Rescheduled" status on its original date

---

## Chunk 4: Recurring Tasks + Task Templates

**Goal**: Set up recurring tasks that auto-populate. Save and reuse task templates.

### Instructions

1. **Drift migration v3** — Add tables:
   - `recurring_rules` (full schema from `architecture.md`)
   - `task_templates` (full schema)
   - Create DAOs: `RecurringRuleDao`, `TemplateDao`

2. **RRULE integration**
   - Add `rrule` package to dependencies
   - Create wrapper utility to parse and evaluate RFC 5545 recurrence rules

3. **RecurrenceService** — Implement:
   - `materializeForDate(DateTime date)`:
     1. Query all active recurring rules
     2. For each rule, evaluate RRULE to check if `date` is an occurrence
     3. Check exceptions_json — skip if date is in exceptions
     4. Check if a task with this `recurring_rule_id` already exists on this date — skip if yes
     5. Create new task from rule template (title, description, duration, category, priority, start_time = date + start_time_of_day)
   - Trigger on day-view load: materialize the viewed date
   - Trigger on app start: materialize today + tomorrow

4. **Recurring rules CRUD** — `RecurringRepository`:
   - Create, update, deactivate, delete rules
   - `watchActiveRules()` — Stream of all active rules

5. **Recurrence picker UI** — In task editor:
   - Dropdown: "Repeat: Never / Daily / Weekdays / Weekly / Monthly / Custom"
   - Selecting a preset generates the appropriate RRULE string
   - "Custom" opens a dialog for: frequency, interval, specific days, end date

6. **Custom recurrence dialog**
   - Frequency selector: Daily / Weekly / Monthly
   - Interval: every N days/weeks/months
   - Day selection: for weekly, which days (checkboxes for Mon-Sun)
   - End date: optional date picker (or "Never")
   - Preview: show human-readable description of the rule

7. **Edit single vs all** — When editing a task that has `recurring_rule_id`:
   - Show dialog: "This occurrence only" / "This and all future"
   - "This occurrence only" → edit the materialized task directly, rule unchanged
   - "This and all future" → update the recurring rule's template fields

8. **Delete single vs all** — When deleting a recurring task instance:
   - Show dialog: "This occurrence only" / "All future occurrences"
   - "This occurrence only" → soft-delete the task, add date to `exceptions_json`
   - "All future" → set `end_date` on the rule, deactivate if needed

9. **TaskTemplate model** — Freezed:
   - Fields: id, name, description, durationMin, categoryId, priority, tagsJson

10. **TemplateRepository** — CRUD + `watchAllTemplates()`

11. **Templates screen** — Settings → Task Templates:
    - List all saved templates
    - Create new template manually (fill in fields)
    - Edit/delete templates

12. **Create from template** — In quick-create or task editor:
    - Option to "Use template" (dropdown of saved templates)
    - Selecting a template pre-fills: title suffix (editable), description, duration, category, priority, tags

13. **Save as template** — In task editor:
    - "Save as template" button
    - Opens dialog to name the template
    - Creates template from current task's fields

14. **Recurring tasks indicator** — On task blocks generated from a recurring rule:
    - Small ↻ icon in the corner of the block

### Verification Checklist
- [ ] Can create a recurring rule (daily, weekdays, weekly, monthly, custom)
- [ ] Recurring tasks auto-materialize when viewing a date
- [ ] Recurring tasks appear on correct days according to RRULE
- [ ] Exception dates are respected (excluded tasks don't appear)
- [ ] "Edit this occurrence only" modifies just the one task
- [ ] "Edit all future" updates the rule template
- [ ] "Delete this occurrence" adds to exceptions, soft-deletes instance
- [ ] "Delete all future" sets end_date on rule
- [ ] Can create, edit, delete task templates
- [ ] "Use template" pre-fills task fields
- [ ] "Save as template" creates template from current task
- [ ] Recurring indicator ↻ shows on recurring task blocks
- [ ] Materialization doesn't create duplicates if instance already exists

---

## Chunk 5: Reviews + Week View

**Goal**: Complete planning and review cycle. Review each day and week. 7-day week overview.

### Instructions

1. **Drift migration v4** — Add tables:
   - `daily_reviews` (full schema)
   - `weekly_reviews` (full schema)
   - `daily_stats_cache` (full schema)
   - Create DAOs: `ReviewDao`, `StatsDao`

2. **DailyReview model** — Freezed:
   - Fields: id, date, reflection, energyLevel, productivityRating, planningAccuracyRating, winsJson, improvementsJson

3. **WeeklyReview model** — Freezed:
   - Fields: id, weekStartDate, reflection, overallRating, goalsMetJson, goalsMissedJson, nextWeekFocusJson

4. **ReviewRepository** — Implement:
   - CRUD for daily and weekly reviews
   - `watchReviewForDate(date)` — Stream
   - `watchWeeklyReviewForWeek(weekStartDate)` — Stream

5. **Daily Review screen** — Implement:
   - Date selector (defaults to today)
   - Read-only mini-timeline showing all blocks with final statuses for the selected date
   - Auto-computed stats section:
     - Completion rate: completed / (total - cancelled)
     - Planned hours: SUM(end_time - start_time)
     - Actual hours: SUM(actual_duration_min) / 60
     - Status breakdown: count per status
   - Review form:
     - Reflection (textarea)
     - Energy level (1-5 star/dot rating)
     - Productivity rating (1-5)
     - Planning accuracy rating (1-5)
     - Wins (list — add/remove items)
     - Improvements (list — add/remove items)
   - Save button

6. **Weekly Review screen** — Implement:
   - Week selector (defaults to current week, Mon-Sun)
   - Aggregate stats for the week (sum/average of daily stats)
   - Review form:
     - Reflection
     - Overall rating (1-5)
     - Goals met (list)
     - Goals missed (list)
     - Next week focus (list)
   - Save button

7. **Week View screen** — Implement:
   - 7-column grid, each column = one day (Mon to Sun)
   - Each column shows compact task blocks (title only, color-coded by category)
   - Column header: day name + date + completion count (e.g., "Mon 21 • 5/7")
   - Click a day column → navigate to that day's Day View
   - Current day column highlighted

8. **Week navigation**
   - `←` / `→` to navigate weeks
   - "This Week" button to jump to current week

9. **Daily stats cache** — Implement computation:
   - Compute and store aggregates in `daily_stats_cache` table
   - Trigger: when analytics screen opens OR when daily review is saved
   - Fields: total_tasks, completed, missed, skipped, cancelled, rescheduled, planned_duration, actual_duration, focus_duration

10. **Navigation updates**
    - Add "Review" destination to navigation rail / bottom nav
    - `W` shortcut: toggle between Day and Week view
    - `Ctrl+R` shortcut: open Daily Review for today

### Verification Checklist
- [ ] Daily Review screen shows read-only timeline for selected date
- [ ] Auto-computed stats are correct (completion rate, hours, breakdown)
- [ ] Can fill and save daily review (reflection, ratings, wins, improvements)
- [ ] Weekly Review screen shows aggregate stats
- [ ] Can fill and save weekly review
- [ ] Week View shows 7 days with compact task blocks
- [ ] Can click a day in Week View to navigate to Day View
- [ ] Week navigation (← → and This Week) works
- [ ] Daily stats cache is computed correctly
- [ ] `W` shortcut toggles between Day/Week view
- [ ] `Ctrl+R` opens Daily Review

---

## Chunk 6: Timer + Daily Review Reminder

**Goal**: Start/pause/stop timer on tasks. See actual vs planned duration. Daily review reminder notification.

### Instructions

1. **Drift migration v5** — Add table:
   - `timer_sessions` (full schema)
   - Create DAO: `TimerDao`

2. **TimerSession model** — Freezed:
   - Fields: id, taskId, startedAt, endedAt, durationSec

3. **TimerService** — Implement:
   - `start(taskId)` — Create new TimerSession with `startedAt = NOW()`, `endedAt = null`
   - `pause()` — Set `endedAt = NOW()`, compute `durationSec`
   - `resume(taskId)` — Create a NEW TimerSession (each start/stop is a separate session)
   - `stop()` — End current session, finalize duration
   - **Enforce single active timer globally** — Starting a timer on task B auto-pauses timer on task A
   - `getActiveTimer()` → TimerSession? (where `endedAt IS NULL`)

4. **TimerRepository** — Implement:
   - CRUD operations
   - `watchActiveTimer()` — Stream of the currently running timer session (if any)
   - `getSessionsForTask(taskId)` — List all sessions for a task
   - `getTotalDurationForTask(taskId)` — Sum of all session durations

5. **Actual duration computation**
   - `actual_duration_min = SUM(timer_sessions.duration_sec) / 60` for a task
   - Auto-update `task.actual_duration_min` when a timer session ends

6. **Manual duration editing**
   - `actual_duration_min` field in task editor is directly editable
   - Manual edit overrides the timer-computed value

7. **Timer UI on task block**
   - When timer is active for a block, show `⏱ 01:23:45` on the block itself
   - Timer ticks every second (use a periodic stream)

8. **Timer overlay (desktop)**
   - Small floating widget in the bottom-right corner
   - Shows: task title (truncated), elapsed time, Pause/Stop buttons
   - Always visible when a timer is running

9. **Timer controls (mobile)**
   - Integrated into the task editor bottom sheet
   - Start/Pause/Stop buttons
   - Show elapsed time

10. **Android foreground service**
    - Use `flutter_foreground_task` package
    - When timer is running and app is backgrounded, show persistent notification with elapsed time
    - Notification actions: Pause, Stop

11. **Auto-status change**
    - Starting a timer auto-sets task status to "In Progress" (if currently "Planned")

12. **Auto-status on stop**
    - Stopping a timer shows a dialog: "Mark as Completed?" with Yes/No
    - If Yes: set status to Completed
    - If No: leave status as In Progress

13. **Daily review reminder notification**
    - Add `flutter_local_notifications` package
    - Schedule a daily notification at a configurable time (default: 9 PM / 21:00)
    - Notification text: "Time to review your day! 📝"
    - Tapping the notification opens the Daily Review screen

14. **Notification settings** — Settings → Notifications:
    - Enable/disable review reminder toggle
    - Time picker to set reminder time
    - Store in `app_settings`

### Verification Checklist
- [ ] Can start a timer on a task
- [ ] Timer ticks and shows elapsed time on the task block
- [ ] Can pause and resume a timer (creates separate sessions)
- [ ] Can stop a timer
- [ ] Only one timer can run at a time (starting B pauses A)
- [ ] `actual_duration_min` is computed from timer sessions
- [ ] Can manually edit actual duration in task editor
- [ ] Timer overlay shows on desktop when timer is running
- [ ] Timer controls work on mobile
- [ ] Starting timer auto-sets status to "In Progress"
- [ ] Stopping timer prompts "Mark as Completed?"
- [ ] Android foreground service keeps timer running in background
- [ ] Daily review reminder notification fires at configured time
- [ ] Notification settings (enable/disable, time) work

---

## Chunk 7: Analytics

**Goal**: Full analytics dashboard with actionable insights on planning habits.

### Instructions

1. **Add fl_chart dependency** to `pubspec.yaml`

2. **AnalyticsService** — Implement computation for all 12 metrics as defined in `architecture.md` Section 10:
   - Completion rate, planned/actual duration, planning accuracy, focus hours, status breakdown, category distribution, planning consistency (streak), productivity trend, reschedule rate, average overrun, peak productive hours

3. **Analytics screen** — Dashboard layout:
   - Toggle at top: Daily / Weekly / Monthly
   - Grid of metric cards (responsive — 2 columns on desktop, 1 on mobile)

4. **Metric cards** — Implement each as a separate widget:
   - **Completion rate card** — Percentage + bar chart + comparison to previous period ("↑ 8% vs last week")
   - **Planned vs Actual card** — Grouped bar chart (planned hours vs actual hours)
   - **Focus hours card** — Daily total + weekly average + small bar chart
   - **Productivity trend chart** — Line chart: `productivity_rating` from reviews over 4 weeks
   - **Category breakdown** — Donut/pie chart: time distribution per category
   - **Consistency heatmap** — GitHub-style contribution grid: green squares for days with planned tasks
   - **Status breakdown** — Horizontal stacked bar or row of counts
   - **Reschedule rate** — Percentage card with trend arrow
   - **Average overrun** — "You typically overrun by X minutes" card
   - **Peak hours heatmap** — Hour-of-day × day-of-week matrix showing completion density

5. **Date range** — Date range picker at the top:
   - Default: last 7 days for daily, last 4 weeks for weekly, last 3 months for monthly
   - Custom range option

6. **Empty states** — For each card:
   - If less than 7 days of data: show "Not enough data yet — keep planning for X more days!" message

7. **Search screen** — Implement full-text search:
   - Search input with debounce (300ms)
   - Uses `tasks_fts` virtual table for search
   - Results show: task title, date, status, category color
   - Tap result → navigate to that task's day view and select the task

### Verification Checklist
- [ ] Analytics screen loads with all metric cards
- [ ] Completion rate card shows correct percentage and trend
- [ ] Planned vs Actual chart renders correctly
- [ ] Focus hours card shows correct data (based on focus categories)
- [ ] Productivity trend line chart shows data from reviews
- [ ] Category breakdown donut chart renders
- [ ] Consistency heatmap shows correct day markers
- [ ] Peak hours heatmap renders
- [ ] Daily/Weekly/Monthly toggle works
- [ ] Empty states show when insufficient data
- [ ] Search works with debounced input
- [ ] Search results navigate to correct task

---

## Chunk 8: Supabase Sync

**Goal**: Data syncs seamlessly between Ubuntu desktop and Android. Full offline support.

### Instructions

1. **Supabase project setup**
   - Create Supabase project (free tier)
   - Create PostgreSQL tables mirroring the SQLite schema (see `architecture.md` Section 9)
   - Add `user_id` column to every syncable table
   - Set up RLS policies: `auth.uid() = user_id` on all tables
   - Create `updated_at` triggers (auto-update on row change)

2. **Supabase Auth** — Implement:
   - Add `supabase_flutter` package
   - Email/password registration screen
   - Email/password login screen
   - "Skip" option to use app without sync (offline-only mode)
   - Session persistence (store tokens locally, auto-refresh)

3. **Auth UI**
   - Simple login/register screen with email + password fields
   - Error handling (invalid email, wrong password, network error)
   - Show logged-in user email in Settings

4. **Drift migration v6** — Add table:
   - `sync_log` table (full schema)
   - Create DAO: `SyncDao`

5. **Sync Log implementation**
   - On every INSERT/UPDATE/DELETE on syncable tables:
     - Set `sync_status = 1` (pending) on the record
     - Increment `revision`
     - Insert entry into `sync_log` (table_name, record_id, operation, JSON payload, timestamp)
   - Implement this as Drift transaction hooks or repository-level logic

6. **SyncEngine** — Implement push/pull:
   - **push()**: Read unpushed sync_log entries → batch upsert to Supabase → mark as pushed → set sync_status = 0 on records
   - **pull()**: Query Supabase for records updated since `last_pull_timestamp` → merge locally using revision comparison
   - **Conflict resolution**: as described in `architecture.md` Section 9 (last-write-wins)

7. **Connectivity monitor**
   - Add `connectivity_plus` package
   - `connectivityProvider` — Stream<bool> of online/offline status

8. **Auto-sync triggers** — Implement all triggers from `architecture.md`:
   - On app launch (if online)
   - On network restored (offline → online)
   - Every 5 minutes while online
   - Debounced 2s after any local write
   - On app backgrounded (Android)

9. **Sync status indicator** — App bar icon:
   - Show sync state: synced ✓ / syncing ⟳ / pending ↑ / offline ✗ / error ⚠ / not configured —
   - Tap to see details or trigger manual sync

10. **First-time sync**
    - On first login: push ALL local data to Supabase
    - If Supabase already has data: pull and merge using last-write-wins
    - Store `last_pull_timestamp`

11. **Sync settings UI** — Settings → Sync:
    - Login/logout button
    - Enable/disable sync toggle
    - Last sync time display
    - Manual sync button
    - Account info (email)

12. **Soft delete cleanup**
    - Periodic job (on app launch, max once per day): hard-delete records where `deleted_at` is older than 30 days, both locally and remotely

13. **Error handling**
    - Retry with exponential backoff (1s, 2s, 4s, max 60s)
    - Toast notification on persistent failure
    - Detailed error in sync settings screen

14. **Sync all tables** — Ensure sync covers:
    - tasks, subtasks, categories, tags, task_tags, recurring_rules, task_templates, daily_reviews, weekly_reviews, timer_sessions

### Verification Checklist
- [ ] Can register a new account with email/password
- [ ] Can login with existing account
- [ ] Can skip login and use offline-only
- [ ] Local changes sync to Supabase when online
- [ ] Remote changes sync to local on pull
- [ ] Sync triggers work (app launch, reconnect, periodic, after write)
- [ ] Sync status indicator shows correct state
- [ ] First-time sync pushes all local data
- [ ] Conflict resolution uses last-write-wins correctly
- [ ] RLS prevents accessing other users' data
- [ ] Sync settings UI works (login/logout, toggle, manual sync)
- [ ] Soft-deleted records are cleaned up after 30 days
- [ ] Error handling with retry works
- [ ] All 10 syncable tables sync correctly

---

## Chunk 9: Keyboard Shortcuts + Platform Polish

**Goal**: Desktop-class keyboard navigation. Polished platform-appropriate experience on both Ubuntu and Android.

### Instructions

1. **Keyboard shortcut system**
   - `KeyboardShortcutHandler` widget wrapping the app
   - All shortcuts from `architecture.md` Section 6 keyboard shortcuts table

2. **Focus management**
   - Arrow keys (↑/↓) navigate between task blocks
   - Visual focus ring on selected block (glowing border)
   - `Ctrl+↑`/`Ctrl+↓` move the selected task by one grid slot
   - `Shift+↑`/`Shift+↓` resize the selected task

3. **Shortcut help overlay**
   - `?` key shows a modal with all keyboard shortcuts

4. **Desktop window management**
   - Add `window_manager` package
   - Remember window size and position across sessions (store in `app_settings`)
   - Minimum window size: 800×600

5. **Responsive layouts** — Polish:
   - Nav rail with labels (desktop) vs bottom nav with icons (mobile)
   - Side panel editor (desktop) vs bottom sheet editor (mobile)
   - Inbox as bottom strip (desktop) vs dedicated tab (mobile)

6. **Scroll behavior**
   - Smooth scroll animations on the timeline
   - Scroll to current time on app open
   - Scroll to newly created task

7. **Context menus (desktop)** — Right-click:
   - Edit, Duplicate, Delete, Change Status (submenu), Start Timer, Save as Template

8. **Touch gestures (mobile)**
   - Long-press to drag tasks
   - Swipe left/right on Day View to navigate between days
   - Pull down to refresh sync

9. **Platform-specific theming**
   - Desktop: denser spacing, smaller touch targets
   - Mobile: larger touch targets (min 48dp), comfortable spacing

10. **App icon** — Design and set launcher icon for both platforms

11. **Splash screen** — Branded splash screen:
    - Dark background with app name centered

12. **Empty day state**
    - When a day has no tasks: show friendly illustration/icon + "Tap + to add your first block" message

### Verification Checklist
- [ ] All keyboard shortcuts from the shortcuts table work
- [ ] Arrow keys navigate between task blocks with visual focus
- [ ] `?` key shows shortcut help overlay
- [ ] Window size/position persists across sessions
- [ ] Responsive layout works correctly at different screen sizes
- [ ] Smooth scroll animations
- [ ] Context menu works on right-click (desktop)
- [ ] Touch gestures work (long-press drag, swipe between days)
- [ ] App icon set for both platforms
- [ ] Splash screen displays on launch
- [ ] Empty day state shows helpful message

---

## Chunk 10: Polish, Performance, Testing

**Goal**: Production-ready, tested, polished application.

### Instructions

1. **Performance profiling**
   - Timeline rendering < 16ms per frame, 60fps during drag/scroll
   - Profile with Flutter DevTools
   - Optimize any widget rebuilds that are too frequent

2. **Query optimization**
   - Run EXPLAIN QUERY PLAN on key queries to verify indexes are used
   - Eliminate any N+1 queries (e.g., loading subtasks for each task separately)

3. **Animations** — Add micro-animations:
   - Status change: color fade transition
   - Task create: slide-in animation
   - Task delete: fade-out animation
   - Drag: scale up + drop shadow
   - Timer tick: subtle pulse
   - Panel open/close: slide animation

4. **Error handling**
   - Graceful error boundaries on all screens
   - User-friendly error messages (not raw exceptions)
   - Retry logic for database operations

5. **Data export** — Settings → Export:
   - Export all data as JSON file
   - Include: tasks, subtasks, categories, tags, recurring rules, templates, reviews, timer sessions

6. **Data import** — Settings → Import:
   - Import JSON backup to restore data
   - Merge strategy: skip records with same ID if they already exist (or overwrite if newer)

7. **Onboarding** — First-launch flow:
   - Welcome screen with app description
   - Guide: create first category
   - Guide: create first task
   - Brief explanation of inbox

8. **Accessibility**
   - Semantic labels on all interactive elements
   - Sufficient contrast ratios (WCAG AA)
   - Screen reader testing

9. **Unit tests** — Write tests for:
   - `ConflictDetector`, `ConflictResolver`
   - `CommandHistory` (undo/redo)
   - `MoveTaskCommand`, `CreateTaskCommand`, etc.
   - `RecurrenceService` (materialization, exceptions)
   - `TimerService` (start/pause/stop, single active enforcement)
   - `SyncEngine` (push/pull, conflict resolution)
   - `AnalyticsService` (metric computation)

10. **Widget tests** — Write tests for:
    - `TaskBlockWidget` (rendering, tap behavior)
    - `TimelineWidget` (layout, grid rendering)
    - `InboxSidebar` (items display, drag)
    - `SubtaskList` (add, toggle, reorder)
    - `TimerControls` (start/pause/stop)

11. **Integration tests** — Write tests for:
    - Full day planning flow (create tasks, move them, set statuses)
    - Reschedule flow (overdue → inbox → drag to new day)
    - Timer flow (start → pause → resume → stop → verify duration)
    - Sync flow (create local → push → pull on another "device")

12. **Edge case handling**
    - Midnight-crossing blocks (task from 23:00 to 01:00)
    - Very long days (20+ blocks)
    - Empty data states everywhere
    - Extremely long task titles (truncation)

13. **Memory management**
    - Ensure all streams are properly disposed
    - No memory leaks on long sessions (verify with DevTools)

14. **Search polish**
    - Debounced search input (300ms)
    - Highlighted matches in results
    - Navigate to task on tap

15. **Final QA**
    - Test both platforms end-to-end
    - Fix all visual bugs, alignment issues, overflow errors
    - Verify all features from all previous chunks still work

### Verification Checklist
- [ ] 60fps during drag and scroll (no jank)
- [ ] All database queries use indexes
- [ ] Animations are smooth and consistent
- [ ] Error boundaries prevent crashes
- [ ] Data export produces valid JSON
- [ ] Data import restores data correctly
- [ ] Onboarding flow completes successfully
- [ ] All interactive elements have semantic labels
- [ ] Unit tests pass (all services and commands)
- [ ] Widget tests pass
- [ ] Integration tests pass
- [ ] No memory leaks on long sessions
- [ ] Both platforms tested end-to-end
- [ ] All features from previous chunks still work

---

*End of planner. For architecture context, see `architecture.md`. For progress tracking, see `progress.md`.*
