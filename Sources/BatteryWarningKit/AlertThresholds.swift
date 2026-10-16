import Foundation

/// 門檻的值型別。清除門檻是推導出來的、從不存檔，因此 `clearPercent > alertPercent`
/// 這個不變式對 App 可能持有的每一個值都成立——包括使用者用 `defaults write`
/// 從外部塞進來的值。
public struct AlertThresholds: Equatable {
    public static let minAlert = 5
    public static let maxAlert = 50
    public static let step = 5
    public static let hysteresis = 5
    public static let defaultAlertPercent = 20

    public static let `default` = AlertThresholds(clamping: defaultAlertPercent)

    /// 唯一的真實欄位。門檻可調範圍 5–50%，上限 50 決定了警示面板可能出現的
    /// 最高電量就是 50%（`ThresholdEvaluator` 用 `<=` 判定）。
    public let alertPercent: Int

    /// 解除提醒的門檻。`min(..., 100)` 是必要的：門檻調到 50 時，
    /// 50 + 5 不會爆掉，但這讓推導式不必假設上界。
    public var clearPercent: Int { min(alertPercent + Self.hysteresis, 100) }

    /// 內部用：只接受已經合法的值。邊界請改用 `init(clamping:)`。
    init(trustedAlertPercent: Int) {
        self.alertPercent = trustedAlertPercent
    }

    /// 唯一的公開進入點。落在 `minAlert...maxAlert` 之外的值一律退回預設，
    /// 而不是造出一個不可能的狀態。
    public init(clamping raw: Int) {
        if (Self.minAlert...Self.maxAlert).contains(raw) {
            self.alertPercent = raw
        } else {
            self.alertPercent = Self.defaultAlertPercent
        }
    }

    /// 依 `delta` 平移後的門檻；若平移後會超出合法範圍則回傳 `nil`。
    ///
    /// 回傳 `nil` 的語意是「什麼都別寫」，而不是「寫個沒變的值」——
    /// 讓呼叫端在按了不能按的項目時不必特判。
    public func stepping(by delta: Int) -> AlertThresholds? {
        let next = alertPercent + delta
        guard (Self.minAlert...Self.maxAlert).contains(next) else { return nil }
        return AlertThresholds(trustedAlertPercent: next)
    }

    /// 下拉選單「提高門檻 (+)」能否使用。邊界時直接讓項目失效，
    /// 比按下後才靜默無反應清楚。
    public var canRaise: Bool { alertPercent < Self.maxAlert }
    public var canLower: Bool { alertPercent > Self.minAlert }
}