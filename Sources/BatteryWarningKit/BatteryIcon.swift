import Foundation

/// 圖示用哪一種外框，依它所在的背景決定。
///
/// 素材提供兩個變體，差別只在外框顏色：電池外殼與正極接點在 `standard` 是
/// `#323456`（深藍），在 `lightOutline` 是 `#FFFFFF`（白）。其餘部分——電量格與
/// 充電閃電——兩個變體完全相同。
public enum BatteryIconVariant: String, Equatable, CaseIterable {
    /// 深藍外框。在淺色背景（例如選單列）上清楚可見。
    case standard
    /// 淺色外框。在深色背景（例如警示面板）上清楚可見。
    case lightOutline = "light"
}

/// 圖示即將被畫到的系統外觀。
///
/// 這裡鏡射 `NSAppearance` 但不 import AppKit，讓選擇規則留在 App 中可測試的部分，
/// 與 `MenuSummaryText` 採同一個分層理由。
public enum SystemAppearance: Equatable {
    case light
    case dark

    /// 在這個外觀的背景上仍然看得見的外框變體。
    public var iconVariant: BatteryIconVariant {
        switch self {
        case .light: return .standard
        case .dark: return .lightOutline
        }
    }
}

/// 依電池狀態選出該用哪一顆圖示。
///
/// 警示面板呼叫 `iconName(for:appearance:)`；選單列改用固定的 `statusIcon`，
/// 不再顯示電量圖示，因此只有面板受這組分級影響。這個型別只決定「名稱」，
/// 載入資源檔與缺檔時的退路都交給呼叫端（`BatteryIconLoader`）。
public enum BatteryIcon {
    /// 充電中時顯示，任何電量都一樣。
    public static let charging = "battery-charging"
    /// 1 格，紅色，對應 0–25%。
    public static let quarter = "battery-25"
    /// 2 格，紅色，對應 26–50%。
    public static let half = "battery-50"
    /// 3 格，橘色，對應 51–75%。
    public static let threeQuarters = "battery-75"
    /// 4 格，綠色，對應 76–100%。
    public static let full = "battery-100"

    /// 各階圖示由低到高。用途有兩個：替這幾個常數命名，以及夾住落在範圍外的
    /// 讀值。
    public static let levelIcons = [quarter, half, threeQuarters, full]

    /// 依電量選出圖示名稱，不含變體後綴。
    ///
    /// 每顆圖示畫的是四分之一格，所以每一區間在「自己名稱所寫的百分比」處收尾，
    /// 下一區間從再一個百分比開始：25% 是 1 格，26% 才是 2 格。
    ///
    /// 落在 0...100 之外的讀值會夾到最接近的一階，而不是失敗——桌上型電腦或
    /// 校準異常的電池都可能回報這種值，圖示消失比顯示錯一格更糟。
    public static func levelIcon(forPercent percent: Int) -> String {
        switch percent {
        case ...25: return quarter
        case 26...50: return half
        case 51...75: return threeQuarters
        default: return full
        }
    }

    /// 能代表 `status` 的資源檔名。
    ///
    /// 沒有電池、或電量讀不到時回傳 `nil`，因為這種情況下沒有任何圖示是對的。
    /// 充電優先於電量分級：正在充電的電池不論剩下多少都畫閃電。
    public static func iconName(
        for status: BatteryStatus,
        appearance: SystemAppearance
    ) -> String? {
        guard status.isBatteryPresent, let percent = status.percent else {
            return nil
        }
        let base = status.isCharging ? charging : levelIcon(forPercent: percent)
        return resourceName(for: base, appearance: appearance)
    }

    /// 在圖示基礎名稱後接上 `appearance` 對應的變體後綴。
    ///
    /// 深藍外框沿用原名（`battery-25`），淺色外框加 `-light`（`battery-25-light`）。
    /// 這個後綴規則與 `Resources/` 的檔名一一對應，改動時兩邊必須同步。
    public static func resourceName(
        for base: String,
        appearance: SystemAppearance
    ) -> String {
        switch appearance.iconVariant {
        case .standard: return base
        case .lightOutline: return "\(base)-\(appearance.iconVariant.rawValue)"
        }
    }
}