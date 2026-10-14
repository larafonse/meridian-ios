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
    private var hrQuery: HKAnchoredObjectQuery?
    private var workoutStartDate: Date?
    private var workoutActivityType: HKWorkoutActivityType?

    private var locationManager: CLLocationManager?
    private var routeBuilder: HKWorkoutRouteBuilder?

    nonisolated static func validLocations(_ locations: [CLLocation]) -> [CLLocation] {
        locations.filter { $0.horizontalAccuracy > 0 }
    }

    func reset() {
        stopHeartRateObserver()
        stopLocationTracking()
        session?.end()
        session = nil
        liveBuilder = nil
        workoutStartDate = nil
        workoutActivityType = nil
        currentBPM = nil
        routeBuilder = nil
        metrics = nil
    }

    func start(configuration: HKWorkoutConfiguration) async throws {
        let startDate = Date()
        workoutStartDate = startDate
        workoutActivityType = configuration.activityType

        async let profileFetch = fetchUserProfile()

        // HKWorkoutSession on iPhone (iOS 26) mirrors to Apple Watch for real-time HR.
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        self.session = session
        self.liveBuilder = builder

        // Only let the data source collect HR — we write energy/distance manually in finish()
        // to avoid double-counting and ensure data is available without a Watch.
        let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        dataSource.disableCollection(for: HKQuantityType(.activeEnergyBurned))
        dataSource.disableCollection(for: HKQuantityType(.distanceWalkingRunning))
        dataSource.disableCollection(for: HKQuantityType(.distanceCycling))
        builder.dataSource = dataSource

        session.delegate = self
        builder.delegate = self

        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)

        // Belt-and-suspenders HR observer: catches samples whether they arrive via
        // the live session delegate or the Watch's background HealthKit writes.
        startHeartRateObserver(from: startDate)

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

        stopHeartRateObserver()
        stopLocationTracking()

        let finalDistance = metrics?.distanceMeters
        let finalCalories = metrics?.activeCalories

        session.end()

        // Write calorie/distance samples so Strava and HealthKit show stats.
        var statSamples: [HKSample] = []
        if let kcal = finalCalories, kcal > 0 {
            let energySample = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: workoutStartDate ?? endDate,
                end: endDate
            )
            statSamples.append(energySample)
        }
        if let metres = finalDistance, metres > 0, let activityType = workoutActivityType {
            let distanceType: HKQuantityType = activityType == .cycling
                ? HKQuantityType(.distanceCycling)
                : HKQuantityType(.distanceWalkingRunning)
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: metres),
                start: workoutStartDate ?? endDate,
                end: endDate
            )
            statSamples.append(distanceSample)
        }
        if !statSamples.isEmpty {
            try? await builder.addSamples(statSamples)
        }

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
            workoutStartDate = nil
            workoutActivityType = nil
            return (workout?.uuid, finalDistance, finalCalories)
        } catch {
            self.session = nil
            self.liveBuilder = nil
            self.routeBuilder = nil
            self.metrics = nil
            workoutStartDate = nil
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

    // MARK: - Heart Rate (fallback observer)

    private func startHeartRateObserver(from startDate: Date) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor [weak self] in self?.handleHRSamples(samples) }
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor [weak self] in self?.handleHRSamples(samples) }
        }
        store.execute(query)
        hrQuery = query
    }

    private func stopHeartRateObserver() {
        if let q = hrQuery { store.stop(q) }
        hrQuery = nil
    }

    private func handleHRSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }
        guard let latest = samples.max(by: { $0.endDate < $1.endDate }) else { return }
        let bpm = Int(latest.quantity.doubleValue(for: HKUnit(from: "count/min")))
        currentBPM = bpm
        metrics?.updateHeartRate(bpm: bpm)
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
                  let stats = workoutBuilder.statistics(for: quantityType) else { continue }
            // mostRecentQuantity() requires .mostRecent statistics option; fall back to average.
            let qty = stats.mostRecentQuantity() ?? stats.averageQuantity()
            guard let qty else { continue }
            let bpm = Int(qty.doubleValue(for: HKUnit(from: "count/min")))
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentBPM = bpm
                metrics?.updateHeartRate(bpm: bpm)
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
