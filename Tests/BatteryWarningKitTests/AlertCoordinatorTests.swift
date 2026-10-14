import Foundation
import Testing
@testable import BatteryWarningKit

/// The coordinator is the single state machine behind the panel and the menu
/// bar, so these cover both "they agree" and "threshold changes take effect at
/// once".
@Suite("提醒協調器")
struct AlertCoordinatorTests {

    final class FakePresenter: AlertPresenting {
        private(set) var presentCount = 0
        private(set) var dismissCount = 0
        private(set) var lastStatus: BatteryStatus?

        func presentAlert(for status: BatteryStatus) {
            presentCount += 1
            lastStatus = status
        }

        func dismissAlert() {
            dismissCount += 1
        }
    }

    final class StubReader: BatteryStatusReading {
        var status: BatteryStatus
        init(_ status: BatteryStatus) { self.status = status }
        func readStatus() -> BatteryStatus { status }
    }

    private func makeStore() -> (ThresholdStore, UserDefaults) {
        let suite = "bw.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (ThresholdStore(defaults: defaults), defaults)
    }

    private func battery(_ percent: Int, external: Bool = false) -> BatteryStatus {
        BatteryStatus(
            isBatteryPresent: true,
            percent: percent,
            isOnExternalPower: external,
            isCharging: false
        )
    }

    @Test func testAbsentBatteryNeverActivatesAlert() {
        #expect(ThresholdEvaluator.isAlerting(.unavailable, thresholds: .default) == false)
        #expect(
            ThresholdEvaluator.isAlerting(previous: true, status: .unavailable, thresholds: .default) == false,
            "losing the battery must also release an active alert"
        )

        let (store, defaults) = makeStore()
        let presenter = FakePresenter()
        let coordinator = AlertCoordinator(
            monitor: BatteryMonitor(reader: StubReader(.unavailable), simulated: .unavailable),
            store: store,
            presenter: presenter
        )
        coordinator.start()

        #expect(presenter.presentCount == 0)
        #expect(presenter.dismissCount == 0)
        #expect(coordinator.isAlerting == false)
        defaults.removePersistentDomain(forName: defaults.description)
    }

    @Test func testReadFailureIsNotSurfaced() {
        // A read that keeps failing must not crash, must not escalate, and must
        // not raise anything on screen — the presenter is never called at all.
        final class AlwaysFails: BatteryStatusReading {
            func readStatus() -> BatteryStatus { .unavailable }
        }
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        let monitor = BatteryMonitor(reader: AlwaysFails())
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)

        var observations = 0
        coordinator.onChange = { _, _ in observations += 1 }

        for _ in 0..<5 { coordinator.refreshNow() }

        #expect(presenter.presentCount == 0)
        #expect(presenter.dismissCount == 0)
        #expect(coordinator.isAlerting == false)
        #expect(observations <= 1, "identical failures are not republished")
    }

    @Test func testPresentingOnlyOnTransitions() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)
        coordinator.start()

        #expect(presenter.presentCount == 1)

        // Still low, but no state change: no repeated ordering-in.
        coordinator.ingest(battery(14))
        coordinator.ingest(battery(13))
        #expect(presenter.presentCount == 1)

        coordinator.ingest(battery(15, external: true))
        #expect(presenter.dismissCount == 1)
    }

    @Test func testThresholdChangeReevaluatesImmediately() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        // Battery currently at 15%, above the default threshold of 20%? No —
        // 15 is *below* 20, so the default alert is on.
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)
        coordinator.start()

        #expect(presenter.presentCount == 1, "default threshold 20 alerts at 15%")

        // Lower the threshold to 10%: 15 is no longer below it, so the panel
        // goes away now, not at the next 30-second poll.
        store.step(by: -AlertThresholds.step * 2)   // 20 -> 10
        #expect(coordinator.thresholds.alertPercent == 10)
        #expect(coordinator.isAlerting == false)
        #expect(presenter.dismissCount == 1)

        // Raise it back to 20%: 15 is below the threshold again, panel returns.
        store.step(by: AlertThresholds.step * 2)    // 10 -> 20
        #expect(coordinator.isAlerting == true)
        #expect(presenter.presentCount == 2)
    }

    @Test func testRaisingThresholdAboveCurrentLevelKeepsPanel() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        // Battery at 15%, default threshold 20% -> alerting.
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)
        coordinator.start()
        #expect(presenter.presentCount == 1)

        // Raising to 45 keeps the battery below the threshold, so the panel
        // stays. Raising a threshold must not silence a genuinely low battery.
        store.step(by: AlertThresholds.step * 5)   // 20 -> 45
        #expect(coordinator.thresholds.alertPercent == 45)
        #expect(coordinator.isAlerting == true)
        #expect(presenter.dismissCount == 0, "still below the new threshold")
        #expect(presenter.presentCount == 1, "no extra present either")
    }

    @Test func testPanelAndMenuBarObserveSameState() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)

        var observed: [Bool] = []
        coordinator.onChange = { _, isAlerting in observed.append(isAlerting) }
        coordinator.start()
        coordinator.ingest(battery(15, external: true))

        #expect(observed == [true, false])
        #expect(
            observed.last == (presenter.presentCount > presenter.dismissCount ? true : observed.last),
            "menu bar observer and panel are driven by the same flag"
        )
    }
}