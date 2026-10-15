import SwiftUI
import SwiftData
import Charts
import UIKit
import HealthKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @Query(sort: \TemplateWorkoutScore.date, order: .forward) private var allScores: [TemplateWorkoutScore]
    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var orphanedSessions: [WorkoutSession]
    @Query(sort: \DashboardCard.sortOrder, order: .forward) private var dashboardCards: [DashboardCard]
    @State private var showingStartWorkout = false
    @State private var showingActiveWorkout = false
    @State private var showingTemplates = false
    @State private var selectedStat: StatItem? = nil
    @State private var showingCardEditor = false
    @State private var editingCard: DashboardCard? = nil
    // activeWorkout is @State (not persisted). If the OS terminates the process while a
    // workout is active, this reference is lost and the orphaned WorkoutSession (endedAt == nil)
    // is cleaned up on next launch via cleanupOrphanedSessions(). This is an accepted limitation.
    @State private var activeWorkout: WorkoutSession? = nil

    private var statItems: [StatItem] {
        let weightItem = StatItem.forWeight(entries: Array(entries))

        var seen = Set<UUID>()
        let recentIDs = allScores.reversed().compactMap { score -> UUID? in
            guard !seen.contains(score.templateID) else { return nil }
            seen.insert(score.templateID)
            return score.templateID
        }.prefix(3)

        var topTemplates = recentIDs.compactMap { id in
            templates.first(where: { $0.id == id })
        }
        if topTemplates.count < 3 {
            let usedIDs = Set(topTemplates.map(\.id))
            let unscored = templates.filter { !usedIDs.contains($0.id) }
            topTemplates += Array(unscored.prefix(3 - topTemplates.count))
        }

        let templateItems = topTemplates.map { StatItem.forTemplate($0, scores: allScores) }
        return [weightItem] + templateItems
    }

    // All available stats — used for the card editor and resolving custom card items
    private var allStatItems: [StatItem] {
        let weightItem = StatItem.forWeight(entries: Array(entries))
        let templateItems = templates.map { StatItem.forTemplate($0, scores: allScores) }
        return [weightItem] + templateItems
    }

    private func items(for card: DashboardCard) -> [StatItem] {
        allStatItems.filter { card.statTickers.contains($0.ticker) }
    }
    @State private var hkWorkouts: [HKWorkout] = []
    @State private var stepCount: Int = 0
    @State private var distanceMeters: Double = 0
    @EnvironmentObject private var linker: WorkoutLinkerService

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.961, green: 0.941, blue: 0.922, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.961, green: 0.941, blue: 0.922)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Meridian")
                        .font(Font.custom("PlayfairDisplay-Regular", size: 34).weight(.bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

                    ActivityRingsWidget()

                    StepsDistanceCardView(stepCount: stepCount, distanceMeters: distanceMeters)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                        )

                    ForEach(dashboardCards) { card in
                        let cardItems = items(for: card)
                        if !cardItems.isEmpty {
                            StatsPortfolioCard(
                                items: cardItems,
                                title: card.name,
                                onTapStat: { selectedStat = $0 },
                                onEdit: {
                                    editingCard = card
                                    showingCardEditor = true
                                },
                                onDelete: {
                                    modelContext.delete(card)
                                }
                            )
                        }
                    }

                    addCardButton

                    StatsPortfolioCard(
                        items: statItems,
                        onTapAll: { showingTemplates = true },
                        onTapStat: { selectedStat = $0 }
                    )

                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .refreshable { await loadHKWorkouts() }

            addButton
        }
        .task { await loadHKWorkouts() }
        .onAppear {
            cleanupOrphanedSessions()
            cleanupOrphanedScores()
            backfillMissingScores()
        }
        .sheet(isPresented: $showingTemplates) {
            TemplateListSheet()
        }
        .sheet(isPresented: $showingCardEditor, onDismiss: { editingCard = nil }) {
            CardEditorSheet(
                availableStats: allStatItems,
                existingCard: editingCard,
                nextSortOrder: (dashboardCards.map(\.sortOrder).max() ?? -1) + 1
            )
        }
        .sheet(item: $selectedStat) { stat in
            switch stat.detail {
            case .weight:
                WeightDetailSheet()
            case .template(let template):
                TemplateDetailSheet(template: template)
            }
        }
        .sheet(isPresented: $showingStartWorkout, onDismiss: {
            if activeWorkout != nil { showingActiveWorkout = true }
        }) {
            StartWorkoutSheet(activeWorkout: $activeWorkout)
        }
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
    }

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

    private func cleanupOrphanedSessions() {
        for session in orphanedSessions {
            modelContext.delete(session)
        }
    }

    private func cleanupOrphanedScores() {
        guard let allSessions = try? modelContext.fetch(FetchDescriptor<WorkoutSession>()),
              let allScores = try? modelContext.fetch(FetchDescriptor<TemplateWorkoutScore>()) else { return }
        let existingSessionIDs = Set(allSessions.map(\.id))
        var didDelete = false
        for score in allScores where !existingSessionIDs.contains(score.sessionID) {
            modelContext.delete(score)
            didDelete = true
        }
        if didDelete { try? modelContext.save() }
    }

    private func backfillMissingScores() {
        guard let allSessions = try? modelContext.fetch(FetchDescriptor<WorkoutSession>()) else { return }
        let completedTemplateSessions = allSessions.filter { $0.templateID != nil && $0.endedAt != nil }
        guard !completedTemplateSessions.isEmpty else { return }

        let existingScores = (try? modelContext.fetch(FetchDescriptor<TemplateWorkoutScore>())) ?? []
        let coveredSessionIDs = Set(existingScores.map(\.sessionID))

        var didInsert = false
        for session in completedTemplateSessions {
            guard let templateID = session.templateID,
                  !coveredSessionIDs.contains(session.id) else { continue }
            let score = TemplateWorkoutScore(
                templateID: templateID,
                templateName: session.label,
                sessionID: session.id,
                date: session.endedAt!,
                totalVolume: totalVolumeInLbs(session: session)
            )
            modelContext.insert(score)
            didInsert = true
        }
        if didInsert { try? modelContext.save() }
    }

    private var addCardButton: some View {
        Button {
            editingCard = nil
            showingCardEditor = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add Card")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color(red: 0.898, green: 0.898, blue: 0.898),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            showingStartWorkout = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }
}
