# Workout Tracking Design Spec

**Date:** 2026-10-13
**Status:** Approved

---

## Goal

Allow users to start a workout session from Meridian that records to HealthKit, log exercises/sets/reps/weights in real-time during the workout, and review progress across sessions of the same workout type.

---

## Context

Meridian is a SwiftUI + SwiftData iOS 17+ app. It already integrates HealthKit for reading activity rings. The new feature extends HealthKit usage to write workouts and read live heart rate, and adds new SwiftData models for workout logging.

---

## User Flow

1. **Dashboard** shows an Activities card below the Weight card. The card lists the last 4 completed workout sessions and has a **Start Workout** button.
2. Tapping **Start Workout** opens a bottom sheet to pick a workout type (from a curated list of `HKWorkoutActivityType` values) and enter an optional label (e.g. "Leg Day").
3. Tapping **Start** dismisses the sheet and opens the **Active Workout View** full-screen.
4. The Active Workout View shows: workout type, label, elapsed timer, live BPM (from Apple Watch via HealthKit observer), and a scrollable exercise log.
5. User adds exercises by name, then adds sets with reps + weight per set.
6. Tapping **Minimize** collapses back to the dashboard. The Activities card shows a pulsing **"Active · Resume"** banner instead of the Start button. Tapping it reopens the Active Workout View.
7. Tapping **End Workout** collects all heart rate samples from HealthKit for the session window, saves the workout via `HKWorkoutBuilder`, persists the `WorkoutSession` to SwiftData, and returns to the dashboard.
8. The completed session appears in the Activities card list.
9. Tapping any past session in the Activities card opens a **Workout History Sheet** showing all sessions of that workout type with exercises and weight/rep progression across dates.

---

## HealthKit Integration

### Permissions required (additions to existing)
- **Write:** `HKWorkoutType`
- **Read:** `HKQuantityType(.heartRate)`

### Recording a workout
- Use `HKWorkoutBuilder` with an `HKWorkoutConfiguration` (activity type set from user selection).
- Call `beginCollection(withStart:)` when the user taps Start.
- When the user taps End Workout:
  1. Query HealthKit for all `HKQuantitySample` heart rate samples between `startDate` and `Date()`.
  2. Add them to the builder via `addSamples(_:)`.
  3. Call `endCollection(withEnd:)` then `finishWorkout()`.
  4. Store the resulting `HKWorkout.uuid` in the `WorkoutSession` SwiftData model.

### Live heart rate
- Use `HKAnchoredObjectQuery` on `HKQuantityType(.heartRate)` with `HKQuery.predicateForSamples(withStart:end:options:)` (start = workout start, end = nil for open-ended).
- Enable live updates via `updateHandler` — update a `@State var currentBPM: Int?` in the Active Workout View.
- Stop the query when the workout ends.

### Note on "in progress" detection
HealthKit does not expose in-progress workouts from other apps (Watch/Fitness) before they are saved. The Activities card refreshes automatically when the app foregrounds; newly saved workouts appear immediately.

---

## Data Models (SwiftData)

All new models are added to the existing `modelContainer`.

```
WorkoutSession
├── id: UUID                        (default: UUID())
├── healthKitUUID: UUID?            (set after HKWorkout saves)
├── workoutType: String             (HKWorkoutActivityType.name, e.g. "traditionalStrengthTraining")
├── workoutTypeDisplayName: String  (human-readable, e.g. "Strength Training")
├── label: String                   (user-entered, e.g. "Leg Day"; may be empty)
├── startedAt: Date
├── endedAt: Date?                  (nil while active)
└── exercises: [Exercise]           (@Relationship(deleteRule: .cascade))

Exercise
├── id: UUID
├── name: String                    (e.g. "Squat")
├── order: Int                      (display order within session)
└── sets: [WorkoutSet]              (@Relationship(deleteRule: .cascade))

WorkoutSet
├── id: UUID
├── reps: Int
├── weight: Double
├── unit: String                    ("lbs" or "kg")
└── order: Int                      (display order within exercise)
```

---

## UI Components

### `ActivitiesCard` (new file)
- Full-width card on dashboard, below `WeightChartView`.
- Shows "Activities" header.
- If a workout is active (passed in as a binding): shows pulsing "Active · Resume" banner.
- Otherwise: shows "Start Workout" button + list of last 4 `WorkoutSession` entries from SwiftData (most recent first).
- Each row: workout type display name, label (if set), date, duration.

### `StartWorkoutSheet` (new file)
- Bottom sheet (`.sheet`).
- Workout type picker: scrollable list of ~12 common types with SF Symbol icons.
- Label text field (optional, placeholder "Label (e.g. Leg Day)").
- Start button.

### `ActiveWorkoutView` (new file)
- Full-screen sheet (`.fullScreenCover`).
- Header: type name + label, elapsed time (updates every second via `Timer`), BPM (live, shows "—" until first reading).
- Body: `List` of exercises. Each exercise has a name header and a list of sets (reps + weight).
- "Add Exercise" button at bottom of list.
- "Add Set" button per exercise.
- Swipe-to-delete on sets and exercises.
- Toolbar: "Minimize" (leading) and "End Workout" (trailing, red).

### `WorkoutHistorySheet` (new file)
- Bottom sheet opened by tapping a past session in `ActivitiesCard`.
- Shows all sessions with the same `workoutType`, ordered by `startedAt` descending.
- Each session: date header, label, then exercises grouped with sets (reps × weight).
- No editing — read-only progress view.

---

## Dashboard Changes

`DashboardView.swift` gains:
- `@State private var activeWorkout: WorkoutSession?` — non-nil while a workout is in progress.
- `@State private var showingStartSheet = false`
- `@State private var showingActiveWorkout = false`
- `ActivitiesCard(activeWorkout: $activeWorkout, onStart: { showingStartSheet = true }, onResume: { showingActiveWorkout = true })` inserted after `WeightChartView`.
- `.sheet(isPresented: $showingStartSheet) { StartWorkoutSheet(activeWorkout: $activeWorkout, showingActiveWorkout: $showingActiveWorkout) }`
- `.fullScreenCover(isPresented: $showingActiveWorkout) { ActiveWorkoutView(workout: activeWorkout!, onMinimize: { showingActiveWorkout = false }) }`

---

## `MeridianApp.swift` Changes

Add `WorkoutSession.self, Exercise.self, WorkoutSet.self` to the model container:
```swift
.modelContainer(for: [WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self])
```

---

## `Meridian.entitlements` Changes

Already has HealthKit entitlement. No change needed.

---

## `Info.plist` Changes

Add `NSHealthUpdateUsageDescription` for writing workouts.

---

## Workout Type List

Curated list of 12 types with display names and SF Symbol icons:

| Display Name              | HKWorkoutActivityType raw        | SF Symbol               |
|---------------------------|----------------------------------|-------------------------|
| Strength Training         | traditionalStrengthTraining      | dumbbell                |
| Functional Training       | functionalStrengthTraining       | figure.strengthtraining.functional |
| Running                   | running                          | figure.run              |
| Cycling                   | cycling                          | figure.outdoor.cycle    |
| HIIT                      | highIntensityIntervalTraining    | bolt.heart              |
| Walking                   | walking                          | figure.walk             |
| Swimming                  | swimming                         | figure.pool.swim        |
| Yoga                      | yoga                             | figure.yoga             |
| Pilates                   | pilates                          | figure.pilates          |
| Rowing                    | rowing                           | figure.rower            |
| Elliptical                | elliptical                       | figure.elliptical       |
| Other                     | other                            | figure.mixed.cardio     |

---

## Success Criteria

- User can start a workout, log exercises/sets/reps/weights, and end it — workout appears in HealthKit/Fitness app history.
- Live BPM displays during an active workout when Apple Watch is paired and worn.
- Minimizing and resuming the Active Workout View preserves all logged data.
- Completed sessions appear in the Activities card on the dashboard.
- Tapping a session shows all past sessions of that workout type with full exercise history.
- App does not crash if HealthKit is unavailable or permission is denied; graceful degradation (no BPM shown, workout saved locally only without HK UUID).

---

## Out of Scope

- watchOS companion app
- Editing past workout sessions
- Custom workout type creation
- Nutrition logging
- Sharing or exporting workouts
