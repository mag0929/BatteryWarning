import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("門檻持久化")
struct ThresholdStoreTests {
    /// 每個測試都有自己的 defaults suite，因此 `UserDefaults.standard`
    /// 完全不會被碰到。
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

        // 像選單那樣一路調到上限：20 → 50，六步。
        for _ in 0..<6 { store.step(by: AlertThresholds.step) }
        #expect(store.current.alertPercent == AlertThresholds.maxAlert)

        var notified = 0
        store.onChange = { _ in notified += 1 }

        // 再往上第七步會超出範圍：不寫入，也不通知。
        store.step(by: AlertThresholds.step)
        #expect(store.current.alertPercent == AlertThresholds.maxAlert)
        #expect(defaults.integer(forKey: ThresholdStore.defaultsKey) == AlertThresholds.maxAlert)
        #expect(notified == 0, "被拒絕的平移不得通知觀察者")

        // 一路調到下限：50 → 5，九步。
        for _ in 0..<9 { store.step(by: -AlertThresholds.step) }
        #expect(store.current.alertPercent == AlertThresholds.minAlert)
        #expect(notified == 9)

        // 再往下一步會超出範圍。
        store.step(by: -AlertThresholds.step)
        #expect(store.current.alertPercent == AlertThresholds.minAlert)
        #expect(defaults.integer(forKey: ThresholdStore.defaultsKey) == AlertThresholds.minAlert)
        #expect(notified == 9, "仍然只有九個範圍內的步驟有通知")
    }

    @Test func testOversizedSingleStepIsRejectedWithoutClamping() {
        let (store, defaults) = makeStore()
        var notified = 0
        store.onChange = { _ in notified += 1 }

        // 一次 +100 會落在範圍之外，因此什麼都不寫入——
        // 平移絕不會靜默地被夾到上限。
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
                "存檔的 \(bad) 應退回 20"
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