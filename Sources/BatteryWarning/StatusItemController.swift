import AppKit
import BatteryWarningKit

/// 持有唯一的 `NSStatusItem`。選單列顯示一個固定的狀態圖示並負責組出下拉選單；
/// 電量與提醒狀態改由警示面板與下拉選單呈現，選單列一律不顯示文字。
///
/// 選單項目在每次打開時全部重建，因此門檻摘要與各項目的可用／停用狀態
/// 永遠反映當下真實情況，不會和實際值漂移。
final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: AlertCoordinator?
    private var thresholds: ThresholdStore?
    private var loginItem: LoginItemController?

    /// 只給下拉選單的摘要列用。選單列本身不顯示任何東西，
    /// 所以狀態改變時不需要重繪選單列。
    private var latestStatus: BatteryStatus = .unavailable

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
        // 第二個參數是 isAlerting，選單列不需要它——摘要文字只描述電量與電源。
        coordinator.onChange = { [weak self] status, _ in
            self?.latestStatus = status
        }
    }

    func tearDown() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: - 選單列繪製

    /// 畫出選單列。圖示固定不變，因此這裡只在 `install()` 跑一次；
    /// 電池狀態更新只會寫入 `latestStatus`，留待選單打開時才讀。
    private func render() {
        guard let button = statusItem?.button else { return }
        // 明確清空標題：即使設定了 imagePosition，殘留的標題仍會佔掉按鈕寬度，
        // 在選單列上表現為圖示被擠偏或出現空白間隙。
        button.attributedTitle = NSAttributedString(string: "")
        button.image = BatteryIconLoader.statusIcon(
            height: BatteryIconLoader.menuBarHeight
        )
        button.imagePosition = .imageOnly
    }

    // MARK: - NSMenuDelegate

    /// 打開選單前重建所有項目。狀態可能在使用者不看選單的這段時間裡改變，
    /// 因此不能只在這裡快取一次建好的選單。
    func menuWillOpen(_ menu: NSMenu) {
        guard let store = thresholds else { return }
        menu.removeAllItems()

        // 狀態摘要（唯讀）。停用而非用 action: nil，是為了讓它仍然顯示成
        // 一般項目的樣式，而不是變成不可點的灰色標籤。
        let summary = NSMenuItem(title: summaryText(), action: nil, keyEquivalent: "")
        summary.isEnabled = false
        summary.image = Self.symbol("bolt.horizontal")
        menu.addItem(summary)

        let refresh = NSMenuItem(title: "立即檢查", action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        refresh.image = Self.symbol("arrow.clockwise")
        menu.addItem(refresh)

        menu.addItem(.separator())

        // 門檻調整
        let current = store.current
        let thresholdTitle = NSMenuItem(
            title: "低電量提醒門檻\u{2009}\(current.alertPercent)%",
            action: nil,
            keyEquivalent: ""
        )
        thresholdTitle.isEnabled = false
        thresholdTitle.image = Self.symbol("percent")
        menu.addItem(thresholdTitle)

        // \u{2009} 是 thin space，讓標題與括號之間的空白比一般空白緊，
        // 視覺上不會斷成兩塊。符號方向與 `AlertThresholds.stepping(by:)` 一致：
        // (+) 提高數值門檻，也就是讓提醒更晚出現。
        let raise = NSMenuItem(
            title: "提高門檻\u{2009}(+)",
            action: #selector(raiseThreshold),
            keyEquivalent: ""
        )
        raise.target = self
        raise.isEnabled = current.canRaise
        raise.image = Self.symbol("plus")
        menu.addItem(raise)

        // (−) 是 U+2212 減號，不是 ASCII 的連字號 `-`，兩者字寬不同，
        // 混用會讓兩個選單項目的括號對不齊。
        let lower = NSMenuItem(
            title: "降低門檻\u{2009}(−)",
            action: #selector(lowerThreshold),
            keyEquivalent: ""
        )
        lower.target = self
        lower.isEnabled = current.canLower
        lower.image = Self.symbol("minus")
        menu.addItem(lower)

        menu.addItem(.separator())

        // 登入時開啟 —— 狀態取自系統，而不是某個存下來的旗標。
        let launchAtLogin = NSMenuItem(
            title: "登入時開啟",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.image = Self.symbol("power")
        launchAtLogin.state = (loginItem?.isEnabled ?? false) ? .on : .off
        menu.addItem(launchAtLogin)

        let batterySettings = NSMenuItem(
            title: "開啟電池設定…",
            action: #selector(openBatterySettings),
            keyEquivalent: ""
        )
        batterySettings.target = self
        batterySettings.image = Self.symbol("gearshape")
        menu.addItem(batterySettings)

        let quit = NSMenuItem(
            title: "結束 BatteryWarning",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        quit.image = Self.symbol("arrow.right.square")
        menu.addItem(quit)
    }

    /// 選單項目的 SF Symbol。`NSImage(systemSymbolName:)` 遇到這個 macOS 不認識
    /// 的名稱會回傳 `nil` 且不作任何回報，因此對不上的符號只會讓選單項光禿禿的，
    /// 而不是明確地報錯。這裡用到的每個名稱都先在執行期確認過確實存在。
    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func summaryText() -> String {
        MenuSummaryText.make(for: latestStatus)
    }

    // MARK: - 動作

    @objc private func refreshNow() {
        coordinator?.refreshNow()
    }

    /// 門檻數值上升，代表電量要更低才提醒。
    @objc private func raiseThreshold() {
        thresholds?.step(by: AlertThresholds.step)
    }

    /// 門檻數值下降，代表電量稍高一點就提醒。
    @objc private func lowerThreshold() {
        thresholds?.step(by: -AlertThresholds.step)
    }

    @objc private func toggleLaunchAtLogin() {
        guard let loginItem else { return }
        loginItem.setEnabled(!(loginItem.isEnabled))
    }

    /// 直接跳到 macOS 的電池設定面板。用 `x-apple.systempreferences:` scheme，
    /// 比手動導覽 Finder → 系統設定 少很多步驟。
    @objc private func openBatterySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}