import AppKit

// Приложение без Dock-иконки: окно поверх экрана и значок в строке меню.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
