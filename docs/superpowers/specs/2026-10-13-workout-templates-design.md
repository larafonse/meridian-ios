# Workout Templates Design Spec

**Date:** 2026-10-13
**Status:** Approved

---

## Goal

Allow users to create named workout templates (e.g. "Leg Day") with pre-defined exercises and optional default reps/weights, then start a workout session from a template with sets pre-filled from either the template defaults or the most recent matching session.

---

## Context

Builds on top of the existing workout tracking feature. `WorkoutSession`, `Exercise`, `WorkoutSet`, and `WorkoutSessionService` already exist. The `StartWorkoutSheet` currently shows a type picker; it will be updated to show templates first.

---

## Data Models (SwiftData — new)

```
WorkoutTemplate
├── id: UUID
├── name: String                      ← "Leg Day"
├── workoutType: String               ← HKWorkoutActivityType raw id, e.g. "traditionalStrengthTraining"
├── workoutTypeDisplayName: String    ← "Strength Training"
├── createdAt: Date
└── exercises: [TemplateExercise]     (@Relationship deleteRule: .cascade)

TemplateExercise
├── id: UUID
├── name: String                      ← "Squat"
├── order: Int
├── defaultReps: Int?                 ← nil = not set
├── defaultWeight: Double?            ← nil = not set
└── defaultWeightUnit: String         ← "lbs" / "kg", default "lbs"
```

Add both to the existing `modelContainer`.

---

## Pre-fill Logic

When the user starts a session from a template:

1. Query SwiftData for the most recent `WorkoutSession` where `workoutType == template.workoutType` and `endedAt != nil`, ordered by `startedAt` descending.
2. Build a lookup: `[exerciseName.lowercased(): [WorkoutSet]]` from that session's exercises.
3. For each `TemplateExercise`:
   - If the last session has a matching exercise (by lowercased name): copy all of its sets (reps + weight + unit) as the starting sets.
   - Otherwise if the template has `defaultReps` or `defaultWeight`: create one set with those values.
   - Otherwise: create one empty set (reps=0, weight=0, unit="lbs").
4. Set the session label to `template.name`.

---

## UI

### `StartWorkoutSheet` — updated

- Toolbar: "Templates" button (leading) opens `TemplateListSheet`.
- If any templates exist: "My Templates" section at top — horizontal scroll of template cards (name + exercise count).
- "Workout Types" section below — existing type list (unchanged).
- Tapping a template card calls `startFromTemplate(_:)`.

### `TemplateListSheet` (new)

- Full-screen sheet with a `List` of templates.
- Each row: template name, workout type display name, exercise count, swipe-to-delete.
- Tap a row → `TemplateEditorSheet` for editing.
- `+` toolbar button → `TemplateEditorSheet` for creating.

### `TemplateEditorSheet` (new)

- Navigation title "New Template" or "Edit Template".
- Fields:
  - Name (text field, required)
  - Workout type (same picker as `StartWorkoutSheet`)
- Exercise list: name + optional default reps + optional default weight (same add/delete pattern as `ActiveWorkoutView`).
- "Save" button (disabled until name is non-empty).

---

## `StartWorkoutSheet` — start from template flow

```swift
func startFromTemplate(_ template: WorkoutTemplate) async {
    // 1. Create WorkoutSession
    let session = WorkoutSession(
        workoutType: template.workoutType,
        workoutTypeDisplayName: template.workoutTypeDisplayName,
        label: template.name,
        startedAt: .now
    )
    modelContext.insert(session)

    // 2. Find last session of same type
    let lastSession = fetchLastSession(workoutType: template.workoutType)

    // 3. Pre-fill exercises
    for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
        let exercise = Exercise(name: templateExercise.name, order: session.exercises.count)
        modelContext.insert(exercise)

        let historySets = lastSession?.exercises
            .first(where: { $0.name.lowercased() == templateExercise.name.lowercased() })?
            .sets.sorted(by: { $0.order < $1.order }) ?? []

        if !historySets.isEmpty {
            for (i, hs) in historySets.enumerated() {
                let set = WorkoutSet(reps: hs.reps, weight: hs.weight, unit: hs.unit, order: i)
                modelContext.insert(set)
                exercise.sets.append(set)
            }
        } else if templateExercise.defaultReps != nil || templateExercise.defaultWeight != nil {
            let set = WorkoutSet(
                reps: templateExercise.defaultReps ?? 0,
                weight: templateExercise.defaultWeight ?? 0,
                unit: templateExercise.defaultWeightUnit,
                order: 0
            )
            modelContext.insert(set)
            exercise.sets.append(set)
        } else {
            let set = WorkoutSet(reps: 0, weight: 0, unit: "lbs", order: 0)
            modelContext.insert(set)
            exercise.sets.append(set)
        }

        session.exercises.append(exercise)
    }

    // 4. Start HK session and navigate
    let config = HKWorkoutConfiguration()
    config.activityType = WorkoutType.all.first(where: { $0.id == template.workoutType })?.hkType ?? .other
    try? await service.start(configuration: config)

    activeWorkout = session
    dismiss()
}
```

---

## `MeridianApp.swift` changes

Add `WorkoutTemplate.self, TemplateExercise.self` to the model container.

---

## Success Criteria

- User can create a named template with exercises and optional defaults.
- Starting from a template pre-fills exercises and sets from last session history (or template defaults if no history).
- Templates are listed first in `StartWorkoutSheet` for quick access.
- Templates can be edited and deleted.
- Workout type picker in the template editor uses the same 12 types.
