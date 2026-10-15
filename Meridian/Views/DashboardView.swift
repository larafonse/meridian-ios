import SwiftUI
import SwiftData
import Charts
import UIKit
import HealthKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var orphanedSessions: [WorkoutSession]
    @State private var showingAddSheet = false
    @State private var showingWeightLog = false
    @State private var showingStartWorkout = false
    @State private var showingActiveWorkout = false
    @State private var showingTemplates = false
    @State private var detailTemplate: WorkoutTemplate? = nil
    // activeWorkout is @State (not persisted). If the OS terminates the process while a
    // workout is active, this reference is lost and the orphaned WorkoutSession (endedAt == nil)
    // is cleaned up on next launch via cleanupOrphanedSessions(). This is an accepted limitation.
    @State private var activeWorkout: WorkoutSession? = nil
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

                    HStack(spacing: 12) {
                        Button { showingWeightLog = true } label: {
                            WeightChartView(entries: entries)
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(.plain)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity)

                        StepsDistanceCardView(stepCount: stepCount, distanceMeters: distanceMeters)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity)
                    }

                    TemplatesPortfolioCard(
                        onTapAll: { showingTemplates = true },
                        onTapTemplate: { detailTemplate = $0 }
                    )

                    ActivitiesCard(
                        activeWorkout: $activeWorkout,
                        hkWorkouts: hkWorkouts,
                        onStart: { showingStartWorkout = true },
                        onResume: { showingActiveWorkout = true }
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
            backfillMissingScores()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEntrySheet()
        }
        .sheet(isPresented: $showingWeightLog) {
            WeightLogSheet()
        }
        .sheet(isPresented: $showingTemplates) {
            TemplateListSheet()
        }
        .sheet(item: $detailTemplate) { template in
            TemplateDetailSheet(template: template)
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

    private var addButton: some View {
        Button {
            showingAddSheet = true
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
