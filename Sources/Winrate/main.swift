import AppKit

// Обычное приложение: иконка в Dock, значок в строке меню, окно поверх экрана.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
