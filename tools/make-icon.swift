// Рисует иконку Counter Trade. Запуск: ./tools/make-icon.sh
import AppKit

func draw(_ s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        let inset = s * 0.098
        let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        NSColor.black.setFill(); path.fill()
        ctx.restoreGState()
        path.addClip()
        NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.05, alpha: 1)])!.draw(in: body, angle: -90)

        // Кольцо винрейта: зелёная дуга побед и красная поражений.
        let c = CGPoint(x: s / 2, y: s / 2)
        let r = s * 0.285, w = s * 0.07
        let win = 0.68, gap = 0.012
        func arc(_ from: Double, _ to: Double, _ color: NSColor) {
            let p = NSBezierPath()
            p.appendArc(withCenter: c, radius: r, startAngle: 90 - CGFloat(from) * 360, endAngle: 90 - CGFloat(to) * 360, clockwise: true)
            p.lineWidth = w; p.lineCapStyle = .round
            color.setStroke(); p.stroke()
        }
        let green = NSColor(red: 0.20, green: 0.84, blue: 0.45, alpha: 1)
        let red = NSColor(red: 1.0, green: 0.30, blue: 0.30, alpha: 1)
        let cap = Double(w / (2 * .pi * r)) // компенсация скруглённых концов
        arc(gap / 2 + cap / 2, win - gap / 2 - cap / 2, green)
        arc(win + gap / 2 + cap / 2, 1 - gap / 2 - cap / 2, red)

        // В центре: винрейт.
        let font = NSFont.systemFont(ofSize: s * 0.17, weight: .bold)
        let str = NSAttributedString(string: "68%", attributes: [.font: font, .foregroundColor: NSColor.white])
        let sz = str.size()
        str.draw(at: CGPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2))
        return true
    }
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    let rep = NSBitmapImageRep(data: draw(CGFloat(px)).tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
