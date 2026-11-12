import SwiftUI
import AppKit

// MARK: - Übe-Voreinstellung pro Lernschritt (Kompatibilität)

struct PracticePreset: Hashable {
    var mode: PracticeMode = .wait
    var hands: HandSelection = .both
    var tempo: Double = 0.8
    var loop: ClosedRange<Int>? = nil
    var viewMode: ViewMode? = nil
    var labelMode: LabelMode? = nil
    var autoTempo: Bool? = nil
    var metronome: Bool? = nil
}

struct LessonStep: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let goal: String
    let paragraphs: [String]
    let arrangement: Arrangement
    let preset: PracticePreset
    let perPhrase: Bool
}

// MARK: - Lernplan für CLI & Analyse

enum LessonPlan {
    static func steps(song: MidiSong, a: SongAnalysis) -> [LessonStep] {
        let distinct = Set(a.phrases.map { $0.label.replacingOccurrences(of: "'", with: "") }).count
        let repeats = a.phrases.filter { $0.repeatOf != nil }.count
        let firstLoop: ClosedRange<Int>? = a.phrases.first.map { $0.fromBar...$0.toBar }
        let cadences = a.phrases.compactMap { p in p.cadence.map { "Takt \(p.toBar + 1): \($0)" } }
        let progLines = a.phrases.prefix(8).map { p in
            "Takt \(p.fromBar + 1)–\(p.toBar + 1) [\(p.label)]: \(p.progression)   ·   \(p.romans)"
        }
        let funcs = Set(a.segments.map(\.function)).filter { $0 != "Pause" }

        return [
            LessonStep(id: 0, icon: "ear", title: "Hören & Überblick",
                       goal: "Verstehen, wie das Stück gebaut ist, bevor du eine Taste drückst.",
                       paragraphs: [
                        "Tonart: **\(a.keyName)** · \(a.character) · \(song.barTimes.count) Takte.",
                        "Form: **\(a.formString)** – \(a.phrases.count) Phrasen, davon \(repeats) Wiederholungen. Du lernst eigentlich nur **\(distinct) verschiedene Teile**.",
                        "Hör auf drei Dinge: Wo ist der Höhepunkt der Melodie (Takt \(a.melodyPeakBar + 1))? Wo „atmet“ die Musik (Phrasenenden)? Was macht die linke Hand (\(a.lhPattern))?",
                        "Die Zahlen auf den Noten zeigen die Rolle im Akkord: 1 = Grundton, 3 = Terz, 5 = Quinte, 7 = Septime, · = Verzierung."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .listen, hands: .both, tempo: 1.0, viewMode: .both, labelMode: .harmony),
                       perPhrase: false),
            LessonStep(id: 1, icon: "square.stack.3d.up", title: "Harmonie: das Gerüst",
                       goal: "Die Akkordfolge als Blöcke spielen – das Fundament, auf dem alles steht.",
                       paragraphs: [
                        "So läuft die Harmonie (Akkord · Stufe):\n" + progLines.joined(separator: "\n"),
                        "Funktionen im Stück: \(funcs.sorted().joined(separator: ", ")). **Tonika** = Zuhause, **Subdominante** = Weg von zu Hause, **Dominante** = Spannung, die zurück zur Tonika will.",
                        cadences.isEmpty ? "Achte darauf, wie jede Phrase auf einem Akkord „landet“." : "Kadenzen (Satzzeichen der Musik):\n" + cadences.prefix(6).joined(separator: "\n"),
                        "Spiel die Akkorde links als Blöcke mit. Ziel: Die Griffwechsel ohne Hinsehen."
                       ],
                       arrangement: .chords,
                       preset: PracticePreset(mode: .wait, hands: .left, tempo: 0.7, viewMode: .both, labelMode: .harmony),
                       perPhrase: false),
            LessonStep(id: 2, icon: "metronome", title: "Rhythmus fühlen",
                       goal: "Den Puls verinnerlichen – hier zählt nur das Timing, nicht die Taste.",
                       paragraphs: [
                        "Takt \(song.timeSignature): Zähl laut mit (\(countPattern(song))). Der Schwerpunkt liegt auf der 1.",
                        "Im Rhythmus-Modus ist jede Taste richtig – nur der Zeitpunkt zählt. Klopf die Rhythmen beider Hände, bis „Perfekt“ kommt.",
                        "Metronom ist an. Wenn du konstant „früh“ bist: du eilst – bewusst warten."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .rhythm, hands: .both, tempo: 0.7, labelMode: LabelMode.none, metronome: true),
                       perPhrase: false),
            LessonStep(id: 3, icon: "hand.raised", title: "Linke Hand: Begleitmuster",
                       goal: "Die Begleitung als zerlegte Akkorde verstehen, nicht als Einzeltöne.",
                       paragraphs: [
                        "Muster: **\(a.lhPattern)**.",
                        a.lhPatternDetail,
                        "Umfang links: \(a.lhRange). Jede Figur ist ein Akkord aus dem Gerüst-Schritt – greif ihn erst als Block, dann zerlege ihn.",
                        "Übe Phrase für Phrase (Phrase unten wählen)."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .wait, hands: .left, tempo: 0.6, loop: firstLoop, labelMode: .fingers),
                       perPhrase: true),
            LessonStep(id: 4, icon: "music.note", title: "Melodie: Kerntöne",
                       goal: "Erst die tragenden Töne der Melodie – die Verzierungen kommen danach.",
                       paragraphs: [
                        "\(a.chordTonePercent) % der Melodie stehen auf Akkordtönen. Diese Fassung zeigt nur die Kerntöne auf den Zählzeiten – das ist das Gerüst, das du singen können solltest.",
                        "Umfang rechts: \(a.rhRange). Höhepunkt in Takt \(a.melodyPeakBar + 1) – darauf läuft alles zu.",
                        "Sing beim Spielen mit. Was du singen kannst, kannst du phrasieren."
                       ],
                       arrangement: .skeleton,
                       preset: PracticePreset(mode: .wait, hands: .right, tempo: 0.7, labelMode: .harmony),
                       perPhrase: false),
            LessonStep(id: 5, icon: "music.quarternote.3", title: "Melodie: Original",
                       goal: "Die Verzierungen um die Kerntöne herum ergänzen.",
                       paragraphs: [
                        "Noten mit „·“ sind Verzierungen: Durchgangstöne (verbinden zwei Akkordtöne) und Nebennoten (umspielen einen Akkordton). Sie lösen sich immer in einen Kernton auf.",
                        "Fingersatz ist eingeblendet. Bleib in einer Handposition, solange es geht – Lagenwechsel am besten auf einem Kernton.",
                        "Phrase für Phrase, dann verbinden."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .wait, hands: .right, tempo: 0.7, loop: firstLoop, labelMode: .fingers),
                       perPhrase: true),
            LessonStep(id: 6, icon: "arrow.up.and.down.and.arrow.left.and.right", title: "Außenstimmen: Melodie + Bass",
                       goal: "Hören, wie Sopran und Bass miteinander sprechen – die Mittelstimmen kommen später.",
                       paragraphs: [
                        "Lass die Akkordfüllung links weg – spiel nur den tiefsten Basston und die Melodie rechts.",
                        "Das ist die wichtigste Achse der Mehrstimmigkeit: Gegenbewegung (Melodie steigt, Bass fällt) klingt am stärksten.",
                        "Erst Takt für Takt, dann flüssig."
                       ],
                       arrangement: .melodyBass,
                       preset: PracticePreset(mode: .wait, hands: .both, tempo: 0.7, labelMode: .names),
                       perPhrase: false),
            LessonStep(id: 7, icon: "hands.sparkles", title: "Phrase für Phrase zusammen",
                       goal: "Beide Hände zusammen – aber immer nur 4 Takte, bis sie sitzen.",
                       paragraphs: [
                        "Wähle Phrase A (Takt \(firstLoop.map { "\($0.lowerBound + 1)–\($0.upperBound + 1)" } ?? "1–4")).",
                        "Warte-Modus stoppt automatisch, wenn ein Ton fehlt – kein Stress.",
                        "Erst wenn eine Phrase 3× sauber läuft: Weiter zur nächsten."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .wait, hands: .both, tempo: 0.6, loop: firstLoop, labelMode: .fingers),
                       perPhrase: true),
            LessonStep(id: 8, icon: "chart.line.uptrend.xyaxis", title: "Fluss & Tempo",
                       goal: "Vom Warte-Modus zum flüssigen Spiel – das Tempo steigt automatisch mit jedem sauberen Durchlauf.",
                       paragraphs: [
                        "Tempo-Trainer ist an: Bei jedem Durchlauf mit ≥ 85 % Genauigkeit steigt das Tempo um 5 %.",
                        "Start bei 70 %, Ziel: 100 % (Originaltempo \(Int(song.bpm)) BPM).",
                        "Wenn du an einer Stelle hängen bleibst: Taste **B** drücken, die App loopt automatisch den fehlerhaftesten Takt."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .play, hands: .both, tempo: 0.7, loop: firstLoop, labelMode: LabelMode.none, autoTempo: true),
                       perPhrase: true),
            LessonStep(id: 9, icon: "slider.horizontal.3", title: "Gestalten & Dynamik",
                       goal: "Nicht nur Tasten drücken, sondern Musik machen: Lautstärke, Phrasierung, Pedal.",
                       paragraphs: [
                        "Dynamik: \(a.dynamicsNote)",
                        "Pedal: Bei jedem Akkordwechsel kurz lupfen (Treten nach dem Anschlag, nicht gleichzeitig). Die gelben Balken zeigen die Pedal-Spur.",
                        "Melodie immer eine Nuance lauter als die Begleitung spielen – Gewicht in den kleinen Finger rechts."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .play, hands: .both, tempo: 0.9, viewMode: .sheet, labelMode: LabelMode.none),
                       perPhrase: false),
            LessonStep(id: 10, icon: "star.fill", title: "Vorspiel (Konzert)",
                       goal: "Das ganze Stück von vorn bis hinten – wie auf der Bühne, ohne Hilfe.",
                       paragraphs: [
                        "Konzert-Modus: Kein Notenblatt, keine Namen, kein Metronom – nur du, das Klavier und die Musik.",
                        "Tempo 100 % (\(Int(song.bpm)) BPM), Originalfassung.",
                        "Ziel: 3 Sterne (≥ 90 % Genauigkeit). Das Stück gilt danach als „Gemeistert“."
                       ],
                       arrangement: .original,
                       preset: PracticePreset(mode: .play, hands: .both, tempo: 1.0, viewMode: .sheet, labelMode: LabelMode.none),
                       perPhrase: false)
        ]
    }

    static func countPattern(_ s: MidiSong) -> String {
        let n = max(s.pulsesPerBar, 1)
        return (1...min(n, 12)).map(String.init).joined(separator: " – ")
    }
}

// MARK: - KI-Lehrer (Chat AI / Gemini)

enum TeacherAI {
    static let system = """
    Du bist ein moderner, ermutigender Klavierlehrer im Stil von Flowkey und PianoSecrets: Du erklärst Stücke \
    Schritt für Schritt – Rhythmus, Melodie, Akkorde und Hände. Antworte auf Deutsch, in der Du-Form, motivierend, \
    kurz und präzise mit Taktnummern. Maximal 150 Wörter.
    """

    static func ask(_ prompt: String) async -> String {
        if let r = try? await chatAI(prompt), !r.isEmpty { return r }
        if let r = gemini(prompt), !r.isEmpty { return r + "\n\n_(Antwort von Gemini)_" }
        return "Der KI-Lehrer ist gerade nicht erreichbar. Prüfe die Internetverbindung."
    }

    private static func run(_ path: String, _ args: [String], cwd: String? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chatAI(_ prompt: String) async throws -> String? {
        guard let key = run("/usr/bin/security", ["find-generic-password", "-s", "saia-api-key", "-w"]), !key.isEmpty else { return nil }
        var req = URLRequest(url: URL(string: "https://chat-ai.academiccloud.de/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "qwen3.5-397b-a17b",
            "temperature": 0.5,
            "max_tokens": 4000,
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let msg = ((json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        return msg.map(stripThinking)
    }

    private static func gemini(_ prompt: String) -> String? {
        let agy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path
        guard FileManager.default.isExecutableFile(atPath: agy) else { return nil }
        let dir = NSTemporaryDirectory() + "pf-agy"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let out = run(agy, ["-p", system + "\n\n" + prompt, "--model", "gemini-3.8-flash-high", "--output-format", "json"], cwd: dir),
              let d = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return (json["response"] as? String).map(stripThinking)
    }

    private static func stripThinking(_ s: String) -> String {
        var t = s
        while let a = t.range(of: "<think>") {
            if let b = t.range(of: "</think>", range: a.upperBound..<t.endIndex) {
                t.removeSubrange(a.lowerBound..<b.upperBound)
            } else {
                t.removeSubrange(a.lowerBound..<t.endIndex)
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class TeacherModel: ObservableObject {
    @Published var answers: [String: String] = [:]
    @Published var loading: Set<String> = []
    let songID: UUID
    private let dir: URL

    init(songID: UUID) {
        self.songID = songID
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PianoFlow/Lehrer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL {
        dir.appendingPathComponent("\(songID.uuidString)-\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key).md")
    }

    func cached(_ key: String) -> String? {
        if let m = answers[key] { return m }
        if let s = try? String(contentsOf: file(key), encoding: .utf8) {
            answers[key] = s
            return s
        }
        return nil
    }

    func ask(key: String, prompt: String, force: Bool = false) {
        if !force, let c = cached(key) { answers[key] = c; return }
        loading.insert(key)
        Task {
            let r = await Task.detached { await TeacherAI.ask(prompt) }.value
            answers[key] = r
            loading.remove(key)
            if !r.hasPrefix("Der KI-Lehrer ist gerade nicht erreichbar") {
                try? r.write(to: file(key), atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - Flowkey LessonView (Ultra-minimalistisch & Takt-für-Takt)

struct LessonView: View {
    let entry: SongEntry
    let song: MidiSong
    let analysis: SongAnalysis
    @EnvironmentObject var library: LibraryStore
    @StateObject private var engine: PracticeEngine
    @StateObject private var teacher: TeacherModel
    @AppStorage("simpleMode") private var simple = true
    @AppStorage("micEnabled") private var micEnabled = false

    // Takt- & Navigationszustand
    @State private var fromBarIndex: Int = 0
    @State private var toBarIndex: Int = 3
    @State private var loopActive: Bool = true
    @State private var showTeacher = false
    @State private var showSettings = false
    @State private var showBarPicker = false
    @State private var monitor: Any?
    @State private var confetti = 0
    @AppStorage("hideKeyboardHint") private var hideKeyboardHint = false

    init(entry: SongEntry, song: MidiSong, analysis: SongAnalysis) {
        self.entry = entry
        self.song = song
        self.analysis = analysis
        _teacher = StateObject(wrappedValue: TeacherModel(songID: entry.id))
        _engine = StateObject(wrappedValue: PracticeEngine(
            song: song,
            audio: AppServices.shared.audio,
            midi: AppServices.shared.midi,
            analysis: analysis
        ))
    }

    private var barsCount: Int { max(song.barTimes.count, 1) }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Schlanke, aufgeräumte Kopfzeile mit Takt-Auswahl & Ansichts-Wahl
            slimHeaderView

            // 2. Voller Fokus auf das Notenblatt, den Wasserfall & die Klaviatur (vollkommen unbedeckt!)
            PianoStage(engine: engine)
                .overlay(alignment: .top) { BannerOverlay(engine: engine).padding(.top, 8) }
                .overlay { CountdownOverlay(engine: engine) }
                .overlay { ConfettiView(trigger: confetti) }
                .overlay {
                    if engine.midiSources.isEmpty && !hideKeyboardHint {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                keyboardHint.padding(.bottom, PianoStage.keyboardHeight(geo.size) + 10)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

            // 3. Feste Bedienleiste UNTERHALB der Tastatur (kein Überlappen!)
            bottomControlsBar
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            engine.detach()
            library.record(songID: entry.id, title: entry.title, result: nil,
                           seconds: engine.takePracticeSeconds(), mode: engine.mode)
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }
        .sheet(isPresented: $showTeacher) {
            teacherSheetView
        }
        .popover(isPresented: $showSettings) {
            MixerPopover(engine: engine)
        }
        .onChange(of: engine.loopBarStart) { _, newStart in
            if let newStart {
                fromBarIndex = newStart
                toBarIndex = engine.loopBarEnd ?? newStart
                loopActive = true
            } else {
                loopActive = false
            }
        }
        .onChange(of: engine.loopBarEnd) { _, newEnd in
            if let newEnd {
                toBarIndex = newEnd
                fromBarIndex = engine.loopBarStart ?? newEnd
                loopActive = true
            } else {
                loopActive = false
            }
        }
    }

    /// Hinweis für alle ohne MIDI-Keyboard: so spielt man mit der Mac-Tastatur
    private var keyboardHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kein MIDI-Keyboard? Spiel mit der Tastatur:").font(.caption.bold())
                Text("A S D F G H J K = C D E F G A H C  ·  W E T Z U = schwarze Tasten  ·  X / C = Oktave runter / hoch")
                    .font(.caption.monospaced())
            }
            Button { hideKeyboardHint = true } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Hinweis ausblenden")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .foregroundStyle(.white)
    }

    // MARK: - Initial Setup

    private func setupInitialState() {
        engine.attach()
        engine.viewMode = .both
        // Einmalig: klassisches Notenbild mit Fingersatz statt Namen als Start
        if !Prefs.bool("classicNotesIntroduced", false) {
            Prefs.set("classicNotesIntroduced", true)
            engine.labelMode = .fingers
        }
        engine.mode = .wait
        engine.handSelection = .both
        engine.tempo = 0.8

        // Starte mit 1 Takt oder einer kurzen Phrase
        if let first = analysis.phrases.first {
            setBarRange(from: first.fromBar, to: first.toBar, autoRestart: false)
        } else {
            setBarRange(from: 0, to: min(1, barsCount - 1), autoRestart: false)
        }

        let id = entry.id
        let t = entry.title
        engine.onFinished = { [weak e = engine, weak lib = library] r in
            lib?.record(songID: id, title: t, result: r, seconds: e?.takePracticeSeconds() ?? 0, mode: r.mode)
            if (r.accuracy ?? 0) >= 0.85 {
                e?.showBanner("Abschnitt gemeistert! ★★★")
            }
        }
        // Jeder sauber geschaffte Loop-Durchgang wird gefeiert
        engine.onPassCompleted = { [weak e = engine] acc in
            guard acc >= 0.9 else { return }
            confetti += 1
            e?.showBanner(acc >= 0.99 ? "Fehlerfrei! 🎉 Weiter mit „Weiter →“" : "Geschafft – \(Int(acc * 100)) % richtig! 🎉")
        }

        // Tastatursteuerung: Pfeil links (Takte zurück), Pfeil rechts (Takte vor), Leertaste (Play/Pause)
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak e = engine] ev in
            guard let e else { return ev }
            if ev.window?.firstResponder is NSText { return ev }
            if ev.keyCode == 123 || ev.keyCode == 124 { // Pfeil links / rechts: taktweise
                if ev.type == .keyDown && !ev.isARepeat {
                    if ev.keyCode == 123 { goToPreviousBar() } else { goToNextBar() }
                }
                return nil
            }
            return e.handleKey(ev) ? nil : ev
        }
    }

    // MARK: - 1. Slim Header View

    private var slimHeaderView: some View {
        HStack(spacing: 12) {
            // Titel & Tonart
            HStack(spacing: 8) {
                Text(entry.title.replacingOccurrences(of: "_", with: " "))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260, alignment: .leading)
                    .help(entry.title)

                Text(analysis.keyName)
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(Color.orange)

                Text("\(Int(song.bpm)) BPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .layoutPriority(-1)

            Spacer()

            // Takt-Navigation & Loop-Auswahl (Zentral oben im Header – kinderleicht zu bedienen)
            HStack(spacing: 8) {
                Button {
                    goToPreviousBar()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.bold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.bordered)
                .disabled(fromBarIndex <= 0)
                .help("Vorherige Takte (Pfeiltaste links)")

                Button {
                    showBarPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: loopActive ? "repeat" : "music.note")
                            .foregroundStyle(loopActive ? Color.accentColor : Color.secondary)

                        if loopActive {
                            if fromBarIndex == toBarIndex {
                                Text("Takt \(fromBarIndex + 1)")
                                    .font(.subheadline.bold())
                            } else {
                                Text("Takt \(fromBarIndex + 1)–\(toBarIndex + 1)")
                                    .font(.subheadline.bold())
                            }
                            if !chordName(fromBarIndex).isEmpty {
                                Text("· \(chordName(fromBarIndex))")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.orange)
                            }
                        } else {
                            Text("Ganzer Song")
                                .font(.subheadline.bold())
                        }

                        Text("von \(barsCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showBarPicker) {
                    barPickerPopoverView
                }

                Button {
                    goToNextBar()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.bold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.bordered)
                .disabled(toBarIndex >= barsCount - 1)
                .help("Nächste Takte (Pfeiltaste rechts)")

                // Schnelle Takt-Längen
                HStack(spacing: 4) {
                    Button("Ganzer Song") {
                        loopActive = false
                        engine.clearLoop()
                        engine.restart()
                        engine.showBanner("Ganzen Song")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(!loopActive ? Color.accentColor : Color.secondary)
                }
            }

            Spacer()

            // Ansichts-Wahl & Optionen
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    viewTabButton("Noten", mode: .sheet, icon: "music.note")
                    viewTabButton("Wasserfall", mode: .waterfall, icon: "water.waves")
                    viewTabButton("Beides", mode: .both, icon: "rectangle.split.2x1")
                    viewTabButton("Ganzes Blatt", mode: .page, icon: "doc.richtext")
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))

                Button {
                    showTeacher = true
                } label: {
                    Label("KI-Tipp", systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.purple)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Mixer & Audio")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    private func viewTabButton(_ title: String, mode: ViewMode, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                engine.viewMode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).fixedSize()
            }
            .font(.caption2.weight(engine.viewMode == mode ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(engine.viewMode == mode ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(engine.viewMode == mode ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Feste Bedienleiste UNTERHALB der Tastatur (Kinderleicht & 100% frei)

    private var bottomControlsBar: some View {
        HStack(spacing: 20) {
            // 1. Hand-Auswahl (Große, verständliche Buttons)
            HStack(spacing: 6) {
                handButton("Rechts", hand: .right, icon: "hand.point.right.fill")
                handButton("Links", hand: .left, icon: "hand.point.left.fill")
                handButton("Beide", hand: .both, icon: "hands.sparkles.fill")
            }

            Spacer()

            // 2. Start / Pause & Wiederholen (Groß im Zentrum)
            HStack(spacing: 12) {
                Button {
                    engine.togglePlay()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.bold())
                        Text(engine.isPlaying ? "Pause" : "Start")
                            .font(.headline.bold())
                    }
                    .frame(width: 105, height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isPlaying ? Color.orange : Color.green)
                .help("Start / Pause (Leertaste)")

                Button {
                    engine.restart()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .help("Von vorn beginnen (R)")
            }

            Spacer()

            // 3. Modus & Tempo
            HStack(spacing: 12) {
                // Modus: Warten (die App wartet) vs. Flüssig
                Button {
                    engine.mode = (engine.mode == .wait) ? .play : .wait
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: engine.mode == .wait ? "hourglass" : "play.circle.fill")
                        Text(engine.mode == .wait ? "Warten auf Taste" : "Flüssig spielen")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                }
                .buttonStyle(.bordered)
                .tint(engine.mode == .wait ? Color.green : Color.accentColor)

                // Tempo-Schnellauswahl: 50% (Langsam), 75% (Mittel), 100% (Original)
                HStack(spacing: 4) {
                    tempoPill("🐢 50%", val: 0.5)
                    tempoPill("🚶 75%", val: 0.75)
                    tempoPill("🐇 100%", val: 1.0)
                }

                // Beschriftung der Noten (Namen, Do-Re-Mi, Fingersatz …)
                Menu {
                    Picker("Beschriftung", selection: $engine.labelMode) {
                        ForEach(LabelMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Picker("Notenbild", selection: $engine.kidNotes) {
                        Text("Klassisch (wie gedruckt)").tag(false)
                        Text("Kindernoten (Namen im Notenkopf)").tag(true)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(engine.labelMode == .none ? "Ohne Namen" : engine.labelMode.rawValue, systemImage: "textformat.abc")
                        .font(.subheadline.weight(.semibold))
                }
                .menuStyle(.button)
                .fixedSize()
                .frame(height: 38)
                .help("Was in den Noten und auf den Tasten steht")

                // Metronom
                Button {
                    engine.metronome.toggle()
                } label: {
                    Image(systemName: "metronome.fill")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .tint(engine.metronome ? .yellow : .secondary)
                .help(engine.metronome ? "Metronom aus (M)" : "Metronom an (M)")

                // Weiter zum nächsten Takt
                Button {
                    goToNextBar()
                } label: {
                    HStack(spacing: 6) {
                        Text("Weiter")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
    }

    private func tempoPill(_ title: String, val: Double) -> some View {
        let isSel = abs(engine.tempo - val) < 0.05
        return Button(title) {
            engine.tempo = val
        }
        .font(.caption.weight(isSel ? .bold : .medium))
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSel ? Color.accentColor : Color.white.opacity(0.06))
        )
        .foregroundStyle(isSel ? .white : .secondary)
        .buttonStyle(.plain)
    }

    private func handButton(_ title: String, hand: HandSelection, icon: String) -> some View {
        let active = engine.handSelection == hand
        return Button {
            engine.handSelection = hand
            engine.restart()
            engine.showBanner(hand == .left ? "Nur linke Hand – die rechte spielt die App" :
                              hand == .right ? "Nur rechte Hand – die linke spielt die App" : "Beide Hände")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(active ? .bold : .medium))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Color.accentColor : Color.white.opacity(0.06))
            )
            .foregroundStyle(active ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bar Picker Popover View

    private var barPickerPopoverView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Takte zum Üben auswählen")
                    .font(.headline)
                Spacer()
                Button("Ganzen Song spielen") {
                    loopActive = false
                    engine.clearLoop()
                    engine.restart()
                    engine.showBanner("Ganzen Song")
                    showBarPicker = false
                }
                .buttonStyle(.bordered)
            }

            // 1. Schnell-Längen: 1 Takt, 2 Takte, 4 Takte, 8 Takte
            HStack(spacing: 8) {
                Text("Länge:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                quickLengthBtn("1 Takt", count: 1)
                quickLengthBtn("2 Takte", count: 2)
                quickLengthBtn("4 Takte", count: 4)
                quickLengthBtn("8 Takte", count: 8)
            }

            Divider()

            // 2. Taktbereich einstellen
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Von Takt: \(fromBarIndex + 1)").font(.caption.bold())
                    Stepper("", onIncrement: {
                        if fromBarIndex < barsCount - 1 {
                            setBarRange(from: fromBarIndex + 1, to: max(fromBarIndex + 1, toBarIndex))
                        }
                    }, onDecrement: {
                        if fromBarIndex > 0 {
                            setBarRange(from: fromBarIndex - 1, to: toBarIndex)
                        }
                    })
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bis Takt: \(toBarIndex + 1)").font(.caption.bold())
                    Stepper("", onIncrement: {
                        if toBarIndex < barsCount - 1 {
                            setBarRange(from: fromBarIndex, to: toBarIndex + 1)
                        }
                    }, onDecrement: {
                        if toBarIndex > fromBarIndex {
                            setBarRange(from: fromBarIndex, to: toBarIndex - 1)
                        }
                    })
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ausgewählt:").font(.caption).foregroundStyle(.secondary)
                    Text("\(toBarIndex - fromBarIndex + 1) Takte").font(.caption.bold()).foregroundStyle(Color.orange)
                }
            }

            if !analysis.phrases.isEmpty {
                Divider()
                Text("Abschnitte aus dem Song:").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(analysis.phrases) { p in
                            let isSel = fromBarIndex == p.fromBar && toBarIndex == p.toBar && loopActive
                            Button {
                                setBarRange(from: p.fromBar, to: p.toBar)
                                showBarPicker = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(p.label).bold()
                                        Text("T. \(p.fromBar + 1)–\(p.toBar + 1)")
                                    }
                                    if !p.progression.isEmpty {
                                        Text(p.progression).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(isSel ? Color.accentColor : Color.white.opacity(0.06)))
                                .foregroundStyle(isSel ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            Text("Oder Einzeltakt wählen:").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(0..<barsCount, id: \.self) { b in
                        let inRange = b >= fromBarIndex && b <= toBarIndex && loopActive
                        Button {
                            setBarRange(from: b, to: b)
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(b + 1)").font(.caption2.bold())
                                let c = chordName(b)
                                Text(c.isEmpty ? "·" : c).font(.system(size: 9)).foregroundStyle(Color.orange)
                            }
                            .frame(width: 38, height: 34)
                            .background(RoundedRectangle(cornerRadius: 6).fill(inRange ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.06)))
                            .foregroundStyle(inRange ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private func quickLengthBtn(_ title: String, count: Int) -> some View {
        Button(title) {
            let newTo = min(barsCount - 1, fromBarIndex + count - 1)
            setBarRange(from: fromBarIndex, to: newTo)
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .tint((toBarIndex - fromBarIndex + 1 == count && loopActive) ? Color.accentColor : Color.secondary)
    }

    // MARK: - Takt für Takt Aktionen

    private func setBarRange(from a: Int, to b: Int, autoRestart: Bool = true) {
        let lo = max(0, min(a, barsCount - 1))
        let hi = max(lo, min(b, barsCount - 1))
        fromBarIndex = lo
        toBarIndex = hi
        loopActive = true
        engine.loopBars(lo, hi)
        if autoRestart {
            engine.restart()
        }
        let span = hi - lo + 1
        if span == 1 {
            engine.showBanner("Takt \(lo + 1) \(chordName(lo).isEmpty ? "" : "· \(chordName(lo))")")
        } else {
            engine.showBanner("Takt \(lo + 1)–\(hi + 1) (\(span) Takte)")
        }
    }

    private func goToPreviousBar() {
        let span = max(1, toBarIndex - fromBarIndex + 1)
        let newFrom = max(0, fromBarIndex - span)
        let newTo = newFrom + span - 1
        setBarRange(from: newFrom, to: newTo)
    }

    private func goToNextBar() {
        let span = max(1, toBarIndex - fromBarIndex + 1)
        let newFrom = min(barsCount - 1, fromBarIndex + span)
        let newTo = min(barsCount - 1, newFrom + span - 1)
        setBarRange(from: newFrom, to: newTo)
    }

    private func chordName(_ bar: Int) -> String {
        guard bar >= 0, bar < song.barTimes.count else { return "" }
        let start = song.barTimes[bar]
        let end = bar + 1 < song.barTimes.count ? song.barTimes[bar + 1] : song.duration
        let segs = analysis.segments.filter { $0.start < end && $0.end > start && $0.rootPC != nil }
        return segs.first?.chord ?? ""
    }

    // MARK: - KI-Lehrer Sheet

    @State private var chatPrompt = ""
    @State private var chatHistory: [(user: String, answer: String)] = []

    private var teacherSheetView: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Takt \(fromBarIndex + 1)–\(toBarIndex + 1)")
                            .font(.headline)
                        Text("Tonart: \(analysis.keyName) · \(chordName(fromBarIndex))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Neu erklären") {
                        loadTeacherExplanation(force: true)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        let key = "bar_\(fromBarIndex)_\(toBarIndex)"
                        if teacher.loading.contains(key) {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("KI analysiert diesen Takt …").font(.caption)
                            }
                            .padding()
                        } else if let exp = teacher.cached(key) {
                            Text(.init(exp))
                                .font(.body)
                                .textSelection(.enabled)
                        } else {
                            Button {
                                loadTeacherExplanation(force: false)
                            } label: {
                                Label("Takt \(fromBarIndex + 1)–\(toBarIndex + 1) erklären", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        ForEach(Array(chatHistory.enumerated()), id: \.offset) { _, item in
                            Divider()
                            Text("Frage: \(item.user)").font(.caption.bold())
                            Text(.init(item.answer)).font(.body).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }

                HStack {
                    TextField("Frage stellen (z. B. Welchen Fingersatz nutze ich?)", text: $chatPrompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(sendChatMessage)
                    Button("Fragen", action: sendChatMessage)
                        .disabled(chatPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("KI-Klavierlehrer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { showTeacher = false }
                }
            }
            .onAppear {
                loadTeacherExplanation(force: false)
            }
        }
        .frame(minWidth: 480, minHeight: 440)
    }

    /// Wo hat der Schüler zuletzt Fehler gemacht? (für gezieltere KI-Tipps)
    private var errorContext: String {
        let errs = engine.errorsPerBar.enumerated()
            .filter { $0.element > 0 && $0.offset >= fromBarIndex && $0.offset <= toBarIndex }
            .map { "Takt \($0.offset + 1): \($0.element) Fehler" }
        return errs.isEmpty ? "" : "Der Schüler hatte zuletzt Probleme in: \(errs.joined(separator: ", ")). Geh besonders darauf ein."
    }

    private func loadTeacherExplanation(force: Bool) {
        let key = "bar_\(fromBarIndex)_\(toBarIndex)"
        let p = """
        Stück: \(entry.title), Tonart: \(analysis.keyName).
        \(errorContext)
        Erkläre Takt \(fromBarIndex + 1)–\(toBarIndex + 1) (\(chordName(fromBarIndex))):
        Welche Noten und Handpositionen liegen hier? Konkreter Fingersatz und Spieltipp in der Du-Form, maximal 100 Wörter.
        """
        teacher.ask(key: key, prompt: p, force: force)
    }

    private func sendChatMessage() {
        let q = chatPrompt.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        chatPrompt = ""
        Task {
            let prompt = "Stück: \(entry.title), Takt \(fromBarIndex + 1)–\(toBarIndex + 1). Frage des Spielers: \(q)"
            let ans = await TeacherAI.ask(prompt)
            chatHistory.append((user: q, answer: ans))
        }
    }
}
