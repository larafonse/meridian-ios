# Workout Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add named workout templates with pre-defined exercises and optional defaults so users can start a session with exercises pre-filled from history or template defaults.

**Architecture:** Two new SwiftData models (`WorkoutTemplate`, `TemplateExercise`). `StartWorkoutSheet` gains a template section and a route to template management. Two new sheets handle list/edit of templates. Pre-fill logic lives in `StartWorkoutSheet`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, HealthKit

**Spec:** `docs/superpowers/specs/2026-10-13-workout-templates-design.md`

## Global Constraints

- iOS 17.0+, Swift 6 strict concurrency
- Existing card styling: white bg, `cornerRadius: 16`, 1pt border `Color(red: 0.898, green: 0.898, blue: 0.898)`, 20pt padding
- No third-party dependencies
- Workout type list lives in `WorkoutType.all` (12 entries) in `WorkoutSessionService.swift`
- Graceful degradation: template start must work even if HealthKit history query fails

## Review Focus

- **Template with no exercises starts correctly:** Session is created with zero exercises and opens `ActiveWorkoutView` normally. Task 3 tests this.
- **Pre-fill uses history over template defaults:** If last session has the exercise, history wins even if template also has defaults. Task 3 tests this.
- **Pre-fill falls back to template defaults when no history:** If exercise name is new, template defaults are used. Task 3 tests this.
- **Cascade delete on WorkoutTemplate:** Deleting a template must delete its `TemplateExercise` children. Task 1 tests this.
- **Duplicate exercise names in history:** If last session has two exercises named "Squat", pre-fill uses the first match. Acceptable; tested in Task 3.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Meridian/Models/WorkoutTemplate.swift` | SwiftData models: `WorkoutTemplate`, `TemplateExercise` |
| Create | `Meridian/Views/TemplateListSheet.swift` | List + delete templates, entry to editor |
| Create | `Meridian/Views/TemplateEditorSheet.swift` | Create/edit a template |
| Modify | `Meridian/Views/StartWorkoutSheet.swift` | Add template section + pre-fill logic |
| Modify | `Meridian/MeridianApp.swift` | Add new models to modelContainer |
| Create | `MeridianTests/WorkoutTemplateTests.swift` | Model + pre-fill logic tests |

---

## Task 1: WorkoutTemplate + TemplateExercise models

**Files:**
- Create: `Meridian/Models/WorkoutTemplate.swift`
- Create: `MeridianTests/WorkoutTemplateTests.swift`
- Modify: `Meridian/MeridianApp.swift`

**Interfaces:**
- Produces:
  - `WorkoutTemplate(name:workoutType:workoutTypeDisplayName:)` → `WorkoutTemplate`
  - `TemplateExercise(name:order:defaultReps:defaultWeight:defaultWeightUnit:)` → `TemplateExercise`

- [ ] **Step 1: Write failing tests**

Create `MeridianTests/WorkoutTemplateTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Meridian

@Suite("WorkoutTemplate model")
struct WorkoutTemplateTests {

    @Test("Template stores name and exercises")
    func templateStoresData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, TemplateExercise.self,
            configurations: config
        )
        let ctx = ModelContext(container)

        let template = WorkoutTemplate(
            name: "Leg Day",
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training"
        )
        let ex = TemplateExercise(name: "Squat", order: 0, defaultReps: 5, defaultWeight: 135.0, defaultWeightUnit: "lbs")
        template.exercises = [ex]
        ctx.insert(template)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Leg Day")
        #expect(fetched[0].exercises[0].defaultWeight == 135.0)
    }

    @Test("Cascade delete removes template exercises")
    func cascadeDeleteTemplate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, TemplateExercise.self,
            configurations: config
        )
        let ctx = ModelContext(container)

        let template = WorkoutTemplate(
            name: "Chest",
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training"
        )
        template.exercises = [TemplateExercise(name: "Bench Press", order: 0, defaultReps: nil, defaultWeight: nil, defaultWeightUnit: "lbs")]
        ctx.insert(template)
        try ctx.save()

        ctx.delete(template)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MeridianTests/WorkoutTemplateTests 2>&1 | grep -E "(error:|FAIL|cannot find)" | head -10
```

Expected: build error — `WorkoutTemplate` not found.

- [ ] **Step 3: Create `Meridian/Models/WorkoutTemplate.swift`**

```swift
import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var workoutType: String
    var workoutTypeDisplayName: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var exercises: [TemplateExercise]

    init(name: String, workoutType: String, workoutTypeDisplayName: String) {
        self.id = UUID()
        self.name = name
        self.workoutType = workoutType
        self.workoutTypeDisplayName = workoutTypeDisplayName
        self.createdAt = .now
        self.exercises = []
    }
}

@Model
final class TemplateExercise {
    var id: UUID
    var name: String
    var order: Int
    var defaultReps: Int?
    var defaultWeight: Double?
    var defaultWeightUnit: String

    init(name: String, order: Int, defaultReps: Int?, defaultWeight: Double?, defaultWeightUnit: String) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.defaultReps = defaultReps
        self.defaultWeight = defaultWeight
        self.defaultWeightUnit = defaultWeightUnit
    }
}
```

- [ ] **Step 4: Update `MeridianApp.swift`**

Change:
```swift
.modelContainer(for: [WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self])
```
to:
```swift
.modelContainer(for: [WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self, WorkoutTemplate.self, TemplateExercise.self])
```

- [ ] **Step 5: Regenerate project and run tests — expect 2 pass**

```bash
xcodegen generate --spec project.yml 2>&1 | tail -2
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MeridianTests/WorkoutTemplateTests 2>&1 | grep -E "(✔|✘|Test run with)" | head -10
```

Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Meridian/Models/WorkoutTemplate.swift Meridian/MeridianApp.swift MeridianTests/WorkoutTemplateTests.swift
git commit -m "feat: add WorkoutTemplate and TemplateExercise SwiftData models"
```

---

## Task 2: TemplateEditorSheet + TemplateListSheet

**Files:**
- Create: `Meridian/Views/TemplateEditorSheet.swift`
- Create: `Meridian/Views/TemplateListSheet.swift`

**Interfaces:**
- Consumes: `WorkoutTemplate`, `TemplateExercise` from Task 1; `WorkoutType.all` from `WorkoutSessionService.swift`
- Produces:
  - `TemplateEditorSheet(template: WorkoutTemplate?)` — nil = new template
  - `TemplateListSheet()`

- [ ] **Step 1: Create `Meridian/Views/TemplateEditorSheet.swift`**

```swift
import SwiftUI
import SwiftData

struct TemplateEditorSheet: View {
    /// Pass nil to create a new template, or an existing one to edit.
    let template: WorkoutTemplate?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: WorkoutType = WorkoutType.all[0]
    @State private var newExerciseName: String = ""
    @State private var showingAddExercise = false

    // Working copy of exercises for display; backed by the model
    @State private var workingTemplate: WorkoutTemplate? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("e.g. Leg Day", text: $name)
                }

                Section("Workout Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(WorkoutType.all) { type in
                            Label(type.displayName, systemImage: type.symbol).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let wt = workingTemplate, !wt.exercises.isEmpty {
                    Section("Exercises") {
                        ForEach(wt.exercises.sorted(by: { $0.order < $1.order })) { ex in
                            TemplateExerciseRow(exercise: ex)
                        }
                        .onDelete { offsets in
                            let sorted = wt.exercises.sorted(by: { $0.order < $1.order })
                            for i in offsets { modelContext.delete(sorted[i]) }
                        }
                    }
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if template == nil, let wt = workingTemplate {
                            modelContext.delete(wt)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        ensureWorkingTemplate()
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
        .onAppear { loadTemplate() }
    }

    // MARK: -

    private func loadTemplate() {
        if let t = template {
            workingTemplate = t
            name = t.name
            selectedType = WorkoutType.all.first(where: { $0.id == t.workoutType }) ?? WorkoutType.all[0]
        }
    }

    private func ensureWorkingTemplate() {
        if workingTemplate == nil {
            let wt = WorkoutTemplate(
                name: name.isEmpty ? "New Template" : name,
                workoutType: selectedType.id,
                workoutTypeDisplayName: selectedType.displayName
            )
            modelContext.insert(wt)
            workingTemplate = wt
        }
    }

    private func addExercise() {
        let exName = newExerciseName.trimmingCharacters(in: .whitespaces)
        guard !exName.isEmpty else { return }
        ensureWorkingTemplate()
        guard let wt = workingTemplate else { return }
        let ex = TemplateExercise(
            name: exName,
            order: wt.exercises.count,
            defaultReps: nil,
            defaultWeight: nil,
            defaultWeightUnit: "lbs"
        )
        modelContext.insert(ex)
        wt.exercises.append(ex)
        newExerciseName = ""
    }

    private func save() {
        ensureWorkingTemplate()
        guard let wt = workingTemplate else { return }
        wt.name = name.trimmingCharacters(in: .whitespaces)
        wt.workoutType = selectedType.id
        wt.workoutTypeDisplayName = selectedType.displayName
        try? modelContext.save()
        dismiss()
    }
}

private struct TemplateExerciseRow: View {
    @Bindable var exercise: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    TextField("Reps", value: $exercise.defaultReps, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text("reps")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    TextField("Weight", value: $exercise.defaultWeight, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $exercise.defaultWeightUnit) {
                        Text("lbs").tag("lbs")
                        Text("kg").tag("kg")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Create `Meridian/Views/TemplateListSheet.swift`**

```swift
import SwiftUI
import SwiftData

struct TemplateListSheet: View {
    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Environment(\.modelContext) private var modelContext

    @State private var editingTemplate: WorkoutTemplate? = nil
    @State private var showingNewTemplate = false

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to create your first workout template.")
                    )
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                editingTemplate = template
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                    Text("\(template.workoutTypeDisplayName) · \(template.exercises.count) exercises")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(templates[i]) }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewTemplate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingTemplate) { t in
                TemplateEditorSheet(template: t)
            }
            .sheet(isPresented: $showingNewTemplate) {
                TemplateEditorSheet(template: nil)
            }
        }
    }
}
```

- [ ] **Step 3: Regenerate and build check**

```bash
xcodegen generate --spec project.yml 2>&1 | tail -2
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)" | head -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Meridian/Views/TemplateEditorSheet.swift Meridian/Views/TemplateListSheet.swift
git commit -m "feat: add TemplateEditorSheet and TemplateListSheet"
```

---

## Task 3: Pre-fill logic + update StartWorkoutSheet

**Files:**
- Modify: `Meridian/Views/StartWorkoutSheet.swift`
- Modify: `MeridianTests/WorkoutTemplateTests.swift`

**Interfaces:**
- Consumes: `WorkoutTemplate`, `TemplateExercise` (Task 1); `TemplateListSheet` (Task 2)
- Produces: updated `StartWorkoutSheet` with template section + `startFromTemplate(_:)` method

- [ ] **Step 1: Write pre-fill tests**

Add to `MeridianTests/WorkoutTemplateTests.swift`:

```swift
// MARK: - Pre-fill logic tests

@Test("Pre-fill uses last session history over template defaults")
func preFillUsesHistory() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: WorkoutTemplate.self, TemplateExercise.self,
        WorkoutSession.self, Exercise.self, WorkoutSet.self,
        configurations: config
    )
    let ctx = ModelContext(container)

    // Last session with Squat sets
    let lastSession = WorkoutSession(
        workoutType: "traditionalStrengthTraining",
        workoutTypeDisplayName: "Strength Training",
        label: "Leg Day",
        startedAt: Date(timeIntervalSince1970: 0)
    )
    lastSession.endedAt = Date(timeIntervalSince1970: 3600)
    let historyExercise = Exercise(name: "Squat", order: 0)
    let historySet = WorkoutSet(reps: 8, weight: 185.0, unit: "lbs", order: 0)
    historyExercise.sets = [historySet]
    lastSession.exercises = [historyExercise]
    ctx.insert(lastSession)
    try ctx.save()

    // Template with different defaults
    let template = WorkoutTemplate(
        name: "Leg Day",
        workoutType: "traditionalStrengthTraining",
        workoutTypeDisplayName: "Strength Training"
    )
    let templateEx = TemplateExercise(name: "Squat", order: 0, defaultReps: 5, defaultWeight: 135.0, defaultWeightUnit: "lbs")
    template.exercises = [templateEx]

    let result = prefillSets(for: templateEx, lastSession: lastSession)
    #expect(result.count == 1)
    #expect(result[0].reps == 8)
    #expect(result[0].weight == 185.0)
}

@Test("Pre-fill falls back to template defaults when no history")
func preFillFallsBackToDefaults() throws {
    let template = WorkoutTemplate(
        name: "Chest",
        workoutType: "traditionalStrengthTraining",
        workoutTypeDisplayName: "Strength Training"
    )
    let templateEx = TemplateExercise(name: "Bench Press", order: 0, defaultReps: 10, defaultWeight: 135.0, defaultWeightUnit: "lbs")
    template.exercises = [templateEx]

    let result = prefillSets(for: templateEx, lastSession: nil)
    #expect(result.count == 1)
    #expect(result[0].reps == 10)
    #expect(result[0].weight == 135.0)
}

@Test("Pre-fill creates empty set when no history and no defaults")
func preFillCreatesEmptySetWhenNoData() {
    let templateEx = TemplateExercise(name: "New Exercise", order: 0, defaultReps: nil, defaultWeight: nil, defaultWeightUnit: "lbs")
    let result = prefillSets(for: templateEx, lastSession: nil)
    #expect(result.count == 1)
    #expect(result[0].reps == 0)
    #expect(result[0].weight == 0)
}

/// Pure function extracted from StartWorkoutSheet for testability.
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
```

- [ ] **Step 2: Run tests — expect 3 new pass (5 total in template suite)**

```bash
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MeridianTests/WorkoutTemplateTests 2>&1 | grep -E "(✔|✘|Test run with)" | head -10
```

Expected: 5 tests pass.

- [ ] **Step 3: Update `Meridian/Views/StartWorkoutSheet.swift`**

Replace the entire file:

```swift
import SwiftUI
import SwiftData
import HealthKit

struct StartWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let service: WorkoutSessionService
    @Binding var activeWorkout: WorkoutSession?

    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var selectedType: WorkoutType = WorkoutType.all[0]
    @State private var label: String = ""
    @State private var isStarting = false
    @State private var showingTemplates = false

    var body: some View {
        NavigationStack {
            List {
                if !templates.isEmpty {
                    Section("My Templates") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(templates) { template in
                                    TemplateCard(template: template) {
                                        Task { await startFromTemplate(template) }
                                    }
                                    .disabled(isStarting)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("Label (optional)") {
                    TextField("e.g. Leg Day", text: $label)
                }

                Section("Workout Type") {
                    ForEach(WorkoutType.all) { type in
                        Button {
                            selectedType = type
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: type.symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                    .frame(width: 28)
                                Text(type.displayName)
                                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                Spacer()
                                if selectedType.id == type.id {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await startBlank() }
                } label: {
                    Group {
                        if isStarting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Start Workout")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isStarting)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .background(Color(.systemGroupedBackground))
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

    // MARK: - Start blank

    private func startBlank() async {
        isStarting = true
        defer { isStarting = false }

        let session = WorkoutSession(
            workoutType: selectedType.id,
            workoutTypeDisplayName: selectedType.displayName,
            label: label.trimmingCharacters(in: .whitespaces),
            startedAt: .now
        )
        modelContext.insert(session)

        let config = HKWorkoutConfiguration()
        config.activityType = selectedType.hkType
        try? await service.start(configuration: config)

        activeWorkout = session
        dismiss()
    }

    // MARK: - Start from template

    private func startFromTemplate(_ template: WorkoutTemplate) async {
        isStarting = true
        defer { isStarting = false }

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

        let hkType = WorkoutType.all.first(where: { $0.id == template.workoutType })?.hkType ?? .other
        let config = HKWorkoutConfiguration()
        config.activityType = hkType
        try? await service.start(configuration: config)

        activeWorkout = session
        dismiss()
    }
}

// MARK: - Template card chip

private struct TemplateCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
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
            .frame(minWidth: 120, alignment: .leading)
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

- [ ] **Step 4: Build check**

```bash
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)" | head -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run full suite**

```bash
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "(Test run with|✘)" | head -5
```

Expected: all tests pass (19 total).

- [ ] **Step 6: Commit**

```bash
git add Meridian/Views/StartWorkoutSheet.swift MeridianTests/WorkoutTemplateTests.swift
git commit -m "feat: add template pre-fill logic and template section to StartWorkoutSheet"
```

- [ ] **Step 7: Push**

```bash
git push
```
