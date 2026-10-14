import AppKit
import BatteryWarningKit

/// `NSPanel` subclass so the focus opt-outs live where AppKit looks for them.
private final class BatteryPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Highest-level, non-activating alert panel.
///
/// Level is the maximum `screenSaver` level so the panel draws over every
/// application including full-screen ones. `.nonactivatingPanel` plus
/// `canBecomeKey = false` keeps the keyboard focus with whatever the user was
/// already typing in.
final class AlertPanelController: AlertPresenting {
    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private var followTimer: Timer?
    private var lastScreenFrame: NSRect?
    private let size = NSSize(width: 260, height: 76)

    func presentAlert(for status: BatteryStatus) {
        let panel = existingPanel()
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        updateContent(of: panel, with: status)
        reposition(panel)
        startFollowingPointer()
        panel.orderFrontRegardless()
    }

    func dismissAlert() {
        stopFollowingPointer()
        panel?.orderOut(nil)
    }

    /// While the panel is up it tracks the display under the pointer, so
    /// dragging the cursor to a second display takes the alert with it.
    ///
    /// Two inputs drive this: a global mouse-moved monitor for responsiveness,
    /// and a slow poll as a safety net. A monitor alone is not enough — global
    /// monitors can miss events (and are unavailable entirely without the
    /// input-monitoring grant), and the panel must not be stranded on the wrong
    /// display. The poll costs one screen lookup and only runs while an alert
    /// is actually visible.
    private func startFollowingPointer() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] _ in
                self?.repositionIfNeeded()
            }
        }
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.repositionIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func repositionIfNeeded() {
        guard let panel, panel.isVisible else { return }
        reposition(panel)
    }

    private func stopFollowingPointer() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        followTimer?.invalidate()
        followTimer = nil
        lastScreenFrame = nil
    }

    private func existingPanel() -> NSPanel {
        if let panel { return panel }
        let created = BatteryPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        created.isFloatingPanel = true
        created.becomesKeyOnlyIfNeeded = true
        created.hidesOnDeactivate = false
        created.isReleasedWhenClosed = false
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.hasShadow = true
        created.isOpaque = false
        created.backgroundColor = .clear
        created.contentView = makeContentView()
        panel = created
        return created
    }

    // MARK: - Content

    private func makeContentView() -> NSView {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.autoresizingMask = [.width, .height]

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "battery.25", accessibilityDescription: "電量")
        icon.contentTintColor = .systemRed
        icon.translatesAutoresizingMaskIntoConstraints = false

        let percent = NSTextField(labelWithString: "")
        percent.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        percent.textColor = .labelColor
        percent.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithString: "請插電充電")
        caption.font = .systemFont(ofSize: 13, weight: .medium)
        caption.textColor = .labelColor
        caption.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [percent, caption])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),

            stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14)
        ])

        // Reach the labels later without walking the view tree.
        percent.identifier = .alertPercentLabel
        caption.identifier = .alertCaptionLabel
        return container
    }

    private func updateContent(of panel: NSPanel, with status: BatteryStatus) {
        guard let container = panel.contentView as? NSVisualEffectView else { return }
        let percentLabel = container.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.identifier == .alertPercentLabel }
        percentLabel?.stringValue = status.percent.map { "\($0)%" } ?? "—"
    }

    // MARK: - Placement

    /// Top-right of the display holding the pointer, clear of the menu bar.
    private func reposition(_ panel: NSPanel) {
        guard let screen = targetScreen() else { return }
        // Skip the work when the pointer is still on the same display.
        guard screen.frame != lastScreenFrame else { return }
        lastScreenFrame = screen.frame

        let visible = screen.visibleFrame
        panel.setContentSize(size)
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - size.width - 16,
                y: visible.maxY - size.height - 16
            )
        )
    }

    private func targetScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    }
}

extension NSUserInterfaceItemIdentifier {
    static let alertPercentLabel = NSUserInterfaceItemIdentifier("alertPercentLabel")
    static let alertCaptionLabel = NSUserInterfaceItemIdentifier("alertCaptionLabel")
}