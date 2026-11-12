import Foundation

struct SongEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var fileName: String
    var added: Date
    var bestAccuracy: Double?
    var plays: Int
    var practiceSeconds: Double
    var lastPlayed: Date?
    var favorite: Bool?
    var difficulty: Int?
    var bestScore: Int?
    var bestStars: Int?
    var bestTempo: Double?
    var sourceURL: String?      // Herkunft aus dem Song-Katalog
    var license: String?
    var composer: String?

    var isFavorite: Bool { favorite ?? false }

    /// Lernstufe nach Flowkey-Prinzip
    var mastery: (label: String, level: Int) {
        let acc = bestAccuracy ?? 0
        let tempo = bestTempo ?? 0
        if plays == 0 { return ("Neu", 0) }
        if acc >= 0.95 && tempo >= 1.0 { return ("Gemeistert", 4) }
        if acc >= 0.9 && tempo >= 0.8 { return ("Gefestigt", 3) }
        if acc >= 0.7 { return ("Üben", 2) }
        return ("Lernen", 1)
    }
}

struct PracticeSession: Codable, Identifiable {
    var id: UUID
    var date: Date
    var songID: UUID?
    var title: String
    var seconds: Double
    var accuracy: Double?
    var stars: Int?
    var score: Int?
    var mode: String
}

struct Achievement: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let unlocked: Bool
}

struct DayStat: Identifiable {
    var id: Date { day }
    let day: Date
    let minutes: Double
}

final class LibraryStore: ObservableObject {
    @Published var songs: [SongEntry] = []
    @Published var sessions: [PracticeSession] = []
    let songsDir: URL
    private let indexURL: URL
    private let sessionsURL: URL

    static let vaultLog = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Second Brain/Hobbys/PianoFlow – Übungslog.md")

    init() {
        let base = ProcessInfo.processInfo.environment["PF_LIBRARY_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PianoFlow", isDirectory: true)
        songsDir = base.appendingPathComponent("Songs", isDirectory: true)
        indexURL = base.appendingPathComponent("library.json")
        sessionsURL = base.appendingPathComponent("sessions.json")
        try? FileManager.default.createDirectory(at: songsDir, withIntermediateDirectories: true)
        load()
        importDemoIfNeeded()
        fillMissingDifficulty()
    }

    func url(for entry: SongEntry) -> URL { songsDir.appendingPathComponent(entry.fileName) }

    // MARK: Laden / Speichern

    private func load() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: indexURL) {
            songs = (try? dec.decode([SongEntry].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: sessionsURL) {
            sessions = (try? dec.decode([PracticeSession].self, from: data)) ?? []
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(songs) { try? data.write(to: indexURL, options: .atomic) }
        if let data = try? enc.encode(sessions) { try? data.write(to: sessionsURL, options: .atomic) }
    }

    private func importDemoIfNeeded() {
        let key = "demoImported"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if let demo = Bundle.main.url(forResource: "Fuer Elise (Demo)", withExtension: "mid") {
            importFiles([demo])
        }
    }

    private func fillMissingDifficulty() {
        var changed = false
        // Skala v2 (Anschläge je Hand statt Notenzahl): einmalig alles neu bewerten
        let recompute = UserDefaults.standard.integer(forKey: "difficultyVersion") < 3
        UserDefaults.standard.set(3, forKey: "difficultyVersion")
        for i in songs.indices where songs[i].difficulty == nil || recompute {
            if let s = try? MidiSong.load(url: url(for: songs[i])) {
                songs[i].difficulty = s.difficulty
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: Songs

    @discardableResult
    func importFiles(_ urls: [URL]) -> [SongEntry] {
        var added: [SongEntry] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let files = (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
                for f in files { if let e = importOne(f) { added.append(e) } }
            } else if let e = importOne(url) {
                added.append(e)
            }
        }
        if !added.isEmpty { save() }
        return added
    }

    private func importOne(_ url: URL) -> SongEntry? {
        guard ["mid", "midi", "kar"].contains(url.pathExtension.lowercased()) else { return nil }
        guard let song = try? MidiSong.load(url: url) else { return nil }
        let id = UUID()
        let fileName = "\(id.uuidString).mid"
        do {
            try FileManager.default.copyItem(at: url, to: songsDir.appendingPathComponent(fileName))
        } catch { return nil }
        let e = SongEntry(id: id, title: url.deletingPathExtension().lastPathComponent, fileName: fileName,
                          added: Date(), bestAccuracy: nil, plays: 0, practiceSeconds: 0, lastPlayed: nil,
                          favorite: false, difficulty: song.difficulty)
        songs.append(e)
        return e
    }

    /// Eigene Aufnahme oder generierte Übung als Song speichern
    @discardableResult
    func addSong(title: String, notes: [NoteEvent], bpm: Double = 120) -> SongEntry? {
        guard !notes.isEmpty else { return nil }
        let id = UUID()
        let fileName = "\(id.uuidString).mid"
        let url = songsDir.appendingPathComponent(fileName)
        do { try MidiWriter.data(notes: notes, bpm: bpm).write(to: url) } catch { return nil }
        let diff = (try? MidiSong.load(url: url))?.difficulty
        let e = SongEntry(id: id, title: title, fileName: fileName, added: Date(), bestAccuracy: nil,
                          plays: 0, practiceSeconds: 0, lastPlayed: nil, favorite: false, difficulty: diff)
        songs.append(e)
        save()
        return e
    }

    func markCatalog(_ entry: SongEntry, source: String, license: String, composer: String) {
        guard let i = songs.firstIndex(where: { $0.id == entry.id }) else { return }
        songs[i].sourceURL = source
        songs[i].license = license
        songs[i].composer = composer
        save()
    }

    func delete(_ entry: SongEntry) {
        try? FileManager.default.removeItem(at: url(for: entry))
        songs.removeAll { $0.id == entry.id }
        save()
    }

    func rename(_ entry: SongEntry, to title: String) {
        guard let i = songs.firstIndex(where: { $0.id == entry.id }), !title.isEmpty else { return }
        songs[i].title = title
        save()
    }

    func toggleFavorite(_ entry: SongEntry) {
        guard let i = songs.firstIndex(where: { $0.id == entry.id }) else { return }
        songs[i].favorite = !(songs[i].favorite ?? false)
        save()
    }

    // MARK: Sessions

    func record(songID: UUID?, title: String, result: SessionResult?, seconds: Double, mode: PracticeMode) {
        guard seconds > 1 || result != nil else { return }
        if let id = songID, let i = songs.firstIndex(where: { $0.id == id }) {
            songs[i].practiceSeconds += seconds
            songs[i].lastPlayed = Date()
            if let r = result, let a = r.accuracy {
                songs[i].plays += 1
                if a >= (songs[i].bestAccuracy ?? 0) { songs[i].bestAccuracy = a }
                songs[i].bestScore = max(songs[i].bestScore ?? 0, r.score)
                songs[i].bestStars = max(songs[i].bestStars ?? 0, r.stars)
                if a >= 0.9 { songs[i].bestTempo = max(songs[i].bestTempo ?? 0, r.tempo) }
            }
        }
        if let r = result, let a = r.accuracy, a >= 0.9, r.tempo >= 1.0 {
            Prefs.set("ach_fullTempo", true)
        }
        let s = PracticeSession(id: UUID(), date: Date(), songID: songID, title: title, seconds: seconds,
                                accuracy: result?.accuracy, stars: result?.stars, score: result?.score,
                                mode: mode.rawValue)
        sessions.append(s)
        save()
        if seconds >= 60 || result != nil { appendObsidianLog(s) }
    }

    /// Übungszeit aus Trainern (Notenlesen, Gehör, Freies Spiel)
    func recordTraining(title: String, seconds: Double) {
        guard seconds > 5 else { return }
        let s = PracticeSession(id: UUID(), date: Date(), songID: nil, title: title, seconds: seconds,
                                accuracy: nil, stars: nil, score: nil, mode: "Training")
        sessions.append(s)
        save()
        if seconds >= 60 { appendObsidianLog(s) }
    }

    private func appendObsidianLog(_ s: PracticeSession) {
        guard Prefs.bool("obsidianLog", true) else { return }
        let url = Self.vaultLog
        let dir = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        let footer = "\n---\n\n⬅️ [[Hobbys]]\n"
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? """
        ---
        tags:
          - hobby
          - musik
          - log
        quelle: pianoflow
        ---

        # 🎹 PianoFlow – Übungslog

        Schreibt PianoFlow automatisch: eine Zeile pro Übungseinheit (ab 1 Minute).

        🔗 [[Klavier]] · [[PianoFlow – Klavier-Lern-App]]

        ## Einheiten

        \(footer)
        """
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "dd.MM.yyyy HH:mm"
        var line = "- \(df.string(from: s.date)) · \(s.title) · \(s.mode) · \(max(1, Int((s.seconds / 60).rounded()))) min"
        if let a = s.accuracy { line += " · \(Int(a * 100)) %" }
        if let st = s.stars, st > 0 { line += " · " + String(repeating: "⭐", count: st) }
        if let r = text.range(of: footer, options: .backwards) {
            text.insert(contentsOf: line + "\n", at: r.lowerBound)
        } else {
            text += line + "\n"
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Statistik

    var totalPracticeSeconds: Double { sessions.reduce(0) { $0 + $1.seconds } }

    func minutes(on day: Date) -> Double {
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.seconds } / 60
    }

    var todayMinutes: Double { minutes(on: Date()) }
    var dailyGoal: Int { Prefs.int("dailyGoal", 15) }

    func minutesPerDay(_ n: Int) -> [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).reversed().compactMap { k in
            guard let d = cal.date(byAdding: .day, value: -k, to: today) else { return nil }
            return DayStat(day: d, minutes: minutes(on: d))
        }
    }

    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        var count = 0
        if minutes(on: day) < 1, let prev = cal.date(byAdding: .day, value: -1, to: day) { day = prev }
        while minutes(on: day) >= 1, count < 10_000 {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    var bestStreak: Int {
        let cal = Calendar.current
        let days = Set(sessions.filter { $0.seconds >= 30 }.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, cur = 0
        var prev: Date? = nil
        for d in days {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { cur += 1 } else { cur = 1 }
            best = max(best, cur)
            prev = d
        }
        return best
    }

    var xp: Int {
        let fromTime = Int(totalPracticeSeconds / 60) * 10
        let fromScore = sessions.compactMap(\.score).reduce(0, +) / 100
        let fromStars = sessions.compactMap(\.stars).reduce(0, +) * 50
        return fromTime + fromScore + fromStars
    }

    /// Level n braucht 100·n² XP
    var level: (level: Int, progress: Double, nextXP: Int) {
        let x = Double(xp)
        let lvl = Int((x / 100).squareRoot()) + 1
        let cur = 100 * (lvl - 1) * (lvl - 1)
        let next = 100 * lvl * lvl
        return (lvl, (x - Double(cur)) / Double(max(next - cur, 1)), next)
    }

    /// Songs, die gelernt waren, aber länger nicht gespielt wurden (Vergessenskurve)
    var refreshSuggestions: [SongEntry] {
        let limit = Date().addingTimeInterval(-7 * 86_400)
        return songs.filter { ($0.bestAccuracy ?? 0) >= 0.8 && ($0.lastPlayed ?? .distantPast) < limit }
            .sorted { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
    }

    var continueSuggestion: SongEntry? {
        songs.filter { $0.plays > 0 && $0.mastery.level < 4 }
            .max { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
    }

    var achievements: [Achievement] {
        let total = totalPracticeSeconds / 60
        let anyPlay = songs.contains { $0.plays > 0 }
        let perfect = songs.contains { ($0.bestAccuracy ?? 0) >= 0.99 }
        let threeStars = songs.filter { ($0.bestStars ?? 0) >= 3 }.count
        let readingBest = Prefs.int("readingBest", 0)
        let earBest = Prefs.int("earBest", 0)
        return [
            Achievement(id: "first", icon: "music.note", title: "Erster Song", detail: "Einen Song komplett gespielt", unlocked: anyPlay),
            Achievement(id: "perfect", icon: "sparkles", title: "Perfektionist", detail: "99 % Genauigkeit", unlocked: perfect),
            Achievement(id: "stars", icon: "star.fill", title: "Sternesammler", detail: "5 Songs mit 3 Sternen", unlocked: threeStars >= 5),
            Achievement(id: "tempo", icon: "hare.fill", title: "Originaltempo", detail: "90 %+ bei 100 % Tempo", unlocked: Prefs.bool("ach_fullTempo", false)),
            Achievement(id: "hour", icon: "clock.fill", title: "Erste Stunde", detail: "60 Minuten geübt", unlocked: total >= 60),
            Achievement(id: "marathon", icon: "flame.fill", title: "Marathon", detail: "10 Stunden geübt", unlocked: total >= 600),
            Achievement(id: "week", icon: "calendar", title: "Wochen-Streak", detail: "7 Tage am Stück", unlocked: bestStreak >= 7),
            Achievement(id: "month", icon: "calendar.badge.checkmark", title: "Monats-Streak", detail: "30 Tage am Stück", unlocked: bestStreak >= 30),
            Achievement(id: "collector", icon: "books.vertical.fill", title: "Sammler", detail: "10 Songs in der Bibliothek", unlocked: songs.count >= 10),
            Achievement(id: "reader", icon: "eye.fill", title: "Notenleser", detail: "25er-Serie im Notenlesen", unlocked: readingBest >= 25),
            Achievement(id: "ear", icon: "ear.fill", title: "Goldenes Ohr", detail: "10er-Serie im Gehörtraining", unlocked: earBest >= 10),
            Achievement(id: "level5", icon: "trophy.fill", title: "Level 5", detail: "2.500 XP gesammelt", unlocked: level.level >= 5)
        ]
    }
}
