import AppKit
import SwiftUI

private let ruLocale = Locale(identifier: "ru_RU")

private func dayTitle(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Сегодня" }
    if cal.isDateInYesterday(date) { return "Вчера" }
    let f = DateFormatter(); f.locale = ruLocale
    f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM yyyy"
    return f.string(from: date)
}

private func shortDate(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = ruLocale; f.dateFormat = "d MMM"
    return f.string(from: date)
}

private func timeRange(_ s: Session) -> String {
    let f = DateFormatter(); f.locale = ruLocale; f.dateFormat = "HH:mm"
    return "\(f.string(from: s.start)) – \(f.string(from: s.end))"
}

/// Точка графика: одна сессия, а если сессий очень много - несколько подряд, слитых в одну.
private struct Bucket {
    let sessions: ClosedRange<Int>
    let wins: Int
    let total: Int
    let start: Date
    let end: Date
    var rate: Int { total == 0 ? 0 : Int((Double(wins) / Double(total) * 100).rounded()) }
}

/// Нижняя часть окна: итоги, график винрейта по сессиям и список. Открывается кнопкой «История».
/// Данные не ограничены по времени и количеству: график сжимает длинную историю, список ленивый.
struct HistoryView: View {
    enum Span: CaseIterable {
        case ten, thirty, all
        var title: String { self == .ten ? "10" : self == .thirty ? "30" : "Всё" }
        var limit: Int? { self == .ten ? 10 : self == .thirty ? 30 : nil }
    }

    let store: Store
    @State private var span = Span.all
    @State private var hover: Int?
    @State private var selection: ClosedRange<Int>?
    @State private var copied = false

    private var sessions: [Session] { store.sessions }

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                VStack(spacing: 6) {
                    Text("Пока нет сессий").font(.system(size: 13, weight: .medium))
                    Text("Нажми «Сохранить», чтобы записать текущую\nсессию в историю.")
                        .font(.system(size: 12)).foregroundStyle(Palette.mute).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            } else {
                summary
                chart
                controls
                list
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        .onChange(of: sessions.count) { _, _ in selection = nil; hover = nil }
    }

    // MARK: Итоги

    private var summary: some View {
        let total = store.archiveTotal
        let avg = total == 0 ? 0 : Int((Double(store.archiveWins) / Double(total) * 100).rounded())
        return HStack(spacing: 0) {
            cell("\(avg)%", "Средний", color: rateColor(avg))
            Rectangle().fill(Palette.line).frame(width: 1)
            cell("\(total)", "Сделок")
            Rectangle().fill(Palette.line).frame(width: 1)
            cell("\(sessions.count)", "Сессий")
        }
        .frame(height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func cell(_ value: String, _ caption: String, color: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .light)).monospacedDigit().foregroundStyle(color)
            Text(caption.uppercased()).font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(Palette.mute)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: График

    private var buckets: [Bucket] {
        let all = sessions
        let from = span.limit.map { max(0, all.count - $0) } ?? 0
        let n = all.count - from
        guard n > 0 else { return [] }
        let size = max(1, Int((Double(n) / 80).rounded(.up)))   // не больше ~80 точек на график
        return stride(from: from, to: all.count, by: size).map { lo in
            let hi = min(lo + size, all.count) - 1
            var w = 0, t = 0
            for i in lo...hi { w += all[i].wins; t += all[i].total }
            return Bucket(sessions: lo...hi, wins: w, total: t, start: all[lo].start, end: all[hi].end)
        }
    }

    private func label(_ b: Bucket) -> String {
        let n = b.sessions.count
        if n == 1 { return "\(dayTitle(b.start)) · \(b.wins):\(b.total - b.wins) · \(b.rate)%" }
        return "\(shortDate(b.start)) – \(shortDate(b.end)) · \(n) сесс. · \(b.rate)%"
    }

    private var chart: some View {
        let bs = buckets
        return VStack(spacing: 3) {
            GeometryReader { g in
                let pts: [CGPoint] = bs.enumerated().map { i, b in
                    let x = bs.count == 1 ? g.size.width / 2 : 6 + (g.size.width - 12) * CGFloat(i) / CGFloat(bs.count - 1)
                    return CGPoint(x: x, y: 4 + (g.size.height - 8) * (1 - CGFloat(b.rate) / 100))
                }
                let dense = bs.count > 30
                ZStack {
                    Path { p in p.move(to: CGPoint(x: 0, y: g.size.height / 2)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 2)) }
                        .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                            pts.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                        }
                        .fill(LinearGradient(colors: [Palette.win.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                        Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                            .stroke(Palette.win.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    }
                    // Выбранный отрезок (кликом по графику) подсвечен полосой.
                    if let sel = selection, let first = bs.firstIndex(where: { $0.sessions.overlaps(sel) }),
                       let last = bs.lastIndex(where: { $0.sessions.overlaps(sel) }) {
                        let x0 = pts[first].x - 5, x1 = pts[last].x + 5
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.09))
                            .frame(width: max(10, x1 - x0), height: g.size.height)
                            .position(x: (x0 + x1) / 2, y: g.size.height / 2)
                    }
                    if !dense {
                        ForEach(Array(bs.enumerated()), id: \.offset) { i, b in
                            Circle().fill(rateColor(b.rate)).frame(width: 6, height: 6).position(pts[i])
                        }
                    }
                    if let h = hover, h < pts.count {
                        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: g.size.height).position(x: pts[h].x, y: g.size.height / 2)
                        Circle().fill(rateColor(bs[h].rate)).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Palette.background, lineWidth: 2)).position(pts[h])
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc): hover = nearest(loc.x, pts)
                    case .ended: hover = nil
                    }
                }
                .gesture(SpatialTapGesture().onEnded { v in
                    guard let i = nearest(v.location.x, pts) else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        selection = selection == bs[i].sessions ? nil : bs[i].sessions
                    }
                })
            }
            .frame(height: 52)
            ZStack {
                if let h = hover, h < bs.count {
                    Text(label(bs[h])).foregroundStyle(.white)
                } else {
                    HStack {
                        Text(bs.first.map { dayTitle($0.start) } ?? "")
                        Spacer()
                        if bs.count > 1 { Text(bs.last.map { dayTitle($0.start) } ?? "") }
                    }
                }
            }
            .font(.system(size: 10)).foregroundStyle(Palette.mute)
            .frame(height: 13)
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.35), value: span)
    }

    private func nearest(_ x: CGFloat, _ pts: [CGPoint]) -> Int? {
        pts.indices.min { abs(pts[$0].x - x) < abs(pts[$1].x - x) }
    }

    // MARK: Управление

    private var controls: some View {
        HStack(spacing: 4) {
            if !sessions.isEmpty {
                ForEach(Span.allCases, id: \.self) { s in
                    Button { withAnimation(.easeOut(duration: 0.2)) { span = s; selection = nil; hover = nil } } label: {
                        Text(s.title).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(span == s ? .white : Palette.mute)
                            .padding(.horizontal, 9).frame(height: 22)
                            .background(Capsule().fill(Color.white.opacity(span == s ? 0.1 : 0)))
                    }
                    .buttonStyle(.plain)
                }
                if selection != nil {
                    Button { withAnimation { selection = nil } } label: {
                        Text("снять выделение").font(.system(size: 10)).foregroundStyle(Palette.mute).padding(.leading, 4)
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            Button(action: copyReport) {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .medium))
                    Text(copied ? "Скопировано" : "Сводка для ИИ").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(copied ? Palette.win : Color.white.opacity(0.8))
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Копирует весь журнал текстом: вставь в ИИ и спроси, что не так")
        }
        .padding(.horizontal, 10).frame(height: 30)
        .overlay(alignment: .top) { if !sessions.isEmpty { Rectangle().fill(Palette.line).frame(height: 1) } }
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Report.make(store), forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { copied = false }
        }
    }

    // MARK: Список

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sessions.indices.reversed()), id: \.self) { i in
                        row(i)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, sel in
                if let sel { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(sel.upperBound, anchor: .center) } }
            }
        }
    }

    private func row(_ i: Int) -> some View {
        let s = sessions[i]
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(dayTitle(s.start)).font(.system(size: 13, weight: .medium))
                Text("\(timeRange(s)) · \(s.total)").font(.system(size: 11)).foregroundStyle(Palette.mute)
            }
            Spacer()
            HStack(spacing: 3) {
                Text("\(s.wins)").foregroundStyle(Palette.win)
                Text(":").foregroundStyle(Palette.mute)
                Text("\(s.losses)").foregroundStyle(Palette.loss)
            }
            .font(.system(size: 13)).monospacedDigit()
            Text("\(s.rate)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(rateColor(s.rate))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(rateColor(s.rate).opacity(0.16)))
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Color.white.opacity(selection?.contains(i) == true ? 0.07 : 0))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1) }
        .contextMenu { Button("Удалить сессию", role: .destructive) { store.deleteSession(s.id) } }
    }
}
