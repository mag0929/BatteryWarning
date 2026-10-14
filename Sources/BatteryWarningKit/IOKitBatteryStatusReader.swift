import Foundation
import IOKit.ps
import os

/// Readable battery state. The IOKit implementation lives behind this so the
/// status parsing can be unit tested with fixed descriptor dictionaries and
/// without a battery.
public protocol BatteryStatusReading: AnyObject {
    func readStatus() -> BatteryStatus
}

/// IOKit-backed reader.
///
/// A missing battery, an unreadable snapshot, or a descriptor without capacity
/// keys all collapse to a status that never alerts — the app then stays silent
/// rather than showing a wrong percentage.
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
            // Desktop Macs report only an AC source; skip it and keep looking.
            guard let isPresent = description[kIOPSIsPresentKey as String] as? Bool,
                  isPresent
            else { continue }

            return Self.makeStatus(from: description)
        }

        Self.logger.info("no battery source present (desktop or unreadable)")
        return .unavailable
    }

    /// Turns one IOKit descriptor into a `BatteryStatus`. Internal so the
    /// parsing can be tested with fixed dictionaries.
    static func makeStatus(from description: [String: Any]) -> BatteryStatus {
        // There is no dedicated "external power" flag in IOKit: the power
        // source state string is the signal. Anything other than
        // "Battery Power" means the machine is running on AC.
        let state = description[kIOPSPowerSourceStateKey as String] as? String
        let external = state != nil && state != kIOPSBatteryPowerValue as String
        let charging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false

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

        let percent = Int((Double(current) / Double(maximum) * 100.0).rounded())
        return BatteryStatus(
            isBatteryPresent: true,
            percent: min(max(percent, 0), 100),
            isOnExternalPower: external,
            isCharging: charging
        )
    }
}