import Foundation
import os

/// 提醒門檻的唯一持有者。包裝 `UserDefaults`，把任何從外部進來的值夾回合法範圍，
/// 並且絕不寫入範圍不允許的值。App 裡沒有其他地方讀這個 defaults key。
public final class ThresholdStore {
    public static let defaultsKey = "alertThresholdPercent"

    /// 寫入成功後觸發，讓面板與選單列能立刻重新評估，不必等下一次輪詢。
    public var onChange: ((AlertThresholds) -> Void)?

    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.local.batterywarning",
        category: "ThresholdStore"
    )
    private var cached: AlertThresholds

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cached = Self.load(from: defaults)
    }

    public var current: AlertThresholds { cached }

    /// 依 `delta` 平移門檻。超出範圍的平移會被拒絕且什麼都不寫入——
    /// 儲存的值與 `current` 都維持原狀。
    @discardableResult
    public func step(by delta: Int) -> AlertThresholds {
        guard let next = cached.stepping(by: delta) else {
            logger.debug("threshold step \(delta) rejected at bound \(self.cached.alertPercent)")
            return cached
        }
        // delta 有可能算回同一個值（例如 delta 為 0）。此時不必寫入也不必通知，
        // 否則會造成一次「狀態沒變卻觸發重新評估」的無謂回呼。
        guard next != cached else { return cached }

        cached = next
        defaults.set(next.alertPercent, forKey: Self.defaultsKey)
        onChange?(next)
        return next
    }

    /// 從 `UserDefaults` 讀出門檻。讀到的值一律視為不可信：
    /// 使用者可能用 `defaults write` 塞進來任何東西，甚至塞進非整數。
    private static func load(from defaults: UserDefaults) -> AlertThresholds {
        guard let raw = defaults.object(forKey: defaultsKey) else {
            return .default
        }
        guard let value = raw as? Int else {
            Logger(
                subsystem: "com.local.batterywarning", category: "ThresholdStore"
            ).warning("stored threshold \(String(describing: raw), privacy: .public) is not an integer; using default")
            return .default
        }
        // 夾住並且記錄：使用者改了門檻卻沒生效時，這行 log 是唯一的線索，
        // 沒有它就只能靠猜（是範圍不對，還是根本沒存進去？）。
        let clamped = AlertThresholds(clamping: value)
        if clamped.alertPercent != value {
            Logger(
                subsystem: "com.local.batterywarning", category: "ThresholdStore"
            ).warning("stored threshold \(value) out of range; using \(clamped.alertPercent)")
        }
        return clamped
    }
}