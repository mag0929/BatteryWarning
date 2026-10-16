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

        // 偏好值說是開啟的，但使用者已從「系統設定」把 App 移除，
        // 註冊確實不見了。這種情況下開關必須顯示為關閉。
        defaults.set(true, forKey: LoginItemController.preferenceKey)
        let registrar = FakeRegistrar(isRegistered: false)
        let controller = LoginItemController(registrar: registrar, defaults: defaults)

        let result = controller.reconcile()

        #expect(result == false, "以實際註冊狀態為準")
        #expect(controller.isEnabled == false)
        #expect(registrar.registerCount == 0, "不得在使用者不知情下重新註冊")
        #expect(
            defaults.bool(forKey: LoginItemController.preferenceKey) == false,
            "存檔的偏好值已修正成與事實一致"
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

        // 不得拋錯，也不得宣稱成功。
        controller.setEnabled(true)

        #expect(controller.isEnabled == false)
        #expect(defaults.bool(forKey: LoginItemController.preferenceKey) == false)
    }

    @Test func testUnregisterFailureStillReportsOff() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // 取消註冊後仍然留在註冊狀態 → 開關不得宣稱成功。
        final class StubbornRegistrar: LoginItemRegistering {
            var isRegistered = true
            func register() throws {}
            func unregister() {}
        }
        let registrar = StubbornRegistrar()
        let controller = LoginItemController(registrar: registrar, defaults: defaults)
        controller.reconcile()
        controller.setEnabled(false)

        #expect(controller.isEnabled == true, "仍然註冊中，因此仍回報為開啟")
    }
}