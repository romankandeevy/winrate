// Обложка README: иконка и два скриншота на тёмном фоне. Запуск: swift tools/make-hero.swift
import AppKit
let W: CGFloat = 1600, H: CGFloat = 800
let img = NSImage(size: NSSize(width: W, height: H), flipped: false) { rect in
    NSGradient(colors: [NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)])!.draw(in: rect, angle: -60)
    // мягкие зелёное и красное свечения
    for (c, x) in [(NSColor(red: 0.2, green: 0.84, blue: 0.45, alpha: 0.18), 380.0), (NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.14), 1250.0)] {
        NSGradient(colors: [c, .clear])!.draw(fromCenter: NSPoint(x: x, y: 400), radius: 0, toCenter: NSPoint(x: x, y: 400), radius: 520, options: [])
    }
    let icon = NSImage(contentsOfFile: "/tmp/counter-trade-icon.png")!
    icon.draw(in: NSRect(x: 90, y: 560, width: 150, height: 150))
    func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat, at p: NSPoint) {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white.withAlphaComponent(alpha)]).draw(at: p)
    }
    text("Counter Trade", 64, .bold, 1, at: NSPoint(x: 90, y: 470))
    text("Счётчик побед и поражений", 30, .regular, 0.7, at: NSPoint(x: 90, y: 410))
    text("поверх экрана для трейдинга", 30, .regular, 0.7, at: NSPoint(x: 90, y: 366))
    func shot(_ path: String, x: CGFloat, height: CGFloat) {
        let s = NSImage(contentsOfFile: path)!
        let w = height * s.size.width / s.size.height
        let r = NSRect(x: x, y: (H - height) / 2, width: w, height: height)
        NSGraphicsContext.current!.cgContext.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: NSColor.black.withAlphaComponent(0.7).cgColor)
        s.draw(in: r)
    }
    shot("docs/counter.png", x: 640, height: 300)
    shot("docs/history.png", x: 1100, height: 640)
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/hero.png"))
