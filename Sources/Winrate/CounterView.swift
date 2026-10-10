import SwiftUI

/// Высота частей окна: счётчик всегда виден, история выезжает под ним.
enum Layout {
    static let counter: CGFloat = 196
    static let history: CGFloat = 340
}

enum Palette {
    static let background = Color(red: 0.02, green: 0.02, blue: 0.025)
    static let win = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let loss = Color(red: 0.97, green: 0.44, blue: 0.44)
    static let mute = Color(red: 0.49, green: 0.50, blue: 0.56)
    static let line = Color.white.opacity(0.07)
}

/// Цвет винрейта: от красного (0%) через жёлтый (50%) к зелёному (100%). Сразу видно, хорошо идёт или плохо.
func rateColor(_ rate: Int?) -> Color {
    guard let rate else { return Palette.mute }
    return Color(hue: 0.36 * Double(rate) / 100, saturation: 0.62, brightness: 0.97)
}

private func tradesWord(_ n: Int) -> String {
    let a = n % 10, b = n % 100
    if a == 1 && b != 11 { return "сделка" }
    if (2...4).contains(a) && !(12...14).contains(b) { return "сделки" }
    return "сделок"
}

struct CounterView: View {
    let store: Store
    var body: some View {
        // Окно то короткое, то высокое. Содержимое полной высоты лежит поверх пустого контейнера, прижатое к верху,
        // и просто обрезается краем окна: так оно не «ездит» при смене высоты.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background.opacity(store.idle ? 0.82 : 1))
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    counter
                    HistoryView(store: store).frame(width: 300, height: Layout.history)
                }
                .frame(width: 300, height: Layout.counter + Layout.history)
            }
            .clipped()
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
    }

    private var counter: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                HalfButton(store: store, side: .win)
                Rectangle().fill(Palette.line).frame(width: 1)
                HalfButton(store: store, side: .loss)
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            footer
        }
        .frame(width: 300, height: Layout.counter)
        .overlay { ConfettiLayer(trigger: store.confettiID) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            ratioBar
            Text(store.rate.map { "\($0)%" } ?? "—")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(rateColor(store.rate))
                .contentTransition(.numericText(value: Double(store.rate ?? 0)))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(rateColor(store.rate).opacity(store.rate == nil ? 0 : 0.16)))
            Text("\(store.total) \(tradesWord(store.total))")
                .font(.system(size: 12))
                .foregroundStyle(Palette.mute)
                .contentTransition(.numericText(value: Double(store.total)))
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: store.total)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: store.wins)
        .animation(.easeInOut(duration: 0.5), value: store.rate)
    }

    private var ratioBar: some View {
        let share = store.total == 0 ? 0 : Double(store.wins) / Double(store.total)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.12))
            GeometryReader { g in
                Capsule().fill(rateColor(store.rate)).frame(width: g.size.width * share)
            }
        }
        .frame(width: 44, height: 3)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            FooterButton(
                icon: "arrow.uturn.backward",
                title: store.lastSide == .win ? "Undo win" : store.lastSide == .loss ? "Undo loss" : "Undo",
                enabled: store.lastSide != nil
            ) { withAnimation(.spring(duration: 0.45, bounce: 0.2)) { store.undo() } }
            FooterButton(icon: "square.and.arrow.down", title: "Сохранить", enabled: store.total > 0) {
                withAnimation(.spring(duration: 0.45, bounce: 0.2)) { store.newSession() }
            }
            .help("Сохранить сессию в историю и начать счёт с нуля")
            FooterButton(icon: "list.bullet", title: "История", enabled: true, active: store.showHistory) {
                store.toggleHistory()
            }
        }
        .padding(6)
        .frame(height: 40)
    }
}

/// Половина окна - большая кнопка: число, подпись, вспышка и всплывающие «+1 / −1».
private struct HalfButton: View {
    let store: Store
    let side: Store.Side
    @State private var hovering = false
    @State private var flash = 0.0
    @State private var flashIsUndo = false
    @State private var badge = ""
    @State private var badgeY = 0.0
    @State private var badgeOpacity = 0.0

    private var isWin: Bool { side == .win }
    private var color: Color { isWin ? Palette.win : Palette.loss }
    private var value: Int { isWin ? store.wins : store.losses }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) { store.add(side) }
        } label: {
            ZStack {
                Rectangle().fill(color.opacity(hovering ? 0.06 : 0))
                Rectangle().fill((flashIsUndo ? Color.white : color).opacity(flash))
                VStack(spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 68, weight: .thin))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .shadow(color: color.opacity(0.25), radius: 5)
                        .contentTransition(.numericText(value: Double(value)))
                        .frame(height: 68)
                    Text(isWin ? "WINS" : "LOSSES")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(Palette.mute)
                }
                .padding(.top, 2)
            }
            .overlay(alignment: .topLeading) {
                Text(isWin ? "←" : "→")
                    .font(.system(size: 10)).foregroundStyle(Palette.mute)
                    .opacity(hovering ? 0.8 : 0).padding(9)
            }
            .overlay(alignment: .topTrailing) {
                Text("+").font(.system(size: 15)).foregroundStyle(color)
                    .opacity(hovering ? 0.7 : 0).padding(.top, 5).padding(.trailing, 10)
            }
            .overlay(alignment: .topTrailing) {
                Text(badge).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                    .opacity(badgeOpacity).offset(y: badgeY).padding(.top, 26).padding(.trailing, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipped()
        .help(isWin ? "Победа (←)" : "Поражение (→)")
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
        .onChange(of: store.event) { _, e in
            guard let e, e.side == side else { return }
            play(undo: e.undo)
        }
    }

    private func play(undo: Bool) {
        // Вспышка: мгновенно яркая, затем гаснет. Отмена - тусклая белая, «+1» летит вверх, «−1» вниз.
        flashIsUndo = undo
        flash = undo ? 0.07 : 0.16
        withAnimation(.easeOut(duration: 0.4)) { flash = 0 }
        let dir: Double = undo ? 1 : -1
        badge = undo ? "−1" : "+1"
        badgeY = -dir * 6; badgeOpacity = 0
        withAnimation(.easeOut(duration: 0.14)) { badgeOpacity = 1 }
        withAnimation(.easeOut(duration: 0.7)) { badgeY = dir * 18 }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeIn(duration: 0.4)) { badgeOpacity = 0 }
        }
    }
}

private struct FooterButton: View {
    let icon: String
    let title: String
    let enabled: Bool
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(enabled ? Color.white.opacity(hovering || active ? 1 : 0.78) : Color.white.opacity(0.25))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(active ? 0.1 : hovering && enabled ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Конфетти из-под левой половины: сильный выброс вверх веером, воздух гасит скорость, потом бумажки падают и тают.
private struct ConfettiLayer: View {
    let trigger: Int
    private struct Piece {
        let vx, vy: Double      // стартовая скорость, pt/s
        let size: Double
        let spin: Double        // рад/с
        let flutter: Double     // частота покачивания
        let phase: Double
        let color: Color
        let round: Bool
    }
    @State private var pieces: [Piece] = []
    @State private var start: Date?
    private let duration = 2.6
    private let colors: [Color] = [
        Color(red: 0.36, green: 0.92, blue: 0.56), Color(red: 1.0, green: 0.84, blue: 0.36),
        Color(red: 0.45, green: 0.72, blue: 1.0), Color(red: 1.0, green: 0.55, blue: 0.78),
        Color(red: 0.98, green: 0.45, blue: 0.45), .white
    ]

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            Canvas { ctx, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                guard t < duration else { return }
                let origin = CGPoint(x: size.width * 0.25, y: size.height * 0.80)
                let drag = exp(-1.6 * t)                    // воздух: быстро тормозит и потом почти стоит
                for p in pieces {
                    let x = origin.x + p.vx * (1 - exp(-1.6 * t)) / 1.6 + sin(t * p.flutter + p.phase) * 14
                    let y = origin.y + p.vy * (1 - exp(-1.6 * t)) / 1.6 + 260 * (t - (1 - exp(-1.6 * t)) / 1.6)
                    let fade = min(1, (duration - t) / 0.8) * min(1, t / 0.05)
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.phase + p.spin * t))
                    c.scaleBy(x: 1, y: max(0.15, abs(cos(p.phase + p.spin * t * 0.7))))   // бумажка переворачивается
                    c.opacity = fade * (0.6 + 0.4 * drag)
                    let rect = CGRect(x: -p.size / 2, y: -p.size * 0.35, width: p.size, height: p.size * 0.7)
                    let path = p.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.2)
                    c.fill(path, with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        pieces = (0..<90).map { _ in
            let angle = Double.random(in: -115 ... -55) * .pi / 180   // узкий веер вверх
            let speed = Double.random(in: 380 ... 820)
            return Piece(vx: cos(angle) * speed * .random(in: 0.6 ... 1.4),
                         vy: sin(angle) * speed,
                         size: .random(in: 6 ... 11),
                         spin: .random(in: -7 ... 7),
                         flutter: .random(in: 3 ... 7),
                         phase: .random(in: 0 ... 6.28),
                         color: colors.randomElement()!,
                         round: Bool.random())
        }
        start = Date()
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.1))
            start = nil
        }
    }
}
