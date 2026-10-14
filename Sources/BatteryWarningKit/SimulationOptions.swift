import Foundation
import os

/// Parses the debug launch arguments documented in the design.
///
/// Only `--simulate-battery` and `--simulate-external-power` are recognised,
/// and only when both are well formed. A normal launch passes no arguments at
/// here, so the real IOKit path is what ships.
public enum SimulationOptions {
    public static let batteryFlag = "--simulate-battery"
    public static let externalPowerFlag = "--simulate-external-power"

    private static let logger = Logger(
        subsystem: "com.local.batterywarning", category: "Simulation"
    )

    public static func simulatedStatus(from arguments: [String]) -> BatteryStatus? {
        let batteryValue = value(of: batteryFlag, in: arguments)
        let externalValue = value(of: externalPowerFlag, in: arguments)

        guard let batteryValue, let externalValue else { return nil }

        guard let percent = Int(batteryValue), (0...100).contains(percent) else {
            logger.warning("ignoring \(batteryFlag) with value \(batteryValue, privacy: .public)")
            return nil
        }
        guard let external = parseBool(externalValue) else {
            logger.warning("ignoring \(externalPowerFlag) with value \(externalValue, privacy: .public)")
            return nil
        }

        return BatteryStatus(
            isBatteryPresent: true,
            percent: percent,
            isOnExternalPower: external,
            isCharging: false
        )
    }

    /// Accepts both `--flag value` and the documented `--flag=value` form.
    private static func value(of flag: String, in arguments: [String]) -> String? {
        for argument in arguments {
            if argument == flag {
                guard let index = arguments.firstIndex(of: argument),
                      arguments.index(after: index) < arguments.endIndex
                else { return nil }
                return arguments[arguments.index(after: index)]
            }
            if argument.hasPrefix("\(flag)=") {
                return String(argument.dropFirst(flag.count + 1))
            }
        }
        return nil
    }

    /// The documented form is `<0|1>`, and `Bool("0")` is nil in Swift, so
    /// digits are handled explicitly alongside the word forms.
    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}