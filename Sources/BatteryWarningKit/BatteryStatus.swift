import Foundation

/// 監控層傳給所有呈現層的單一資料形狀。
///
/// `isBatteryPresent == false` 同時涵蓋「桌上型電腦沒有電池」與「讀取失敗」兩種情況，
/// App 一律把它當成「沒有需要提醒的事」，因此這兩個原因不必在下游分開處理。
public struct BatteryStatus: Equatable {
    public var isBatteryPresent: Bool
    /// `nil` 代表電量讀不到（例如 IOKit 回報異常），與 `isBatteryPresent == false` 不同：
    /// 前者代表「有電池但不知道剩多少」，後者代表「根本沒有電池可談」。
    public var percent: Int?
    public var isOnExternalPower: Bool
    public var isCharging: Bool

    public init(
        isBatteryPresent: Bool,
        percent: Int?,
        isOnExternalPower: Bool,
        isCharging: Bool
    ) {
        self.isBatteryPresent = isBatteryPresent
        self.percent = percent
        self.isOnExternalPower = isOnExternalPower
        self.isCharging = isCharging
    }

    /// 桌上型電腦，或讀取失敗的結果。永遠不會觸發提醒。
    public static let unavailable = BatteryStatus(
        isBatteryPresent: false,
        percent: nil,
        isOnExternalPower: false,
        isCharging: false
    )
}