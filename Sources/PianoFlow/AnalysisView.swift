import SwiftUI

struct AnalysisView: View {
    let title: String
    let song: MidiSong
    let analysis: SongAnalysis
    @StateObject private var teacher: TeacherModel

    init(title: String, song: MidiSong, analysis: SongAnalysis) {
        self.title = title
        self.song = song
        self.analysis = analysis
        _teacher = StateObject(wrappedValue: TeacherModel(songID: UUID(uuidString: Self.stableID(title)) ?? UUID()))
    }

    /// Stabile ID aus dem Titel, damit die Werkeinführung gecacht bleibt
    static func stableID(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let hex = String(format: "%016llx%016llx", h, h ^ 0x9E3779B97F4A7C15)
        let c = Array(hex)
        return "\(String(c[0..<8]))-\(String(c[8..<12]))-\(String(c[12..<16]))-\(String(c[16..<20]))-\(String(c[20..<32]))"
    }

    private static let labelColors: [Color] = [.rightHand, .leftHand, .green, .purple, .pink, .teal, .yellow]

    private func color(_ label: String) -> Color {
        let base = label.replacingOccurrences(of: "'", with: "")
        let idx = Int(base.unicodeScalars.first?.value ?? 65) - 65
        return Self.labelColors[max(0, idx) % Self.labelColors.count]
    }

    private func funcColor(_ f: String) -> Color {
        if f.hasPrefix("Tonika") { return .green }
        if f.hasPrefix("Subdominante") { return .blue }
        if f.hasPrefix("Dominante") || f.contains("dominante") { return .orange }
        return .gray
    }

    private var diatonicChords: [(roman: String, chord: String, function: String)] {
        let k = analysis.keyRoot
        let steps: [(Int, String)] = analysis.minor
            ? [(0, "m"), (2, "°"), (3, ""), (5, "m"), (7, ""), (8, ""), (11, "°")]
            : [(0, ""), (2, "m"), (4, "m"), (5, ""), (7, ""), (9, "m"), (11, "°")]
        return steps.map { iv, q in
            let r = SongAnalyzer.roman(root: (k + iv) % 12, q: q, keyRoot: k, minor: analysis.minor)
            return (r.roman, ChordNamer.rootNames[(k + iv) % 12] + q, r.function)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    card("Tonart", analysis.keyName)
                    card("Charakter", analysis.character)
                    card("Form", analysis.formString)
                    card("Linke Hand", analysis.lhPattern)
                    card("Melodie", "\(analysis.chordTonePercent) % Akkordtöne")
                }

                section("Form – so ist das Stück gebaut") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(analysis.phrases) { p in
                                VStack(spacing: 2) {
                                    Text(p.label).font(.headline)
                                    Text("T. \(p.fromBar + 1)–\(p.toBar + 1)").font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(color(p.label).opacity(p.repeatOf != nil ? 0.35 : 0.7)))
                            }
                        }
                        Text("Gleicher Buchstabe = gleiche Musik, ' = Variation. Jede Wiederholung ist geschenkte Übezeit.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                section("Harmonie Phrase für Phrase") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(analysis.phrases) { p in
                            HStack(alignment: .top, spacing: 12) {
                                Text(p.label).font(.headline).frame(width: 30)
                                    .padding(4).background(RoundedRectangle(cornerRadius: 6).fill(color(p.label).opacity(0.5)))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Takt \(p.fromBar + 1)–\(p.toBar + 1)").font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        ForEach(Array(analysis.segments.filter { $0.bar >= p.fromBar && $0.bar <= p.toBar }.enumerated()), id: \.offset) { _, s in
                                            VStack(spacing: 1) {
                                                Text(s.chord).font(.callout.bold())
                                                Text(s.roman).font(.system(.caption, design: .serif).bold())
                                            }
                                            .padding(.horizontal, 7).padding(.vertical, 4)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(funcColor(s.function).opacity(0.3)))
                                            .help(s.function)
                                        }
                                    }
                                    if let c = p.cadence { Text("→ \(c)").font(.caption).foregroundStyle(.yellow) }
                                }
                            }
                        }
                        HStack(spacing: 14) {
                            legend(.green, "Tonika – Ruhe, Zuhause")
                            legend(.blue, "Subdominante – Bewegung weg")
                            legend(.orange, "Dominante – Spannung, will zurück")
                            legend(.gray, "Farbe / leiterfremd")
                        }
                        .font(.caption)
                    }
                }

                section("Die Akkorde von \(analysis.keyName) – dein Werkzeugkasten") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(Array(diatonicChords.enumerated()), id: \.offset) { _, c in
                                VStack(spacing: 2) {
                                    Text(c.roman).font(.system(.title3, design: .serif).bold())
                                    Text(c.chord).font(.callout)
                                    Text(c.function).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(funcColor(c.function).opacity(0.22)))
                                .onTapGesture { playChord(c.chord) }
                            }
                        }
                        Text("Klick auf einen Akkord, um ihn zu hören. Fast jedes Stück in \(analysis.keyName) ist aus diesen sieben Bausteinen gebaut\(analysis.minor ? " (in Moll ist die V meist Dur – wegen des Leittons)" : "").")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                section("Spieltechnik & Gestaltung") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(.init("**Linke Hand – \(analysis.lhPattern):** \(analysis.lhPatternDetail)"))
                        Text(.init("**Umfang:** rechts \(analysis.rhRange), links \(analysis.lhRange). Höhepunkt der Melodie in Takt \(analysis.melodyPeakBar + 1)."))
                        Text(.init("**Dynamik:** \(analysis.dynamicsNote)"))
                        Text(.init("**Pedal:** \(analysis.pedalNote)"))
                    }
                    .font(.callout)
                }

                section("Werk-Einführung vom KI-Lehrer") {
                    VStack(alignment: .leading, spacing: 8) {
                        if teacher.loading.contains("intro") {
                            HStack { ProgressView().controlSize(.small); Text("Chat AI schreibt …").font(.caption) }
                        } else if let a = teacher.cached("intro") {
                            Text(.init(a)).font(.callout).textSelection(.enabled)
                        } else {
                            Button {
                                teacher.ask(key: "intro", prompt: """
                                \(analysis.summary(song: song, title: title))
                                Gib mir eine Einführung in dieses Stück wie zu Beginn einer PianoSecrets-Lektion: \
                                Wer/was ist es (falls bekannt), Charakter und Stimmung, wie es harmonisch gebaut ist, \
                                die 3 größten technischen Herausforderungen und in welcher Reihenfolge ich es lernen sollte.
                                """)
                            } label: { Label("Einführung schreiben lassen", systemImage: "sparkles") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func playChord(_ name: String) {
        // J104: längster passender Grundton, dessen Rest eine bekannte Akkordart ist (Cis/Fis wurden als C/F gespielt, Esus4 als Es)
        let names = ChordNamer.rootNames
        let known = Set(SongAnalyzer.templates.map { $0.q })
        let cands = names.indices.filter { name.hasPrefix(names[$0]) }.sorted { names[$0].count > names[$1].count }
        let fits: (Int) -> Bool = { i in known.contains(String(name.dropFirst(names[i].count).split(separator: "/", omittingEmptySubsequences: false).first ?? "")) }
        guard let root = cands.first(where: fits) ?? cands.first else { return }
        let q = String(name.dropFirst(ChordNamer.rootNames[root].count))
        let iv = SongAnalyzer.templates.first { $0.q == q }?.iv ?? [0, 4, 7]
        for k in iv.prefix(3) { AppServices.shared.audio.preview(UInt8(60 + root + k), duration: 1.2, velocity: 80) }
        AppServices.shared.audio.preview(UInt8(48 + root), duration: 1.2, velocity: 85)
    }

    private func card(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.headline).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t).font(.title3.bold())
            c()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c.opacity(0.5)).frame(width: 12, height: 12)
            Text(t)
        }
    }
}
