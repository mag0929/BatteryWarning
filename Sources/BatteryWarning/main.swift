import AppKit

// Menu bar only. Info.plist carries LSUIElement=true; the explicit accessory
// policy keeps the Dock icon away even when the raw executable is launched.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()