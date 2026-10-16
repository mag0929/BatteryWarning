import Foundation
import Testing
@testable import BatteryWarningKit

/// 協調器是面板與下拉選單背後唯一的狀態機，因此這裡同時涵蓋「兩者看法一致」
/// 與「門檻一改就立刻生效」。
@Suite("提醒協調器")
struct AlertCoordinatorTests {

    final class FakePresenter: AlertPresenting {
        private(set) var presentCount = 0
        private(set) var refreshCount = 0
        private(set) var dismissCount = 0
        private(set) var lastStatus: BatteryStatus?

        func presentAlert(for status: BatteryStatus) {
            presentCount += 1
            lastStatus = status
        }

        func refreshAlertContent(for status: BatteryStatus) {
            refreshCount += 1
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
            "電池消失也必須解除進行中的提醒"
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
        // 持續讀取失敗時不得崩潰、不得升級成提醒，也不得在畫面上跳出任何東西——
        // presenter 完全不會被呼叫。
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
        #expect(observations <= 1, "相同的失敗結果不重複發布")
    }

    @Test func testPresentingOnlyOnTransitions() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)
        coordinator.start()

        #expect(presenter.presentCount == 1)

        // 電量仍然偏低，但狀態沒有轉換：不會重複把面板叫到畫面上，只更新內容，
        // 讓面板不再停在它剛出現時的電量。
        coordinator.ingest(battery(14))
        coordinator.ingest(battery(13))
        #expect(presenter.presentCount == 1)
        #expect(presenter.refreshCount == 2)
        #expect(presenter.lastStatus?.percent == 13)
        #expect(presenter.dismissCount == 0)

        coordinator.ingest(battery(15, external: true))
        #expect(presenter.dismissCount == 1)
    }

    @Test func testThresholdChangeReevaluatesImmediately() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        // 目前電量 15%，在預設門檻 20% 之上嗎？不是——15 低於 20，
        // 因此預設情況下提醒是開啟的。
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)
        coordinator.start()

        #expect(presenter.presentCount == 1, "預設門檻 20 會在 15% 觸發提醒")

        // 把門檻降到 10%：15 已經不再低於它，因此面板現在就消失，
        // 而不是等下一次 30 秒輪詢。
        store.step(by: -AlertThresholds.step * 2)   // 20 -> 10
        #expect(coordinator.thresholds.alertPercent == 10)
        #expect(coordinator.isAlerting == false)
        #expect(presenter.dismissCount == 1)

        // 調回 20%：15 又低於門檻，面板回來。
        store.step(by: AlertThresholds.step * 2)    // 10 -> 20
        #expect(coordinator.isAlerting == true)
        #expect(presenter.presentCount == 2)
    }

    @Test func testRaisingThresholdAboveCurrentLevelKeepsPanel() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        // 電量 15%，預設門檻 20% → 觸發提醒。
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)
        coordinator.start()
        #expect(presenter.presentCount == 1)

        // 調到 45 之後電量仍然低於門檻，因此面板留下。
        // 提高門檻不該讓一台真的快沒電的機器安靜下來。
        store.step(by: AlertThresholds.step * 5)   // 20 -> 45
        #expect(coordinator.thresholds.alertPercent == 45)
        #expect(coordinator.isAlerting == true)
        #expect(presenter.dismissCount == 0, "仍低於新門檻")
        #expect(presenter.presentCount == 1, "也沒有額外的 present")
        #expect(presenter.refreshCount == 1, "但內容仍更新了一次")
    }

    @Test func testPanelFollowsSingleAlertFlag() {
        let (store, _) = makeStore()
        let presenter = FakePresenter()
        let monitor = BatteryMonitor(reader: StubReader(battery(15)), simulated: battery(15))
        let coordinator = AlertCoordinator(monitor: monitor, store: store, presenter: presenter)

        var observed: [Bool] = []
        coordinator.onChange = { _, isAlerting in observed.append(isAlerting) }
        coordinator.start()
        // 接上外部電源：面板收起，回報的布林值翻回 false。
        coordinator.ingest(battery(15, external: true))

        #expect(observed == [true, false])
        // 面板是否可見，必須等於對外回報的提醒狀態。presentCount 減去
        // dismissCount 就是「面板現在開著或關著」——這是面板可見度的唯一
        // 事實來源，因此拿它與回報的旗標直接比較才有意義。
        let panelIsVisible = presenter.presentCount - presenter.dismissCount > 0
        #expect(
            panelIsVisible == (observed.last ?? false),
            "面板可見度必須與回報的提醒狀態一致"
        )
    }
}