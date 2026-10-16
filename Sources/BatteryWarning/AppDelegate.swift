import AppKit
import BatteryWarningKit

/// 只有選單列的 App：沒有 Dock 圖示，也沒有主視窗。
///
/// Info.plist 的 `LSUIElement` 已經讓 App 不出現在 Dock；
/// `.accessory` 則補上直接執行執行檔（不經由 bundle）時的情況。
final class AppDelegate: NSObject, NSApplicationDelegate {
    // 這五個屬性存在的唯一理由是「持有」：監控器與選單列必須活到 App 結束，
    // 釋放後就沒有東西在跑、也沒有選單列圖示。
    private var statusItemController: StatusItemController?
    private var alertPanel: AlertPanelController?
    private var thresholdStore: ThresholdStore?
    private var batteryMonitor: BatteryMonitor?
    private var alertCoordinator: AlertCoordinator?
    private var loginItemController: LoginItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let thresholds = ThresholdStore()
        let simulated = SimulationOptions.simulatedStatus(
            from: CommandLine.arguments
        )
        let monitor = BatteryMonitor(simulated: simulated)
        let loginItem = LoginItemController(registrar: LoginItemRegistrar())

        let statusItem = StatusItemController()
        statusItem.install()
        let panel = AlertPanelController()
        let coordinator = AlertCoordinator(
            monitor: monitor,
            store: thresholds,
            presenter: panel
        )
        statusItem.attach(
            coordinator: coordinator,
            thresholds: thresholds,
            loginItem: loginItem
        )

        // 開始供應選單之前，先採用系統實際註冊的狀態，
        // 這樣第一次點下去時核取方塊就已經是對的。
        loginItem.reconcile()

        // 最後才啟動監控：前面都已接好，監控一開就會立刻送進第一個狀態，
        // 不會有狀態送達時還沒人接的情況。
        coordinator.start()

        thresholdStore = thresholds
        batteryMonitor = monitor
        alertCoordinator = coordinator
        loginItemController = loginItem
        // 刻意持有：`AlertCoordinator` 對 presenter 只有弱參考，
        // 因此不在這裡保留的話，面板會在下一次輪詢前就被釋放而消失。
        alertPanel = panel
        statusItemController = statusItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        batteryMonitor?.stop()
        statusItemController?.tearDown()
    }

    /// 選單列 App 沒有視窗需要恢復。
    ///
    /// 回傳 false：面板即使關掉，App 也必須繼續在選單列跑下去。
    /// 回傳 true 會讓「按一下面板的關閉鈕」直接結束整個 App。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}