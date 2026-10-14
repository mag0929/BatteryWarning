import Testing
@testable import BatteryWarningKit

/// Rows come from the transition table in the `battery-alert` spec.
@Suite("門檻判定")
struct ThresholdEvaluatorTests {
    private func status(_ percent: Int, external: Bool = false, charging: Bool = false, present: Bool = true) -> BatteryStatus {
        BatteryStatus(
            isBatteryPresent: present,
            percent: percent,
            isOnExternalPower: external,
            isCharging: charging
        )
    }

    private let thresholds = AlertThresholds.default  // 20 / 25

    @Test func testDefaultThresholdTransitions() {
        // previous level, new level, external power, alerting after
        let rows: [(Int, Int, Bool, Bool)] = [
            (21, 20, false, true),
            (20, 21, false, true),
            (20, 24, false, true),
            (20, 25, false, false),
            (20, 30, false, false),
            (20, 15, true, false)
        ]

        for (previousLevel, newLevel, external, expected) in rows {
            let previousAlerting = ThresholdEvaluator.isAlerting(
                status(previousLevel, external: external), thresholds: thresholds
            )
            let result = ThresholdEvaluator.isAlerting(
                previous: previousAlerting,
                status: status(newLevel, external: external),
                thresholds: thresholds
            )
            #expect(result == expected, "\(previousLevel)->\(newLevel) ext=\(external)")
        }
    }

    @Test func testHysteresisBandKeepsAlertActive() {
        let active = ThresholdEvaluator.isAlerting(status(19), thresholds: thresholds)
        #expect(active)

        // 19 -> 21 sits inside the 20..25 band and must not clear.
        let afterRise = ThresholdEvaluator.isAlerting(
            previous: active, status: status(21), thresholds: thresholds
        )
        #expect(afterRise)

        // Reaching the clear threshold releases it.
        let afterClear = ThresholdEvaluator.isAlerting(
            previous: afterRise, status: status(25), thresholds: thresholds
        )
        #expect(afterClear == false)
    }

    @Test func testExternalPowerWithoutChargingClearsAlert() {
        let active = ThresholdEvaluator.isAlerting(status(15), thresholds: thresholds)
        #expect(active)

        // Plugged in but NOT charging (full, or charge optimisation).
        let afterPlug = ThresholdEvaluator.isAlerting(
            previous: active,
            status: status(15, external: true, charging: false),
            thresholds: thresholds
        )
        #expect(afterPlug == false)
    }

    @Test func testExternalPowerDisconnectedReactivates() {
        let afterPlug = ThresholdEvaluator.isAlerting(
            previous: false,
            status: status(15, external: true, charging: false),
            thresholds: thresholds
        )
        #expect(afterPlug == false)

        let afterUnplug = ThresholdEvaluator.isAlerting(
            previous: afterPlug,
            status: status(15, external: false),
            thresholds: thresholds
        )
        #expect(afterUnplug)
    }

    @Test func testUnpluggedAtAlertThresholdActivates() {
        #expect(ThresholdEvaluator.isAlerting(status(20), thresholds: thresholds))
        #expect(ThresholdEvaluator.isAlerting(status(21), thresholds: thresholds) == false)
    }

    @Test func testPluggedInAtAlertThresholdNeverAlerts() {
        #expect(
            ThresholdEvaluator.isAlerting(status(20, external: true), thresholds: thresholds) == false
        )
    }

    @Test func testClearPercentAlwaysExceedsAlertPercent() {
        for percent in [AlertThresholds.minAlert, 10, 20, 35, AlertThresholds.maxAlert] {
            let t = AlertThresholds(clamping: percent)
            #expect(t.clearPercent > t.alertPercent, "alert=\(t.alertPercent)")
        }
    }

    @Test func testClearPercentIsCappedAt100() {
        let t = AlertThresholds(clamping: AlertThresholds.maxAlert)
        #expect(t.clearPercent == 55)
        #expect(t.clearPercent <= 100)
    }
}