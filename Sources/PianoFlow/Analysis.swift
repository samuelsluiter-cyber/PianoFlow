import Foundation

// MARK: - Ergebnis-Typen

struct HarmonySegment {
    let bar: Int            // 0-basiert
    let start: Double
    let end: Double
    let rootPC: Int?
    let quality: String     // "", "m", "°", "7", "maj7", "m7"
    let chord: String       // z. B. "Am", "E7"
    let roman: String       // z. B. "i", "V7", "V/V"
    let function: String    // Tonika, Subdominante, Dominante …
    let tones: Set<Int>     // Akkordtöne als Tonklassen
}

struct Phrase: Identifiable {
    let id: Int
    let fromBar: Int        // 0-basiert, inklusive
    let toBar: Int
    let label: String       // A, A', B …
    let repeatOf: Int?      // Index der Phrase, die hier wiederkommt
    let cadence: String?
    let progression: String // "Am – E7 – Am – E7"
    let romans: String      // "i – V7 – i – V7"
}

enum Arrangement: String, CaseIterable, Identifiable {
    case original = "Original"
    case melodyBass = "Melodie + Bass"
    case skeleton = "Gerüst (Kerntöne + Akkorde)"
    case chords = "Nur Akkorde"
    var id: String { rawValue }
}

struct SongAnalysis {
    let keyRoot: Int
    let minor: Bool
    let segments: [HarmonySegment]
    let phrases: [Phrase]
    let lhPattern: String
    let lhPatternDetail: String
    let lhPatternPerBar: [String]
    var roles: [String]              // pro Note: "1", "3", "5", "7", "6", "·"

    /// Analyse des Originals auf eine andere Fassung (gleiche Zeitachse) übertragen
    func applied(to song: MidiSong) -> SongAnalysis {
        var a = self
        a.roles = SongAnalyzer.roles(song.notes, segments).roles
        return a
    }
    let chordTonePercent: Int
    let melodyPeakBar: Int
    let dynamicsNote: String
    let pedalNote: String
    let character: String
    let rhRange: String
    let lhRange: String

    var keyName: String {
        let majorNames = ["C", "Des", "D", "Es", "E", "F", "Fis", "G", "As", "A", "B", "H"]
        let minorNames = ["C", "Cis", "D", "Es", "E", "F", "Fis", "G", "Gis", "A", "B", "H"]
        return (minor ? minorNames : majorNames)[keyRoot] + (minor ? "-Moll" : "-Dur")
    }

    func segment(at t: Double) -> HarmonySegment? {
        var lo = 0, hi = segments.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if segments[mid].start <= t { lo = mid + 1 } else { hi = mid }
        }
        let i = lo - 1
        guard i >= 0, t < segments[i].end + 0.001 else { return nil }
        return segments[i]
    }

    var formString: String { phrases.map(\.label).joined(separator: " ") }

    /// Textzusammenfassung für den KI-Lehrer
    func summary(song: MidiSong, title: String) -> String {
        var s = "Stück: \(title)\nTonart: \(keyName), Takt \(song.timeSignature), ca. \(Int(song.bpm)) BPM, \(song.barTimes.count) Takte\n"
        s += "Charakter: \(character)\nForm (Phrasen à \(phrases.first.map { $0.toBar - $0.fromBar + 1 } ?? 4) Takte): \(formString)\n"
        s += "Linke Hand: \(lhPattern) – \(lhPatternDetail)\nMelodie: \(chordTonePercent) % auf Akkordtönen, Höhepunkt Takt \(melodyPeakBar + 1)\n"
        s += "Umfang rechts \(rhRange), links \(lhRange)\nDynamik: \(dynamicsNote)\nPedal: \(pedalNote)\nHarmonie je Phrase:\n"
        for p in phrases {
            s += "- Takt \(p.fromBar + 1)–\(p.toBar + 1) [\(p.label)]: \(p.progression)  (\(p.romans))"
            if let c = p.cadence { s += " → \(c)" }
            s += "\n"
        }
        return s
    }
}

// MARK: - Analyse

enum SongAnalyzer {
    static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static let templates: [(iv: [Int], q: String)] = [
        ([0, 4, 7], ""), ([0, 3, 7], "m"), ([0, 4, 7, 10], "7"), ([0, 3, 6], "°"),
        ([0, 3, 7, 10], "m7"), ([0, 4, 7, 11], "maj7"), ([0, 3, 6, 9], "°7"), ([0, 5, 7], "sus4")
    ]

    static func analyze(_ song: MidiSong) -> SongAnalysis {
        let notes = song.notes

        // 1) Tonart (Krumhansl-Schmuckler, gewichtet nach Dauer)
        var hist = Array(repeating: 0.0, count: 12)
        for n in notes { hist[NoteNames.pc(Int(n.pitch))] += max(0.05, n.end - n.start) }
        var bestKey = (root: 0, minor: false, r: -Double.infinity)
        for root in 0..<12 {
            for minor in [false, true] {
                let prof = minor ? minorProfile : majorProfile
                let r = correlation(hist, (0..<12).map { prof[($0 - root + 12) % 12] })
                if r > bestKey.r { bestKey = (root, minor, r) }
            }
        }
        // Tonart aus der MIDI-Datei hat Vorrang; Dur oder paralleles Moll entscheidet das Tonprofil
        if let f = song.keyFifths {
            let major = ((f * 7) % 12 + 12) % 12
            let minorRoot = (major + 9) % 12
            let rMaj = correlation(hist, (0..<12).map { majorProfile[($0 - major + 12) % 12] })
            let rMin = correlation(hist, (0..<12).map { minorProfile[($0 - minorRoot + 12) % 12] })
            bestKey = rMin > rMaj ? (minorRoot, true, rMin) : (major, false, rMaj)
        }
        let keyRoot = bestKey.root
        let minor = bestKey.minor

        // 2) Harmonie pro Takt (bei 4er-Takt optional halbtaktig)
        var bounds: [(bar: Int, start: Double, end: Double)] = []
        let bars = song.barTimes
        for (b, t0) in bars.enumerated() {
            let t1 = b + 1 < bars.count ? bars[b + 1] : max(song.duration, t0 + 0.5)
            if t1 <= t0 { continue }
            if song.pulsesPerBar == 4 {
                let mid = (t0 + t1) / 2
                let a = chordFor(notes, t0, mid, keyRoot: keyRoot, minor: minor)
                let c = chordFor(notes, mid, t1, keyRoot: keyRoot, minor: minor)
                if let a, let c, (a.root != c.root || a.q != c.q), a.strength > 0.55, c.strength > 0.55 {
                    bounds.append((b, t0, mid)); bounds.append((b, mid, t1)); continue
                }
            }
            bounds.append((b, t0, t1))
        }
        if bounds.isEmpty { bounds = [(0, 0, max(song.duration, 0.5))] }

        var segments: [HarmonySegment] = []
        var prev: (root: Int, q: String)? = nil
        for bd in bounds {
            if let c = chordFor(notes, bd.start, bd.end, keyRoot: keyRoot, minor: minor) {
                prev = (c.root, c.q)
            }
            guard let p = prev else {
                segments.append(HarmonySegment(bar: bd.bar, start: bd.start, end: bd.end, rootPC: nil, quality: "",
                                               chord: "–", roman: "–", function: "Pause", tones: []))
                continue
            }
            let tones = Set(templates.first { $0.q == p.q }!.iv.map { ($0 + p.root) % 12 })
            let rn = roman(root: p.root, q: p.q, keyRoot: keyRoot, minor: minor)
            segments.append(HarmonySegment(bar: bd.bar, start: bd.start, end: bd.end, rootPC: p.root, quality: p.q,
                                           chord: ChordNamer.rootNames[p.root] + p.q, roman: rn.roman,
                                           function: rn.function, tones: tones))
        }

        // 3) Rollen der Noten (Akkordton oder Verzierung)
        let (roles, ctPercent) = Self.roles(notes, segments)

        // 4) Phrasen + Wiederholungen + Kadenzen
        let barCount = max(bars.count, 1)
        let plen = barCount >= 8 ? 4 : 2
        var phrases: [Phrase] = []
        var prints: [Set<String>] = []
        var labels: [String] = []
        var nextLetter = 0
        let letters = Array("ABCDEFGHIJKLMNOP").map(String.init)
        var start = 0
        while start < barCount {
            let end = min(start + plen - 1, barCount - 1)
            let t0 = bars.isEmpty ? 0 : bars[start]
            let t1 = end + 1 < bars.count ? bars[end + 1] : song.duration + 0.01
            let fp = Set(notes.filter { $0.hand == .right && $0.start >= t0 - 0.001 && $0.start < t1 - 0.001 }
                            .map { "\(Int(((($0.start - t0) * 20)).rounded()))-\($0.pitch)" })
            var label = ""
            var repeatOf: Int? = nil
            var bestSim = 0.0
            for (k, other) in prints.enumerated() where !fp.isEmpty || !other.isEmpty {
                let inter = Double(fp.intersection(other).count)
                let sim = inter / Double(max(fp.count, other.count, 1))
                if sim > bestSim { bestSim = sim; repeatOf = k }
            }
            if let r = repeatOf, bestSim >= 0.85 {
                label = String(labels[r].prefix(1))
            } else if let r = repeatOf, bestSim >= 0.45 {
                label = String(labels[r].prefix(1)) + "'"
            } else {
                label = letters[min(nextLetter, letters.count - 1)]
                nextLetter += 1
                repeatOf = nil
            }
            prints.append(fp)
            labels.append(label)

            let segs = segments.filter { $0.bar >= start && $0.bar <= end }
            var chordSeq: [HarmonySegment] = []
            for s in segs where chordSeq.last?.chord != s.chord { chordSeq.append(s) }
            let cadence = cadenceName(chordSeq.suffix(2).map(\.roman))
            phrases.append(Phrase(id: phrases.count, fromBar: start, toBar: end, label: label,
                                  repeatOf: bestSim >= 0.85 ? repeatOf : nil,
                                  cadence: cadence,
                                  progression: chordSeq.map(\.chord).joined(separator: " – "),
                                  romans: chordSeq.map(\.roman).joined(separator: " – ")))
            start = end + 1
        }

        // 5) Begleitmuster der linken Hand
        var perBar: [String] = []
        for (b, t0) in bars.enumerated() {
            let t1 = b + 1 < bars.count ? bars[b + 1] : song.duration + 0.01
            perBar.append(lhPattern(notes.filter { $0.hand == .left && $0.start >= t0 - 0.001 && $0.start < t1 - 0.001 }))
        }
        let counts = Dictionary(grouping: perBar.filter { $0 != "Pause" }, by: { $0 }).mapValues(\.count)
        let main = counts.max { $0.value < $1.value }?.key ?? "Keine linke Hand"
        let detail = patternExplanation(main, timeSig: song.timeSignature)

        // 6) Melodie-Höhepunkt, Dynamik, Pedal, Charakter
        let rh = notes.filter { $0.hand == .right }
        let lh = notes.filter { $0.hand == .left }
        let peak = rh.max { $0.pitch < $1.pitch }
        let peakBar = peak.map { max(0, song.barIndex(at: $0.start)) } ?? 0
        let vels = Set(notes.map(\.velocity))
        let dyn: String
        if vels.count <= 2 {
            dyn = "Die MIDI-Datei hat keine Dynamik. Gestalte selbst: zum Höhepunkt in Takt \(peakBar + 1) lauter werden, an Phrasenenden zurücknehmen."
        } else {
            let avg = Double(notes.reduce(0) { $0 + Int($1.velocity) }) / Double(max(notes.count, 1))
            let loud = phrases.max { a, b in avgVel(notes, song, a) < avgVel(notes, song, b) }
            dyn = "Dynamik vorhanden (Ø Anschlag \(Int(avg))). Lauteste Stelle: Takt \(loud.map { $0.fromBar + 1 } ?? 1)–\(loud.map { $0.toBar + 1 } ?? 1)."
        }
        let pedal = song.pedalSpans.isEmpty
            ? "Kein Pedal in der Datei. Faustregel: Pedal bei jedem Akkordwechsel neu treten (nach dem Anschlag wechseln = „Synkopenpedal“)."
            : "\(song.pedalSpans.count) Pedalwechsel im Original – meist genau beim Akkordwechsel. Spur links im Wasserfall."
        var character = "\(song.timeSignature)-Takt, \(Int(song.bpm)) BPM"
        if song.timeSignature.hasPrefix("3/") && main.contains("Walzer") { character = "Walzer (\(song.timeSignature)) – Schwerpunkt auf der 1" }
        else if song.bpm < 72 { character += " – ruhig, gesanglich" }
        else if song.bpm > 130 { character += " – lebhaft, virtuos" }

        func range(_ ns: [NoteEvent]) -> String {
            guard let lo = ns.min(by: { $0.pitch < $1.pitch }), let hi = ns.max(by: { $0.pitch < $1.pitch }) else { return "–" }
            return "\(NoteNames.name(Int(lo.pitch)))–\(NoteNames.name(Int(hi.pitch)))"
        }

        return SongAnalysis(keyRoot: keyRoot, minor: minor, segments: segments, phrases: phrases,
                            lhPattern: main, lhPatternDetail: detail, lhPatternPerBar: perBar, roles: roles,
                            chordTonePercent: ctPercent,
                            melodyPeakBar: peakBar, dynamicsNote: dyn, pedalNote: pedal, character: character,
                            rhRange: range(rh), lhRange: range(lh))
    }

    static func roles(_ notes: [NoteEvent], _ segments: [HarmonySegment]) -> (roles: [String], percent: Int) {
        var roles = Array(repeating: "·", count: notes.count)
        var ctCount = 0, rhCount = 0
        var segIdx = 0
        guard !segments.isEmpty else { return (roles, 0) }
        for (i, n) in notes.enumerated() {
            while segIdx + 1 < segments.count && segments[segIdx + 1].start <= n.start + 0.001 { segIdx += 1 }
            let seg = segments[segIdx]
            guard let r = seg.rootPC else { continue }
            let pc = NoteNames.pc(Int(n.pitch))
            let rel = (pc - r + 12) % 12
            let isTone = seg.tones.contains(pc)
            switch rel {
            case 0: roles[i] = "1"
            case 3, 4: roles[i] = isTone ? "3" : "·"
            case 5: roles[i] = isTone ? "4" : "·"  // J104: Quarte im sus4-Akkord ist Akkordton
            case 6, 7, 8: roles[i] = isTone ? "5" : "·"
            case 9: roles[i] = isTone ? "6" : "·"
            case 10, 11: roles[i] = isTone ? "7" : "·"
            default: roles[i] = "·"
            }
            if n.hand == .right {
                rhCount += 1
                if isTone { ctCount += 1 }
            }
        }
        return (roles, rhCount == 0 ? 0 : ctCount * 100 / rhCount)
    }

    private static func avgVel(_ notes: [NoteEvent], _ song: MidiSong, _ p: Phrase) -> Double {
        let bars = song.barTimes
        guard p.fromBar < bars.count else { return 0 }
        let t0 = bars[p.fromBar]
        let t1 = p.toBar + 1 < bars.count ? bars[p.toBar + 1] : song.duration
        let ns = notes.filter { $0.start >= t0 && $0.start < t1 }
        return ns.isEmpty ? 0 : Double(ns.reduce(0) { $0 + Int($1.velocity) }) / Double(ns.count)
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<12 {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        return da == 0 || db == 0 ? 0 : num / (da.squareRoot() * db.squareRoot())
    }

    private static func diatonic(_ keyRoot: Int, _ minor: Bool) -> Set<Int> {
        let scale = minor ? [0, 2, 3, 5, 7, 8, 10, 11] : [0, 2, 4, 5, 7, 9, 11]
        return Set(scale.map { ($0 + keyRoot) % 12 })
    }

    private static func chordFor(_ notes: [NoteEvent], _ t0: Double, _ t1: Double,
                                 keyRoot: Int, minor: Bool) -> (root: Int, q: String, strength: Double)? {
        var w = Array(repeating: 0.0, count: 12)
        var bassPitch = Int.max
        for n in notes where n.end > t0 + 0.01 && n.start < t1 - 0.01 {
            let ov = min(n.end, t1) - max(n.start, t0)
            guard ov > 0 else { continue }
            var weight = ov
            if abs(n.start - t0) < 0.04 { weight *= 1.4 }
            w[NoteNames.pc(Int(n.pitch))] += weight
            if (n.hand == .left || n.pitch < 55) && Int(n.pitch) < bassPitch { bassPitch = Int(n.pitch) }
        }
        let total = w.reduce(0, +)
        guard total > 0.001 else { return nil }
        let bassPC = bassPitch == Int.max ? -1 : NoteNames.pc(bassPitch)
        let dia = diatonic(keyRoot, minor)
        var best: (root: Int, q: String, score: Double) = (0, "", -Double.infinity)
        for root in 0..<12 {
            for t in templates {
                let pcs = Set(t.iv.map { ($0 + root) % 12 })
                if t.iv.count == 4 {
                    let seventh = (t.iv[3] + root) % 12
                    if w[seventh] < 0.2 * total { continue }
                    if t.q == "maj7" && !pcs.isSubset(of: dia) { continue }   // leiterfremde maj7 = meist Leitton-Verzierung
                }
                if t.q == "sus4" && (w[(root + 5) % 12] < 0.2 * total || w[(root + 3) % 12] + w[(root + 4) % 12] > 0.05 * total) { continue }
                var s = 0.0
                for pc in 0..<12 { s += pcs.contains(pc) ? w[pc] : -0.7 * w[pc] }
                if root == bassPC { s += 0.25 * total }
                s += 0.15 * w[root]                                   // Gleichstand: präsenterer Grundton gewinnt
                if minor && t.q == "" && root == (keyRoot + 7) % 12 && w[(keyRoot + 11) % 12] > 0 { s += 0.08 * total } // Leitton → Dominante
                if pcs.isSubset(of: dia) { s += 0.12 * total }
                if w[root] < 0.05 * total { s -= 0.3 * total }
                if t.q == "°7" || t.q == "sus4" { s -= 0.05 * total }
                if s > best.score { best = (root, t.q, s) }
            }
        }
        return (best.root, best.q, best.score / total)
    }

    static func roman(root: Int, q: String, keyRoot: Int, minor: Bool) -> (roman: String, function: String) {
        let iv = (root - keyRoot + 12) % 12
        let base = minor
            ? ["I", "♭II", "II", "III", "♯III", "IV", "♯IV", "V", "VI", "♯VI", "VII", "♯VII"][iv]
            : ["I", "♭II", "II", "♭III", "III", "IV", "♯IV", "V", "♭VI", "VI", "♭VII", "VII"][iv]
        let isMinorQ = q.hasPrefix("m") && !q.hasPrefix("maj")
        let isDim = q.hasPrefix("°") || q.contains("♭5")
        var numeral = (isMinorQ || isDim) ? base.lowercased() : base
        if isDim { numeral += "°" }
        if q == "7" || q == "m7" || q == "maj7" || q == "°7" { numeral += q == "maj7" ? "maj7" : "7" }

        let dia = diatonic(keyRoot, minor)
        let tones = Set(templates.first { $0.q == q }!.iv.prefix(3).map { ($0 + root) % 12 })
        let isDiatonic = tones.isSubset(of: dia)

        // Zwischendominante: Dur/Dom7-Akkord, der eine Quinte über einer leitereigenen Stufe liegt
        if !isDiatonic && (q == "" || q == "7") {
            let target = (iv + 5) % 12
            let targets: [Int: String] = minor
                ? [0: "i", 3: "III", 5: "iv", 7: "V", 8: "VI", 10: "VII"]
                : [0: "I", 2: "ii", 4: "iii", 5: "IV", 7: "V", 9: "vi"]
            if let tName = targets[target], target != 0 {
                return ("V\(q == "7" ? "7" : "")/\(tName)", target == 7 ? "Doppeldominante" : "Zwischendominante")
            }
        }

        let function: String
        switch iv {
        case 0: function = "Tonika"
        case 7, 11: function = "Dominante"
        case 5, 2: function = "Subdominante"
        case 9, 4, 3, 8: function = isDiatonic ? "Tonika-Parallele" : "Farbe (leiterfremd)"
        case 10: function = minor ? "Dominante (natürlich Moll)" : "Farbe (leiterfremd)"
        default: function = "Farbe (leiterfremd)"
        }
        return (numeral, isDiatonic || iv == 0 || iv == 7 ? function : "Farbe (leiterfremd)")
    }

    private static func cadenceName(_ romans: [String]) -> String? {
        guard let last = romans.last else { return nil }
        let l = last.uppercased().replacingOccurrences(of: "°", with: "")
        let p = romans.count == 2 ? romans[0].uppercased() : ""
        if l.hasPrefix("V") && !l.contains("/") && !l.hasPrefix("VI") && !l.hasPrefix("VII") { return "Halbschluss (endet offen auf der Dominante)" }
        if l == "I" || l == "I7" {
            if p.hasPrefix("V") && !p.hasPrefix("VI") { return "Ganzschluss V → I (Ankommen)" }
            if p.hasPrefix("IV") { return "Plagalschluss IV → I („Amen“)" }
            return "Endet auf der Tonika"
        }
        if l.hasPrefix("VI") && p.hasPrefix("V") && !p.hasPrefix("VI") { return "Trugschluss V → vi (überraschend)" }
        return nil
    }

    private static func lhPattern(_ ns: [NoteEvent]) -> String {
        guard !ns.isEmpty else { return "Pause" }
        var groups: [[NoteEvent]] = []
        for n in ns.sorted(by: { $0.start < $1.start }) {
            if let last = groups.last?.first, n.start - last.start < 0.03 { groups[groups.count - 1].append(n) }
            else { groups.append([n]) }
        }
        let sizes = groups.map(\.count)
        if groups.count == 1 { return sizes[0] >= 2 ? "Gehaltener Akkord" : "Gehaltener Basston" }
        if sizes.allSatisfy({ $0 == 2 }) {
            let iv = groups.map { abs(Int($0[0].pitch) - Int($0[1].pitch)) }
            if iv.allSatisfy({ $0 == 12 }) { return "Oktaven" }
        }
        if sizes.allSatisfy({ $0 >= 2 }) { return "Repetierte Akkorde" }
        if sizes.count >= 3 && sizes[0] == 1 && sizes.dropFirst().allSatisfy({ $0 >= 2 }) { return "Walzer-Begleitung (Bass + Akkord)" }  // J104: [1,2] ist kein Um-pa-pa
        if sizes.allSatisfy({ $0 == 1 }) {
            let p = groups.map { Int($0[0].pitch) }
            if p.count >= 4 && p[0] < p[2] && p[2] < p[1] && p[1] == p[3] { return "Alberti-Bass" }
            let span = (p.max() ?? 0) - (p.min() ?? 0)
            let ups = zip(p, p.dropFirst()).filter { $0 < $1 }.count
            if span >= 7 && (ups == p.count - 1 || ups == 0 || (p.count >= 4 && ups >= p.count / 2)) { return "Gebrochener Akkord (Arpeggio)" }
            return "Basslinie (Einzeltöne)"
        }
        return "Gemischte Begleitung"
    }

    private static func patternExplanation(_ p: String, timeSig: String) -> String {
        switch p {
        case "Walzer-Begleitung (Bass + Akkord)":
            return "Auf Zählzeit 1 der Basston (Grundton des Akkords, meist mit dem 5. Finger), auf 2 und 3 der Akkord darüber – leiser und kürzer als der Bass. Das ist das „Um-pa-pa“."
        case "Alberti-Bass":
            return "Der Akkord wird gebrochen: tief – hoch – Mitte – hoch. Die Hand bleibt in einer Position, nur die Finger wechseln (z. B. 5-1-3-1). Gleichmäßig und leise, die Melodie singt darüber."
        case "Gebrochener Akkord (Arpeggio)":
            return "Die Akkordtöne werden nacheinander gespielt – erst blockweise greifen lernen, dann auflösen. Handgelenk führt die Bewegung, Pedal verbindet."
        case "Repetierte Akkorde":
            return "Der Akkord wird rhythmisch wiederholt. Erst die Griffe als Block sicher wechseln, dann den Rhythmus dazunehmen. Locker aus dem Handgelenk."
        case "Oktaven":
            return "Bass in Oktaven (Daumen + 5. Finger). Hand als Rahmen fest, Bewegung aus dem Arm."
        case "Gehaltener Akkord", "Gehaltener Basston":
            return "Die linke Hand legt nur das harmonische Fundament – lange liegen lassen und hören, wie die Melodie darüber wandert."
        case "Basslinie (Einzeltöne)":
            return "Eine eigenständige Basslinie. Sing sie mit – sie ist die zweite Melodie des Stücks."
        default:
            return "Die Begleitung wechselt das Muster. Takt für Takt ansehen, welches Akkordgerüst darunter liegt."
        }
    }

    // MARK: - Vereinfachte Fassungen

    static func arrangement(_ a: Arrangement, song: MidiSong, analysis: SongAnalysis) -> MidiSong {
        guard a != .original else { return song }
        var out: [NoteEvent] = []

        // Melodie = oberste Stimme der rechten Hand
        let rh = song.notes.filter { $0.hand == .right }
        var top: [NoteEvent] = []
        for n in rh {
            if let last = top.last, abs(last.start - n.start) < 0.03 {
                if n.pitch > last.pitch { top[top.count - 1] = n }
            } else { top.append(n) }
        }

        func chordNotes(_ s: HarmonySegment) -> [NoteEvent] {
            guard let r = s.rootPC else { return [] }
            let rootPitch = 48 + r
            let iv = templates.first { $0.q == s.quality }?.iv.prefix(3) ?? [0, 4, 7]
            var ns = iv.map { NoteEvent(pitch: UInt8(rootPitch + $0), velocity: 70, start: s.start,
                                        end: s.end - 0.02, hand: .left) }
            ns.append(NoteEvent(pitch: UInt8(rootPitch - 12), velocity: 80, start: s.start, end: s.end - 0.02, hand: .left))
            return ns
        }

        switch a {
        case .original:
            break
        case .chords:
            for s in analysis.segments { out += chordNotes(s) }
        case .melodyBass:
            out += top
            for s in analysis.segments {
                let bass = song.notes.filter { $0.hand == .left && $0.start >= s.start - 0.01 && $0.start < s.end - 0.01 }
                    .min { $0.pitch < $1.pitch }
                if let b = bass {
                    out.append(NoteEvent(pitch: b.pitch, velocity: b.velocity, start: s.start, end: s.end - 0.02, hand: .left))
                } else if let r = s.rootPC {
                    out.append(NoteEvent(pitch: UInt8(36 + r), velocity: 80, start: s.start, end: s.end - 0.02, hand: .left))
                }
            }
        case .skeleton:
            // Kerntöne: Melodienoten auf Zählzeiten, die Akkordtöne sind
            let pulses = song.pulseTimes
            for (k, t) in pulses.enumerated() {
                guard let seg = analysis.segment(at: t) else { continue }
                let sounding = top.last { $0.start <= t + 0.03 && $0.end > t - 0.01 }
                guard let n = sounding, seg.tones.contains(NoteNames.pc(Int(n.pitch))) || seg.rootPC == nil else { continue }
                let next = k + 1 < pulses.count ? pulses[k + 1] : t + 0.5
                if let last = out.last, last.pitch == n.pitch, abs(last.end - t) < 0.05 {
                    out[out.count - 1] = NoteEvent(pitch: last.pitch, velocity: last.velocity, start: last.start, end: next - 0.02, hand: .right)
                } else {
                    out.append(NoteEvent(pitch: n.pitch, velocity: n.velocity, start: t, end: next - 0.02, hand: .right))
                }
            }
            for s in analysis.segments { out += chordNotes(s) }
        }

        out.sort { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        var s = MidiSong.build(title: song.title + " – " + a.rawValue, notes: out, bpm: song.bpm,
                               pulseTimes: song.pulseTimes, pulsesPerBar: song.pulsesPerBar,
                               timeSignature: song.timeSignature)
        s.pedalSpans = song.pedalSpans
        s.pulseOffset = song.pulseOffset
        s.barTimes = song.barTimes
        return s
    }
}
