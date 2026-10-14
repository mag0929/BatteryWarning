import Foundation
import os

/// The single owner of the alert threshold. Wraps `UserDefaults`, clamps
/// anything that arrives from outside, and never writes a value the range
/// does not allow. Nothing else in the app reads the defaults key.
public final class ThresholdStore {
    public static let defaultsKey = "alertThresholdPercent"

    /// Fired after a successful write so the panel and the menu bar can
    /// re-evaluate immediately instead of waiting for the next poll.
    public var onChange: ((AlertThresholds) -> Void)?

    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.local.batterywarning",
        category: "ThresholdStore"
    )
    private var cached: AlertThresholds

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cached = Self.load(from: defaults)
    }

    public var current: AlertThresholds { cached }

    /// Moves the threshold by `delta`. Out-of-range moves are rejected and
    /// nothing is written — the stored value and `current` stay untouched.
    @discardableResult
    public func step(by delta: Int) -> AlertThresholds {
        guard let next = cached.stepping(by: delta) else {
            logger.debug("threshold step \(delta) rejected at bound \(self.cached.alertPercent)")
            return cached
        }
        guard next != cached else { return cached }

        cached = next
        defaults.set(next.alertPercent, forKey: Self.defaultsKey)
        onChange?(next)
        return next
    }

    private static func load(from defaults: UserDefaults) -> AlertThresholds {
        guard let raw = defaults.object(forKey: defaultsKey) else {
            return .default
        }
        guard let value = raw as? Int else {
            Logger(
                subsystem: "com.local.batterywarning", category: "ThresholdStore"
            ).warning("stored threshold \(String(describing: raw), privacy: .public) is not an integer; using default")
            return .default
        }
        let clamped = AlertThresholds(clamping: value)
        if clamped.alertPercent != value {
            Logger(
                subsystem: "com.local.batterywarning", category: "ThresholdStore"
            ).warning("stored threshold \(value) out of range; using \(clamped.alertPercent)")
        }
        return clamped
    }
}