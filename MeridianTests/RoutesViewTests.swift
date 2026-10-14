import Testing
import HealthKit
@testable import Meridian

@Suite("RoutesView GPS filter")
struct RoutesViewTests {

    @Test("cycling is GPS tracked")
    func cyclingIsGPSTracked() {
        #expect(HKWorkoutActivityType.cycling.isGPSTracked == true)
    }

    @Test("running is GPS tracked")
    func runningIsGPSTracked() {
        #expect(HKWorkoutActivityType.running.isGPSTracked == true)
    }

    @Test("walking is GPS tracked")
    func walkingIsGPSTracked() {
        #expect(HKWorkoutActivityType.walking.isGPSTracked == true)
    }

    @Test("strength training is not GPS tracked")
    func strengthTrainingIsNotGPSTracked() {
        #expect(HKWorkoutActivityType.traditionalStrengthTraining.isGPSTracked == false)
    }

    @Test("swimming is not GPS tracked")
    func swimmingIsNotGPSTracked() {
        #expect(HKWorkoutActivityType.swimming.isGPSTracked == false)
    }
}
