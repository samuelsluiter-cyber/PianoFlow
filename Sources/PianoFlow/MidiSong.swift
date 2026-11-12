import Foundation
import AudioToolbox

enum Hand: String, Codable {
    case right, left
}

struct NoteEvent {
    let pitch: UInt8
    let velocity: UInt8
    let start: Double   // Sekunden
    let end: Double     // Sekunden
    var hand: Hand
}

struct MidiSong {
    var title: String
    var notes: [NoteEvent]          // sortiert nach Startzeit
    var duration: Double
    var minPitch: Int
    var maxPitch: Int
    var bpm: Double
    var pulseTimes: [Double]        // Zählzeiten in Sekunden
    var pulsesPerBar: Int
    var timeSignature: String
    var barTimes: [Double] = []
    var fingers: [Int] = []
    var autoHands: [Hand] = []
    var pedalSpans: [ClosedRange<Double>] = []
    var pulseOffset = 0             // Auftakt: so viele Zählzeiten vor der ersten Eins
    var keyFifths: Int? = nil       // Tonart laut MIDI-Datei (Vorzeichen: >0 Kreuze, <0 Bs)

    func isBarPulse(_ k: Int) -> Bool { (k - pulseOffset) % max(pulsesPerBar, 1) == 0 && k >= pulseOffset }

    /// Auftakt erkennen: Raster so verschieben, dass Bass-Einsätze und lange Töne auf die Eins fallen
    mutating func detectPickup() {
        let ppb = max(pulsesPerBar, 1)
        guard ppb > 1, pulseTimes.count > ppb * 3 else { return }
        func score(_ off: Int) -> Double {
            var s = 0.0
            var k = off
            while k < pulseTimes.count {
                let t = pulseTimes[k]
                for n in notes where abs(n.start - t) < 0.04 {
                    s += (n.hand == .left ? 1.0 : 0.35) * min(2, 1 + (n.end - n.start))
                }
                k += ppb
            }
            return s
        }
        let base = score(0)
        var best = (off: 0, s: base)
        for off in 1..<ppb {
            let sc = score(off)
            if sc > best.s { best = (off, sc) }
        }
        guard best.off != 0, best.s > base * 1.3 else { return }
        pulseOffset = best.off
        barTimes = stride(from: best.off, to: pulseTimes.count, by: ppb).map { pulseTimes[$0] }
    }

    static func build(title: String, notes: [NoteEvent], bpm: Double, pulseTimes: [Double],
                      pulsesPerBar: Int, timeSignature: String) -> MidiSong {
        let pitches = notes.map { Int($0.pitch) }
        let ppb = max(pulsesPerBar, 1)
        var s = MidiSong(title: title,
                         notes: notes,
                         duration: notes.map(\.end).max() ?? 0,
                         minPitch: pitches.min() ?? 60,
                         maxPitch: pitches.max() ?? 72,
                         bpm: bpm,
                         pulseTimes: pulseTimes,
                         pulsesPerBar: ppb,
                         timeSignature: timeSignature)
        s.barTimes = stride(from: 0, to: pulseTimes.count, by: ppb).map { pulseTimes[$0] }
        s.autoHands = notes.map(\.hand)
        s.fingers = Fingering.compute(notes)
        return s
    }

    /// Takt-Index (0-basiert) für Zeitpunkt t, -1 vor dem ersten Takt
    func barIndex(at t: Double) -> Int {
        guard !barTimes.isEmpty, t >= barTimes[0] else { return -1 }
        return max(0, barTimes.lowerBound(t + 0.0001) - 1)
    }

    func transposed(_ semis: Int) -> MidiSong {
        var s = self
        s.notes = notes.map {
            NoteEvent(pitch: UInt8(clamping: min(108, max(21, Int($0.pitch) + semis))),
                      velocity: $0.velocity, start: $0.start, end: $0.end, hand: $0.hand)
        }
        let pitches = s.notes.map { Int($0.pitch) }
        s.minPitch = pitches.min() ?? 60
        s.maxPitch = pitches.max() ?? 72
        s.fingers = Fingering.compute(s.notes)
        return s
    }

    func reassigned(split: Int?, swap: Bool) -> MidiSong {
        var s = self
        for i in s.notes.indices {
            var h = split.map { Int(s.notes[i].pitch) >= $0 ? Hand.right : Hand.left } ?? autoHands[i]
            if swap { h = h == .right ? .left : .right }
            s.notes[i].hand = h
        }
        s.fingers = Fingering.compute(s.notes)
        return s
    }

    /// Kennzahl für die Schwierigkeit (Anschläge/s je Hand, Akkorde, Sprünge, Beidhändigkeit)
    var difficultyScore: Double {
        guard duration > 0, !notes.isEmpty else { return 0 }
        var onsets: [Hand: Int] = [.left: 0, .right: 0]
        var chordNotes = 0, chords = 0, leaps = 0
        var last: [Hand: (t: Double, p: Int)] = [:]
        for n in notes {
            if let l = last[n.hand], n.start - l.t < 0.035 { chordNotes += 1; continue }
            onsets[n.hand, default: 0] += 1
            chords += 1
            if let l = last[n.hand], abs(Int(n.pitch) - l.p) > 9 { leaps += 1 }
            last[n.hand] = (n.start, Int(n.pitch))
        }
        let active = max(1, duration - (notes.first?.start ?? 0))
        let r = Double(onsets[.right] ?? 0) / active, l = Double(onsets[.left] ?? 0) / active
        let rate = max(r, l) + 0.6 * min(r, l)
        let chordiness = Double(chordNotes) / Double(max(chords, 1))
        let leapRate = Double(leaps) / Double(max(chords, 1))
        let both = min(r, l) > 0.2 ? 0.6 : 0
        return rate * 0.85 + chordiness * 1.2 + leapRate * 3 + both + (maxPitch - minPitch > 40 ? 0.4 : 0)
    }

    /// Schwierigkeit 1–5 (1 = Einsteiger)
    var difficulty: Int {
        let s = difficultyScore
        switch s {
        // kalibriert an 559 Mutopia-Klavierstücken (ca. 8/20/27/23/22 %)
        case ..<3.6: return 1
        case ..<4.6: return 2
        case ..<5.8: return 3
        case ..<7.2: return 4
        default: return 5
        }
    }

    enum LoadError: LocalizedError {
        case cannotOpen(OSStatus)
        case noNotes
        var errorDescription: String? {
            switch self {
            case .cannotOpen(let s): return "MIDI-Datei konnte nicht geöffnet werden (Fehler \(s))."
            case .noNotes: return "Die MIDI-Datei enthält keine spielbaren Noten."
            }
        }
    }

    /// Index der ersten Note mit Start >= t
    func firstNoteIndex(startingAtOrAfter t: Double) -> Int {
        var lo = 0, hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].start < t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    static func load(url: URL) throws -> MidiSong {
        var seqOpt: MusicSequence?
        NewMusicSequence(&seqOpt)
        guard let seq = seqOpt else { throw LoadError.cannotOpen(-1) }
        defer { DisposeMusicSequence(seq) }
        let st = MusicSequenceFileLoad(seq, url as CFURL, .midiType, [])
        guard st == noErr else { throw LoadError.cannotOpen(st) }

        struct Raw {
            var pitch: UInt8
            var vel: UInt8
            var startBeat: Double
            var endBeat: Double
            var group: Int
        }
        var raws: [Raw] = []
        var bpm: Double? = nil
        var tsNum = 4
        var tsDen = 4
        var foundTS = false
        var pedalEvents: [(beat: Double, down: Bool)] = []
        var trackNames: [Int: String] = [:]
        var keyFifths: Int? = nil

        func scan(_ track: MusicTrack, index: Int) {
            var iterOpt: MusicEventIterator?
            NewMusicEventIterator(track, &iterOpt)
            guard let iter = iterOpt else { return }
            defer { DisposeMusicEventIterator(iter) }
            var has: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(iter, &has)
            while has.boolValue {
                var ts: MusicTimeStamp = 0
                var type: MusicEventType = 0
                var dataPtr: UnsafeRawPointer?
                var size: UInt32 = 0
                MusicEventIteratorGetEventInfo(iter, &ts, &type, &dataPtr, &size)
                if let d = dataPtr {
                    if type == kMusicEventType_MIDINoteMessage {
                        let m = d.loadUnaligned(as: MIDINoteMessage.self)
                        if m.channel != 9 && m.velocity > 0 && (21...108).contains(m.note) {
                            raws.append(Raw(pitch: m.note,
                                            vel: m.velocity,
                                            startBeat: ts,
                                            endBeat: ts + Double(max(m.duration, 0.05)),
                                            group: (index + 1) * 16 + Int(m.channel)))
                        }
                    } else if type == kMusicEventType_MIDIChannelMessage {
                        let m = d.loadUnaligned(as: MIDIChannelMessage.self)
                        if (m.status & 0xF0) == 0xB0 && m.data1 == 64 {
                            pedalEvents.append((ts, m.data2 >= 64))
                        }
                    } else if type == kMusicEventType_ExtendedTempo {
                        if bpm == nil {
                            bpm = d.loadUnaligned(as: Float64.self)
                        }
                    } else if type == kMusicEventType_Meta {
                        let metaType = d.load(as: UInt8.self)
                        if metaType == 0x03 || metaType == 0x04, size >= 8 {
                            let len = Int(d.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
                            if len > 0, len < 200, Int(size) >= 8 + len {
                                let bytes = (0..<len).map { d.load(fromByteOffset: 8 + $0, as: UInt8.self) }
                                let name = String(decoding: bytes, as: UTF8.self)
                                trackNames[index] = (trackNames[index].map { $0 + " " } ?? "") + name
                            }
                        }
                        if metaType == 0x59, keyFifths == nil, size >= 10 {
                            let len = d.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
                            if len >= 2 {
                                let sf = Int(Int8(bitPattern: d.load(fromByteOffset: 8, as: UInt8.self)))
                                if (-7...7).contains(sf) { keyFifths = sf }
                            }
                        }
                        if metaType == 0x58 && !foundTS {
                            let len = d.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
                            if len >= 2 {
                                tsNum = max(1, Int(d.load(fromByteOffset: 8, as: UInt8.self)))
                                tsDen = 1 << min(6, Int(d.load(fromByteOffset: 9, as: UInt8.self)))
                                foundTS = true
                            }
                        }
                    }
                }
                MusicEventIteratorNextEvent(iter)
                MusicEventIteratorHasCurrentEvent(iter, &has)
            }
        }

        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(seq, &tempoTrack)
        if let tt = tempoTrack { scan(tt, index: -1) }

        var count: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &count)
        for i in 0..<count {
            var tr: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &tr)
            if let tr { scan(tr, index: Int(i)) }
        }
        guard !raws.isEmpty else { throw LoadError.noNotes }

        func sec(_ beats: Double) -> Double {
            var s: Float64 = 0
            MusicSequenceGetSecondsForBeats(seq, beats, &s)
            return s
        }

        // Hände zuordnen:
        // 1. Spurnamen ("Rechte Hand", "Left", "Bass" …) haben Vorrang
        // 2. genau zwei Stimmen -> höhere = rechts
        // 3. sonst (eine Spur / viele Spuren): Griffweiten-basierte Erkennung (HandSplitter)
        let groups = Dictionary(grouping: raws.indices, by: { raws[$0].group })
        var handOf: [Int: Hand] = [:]
        for g in groups.keys {
            if let name = trackNames[g / 16 - 1], let h = HandSplitter.hand(fromTrackName: name) { handOf[g] = h }
        }
        let named = handOf.count == groups.count && Set(handOf.values).count == 2
        if !named { handOf = [:] }
        if !named && groups.count > 2 {
            // Spuren nach mittlerer Tonhöhe sortieren und an der größten Lücke teilen
            let avgs = groups.mapValues { idxs in idxs.reduce(0.0) { $0 + Double(raws[$1].pitch) } / Double(idxs.count) }
            let sorted = avgs.sorted { $0.value < $1.value }
            var bestGap = (k: 1, g: -1.0)
            for k in 1..<sorted.count where sorted[k].value - sorted[k - 1].value > bestGap.g {
                bestGap = (k, sorted[k].value - sorted[k - 1].value)
            }
            if bestGap.g >= 5 {
                for (k, e) in sorted.enumerated() { handOf[e.key] = k < bestGap.k ? .left : .right }
            }
        }
        if !named && groups.count == 2 {
            let avgs = groups.mapValues { idxs in
                idxs.reduce(0.0) { $0 + Double(raws[$1].pitch) } / Double(idxs.count)
            }
            let sorted = avgs.sorted { $0.value > $1.value }
            handOf[sorted[0].key] = .right
            handOf[sorted[1].key] = .left
        }

        var notes = raws.map { r in
            NoteEvent(pitch: r.pitch,
                      velocity: r.vel,
                      start: sec(r.startBeat),
                      end: sec(r.endBeat),
                      hand: handOf[r.group] ?? (r.pitch >= 60 ? .right : .left))
        }
        notes.sort { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        if !handOf.isEmpty {
            HandSplitter.fixUnplayable(&notes)
        } else {
            let barSec = Double(tsNum) * (4.0 / Double(tsDen)) * 60.0 / max(20, bpm ?? 120)
            HandSplitter.assign(&notes, windowSec: barSec)
        }

        let maxBeat = raws.map(\.endBeat).max() ?? 0
        let pulseQuarter = 4.0 / Double(tsDen)
        var pulses: [Double] = []
        var b = 0.0
        while b <= maxBeat + pulseQuarter && pulses.count < 50_000 {
            pulses.append(sec(b))
            b += pulseQuarter
        }

        var song = MidiSong.build(title: url.deletingPathExtension().lastPathComponent,
                                  notes: notes,
                                  bpm: bpm ?? 120,
                                  pulseTimes: pulses,
                                  pulsesPerBar: tsNum,
                                  timeSignature: "\(tsNum)/\(tsDen)")
        var spans: [ClosedRange<Double>] = []
        var downAt: Double? = nil
        for e in pedalEvents.sorted(by: { $0.beat < $1.beat }) {
            if e.down, downAt == nil { downAt = e.beat }
            if !e.down, let s = downAt {
                let a = sec(s), b = sec(e.beat)
                if b > a { spans.append(a...b) }
                downAt = nil
            }
        }
        song.pedalSpans = spans
        song.keyFifths = keyFifths
        song.detectPickup()
        return song
    }
}


// MARK: - Hand-Erkennung

/// Teilt Noten ohne Spur-Information auf die Hände auf.
/// Pro Anschlag-Gruppe wird die Trennstelle gewählt, die
/// – keiner Hand mehr als ca. eine Oktave Griffweite abverlangt,
/// – jede Hand möglichst nah an ihrer bisherigen Lage lässt,
/// – rechts eher oben und links eher unten hält.
enum HandSplitter {
    static func hand(fromTrackName raw: String) -> Hand? {
        let n = raw.lowercased()
        let right = ["rechte", "rechts", "right", "r.h", "rh", "treble", "melod", "violin", "diskant"]
        let left = ["linke", "links", "left", "l.h", "lh", "bass", "begleit"]
        // Choral-/Stimmnamen (Sopran, Tenor …) und "upper/lower" (oft Stimmen innerhalb eines Systems) sind zweideutig
        if ["sopran", "alto", "alt ", "tenor", "upper", "lower"].contains(where: { raw.lowercased().contains($0) }) { return nil }
        let words = n.split(whereSeparator: { !$0.isLetter && $0 != "." }).map(String.init)
        func hit(_ keys: [String]) -> Bool {
            keys.contains { k in k.count <= 3 ? words.contains(k) : n.contains(k) }
        }
        let r = hit(right), l = hit(left)
        if r && !l { return .right }
        if l && !r { return .left }
        return nil
    }

    static func spanCost(_ ps: ArraySlice<Int>) -> Double {
        guard let lo = ps.first, let hi = ps.last else { return 0 }
        let s = hi - lo
        if s <= 12 { return 0 }
        if s <= 14 { return Double(s - 12) * 6 }
        return 60 + Double(s - 14) * 12
    }

    /// Korrigiert einzelne Anschläge, bei denen eine Hand mehr als ~Dezime greifen müsste
    /// (z. B. Tenor + Bass im Choral): die äußere Note wandert zur anderen Hand.
    static func fixUnplayable(_ notes: inout [NoteEvent]) {
        var i = 0
        while i < notes.count {
            var j = i + 1
            while j < notes.count, notes[j].start - notes[i].start < 0.035 { j += 1 }
            let idx = Array(i..<j).sorted { notes[$0].pitch < notes[$1].pitch }
            let ps = idx.map { Int(notes[$0].pitch) }
            func span(_ h: Hand) -> Int {
                let q = idx.filter { notes[$0].hand == h }.map { Int(notes[$0].pitch) }
                return (q.max() ?? 0) - (q.min() ?? 0)
            }
            if span(.left) > 14 || span(.right) > 14 {
                let current = idx.map { notes[$0].hand }
                var best = (k: 0, c: Double.infinity)
                for k in 0...ps.count {
                    var c = spanCost(ps[0..<k]) + spanCost(ps[k..<ps.count])
                    for (m, h) in current.enumerated() where (m < k ? Hand.left : .right) != h { c += 1 }
                    if c < best.c { best = (k, c) }
                }
                for (m, id) in idx.enumerated() { notes[id].hand = m < best.k ? .left : .right }
            }
            i = j
        }
    }

    /// Trennt per Takt-Fenster mit einer stabilen Grenze; nur bei unspielbaren Griffen wird pro Anschlag nachkorrigiert.
    static func assign(_ notes: inout [NoteEvent], windowSec: Double) {
        guard !notes.isEmpty else { return }
        // Anschlag-Gruppen bilden
        var groups: [[Int]] = []
        var i = 0
        while i < notes.count {
            var j = i + 1
            while j < notes.count, notes[j].start - notes[i].start < 0.035 { j += 1 }
            groups.append(Array(i..<j).sorted { notes[$0].pitch < notes[$1].pitch })
            i = j
        }
        let win = max(0.5, windowSec)
        var byWindow: [Int: [Int]] = [:]   // Fenster -> Gruppen-Indizes
        for (g, idx) in groups.enumerated() {
            byWindow[Int(notes[idx[0]].start / win), default: []].append(g)
        }
        func cost(_ ps: [Int], split: Int) -> Double {
            let k = ps.firstIndex { $0 >= split } ?? ps.count
            return spanCost(ps[0..<k]) + spanCost(ps[k..<ps.count])
        }
        var prevSplit = 60
        for w in byWindow.keys.sorted() {
            let gs = byWindow[w]!
            let pitchSets = gs.map { groups[$0].map { Int(notes[$0].pitch) } }
            var best = (s: prevSplit, c: Double.infinity)
            for split in 36...84 {
                var c = Double(abs(split - 60)) * 0.35 + Double(abs(split - prevSplit)) * 0.25
                for ps in pitchSets { c += cost(ps, split: split) }
                // eine Hand ganz leer zu lassen, während die andere voll ist, ist unwahrscheinlich
                let all = pitchSets.flatMap { $0 }
                let nl = all.filter { $0 < split }.count, nr = all.count - nl
                if all.count >= 6 && (nl == 0 || nr == 0) { c += 4 }
                if c < best.c { best = (split, c) }
            }
            prevSplit = best.s
            for (n, g) in gs.enumerated() {
                let idx = groups[g]
                let ps = pitchSets[n]
                var k = ps.firstIndex { $0 >= best.s } ?? ps.count
                if cost(ps, split: best.s) > 0 {
                    // Einzelner unspielbarer Griff: beste Teilung für diesen Anschlag
                    var bk = (k: k, c: Double.infinity)
                    for kk in 0...ps.count {
                        let c = spanCost(ps[0..<kk]) + spanCost(ps[kk..<ps.count]) + Double(abs(kk - k)) * 0.5
                        if c < bk.c { bk = (kk, c) }
                    }
                    k = bk.k
                }
                for (m, id) in idx.enumerated() { notes[id].hand = m < k ? .left : .right }
            }
        }
    }
}
