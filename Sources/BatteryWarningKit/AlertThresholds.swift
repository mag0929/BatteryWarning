import Foundation

/// Thresholds as a value type. The clear threshold is derived, never stored,
/// so `clearPercent > alertPercent` holds for every value the app can hold —
/// including values written from outside by `defaults write`.
public struct AlertThresholds: Equatable {
    public static let minAlert = 5
    public static let maxAlert = 50
    public static let step = 5
    public static let hysteresis = 5
    public static let defaultAlertPercent = 20

    public static let `default` = AlertThresholds(clamping: defaultAlertPercent)

    public let alertPercent: Int

    public var clearPercent: Int { min(alertPercent + Self.hysteresis, 100) }

    /// Internal: trusted values only. Prefer `init(clamping:)` at the edges.
    init(trustedAlertPercent: Int) {
        self.alertPercent = trustedAlertPercent
    }

    /// The only public entry point. Anything outside `minAlert...maxAlert`
    /// falls back to the default rather than producing an impossible state.
    public init(clamping raw: Int) {
        if (Self.minAlert...Self.maxAlert).contains(raw) {
            self.alertPercent = raw
        } else {
            self.alertPercent = Self.defaultAlertPercent
        }
    }

    /// Returns the same thresholds moved by `delta`, or nil when the move
    /// would leave the legal range. Nil means "do not write anything".
    public func stepping(by delta: Int) -> AlertThresholds? {
        let next = alertPercent + delta
        guard (Self.minAlert...Self.maxAlert).contains(next) else { return nil }
        return AlertThresholds(trustedAlertPercent: next)
    }

    public var canRaise: Bool { alertPercent < Self.maxAlert }
    public var canLower: Bool { alertPercent > Self.minAlert }
}