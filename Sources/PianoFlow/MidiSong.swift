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

    /// Schwierigkeit 1–5 aus Notendichte, Akkorden und Umfang
    var difficulty: Int {
        guard duration > 0, !notes.isEmpty else { return 1 }
        let nps = Double(notes.count) / duration
        var d: Int
        switch nps {
        case ..<1.5: d = 1
        case ..<2.5: d = 2
        case ..<4: d = 3
        case ..<6: d = 4
        default: d = 5
        }
        let hasBoth = notes.contains { $0.hand == .left } && notes.contains { $0.hand == .right }
        if hasBoth && maxPitch - minPitch > 36 { d += 1 }
        return min(5, max(1, d))
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
                        if m.channel != 9 && m.velocity > 0 {
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

        // Hände zuordnen: genau zwei Stimmen -> höhere = rechts, sonst Split bei C4
        let groups = Dictionary(grouping: raws.indices, by: { raws[$0].group })
        var handOf: [Int: Hand] = [:]
        if groups.count == 2 {
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
        song.detectPickup()
        return song
    }
}
