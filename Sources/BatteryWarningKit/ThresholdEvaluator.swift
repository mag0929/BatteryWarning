import Foundation

/// 純粹的提醒判定。不持有狀態、不讀取任何東西、不碰 `UserDefaults`——
/// 門檻一律由參數傳入，因此整組規則可以單獨測試。
public enum ThresholdEvaluator {

    /// 冷啟動式的判定，給 App 啟動時與任何沒有前次狀態的觀察者使用。
    ///
    /// 接了外部電源就不提醒：警告的前提是「即將沒電」，插著電的機器不屬於
    /// 這種情況。注意比較是 `<=` 而非 `<`，電量剛好等於門檻就該跳出來。
    public static func isAlerting(
        _ status: BatteryStatus,
        thresholds: AlertThresholds
    ) -> Bool {
        guard status.isBatteryPresent,
              !status.isOnExternalPower,
              let percent = status.percent
        else { return false }

        return percent <= thresholds.alertPercent
    }

    /// 有狀態的判定。提醒一旦啟動就會持續，直到接上外部電源或電量回升到清除門檻——
    /// 這段落差就是遲滯區間（hysteresis），作用是避免電量在門檻附近來回跳動時
    /// 面板閃爍。
    ///
    /// 這裡的比較是 `<` 而非 `<=`：清除門檻比啟動門檻高 5%，只有在確實高於
    /// 清除門檻時才解除，否則會在區間內反覆觸發。
    ///
    /// 外部電源會解除提醒，即使電池並沒有在充電：插著電卻沒在充（充飽了，或
    /// 啟用充電最佳化）的機器，警告要解決的問題本來就已經不存在了。
    public static func isAlerting(
        previous: Bool,
        status: BatteryStatus,
        thresholds: AlertThresholds
    ) -> Bool {
        guard status.isBatteryPresent, let percent = status.percent else {
            return false
        }
        guard !status.isOnExternalPower else {
            return false
        }
        // 尚未提醒：純粹看門檻。
        guard previous else {
            return percent <= thresholds.alertPercent
        }
        // 已在提醒：只看清除門檻。
        return percent < thresholds.clearPercent
    }
}