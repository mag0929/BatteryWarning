import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("登入開關")
struct LoginItemControllerTests {

    final class FakeRegistrar: LoginItemRegistering {
        var isRegistered: Bool
        var registerShouldThrow: Error?
        private(set) var registerCount = 0
        private(set) var unregisterCount = 0

        init(isRegistered: Bool = false, registerShouldThrow: Error? = nil) {
            self.isRegistered = isRegistered
            self.registerShouldThrow = registerShouldThrow
        }

        func register() throws {
            registerCount += 1
            if let registerShouldThrow { throw registerShouldThrow }
            isRegistered = true
        }

        func unregister() {
            unregisterCount += 1
            isRegistered = false
        }
    }

    struct Rejected: Error {}

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "bw.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test func testReconcileRespectsExternalDisable() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Preference says enabled, but the user removed the app from System
        // Settings. The registration is genuinely gone.
        defaults.set(true, forKey: LoginItemController.preferenceKey)
        let registrar = FakeRegistrar(isRegistered: false)
        let controller = LoginItemController(registrar: registrar, defaults: defaults)

        let result = controller.reconcile()

        #expect(result == false, "actual registration wins")
        #expect(controller.isEnabled == false)
        #expect(registrar.registerCount == 0, "must not re-register behind the user's back")
        #expect(
            defaults.bool(forKey: LoginItemController.preferenceKey) == false,
            "the stored preference is corrected to match reality"
        )
    }

    @Test func testReconcileAdoptsEnabledRegistration() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let registrar = FakeRegistrar(isRegistered: true)
        let controller = LoginItemController(registrar: registrar, defaults: defaults)

        #expect(controller.reconcile() == true)
        #expect(controller.isEnabled)
        #expect(registrar.registerCount == 0)
    }

    @Test func testToggleOnRegisters() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let registrar = FakeRegistrar(isRegistered: false)
        let controller = LoginItemController(registrar: registrar, defaults: defaults)
        controller.reconcile()

        var reported: [Bool] = []
        controller.onChange = { reported.append($0) }
        controller.setEnabled(true)

        #expect(registrar.registerCount == 1)
        #expect(controller.isEnabled)
        #expect(defaults.bool(forKey: LoginItemController.preferenceKey))
        #expect(reported == [true])
    }

    @Test func testToggleOffUnregisters() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let registrar = FakeRegistrar(isRegistered: true)
        let controller = LoginItemController(registrar: registrar, defaults: defaults)
        controller.reconcile()
        controller.setEnabled(false)

        #expect(registrar.unregisterCount == 1)
        #expect(controller.isEnabled == false)
        #expect(defaults.bool(forKey: LoginItemController.preferenceKey) == false)
    }

    @Test func testRegistrationFailureLeavesToggleOffAndDoesNotThrow() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let registrar = FakeRegistrar(isRegistered: false, registerShouldThrow: Rejected())
        let controller = LoginItemController(registrar: registrar, defaults: defaults)
        controller.reconcile()

        // Must not throw and must not claim success.
        controller.setEnabled(true)

        #expect(controller.isEnabled == false)
        #expect(defaults.bool(forKey: LoginItemController.preferenceKey) == false)
    }

    @Test func testUnregisterFailureStillReportsOff() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Unregister leaves it registered -> the toggle must not claim success.
        final class StubbornRegistrar: LoginItemRegistering {
            var isRegistered = true
            func register() throws {}
            func unregister() {}
        }
        let registrar = StubbornRegistrar()
        let controller = LoginItemController(registrar: registrar, defaults: defaults)
        controller.reconcile()
        controller.setEnabled(false)

        #expect(controller.isEnabled == true, "still registered, so still reported on")
    }
}