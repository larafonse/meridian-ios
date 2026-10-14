import Foundation
import HealthKit
import CoreLocation
import Combine

@MainActor
final class WorkoutSessionService: NSObject, ObservableObject {
    @Published var currentBPM: Int? = nil
    @Published private(set) var metrics: WorkoutMetricsAccumulator?

    private let store = HKHealthStore()
    private var builder: HKWorkoutBuilder?
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
        builder = nil
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

        // Fetch user profile in parallel with builder setup so the HR observer
        // starts without waiting for HealthKit characteristic reads.
        async let profileFetch = fetchUserProfile()

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        self.builder = builder
        try await builder.beginCollection(at: startDate)
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

    /// Returns the saved HKWorkout UUID, or nil if HealthKit write fails.
    /// Also returns final distance and calorie values for saving to the model.
    func finish() async throws -> (uuid: UUID?, distanceMeters: Double?, activeCalories: Double?) {
        let endDate = Date()
        guard let builder else { return (nil, nil, nil) }

        stopHeartRateObserver()
        stopLocationTracking()

        let finalDistance = metrics?.distanceMeters
        let finalCalories = metrics?.activeCalories

        if let start = workoutStartDate {
            let hrSamples = await fetchHeartRateSamples(from: start, to: endDate)
            if !hrSamples.isEmpty {
                try? await builder.addSamples(hrSamples)
            }
        }

        // Write distance + calorie samples before ending collection
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
            self.builder = nil
            self.routeBuilder = nil
            self.metrics = nil
            workoutStartDate = nil
            workoutActivityType = nil
            return (workout?.uuid, finalDistance, finalCalories)
        } catch {
            self.builder = nil
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

    // MARK: - Heart Rate

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
            Task { @MainActor [weak self] in self?.handleHeartRateSamples(samples) }
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor [weak self] in self?.handleHeartRateSamples(samples) }
        }
        store.execute(query)
        hrQuery = query
    }

    private func stopHeartRateObserver() {
        if let q = hrQuery { store.stop(q) }
        hrQuery = nil
    }

    private func handleHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }
        let latest = samples.max(by: { $0.endDate < $1.endDate })
        if let latest {
            let bpm = Int(latest.quantity.doubleValue(for: HKUnit(from: "count/min")))
            currentBPM = bpm
            metrics?.addHeartRateSample(bpm: bpm, at: latest.endDate)
        }
    }

    private func fetchHeartRateSamples(from start: Date, to end: Date) async -> [HKSample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
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
