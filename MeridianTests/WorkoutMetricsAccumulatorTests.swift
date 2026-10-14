import Testing
import CoreLocation
import HealthKit
@testable import Meridian

@Suite("WorkoutMetricsAccumulator")
struct WorkoutMetricsAccumulatorTests {

    // MARK: - Distance

    @Test("two locations 100 m apart accumulate ~100 m distance")
    @MainActor func distanceAccumulatesTwoPoints() {
        let acc = WorkoutMetricsAccumulator(
            activityType: .walking,
            bodyMassKg: 70, ageYears: 30, isMale: true
        )
        let a = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let b = CLLocation(latitude: 37.7758, longitude: -122.4194) // ~100 m north
        acc.addLocations([a, b])
        #expect(acc.distanceMeters > 90 && acc.distanceMeters < 110)
    }

    @Test("non-GPS workout type ignores location updates")
    @MainActor func nonGPSIgnoresLocations() {
        let acc = WorkoutMetricsAccumulator(
            activityType: .traditionalStrengthTraining,
            bodyMassKg: 70, ageYears: 30, isMale: true
        )
        let a = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let b = CLLocation(latitude: 37.7758, longitude: -122.4194)
        acc.addLocations([a, b])
        #expect(acc.distanceMeters == 0)
    }

    @Test("reset clears distance")
    @MainActor func resetClearsDistance() {
        let acc = WorkoutMetricsAccumulator(
            activityType: .running,
            bodyMassKg: 70, ageYears: 30, isMale: true
        )
        let a = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let b = CLLocation(latitude: 37.7758, longitude: -122.4194)
        acc.addLocations([a, b])
        acc.reset()
        #expect(acc.distanceMeters == 0)
    }

    // MARK: - Calories (HR-based)

    @Test("HR-based calories accumulate over time")
    @MainActor func hrCaloriesAccumulate() {
        let acc = WorkoutMetricsAccumulator(
            activityType: .running,
            bodyMassKg: 75, ageYears: 30, isMale: true
        )
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 60) // 1 minute later
        acc.addHeartRateSample(bpm: 150, at: t0)
        acc.addHeartRateSample(bpm: 150, at: t1)
        // Keytel male: (-55.0969 + 0.6309*150 + 0.1988*75 + 0.2017*30) / 4.184 ≈ 13.8 kcal/min
        #expect(acc.activeCalories > 10 && acc.activeCalories < 20)
    }

    @Test("first HR sample initialises clock without adding calories")
    @MainActor func firstSampleNonAdditive() {
        let acc = WorkoutMetricsAccumulator(
            activityType: .running,
            bodyMassKg: 75, ageYears: 30, isMale: true
        )
        acc.addHeartRateSample(bpm: 150, at: Date())
        #expect(acc.activeCalories == 0)
    }

    // MARK: - MET fallback

    @Test("MET fallback fires when body mass is nil")
    @MainActor func metFallbackWhenNoBodyMass() {
        let acc = WorkoutMetricsAccumulator(
            activityType: .walking,
            bodyMassKg: nil, ageYears: nil, isMale: nil
        )
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 60)
        acc.addHeartRateSample(bpm: 100, at: t0)
        acc.addHeartRateSample(bpm: 100, at: t1)
        // MET fallback: 3.5 * 70 / 60 ≈ 4.08 kcal/min
        #expect(acc.activeCalories > 2 && acc.activeCalories < 8)
    }

    @Test("reset clears calories")
    @MainActor func resetClearsCalories() {
        let acc = WorkoutMetricsAccumulator(
            activityType: .running,
            bodyMassKg: 75, ageYears: 30, isMale: true
        )
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 60)
        acc.addHeartRateSample(bpm: 150, at: t0)
        acc.addHeartRateSample(bpm: 150, at: t1)
        acc.reset()
        #expect(acc.activeCalories == 0)
    }

    // MARK: - MET values

    @Test("met returns expected value for walking")
    func metWalking() {
        #expect(WorkoutMetricsAccumulator.met(for: .walking) == 3.5)
    }

    @Test("met returns expected value for running")
    func metRunning() {
        #expect(WorkoutMetricsAccumulator.met(for: .running) == 8.0)
    }

    @Test("met returns expected value for cycling")
    func metCycling() {
        #expect(WorkoutMetricsAccumulator.met(for: .cycling) == 6.0)
    }
}
