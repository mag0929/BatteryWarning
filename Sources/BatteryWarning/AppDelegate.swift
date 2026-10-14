import AppKit
import BatteryWarningKit

/// Menu bar only shell: no Dock icon, no main window.
/// `LSUIElement` in Info.plist already keeps the app out of the Dock;
/// `.accessory` covers the case where the executable is run without the bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
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

        // Adopt whatever the system actually has registered before serving
        // the menu, so the checkbox is truthful from the first click.
        loginItem.reconcile()

        coordinator.start()

        thresholdStore = thresholds
        batteryMonitor = monitor
        alertCoordinator = coordinator
        loginItemController = loginItem
        // Retained on purpose: AlertCoordinator holds the presenter weakly,
        // so a panel that is not kept alive here would vanish immediately.
        alertPanel = panel
        statusItemController = statusItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        batteryMonitor?.stop()
        statusItemController?.tearDown()
    }

    /// Menu bar apps have no windows to restore.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}