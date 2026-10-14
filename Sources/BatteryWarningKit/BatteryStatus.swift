import Foundation

/// The single shape passed from the monitoring layer to every presenter.
/// `isBatteryPresent == false` covers desktops and read failures alike:
/// the app treats "no battery" as "nothing to warn about".
public struct BatteryStatus: Equatable {
    public var isBatteryPresent: Bool
    /// nil = level could not be read.
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

    /// Desktop Mac, or a read that failed. Never alerts.
    public static let unavailable = BatteryStatus(
        isBatteryPresent: false,
        percent: nil,
        isOnExternalPower: false,
        isCharging: false
    )
}