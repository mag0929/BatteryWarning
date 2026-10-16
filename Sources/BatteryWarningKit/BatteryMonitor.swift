import AppKit
import Foundation
import IOKit.ps
import os

/// 監看電池狀態並把變化轉發出去。
///
/// 依 design 設計兩個輸入來源：IOKit 的 run-loop 通知負責立即回應電源事件，
/// 30 秒的計時器則是保險——macOS 回報電量是粗略跳動的，沒有任何事件抵達時，
/// 一次百分比的變化可能就這樣漏掉。從睡眠喚醒時會立刻重讀。
public final class BatteryMonitor {
    public static let pollInterval: TimeInterval = 30

    /// 狀態有變化時觸發。只在真的改變時觸發，不會每次輪詢都響。
    public var onStatusChange: ((BatteryStatus) -> Void)?

    private let reader: BatteryStatusReading
    private let pollInterval: TimeInterval
    private let logger = Logger(
        subsystem: "com.local.batterywarning", category: "BatteryMonitor"
    )

    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var lastStatus: BatteryStatus?

    /// 有值時，監控器改報這個狀態、完全不碰 IOKit，也不啟動計時器與通知。
    /// 只有文件記載的 `--simulate-battery` 啟動參數會設到它；正常啟動永遠是 `nil`。
    private let simulated: BatteryStatus?

    public init(
        reader: BatteryStatusReading = IOKitBatteryStatusReader(),
        pollInterval: TimeInterval = BatteryMonitor.pollInterval,
        simulated: BatteryStatus? = nil
    ) {
        self.reader = reader
        self.pollInterval = pollInterval
        self.simulated = simulated
    }

    deinit { stop() }

    public func start() {
        // timer != nil 代表已經啟動過。但模擬路徑不會建立 timer，因此要放行
        // 模擬狀態，否則同一個實例重複 start() 時模擬狀態只會報一次。
        guard timer == nil || simulated != nil else { return }

        if let simulated {
            // 除錯路徑：立即報一次，不碰 IOKit、不啟動計時器。
            lastStatus = simulated
            onStatusChange?(simulated)
            return
        }

        startNotification()
        startTimer()
        refreshNow()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
    }

    /// 立刻重讀；只有在結果與上次不同時才轉發。
    ///
    /// 這道 `!=` 判斷讓下游不必自己去重複判斷「有沒有變」，也讓 30 秒輪詢不會
    /// 無謂地觸發一整串 UI 更新。
    public func refreshNow() {
        let status = simulated ?? reader.readStatus()
        guard status != lastStatus else { return }
        lastStatus = status
        onStatusChange?(status)
    }

    // MARK: - 輸入來源

    private func startTimer() {
        let t = Timer(
            timeInterval: pollInterval,
            target: self,
            selector: #selector(pollFired),
            userInfo: nil,
            repeats: true
        )
        // 加在 .common 模式：拖曳視窗或調整音量時 run loop 會進入 tracking 模式，
        // 只掛在 .default 會讓計時器在那段期間完全停擺。
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func pollFired() {
        refreshNow()
    }

    @objc private func systemDidWake() {
        handleSystemWake()
    }

    /// 喚醒處理。設為 internal，讓測試不必真的讓機器睡眠就能驅動它。
    func handleSystemWake() {
        // 睡眠期間的舊讀值必須丟掉：喚醒後直接用記憶中的值比對等於什麼都沒比，
        // 面板會停在睡前的電量。
        lastStatus = nil
        refreshNow()
    }

    private func startNotification() {
        // 公開 API 只接受 callback 與 context，沒有型別過濾——電源被插入、拔出或
        // 變化（含剩餘電量）都會觸發，因此只能進來之後自己比對。
        //
        // passUnretained：self 的生命週期由呼叫端管理，不讓這個 notification 持有
        // 監控器；這是為此 API 手動管理記憶體時的標準做法。
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            // 切回主 run loop：觀察者會碰到 AppKit，必須在主執行緒上更新。
            DispatchQueue.main.async { monitor.refreshNow() }
        }, context) else {
            // 建不出來就只失去「立即反應」，30 秒計時器仍在，屬可接受降級。
            // 這裡只記錄不拋錯：一個選單列小工具不該因為拿不到通知就無法啟動。
            logger.error("could not create IOKit power source notification")
            return
        }
        let source = unmanaged.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
}