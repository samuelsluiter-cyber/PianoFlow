import Foundation
import QuartzCore
import AppKit

enum PracticeMode: String, CaseIterable, Identifiable {
    case listen = "Anhören"
    case wait = "Warte-Modus"
    case play = "Durchspielen"
    case rhythm = "Rhythmus"
    var id: String { rawValue }
    var continuous: Bool { self == .play || self == .rhythm }
}

enum HandSelection: String, CaseIterable, Identifiable {
    case right = "Rechts"
    case left = "Links"
    case both = "Beide"
    var id: String { rawValue }
    var hands: Set<Hand> {
        switch self {
        case .right: return [.right]
        case .left: return [.left]
        case .both: return [.right, .left]
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case waterfall = "Wasserfall"
    case sheet = "Noten"
    case both = "Beides"
    case page = "Ganzes Blatt"
    var id: String { rawValue }
}

enum HandAssign: String, CaseIterable, Identifiable {
    case auto = "Automatisch (Spuren)"
    case split = "Split-Punkt"
    var id: String { rawValue }
}

enum KeyboardSize: String, CaseIterable, Identifiable {
    case auto = "Auto (Song)"
    case k49 = "49 Tasten"
    case k61 = "61 Tasten"
    case k76 = "76 Tasten"
    case k88 = "88 Tasten"
    var id: String { rawValue }
}

enum NoteState { case pending, hit, missed }

enum ParticleKind { case hit, perfect }

struct Particle {
    let pitch: Int
    let born: CFTimeInterval
    let kind: ParticleKind
}

struct SessionResult {
    let accuracy: Double?
    let score: Int
    let stars: Int
    let maxCombo: Int
    let tempo: Double
    let mode: PracticeMode
    let avgOffsetMs: Double?
    let early: Int
    let late: Int
    let rightAcc: Double?
    let leftAcc: Double?
}

extension Array where Element == Double {
    func lowerBound(_ x: Double) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

final class PracticeEngine: ObservableObject {
    let baseSong: MidiSong
    @Published private(set) var song: MidiSong
    private let audio: AudioEngine
    private let midi: MidiInput

    // MARK: Übungseinstellungen
    @Published var mode: PracticeMode = .wait { didSet { rebuildUserNotes(); restart() } }
    @Published var handSelection: HandSelection = .both { didSet { rebuildUserNotes(); restart() } }
    @Published var tempo: Double = 1.0
    @Published var isPlaying = false
    @Published var loopStart: Double? = nil
    @Published var loopEnd: Double? = nil
    @Published var loopBarStart: Int? = nil
    @Published var loopBarEnd: Int? = nil
    @Published var finished = false
    @Published var midiSources: [String] = []
    @Published var keyOctave = 4
    @Published var transpose = 0 { didSet { rebuildSong() } }
    @Published var handAssign: HandAssign = .auto { didSet { rebuildSong() } }
    @Published var splitPitch = 60 { didSet { if handAssign == .split { rebuildSong() } } }
    @Published var swapHands = false { didSet { rebuildSong() } }
    @Published var countdown: Int? = nil
    @Published var isRecording = false
    @Published private(set) var lastResult: SessionResult?
    @Published private(set) var analysis: SongAnalysis

    // MARK: Globale Vorlieben (gespeichert)
    @Published var metronome = Prefs.bool("metronome", false) { didSet { Prefs.set("metronome", metronome) } }
    @Published var playOwnNotes = Prefs.bool("playOwnNotes", true) { didSet { Prefs.set("playOwnNotes", playOwnNotes) } }
    @Published var countIn = Prefs.bool("countIn", true) { didSet { Prefs.set("countIn", countIn) } }
    @Published var autoTempo = Prefs.bool("autoTempo", false) { didSet { Prefs.set("autoTempo", autoTempo) } }
    @Published var hideOtherHand = Prefs.bool("hideOtherHand", false) { didSet { Prefs.set("hideOtherHand", hideOtherHand) } }
    @Published var concertMode = Prefs.bool("concertMode", false) { didSet { Prefs.set("concertMode", concertMode) } }
    @Published var showChords = Prefs.bool("showChords", true) { didSet { Prefs.set("showChords", showChords) } }
    @Published var midiRemote = Prefs.bool("midiRemote", false) { didSet { Prefs.set("midiRemote", midiRemote) } }
    @Published var visibleSeconds = Prefs.double("visibleSeconds", 3.5) { didSet { Prefs.set("visibleSeconds", visibleSeconds) } }
    @Published var viewMode = ViewMode(rawValue: Prefs.string("viewMode", "Wasserfall")) ?? .waterfall {
        didSet {
            Prefs.set("viewMode", viewMode.rawValue)
            if viewMode == .page && oldValue != .page { lastPlayView = oldValue }
        }
    }
    /// Ansicht vor dem Wechsel aufs ganze Notenblatt (für "Zurück")
    var lastPlayView: ViewMode = .both

    // MARK: Notensatz (gecacht)
    private var _score: Score?
    private(set) var scoreVersion = 0
    var notation: Score {
        if let s = _score { return s }
        let s = Score(song: song, analysis: analysis)
        _score = s
        return s
    }
    @Published var labelMode = LabelMode(rawValue: Prefs.string("labelMode", "Notennamen")) ?? .names {
        didSet { Prefs.set("labelMode", labelMode.rawValue) }
    }
    @Published var keyboardSize = KeyboardSize(rawValue: Prefs.string("keyboardSize", "Auto (Song)")) ?? .auto {
        didSet { Prefs.set("keyboardSize", keyboardSize.rawValue) }
    }

    // MARK: Hochfrequenter Zustand (per TimelineView gezeichnet)
    private(set) var currentTime: Double = -2
    private(set) var waiting = false
    private(set) var waitGroup: [Int] = []
    private(set) var noteStates: [NoteState]
    private(set) var isUserNote: [Bool]
    private(set) var pressed: Set<UInt8> = []
    private(set) var pressedCorrect: Set<UInt8> = []
    private(set) var wrongCount = 0
    private(set) var score = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var timingOffsets: [Double] = []
    private(set) var errorsPerBar: [Int] = []
    private(set) var particles: [Particle] = []
    private(set) var judgement: (text: String, pitch: Int, time: CFTimeInterval)?
    private(set) var banner: (text: String, time: CFTimeInterval)?
    private(set) var lastVelocity: UInt8 = 0
    private var practiceSeconds: Double = 0
    var onFinished: ((SessionResult) -> Void)?

    private var userNoteIdx: [Int] = []
    private var nextUser = 0
    private var nextAuto = 0
    private var nextPulse = 0
    private var autoActive: [(pitch: UInt8, end: Double)] = []
    private var timer: Timer?
    private var lastTick: CFTimeInterval = CACurrentMediaTime()
    private var passHits = 0
    private var passErrors = 0
    private var countInLeft = 0
    private var countInNext: CFTimeInterval = 0
    private var countInEnd: CFTimeInterval = 0
    private var countInInterval = 0.5
    private var recEvents: [(t: Double, pitch: UInt8, vel: UInt8, on: Bool)] = []
    private var recClock = 0.0
    static let leadIn = 2.0

    var latencyMs: Double { Prefs.double("latencyMs", 0) }

    private let baseAnalysis: SongAnalysis

    init(song: MidiSong, audio: AudioEngine, midi: MidiInput, analysis given: SongAnalysis? = nil) {
        self.baseSong = song
        self.song = song
        let a = given?.applied(to: song) ?? SongAnalyzer.analyze(song)
        self.baseAnalysis = a
        self.analysis = a
        self.audio = audio
        self.midi = midi
        noteStates = Array(repeating: .pending, count: song.notes.count)
        isUserNote = Array(repeating: false, count: song.notes.count)
        errorsPerBar = Array(repeating: 0, count: max(song.barTimes.count, 1))
        rebuildUserNotes()
        seek(to: -Self.leadIn)
    }

    deinit { timer?.invalidate() }

    // MARK: Lebenszyklus

    func attach() {
        midi.onNoteOn = { [weak self] p, v in self?.userNoteOn(p, velocity: v) }
        midi.onNoteOff = { [weak self] p in self?.userNoteOff(p) }
        midi.onSourcesChanged = { [weak self] names in self?.midiSources = names }
        midiSources = midi.sourceNames
        midi.refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        lastTick = CACurrentMediaTime()
    }

    func detach() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        countdown = nil
        silenceAuto()
        midi.onNoteOn = nil
        midi.onNoteOff = nil
    }

    func takePracticeSeconds() -> Double {
        let s = practiceSeconds
        practiceSeconds = 0
        return s
    }

    // MARK: Abgeleitete Werte

    var keyRange: ClosedRange<Int> {
        switch keyboardSize {
        case .k49: return 36...84
        case .k61: return 36...96
        case .k76: return 28...103
        case .k88: return 21...108
        case .auto:
            var lo = min(song.minPitch, 60) - 2
            var hi = max(song.maxPitch, 72) + 2
            while hi - lo < 36 { lo -= 1; hi += 1 }
            lo -= ((lo % 12) + 12) % 12
            hi += 11 - ((hi % 12) + 12) % 12
            return max(lo, 21)...min(hi, 108)
        }
    }

    var hits: Int { userNoteIdx.reduce(0) { $0 + (noteStates[$1] == .hit ? 1 : 0) } }
    var misses: Int { userNoteIdx.reduce(0) { $0 + (noteStates[$1] == .missed ? 1 : 0) } }
    var accuracy: Double? {
        let total = hits + misses + wrongCount
        return total == 0 ? nil : Double(hits) / Double(total)
    }
    var userNoteCount: Int { userNoteIdx.count }
    var progress: Double {
        guard !userNoteIdx.isEmpty else { return max(0, min(1, currentTime / max(song.duration, 0.1))) }
        return Double(hits + misses) / Double(userNoteIdx.count)
    }
    var hasRecording: Bool { !recEvents.isEmpty }
    var currentBar: Int { song.barIndex(at: currentTime) + 1 }

    func handAccuracy(_ hand: Hand) -> Double? {
        let idx = userNoteIdx.filter { song.notes[$0].hand == hand }
        let done = idx.filter { noteStates[$0] != .pending }
        guard !done.isEmpty else { return nil }
        return Double(done.filter { noteStates[$0] == .hit }.count) / Double(done.count)
    }

    static func stars(for acc: Double?) -> Int {
        guard let a = acc else { return 0 }
        switch a {
        case 0.95...: return 3
        case 0.8..<0.95: return 2
        case 0.6..<0.8: return 1
        default: return 0
        }
    }

    /// Gerade klingende Song-Noten (für Hervorhebung und Akkordnamen)
    func activeSongNotes() -> [Int] {
        let t = currentTime
        var res: [Int] = []
        var i = max(0, nextAuto - 400)
        while i < song.notes.count {
            let n = song.notes[i]
            if n.start > t + 0.0005 { break }
            if n.end > t { res.append(i) }
            i += 1
        }
        return res
    }

    var currentHarmony: HarmonySegment? { analysis.segment(at: max(0, currentTime)) }

    func apply(_ p: PracticePreset) {
        mode = p.mode
        handSelection = p.hands
        tempo = p.tempo
        if let v = p.viewMode { viewMode = v }
        if let l = p.labelMode { labelMode = l }
        if let a = p.autoTempo { autoTempo = a }
        if let m = p.metronome { metronome = m }
        if let r = p.loop { loopBars(r.lowerBound, r.upperBound) } else { clearLoop(); restart() }
    }

    var currentChordName: String? {
        ChordNamer.name(for: activeSongNotes().map { Int(song.notes[$0].pitch) })
    }
    var playedChordName: String? { ChordNamer.name(for: pressed.map(Int.init)) }

    var waitingNames: [String] {
        waitGroup.filter { noteStates[$0] == .pending }
            .map { NoteNames.name(Int(song.notes[$0].pitch)) }
    }

    var dynamicsLabel: String? {
        guard lastVelocity > 0 else { return nil }
        switch lastVelocity {
        case ..<32: return "pp"
        case ..<48: return "p"
        case ..<64: return "mp"
        case ..<80: return "mf"
        case ..<100: return "f"
        default: return "ff"
        }
    }

    // MARK: Steuerung

    func togglePlay() {
        if finished { restart() }
        if isPlaying {
            isPlaying = false
            countdown = nil
            countInLeft = 0
            countInEnd = 0
            silenceAuto()
            return
        }
        isPlaying = true
        lastTick = CACurrentMediaTime()
        if countIn && mode != .listen {
            let pulseLen = song.pulseTimes.count > 1 ? song.pulseTimes[1] - song.pulseTimes[0] : 0.5
            countInInterval = max(0.18, pulseLen / max(tempo, 0.1))
            countInLeft = min(max(song.pulsesPerBar, 2), 6)
            countInNext = lastTick
            countInEnd = 0
        }
    }

    func restart() {
        wrongCount = 0
        score = 0
        combo = 0
        maxCombo = 0
        timingOffsets = []
        passHits = 0
        passErrors = 0
        for i in noteStates.indices { noteStates[i] = .pending }
        seek(to: (loopStart ?? 0) - Self.leadIn)
    }

    func seek(to t: Double) {
        silenceAuto()
        currentTime = t
        waiting = false
        waitGroup = []
        finished = false
        for i in song.notes.indices where song.notes[i].start >= t - 0.0001 {
            noteStates[i] = .pending
        }
        nextAuto = song.firstNoteIndex(startingAtOrAfter: t)
        let from = max(t, loopStart ?? t)
        nextUser = userNoteIdx.firstIndex { song.notes[$0].start >= from - 0.0001 } ?? userNoteIdx.count
        nextPulse = song.pulseTimes.lowerBound(t)
    }

    func setLoopA() {
        let a = max(0, currentTime)
        loopStart = a
        if let e = loopEnd, e <= a + 0.2 { loopEnd = nil }
    }

    func setLoopB() {
        let s = loopStart ?? 0
        guard currentTime > s + 0.2 else { return }
        loopEnd = currentTime
        if loopStart == nil { loopStart = 0 }
        seek(to: s - 1.0)
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
        loopBarStart = nil
        loopBarEnd = nil
    }

    /// Takte a…b (0-basiert, inklusive) loopen
    func loopBars(_ a: Int, _ b: Int) {
        let bars = song.barTimes
        guard !bars.isEmpty else { return }
        let lo = max(0, min(a, bars.count - 1))
        let hi = max(lo, min(b, bars.count - 1))
        loopBarStart = lo
        loopBarEnd = hi
        loopStart = bars[lo]
        loopEnd = hi + 1 < bars.count ? bars[hi + 1] : song.duration + 0.3
        passHits = 0
        passErrors = 0
        seek(to: bars[lo] - 1.0)
    }

    var hardestBar: Int? {
        guard let m = errorsPerBar.max(), m > 0 else { return nil }
        return errorsPerBar.firstIndex(of: m)
    }

    func loopHardestSection() {
        guard let b = hardestBar else { return }
        loopBars(b - 1, b + 1)
        showBanner("Problemstelle: Takt \(max(1, b)) – \(min(max(song.barTimes.count, 1), b + 2))")
    }

    func setSound(_ s: PianoSound) {
        audio.setSound(s)
        objectWillChange.send()
    }
    var sound: PianoSound { audio.sound }
    var accompVolume: Double {
        get { Double(audio.accompVolume) }
        set { audio.accompVolume = Float(newValue); objectWillChange.send() }
    }
    var ownVolume: Double {
        get { Double(audio.ownVolume) }
        set { audio.ownVolume = Float(newValue); objectWillChange.send() }
    }
    var clickVolume: Double {
        get { Double(audio.clickVolume) }
        set { audio.clickVolume = Float(newValue); objectWillChange.send() }
    }

    // MARK: Aufnahme

    func toggleRecording() {
        if isRecording {
            isRecording = false
            for p in pressed { recEvents.append((recClock, p, 0, false)) }
            showBanner("Aufnahme gestoppt – \(recordedNotes().count) Noten")
        } else {
            recEvents = []
            recClock = 0
            isRecording = true
            showBanner("● Aufnahme läuft")
        }
    }

    func recordedNotes() -> [NoteEvent] {
        var open: [UInt8: (t: Double, v: UInt8)] = [:]
        var out: [NoteEvent] = []
        let firstT = recEvents.first?.t ?? 0
        for e in recEvents {
            if e.on {
                open[e.pitch] = (e.t, e.vel)
            } else if let o = open.removeValue(forKey: e.pitch) {
                out.append(NoteEvent(pitch: e.pitch, velocity: o.v, start: o.t - firstT,
                                     end: max(e.t, o.t + 0.05) - firstT,
                                     hand: e.pitch >= 60 ? .right : .left))
            }
        }
        for (p, o) in open {
            out.append(NoteEvent(pitch: p, velocity: o.v, start: o.t - firstT, end: recClock - firstT,
                                 hand: p >= 60 ? .right : .left))
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: Eingabe

    func userNoteOn(_ p: UInt8, velocity: UInt8) {
        if midiRemote, handleRemote(p) { return }
        pressed.insert(p)
        lastVelocity = velocity
        if playOwnNotes { audio.ownOn(p, velocity: velocity) }
        if isRecording { recEvents.append((recClock, p, velocity, true)) }
        guard mode != .listen else { return }

        let latency = latencyMs / 1000 * tempo
        let t = currentTime - latency
        let window = (mode == .wait ? 0.4 : (mode == .rhythm ? 0.25 : 0.2)) * tempo
        var best: Int? = nil
        var bestD = Double.infinity
        let lo = max(0, nextUser - 30)
        let hi = min(userNoteIdx.count, nextUser + 60)
        if lo < hi {
            for k in lo..<hi {
                let i = userNoteIdx[k]
                guard noteStates[i] == .pending else { continue }
                guard mode == .rhythm || song.notes[i].pitch == p else { continue }
                let d = abs(song.notes[i].start - t)
                if d <= window && d < bestD { best = i; bestD = d }
            }
        }
        if let b = best {
            registerHit(b, pitch: p, songTime: t)
            checkWaitGroup()
        } else if isPlaying || waiting {
            wrongCount += 1
            registerError(at: currentTime, label: "Falsch", pitch: Int(p))
        }
    }

    func userNoteOff(_ p: UInt8) {
        if !pressed.contains(p) { return }
        pressed.remove(p)
        pressedCorrect.remove(p)
        if playOwnNotes { audio.ownOff(p) }
        if isRecording { recEvents.append((recClock, p, 0, false)) }
    }

    /// Tiefste Tasten als Fernbedienung: A0 = Play/Pause, B0 = Von vorn, C1 = Problemstelle
    private func handleRemote(_ p: UInt8) -> Bool {
        switch p {
        case 21: togglePlay(); return true
        case 23: restart(); return true
        case 24: loopHardestSection(); return true
        default: return false
        }
    }

    private func registerHit(_ i: Int, pitch: UInt8, songTime: Double) {
        noteStates[i] = .hit
        pressedCorrect.insert(pitch)
        combo += 1
        maxCombo = max(maxCombo, combo)
        passHits += 1
        var text = "Richtig"
        var mult = 1.0
        var kind = ParticleKind.hit
        if mode.continuous {
            let offMs = (songTime - song.notes[i].start) / max(tempo, 0.01) * 1000
            timingOffsets.append(offMs)
            let a = abs(offMs)
            if a < 45 {
                text = "Perfekt"; mult = 1.0; kind = .perfect
            } else if a < 110 {
                text = offMs < 0 ? "Gut · früh" : "Gut · spät"; mult = 0.75
            } else {
                text = offMs < 0 ? "Zu früh" : "Zu spät"; mult = 0.5
            }
        }
        let comboMult = 1.0 + min(Double(combo) / 10.0, 3.0)
        score += Int(100 * mult * comboMult)
        judgement = (combo >= 10 ? "\(text) ×\(combo)" : text, Int(pitch), CACurrentMediaTime())
        particles.append(Particle(pitch: Int(pitch), born: CACurrentMediaTime(), kind: kind))
    }

    private func registerError(at t: Double, label: String, pitch: Int) {
        combo = 0
        passErrors += 1
        let b = song.barIndex(at: t)
        if b >= 0 && b < errorsPerBar.count { errorsPerBar[b] += 1 }
        judgement = (label, pitch, CACurrentMediaTime())
    }

    func handleKey(_ ev: NSEvent) -> Bool {
        if ev.modifierFlags.contains(.command) { return false }
        let chars = ev.charactersIgnoringModifiers?.lowercased() ?? ""
        if ev.type == .keyDown {
            switch ev.keyCode {
            case 49: if !ev.isARepeat { togglePlay() }; return true
            case 123: seek(to: max(-Self.leadIn, currentTime - 5)); return true
            case 124: seek(to: min(song.duration, currentTime + 5)); return true
            case 126: tempo = min(1.5, (tempo * 20 + 1).rounded() / 20); return true
            case 125: tempo = max(0.25, (tempo * 20 - 1).rounded() / 20); return true
            default: break
            }
            switch chars {
            case "r": restart(); return true
            case "x": keyOctave = max(1, keyOctave - 1); return true
            case "c": keyOctave = min(7, keyOctave + 1); return true
            case "m": metronome.toggle(); return true
            case "b": loopHardestSection(); return true
            case "n": toggleRecording(); return true
            default: break
            }
        }
        guard let p = KeyboardPiano.pitch(for: ev, octave: keyOctave) else { return false }
        if ev.type == .keyDown {
            if !ev.isARepeat { userNoteOn(p, velocity: 90) }
        } else {
            userNoteOff(p)
        }
        return true
    }

    // MARK: Interna

    private func rebuildSong() {
        var s = baseSong.reassigned(split: handAssign == .split ? splitPitch : nil, swap: swapHands)
        if transpose != 0 { s = s.transposed(transpose) }
        song = s
        analysis = transpose == 0 ? baseAnalysis.applied(to: s) : SongAnalyzer.analyze(s)
        _score = nil
        scoreVersion += 1
        rebuildUserNotes()
        restart()
    }

    private func rebuildUserNotes() {
        let hands: Set<Hand> = mode == .listen ? [] : handSelection.hands
        for i in song.notes.indices { isUserNote[i] = hands.contains(song.notes[i].hand) }
        userNoteIdx = song.notes.indices.filter { isUserNote[$0] }
    }

    private func silenceAuto() {
        for a in autoActive { audio.noteOff(a.pitch) }
        autoActive.removeAll()
    }

    func showBanner(_ s: String) { banner = (s, CACurrentMediaTime()) }

    private func checkWaitGroup() {
        guard waiting else { return }
        if waitGroup.allSatisfy({ noteStates[$0] == .hit }) {
            waiting = false
            waitGroup = []
            while nextUser < userNoteIdx.count, noteStates[userNoteIdx[nextUser]] == .hit { nextUser += 1 }
            lastTick = CACurrentMediaTime()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(0, now - lastTick), 0.1)
        lastTick = now
        particles.removeAll { now - $0.born > 0.8 }
        if isRecording { recClock += dt }
        guard isPlaying else { return }
        practiceSeconds += dt

        // Einzähler
        if countInLeft > 0 || now < countInEnd {
            if countInLeft > 0 && now >= countInNext {
                audio.click(accent: countdown == nil)
                countdown = countInLeft
                countInLeft -= 1
                countInNext += countInInterval
                if countInLeft == 0 { countInEnd = countInNext }
            }
            return
        }
        if countdown != nil { countdown = nil }

        if waiting {
            checkWaitGroup()
            if waiting { return }
        }

        let end = loopEnd ?? (song.duration + 0.8)
        var newTime = currentTime + dt * tempo

        if mode == .wait {
            while nextUser < userNoteIdx.count, noteStates[userNoteIdx[nextUser]] == .hit { nextUser += 1 }
            if nextUser < userNoteIdx.count {
                let gStart = song.notes[userNoteIdx[nextUser]].start
                if newTime >= gStart && gStart < end {
                    newTime = gStart
                    var g: [Int] = []
                    var k = nextUser
                    while k < userNoteIdx.count, song.notes[userNoteIdx[k]].start - gStart < 0.035 {
                        g.append(userNoteIdx[k])
                        k += 1
                    }
                    waitGroup = g
                    waiting = true
                }
            }
        }

        advance(to: min(newTime, end))
        if waiting { checkWaitGroup() }

        if mode.continuous {
            let window = (mode == .rhythm ? 0.25 : 0.2) * tempo + latencyMs / 1000 * tempo
            while nextUser < userNoteIdx.count {
                let i = userNoteIdx[nextUser]
                if noteStates[i] != .pending { nextUser += 1; continue }
                if song.notes[i].start + window < currentTime {
                    noteStates[i] = .missed
                    registerError(at: song.notes[i].start, label: "Verpasst", pitch: Int(song.notes[i].pitch))
                    nextUser += 1
                } else { break }
            }
        }

        if currentTime >= end - 0.0001 && !waiting {
            if loopEnd != nil { loopWrapped() } else { finish() }
        }
    }

    private func loopWrapped() {
        if autoTempo && mode != .listen {
            let total = passHits + passErrors
            if total > 0 {
                let acc = Double(passHits) / Double(total)
                if acc >= 0.9 && tempo < 1.0 {
                    tempo = min(1.0, (tempo * 20 + 1).rounded() / 20)
                    showBanner("Sauber! Tempo ↑ \(Int((tempo * 100).rounded())) %")
                } else if acc < 0.6 && tempo > 0.4 {
                    tempo = max(0.4, (tempo * 20 - 1).rounded() / 20)
                    showBanner("Tempo ↓ \(Int((tempo * 100).rounded())) % – erst sauber, dann schnell")
                } else {
                    showBanner("Durchgang: \(Int(acc * 100)) % – nochmal")
                }
            }
        }
        passHits = 0
        passErrors = 0
        seek(to: (loopStart ?? 0) - 1.0)
    }

    private func advance(to newTime: Double) {
        while nextAuto < song.notes.count, song.notes[nextAuto].start <= newTime {
            let i = nextAuto
            let n = song.notes[i]
            if !isUserNote[i] {
                if let existing = autoActive.firstIndex(where: { $0.pitch == n.pitch }) {
                    audio.noteOff(n.pitch)
                    autoActive.remove(at: existing)
                }
                audio.noteOn(n.pitch, velocity: n.velocity)
                autoActive.append((n.pitch, n.end))
            }
            nextAuto += 1
        }
        autoActive.removeAll { a in
            if a.end <= newTime { audio.noteOff(a.pitch); return true }
            return false
        }
        while nextPulse < song.pulseTimes.count, song.pulseTimes[nextPulse] <= newTime {
            if metronome { audio.click(accent: song.isBarPulse(nextPulse)) }
            nextPulse += 1
        }
        currentTime = newTime
    }

    private func finish() {
        if mode.continuous {
            for k in nextUser..<userNoteIdx.count where noteStates[userNoteIdx[k]] == .pending {
                noteStates[userNoteIdx[k]] = .missed
            }
        }
        isPlaying = false
        silenceAuto()
        let acc = mode == .listen ? nil : accuracy
        let offs = timingOffsets
        let result = SessionResult(
            accuracy: acc,
            score: score,
            stars: Self.stars(for: acc),
            maxCombo: maxCombo,
            tempo: tempo,
            mode: mode,
            avgOffsetMs: offs.isEmpty ? nil : offs.reduce(0, +) / Double(offs.count),
            early: offs.filter { $0 < -45 }.count,
            late: offs.filter { $0 > 45 }.count,
            rightAcc: handAccuracy(.right),
            leftAcc: handAccuracy(.left))
        lastResult = result
        finished = true
        onFinished?(result)
    }
}
