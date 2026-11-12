import Foundation
import AppKit

// MARK: - Einstellungen

enum Prefs {
    static let d = UserDefaults.standard
    static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    static func double(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
    static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    static func string(_ k: String, _ def: String) -> String { d.string(forKey: k) ?? def }
    static func set(_ k: String, _ v: Any) { d.set(v, forKey: k) }
}

// MARK: - Notennamen

enum LabelMode: String, CaseIterable, Identifiable {
    case none = "Keine Beschriftung"
    case names = "Notennamen"
    case solfege = "Do-Re-Mi"
    case fingers = "Fingersatz"
    case harmony = "Akkordtöne (1-3-5)"
    var id: String { rawValue }
}

enum NoteNames {
    static let names = ["C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"]
    static let solfegeNames = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
    static func pc(_ p: Int) -> Int { ((p % 12) + 12) % 12 }
    static func name(_ p: Int, octave: Bool = true) -> String {
        names[pc(p)] + (octave ? "\(p / 12 - 1)" : "")
    }
    static func solfege(_ p: Int) -> String { solfegeNames[pc(p)] }
    static let intervalNames = ["Prime", "kleine Sekunde", "große Sekunde", "kleine Terz", "große Terz", "Quarte",
                                "Tritonus", "Quinte", "kleine Sexte", "große Sexte", "kleine Septime", "große Septime", "Oktave"]
}

// MARK: - Akkorderkennung

enum ChordNamer {
    static let rootNames = ["C", "Cis", "D", "Es", "E", "F", "Fis", "G", "As", "A", "B", "H"]
    static let templates: [(intervals: Set<Int>, suffix: String)] = [
        ([0, 4, 7], ""), ([0, 3, 7], "m"), ([0, 4, 7, 10], "7"), ([0, 4, 7, 11], "maj7"),
        ([0, 3, 7, 10], "m7"), ([0, 3, 6], "°"), ([0, 4, 8], "+"), ([0, 3, 6, 10], "m7♭5"),
        ([0, 3, 6, 9], "°7"), ([0, 2, 7], "sus2"), ([0, 5, 7], "sus4"), ([0, 4, 7, 9], "6"),
        ([0, 3, 7, 9], "m6"), ([0, 2, 4, 7, 10], "9"), ([0, 2, 4, 7], "add9"), ([0, 7], "5"),
        ([0, 4], " (Terz)"), ([0, 3], "m (Terz)")
    ]

    static func name(for pitches: [Int]) -> String? {
        let pcs = Set(pitches.map(NoteNames.pc))
        guard pcs.count >= 2 else { return nil }
        let bass = pitches.min().map(NoteNames.pc)
        var best: (name: String, prio: Int)? = nil
        for root in pcs.sorted() {
            let rel = Set(pcs.map { ($0 - root + 12) % 12 })
            for (k, t) in templates.enumerated() where t.intervals == rel {
                var n = rootNames[root] + t.suffix
                if let b = bass, b != root { n += "/" + rootNames[b] }
                let prio = (root == bass ? 0 : 100) + k
                if best == nil || prio < best!.prio { best = (n, prio) }
            }
        }
        return best?.name
    }
}

// MARK: - Notensystem

enum Staff {
    static let letterOf = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
    static let sharp = [false, true, false, true, false, false, true, false, true, false, true, false]
    static func diatonic(_ p: Int) -> Int { (p / 12) * 7 + letterOf[NoteNames.pc(p)] }
    static func isSharp(_ p: Int) -> Bool { sharp[NoteNames.pc(p)] }
    static let trebleBottom = diatonic(64)   // E4
    static let bassBottom = diatonic(43)     // G2
}

// MARK: - Fingersatz (Heuristik)

enum Fingering {
    static func pos(_ p: Int) -> Double { Double(Staff.diatonic(p)) + (Staff.isSharp(p) ? 0.5 : 0) }

    /// Finger 1–5, aufsteigend vergeben für aufsteigende Positionen
    private static func assignChord(_ positions: [Double]) -> [Int] {
        let n = positions.count
        guard let lo = positions.first, let hi = positions.last else { return [] }
        let span = max(hi - lo, 1)
        var f: [Int] = []
        for (k, p) in positions.enumerated() {
            var v = n == 1 ? 1 : 1 + Int(((p - lo) / span * 4).rounded())
            if let prev = f.last { v = max(v, prev + 1) }
            v = min(v, 5 - (n - 1 - k))
            f.append(max(1, v))
        }
        return f
    }

    static func compute(_ notes: [NoteEvent]) -> [Int] {
        var fingers = Array(repeating: 0, count: notes.count)
        for hand in [Hand.right, Hand.left] {
            let idx = notes.indices.filter { notes[$0].hand == hand }
            var thumb: Double? = nil
            var i = 0
            while i < idx.count {
                let t0 = notes[idx[i]].start
                var group: [Int] = []
                while i < idx.count, notes[idx[i]].start - t0 < 0.03 {
                    group.append(idx[i])
                    i += 1
                }
                group.sort { notes[$0].pitch < notes[$1].pitch }
                let used = Array(group.prefix(5))
                let positions = used.map { pos(Int(notes[$0].pitch)) }

                if used.count > 1 {
                    if hand == .right {
                        let f = assignChord(positions)
                        for (k, gi) in used.enumerated() { fingers[gi] = f[k] }
                    } else {
                        let f = assignChord(positions.reversed().map { -$0 })
                        let fr = Array(f.reversed())
                        for (k, gi) in used.enumerated() { fingers[gi] = fr[k] }
                    }
                    thumb = nil
                    continue
                }

                // Einzelnoten: Handposition in Halbtönen (Daumen-Anker), Fenster per Vorausschau
                let p = Double(notes[used[0]].pitch)
                func anchorFromHere() -> Double {
                    var lo = p, hi = p
                    var k = i - 1
                    var seen = 0
                    while k < idx.count && seen < 10 {
                        let q = Double(notes[idx[k]].pitch)
                        if max(hi, q) - min(lo, q) > 8 { break }
                        lo = min(lo, q); hi = max(hi, q)
                        k += 1; seen += 1
                    }
                    return hand == .right ? lo : hi
                }
                if thumb == nil { thumb = anchorFromHere() }
                var s = hand == .right ? p - thumb! : thumb! - p
                if s < 0 || s > 8 {
                    thumb = anchorFromHere()
                    s = hand == .right ? p - thumb! : thumb! - p
                }
                let spans: [Double] = [0, 2, 3.5, 5, 7]
                var f = 1
                var bestD = Double.infinity
                for (k, sp) in spans.enumerated() where abs(s - sp) < bestD - 0.001 {
                    bestD = abs(s - sp)
                    f = k + 1
                }
                fingers[used[0]] = f
            }
        }
        return fingers
    }
}

// MARK: - MIDI schreiben

enum MidiWriter {
    static func data(notes: [NoteEvent], bpm: Double = 120) -> Data {
        let tpq = 480.0
        let ticksPerSec = bpm / 60 * tpq
        var events: [(tick: Int, bytes: [UInt8], order: Int)] = []
        for n in notes {
            let ch: UInt8 = n.hand == .right ? 0 : 1
            let on = Int((n.start * ticksPerSec).rounded())
            let off = max(on + 1, Int((n.end * ticksPerSec).rounded()))
            events.append((on, [0x90 | ch, n.pitch, max(1, n.velocity)], 1))
            events.append((off, [0x80 | ch, n.pitch, 0], 0))
        }
        events.sort { ($0.tick, $0.order) < ($1.tick, $1.order) }

        func vlq(_ v: Int) -> [UInt8] {
            var v = v
            var out: [UInt8] = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 { out.insert(UInt8((v & 0x7F) | 0x80), at: 0); v >>= 7 }
            return out
        }

        var track: [UInt8] = []
        let mpq = Int(60_000_000 / bpm)
        track += [0x00, 0xFF, 0x51, 0x03, UInt8((mpq >> 16) & 0xFF), UInt8((mpq >> 8) & 0xFF), UInt8(mpq & 0xFF)]
        track += [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]
        var last = 0
        for e in events {
            track += vlq(e.tick - last) + e.bytes
            last = e.tick
        }
        track += [0x00, 0xFF, 0x2F, 0x00]

        var out: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, UInt8(Int(tpq) >> 8), UInt8(Int(tpq) & 0xFF)]
        let len = track.count
        out += Array("MTrk".utf8) + [UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)]
        out += track
        return Data(out)
    }
}

// MARK: - Übungsgenerator

enum ExerciseKind: String, CaseIterable, Identifiable {
    case majorScale = "Dur-Tonleiter"
    case minorScale = "Moll-Tonleiter (harmonisch)"
    case majorArpeggio = "Arpeggio Dur"
    case minorArpeggio = "Arpeggio Moll"
    case fiveFinger = "Fünffinger-Übung"
    case chromatic = "Chromatische Tonleiter"
    case cadence = "Kadenz I–IV–V–I"
    case pop = "Pop-Akkorde I–V–vi–IV"
    case broken = "Gebrochene Akkorde (Alberti-Bass)"
    case sightReading = "Blattspiel (Zufallsmelodie)"
    case hanon = "Hanon Nr. 1 (Technik)"
    var id: String { rawValue }
}

struct ExerciseConfig: Hashable {
    var kind: ExerciseKind = .majorScale
    var root = 0
    var octaves = 1
    var hands: HandSelection = .right
    var bpm: Double = 80

    var title: String { "\(kind.rawValue) – \(ChordNamer.rootNames[root])" }
}

enum ExerciseFactory {
    static func make(_ c: ExerciseConfig) -> MidiSong {
        let beat = 60.0 / c.bpm
        var notes: [NoteEvent] = []

        func add(_ pitch: Int, at b: Double, len: Double, hand: Hand) {
            guard (21...108).contains(pitch) else { return }
            notes.append(NoteEvent(pitch: UInt8(pitch), velocity: 80,
                                   start: b * beat, end: (b + len * 0.92) * beat, hand: hand))
        }

        func line(_ intervals: [Int], base: Int, hand: Hand, step: Double = 0.5) -> Double {
            var b = 0.0
            for iv in intervals { add(base + iv, at: b, len: step, hand: hand); b += step }
            return b
        }

        let rh = 60 + c.root
        let lh = 48 + c.root
        let useR = c.hands != .left
        let useL = c.hands != .right

        func upDown(_ pattern: [Int]) -> [Int] {
            var up: [Int] = []
            for o in 0..<c.octaves { up += pattern.map { $0 + 12 * o } }
            up.append(12 * c.octaves)
            return up + up.dropLast().reversed()
        }

        switch c.kind {
        case .majorScale, .minorScale, .majorArpeggio, .minorArpeggio, .chromatic:
            let pattern: [Int]
            switch c.kind {
            case .majorScale: pattern = [0, 2, 4, 5, 7, 9, 11]
            case .minorScale: pattern = [0, 2, 3, 5, 7, 8, 11]
            case .majorArpeggio: pattern = [0, 4, 7]
            case .minorArpeggio: pattern = [0, 3, 7]
            default: pattern = Array(0..<12)
            }
            let seq = upDown(pattern)
            if useR { _ = line(seq, base: rh, hand: .right) }
            if useL { _ = line(seq, base: lh, hand: .left) }
        case .fiveFinger:
            let seq = [0, 2, 4, 5, 7, 5, 4, 2, 0, 2, 4, 5, 7, 5, 4, 2, 0]
            if useR { _ = line(seq, base: rh, hand: .right) }
            if useL { _ = line(seq, base: lh, hand: .left) }
        case .cadence, .pop:
            let chords: [(rh: [Int], bass: Int)] = c.kind == .cadence
                ? [([0, 4, 7], 0), ([0, 5, 9], 5), ([-1, 2, 7], -5), ([0, 4, 7], 0)]
                : [([0, 4, 7], 0), ([-1, 2, 7], -5), ([0, 4, 9], -3), ([0, 5, 9], -7)]
            var b = 0.0
            for _ in 0..<2 {
                for ch in chords {
                    if useR { for iv in ch.rh { add(rh + iv, at: b, len: 2, hand: .right) } }
                    if useL { add(lh + ch.bass, at: b, len: 2, hand: .left) }
                    b += 2
                }
            }
            if useR { for iv in [0, 4, 7] { add(rh + iv, at: b, len: 4, hand: .right) } }
            if useL { add(lh, at: b, len: 4, hand: .left) }
        case .sightReading:
            let scale = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
            var gen = SystemRandomNumberGenerator()
            var deg = 2
            var b = 0.0
            let lens: [Double] = [1, 1, 1, 0.5, 0.5, 2]
            for k in 0..<24 {
                let step = [-2, -1, -1, 0, 1, 1, 2, 3, -3].randomElement(using: &gen)!
                deg = min(scale.count - 1, max(0, deg + step))
                let len = k == 23 ? 2 : lens.randomElement(using: &gen)!
                if useR { add(rh + scale[deg], at: b, len: len, hand: .right) }
                if useL && Int(b) % 2 == 0 && b == b.rounded() {
                    add(lh + [0, 7, 5, 7][Int(b / 2) % 4], at: b, len: 2, hand: .left)
                }
                b += len
            }
        case .hanon:
            let cell = [0, 2, 3, 4, 5, 4, 3, 2]                 // Stufen: C E F G A G F E
            let major = [0, 2, 4, 5, 7, 9, 11]
            func deg(_ k: Int) -> Int { major[k % 7] + 12 * (k / 7) }
            var b = 0.0
            for start in 0..<(c.octaves == 1 ? 7 : 14) {
                for s in cell {
                    if useR { add(rh + deg(start + s), at: b, len: 0.5, hand: .right) }
                    if useL { add(lh + deg(start + s), at: b, len: 0.5, hand: .left) }
                    b += 0.5
                }
            }
        case .broken:
            let chords: [[Int]] = [[0, 4, 7], [0, 5, 9], [-1, 2, 7], [0, 4, 7]]
            var b = 0.0
            for _ in 0..<2 {
                for ch in chords {
                    if useL {
                        for iv in [ch[0], ch[2], ch[1], ch[2], ch[0], ch[2], ch[1], ch[2]] {
                            add(lh + iv, at: b, len: 0.5, hand: .left); b += 0.5
                        }
                        b -= 4
                    }
                    if useR {
                        add(rh + 12 + ch[2], at: b, len: 2, hand: .right)
                        add(rh + 12 + ch[1], at: b + 2, len: 2, hand: .right)
                    }
                    b += 4
                }
            }
        }

        notes.sort { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        let total = (notes.map(\.end).max() ?? 0) / beat
        let pulses = stride(from: 0.0, through: total + 1, by: 1.0).map { $0 * beat }
        var song = MidiSong.build(title: c.title, notes: notes, bpm: c.bpm,
                                  pulseTimes: pulses, pulsesPerBar: 4, timeSignature: "4/4")
        // Übungen kennen ihre Tonart: Vorzeichen direkt setzen statt raten
        let minorKind = c.kind == .minorScale || c.kind == .minorArpeggio
        let majorRoot = minorKind ? (c.root + 3) % 12 : c.root
        song.keyFifths = c.kind == .chromatic ? 0 : [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5][((majorRoot % 12) + 12) % 12]
        Self.textbookFingering(&song, kind: c.kind, root: c.root)
        return song
    }

    /// Lehrbuch-Fingersatz für Tonleitern (C-, G-, D-, A-, E-Typ), Arpeggien und Fünffinger-Übung
    static func textbookFingering(_ song: inout MidiSong, kind: ExerciseKind, root: Int) {
        let whiteKeyTonic = [0, 7, 2, 9, 4].contains(((root % 12) + 12) % 12)
        for hand in [Hand.right, .left] {
            let idxs = song.notes.indices.filter { song.notes[$0].hand == hand }
            let uniq = Array(Set(idxs.map { Int(song.notes[$0].pitch) })).sorted()
            guard uniq.count > 1 else { continue }
            let top = uniq.count - 1
            func finger(_ k: Int) -> Int? {
                switch kind {
                case .majorScale, .minorScale:
                    guard whiteKeyTonic else { return nil }
                    if k == top { return hand == .right ? 5 : 1 }
                    return (hand == .right ? [1, 2, 3, 1, 2, 3, 4] : [5, 4, 3, 2, 1, 3, 2])[k % 7]
                case .majorArpeggio, .minorArpeggio:
                    guard whiteKeyTonic else { return nil }
                    if k == top { return hand == .right ? 5 : 1 }
                    if hand == .right { return [1, 2, 3][k % 3] }
                    return k == 0 ? 5 : [4, 2, 1][(k - 1) % 3]
                case .fiveFinger:
                    guard uniq.count <= 5 else { return nil }
                    return hand == .right ? k + 1 : 5 - k
                default: return nil
                }
            }
            for i in idxs {
                if let k = uniq.firstIndex(of: Int(song.notes[i].pitch)), let f = finger(k), i < song.fingers.count {
                    song.fingers[i] = f
                }
            }
        }
    }
}

// MARK: - Mac-Tastatur als Klavier

enum KeyboardPiano {
    static let map: [String: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7,
        "z": 8, "y": 8, "h": 9, "u": 10, "j": 11, "k": 12, "o": 13, "l": 14,
        "p": 15, "ö": 16, ";": 16
    ]
    static func pitch(for ev: NSEvent, octave: Int) -> UInt8? {
        guard !ev.modifierFlags.contains(.command) else { return nil }
        let chars = ev.charactersIgnoringModifiers?.lowercased() ?? ""
        guard let off = map[chars] else { return nil }
        return UInt8(clamping: 12 * (octave + 1) + off)
    }
}
