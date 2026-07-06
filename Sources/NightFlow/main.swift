import AppKit

// NightFlow entry point.
// Menu-bar-only app: .accessory activation policy means no Dock icon and no main menu,
// which is the programmatic equivalent of Info.plist's LSUIElement = YES.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
