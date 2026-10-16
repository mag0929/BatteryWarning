import Foundation
import IOKit.ps
import os

/// 可讀取電池狀態的介面。IOKit 實作藏在這個協定後面，
/// 因此狀態解析可以用固定的 descriptor 字典做單元測試，不需要真的有一顆電池。
public protocol BatteryStatusReading: AnyObject {
    func readStatus() -> BatteryStatus
}

/// 以 IOKit 為後端的讀取器。
///
/// 沒有電池、快照讀不到、或 descriptor 缺少容量欄位，這三種情況一律收斂成
/// 「永遠不會提醒」的狀態——App 因此保持靜默，而不是顯示一個錯誤的百分比。
public final class IOKitBatteryStatusReader: BatteryStatusReading {
    private static let logger = Logger(
        subsystem: "com.local.batterywarning", category: "BatteryStatus"
    )

    public init() {}

    public func readStatus() -> BatteryStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            Self.logger.error("IOPSCopyPowerSourcesInfo returned nil")
            return .unavailable
        }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty
        else {
            Self.logger.error("no power sources reported")
            return .unavailable
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            // 桌上型 Mac 只會回報一個 AC 電源來源；跳過它繼續找下一個。
            guard let isPresent = description[kIOPSIsPresentKey as String] as? Bool,
                  isPresent
            else { continue }

            return Self.makeStatus(from: description)
        }

        Self.logger.info("no battery source present (desktop or unreadable)")
        return .unavailable
    }

    /// 把單一 IOKit descriptor 轉成 `BatteryStatus`。
    /// 設為 internal，讓解析邏輯可以用固定字典測試。
    static func makeStatus(from description: [String: Any]) -> BatteryStatus {
        // IOKit 沒有專門的「外部電源」旗標，唯一的訊號是電源狀態字串。
        // 任何不是 "Battery Power" 的值都代表機器跑在 AC 上。
        let state = description[kIOPSPowerSourceStateKey as String] as? String
        let external = state != nil && state != kIOPSBatteryPowerValue as String
        let charging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false

        // 容量欄位是算百分比的必要條件；缺了就寧可回報讀不到電量，
        // 也不要拿 0/0 硬算出一個 NaN 百分比給面板顯示。
        guard let current = description[kIOPSCurrentCapacityKey as String] as? Int,
              let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
              maximum > 0
        else {
            logger.error("battery present but capacity keys missing or invalid")
            return BatteryStatus(
                isBatteryPresent: true,
                percent: nil,
                isOnExternalPower: external,
                isCharging: charging
            )
        }

        // 四捨五入而非直接取整：直接截斷會讓 99.6% 顯示成 99%，使用者會覺得
        // 明明充飽了卻一直顯示 99%。夾在 0...100 是防校準異常回報超界值。
        let percent = Int((Double(current) / Double(maximum) * 100.0).rounded())
        return BatteryStatus(
            isBatteryPresent: true,
            percent: min(max(percent, 0), 100),
            isOnExternalPower: external,
            isCharging: charging
        )
    }
}