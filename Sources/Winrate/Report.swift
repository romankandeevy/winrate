import Foundation

/// Сводка для ИИ: весь архив одним текстом, чтобы вставить в чат и спросить «что я делаю не так».
@MainActor
enum Report {
    private static func pct(_ w: Int, _ t: Int) -> String { t == 0 ? "—" : String(format: "%.1f%%", Double(w) / Double(t) * 100) }
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
    private static let month: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"; return f
    }()

    private static func longest(_ s: String, _ ch: Character) -> Int {
        var best = 0, cur = 0
        for c in s { if c == ch { cur += 1; best = max(best, cur) } else { cur = 0 } }
        return best
    }

    /// Счёт «после чего что»: сколько раз после заданного префикса следующая сделка была победой.
    private static func after(_ prefix: String, in trades: [String]) -> (wins: Int, total: Int) {
        var w = 0, t = 0
        let p = Array(prefix)
        for s in trades {
            let a = Array(s)
            guard a.count > p.count else { continue }
            for i in p.count..<a.count where Array(a[(i - p.count)..<i]) == p {
                t += 1; if a[i] == "w" { w += 1 }
            }
        }
        return (w, t)
    }

    static func make(_ store: Store) -> String {
        var all = store.sessions
        if !store.history.isEmpty { all.append(Session(start: store.currentStart ?? Date(), end: Date(), trades: store.currentTrades)) }
        let trades = all.map(\.trades)
        let totalW = all.reduce(0) { $0 + $1.wins }, totalN = all.reduce(0) { $0 + $1.total }
        var o = ""
        o += "# Counter Trade: сводка для анализа\n\n"
        o += "Сформировано: \(stamp.string(from: Date())) (\(TimeZone.current.identifier)).\n"
        o += "Это журнал побед и поражений трейдера. Данных о размере сделок, инструментах и риске нет - только порядок и время результатов.\n"
        o += "Обозначения: w = победа, l = поражение. Строка сделок идёт в хронологическом порядке внутри сессии. Сессия = то, что трейдер сохранил кнопкой «Сохранить».\n\n"

        o += "## Итого\n"
        o += "- Сделок: \(totalN), побед: \(totalW), поражений: \(totalN - totalW), винрейт: \(pct(totalW, totalN))\n"
        o += "- Сессий: \(all.count)" + (store.history.isEmpty ? "" : " (последняя ещё идёт)") + "\n"
        if let f = all.first, let l = all.last { o += "- Период: \(stamp.string(from: f.start)) - \(stamp.string(from: l.end))\n" }
        if !all.isEmpty { o += "- Среднее сделок за сессию: \(String(format: "%.1f", Double(totalN) / Double(all.count)))\n" }
        o += "- Самая длинная серия побед: \(trades.map { longest($0, "w") }.max() ?? 0), серия поражений: \(trades.map { longest($0, "l") }.max() ?? 0)\n"
        let ranked = all.filter { $0.total >= 5 }
        if let best = ranked.max(by: { Double($0.wins) / Double($0.total) < Double($1.wins) / Double($1.total) }),
           let worst = ranked.min(by: { Double($0.wins) / Double($0.total) < Double($1.wins) / Double($1.total) }) {
            o += "- Лучшая сессия (от 5 сделок): \(stamp.string(from: best.start)), \(best.wins):\(best.losses), \(pct(best.wins, best.total))\n"
            o += "- Худшая сессия (от 5 сделок): \(stamp.string(from: worst.start)), \(worst.wins):\(worst.losses), \(pct(worst.wins, worst.total))\n"
        }

        o += "\n## Поведение после результата (признаки тильта и эйфории)\n"
        for (title, prefix) in [("После победы", "w"), ("После поражения", "l"), ("После 2 поражений подряд", "ll"), ("После 3 поражений подряд", "lll"), ("После 3 побед подряд", "www")] {
            let r = after(prefix, in: trades)
            o += "- \(title): следующая сделка выиграна в \(pct(r.wins, r.total)) (\(r.total) случаев)\n"
        }

        let long = all.filter { $0.total >= 10 }
        if !long.isEmpty {
            var fw = 0, ft = 0, sw = 0, st = 0
            for s in long {
                let a = Array(s.trades), h = a.count / 2
                fw += a[..<h].filter { $0 == "w" }.count; ft += h
                sw += a[h...].filter { $0 == "w" }.count; st += a.count - h
            }
            o += "\n## Усталость внутри сессии (сессии от 10 сделок: \(long.count))\n"
            o += "- Первая половина сессий: \(pct(fw, ft)), вторая половина: \(pct(sw, st))\n"
        }

        if all.count >= 3 {
            let cal = Calendar.current
            func block(_ title: String, _ key: (Session) -> String, _ order: [String]) {
                var d: [String: (Int, Int)] = [:]
                for s in all { let k = key(s); let v = d[k] ?? (0, 0); d[k] = (v.0 + s.wins, v.1 + s.total) }
                o += "\n## \(title)\n"
                for k in order { if let v = d[k] { o += "- \(k): \(pct(v.0, v.1)) (\(v.1) сделок)\n" } }
            }
            block("Винрейт по времени начала сессии", { s in
                let h = cal.component(.hour, from: s.start)
                return h < 12 ? "утро (до 12:00)" : h < 17 ? "день (12-17)" : "вечер (с 17:00)"
            }, ["утро (до 12:00)", "день (12-17)", "вечер (с 17:00)"])
            let days = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
            block("Винрейт по дням недели", { days[cal.component(.weekday, from: $0.start) - 1] }, ["пн", "вт", "ср", "чт", "пт", "сб", "вс"])
        }

        if all.count >= 6 {
            let recent = all.suffix(10), older = all.dropLast(10)
            let rw = recent.reduce(0) { $0 + $1.wins }, rt = recent.reduce(0) { $0 + $1.total }
            let ow = older.reduce(0) { $0 + $1.wins }, ot = older.reduce(0) { $0 + $1.total }
            o += "\n## Динамика\n- Последние \(recent.count) сессий: \(pct(rw, rt)); все более ранние: \(pct(ow, ot))\n"
        }

        let detailed = all.suffix(300), old = all.dropLast(detailed.count)
        if !old.isEmpty {
            o += "\n## Старые сессии по месяцам (\(old.count) сессий)\n| Месяц | Сессий | Сделок | Винрейт |\n|---|---|---|---|\n"
            var months: [(String, Int, Int, Int)] = []
            for s in old {
                let k = month.string(from: s.start)
                if let i = months.firstIndex(where: { $0.0 == k }) { months[i].1 += 1; months[i].2 += s.total; months[i].3 += s.wins }
                else { months.append((k, 1, s.total, s.wins)) }
            }
            for m in months { o += "| \(m.0) | \(m.1) | \(m.2) | \(pct(m.3, m.2)) |\n" }
        }
        o += "\n## Сессии\(all.count > 300 ? " (последние 300)" : "")\n| # | Начало | Конец | W:L | Винрейт | Серия L | Сделки |\n|---|---|---|---|---|---|---|\n"
        let offset = all.count - detailed.count
        for (i, s) in detailed.enumerated() {
            o += "| \(offset + i + 1) | \(stamp.string(from: s.start)) | \(stamp.string(from: s.end)) | \(s.wins):\(s.losses) | \(pct(s.wins, s.total)) | \(longest(s.trades, "l")) | \(s.trades) |\n"
        }

        o += "\n## Задача\nПроанализируй этот журнал. Найди закономерности: серии поражений, влияние времени суток и дня недели, поведение после проигрышей (тильт), усталость в длинных сессиях, динамику. Скажи, что со мной не так, и дай 3-5 конкретных правил, которые стоит ввести. Если данных мало для вывода, так и скажи. Не делай вид, что знаешь размер сделок или инструменты: их здесь нет.\n"
        o += "\n(Файлы данных: \(store.folder.path))\n"
        return o
    }
}
