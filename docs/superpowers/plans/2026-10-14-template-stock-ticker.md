# Template Stock Ticker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display workout templates like a stock portfolio — each template shows a ticker symbol, sparkline of volume history, and latest total volume, both on a new dashboard card and in the template list.

**Architecture:** Add `TemplateWorkoutScore` (SwiftData model) to persist total volume per completed template session. Thread `templateID` through workout start so the score can be written on end. Render history via dynamic `@Query` in SwiftUI subviews; no service layer needed.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Charts, Swift Testing

**Spec:** `docs/superpowers/specs/2026-10-14-template-stock-ticker-design.md`

## Global Constraints

- All new SwiftData models must be added to the `ModelContainer` schema in `MeridianApp.swift`
- kg weights convert to lbs at `weight * 0.453592` before summing
- Volume formatted with commas, no decimals, unit suffix: e.g. `"12,450 lbs"`
- Sparkline color: green if `scores.last >= scores.first`, red otherwise
- Sparkline window: last 10 sessions
- Ticker symbol: multi-word → first letter of each word uppercased up to 4 chars; single word → first 4 chars uppercased
- Follow existing test style: `import Testing`, `@Suite`, `@Test`, `#expect`, in-memory `ModelContainer`
- No new subdirectories — new view files go directly in `Meridian/Views/`

## Review Focus

- **kg-only workout:** A session where all sets use "kg" — volume must convert correctly, not be zero or double-converted.
- **Template with no completed sessions:** `TemplateTickerRow` must render cleanly showing `--` for value and no sparkline, without crashing on empty scores array.
- **Ticker symbol with leading/trailing spaces or mixed-case input:** `tickerSymbol(for: " Push pull legs ")` must still produce `"PPL"`, not `"  P"`.
- **Score written for template-linked workout only:** Ending a free-form (non-template) workout must NOT create a `TemplateWorkoutScore`.
- **Dashboard card with fewer than 3 used templates:** `TemplatesPortfolioCard` must display however many exist (0, 1, 2) without crashing or showing phantom rows.

---

### Task 1: `TemplateWorkoutScore` model + `WorkoutSession.templateID`

**Files:**
- Create: `Meridian/Models/TemplateWorkoutScore.swift`
- Modify: `Meridian/Models/WorkoutSession.swift:5-36`
- Modify: `Meridian/MeridianApp.swift:8`
- Test: `MeridianTests/TemplateWorkoutScoreTests.swift`

**Interfaces:**
- Produces: `TemplateWorkoutScore` model with `id: UUID`, `templateID: UUID`, `templateName: String`, `sessionID: UUID`, `date: Date`, `totalVolume: Double`
- Produces: `WorkoutSession.templateID: UUID?` (nil by default)

- [ ] **Step 1: Write the failing test**

Create `MeridianTests/TemplateWorkoutScoreTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import Meridian

@Suite("TemplateWorkoutScore model")
struct TemplateWorkoutScoreTests {
    @Test("TemplateWorkoutScore persists all fields")
    func persistsAllFields() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TemplateWorkoutScore.self, configurations: config)
        let ctx = ModelContext(container)

        let templateID = UUID()
        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let score = TemplateWorkoutScore(
            templateID: templateID,
            templateName: "Push Pull Legs",
            sessionID: sessionID,
            date: date,
            totalVolume: 12450.0
        )
        ctx.insert(score)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<TemplateWorkoutScore>())
        #expect(fetched.count == 1)
        #expect(fetched[0].templateID == templateID)
        #expect(fetched[0].templateName == "Push Pull Legs")
        #expect(fetched[0].sessionID == sessionID)
        #expect(fetched[0].totalVolume == 12450.0)
    }

    @Test("WorkoutSession.templateID defaults to nil")
    func templateIDDefaultsNil() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "",
            startedAt: .now
        )
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched[0].templateID == nil)
    }
}
```

- [ ] **Step 2: Run test to confirm it fails**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/TemplateWorkoutScoreTests 2>&1 | tail -30
```
Expected: compile error — `TemplateWorkoutScore` not found.

- [ ] **Step 3: Create `TemplateWorkoutScore` model**

Create `Meridian/Models/TemplateWorkoutScore.swift`:
```swift
import Foundation
import SwiftData

@Model
final class TemplateWorkoutScore {
    var id: UUID
    var templateID: UUID
    var templateName: String
    var sessionID: UUID
    var date: Date
    var totalVolume: Double

    init(templateID: UUID, templateName: String, sessionID: UUID, date: Date, totalVolume: Double) {
        self.id = UUID()
        self.templateID = templateID
        self.templateName = templateName
        self.sessionID = sessionID
        self.date = date
        self.totalVolume = totalVolume
    }
}
```

- [ ] **Step 4: Add `templateID` to `WorkoutSession`**

In `Meridian/Models/WorkoutSession.swift`, add the property and update `init`:
```swift
// Add after `var activeCalories: Double?`:
var templateID: UUID?
```
In `init(workoutType:workoutTypeDisplayName:label:startedAt:)`, add:
```swift
self.templateID = nil
```

- [ ] **Step 5: Add `TemplateWorkoutScore` to ModelContainer schema**

In `Meridian/MeridianApp.swift`, update line 8:
```swift
try! ModelContainer(for: WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self, WorkoutTemplate.self, TemplateExercise.self, TemplateWorkoutScore.self)
```

- [ ] **Step 6: Run tests to confirm they pass**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/TemplateWorkoutScoreTests 2>&1 | tail -30
```
Expected: 2 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Meridian/Models/TemplateWorkoutScore.swift Meridian/Models/WorkoutSession.swift Meridian/MeridianApp.swift MeridianTests/TemplateWorkoutScoreTests.swift
git commit -m "feat: add TemplateWorkoutScore model and templateID to WorkoutSession"
```

---

### Task 2: Volume calculation + score writing on workout end

**Files:**
- Modify: `Meridian/Views/StartWorkoutSheet.swift:69-98`
- Modify: `Meridian/Views/ActiveWorkoutView.swift:160-164`
- Test: `MeridianTests/TemplateWorkoutScoreTests.swift` (append tests)

**Interfaces:**
- Consumes: `WorkoutSession.templateID: UUID?` (Task 1)
- Consumes: `TemplateWorkoutScore.init(templateID:templateName:sessionID:date:totalVolume:)` (Task 1)
- Produces: `totalVolumeInLbs(session: WorkoutSession) -> Double` — free function in `ActiveWorkoutView.swift`

- [ ] **Step 1: Write failing tests**

Append to `MeridianTests/TemplateWorkoutScoreTests.swift`:
```swift
@Test("totalVolumeInLbs sums weight × reps in lbs")
func totalVolumeAllLbs() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
    let ctx = ModelContext(container)

    let session = WorkoutSession(
        workoutType: "traditionalStrengthTraining",
        workoutTypeDisplayName: "Strength Training",
        label: "",
        startedAt: .now
    )
    let ex = Exercise(name: "Squat", order: 0)
    ex.sets = [
        WorkoutSet(reps: 10, weight: 135.0, unit: "lbs", order: 0),
        WorkoutSet(reps: 8, weight: 155.0, unit: "lbs", order: 1)
    ]
    session.exercises = [ex]
    ctx.insert(session)

    // 10*135 + 8*155 = 1350 + 1240 = 2590
    #expect(totalVolumeInLbs(session: session) == 2590.0)
}

@Test("totalVolumeInLbs converts kg sets to lbs")
func totalVolumeKg() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
    let ctx = ModelContext(container)

    let session = WorkoutSession(
        workoutType: "traditionalStrengthTraining",
        workoutTypeDisplayName: "Strength Training",
        label: "",
        startedAt: .now
    )
    let ex = Exercise(name: "Deadlift", order: 0)
    ex.sets = [
        WorkoutSet(reps: 5, weight: 100.0, unit: "kg", order: 0)
    ]
    session.exercises = [ex]
    ctx.insert(session)

    // 5 * 100 * 0.453592 = 226.796
    let result = totalVolumeInLbs(session: session)
    #expect(abs(result - 226.796) < 0.001)
}

@Test("totalVolumeInLbs returns 0 for session with no sets")
func totalVolumeEmpty() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
    let ctx = ModelContext(container)

    let session = WorkoutSession(
        workoutType: "other",
        workoutTypeDisplayName: "Other",
        label: "",
        startedAt: .now
    )
    ctx.insert(session)

    #expect(totalVolumeInLbs(session: session) == 0.0)
}
```

- [ ] **Step 2: Run to confirm they fail**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/TemplateWorkoutScoreTests 2>&1 | tail -30
```
Expected: compile error — `totalVolumeInLbs` not found.

- [ ] **Step 3: Add `totalVolumeInLbs` free function and score writing to `ActiveWorkoutView.swift`**

After the closing `}` of the `SetRow` struct at the bottom of `Meridian/Views/ActiveWorkoutView.swift`, add:
```swift
// MARK: - Volume calculation

/// Returns total volume in lbs for a session. Exposed at file scope for testability.
func totalVolumeInLbs(session: WorkoutSession) -> Double {
    session.exercises.reduce(0.0) { exSum, exercise in
        exSum + exercise.sets.reduce(0.0) { setSum, set in
            let lbs = set.unit == "kg" ? set.weight * 0.453592 : set.weight
            return setSum + lbs * Double(set.reps)
        }
    }
}
```

Replace `endWorkout()` in `ActiveWorkoutView`:
```swift
private func endWorkout() {
    workout.endedAt = Date()
    if let templateID = workout.templateID {
        let score = TemplateWorkoutScore(
            templateID: templateID,
            templateName: workout.label,
            sessionID: workout.id,
            date: workout.endedAt!,
            totalVolume: totalVolumeInLbs(session: workout)
        )
        modelContext.insert(score)
    }
    try? modelContext.save()
    onEnd()
}
```

- [ ] **Step 4: Set `templateID` when starting from template**

In `Meridian/Views/StartWorkoutSheet.swift`, inside `startFromTemplate(_ template:)`, add one line after `modelContext.insert(session)`:
```swift
session.templateID = template.id
```
The function becomes:
```swift
private func startFromTemplate(_ template: WorkoutTemplate) {
    let session = WorkoutSession(
        workoutType: template.workoutType,
        workoutTypeDisplayName: template.workoutTypeDisplayName,
        label: template.name,
        startedAt: .now
    )
    modelContext.insert(session)
    session.templateID = template.id   // ← new line

    let lastSession = allSessions.first(where: {
        $0.workoutType == template.workoutType && $0.endedAt != nil
    })
    // ... rest of function unchanged
```

- [ ] **Step 5: Run tests to confirm they pass**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/TemplateWorkoutScoreTests 2>&1 | tail -30
```
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Meridian/Views/ActiveWorkoutView.swift Meridian/Views/StartWorkoutSheet.swift MeridianTests/TemplateWorkoutScoreTests.swift
git commit -m "feat: compute and persist template volume score on workout end"
```

---

### Task 3: `tickerSymbol` function + `SparklineView`

**Files:**
- Create: `Meridian/Views/SparklineView.swift`
- Test: `MeridianTests/TemplateWorkoutScoreTests.swift` (append tests)

**Interfaces:**
- Produces: `tickerSymbol(for name: String) -> String` — free function in `SparklineView.swift`
- Produces: `SparklineView(values: [Double])` — SwiftUI View; green if `values.last >= values.first`, red otherwise; empty array renders nothing

- [ ] **Step 1: Write failing tests**

Append to `MeridianTests/TemplateWorkoutScoreTests.swift`:
```swift
@Test("tickerSymbol: multi-word name uses initials up to 4 chars")
func tickerMultiWord() {
    #expect(tickerSymbol(for: "Push Pull Legs") == "PPL")
    #expect(tickerSymbol(for: "Upper Body Strength Training") == "UBST")
}

@Test("tickerSymbol: single-word name uses first 4 chars uppercased")
func tickerSingleWord() {
    #expect(tickerSymbol(for: "Cardio") == "CARD")
    #expect(tickerSymbol(for: "Abs") == "ABS")
}

@Test("tickerSymbol: trims whitespace and handles mixed case")
func tickerTrimmed() {
    #expect(tickerSymbol(for: " push pull legs ") == "PPL")
}
```

- [ ] **Step 2: Run to confirm they fail**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/TemplateWorkoutScoreTests 2>&1 | tail -30
```
Expected: compile error — `tickerSymbol` not found.

- [ ] **Step 3: Create `SparklineView.swift`**

Create `Meridian/Views/SparklineView.swift`:
```swift
import SwiftUI
import Charts

// MARK: - Ticker symbol

/// Exposed at file scope for testability.
func tickerSymbol(for name: String) -> String {
    let words = name.trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
    if words.count > 1 {
        return String(words.prefix(4).compactMap { $0.first }.map { Character($0.uppercased()) })
    } else {
        return String(name.trimmingCharacters(in: .whitespaces).prefix(4)).uppercased()
    }
}

// MARK: - SparklineView

struct SparklineView: View {
    let values: [Double]

    private var color: Color {
        guard let first = values.first, let last = values.last else { return .green }
        return last >= first ? .green : .red
    }

    var body: some View {
        if values.isEmpty {
            EmptyView()
        } else {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Session", index),
                        y: .value("Volume", value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 60, height: 30)
        }
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/TemplateWorkoutScoreTests 2>&1 | tail -30
```
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Meridian/Views/SparklineView.swift MeridianTests/TemplateWorkoutScoreTests.swift
git commit -m "feat: add tickerSymbol function and SparklineView"
```

---

### Task 4: `TemplateTickerRow`

**Files:**
- Create: `Meridian/Views/TemplateTickerRow.swift`

**Interfaces:**
- Consumes: `tickerSymbol(for:)` (Task 3)
- Consumes: `SparklineView(values:)` (Task 3)
- Consumes: `TemplateWorkoutScore` model (Task 1)
- Produces: `TemplateTickerRow(template: WorkoutTemplate)` — SwiftUI View

- [ ] **Step 1: Create `TemplateTickerRow.swift`**

Create `Meridian/Views/TemplateTickerRow.swift`:
```swift
import SwiftUI
import SwiftData

struct TemplateTickerRow: View {
    let template: WorkoutTemplate

    @Query private var scores: [TemplateWorkoutScore]

    init(template: WorkoutTemplate) {
        self.template = template
        let id = template.id
        self._scores = Query(
            filter: #Predicate<TemplateWorkoutScore> { $0.templateID == id },
            sort: \.date,
            order: .forward
        )
    }

    private var recentScores: [Double] {
        Array(scores.suffix(10).map { $0.totalVolume })
    }

    private var latestVolume: Double? {
        scores.last?.totalVolume
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(tickerSymbol(for: template.name))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(template.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text(template.workoutTypeDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !recentScores.isEmpty {
                SparklineView(values: recentScores)
            }

            if let volume = latestVolume {
                Text(formatVolume(volume))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                    .frame(minWidth: 70, alignment: .trailing)
            } else {
                Text("--")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }

    private func formatVolume(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(formatted) lbs"
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add Meridian/Views/TemplateTickerRow.swift
git commit -m "feat: add TemplateTickerRow with dynamic score query and sparkline"
```

---

### Task 5: Update `TemplateListSheet` to ticker-row style

**Files:**
- Modify: `Meridian/Views/TemplateListSheet.swift`

**Interfaces:**
- Consumes: `TemplateTickerRow(template:)` (Task 4)
- Consumes: `TemplateWorkoutScore` model (Task 1)

- [ ] **Step 1: Replace `TemplateListSheet` content**

Replace the entire content of `Meridian/Views/TemplateListSheet.swift` with:
```swift
import SwiftUI
import SwiftData

struct TemplateListSheet: View {
    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Query(sort: \TemplateWorkoutScore.date, order: .reverse) private var scores: [TemplateWorkoutScore]
    @Environment(\.modelContext) private var modelContext

    @State private var editingTemplate: WorkoutTemplate? = nil
    @State private var showingNewTemplate = false

    /// Templates sorted: those with scores first (most recently used), then by creation date.
    private var sortedTemplates: [WorkoutTemplate] {
        let recentTemplateIDs: [UUID] = {
            var seen = Set<UUID>()
            return scores.compactMap { score -> UUID? in
                guard !seen.contains(score.templateID) else { return nil }
                seen.insert(score.templateID)
                return score.templateID
            }
        }()

        let withScores = recentTemplateIDs.compactMap { id in
            templates.first(where: { $0.id == id })
        }
        let withoutScores = templates.filter { t in
            !recentTemplateIDs.contains(t.id)
        }
        return withScores + withoutScores
    }

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
                        ForEach(sortedTemplates) { template in
                            Button {
                                editingTemplate = template
                            } label: {
                                TemplateTickerRow(template: template)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(sortedTemplates[i]) }
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

- [ ] **Step 2: Build to confirm it compiles**

```
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add Meridian/Views/TemplateListSheet.swift
git commit -m "feat: update TemplateListSheet to ticker-row style sorted by recency"
```

---

### Task 6: `TemplatesPortfolioCard`

**Files:**
- Create: `Meridian/Views/TemplatesPortfolioCard.swift`

**Interfaces:**
- Consumes: `TemplateTickerRow(template:)` (Task 4)
- Consumes: `TemplateWorkoutScore` model (Task 1)
- Produces: `TemplatesPortfolioCard(onTapAll: () -> Void)` — SwiftUI View; calls `onTapAll` to navigate to full list

- [ ] **Step 1: Create `TemplatesPortfolioCard.swift`**

Create `Meridian/Views/TemplatesPortfolioCard.swift`:
```swift
import SwiftUI
import SwiftData

struct TemplatesPortfolioCard: View {
    let onTapAll: () -> Void

    @Query(sort: \TemplateWorkoutScore.date, order: .reverse) private var scores: [TemplateWorkoutScore]
    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]

    /// Up to 3 most recently used templates, in order of last use.
    private var topTemplates: [WorkoutTemplate] {
        var seen = Set<UUID>()
        let recentIDs = scores.compactMap { score -> UUID? in
            guard !seen.contains(score.templateID) else { return nil }
            seen.insert(score.templateID)
            return score.templateID
        }.prefix(3)

        return recentIDs.compactMap { id in
            templates.first(where: { $0.id == id })
        }
    }

    var body: some View {
        Button(action: onTapAll) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Templates")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                if topTemplates.isEmpty {
                    Text("Complete a workout from a template to see your history here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(topTemplates) { template in
                            TemplateTickerRow(template: template)
                            if template.id != topTemplates.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add Meridian/Views/TemplatesPortfolioCard.swift
git commit -m "feat: add TemplatesPortfolioCard showing 3 most recently used templates"
```

---

### Task 7: Add `TemplatesPortfolioCard` to `DashboardView`

**Files:**
- Modify: `Meridian/Views/DashboardView.swift:75-80`

**Interfaces:**
- Consumes: `TemplatesPortfolioCard(onTapAll:)` (Task 6)

- [ ] **Step 1: Add portfolio card and sheet state to `DashboardView`**

In `Meridian/Views/DashboardView.swift`:

Add a `@State` variable for showing the template list. After `@State private var showingActiveWorkout = false` (line 14), add:
```swift
@State private var showingTemplates = false
```

Add `TemplatesPortfolioCard` just before `ActivitiesCard` (before line 75):
```swift
TemplatesPortfolioCard {
    showingTemplates = true
}
```

Add a sheet for it alongside the other `.sheet` modifiers (after `.sheet(isPresented: $showingWeightLog)`):
```swift
.sheet(isPresented: $showingTemplates) {
    TemplateListSheet()
}
```

- [ ] **Step 2: Build to confirm it compiles**

```
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 3: Run the full test suite**

```
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -40
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Meridian/Views/DashboardView.swift
git commit -m "feat: add TemplatesPortfolioCard to dashboard"
```
