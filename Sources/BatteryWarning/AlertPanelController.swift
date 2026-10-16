import AppKit
import BatteryWarningKit

/// `NSPanel` 子類別，讓焦點的退出設定放在 AppKit 真正會去查的地方。
///
/// 這兩個 override 不是裝飾：不寫的話面板會搶走鍵盤焦點，
/// 使用者正在打字時畫面就會跳掉游標。
private final class BatteryPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 最高層級、不搶焦點的警示面板。
///
/// 層級取 `screenSaver` 的最大值，因此面板會畫在任何 App 之上，包含全螢幕 App。
/// `.nonactivatingPanel` 加上 `canBecomeKey = false`，讓鍵盤焦點留在使用者
/// 原本正在輸入的地方。
final class AlertPanelController: AlertPresenting {
    private var panel: NSPanel?

    /// 兩個驅動面板跟隨指標的來源，都是強參考。移除時要交還給 AppKit，
    /// 否則全域監聽會洩漏。
    private var mouseMonitor: Any?
    private var followTimer: Timer?

    /// 上次定位時的螢幕框。用來判斷指標是否還在同一台螢幕上。
    private var lastScreenFrame: NSRect?

    /// 直接持有，因此更新時不必走訪檢視樹。容器擁有這兩個檢視，
    /// 所以這個參考不可能活得比面板久。
    private var percentLabel: NSTextField?
    private var iconView: NSImageView?

    /// 目前圖示的資源名與外觀。兩者都沒變就不重載 PNG。
    private var currentIconName: String?
    private var currentIconAppearance: SystemAppearance?

    /// 固定 300×100。寬度不跟著文字收縮，理由見 `reposition(_:)`。
    private let size = NSSize(width: 300, height: 100)

    func presentAlert(for status: BatteryStatus) {
        // `existingPanel()` 負責建立內容檢視並填好 percentLabel 與 iconView，
        // 因此它必須在 refresh 之前跑，否則第一次顯示會沒有數字。
        let panel = existingPanel()
        refreshAlertContent(for: status)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        // canJoinAllSpaces + fullScreenAuxiliary：切到其他桌面或進入全螢幕時
        // 面板仍然跟著出現。stationary + ignoresCycle：不被「(cmd)Tab」掃到，
        // 也不會被螢幕保護程式之類的 cycle 掃掉藏起來。
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        reposition(panel)
        startFollowingPointer()
        // orderFrontRegardless：即使 App 不是前景應用程式也照樣顯示。
        // 這是「插著電卻沒人看到警告」唯一會發生的地方。
        panel.orderFrontRegardless()
    }

    func dismissAlert() {
        stopFollowingPointer()
        panel?.orderOut(nil)
    }

    /// 面板顯示期間追蹤指標所在的螢幕，讓使用者把游標拖到第二台螢幕時
    /// 警告跟著過去。
    ///
    /// 兩個輸入來源：全域滑鼠移動監聽負責即時反應，1 秒輪詢則是保險。
    /// 只有監聽不夠——全域監聽可能漏掉事件，而且沒有輸入監控授權時根本不會建立；
    /// 面板不能因此被留在錯誤的螢幕上。輪詢每次只查一次螢幕，成本很低，
    /// 而且只在面板真的可見時才跑。
    private func startFollowingPointer() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] _ in
                self?.repositionIfNeeded()
            }
        }
        // 已經有計時器就不再建立，避免每次重新出現面板都疊一個。
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.repositionIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    /// 面板不可見時不做任何事。面板還沒出現前就定位是白做工。
    private func repositionIfNeeded() {
        guard let panel, panel.isVisible else { return }
        reposition(panel)
    }

    /// 移除監聽、停掉計時器，並清掉螢幕快取。
    ///
    /// `lastScreenFrame = nil` 是必要的：清掉之後下次 `presentAlert` 才會重新定位，
    /// 否則面板在相同螢幕上重新出現時會因為「沒變」而跳過定位。
    private func stopFollowingPointer() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        followTimer?.invalidate()
        followTimer = nil
        lastScreenFrame = nil
    }

    /// 取得面板，必要時建立。第一次呼叫時建出內容檢視，之後直接沿用。
    private func existingPanel() -> NSPanel {
        if let panel { return panel }
        let created = BatteryPanel(
            contentRect: NSRect(origin: .zero, size: size),
            // nonactivatingPanel：顯示時不搶焦點。
            // titled + fullSizeContentView：有標題列但內容可以畫滿整個視窗，
            // 這樣才能做出「只有一張卡片」的樣子。
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        created.isFloatingPanel = true
        created.becomesKeyOnlyIfNeeded = true
        // 關閉程式時不自動隱藏面板。App 沒有「恢復視窗」的流程，
        // 在這種情況下自動隱藏等於讓警告消失。
        created.hidesOnDeactivate = false
        // 必須為 false：面板只 orderOut 不 close，一旦 close 就被釋放，
        // 而協調器對 presenter 是弱參考，面板會就這樣消失。
        created.isReleasedWhenClosed = false
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.hasShadow = true
        created.isOpaque = false
        created.backgroundColor = .clear
        created.contentView = makeContentView()
        panel = created
        return created
    }

    // MARK: - 內容

    /// 建立面板內容：左側自製電池圖示，右側兩行文字，整組置中。
    private func makeContentView() -> NSView {
        let container = NSVisualEffectView()
        // .hudWindow 實測會跟著系統外觀走：淺色外觀下是淺灰卡片，
        // 深色外觀下才需要淺色外框的圖示變體。它不是恆深色。
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.autoresizingMask = [.width, .height]

        let icon = NSImageView()
        // 比例縮放：圖示換成別顆時（1 格換 2 格寬度不同）自動維持自己的比例，
        // 不需要為每個分級各寫一份寬度約束。
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconView = icon

        let percent = NSTextField(labelWithString: "")
        // 等寬數字：電量從 99% 變 100% 時數字不會左右跳動。
        // 這是面板固定寬度能成立的前提。
        percent.font = .monospacedDigitSystemFont(ofSize: 40, weight: .semibold)
        percent.textColor = .labelColor
        percent.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithString: "請插電充電")
        caption.font = .systemFont(ofSize: 18, weight: .medium)
        caption.textColor = .labelColor
        caption.translatesAutoresizingMaskIntoConstraints = false

        // 提示文字前面加一個警示標記，讓它讀起來是「警告」而不是「建議」。
        // 符號名稱先在執行期確認過：對不上的名稱會回傳 nil 且不作回報。
        let warning = NSImageView()
        warning.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: "警告"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        warning.contentTintColor = .systemRed
        warning.translatesAutoresizingMaskIntoConstraints = false

        // 規格規定面板固定兩行資訊：電量百分比與「請插電充電」。
        // 刻意不顯示剩餘時間——那會是第三行，而且預估值本身不準。
        let captionRow = NSStackView(views: [warning, caption])
        captionRow.orientation = .horizontal
        captionRow.alignment = .centerY
        captionRow.spacing = 7
        captionRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [percent, captionRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 圖示與文字排成一行，整組置中。面板寬度固定，因此電量變化時
        // 只會改動中間那個數字本身，面板不會在使用者眼前縮放。
        let row = NSStackView(views: [icon, stack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(row)

        // 圖示尺寸完全交給 NSImageView 的固有尺寸——載入器已經依素材自己的
        // 60:106 比例縮放到 `panelHeight`，因此不需要寬高約束，
        // 換圖時尺寸自動跟上。
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        percent.identifier = .alertPercentLabel
        caption.identifier = .alertCaptionLabel
        // 直接持有，之後更新就不必走訪檢視樹。
        percentLabel = percent
        return container
    }

    /// 面板已經在畫面上而電池狀態變了。只有數字與圖示需要改；
    /// 視窗的層級、collection behavior 與指標追蹤都已經由 `presentAlert` 設定好，
    /// 這裡重做一次都是白做工。
    func refreshAlertContent(for status: BatteryStatus) {
        updateContent(with: status)
    }

    private func updateContent(with status: BatteryStatus) {
        // `?? "—"` 在目前的呼叫路徑下**不可達**：面板只會在 `AlertCoordinator`
        // 判定仍需提醒時才更新，而 `ThresholdEvaluator` 在 `percent == nil` 時
        // 一律回傳 false，面板根本不會出現。保留它是為了萬一哪天這條不變式
        // 被打破時，顯示破折號好過顯示上一個電量的殘值。
        // 若要為它寫測試，先確認呼叫條件是否已經改變——否則等於把死路徑釘死。
        percentLabel?.stringValue = status.percent.map { "\($0)%" } ?? "—"
        guard let iconView else { return }

        // 外觀沒有可直接訂閱的通知，因此只能在每次更新時取樣。
        // 好處是使用者在面板可見期間切換深淺色，下次電量變動時圖示就會跟著換。
        let appearance: SystemAppearance = iconView.effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]
        ) == .darkAqua ? .dark : .light

        guard let name = BatteryIcon.iconName(for: status, appearance: appearance) else {
            // 沒有電池可畫：清空並記下「目前沒有圖示」，
            // 否則恢復有電池時會因為名稱沒變而跳過載入。
            iconView.image = nil
            currentIconName = nil
            return
        }

        // 解碼 PNG 是這裡最貴的部分；分級沒變、外觀沒翻就不必重來。
        guard name != currentIconName || appearance != currentIconAppearance else { return }
        guard let image = BatteryIconLoader.image(
            for: status,
            appearance: appearance,
            height: BatteryIconLoader.panelHeight
        ), image.size.height > 0 else { return }

        iconView.image = image
        currentIconName = name
        currentIconAppearance = appearance
    }

    // MARK: - 位置

    /// 放在指標所在螢幕的右上角，並避開選單列。
    ///
    /// `visibleFrame` 已經排除了選單列與 Dock，因此直接用它就不會被蓋住。
    /// 邊界留 16pt，看起來才不像貼在螢幕邊緣。
    private func reposition(_ panel: NSPanel) {
        guard let screen = targetScreen() else { return }
        // 指標還在同一台螢幕上就跳過：位置與尺寸上一次就設好了，不會自己跑掉。
        // setContentSize 在這裡是必要的，因為它同時負責更新視窗的 frame origin。
        guard screen.frame != lastScreenFrame else { return }
        lastScreenFrame = screen.frame

        let visible = screen.visibleFrame
        panel.setContentSize(size)
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - size.width - 16,
                y: visible.maxY - size.height - 16
            )
        )
    }

    /// 指標所在的螢幕。指標落在任何螢幕之外（理論上不該發生）時退回主螢幕。
    private func targetScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    }
}

extension NSUserInterfaceItemIdentifier {
    static let alertPercentLabel = NSUserInterfaceItemIdentifier("alertPercentLabel")
    /// 目前沒有程式碼透過 identifier 查找這個標籤（`percentLabel` 是直接持有的）。
    /// 留著是為了 UI 測試與無障礙工具能指到它；純粹是識別用途，不參與更新流程。
    static let alertCaptionLabel = NSUserInterfaceItemIdentifier("alertCaptionLabel")
}