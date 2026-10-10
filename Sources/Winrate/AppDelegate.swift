import AppKit
import SwiftUI

/// Панель, которая может получать клавиши, не отбирая активность у приложения с графиком.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var fadeTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        makePanel()
        store.onHistoryToggle = { [weak self] open in self?.resizePanel(open: open) }
        makeStatusItem()
        hotKey = HotKey { [weak self] in self?.toggle() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        show()
    }

    // MARK: Окно

    private func makePanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 196),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.setFrameAutosaveName("WinratePanel")

        let host = NSHostingView(rootView: CounterView(store: store))
        host.sizingOptions = []   // размер окна задаём сами, SwiftUI его не подгоняет
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 196)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        if panel.setFrameUsingName("WinratePanel") {
            // Размер фиксирован: сохраняем только положение, верхний край остаётся на месте.
            var f = panel.frame
            f.origin.y += f.height - 196
            f.size = NSSize(width: 300, height: 196)
            panel.setFrame(f, display: false)
        } else if let screen = NSScreen.main {
            // Первый запуск: правый верхний угол экрана.
            let v = screen.visibleFrame
            panel.setFrame(NSRect(x: v.maxX - 300 - 24, y: v.maxY - 196 - 24, width: 300, height: 196), display: false)
        }

        // Когда мышь ушла - окно становится полупрозрачным и не закрывает график.
        let tracker = HoverTracker { [weak self] inside in self?.setHover(inside) }
        host.addSubview(tracker)
        tracker.frame = host.bounds
        tracker.autoresizingMask = [.width, .height]
        self.panel = panel
    }

    /// История раскрывается вниз: верхний край окна остаётся на месте, высота плавно растёт.
    private func resizePanel(open: Bool) {
        let height: CGFloat = open ? Layout.counter + Layout.history : Layout.counter
        var f = panel.frame
        f.origin.y = f.maxY - height
        f.size.height = height
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame, f.origin.y < visible.minY {
            f.origin.y = visible.minY   // не уходим за нижний край экрана
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(f, display: true)
        }
    }

    private func setHover(_ inside: Bool) {
        fadeTask?.cancel()
        if inside {
            withAnimation(.easeOut(duration: 0.25)) { store.idle = false }
        } else {
            fadeTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.45)) { store.idle = true } }
            }
        }
    }

    private func show() {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        // Мышь может быть где угодно: сразу решаем, гасить окно или нет.
        setHover(panel.frame.contains(NSEvent.mouseLocation))
    }

    private func toggle() {
        panel.isVisible ? panel.orderOut(nil) : show()
    }

    // MARK: Клавиши

    /// ← победа, → поражение, ⌫ отмена, ⌘R сброс (двойной), Esc спрятать. Работает, когда окно активно.
    private func handle(_ event: NSEvent) -> Bool {
        guard NSApp.keyWindow === panel else { return false }
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 123 where !cmd: withAnimation(.spring(duration: 0.45, bounce: 0.2)) { store.add(.win) }
        case 124 where !cmd: withAnimation(.spring(duration: 0.45, bounce: 0.2)) { store.add(.loss) }
        case 51: withAnimation(.spring(duration: 0.45, bounce: 0.2)) { store.undo() }
        case 53: panel.orderOut(nil)
        default: return false
        }
        return true
    }

    // MARK: Строка меню

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "plusminus.circle", accessibilityDescription: "Winrate")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Левый клик - показать или спрятать, правый - меню.
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let toggleItem = NSMenuItem(title: panel.isVisible ? "Спрятать окно" : "Показать окно", action: #selector(toggleAction), keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)
            menu.addItem(withTitle: "Горячая клавиша: ⌃⌥W", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Выйти", action: #selector(quitAction), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggle()
        }
    }

    @objc private func toggleAction() { toggle() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}

/// Прозрачный слой, который сообщает, где мышь, и не мешает кликам.
private final class HoverTracker: NSView {
    private let onChange: (Bool) -> Void
    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onChange(true) }
    override func mouseExited(with event: NSEvent) { onChange(false) }
}
