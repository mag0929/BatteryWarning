import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("門檻持久化")
struct ThresholdStoreTests {
    /// Each test gets its own defaults suite so `UserDefaults.standard` is
    /// never touched.
    private func makeStore() -> (ThresholdStore, UserDefaults) {
        let suite = "bw.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (ThresholdStore(defaults: defaults), defaults)
    }

    @Test func testDefaultIsTwentyWhenNothingStored() {
        let (store, _) = makeStore()
        #expect(store.current.alertPercent == 20)
        #expect(store.current.clearPercent == 25)
    }

    @Test func testStepPersistsAndNotifies() {
        let (store, defaults) = makeStore()
        var notified: Int?
        store.onChange = { notified = $0.alertPercent }

        store.step(by: AlertThresholds.step)
        #expect(store.current.alertPercent == 25)
        #expect(defaults.integer(forKey: ThresholdStore.defaultsKey) == 25)
        #expect(notified == 25)

        store.step(by: -AlertThresholds.step)
        #expect(store.current.alertPercent == 20)
        #expect(notified == 20)
    }

    @Test func testStepAtBoundsDoesNotWrite() {
        let (store, defaults) = makeStore()

        // Walk up to the ceiling the way the menu does: 20 -> 50 in six steps.
        for _ in 0..<6 { store.step(by: AlertThresholds.step) }
        #expect(store.current.alertPercent == AlertThresholds.maxAlert)

        var notified = 0
        store.onChange = { _ in notified += 1 }

        // A seventh upward step is out of range: no write, no notification.
        store.step(by: AlertThresholds.step)
        #expect(store.current.alertPercent == AlertThresholds.maxAlert)
        #expect(defaults.integer(forKey: ThresholdStore.defaultsKey) == AlertThresholds.maxAlert)
        #expect(notified == 0, "a rejected step must not notify observers")

        // Walk down to the floor: 50 -> 5 in nine steps.
        for _ in 0..<9 { store.step(by: -AlertThresholds.step) }
        #expect(store.current.alertPercent == AlertThresholds.minAlert)
        #expect(notified == 9)

        // One more downward step is out of range.
        store.step(by: -AlertThresholds.step)
        #expect(store.current.alertPercent == AlertThresholds.minAlert)
        #expect(defaults.integer(forKey: ThresholdStore.defaultsKey) == AlertThresholds.minAlert)
        #expect(notified == 9, "still only the nine in-range steps notified")
    }

    @Test func testOversizedSingleStepIsRejectedWithoutClamping() {
        let (store, defaults) = makeStore()
        var notified = 0
        store.onChange = { _ in notified += 1 }

        // +100 in one go lands outside the range, so nothing is written —
        // the step never silently clamps to the ceiling.
        store.step(by: AlertThresholds.step * 20)
        #expect(store.current.alertPercent == 20)
        #expect(defaults.object(forKey: ThresholdStore.defaultsKey) == nil)
        #expect(notified == 0)
    }

    @Test func testOutOfRangeStoredValueFallsBackToDefault() {
        for bad in [200, 1000, -5, 0, 4] {
            let suite = "bw.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(bad, forKey: ThresholdStore.defaultsKey)
            let store = ThresholdStore(defaults: defaults)
            #expect(
                store.current.alertPercent == AlertThresholds.defaultAlertPercent,
                "stored \(bad) should fall back to 20"
            )
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @Test func testNonIntegerStoredValueFallsBackToDefault() {
        let suite = "bw.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("not a number", forKey: ThresholdStore.defaultsKey)
        let store = ThresholdStore(defaults: defaults)
        #expect(store.current.alertPercent == AlertThresholds.defaultAlertPercent)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func testInRangeStoredValueIsPreserved() {
        let suite = "bw.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(30, forKey: ThresholdStore.defaultsKey)
        let store = ThresholdStore(defaults: defaults)
        #expect(store.current.alertPercent == 30)
        #expect(store.current.clearPercent == 35)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func testSurvivesRelaunch() {
        let suite = "bw.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let first = ThresholdStore(defaults: defaults)
        first.step(by: AlertThresholds.step * 2)   // 20 -> 30

        let second = ThresholdStore(defaults: defaults)   // "relaunch"
        #expect(second.current.alertPercent == 30)
        #expect(second.current.clearPercent == 35)

        defaults.removePersistentDomain(forName: suite)
    }
}