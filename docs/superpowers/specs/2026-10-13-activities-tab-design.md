# Activities Tab Design

**Date:** 2026-10-13

## Goal

Replace the Log tab with an Activities tab that shows full workout history and gives access to workout template management. Move weight log access to the Dashboard weight chart. Keep Start Workout on Dashboard only.

## Tab Structure (Before → After)

| Tab | Before | After |
|-----|--------|-------|
| 1 | Dashboard | Dashboard (unchanged) |
| 2 | Routes | Routes (unchanged) |
| 3 | Log (weight entries) | Activities (workout history + templates) |

## Activities Tab

A `NavigationStack`-based view titled "Activities".

**Toolbar:** Single trailing button "Templates" — opens the existing `TemplateListSheet` as a sheet. No Start Workout button.

**Content:** Full scrollable list of all workouts — same merge logic as `ActivitiesCard` (HealthKit + local SwiftData sessions), but without the current 3-item truncation limit. Each row taps into the existing `WorkoutLogSheet`.

**New file:** `ActivitiesView.swift` (~100 lines). Extracts and reuses the merge/query logic already in `ActivitiesCard`.

## Weight Log Access (Dashboard)

The `WeightChartView` on Dashboard becomes tappable. Tapping it presents a sheet containing the weight entry list (currently the body of `LogView`).

**Changes:**
- Extract the list content from `LogView` into a new `WeightLogSheet.swift` (sheet presentation style, matching existing sheet patterns).
- `DashboardView`: wrap `WeightChartView` in a `Button` or add `.onTapGesture` that toggles `showingWeightLog: Bool` state, presenting `WeightLogSheet`.
- `LogView.swift`: deleted (no longer a tab).

## Dashboard (unchanged except weight log trigger)

- `ActivitiesCard` stays as a summary (truncated list, "See all" could remain or be removed — no change required for this spec).
- Activity rings, weight chart, start workout button all remain.

## Files Changed

| File | Change |
|------|--------|
| `ContentView.swift` | Swap Log tab → Activities tab |
| `ActivitiesView.swift` | New — full activity list with Templates toolbar button |
| `WeightLogSheet.swift` | New — weight entry list as a sheet (extracted from LogView) |
| `DashboardView.swift` | Add tap gesture on WeightChartView to present WeightLogSheet |
| `LogView.swift` | Deleted |

## Files Unchanged

`TemplateListSheet`, `TemplateEditorSheet`, `WorkoutLogSheet`, `ActivitiesCard`, `WorkoutSessionService`, all data models, all HealthKit services.

## Out of Scope

- Pagination or infinite scroll for the activity list
- Start Workout in Activities tab
- Any changes to template data model or editor UI
