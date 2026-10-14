import Foundation

/// Pure alert decisions. Holds no state, reads nothing, touches no
/// `UserDefaults` — thresholds arrive as an argument so the whole rule set
/// is testable in isolation.
public enum ThresholdEvaluator {

    /// Cold evaluation, for launch and for observers that hold no prior state.
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

    /// Stateful evaluation. Once active the alert holds until external power
    /// is connected or the level reaches the clear threshold — that gap is the
    /// hysteresis band and is what stops the panel flickering at the boundary.
    ///
    /// External power clears the alert even when the battery is not charging:
    /// a plugged-in-but-not-charging machine (full, or charge optimisation on)
    /// has already solved the problem the warning is about.
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
        guard previous else {
            return percent <= thresholds.alertPercent
        }
        return percent < thresholds.clearPercent
    }
}