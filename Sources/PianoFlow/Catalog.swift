import SwiftUI

// MARK: - Kostenloser Song-Katalog (Mutopia Project: gemeinfrei / Creative Commons)

struct CatalogSong: Codable, Hashable {
    let id: Int?
    let title: String
    let composer: String
    let instrument: String
    let date: String
    let style: String
    let license: String
    let midi: String
    let source: String
    let notes: Int
    let seconds: Double
    let timeSignature: String
    let bars: Int
    let difficulty: Int

    /// "J. S. Bach (1685–1750)" -> "J. S. Bach"
    var composerShort: String {
        composer.replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression)
    }
    var licenseShort: String {
        if license.localizedCaseInsensitiveContains("public domain") { return "Gemeinfrei" }
        if license.contains("ShareAlike") { return "CC BY-SA" }
        if license.contains("Attribution") { return "CC BY" }
        return license
    }
    var displayTitle: String { "\(title) – \(composerShort)" }
}

private struct CatalogFile: Codable {
    let generated: String
    let songs: [CatalogSong]
}

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var songs: [CatalogSong] = []
    @Published private(set) var generated = ""
    @Published var downloading: Set<String> = []
    @Published var failed: [String: String] = [:]

    init() { load() }

    static var catalogURL: URL? {
        if let u = Bundle.main.url(forResource: "songs", withExtension: "json") { return u }
        // Entwicklung (swift run): Datei im Projektordner
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("catalog/songs.json")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    private func load() {
        guard let url = Self.catalogURL, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else { return }
        var seen = Set<String>()
        songs = file.songs.filter { seen.insert($0.midi).inserted }
        generated = file.generated
    }

    /// Lädt die MIDI-Datei und legt sie in der Bibliothek ab. Gibt die neue Song-ID zurück.
    func download(_ s: CatalogSong, into library: LibraryStore) async -> UUID? {
        if let existing = library.songs.first(where: { $0.sourceURL == s.midi }) { return existing.id }
        guard let url = URL(string: s.midi), url.scheme == "https",
              url.host?.hasSuffix("mutopiaproject.org") == true else {
            failed[s.midi] = "Ungültige Quelle"
            return nil
        }
        downloading.insert(s.midi)
        defer { downloading.remove(s.midi) }
        do {
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.setValue("PianoFlow/1.0", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 20,
                  data.prefix(4) == Data("MThd".utf8) else {
                failed[s.midi] = "Download fehlgeschlagen"
                return nil
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pf-catalog", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safe = s.displayTitle.replacingOccurrences(of: "/", with: "-")
            let tmp = dir.appendingPathComponent("\(safe).mid")
            try data.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let entry = library.importFiles([tmp]).first else {
                failed[s.midi] = "Datei nicht lesbar"
                return nil
            }
            library.markCatalog(entry, source: s.midi, license: s.license, composer: s.composerShort)
            failed[s.midi] = nil
            return entry.id
        } catch {
            failed[s.midi] = "Keine Verbindung"
            return nil
        }
    }
}

// MARK: - Ansicht "Songs entdecken"

struct CatalogView: View {
    @EnvironmentObject var library: LibraryStore
    @StateObject private var store = CatalogStore()
    var onOpen: (UUID) -> Void
    @State private var search = ""
    @State private var level = 0                // 0 = alle
    @State private var maxMinutes = 0.0         // 0 = egal
    @State private var composer = ""

    private static let levels = [(1, "Einsteiger"), (2, "Leicht"), (3, "Mittel"), (4, "Fortgeschritten"), (5, "Profi")]

    private var composers: [String] {
        let counts = Dictionary(grouping: store.songs, by: \.composerShort).mapValues(\.count)
        return counts.filter { $0.value >= 3 }.keys.sorted()
    }

    private var filtered: [CatalogSong] {
        store.songs.filter { s in
            (level == 0 || s.difficulty == level)
            && (maxMinutes == 0 || s.seconds <= maxMinutes * 60)
            && (composer.isEmpty || s.composerShort == composer)
            && (search.isEmpty || s.title.localizedCaseInsensitiveContains(search)
                || s.composer.localizedCaseInsensitiveContains(search)
                || s.style.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.songs.isEmpty {
                ContentUnavailableView("Kein Katalog gefunden", systemImage: "music.note.list",
                                       description: Text("Die Datei songs.json fehlt im App-Paket."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(filtered, id: \.midi) { s in row(s) }
                    .listStyle(.inset)
            }
        }
        .navigationTitle("Songs entdecken")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Kostenlose Klavierstücke").font(.title2.bold())
                Text("\(store.songs.count) Stücke · gemeinfrei oder Creative Commons · Quelle: Mutopia Project")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Titel, Komponist oder Stil suchen (z. B. Bach, Walzer, Menuett)", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                Picker("Komponist", selection: $composer) {
                    Text("Alle Komponisten").tag("")
                    ForEach(composers, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 230)
                Picker("Länge", selection: $maxMinutes) {
                    Text("Jede Länge").tag(0.0)
                    Text("bis 1 Min.").tag(1.0)
                    Text("bis 2 Min.").tag(2.0)
                    Text("bis 4 Min.").tag(4.0)
                }
                .frame(width: 150)
            }
            HStack(spacing: 6) {
                levelChip(0, "Alle")
                ForEach(Self.levels, id: \.0) { levelChip($0.0, $0.1) }
                Spacer()
                Text("\(filtered.count) Treffer").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func levelChip(_ l: Int, _ title: String) -> some View {
        let sel = level == l
        return Button {
            level = l
        } label: {
            HStack(spacing: 5) {
                if l > 0 { DifficultyDots(level: l) }
                Text(title)
            }
            .font(.callout.weight(sel ? .bold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(sel ? Color.accentColor : Color.white.opacity(0.07)))
            .foregroundStyle(sel ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func row(_ s: CatalogSong) -> some View {
        let have = library.songs.first { $0.sourceURL == s.midi }
        let busy = store.downloading.contains(s.midi)
        return HStack(spacing: 14) {
            DifficultyDots(level: s.difficulty).frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.headline).lineLimit(1)
                Text([s.composerShort, s.style, s.date].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(formatTime(s.seconds)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text(s.timeSignature).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34)
            Text(s.licenseShort)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.18)))
                .help(s.license)
            if let err = store.failed[s.midi] {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Button {
                if let have { onOpen(have.id); return }
                Task { if let id = await store.download(s, into: library) { onOpen(id) } }
            } label: {
                Group {
                    if busy { ProgressView().controlSize(.small) }
                    else if have != nil { Label("Üben", systemImage: "play.fill") }
                    else { Label("Holen & üben", systemImage: "arrow.down.circle.fill") }
                }
                .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(have != nil ? .green : .accentColor)
            .disabled(busy)
        }
        .padding(.vertical, 4)
    }
}

struct DifficultyDots: View {
    let level: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { k in
                Circle().fill(k <= level ? color : Color.white.opacity(0.15)).frame(width: 6, height: 6)
            }
        }
        .help(["", "Einsteiger", "Leicht", "Mittel", "Fortgeschritten", "Profi"][min(5, max(0, level))])
    }
    private var color: Color { level <= 2 ? .green : level == 3 ? .yellow : .orange }
}
