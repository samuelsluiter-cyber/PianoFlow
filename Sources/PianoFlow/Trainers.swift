import SwiftUI
import QuartzCore

/// Gemeinsame Eingabe für Trainer: MIDI, Mikrofon (über MIDI-Injektion) und Mac-Tastatur
final class KeyInputMonitor {
    private var monitor: Any?
    var octave = 4
    func install(on: @escaping (UInt8) -> Void, off: @escaping (UInt8) -> Void) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] ev in
            guard let self else { return ev }
            if ev.window?.firstResponder is NSText { return ev }
            let chars = ev.charactersIgnoringModifiers?.lowercased() ?? ""
            if ev.type == .keyDown && chars == "x" { self.octave = max(1, self.octave - 1); return nil }
            if ev.type == .keyDown && chars == "c" { self.octave = min(7, self.octave + 1); return nil }
            guard let p = KeyboardPiano.pitch(for: ev, octave: self.octave) else { return ev }
            if ev.type == .keyDown { if !ev.isARepeat { on(p) } } else { off(p) }
            return nil
        }
    }
    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

// MARK: - Freies Spielen

final class FreePlayModel: ObservableObject {
    private let audio = AppServices.shared.audio
    private let midi = AppServices.shared.midi
    let keys = KeyInputMonitor()
    private(set) var pressed: [UInt8: CFTimeInterval] = [:]
    private(set) var trails: [(pitch: Int, start: CFTimeInterval, end: CFTimeInterval?)] = []
    @Published var chordHistory: [String] = []
    @Published var isRecording = false
    @Published var noteCount = 0
    private var rec: [(t: Double, pitch: UInt8, vel: UInt8, on: Bool)] = []
    private var recStart: CFTimeInterval = 0
    private var sessionStart: CFTimeInterval = 0

    var currentChord: String? { ChordNamer.name(for: pressed.keys.map(Int.init)) }
    var hasRecording: Bool { !rec.isEmpty }

    func attach() {
        sessionStart = CACurrentMediaTime()
        midi.onNoteOn = { [weak self] p, v in self?.on(p, v) }
        midi.onNoteOff = { [weak self] p in self?.off(p) }
        keys.install(on: { [weak self] p in self?.on(p, 90) }, off: { [weak self] p in self?.off(p) })
    }

    func detach() -> Double {
        midi.onNoteOn = nil
        midi.onNoteOff = nil
        keys.remove()
        for p in pressed.keys { audio.ownOff(p) }
        pressed = [:]
        return CACurrentMediaTime() - sessionStart
    }

    private func on(_ p: UInt8, _ v: UInt8) {
        let now = CACurrentMediaTime()
        audio.ownOn(p, velocity: v)
        pressed[p] = now
        trails.append((Int(p), now, nil))
        noteCount += 1
        if isRecording { rec.append((now - recStart, p, v, true)) }
        if pressed.count >= 2, let c = currentChord, chordHistory.last != c {
            chordHistory.append(c)
            if chordHistory.count > 14 { chordHistory.removeFirst() }
        }
    }

    private func off(_ p: UInt8) {
        let now = CACurrentMediaTime()
        audio.ownOff(p)
        pressed[p] = nil
        if let i = trails.lastIndex(where: { $0.pitch == Int(p) && $0.end == nil }) { trails[i].end = now }
        if isRecording { rec.append((now - recStart, p, 0, false)) }
    }

    func cleanup() {
        let now = CACurrentMediaTime()
        trails.removeAll { ($0.end ?? now) < now - 8 }
    }

    func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            rec = []
            recStart = CACurrentMediaTime()
            isRecording = true
        }
    }

    func recordedNotes() -> [NoteEvent] {
        var open: [UInt8: (Double, UInt8)] = [:]
        var out: [NoteEvent] = []
        let end = rec.last?.t ?? 0
        for e in rec {
            if e.on { open[e.pitch] = (e.t, e.vel) }
            else if let o = open.removeValue(forKey: e.pitch) {
                out.append(NoteEvent(pitch: e.pitch, velocity: o.1, start: o.0, end: max(e.t, o.0 + 0.05),
                                     hand: e.pitch >= 60 ? .right : .left))
            }
        }
        for (p, o) in open {
            out.append(NoteEvent(pitch: p, velocity: o.1, start: o.0, end: end + 0.3, hand: p >= 60 ? .right : .left))
        }
        return out.sorted { $0.start < $1.start }
    }
}

struct FreePlayView: View {
    @StateObject private var model = FreePlayModel()
    @EnvironmentObject var library: LibraryStore
    @State private var size: KeyboardSize = .k88
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.toggleRecording(); saved = false } label: {
                    Label(model.isRecording ? "Stopp" : "Aufnehmen",
                          systemImage: model.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .tint(model.isRecording ? .red : nil)
                if !model.isRecording && model.hasRecording {
                    Button(saved ? "Gespeichert ✓" : "Als Song speichern") {
                        let df = DateFormatter()
                        df.dateFormat = "dd.MM. HH:mm"
                        library.addSong(title: "🎙 Freies Spiel – \(df.string(from: Date()))", notes: model.recordedNotes())
                        saved = true
                    }
                    .disabled(saved)
                }
                Picker("Klang", selection: Binding(get: { AppServices.shared.audio.sound },
                                                    set: { AppServices.shared.audio.setSound($0); model.objectWillChange.send() })) {
                    ForEach(PianoSound.allCases) { Text($0.name).tag($0) }
                }
                .frame(width: 220)
                Picker("Klaviatur", selection: $size) {
                    ForEach(KeyboardSize.allCases.filter { $0 != .auto }) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 170)
                Spacer()
                Text("\(model.noteCount) Noten gespielt").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)

            TimelineView(.animation) { tl in
                Canvas { ctx, sz in
                    _ = tl.date
                    draw(ctx, size: sz)
                }
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    TimelineView(.animation(minimumInterval: 0.05)) { _ in
                        Text(model.currentChord ?? " ")
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(radius: 8)
                    }
                    if !model.chordHistory.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(model.chordHistory.enumerated()), id: \.offset) { _, c in
                                Text(c).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
        .background(Color(white: 0.05))
        .navigationTitle("Freies Spielen")
        .navigationSubtitle("Spiel einfach los – Akkorde werden erkannt")
        .onAppear { model.attach() }
        .onDisappear { library.recordTraining(title: "Freies Spielen", seconds: model.detach()) }
    }

    private var range: ClosedRange<Int> {
        switch size {
        case .k49: return 36...84
        case .k61: return 36...96
        case .k76: return 28...103
        default: return 21...108
        }
    }

    private func draw(_ ctx: GraphicsContext, size sz: CGSize) {
        model.cleanup()
        let now = CACurrentMediaTime()
        let kbH = min(170, max(100, sz.height * 0.24))
        let top = sz.height - kbH
        let layout = KeyLayout(range: range, width: sz.width)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: sz.width, height: top)), with: .color(Color(white: 0.06)))
        let speed: CGFloat = 140
        for tr in model.trails {
            guard let f = layout.frame(tr.pitch) else { continue }
            let yBot = top - CGFloat(now - (tr.end ?? now)) * speed
            let yTop = top - CGFloat(now - tr.start) * speed
            guard yBot > 0 else { continue }
            let hue = Double(NoteNames.pc(tr.pitch)) / 12
            let r = CGRect(x: f.x + 1.5, y: max(0, yTop), width: f.w - 3, height: max(4, yBot - max(0, yTop)))
            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Color(hue: hue, saturation: 0.65, brightness: 1).opacity(0.85)))
        }
        KeyboardPainter.draw(ctx, rect: CGRect(x: 0, y: top, width: sz.width, height: kbH), layout: layout, color: { p in
            model.pressed[UInt8(p)] != nil ? Color(hue: Double(NoteNames.pc(p)) / 12, saturation: 0.7, brightness: 1) : nil
        }, label: { p in
            if model.pressed[UInt8(p)] != nil { return NoteNames.name(p, octave: false) }
            return p % 12 == 0 ? NoteNames.name(p) : nil
        })
    }
}

// MARK: - Übungen

struct ExerciseView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var config = ExerciseConfig()
    @State private var song: MidiSong?
    @State private var generation = 0
    @State private var savedTitle: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Übung", selection: $config.kind) {
                    ForEach(ExerciseKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 300)
                Picker("Tonart", selection: $config.root) {
                    ForEach(0..<12, id: \.self) { Text(ChordNamer.rootNames[$0]).tag($0) }
                }
                .frame(width: 120)
                Picker("Hände", selection: $config.hands) {
                    ForEach(HandSelection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                Stepper("Oktaven: \(config.octaves)", value: $config.octaves, in: 1...2).fixedSize()
                Stepper("\(Int(config.bpm)) BPM", value: $config.bpm, in: 40...180, step: 5).fixedSize()
                Button { generate() } label: { Label("Neu erzeugen", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent)
                Button {
                    if let s = song { library.addSong(title: config.title, notes: s.notes, bpm: config.bpm); savedTitle = config.title }
                } label: { Label(savedTitle == config.title ? "Gespeichert" : "In Bibliothek", systemImage: "tray.and.arrow.down") }
                    .disabled(song == nil || savedTitle == config.title)
                Spacer()
            }
            .padding(12)
            Divider()
            if let song {
                PlayerView(title: config.title, song: song, entryID: nil).id(generation)
            }
        }
        .navigationTitle("Übungen & Tonleitern")
        .onAppear { if song == nil { generate() } }
        .onChange(of: config) { _, _ in generate() }
    }

    private func generate() {
        song = ExerciseFactory.make(config)
        generation += 1
    }
}

// MARK: - Notenlesen

enum ClefChoice: String, CaseIterable, Identifiable {
    case treble = "Violinschlüssel"
    case bass = "Bassschlüssel"
    case both = "Beide"
    var id: String { rawValue }
}

final class ReadingModel: ObservableObject {
    private let audio = AppServices.shared.audio
    private let midi = AppServices.shared.midi
    let keys = KeyInputMonitor()
    @Published var clef: ClefChoice = .treble { didSet { next() } }
    @Published var accidentals = false { didSet { next() } }
    @Published var target = 67
    @Published var streak = 0
    @Published var best = Prefs.int("readingBest", 0)
    @Published var correct = 0
    @Published var wrong = 0
    @Published var feedback: (ok: Bool, text: String)?
    @Published var sprintEnd: Date?
    @Published var sprintScore = 0
    @Published var bestSprint = Prefs.int("readingSprintBest", 0)
    @Published var lastPressed: Int?
    private var shownAt = Date()
    private var reactions: [Double] = []
    private var started = CACurrentMediaTime()

    var avgReaction: Double? { reactions.isEmpty ? nil : reactions.suffix(20).reduce(0, +) / Double(min(20, reactions.count)) }

    func attach() {
        started = CACurrentMediaTime()
        midi.onNoteOn = { [weak self] p, _ in self?.answer(pitch: Int(p)) }
        midi.onNoteOff = { _ in }
        keys.install(on: { [weak self] p in self?.answer(pitch: Int(p)) }, off: { _ in })
        next()
    }

    func detach() -> Double {
        midi.onNoteOn = nil
        midi.onNoteOff = nil
        keys.remove()
        return CACurrentMediaTime() - started
    }

    func next() {
        let range: ClosedRange<Int>
        switch clef {
        case .treble: range = 60...81
        case .bass: range = 40...60
        case .both: range = 40...81
        }
        var p = target
        var tries = 0
        repeat {
            p = Int.random(in: range)
            tries += 1
        } while ((!accidentals && Staff.isSharp(p)) || p == target) && tries < 50
        target = p
        shownAt = Date()
    }

    func startSprint() {
        sprintScore = 0
        streak = 0
        sprintEnd = Date().addingTimeInterval(60)
        next()
    }

    func checkSprint() {
        if let e = sprintEnd, Date() >= e {
            sprintEnd = nil
            if sprintScore > bestSprint { bestSprint = sprintScore; Prefs.set("readingSprintBest", sprintScore) }
            feedback = (true, "Sprint vorbei: \(sprintScore) Noten in 60 s")
        }
    }

    func answer(pitch: Int) {
        lastPressed = pitch
        audio.preview(UInt8(pitch), duration: 0.5)
        evaluate(ok: pitch == target, given: NoteNames.name(pitch))
    }

    func answer(pc: Int) {
        evaluate(ok: NoteNames.pc(target) == pc, given: NoteNames.names[pc])
        audio.preview(UInt8(target), duration: 0.5)
    }

    private func evaluate(ok: Bool, given: String) {
        checkSprint()
        if ok {
            correct += 1
            streak += 1
            reactions.append(Date().timeIntervalSince(shownAt))
            if sprintEnd != nil { sprintScore += 1 }
            if streak > best { best = streak; Prefs.set("readingBest", streak) }
            feedback = (true, "Richtig: \(NoteNames.name(target))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.next() }
        } else {
            wrong += 1
            streak = 0
            feedback = (false, "\(given) – gesucht war \(NoteNames.name(target))")
        }
    }
}

struct ReadingTrainerView: View {
    @StateObject private var model = ReadingModel()
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Picker("Schlüssel", selection: $model.clef) {
                    ForEach(ClefChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 340)
                Toggle("Vorzeichen (♯)", isOn: $model.accidentals)
                Spacer()
                Button { model.startSprint() } label: { Label("60-Sekunden-Sprint", systemImage: "stopwatch") }
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 30) {
                big("\(model.streak)", "Serie")
                big("\(model.best)", "Beste Serie")
                big("\(model.correct)/\(model.correct + model.wrong)", "Richtig")
                big(model.avgReaction.map { String(format: "%.1f s", $0) } ?? "–", "Ø Reaktion")
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    if let e = model.sprintEnd {
                        big("\(max(0, Int(e.timeIntervalSinceNow.rounded(.up)))) s · \(model.sprintScore)", "Sprint")
                            .onAppear { model.checkSprint() }
                            .onChange(of: Int(e.timeIntervalSinceNow)) { _, _ in model.checkSprint() }
                    } else {
                        big("\(model.bestSprint)", "Bester Sprint")
                    }
                }
            }

            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 14), with: .color(PianoStage.paper))
                let ink = PianoStage.sheetInk
                let ls = min(22, size.height / 24)
                let g = GrandStaff(ls: ls, trebleTop: (size.height - (8 + GrandStaff.gap) * ls) / 2)
                let painter = NotationPainter(g: g, ink: ink)
                let x0 = size.width / 2 - ls * 16, x1 = size.width / 2 + ls * 16
                painter.staffLines(ctx, from: x0, to: x1)
                painter.systemStart(ctx, x: x0)
                painter.clefsAndSignature(ctx, x: x0, fifths: 0, num: 4, den: 4, showTime: false)
                painter.barline(ctx, x: x1, final: true)
                let col: Color = model.feedback.map { $0.ok ? Color(red: 0.05, green: 0.6, blue: 0.28) : Color(red: 0.85, green: 0.15, blue: 0.15) } ?? ink
                painter.drawLoneNote(ctx, pitch: model.target, x: size.width / 2 + ls * 2, treble: model.target >= 60, color: col)
            }
            .frame(height: 380)

            if let f = model.feedback {
                Text(f.text).font(.title3.bold()).foregroundStyle(f.ok ? Color.hitGreen : Color.missRed)
            } else {
                Text("Spiel die Note auf dem Keyboard – oder klick den Namen").foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(model.accidentals ? Array(0..<12) : [0, 2, 4, 5, 7, 9, 11], id: \.self) { pc in
                    Button { model.answer(pc: pc) } label: {
                        Text(NoteNames.names[pc]).font(.title3.bold()).frame(width: 44, height: 34)
                    }
                }
            }
            Text("Auf dem Keyboard zählt die exakte Oktave, bei den Buttons nur der Name.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Notenlesen-Trainer")
        .onAppear { model.attach() }
        .onDisappear { library.recordTraining(title: "Notenlesen", seconds: model.detach()) }
    }

    private func big(_ v: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.title2, design: .rounded).bold()).monospacedDigit()
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Gehörtraining

enum EarMode: String, CaseIterable, Identifiable {
    case note = "Einzelton"
    case interval = "Intervall (ab C4)"
    case melody = "Mini-Melodie"
    case chord = "Akkord-Qualität"
    var id: String { rawValue }
}

final class EarModel: ObservableObject {
    private let audio = AppServices.shared.audio
    private let midi = AppServices.shared.midi
    let keys = KeyInputMonitor()
    @Published var mode: EarMode = .note { didSet { newRound() } }
    @Published var sequence: [Int] = []
    @Published var progress = 0
    @Published var streak = 0
    @Published var best = Prefs.int("earBest", 0)
    @Published var solved = 0
    @Published var feedback: (ok: Bool, text: String)?
    @Published var revealed = false
    @Published var chordAnswer: String = ""
    private var started = CACurrentMediaTime()
    static let chordTypes: [(name: String, iv: [Int])] = [("Dur", [0, 4, 7]), ("Moll", [0, 3, 7]),
                                                          ("Vermindert", [0, 3, 6]), ("Übermäßig", [0, 4, 8])]

    func attach() {
        started = CACurrentMediaTime()
        midi.onNoteOn = { [weak self] p, v in self?.input(Int(p), v) }
        midi.onNoteOff = { [weak self] p in self?.audio.ownOff(p) }
        keys.install(on: { [weak self] p in self?.input(Int(p), 90) }, off: { [weak self] p in self?.audio.ownOff(p) })
        newRound()
    }

    func detach() -> Double {
        midi.onNoteOn = nil
        midi.onNoteOff = nil
        keys.remove()
        return CACurrentMediaTime() - started
    }

    func newRound() {
        progress = 0
        revealed = false
        feedback = nil
        switch mode {
        case .note: sequence = [Int.random(in: 60...72)]
        case .interval: sequence = [60 + Int.random(in: 1...12)]
        case .melody:
            let scale = [60, 62, 64, 65, 67, 69, 71, 72]
            sequence = (0..<3).map { _ in scale.randomElement()! }
        case .chord:
            let t = Self.chordTypes.randomElement()!
            let root = Int.random(in: 55...65)
            sequence = t.iv.map { root + $0 }
            chordAnswer = t.name
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.play() }
    }

    func play() {
        var delay = 0.0
        if mode == .interval {
            audio.preview(60, duration: 0.7)
            delay = 0.8
        }
        if mode == .chord {
            for p in sequence { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.audio.preview(UInt8(p), duration: 1.2) } }
            return
        }
        for p in sequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.audio.preview(UInt8(p), duration: 0.55) }
            delay += 0.6
        }
    }

    func reveal() {
        revealed = true
        streak = 0
    }

    func answerChord(_ name: String) {
        guard mode == .chord else { return }
        if name == chordAnswer { success("Richtig: \(name)") } else {
            streak = 0
            feedback = (false, "\(name)? Nochmal hinhören.")
        }
    }

    private func input(_ p: Int, _ v: UInt8) {
        audio.ownOn(UInt8(p), velocity: v)
        guard mode != .chord, progress < sequence.count else { return }
        if p == sequence[progress] {
            progress += 1
            if progress == sequence.count {
                var text = "Richtig: " + sequence.map { NoteNames.name($0) }.joined(separator: " – ")
                if mode == .interval { text += " (\(NoteNames.intervalNames[sequence[0] - 60]))" }
                success(text)
            }
        } else {
            streak = 0
            feedback = (false, "\(NoteNames.name(p)) – nicht ganz. Nochmal hören?")
        }
    }

    private func success(_ text: String) {
        streak += 1
        solved += 1
        if streak > best { best = streak; Prefs.set("earBest", streak) }
        feedback = (true, text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.newRound() }
    }
}

struct EarTrainerView: View {
    @StateObject private var model = EarModel()
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        VStack(spacing: 22) {
            Picker("Modus", selection: $model.mode) {
                ForEach(EarMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 520)

            HStack(spacing: 34) {
                stat("\(model.streak)", "Serie")
                stat("\(model.best)", "Beste Serie")
                stat("\(model.solved)", "Gelöst")
            }

            Text(instruction).font(.title3).multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button { model.play() } label: { Label("Nochmal hören", systemImage: "speaker.wave.3.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button { model.reveal() } label: { Label("Lösung zeigen", systemImage: "eye") }
                Button { model.newRound() } label: { Label("Neue Aufgabe", systemImage: "arrow.clockwise") }
            }

            if model.mode == .chord {
                HStack {
                    ForEach(EarModel.chordTypes, id: \.name) { t in
                        Button(t.name) { model.answerChord(t.name) }.controlSize(.large)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<model.sequence.count, id: \.self) { k in
                        Circle().fill(k < model.progress ? Color.hitGreen : Color.white.opacity(0.2)).frame(width: 18, height: 18)
                    }
                }
            }

            if model.revealed {
                Text(model.mode == .chord ? model.chordAnswer : model.sequence.map { NoteNames.name($0) }.joined(separator: " – "))
                    .font(.title2.bold()).foregroundStyle(.yellow)
            }
            if let f = model.feedback {
                Text(f.text).font(.title3.bold()).foregroundStyle(f.ok ? Color.hitGreen : Color.missRed)
            }
            Spacer()
        }
        .padding(30)
        .navigationTitle("Gehörtraining")
        .onAppear { model.attach() }
        .onDisappear { library.recordTraining(title: "Gehörtraining", seconds: model.detach()) }
    }

    private var instruction: String {
        switch model.mode {
        case .note: return "Hör den Ton und spiel ihn nach (C4–C5)."
        case .interval: return "Erst C4, dann der Zielton. Spiel den Zielton."
        case .melody: return "Drei Töne in C-Dur. Spiel sie in der richtigen Reihenfolge nach."
        case .chord: return "Welche Akkord-Qualität hörst du?"
        }
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.title, design: .rounded).bold())
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
    }
}
