import AppKit
import BatteryWarningKit

/// Owns the single `NSStatusItem`. Renders battery level and the alert state,
/// and builds the dropdown menu. Menu items are rebuilt on every open so the
/// threshold summary and the enabled/disabled bounds always match reality.
final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: AlertCoordinator?
    private var thresholds: ThresholdStore?
    private var loginItem: LoginItemController?

    private var latestStatus: BatteryStatus = .unavailable
    private var alerting = false

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "BatteryWarning"
        statusItem = item
        render()
    }

    func attach(
        coordinator: AlertCoordinator,
        thresholds: ThresholdStore,
        loginItem: LoginItemController
    ) {
        self.coordinator = coordinator
        self.thresholds = thresholds
        self.loginItem = loginItem
        coordinator.onChange = { [weak self] status, isAlerting in
            self?.latestStatus = status
            self?.alerting = isAlerting
            self?.render()
        }
        render()
    }

    func tearDown() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: - Rendering

    private func render() {
        guard let button = statusItem?.button else { return }
        let display = MenuBarDisplayBuilder.make(status: latestStatus, isAlerting: alerting)
        // NSStatusBarButton has no textColor; colour goes through the title.
        button.attributedTitle = NSAttributedString(
            string: display.title,
            attributes: [.foregroundColor: Self.color(for: display.style)]
        )
    }

    private static func color(for style: MenuBarDisplay.Style) -> NSColor {
        switch style {
        case .normal:
            return .labelColor
        case .warning:
            return .systemRed
        case .noBattery:
            return .secondaryLabelColor
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard let store = thresholds else { return }
        menu.removeAllItems()

        // Status summary (read-only)
        let summary = NSMenuItem(title: summaryText(), action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)

        let refresh = NSMenuItem(title: "立即檢查", action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        // Threshold adjustment
        let current = store.current
        let thresholdTitle = NSMenuItem(
            title: "低電量提醒門檻\u{2009}\(current.alertPercent)%",
            action: nil,
            keyEquivalent: ""
        )
        thresholdTitle.isEnabled = false
        menu.addItem(thresholdTitle)

        let raise = NSMenuItem(
            title: "提高門檻\u{2009}(−)",
            action: #selector(raiseThreshold),
            keyEquivalent: ""
        )
        raise.target = self
        raise.isEnabled = current.canRaise
        menu.addItem(raise)

        let lower = NSMenuItem(
            title: "降低門檻\u{2009}(+)",
            action: #selector(lowerThreshold),
            keyEquivalent: ""
        )
        lower.target = self
        lower.isEnabled = current.canLower
        menu.addItem(lower)

        menu.addItem(.separator())

        // Launch at login — state comes from the system, not a stored flag.
        let launchAtLogin = NSMenuItem(
            title: "登入時開啟",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = (loginItem?.isEnabled ?? false) ? .on : .off
        menu.addItem(launchAtLogin)

        let batterySettings = NSMenuItem(
            title: "開啟電池設定…",
            action: #selector(openBatterySettings),
            keyEquivalent: ""
        )
        batterySettings.target = self
        menu.addItem(batterySettings)

        let quit = NSMenuItem(
            title: "結束 BatteryWarning",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    private func summaryText() -> String {
        let status = latestStatus
        guard status.isBatteryPresent, let percent = status.percent else {
            return "無電池資訊"
        }
        let power = status.isOnExternalPower
            ? (status.isCharging ? "充電中" : "已接電源")
            : "使用電池"
        return "電量 \(percent)%\u{2009}·\u{2009}\(power)"
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        coordinator?.refreshNow()
    }

    @objc private func raiseThreshold() {
        thresholds?.step(by: AlertThresholds.step)
    }

    @objc private func lowerThreshold() {
        thresholds?.step(by: -AlertThresholds.step)
    }

    @objc private func toggleLaunchAtLogin() {
        guard let loginItem else { return }
        loginItem.setEnabled(!(loginItem.isEnabled))
    }

    @objc private func openBatterySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}