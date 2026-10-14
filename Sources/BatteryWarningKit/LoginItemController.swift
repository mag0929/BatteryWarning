import Foundation
import os

/// Mediates the "launch at login" toggle between the menu and the system.
///
/// The stored preference is never treated as truth, and the app never
/// re-registers itself: if the user removed the app from System Settings, the
/// next launch reports the toggle as off and leaves it that way. Re-enabling
/// is something only the user can do, through the toggle.
public final class LoginItemController {
    public static let preferenceKey = "launchAtLoginEnabled"

    public var onChange: ((Bool) -> Void)?

    private let registrar: LoginItemRegistering
    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: "com.local.batterywarning", category: "LoginItemController"
    )
    public private(set) var isEnabled = false

    public init(
        registrar: LoginItemRegistering,
        defaults: UserDefaults = .standard
    ) {
        self.registrar = registrar
        self.defaults = defaults
    }

    /// Reads the actual registration state and adopts it. Registers nothing.
    @discardableResult
    public func reconcile() -> Bool {
        isEnabled = registrar.isRegistered
        // Keep the stored preference in step with reality so the menu and the
        // system cannot drift apart.
        if defaults.bool(forKey: Self.preferenceKey) != isEnabled {
            defaults.set(isEnabled, forKey: Self.preferenceKey)
        }
        onChange?(isEnabled)
        return isEnabled
    }

    /// Flips the toggle. Never throws: a failure leaves the toggle off and is
    /// logged, never shown as a dialog.
    public func setEnabled(_ enabled: Bool) {
        if enabled {
            do {
                try registrar.register()
                isEnabled = registrar.isRegistered
            } catch {
                logger.error("registration failed: \(String(describing: error), privacy: .public)")
                isEnabled = false
            }
        } else {
            registrar.unregister()
            isEnabled = registrar.isRegistered
        }
        defaults.set(isEnabled, forKey: Self.preferenceKey)
        onChange?(isEnabled)
    }
}