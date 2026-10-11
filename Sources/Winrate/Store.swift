import Foundation
import Observation

/// Завершённая сессия: сделки по порядку строкой «wlw…» и время начала и конца.
struct Session: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date
    var trades: String
    // Считаются один раз при создании: история может быть огромной, пересчитывать строки на каждый кадр нельзя.
    let wins: Int
    let total: Int

    var losses: Int { total - wins }
    var rate: Int { total == 0 ? 0 : Int((Double(wins) / Double(total) * 100).rounded()) }

    init(start: Date, end: Date, trades: String, id: UUID = UUID()) {
        self.id = id; self.start = start; self.end = end; self.trades = trades
        wins = trades.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "w") ? 1 : 0) }
        total = trades.utf8.count
    }

    private enum CodingKeys: String, CodingKey { case id, start, end, trades }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try c.decode(Date.self, forKey: .start), end: try c.decode(Date.self, forKey: .end),
                  trades: try c.decode(String.self, forKey: .trades), id: try c.decode(UUID.self, forKey: .id))
    }
}

/// Текущая, ещё не закрытая сессия: лежит отдельным маленьким файлом, пишется на каждый клик.
private struct CurrentFile: Codable {
    var trades: String
    var start: Date?
}

/// Счёт, текущая сессия и архив сессий.
/// Хранение: ~/Library/Application Support/Winrate/
///   sessions.jsonl - архив, по сессии на строку; новые дописываются в конец, старое никогда не удаляется само
///   current.json   - текущая сессия
@MainActor
@Observable
final class Store {
    enum Side { case win, loss }
    /// Последнее действие: по нему половины окна играют свою анимацию.
    struct Event: Equatable { let id: Int; let side: Side; let undo: Bool }

    private(set) var wins = 0
    private(set) var losses = 0
    private(set) var history: [Side] = []
    private(set) var event: Event?
    /// Мышь давно не над окном: окно бледнеет.
    var idle = false
    /// Растёт, когда набралась серия из трёх побед подряд (и дальше каждые три): по нему идёт конфетти.
    private(set) var confettiID = 0
    private(set) var sessions: [Session] = []
    /// Суммы по архиву, чтобы сводка не пересчитывала всё при каждой перерисовке.
    private(set) var archiveWins = 0
    private(set) var archiveTotal = 0
    /// Когда начата текущая сессия (время первой сделки).
    private(set) var currentStart: Date?
    /// Развёрнута ли история под счётчиком; окно подстраивает высоту через onHistoryToggle.
    private(set) var showHistory = false
    @ObservationIgnored var onHistoryToggle: ((Bool) -> Void)?
    private var eventCounter = 0

    let folder: URL
    private var sessionsURL: URL { folder.appendingPathComponent("sessions.jsonl") }
    private var currentURL: URL { folder.appendingPathComponent("current.json") }
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Winrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        migrateFromDefaultsIfNeeded()
        load()
    }

    var total: Int { wins + losses }
    var rate: Int? { total == 0 ? nil : Int((Double(wins) / Double(total) * 100).rounded()) }
    var lastSide: Side? { history.last }
    /// Сколько побед подряд в конце истории.
    var winStreak: Int { history.reversed().prefix { $0 == .win }.count }
    var currentTrades: String { String(history.map { $0 == .win ? "w" : "l" }) }

    // MARK: Действия

    func add(_ side: Side) {
        if history.isEmpty { currentStart = Date() }
        history.append(side)
        side == .win ? (wins += 1) : (losses += 1)
        fire(side, undo: false)
        if side == .win, winStreak % 3 == 0 { confettiID += 1 }
    }

    func undo() {
        guard let side = history.popLast() else { return }
        side == .win ? (wins -= 1) : (losses -= 1)
        if history.isEmpty { currentStart = nil }
        fire(side, undo: true)
    }

    /// Закрывает текущую сессию: кладёт её в архив и обнуляет счётчик.
    func newSession() {
        guard !history.isEmpty else { return }
        let s = Session(start: currentStart ?? Date(), end: Date(), trades: currentTrades)
        sessions.append(s)
        append(s)
        recount()
        wins = 0; losses = 0; history = []; currentStart = nil
        saveCurrent()
    }

    /// Обнуляет текущий счёт без сохранения в архив.
    func reset() {
        guard !history.isEmpty else { return }
        wins = 0; losses = 0; history = []; currentStart = nil
        saveCurrent()
    }

    /// Единственный способ потерять данные - явно удалить сессию из списка.
    func deleteSession(_ id: Session.ID) {
        sessions.removeAll { $0.id == id }
        recount()
        rewriteArchive()
    }

    func toggleHistory() {
        showHistory.toggle()
        onHistoryToggle?(showHistory)
    }

    // MARK: Хранение

    private func fire(_ side: Side, undo: Bool) {
        eventCounter += 1
        event = Event(id: eventCounter, side: side, undo: undo)
        saveCurrent()
    }

    private func recount() {
        archiveWins = sessions.reduce(0) { $0 + $1.wins }
        archiveTotal = sessions.reduce(0) { $0 + $1.total }
    }

    private func load() {
        if let data = try? Data(contentsOf: currentURL), let cur = try? Self.decoder.decode(CurrentFile.self, from: data) {
            history = cur.trades.compactMap { $0 == "w" ? .win : $0 == "l" ? .loss : nil }
            currentStart = cur.start
        }
        wins = history.filter { $0 == .win }.count
        losses = history.count - wins
        if !history.isEmpty && currentStart == nil { currentStart = Date() }
        if let text = try? String(contentsOf: sessionsURL, encoding: .utf8) {
            sessions = text.split(separator: "\n").compactMap { try? Self.decoder.decode(Session.self, from: Data($0.utf8)) }
        }
        recount()
    }

    private func saveCurrent() {
        let file = CurrentFile(trades: currentTrades, start: currentStart)
        if let data = try? Self.encoder.encode(file) { try? data.write(to: currentURL, options: .atomic) }
    }

    private func append(_ s: Session) {
        guard let line = try? Self.encoder.encode(s) else { return }
        let data = line + Data("\n".utf8)
        if let h = try? FileHandle(forWritingTo: sessionsURL) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: sessionsURL)
        }
    }

    private func rewriteArchive() {
        var out = Data()
        for s in sessions { if let l = try? Self.encoder.encode(s) { out += l; out += Data("\n".utf8) } }
        try? out.write(to: sessionsURL, options: .atomic)
    }

    /// Первая версия хранила всё в настройках приложения: один раз переносим в файлы, старое не трогаем.
    private func migrateFromDefaultsIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: sessionsURL.path), !fm.fileExists(atPath: currentURL.path) else { return }
        let d = UserDefaults.standard
        let legacyTrades = d.string(forKey: "history") ?? ""
        let legacyStart = d.object(forKey: "currentStart") as? Date
        if let data = d.data(forKey: "sessions"), let old = try? JSONDecoder().decode([Session].self, from: data) {
            sessions = old
            rewriteArchive()
            sessions = []
        }
        if !legacyTrades.isEmpty {
            let file = CurrentFile(trades: legacyTrades, start: legacyStart)
            if let data = try? Self.encoder.encode(file) { try? data.write(to: currentURL, options: .atomic) }
        }
    }
}
