# Decouple App Workouts from HealthKit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove HKWorkoutSession management from the app so it acts as a pure exercise log; auto-link sessions to Apple Watch workouts after both finish, with a manual fallback.

**Architecture:** A new `WorkoutLinkerService` registers an HK background observer. When a Watch workout lands in HealthKit, it scans unlinked `WorkoutSession`s for time overlap and sets `healthKitUUID`. `WorkoutLogSheet` gains a manual "Link to Watch workout" picker for the reverse flow. All HK session creation, metrics accumulation, GPS, and writes are removed.

**Tech Stack:** Swift, SwiftUI, SwiftData, HealthKit, Swift Testing

**Spec:** Emerged from brainstorming conversation 2026-10-14.

## Global Constraints

- Target iOS 17+
- Swift Testing (`@Test`, `@Suite`) for all new tests
- No HKWorkoutSession creation, no HKLiveWorkoutBuilder, no HK write operations
- `WorkoutSession.healthKitUUID: UUID?` remains the linking key
- Each task must leave the project building after its commit

## Review Focus

- Watch workout starts before app session and ends after: overlap filter should still match (session.startedAt ≤ hk.endDate && sessionEnd ≥ hk.startDate)
- Two sessions overlap the same HK workout: only the one with greater overlap duration gets linked; remaining session stays unlinked
- App session still in-progress (endedAt == nil) when Watch workout arrives: link and set endedAt from HK workout's endDate
- Multiple HK workouts arrive simultaneously (batch): each unlinked session is consumed at most once — use a shrinking `remaining` list
- Session manually linked to the wrong HK workout: user can re-open `WorkoutLogSheet` and pick a different one; the new UUID overwrites the old

---

### Task 1: Extract `WorkoutType` to its own model file

`WorkoutType` struct currently lives at the bottom of `WorkoutSessionService.swift`. It needs to move before that file is deleted.

**Files:**
- Create: `Meridian/Models/WorkoutType.swift`
- Modify: `Meridian/Helpers/WorkoutSessionService.swift` (delete the `WorkoutType` block at lines 280–300)

- [ ] **Step 1: Create `Meridian/Models/WorkoutType.swift`**

```swift
import HealthKit

struct WorkoutType: Identifiable, Hashable {
    let id: String
    let displayName: String
    let symbol: String
    let hkType: HKWorkoutActivityType

    static let all: [WorkoutType] = [
        WorkoutType(id: "traditionalStrengthTraining",   displayName: "Strength Training",   symbol: "dumbbell",                           hkType: .traditionalStrengthTraining),
        WorkoutType(id: "functionalStrengthTraining",    displayName: "Functional Training",  symbol: "figure.strengthtraining.functional", hkType: .functionalStrengthTraining),
        WorkoutType(id: "running",                       displayName: "Running",              symbol: "figure.run",                         hkType: .running),
        WorkoutType(id: "cycling",                       displayName: "Cycling",              symbol: "figure.outdoor.cycle",               hkType: .cycling),
        WorkoutType(id: "highIntensityIntervalTraining", displayName: "HIIT",                 symbol: "bolt.heart",                         hkType: .highIntensityIntervalTraining),
        WorkoutType(id: "walking",                       displayName: "Walking",              symbol: "figure.walk",                        hkType: .walking),
        WorkoutType(id: "swimming",                      displayName: "Swimming",             symbol: "figure.pool.swim",                   hkType: .swimming),
        WorkoutType(id: "yoga",                          displayName: "Yoga",                 symbol: "figure.yoga",                        hkType: .yoga),
        WorkoutType(id: "pilates",                       displayName: "Pilates",              symbol: "figure.pilates",                     hkType: .pilates),
        WorkoutType(id: "rowing",                        displayName: "Rowing",               symbol: "figure.rower",                       hkType: .rowing),
        WorkoutType(id: "elliptical",                    displayName: "Elliptical",           symbol: "figure.elliptical",                  hkType: .elliptical),
        WorkoutType(id: "other",                         displayName: "Other",                symbol: "figure.mixed.cardio",                hkType: .other),
    ]
}
```

- [ ] **Step 2: Delete the duplicate `WorkoutType` block from `WorkoutSessionService.swift`**

Delete lines 279–300 (the `// MARK: - WorkoutType catalogue` section and everything below it). The file now ends at the `CLLocationManagerDelegate` extension closing brace.

- [ ] **Step 3: Build and confirm it compiles**

```
xcodebuild -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Meridian/Models/WorkoutType.swift Meridian/Helpers/WorkoutSessionService.swift
git commit -m "refactor: extract WorkoutType to its own model file"
```

---

### Task 2: Add `WorkoutLinkerService` — tests then implementation

**Files:**
- Create: `Meridian/Helpers/WorkoutLinkerService.swift`
- Create: `MeridianTests/WorkoutLinkerTests.swift`

**Interfaces:**
- Produces: `WorkoutLinkerService(modelContainer:)`, `linkPendingSessions() async`, `findBestOverlap(hkWorkout:sessions:) -> WorkoutSession?`

- [ ] **Step 1: Write the failing tests**

Create `MeridianTests/WorkoutLinkerTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
import HealthKit
@testable import Meridian

@Suite("WorkoutLinkerService")
@MainActor
struct WorkoutLinkerTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
    }

    private func makeSession(
        start: Date,
        end: Date?,
        in ctx: ModelContext
    ) -> WorkoutSession {
        let s = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "",
            startedAt: start
        )
        s.endedAt = end
        ctx.insert(s)
        return s
    }

    private func makeHKWorkout(start: Date, end: Date) -> HKWorkout {
        HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: end)
    }

    @Test("returns nil when sessions list is empty")
    func noSessions() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let hk = makeHKWorkout(start: .now, end: .now.addingTimeInterval(3600))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: []) == nil)
    }

    @Test("returns nil when no session overlaps the HK workout")
    func noOverlap() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // Session ends at t=1800; HK starts at t=3600
        let session = makeSession(start: base, end: base.addingTimeInterval(1800), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(3600), end: base.addingTimeInterval(5400))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session]) == nil)
    }

    @Test("returns the single overlapping session")
    func singleOverlap() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // Session: 0..3600, HK: 1800..5400 — overlap 1800..3600
        let session = makeSession(start: base, end: base.addingTimeInterval(3600), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(1800), end: base.addingTimeInterval(5400))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session])?.id == session.id)
    }

    @Test("picks the session with greater overlap when two candidates exist")
    func picksGreaterOverlap() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // HK: 1000..5000
        // Session A: 0..2000   → overlap 1000..2000 = 1000 s
        // Session B: 500..4500 → overlap 1000..4500 = 3500 s ← better
        let sessionA = makeSession(start: base, end: base.addingTimeInterval(2000), in: ctx)
        let sessionB = makeSession(start: base.addingTimeInterval(500), end: base.addingTimeInterval(4500), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(1000), end: base.addingTimeInterval(5000))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [sessionA, sessionB])?.id == sessionB.id)
    }

    @Test("matches an in-progress session (endedAt == nil)")
    func inProgressSession() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        // HK workout finished 30 minutes ago; session started 1 hour ago and is still open
        let now = Date()
        let session = makeSession(start: now.addingTimeInterval(-3600), end: nil, in: ctx)
        let hk = makeHKWorkout(
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(-1800)
        )
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session])?.id == session.id)
    }

    @Test("does not match a session that ends before the HK workout starts")
    func sessionEndsBeforeHKStarts() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // Session: 0..1000, HK: 2000..3000
        let session = makeSession(start: base, end: base.addingTimeInterval(1000), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(2000), end: base.addingTimeInterval(3000))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session]) == nil)
    }

    @Test("does not match a session starting after the HK workout ends")
    func sessionStartsAfterHKEnds() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // HK: 0..1000, Session: 2000..3000
        let session = makeSession(start: base.addingTimeInterval(2000), end: base.addingTimeInterval(3000), in: ctx)
        let hk = makeHKWorkout(start: base, end: base.addingTimeInterval(1000))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session]) == nil)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail** (type not found)

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/WorkoutLinkerTests 2>&1 | grep -E "error:|FAILED|PASSED"
```
Expected: compile error — `WorkoutLinkerService` not found.

- [ ] **Step 3: Implement `WorkoutLinkerService`**

Create `Meridian/Helpers/WorkoutLinkerService.swift`:

```swift
import Foundation
import HealthKit
import SwiftData

@MainActor
final class WorkoutLinkerService: ObservableObject {
    private let store = HKHealthStore()
    private let modelContainer: ModelContainer
    private var observerQuery: HKObserverQuery?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        startObserving()
    }

    // MARK: - Observer

    private func startObserving() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task { @MainActor [weak self] in
                await self?.linkPendingSessions()
                completionHandler()
            }
        }
        store.execute(query)
        observerQuery = query
        store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
    }

    func stopObserving() {
        if let q = observerQuery { store.stop(q) }
        observerQuery = nil
    }

    // MARK: - Auto-linking

    /// Fetches all unlinked sessions and matches them against recent HK workouts by time overlap.
    /// Safe to call on every app foreground / dashboard refresh.
    func linkPendingSessions() async {
        let ctx = ModelContext(modelContainer)
        let predicate = #Predicate<WorkoutSession> { $0.healthKitUUID == nil }
        guard let unlinked = try? ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: predicate)),
              !unlinked.isEmpty else { return }

        let earliest = unlinked.map(\.startedAt).min() ?? Date().addingTimeInterval(-86400)
        let hkWorkouts = await fetchHKWorkouts(from: earliest.addingTimeInterval(-3600))
        guard !hkWorkouts.isEmpty else { return }

        var remaining = unlinked
        for hkWorkout in hkWorkouts {
            guard let match = findBestOverlap(hkWorkout: hkWorkout, sessions: remaining) else { continue }
            link(session: match, to: hkWorkout)
            remaining.removeAll { $0.id == match.id }
        }

        try? ctx.save()
    }

    // MARK: - Linking helpers (internal for testability)

    func findBestOverlap(hkWorkout: HKWorkout, sessions: [WorkoutSession]) -> WorkoutSession? {
        let overlapping = sessions.filter { session in
            let sessionEnd = session.endedAt ?? Date()
            return session.startedAt <= hkWorkout.endDate && sessionEnd >= hkWorkout.startDate
        }
        return overlapping.max {
            overlapDuration(session: $0, hkWorkout: hkWorkout) <
            overlapDuration(session: $1, hkWorkout: hkWorkout)
        }
    }

    private func overlapDuration(session: WorkoutSession, hkWorkout: HKWorkout) -> TimeInterval {
        let sessionEnd = session.endedAt ?? Date()
        let overlapStart = max(session.startedAt, hkWorkout.startDate)
        let overlapEnd = min(sessionEnd, hkWorkout.endDate)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }

    private func link(session: WorkoutSession, to hkWorkout: HKWorkout) {
        session.healthKitUUID = hkWorkout.uuid
        if session.endedAt == nil {
            session.endedAt = hkWorkout.endDate
        }
        session.activeCalories = hkWorkout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        session.distanceMeters = hkWorkout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
    }

    // MARK: - HK fetch

    private func fetchHKWorkouts(from startDate: Date) async -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 50,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            self.store.execute(query)
        }
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/WorkoutLinkerTests 2>&1 | grep -E "Test.*passed|Test.*failed|error:"
```
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Meridian/Helpers/WorkoutLinkerService.swift MeridianTests/WorkoutLinkerTests.swift
git commit -m "feat: add WorkoutLinkerService with HK observer and overlap matching"
```

---

### Task 3: Remove `WorkoutSessionService` from the active workout flow

`StartWorkoutSheet`, `ActiveWorkoutView`, and `DashboardView` are tightly coupled through `WorkoutSessionService`. All three change together so the build stays green.

**Files:**
- Modify: `Meridian/Views/StartWorkoutSheet.swift`
- Modify: `Meridian/Views/ActiveWorkoutView.swift`
- Modify: `Meridian/Views/DashboardView.swift`
- Modify: `Meridian/MeridianApp.swift`

- [ ] **Step 1: Replace `StartWorkoutSheet.swift` with service-free version**

Complete replacement (keep UI cards, remove HK config + service + isStarting + async):

```swift
import SwiftUI
import SwiftData

struct StartWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var activeWorkout: WorkoutSession?

    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var showingTemplates = false

    private var strengthType: WorkoutType {
        WorkoutType.all.first(where: { $0.id == "traditionalStrengthTraining" }) ?? WorkoutType.all[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    DefaultWorkoutCard(type: strengthType) {
                        startDefault()
                    }

                    ForEach(templates) { template in
                        TemplateCard(template: template) {
                            startFromTemplate(template)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Templates") { showingTemplates = true }
                        .font(.system(size: 14))
                }
            }
            .sheet(isPresented: $showingTemplates) {
                TemplateListSheet()
            }
        }
    }

    // MARK: - Start default

    private func startDefault() {
        let session = WorkoutSession(
            workoutType: strengthType.id,
            workoutTypeDisplayName: strengthType.displayName,
            label: "",
            startedAt: .now
        )
        modelContext.insert(session)
        activeWorkout = session
        dismiss()
    }

    // MARK: - Start from template

    private func startFromTemplate(_ template: WorkoutTemplate) {
        let session = WorkoutSession(
            workoutType: template.workoutType,
            workoutTypeDisplayName: template.workoutTypeDisplayName,
            label: template.name,
            startedAt: .now
        )
        modelContext.insert(session)

        let lastSession = allSessions.first(where: {
            $0.workoutType == template.workoutType && $0.endedAt != nil
        })

        for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            let exercise = Exercise(name: templateExercise.name, order: session.exercises.count)
            modelContext.insert(exercise)

            let setValues = prefillSets(for: templateExercise, lastSession: lastSession)
            for (i, sv) in setValues.enumerated() {
                let set = WorkoutSet(reps: sv.reps, weight: sv.weight, unit: sv.unit, order: i)
                modelContext.insert(set)
                exercise.sets.append(set)
            }

            session.exercises.append(exercise)
        }

        activeWorkout = session
        dismiss()
    }
}

// MARK: - Pre-fill helper

/// Returns set values to pre-populate when starting from a template.
/// Mirrors the copy in MeridianTests for testability via @testable import.
func prefillSets(for templateExercise: TemplateExercise, lastSession: WorkoutSession?) -> [(reps: Int, weight: Double, unit: String)] {
    if let last = lastSession,
       let match = last.exercises.first(where: { $0.name.lowercased() == templateExercise.name.lowercased() }) {
        let sorted = match.sets.sorted { $0.order < $1.order }
        return sorted.map { (reps: $0.reps, weight: $0.weight, unit: $0.unit) }
    } else if templateExercise.defaultReps != nil || templateExercise.defaultWeight != nil {
        return [(reps: templateExercise.defaultReps ?? 0, weight: templateExercise.defaultWeight ?? 0, unit: templateExercise.defaultWeightUnit)]
    } else {
        return [(reps: 0, weight: 0, unit: "lbs")]
    }
}

// MARK: - Default workout card

private struct DefaultWorkoutCard: View {
    let type: WorkoutType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: type.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Spacer()
                Text(type.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text("Quick start")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.961, green: 0.941, blue: 0.922))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
        }
    }
}

// MARK: - Template card

private struct TemplateCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: WorkoutType.all.first(where: { $0.id == template.workoutType })?.symbol ?? "figure.mixed.cardio")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Spacer()
                Text(template.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text(template.workoutTypeDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(template.exercises.count) exercises")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.961, green: 0.941, blue: 0.922))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
        }
    }
}
```

- [ ] **Step 2: Replace `ActiveWorkoutView.swift` with service-free version**

Remove `service` param, remove BPM/kcal/distance cells, make `endWorkout()` synchronous:

```swift
import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    let workout: WorkoutSession
    let onMinimize: () -> Void
    let onEnd: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var newExerciseName: String = ""
    @State private var showingAddExercise = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Timer header
                HStack {
                    statCell(label: "Time", value: formatElapsed(elapsed))
                }
                .padding(.vertical, 12)
                .background(Color(red: 0.961, green: 0.941, blue: 0.922))

                Divider()

                // Exercise list
                List {
                    let sortedExercises = workout.exercises.sorted { $0.order < $1.order }
                    ForEach(sortedExercises) { exercise in
                        Section {
                            let sortedSets = exercise.sets.sorted { $0.order < $1.order }
                            ForEach(sortedSets) { set in
                                SetRow(set: set)
                            }
                            .onDelete { offsets in
                                deleteSets(offsets, from: exercise, sortedSets: sortedSets)
                            }

                            Button {
                                addSet(to: exercise)
                            } label: {
                                Label("Add Set", systemImage: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.blue)
                            }
                        } header: {
                            HStack {
                                Text(exercise.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                Spacer()
                                Button {
                                    modelContext.delete(exercise)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(workout.label.isEmpty ? workout.workoutTypeDisplayName : workout.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Minimize") { onMinimize() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        endWorkout()
                    } label: {
                        Text("End")
                            .foregroundStyle(.red)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }
            }
            .alert("Add Exercise", isPresented: $showingAddExercise) {
                TextField("Exercise name", text: $newExerciseName)
                Button("Add") { addExercise() }
                Button("Cancel", role: .cancel) { newExerciseName = "" }
            }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Stats header

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timer

    private func startTimer() {
        elapsed = Date().timeIntervalSince(workout.startedAt)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed = Date().timeIntervalSince(workout.startedAt)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Exercise / Set mutations

    private func addExercise() {
        let name = newExerciseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let exercise = Exercise(name: name, order: workout.exercises.count)
        modelContext.insert(exercise)
        workout.exercises.append(exercise)
        newExerciseName = ""
    }

    private func addSet(to exercise: Exercise) {
        let sorted = exercise.sets.sorted { $0.order < $1.order }
        let lastWeight = sorted.last?.weight ?? 0
        let lastUnit = sorted.last?.unit ?? "lbs"
        let set = WorkoutSet(reps: 0, weight: lastWeight, unit: lastUnit, order: exercise.sets.count)
        modelContext.insert(set)
        exercise.sets.append(set)
    }

    private func deleteSets(_ offsets: IndexSet, from exercise: Exercise, sortedSets: [WorkoutSet]) {
        for i in offsets {
            modelContext.delete(sortedSets[i])
        }
    }

    // MARK: - End workout

    private func endWorkout() {
        workout.endedAt = Date()
        try? modelContext.save()
        onEnd()
    }
}

// MARK: - SetRow

private struct SetRow: View {
    @Bindable var set: WorkoutSet

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TextField("0", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Text("reps")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                TextField("0", value: $set.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $set.unit) {
                    Text("lbs").tag("lbs")
                    Text("kg").tag("kg")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
```

- [ ] **Step 3: Update `DashboardView.swift`**

Replace `@StateObject private var workoutService = WorkoutSessionService()` with `@EnvironmentObject private var linker: WorkoutLinkerService`.

Update `loadHKWorkouts()` to call `linkPendingSessions()` first:
```swift
private func loadHKWorkouts() async {
    await linker.linkPendingSessions()
    let hkWorkoutService = HealthKitWorkoutService()
    hkWorkouts = (try? await hkWorkoutService.fetchTodayWorkouts()) ?? []

    let activityService = HealthKitActivityService()
    if let result = try? await activityService.fetchTodayStepsAndDistance() {
        stepCount = result.steps
        distanceMeters = result.distanceMeters
    }
}
```

Update the StartWorkoutSheet sheet (remove `service:` argument):
```swift
.sheet(isPresented: $showingStartWorkout, onDismiss: {
    if activeWorkout != nil { showingActiveWorkout = true }
}) {
    StartWorkoutSheet(activeWorkout: $activeWorkout)
}
```

Update the fullScreenCover (remove `service:` argument, remove `workoutService.reset()`):
```swift
.fullScreenCover(isPresented: $showingActiveWorkout) {
    if let workout = activeWorkout {
        ActiveWorkoutView(
            workout: workout,
            onMinimize: { showingActiveWorkout = false },
            onEnd: {
                showingActiveWorkout = false
                activeWorkout = nil
                Task { await loadHKWorkouts() }
            }
        )
    }
}
```

- [ ] **Step 4: Update `MeridianApp.swift`**

Create a shared container and inject the linker:

```swift
import SwiftUI
import SwiftData

@main
struct MeridianApp: App {
    private static let sharedContainer: ModelContainer = {
        try! ModelContainer(for: WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self, WorkoutTemplate.self, TemplateExercise.self)
    }()

    @StateObject private var linker = WorkoutLinkerService(modelContainer: sharedContainer)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(linker)
        }
        .modelContainer(MeridianApp.sharedContainer)
    }
}
```

- [ ] **Step 5: Build and confirm it compiles**

```
xcodebuild -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Meridian/Views/StartWorkoutSheet.swift Meridian/Views/ActiveWorkoutView.swift Meridian/Views/DashboardView.swift Meridian/MeridianApp.swift
git commit -m "feat: decouple workout start/end from HealthKit session management"
```

---

### Task 4: Add manual "Link to Watch workout" UI in `WorkoutLogSheet`

Users with an unlinked session can manually pick the Watch workout to attach.

**Files:**
- Modify: `Meridian/Views/WorkoutLogSheet.swift`

- [ ] **Step 1: Add state and helper methods**

Add to `WorkoutLogSheet`:
```swift
@State private var showingHKPicker = false
@State private var hkWorkoutsForPicker: [HKWorkout] = []
```

Add methods (after `addExercises(from:)`):
```swift
private func loadHKWorkoutsForPicker() {
    Task {
        hkWorkoutsForPicker = (try? await HealthKitWorkoutService().fetchRecentWorkouts(limit: 20)) ?? []
    }
}

private func linkSession(to hkWorkout: HKWorkout) {
    guard let session = workingSession else { return }
    session.healthKitUUID = hkWorkout.uuid
    session.activeCalories = hkWorkout.statistics(for: HKQuantityType(.activeEnergyBurned))?
        .sumQuantity()?.doubleValue(for: .kilocalorie())
    session.distanceMeters = hkWorkout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
        .sumQuantity()?.doubleValue(for: .meter())
    try? modelContext.save()
}
```

- [ ] **Step 2: Add "Link to Watch workout" to the bottom bar menu**

Inside the `Menu` in the bottom bar toolbar (after the existing two buttons), add:
```swift
if workingSession != nil && workingSession?.healthKitUUID == nil {
    Button {
        ensureSession()
        loadHKWorkoutsForPicker()
        showingHKPicker = true
    } label: {
        Label("Link to Watch workout", systemImage: "applewatch")
    }
}
```

- [ ] **Step 3: Add the HK picker sheet**

Add `.sheet(isPresented: $showingHKPicker)` after the existing `.sheet(isPresented: $showingTemplatePicker)`:
```swift
.sheet(isPresented: $showingHKPicker) {
    HKWorkoutPickerSheet(workouts: hkWorkoutsForPicker) { selected in
        linkSession(to: selected)
        showingHKPicker = false
    }
}
```

- [ ] **Step 4: Add `HKWorkoutPickerSheet` private struct** (at the bottom of `WorkoutLogSheet.swift`, before the final closing brace)

```swift
// MARK: - HKWorkoutPickerSheet

private struct HKWorkoutPickerSheet: View {
    let workouts: [HKWorkout]
    let onSelect: (HKWorkout) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Recent Workouts",
                        systemImage: "applewatch",
                        description: Text("No Apple Watch workouts found in the last 30 days.")
                    )
                } else {
                    List(workouts, id: \.uuid) { workout in
                        Button {
                            onSelect(workout)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(workout.workoutActivityType.meridianDisplayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                HStack(spacing: 4) {
                                    Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                                    Text("·")
                                    Text(String(format: "%02d:%02d", Int(workout.duration) / 60, Int(workout.duration) % 60))
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Link to Watch Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Build**

```
xcodebuild -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Meridian/Views/WorkoutLogSheet.swift
git commit -m "feat: add manual Watch workout linking to WorkoutLogSheet"
```

---

### Task 5: Remove dead code and update tests

Delete `WorkoutSessionService.swift` and `WorkoutMetricsAccumulator.swift`, remove tests that reference them, trim HK write permissions.

**Files:**
- Delete: `Meridian/Helpers/WorkoutSessionService.swift`
- Delete: `Meridian/Helpers/WorkoutMetricsAccumulator.swift`
- Delete: `MeridianTests/WorkoutMetricsAccumulatorTests.swift`
- Modify: `MeridianTests/WorkoutSessionTests.swift` (remove 2 tests that reference deleted code)
- Modify: `Meridian/Helpers/ActivityService.swift` (remove write types)

- [ ] **Step 1: Delete the three files**

```bash
rm Meridian/Helpers/WorkoutSessionService.swift
rm Meridian/Helpers/WorkoutMetricsAccumulator.swift
rm MeridianTests/WorkoutMetricsAccumulatorTests.swift
```

Also remove them from the Xcode project by deleting via Xcode or confirming they're removed from the build (since Xcode auto-discovers files via folder references if configured, but if using explicit file references, they must be removed from the `.xcodeproj` too). Check the project file after:
```bash
grep -c "WorkoutSessionService\|WorkoutMetricsAccumulator" Meridian.xcodeproj/project.pbxproj
```
If > 0, open Xcode and remove the file references from the project navigator (Delete → Remove Reference). Then rebuild.

- [ ] **Step 2: Update `WorkoutSessionTests.swift`**

Remove the two tests that reference deleted code:
- `handleHeartRateTakesMostRecent` (tests `WorkoutSessionService` internals — the logic now lives nowhere)
- `validLocationsFiltersInaccurateReadings` (tests `WorkoutSessionService.validLocations`)

The remaining tests (`workoutSetStoresData`, `cascadeDelete`, `emptySessionEnds`, `durationFormatted`) all test `WorkoutSession` model directly and stay unchanged.

- [ ] **Step 3: Trim HK write permissions in `ActivityService.swift`**

Remove all write types — the app no longer writes to HealthKit:

```swift
func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    let readTypes: Set<HKObjectType> = [
        HKObjectType.activitySummaryType(),
        HKQuantityType(.heartRate),
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType(.bodyMass),
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning)
    ]
    try await store.requestAuthorization(toShare: [], read: readTypes)
}
```

- [ ] **Step 4: Build and run all tests**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "Test Suite|passed|failed|error:"
```
Expected: all remaining tests pass, no compile errors.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: remove WorkoutSessionService and WorkoutMetricsAccumulator, app is now a pure exercise log"
```
