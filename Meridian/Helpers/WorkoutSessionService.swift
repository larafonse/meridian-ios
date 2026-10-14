import Foundation
import HealthKit
import CoreLocation

@MainActor
final class WorkoutSessionService: NSObject, ObservableObject {
    @Published var currentBPM: Int? = nil
    @Published private(set) var metrics: WorkoutMetricsAccumulator?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var liveBuilder: HKLiveWorkoutBuilder?
    private var workoutActivityType: HKWorkoutActivityType?

    private var locationManager: CLLocationManager?
    private var routeBuilder: HKWorkoutRouteBuilder?

    nonisolated static func validLocations(_ locations: [CLLocation]) -> [CLLocation] {
        locations.filter { $0.horizontalAccuracy > 0 }
    }

    func reset() {
        stopLocationTracking()
        session?.end()
        session = nil
        liveBuilder = nil
        workoutActivityType = nil
        currentBPM = nil
        routeBuilder = nil
        metrics = nil
    }

    func start(configuration: HKWorkoutConfiguration) async throws {
        let startDate = Date()
        workoutActivityType = configuration.activityType

        async let profileFetch = fetchUserProfile()

        // iOS 17: HKWorkoutSession mirrors to Apple Watch, enabling real-time HR monitoring.
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        self.session = session
        self.liveBuilder = builder

        // HKLiveWorkoutDataSource auto-collects HR, energy, distance from Watch.
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: store,
            workoutConfiguration: configuration
        )
        session.delegate = self
        builder.delegate = self

        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)

        if configuration.activityType.isGPSTracked {
            startLocationTracking()
        }

        let (bodyMassKg, ageYears, isMale) = await profileFetch
        metrics = WorkoutMetricsAccumulator(
            activityType: configuration.activityType,
            bodyMassKg: bodyMassKg,
            ageYears: ageYears,
            isMale: isMale
        )
    }

    /// Ends the session and returns the saved HKWorkout UUID plus final display metrics.
    func finish() async throws -> (uuid: UUID?, distanceMeters: Double?, activeCalories: Double?) {
        let endDate = Date()
        guard let session, let builder = liveBuilder else { return (nil, nil, nil) }

        stopLocationTracking()

        // Capture display values before clearing metrics.
        let finalDistance = metrics?.distanceMeters
        let finalCalories = metrics?.activeCalories

        session.end()

        do {
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            if let workout, let routeBuilder {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
            self.session = nil
            self.liveBuilder = nil
            self.routeBuilder = nil
            self.metrics = nil
            workoutActivityType = nil
            return (workout?.uuid, finalDistance, finalCalories)
        } catch {
            self.session = nil
            self.liveBuilder = nil
            self.routeBuilder = nil
            self.metrics = nil
            workoutActivityType = nil
            return (nil, nil, nil)
        }
    }

    // MARK: - User profile

    private func fetchUserProfile() async -> (bodyMassKg: Double?, ageYears: Int?, isMale: Bool?) {
        guard HKHealthStore.isHealthDataAvailable() else { return (nil, nil, nil) }

        let bodyMassKg: Double? = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.bodyMass),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }

        let ageYears: Int? = try? store.dateOfBirthComponents().date
            .map { Calendar.current.dateComponents([.year], from: $0, to: Date()).year ?? 0 }

        let isMale: Bool? = try? {
            let sex = try store.biologicalSex().biologicalSex
            return sex == .male ? true : sex == .female ? false : nil
        }()

        return (bodyMassKg, ageYears, isMale)
    }

    // MARK: - GPS

    private func startLocationTracking() {
        routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        locationManager = manager
    }

    private func stopLocationTracking() {
        locationManager?.stopUpdatingLocation()
        locationManager = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutSessionService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {}
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutSessionService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  quantityType == HKQuantityType(.heartRate),
                  let stats = workoutBuilder.statistics(for: quantityType),
                  let qty = stats.mostRecentQuantity() else { continue }
            let bpm = Int(qty.doubleValue(for: HKUnit(from: "count/min")))
            let date = stats.mostRecentQuantityDateInterval()?.end ?? Date()
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentBPM = bpm
                metrics?.addHeartRateSample(bpm: bpm, at: date)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WorkoutSessionService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let valid = WorkoutSessionService.validLocations(locations)
        guard !valid.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.metrics?.addLocations(valid)
            try? await self?.routeBuilder?.insertRouteData(valid)
        }
    }
}

// MARK: - WorkoutType catalogue

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
