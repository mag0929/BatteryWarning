import Foundation

/// 狀態圖示點開後，下拉選單的第一行摘要文字。
///
/// 這段規則原本寫在 `StatusItemController` 裡，但那是 App 層、import AppKit，
/// 單元測試碰不到。移到這裡的理由和早先的 `MenuBarDisplay` 一樣：
/// 呈現規則必須能不啟動 App 就直接驗證。
public enum MenuSummaryText {
    public static let noBatteryText = "無電池資訊"

    /// 同時報出目前電量與電源來源，讓使用者不必再開別的 App 就能判斷狀況。
    ///
    /// 「已接電源」與「充電中」刻意分開：插著電但沒在充（充飽了，或啟用充電
    /// 最佳化）是很常見的狀態，兩者混為一談會讓使用者以為電池有問題。
    public static func make(for status: BatteryStatus) -> String {
        guard status.isBatteryPresent, let percent = status.percent else {
            return noBatteryText
        }
        let power = status.isOnExternalPower
            ? (status.isCharging ? "充電中" : "已接電源")
            : "使用電池"
        // \u{2009} 是 thin space，比一般空白緊，用來分隔「電量 63% · 充電中」兩段
        // 資訊。刻意不用「,」或「—」：符號本身不該被誤讀成提示或情緒。
        return "電量 \(percent)%\u{2009}·\u{2009}\(power)"
    }
}