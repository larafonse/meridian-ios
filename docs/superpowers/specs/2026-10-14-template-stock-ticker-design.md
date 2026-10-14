# Template Stock Ticker Design

**Date:** 2026-10-14
**Status:** Approved

## Overview

Workout templates are displayed like a stock portfolio: each template has a ticker symbol, a sparkline of volume history, and a current value (most recent total volume). Completing a workout from a template records a score. Two entry points: a dashboard card showing the 3 most recently-used templates, and a full ticker-style template list.

## Data Model

### New: `TemplateWorkoutScore`

```swift
@Model class TemplateWorkoutScore {
    var id: UUID
    var templateID: UUID
    var templateName: String   // denormalized — survives template deletion
    var sessionID: UUID
    var date: Date
    var totalVolume: Double    // always stored in lbs (kg converted at write time)
}
```

Added to `MeridianApp.swift` `ModelContainer` schema.

### Modified: `WorkoutSession`

Add one field:
```swift
var templateID: UUID?
```

Set at session start if the workout was initiated from a template. Remains `nil` for free-form workouts.

## Ticker Symbol Generation

Computed at display time from the template name — no storage needed.

- Multi-word names: first letter of each word, uppercased, up to 4 characters. ("Push Pull Legs" → "PPL", "Upper Body Strength" → "UBS")
- Single-word names: first 4 characters uppercased. ("Cardio" → "CARD")

## Score Calculation

Triggered inside `WorkoutSessionService.endSession()` when `WorkoutSession.templateID` is non-nil:

1. Iterate all `Exercise → WorkoutSet` in the session.
2. For each set: `volume += weight × reps`, converting kg to lbs (`× 0.453592`) when `unit == "kg"`.
3. Create and persist a `TemplateWorkoutScore` with the computed `totalVolume`.

## UI Components

### `SparklineView`
- SwiftUI Charts mini line graph, ~60×30pt, no axes or labels.
- Input: array of `Double` (volume values, chronological order).
- Color: green if last value ≥ first value in the window, red otherwise.
- Shows up to last 10 sessions for the template.

### `TemplateTickerRow`
A single list row:
```
[TICKER]   [Template Name]      [sparkline]    [12,450 lbs]
```
- Ticker: small monospaced bold label (e.g., "PPL").
- Volume: formatted with commas, no decimals, unit suffix ("lbs").
- Templates with zero history: no sparkline, value shows "--".

### `TemplatesPortfolioCard`
- Dashboard card matching existing card style (ActivitiesCard etc.).
- Shows the 3 most recently-used templates as `TemplateTickerRow`s, determined by the latest `TemplateWorkoutScore.date` per template.
- Tapping navigates to the full `TemplateListSheet`.

### `TemplateListSheet` (modified)
- Replaces current plain list rows with `TemplateTickerRow`.
- Templates with no history sort to the bottom.
- Edit, delete, and add buttons remain unchanged.

## Data Flow

### Starting a workout
`StartWorkoutSheet` passes the selected template's `id` into `WorkoutSessionService`. The service sets `WorkoutSession.templateID` when creating the session.

### Finishing a workout
`WorkoutSessionService.endSession()` checks `templateID`. If set, computes total volume and creates a `TemplateWorkoutScore`. This happens in the same transaction as saving the `WorkoutSession`.

### Querying for sparklines
Each `TemplateTickerRow` uses a `@Query` filtered by `templateID`, sorted by `date` ascending. The last 10 results are passed to `SparklineView`.

### Dashboard card ordering
Fetches all `TemplateWorkoutScore` sorted by `date` descending, extracts the 3 distinct most-recently-used `templateID`s, loads the corresponding `WorkoutTemplate` records.

## Files Affected

| File | Change |
|------|--------|
| `Models/TemplateWorkoutScore.swift` | **New** — SwiftData model |
| `Models/WorkoutSession.swift` | Add `templateID: UUID?` |
| `MeridianApp.swift` | Add `TemplateWorkoutScore` to ModelContainer schema |
| `Helpers/WorkoutSessionService.swift` | Thread `templateID` through start; write score on end |
| `Views/StartWorkoutSheet.swift` | Pass `templateID` when starting from template |
| `Views/Components/SparklineView.swift` | **New** — mini line chart |
| `Views/Components/TemplateTickerRow.swift` | **New** — stock-ticker row |
| `Views/TemplatesPortfolioCard.swift` | **New** — dashboard card |
| `Views/TemplateListSheet.swift` | Adopt `TemplateTickerRow`, reorder by history |
| Dashboard view | Add `TemplatesPortfolioCard` |
