import SwiftUI
import UniformTypeIdentifiers
import QuartzCore

func formatTime(_ s: Double) -> String {
    let v = max(0, Int(s.rounded(.down)))
    return String(format: "%d:%02d", v / 60, v % 60)
}

extension Notification.Name {
    static let openMIDIFiles = Notification.Name("PianoFlowOpenMIDIFiles")
}

enum NavItem: Hashable {
    case dashboard, freePlay, exercises, reading, ear
    case song(UUID)
}

enum SongSort: String, CaseIterable, Identifiable {
    case title = "Titel", recent = "Zuletzt geübt", difficulty = "Schwierigkeit", added = "Hinzugefügt"
    var id: String { rawValue }
}

// MARK: - Hauptfenster

struct ContentView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var selection: NavItem? = .dashboard
    @State private var importing = false
    @State private var renaming: SongEntry?
    @State private var newTitle = ""
    @State private var search = ""
    @State private var onlyFavorites = false
    @State private var sort: SongSort = .title
    @AppStorage("simpleMode") private var simple = true

    private var filtered: [SongEntry] {
        var list = library.songs
        if onlyFavorites { list = list.filter(\.isFavorite) }
        if !search.isEmpty { list = list.filter { $0.title.localizedCaseInsensitiveContains(search) } }
        switch sort {
        case .title: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent: list.sort { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .difficulty: list.sort { ($0.difficulty ?? 0) < ($1.difficulty ?? 0) }
        case .added: list.sort { $0.added > $1.added }
        }
        return list
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Training") {
                    Label("Übersicht", systemImage: "chart.bar.xaxis").tag(NavItem.dashboard)
                    Label("Freies Spielen", systemImage: "pianokeys").tag(NavItem.freePlay)
                    if !simple {
                        Label("Übungen & Tonleitern", systemImage: "figure.strengthtraining.traditional").tag(NavItem.exercises)
                        Label("Notenlesen-Trainer", systemImage: "eye").tag(NavItem.reading)
                        Label("Gehörtraining", systemImage: "ear").tag(NavItem.ear)
                    }
                }
                Section("Songs (\(library.songs.count))") {
                    ForEach(filtered) { s in
                        SongRow(entry: s)
                            .tag(NavItem.song(s.id))
                            .contextMenu {
                                Button(s.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten") { library.toggleFavorite(s) }
                                Button("Umbenennen …") { newTitle = s.title; renaming = s }
                                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([library.url(for: s)]) }
                                Divider()
                                Button("Löschen", role: .destructive) {
                                    if selection == .song(s.id) { selection = .dashboard }
                                    library.delete(s)
                                }
                            }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Songs suchen")
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        Picker("Sortieren", selection: $sort) {
                            ForEach(SongSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Nur Favoriten", isOn: $onlyFavorites)
                    } label: { Label("Sortieren", systemImage: "line.3.horizontal.decrease.circle") }
                    Button { importing = true } label: { Label("MIDI importieren", systemImage: "plus") }
                        .help("MIDI-Dateien oder Ordner importieren")
                }
            }
            .dropDestination(for: URL.self) { urls, _ in importAndSelect(urls) }
        } detail: {
            detail
                .dropDestination(for: URL.self) { urls, _ in importAndSelect(urls) }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType.midi, UTType.folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { _ = importAndSelect(urls) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMIDIFiles)) { note in
            if let urls = note.object as? [URL] { _ = importAndSelect(urls) }
        }
        .alert("Song umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titel", text: $newTitle)
            Button("Speichern") { if let r = renaming { library.rename(r, to: newTitle) }; renaming = nil }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .freePlay?: FreePlayView()
        case .exercises?: ExerciseView()
        case .reading?: ReadingTrainerView()
        case .ear?: EarTrainerView()
        case .song(let id)?:
            if let entry = library.songs.first(where: { $0.id == id }) {
                PlayerContainer(entry: entry).id(id)
            } else {
                DashboardView { selection = $0 }
            }
        default:
            DashboardView { selection = $0 }
        }
    }

    private func importAndSelect(_ urls: [URL]) -> Bool {
        let added = library.importFiles(urls)
        if let f = added.first { selection = .song(f.id) }
        return !added.isEmpty
    }
}

struct SongRow: View {
    let entry: SongEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if entry.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption2) }
                Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
            }
            HStack(spacing: 7) {
                if let d = entry.difficulty {
                    Text(String(repeating: "●", count: min(5, max(0, d))) + String(repeating: "○", count: max(0, 5 - d)))
                        .font(.system(size: 8))
                        .foregroundStyle(d <= 2 ? .green : d == 3 ? .yellow : .orange)
                }
                if let st = entry.bestStars, st > 0 {
                    Text(String(repeating: "★", count: st)).foregroundStyle(Color.gold)
                }
                if let a = entry.bestAccuracy { Text("\(Int(a * 100)) %") }
                Text(entry.mastery.label)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(masteryColor.opacity(0.25)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var masteryColor: Color {
        switch entry.mastery.level {
        case 4: return .gold
        case 3: return .green
        case 2: return .blue
        case 1: return .orange
        default: return .gray
        }
    }
}

// MARK: - Player

enum SongTab: String, CaseIterable, Identifiable {
    case lesson = "Lektion"
    case practice = "Freies Üben"
    case analysis = "Analyse"
    var id: String { rawValue }
}

struct PlayerContainer: View {
    let entry: SongEntry
    @EnvironmentObject var library: LibraryStore
    @State private var song: MidiSong?
    @State private var analysis: SongAnalysis?
    @State private var error: String?
    @State private var tab: SongTab = SongTab(rawValue: Prefs.string("songTab", "Lektion")) ?? .lesson
    @State private var arrangement: Arrangement = .original
    @AppStorage("simpleMode") private var simple = true

    var body: some View {
        Group {
            if let song, let analysis, simple {
                LessonView(entry: entry, song: song, analysis: analysis)
            } else if let song, let analysis {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Picker("Ansicht", selection: $tab) {
                            ForEach(SongTab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 330)
                        if tab == .practice {
                            Picker("Fassung", selection: $arrangement) {
                                ForEach(Arrangement.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .frame(width: 290)
                        }
                        Button("Einfach-Modus") { simple = true }.buttonStyle(.bordered)
                        Spacer()
                        Text("\(analysis.keyName) · \(song.timeSignature) · Form \(analysis.formString)")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.09))
                    switch tab {
                    case .lesson:
                        LessonView(entry: entry, song: song, analysis: analysis)
                    case .practice:
                        PlayerView(title: entry.title,
                                   song: SongAnalyzer.arrangement(arrangement, song: song, analysis: analysis),
                                   entryID: entry.id, analysis: analysis)
                            .id(arrangement)
                    case .analysis:
                        AnalysisView(title: entry.title, song: song, analysis: analysis)
                    }
                }
                .onChange(of: tab) { _, t in Prefs.set("songTab", t.rawValue) }
            } else if let error {
                ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .task(id: entry.id) {
            do {
                let s = try MidiSong.load(url: library.url(for: entry))
                analysis = SongAnalyzer.analyze(s)
                song = s
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PlayerView: View {
    let title: String
    let entryID: UUID?
    let preset: PracticePreset?
    let onResult: ((SessionResult) -> Void)?
    @StateObject private var engine: PracticeEngine
    @EnvironmentObject var library: LibraryStore
    @State private var monitor: Any?

    init(title: String, song: MidiSong, entryID: UUID?, preset: PracticePreset? = nil,
         analysis: SongAnalysis? = nil, onResult: ((SessionResult) -> Void)? = nil) {
        self.title = title
        self.entryID = entryID
        self.preset = preset
        self.onResult = onResult
        _engine = StateObject(wrappedValue: PracticeEngine(song: song,
                                                           audio: AppServices.shared.audio,
                                                           midi: AppServices.shared.midi,
                                                           analysis: analysis))
    }

    var body: some View {
        VStack(spacing: 0) {
            ControlBar(engine: engine, saveRecording: saveRecording)
            ProgressBar(engine: engine)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            StatsHUD(engine: engine)
                .padding(.bottom, 6)
            PianoStage(engine: engine)
                .overlay(alignment: .top) { BannerOverlay(engine: engine).padding(.top, 12) }
                .overlay { CountdownOverlay(engine: engine) }
        }
        .background(Color(white: 0.05))
        .navigationTitle(title)
        .navigationSubtitle("\(engine.song.timeSignature) · \(Int(engine.song.bpm.rounded())) BPM · \(formatTime(engine.song.duration)) · \(engine.song.notes.count) Noten · Schwierigkeit \(engine.song.difficulty)/5")
        .onAppear {
            engine.attach()
            if let p = preset { engine.apply(p) }
            let id = entryID
            let t = title
            let cb = onResult
            engine.onFinished = { [weak e = engine, weak lib = library] r in
                lib?.record(songID: id, title: t, result: r, seconds: e?.takePracticeSeconds() ?? 0, mode: r.mode)
                cb?(r)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak e = engine] ev in
                guard let e else { return ev }
                if ev.window?.firstResponder is NSText { return ev }
                return e.handleKey(ev) ? nil : ev
            }
        }
        .onDisappear {
            engine.detach()
            library.record(songID: entryID, title: title, result: nil, seconds: engine.takePracticeSeconds(), mode: engine.mode)
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }
        .sheet(isPresented: $engine.finished) {
            ResultView(engine: engine,
                       best: entryID.flatMap { id in library.songs.first(where: { $0.id == id })?.bestAccuracy },
                       saveRecording: saveRecording)
        }
    }

    private func saveRecording() {
        let notes = engine.recordedNotes()
        let df = DateFormatter()
        df.dateFormat = "dd.MM. HH:mm"
        library.addSong(title: "🎙 \(title) – \(df.string(from: Date()))", notes: notes)
    }
}

// MARK: - Steuerleiste

struct ControlBar: View {
    @ObservedObject var engine: PracticeEngine
    let saveRecording: () -> Void
    @State private var showSection = false
    @State private var showMixer = false
    @AppStorage("micEnabled") private var micEnabled = false
    @AppStorage("simpleMode") private var simple = true

    var body: some View {
        if simple { simpleBar } else { fullBar }
    }

    /// Einfach-Modus: nur das Nötigste
    private var simpleBar: some View {
        HStack(spacing: 14) {
            Button { engine.togglePlay() } label: {
                Label(engine.isPlaying ? "Pause" : "Start", systemImage: engine.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 80)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Button { engine.restart() } label: { Label("Nochmal", systemImage: "arrow.counterclockwise") }
                .controlSize(.large)

            Picker("Hand", selection: $engine.handSelection) {
                ForEach(HandSelection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            .controlSize(.large)
            .disabled(engine.mode == .listen)

            HStack(spacing: 6) {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                Slider(value: $engine.tempo, in: 0.3...1.2, step: 0.1).frame(width: 140)
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
                Text("\(Int((engine.tempo * 100).rounded())) %").monospacedDigit().frame(width: 44)
            }

            Spacer()
            InputStatus(sources: engine.midiSources, octave: engine.keyOctave, mic: micEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fullBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { engine.togglePlay() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").frame(width: 22)
                }
                .controlSize(.large)
                .help("Play/Pause (Leertaste)")
                Button { engine.restart() } label: { Image(systemName: "backward.end.fill") }
                    .help("Von vorn (R)")
                Button { engine.toggleRecording() } label: {
                    Image(systemName: engine.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(engine.isRecording ? .red : .primary)
                }
                .help("Eigenes Spiel aufnehmen (N)")
                if !engine.isRecording && engine.hasRecording {
                    Button { saveRecording() } label: { Image(systemName: "square.and.arrow.down") }
                        .help("Aufnahme als Song in der Bibliothek speichern")
                }

                Picker("Modus", selection: $engine.mode) {
                    ForEach(PracticeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 360)
                .help("Anhören · Warte-Modus (stoppt bis zur richtigen Taste) · Durchspielen (mit Timing-Wertung) · Rhythmus (nur Timing zählt)")

                Picker("Hand", selection: $engine.handSelection) {
                    ForEach(HandSelection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                .disabled(engine.mode == .listen)

                HStack(spacing: 5) {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                    Slider(value: $engine.tempo, in: 0.25...1.5, step: 0.05).frame(width: 100)
                    Text("\(Int((engine.tempo * 100).rounded())) %").monospacedDigit().frame(width: 42, alignment: .leading)
                }
                .help("Tempo (↑/↓)")

                Toggle(isOn: $engine.autoTempo) { Image(systemName: "chart.line.uptrend.xyaxis") }
                    .toggleStyle(.button).help("Tempo-Trainer: nach sauberem Loop +5 %")
                Toggle(isOn: $engine.countIn) { Image(systemName: "timer") }
                    .toggleStyle(.button).help("Einzähler vor dem Start")
                Toggle(isOn: $engine.metronome) { Image(systemName: "metronome.fill") }
                    .toggleStyle(.button).help("Metronom (M)")

                Spacer(minLength: 6)
                InputStatus(sources: engine.midiSources, octave: engine.keyOctave, mic: micEnabled)
            }

            HStack(spacing: 10) {
                Picker("Ansicht", selection: $engine.viewMode) {
                    ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)

                Picker("Beschriftung", selection: $engine.labelMode) {
                    ForEach(LabelMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 150)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line").foregroundStyle(.secondary)
                    Slider(value: $engine.visibleSeconds, in: 1.5...7).frame(width: 80)
                }
                .help("Fallgeschwindigkeit / Zoom")

                Button { showSection = true } label: { Label("Abschnitte", systemImage: "repeat") }
                    .popover(isPresented: $showSection) { SectionPopover(engine: engine) }
                HStack(spacing: 2) {
                    Button("A") { engine.setLoopA() }.help("Loop-Start")
                    Button("B") { engine.setLoopB() }.help("Loop-Ende")
                    if engine.loopStart != nil || engine.loopEnd != nil {
                        Button { engine.clearLoop() } label: { Image(systemName: "xmark.circle.fill") }
                    }
                }

                Stepper(value: $engine.transpose, in: -12...12) {
                    Text("Transp. \(engine.transpose > 0 ? "+" : "")\(engine.transpose)").monospacedDigit()
                }
                .fixedSize()

                Menu {
                    Picker("Hände zuordnen", selection: $engine.handAssign) {
                        ForEach(HandAssign.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if engine.handAssign == .split {
                        Picker("Split-Punkt", selection: $engine.splitPitch) {
                            ForEach(Array(stride(from: 48, through: 72, by: 1)), id: \.self) { p in
                                Text(NoteNames.name(p)).tag(p)
                            }
                        }
                    }
                    Toggle("Hände tauschen", isOn: $engine.swapHands)
                    Toggle("Andere Hand ausblenden", isOn: $engine.hideOtherHand)
                } label: { Label("Hände", systemImage: "hand.raised") }
                .fixedSize()

                Menu {
                    Picker("Klang", selection: Binding(get: { engine.sound }, set: { engine.setSound($0) })) {
                        ForEach(PianoSound.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Klaviatur", selection: $engine.keyboardSize) {
                        ForEach(KeyboardSize.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Akkordnamen anzeigen", isOn: $engine.showChords)
                    Toggle("Konzert-Modus (keine Hilfen)", isOn: $engine.concertMode)
                    Toggle("Eigene Tasten über Mac hörbar", isOn: $engine.playOwnNotes)
                    Toggle("Fernbedienung über tiefste Tasten (A0/H0/C1)", isOn: $engine.midiRemote)
                    Divider()
                    Toggle("Mikrofon-Erkennung (akustisches Klavier, einstimmig)", isOn: $micEnabled)
                } label: { Label("Mehr", systemImage: "slider.horizontal.3") }
                .fixedSize()

                Button { showMixer = true } label: { Image(systemName: "dial.medium") }
                    .help("Mixer")
                    .popover(isPresented: $showMixer) { MixerPopover(engine: engine) }

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onChange(of: micEnabled) { _, on in MicSwitch.apply(on) }
    }
}

enum MicSwitch {
    static func apply(_ on: Bool) {
        let mic = AppServices.shared.mic
        if on {
            if !mic.running {
                mic.start { ok in if !ok { UserDefaults.standard.set(false, forKey: "micEnabled") } }
            }
        } else {
            mic.stop()
        }
    }
}

struct InputStatus: View {
    let sources: [String]
    let octave: Int
    let mic: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(sources.isEmpty && !mic ? Color.orange : Color.green).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .help("MIDI-Keyboard per USB/Bluetooth wird automatisch erkannt. Ohne Keyboard: Mac-Tastatur A W S E D F T G Z H U J K, Oktave X / C.")
    }
    private var text: String {
        var parts: [String] = []
        if !sources.isEmpty { parts.append(sources.joined(separator: ", ")) }
        if mic { parts.append("🎤 Mikrofon") }
        if parts.isEmpty { parts.append("Mac-Tastatur (Oktave \(octave))") }
        return parts.joined(separator: " · ")
    }
}

struct MixerPopover: View {
    @ObservedObject var engine: PracticeEngine
    @AppStorage("latencyMs") private var latency = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mixer").font(.headline)
            slider("Begleitung", value: Binding(get: { engine.accompVolume }, set: { engine.accompVolume = $0 }))
            slider("Deine Tasten", value: Binding(get: { engine.ownVolume }, set: { engine.ownVolume = $0 }))
            slider("Metronom", value: Binding(get: { engine.clickVolume }, set: { engine.clickVolume = $0 }))
            Divider()
            VStack(alignment: .leading) {
                Text("Latenz-Ausgleich: \(Int(latency)) ms").font(.caption)
                Slider(value: $latency, in: 0...200, step: 5)
                Text("Wenn dir „zu spät“ angezeigt wird, obwohl du im Takt bist: hochdrehen.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }
    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 95, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }
}

struct SectionPopover: View {
    @ObservedObject var engine: PracticeEngine
    @State private var from = 1
    @State private var to = 4

    private struct Chunk: Identifiable {
        let id: Int
        let a: Int
        let b: Int
        let errors: Int
    }

    private var bars: Int { max(engine.song.barTimes.count, 1) }
    private var chunks: [Chunk] {
        stride(from: 0, to: bars, by: 4).map { a in
            let b = min(a + 3, bars - 1)
            let e = (a...b).reduce(0) { $0 + ($1 < engine.errorsPerBar.count ? engine.errorsPerBar[$1] : 0) }
            return Chunk(id: a, a: a, b: b, errors: e)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Abschnitte üben").font(.headline)
            HStack {
                Stepper("Takt \(from)", value: $from, in: 1...bars)
                Stepper("bis \(max(to, from))", value: Binding(get: { max(to, from) }, set: { to = $0 }), in: from...max(from, bars))
            }
            Button("Takt \(from)–\(max(to, from)) loopen") { engine.loopBars(from - 1, max(to, from) - 1) }
                .buttonStyle(.borderedProminent)
            Divider()
            Text("Phrasen (4 Takte) – rot = Fehler").font(.subheadline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 6) {
                    ForEach(chunks) { c in
                        Button {
                            engine.loopBars(c.a, c.b)
                        } label: {
                            VStack(spacing: 1) {
                                Text("T. \(c.a + 1)–\(c.b + 1)").font(.caption.bold())
                                Text(c.errors > 0 ? "\(c.errors) Fehler" : "–").font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .tint(c.errors >= 3 ? .red : c.errors > 0 ? .orange : .gray)
                    }
                }
            }
            .frame(maxHeight: 180)
            Divider()
            HStack {
                Button { engine.loopHardestSection() } label: { Label("Problemstelle (B)", systemImage: "target") }
                    .disabled(engine.hardestBar == nil)
                Spacer()
                Button("Loop entfernen") { engine.clearLoop() }
            }
            Toggle("Tempo-Trainer (+5 % nach sauberem Durchgang)", isOn: $engine.autoTempo)
                .font(.caption)
        }
        .padding()
        .frame(width: 340)
        .onAppear {
            let b = max(1, engine.currentBar)
            from = min(b, bars)
            to = min(b + 3, bars)
        }
    }
}

// MARK: - Fortschritt, HUD, Einzähler

struct ProgressBar: View {
    @ObservedObject var engine: PracticeEngine

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            HStack(spacing: 10) {
                Text(formatTime(engine.currentTime)).monospacedDigit().font(.caption)
                GeometryReader { geo in
                    let w = geo.size.width
                    let d = max(engine.song.duration, 0.1)
                    let maxErr = max(engine.errorsPerBar.max() ?? 0, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                        ForEach(Array(engine.errorsPerBar.enumerated()), id: \.offset) { k, e in
                            if e > 0, k < engine.song.barTimes.count {
                                Rectangle()
                                    .fill(Color.missRed.opacity(0.3 + 0.7 * Double(e) / Double(maxErr)))
                                    .frame(width: max(2, w / CGFloat(max(engine.song.barTimes.count, 1)) - 1), height: 14)
                                    .offset(x: CGFloat(engine.song.barTimes[k] / d) * w)
                            }
                        }
                        if let a = engine.loopStart {
                            let b = engine.loopEnd ?? d
                            Rectangle()
                                .fill(Color.yellow.opacity(0.35))
                                .frame(width: max(2, CGFloat((b - a) / d) * w), height: 12)
                                .offset(x: CGFloat(a / d) * w)
                        }
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(0, CGFloat(min(1, max(0, engine.currentTime) / d)) * w), height: 6)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        guard w > 0, d > 0 else { return }
                        engine.seek(to: Double(max(0, min(1, v.location.x / w))) * d)
                    })
                }
                .frame(height: 18)
                Text("Takt \(max(1, engine.currentBar))/\(max(engine.song.barTimes.count, 1))")
                    .monospacedDigit().font(.caption).frame(width: 82, alignment: .trailing)
                Text(formatTime(engine.song.duration)).monospacedDigit().font(.caption)
            }
        }
    }
}

struct StatsHUD: View {
    @ObservedObject var engine: PracticeEngine
    @AppStorage("simpleMode") private var simple = true

    var body: some View {
        if simple { simpleHUD } else { fullHUD }
    }

    private var simpleHUD: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { _ in
            HStack(spacing: 20) {
                if engine.waiting && !engine.waitingNames.isEmpty {
                    Label("Spiel jetzt: " + engine.waitingNames.joined(separator: " + "), systemImage: "hand.point.down.fill")
                        .font(.title3.bold()).foregroundStyle(.yellow)
                } else if !engine.isPlaying && !engine.finished {
                    Label("Drück Start oder die Leertaste", systemImage: "play.circle").foregroundStyle(.secondary)
                } else if let h = engine.currentHarmony, h.rootPC != nil {
                    Text("Akkord: \(h.chord)").font(.headline)
                }
                if engine.mode != .listen, let a = engine.accuracy {
                    Text("\(Int(a * 100)) % richtig").font(.headline).foregroundStyle(a >= 0.85 ? Color.hitGreen : .orange)
                }
            }
            .frame(height: 34)
        }
    }

    private var fullHUD: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { _ in
            VStack(spacing: 6) {
                HStack(spacing: 16) {
                    if engine.mode != .listen && !engine.concertMode {
                        stat("Punkte", "\(engine.score)", .gold)
                        stat("Combo", "×\(engine.combo)", engine.combo >= 10 ? .gold : .white)
                        stat("Treffer", "\(engine.hits)/\(engine.userNoteCount)", .hitGreen)
                        if engine.mode.continuous { stat("Verpasst", "\(engine.misses)", .missRed) }
                        stat("Falsch", "\(engine.wrongCount)", .orange)
                        stat("Genauigkeit", engine.accuracy.map { "\(Int($0 * 100)) %" } ?? "–", .white)
                    }
                    if engine.showChords, let h = engine.currentHarmony, h.rootPC != nil, !engine.concertMode {
                        VStack(spacing: 1) {
                            HStack(spacing: 5) {
                                Text(h.chord).font(.system(.headline, design: .rounded))
                                Text(h.roman).font(.system(.subheadline, design: .serif).bold()).foregroundStyle(.yellow)
                            }
                            Text(h.function).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if engine.showChords, !engine.pressed.isEmpty, let played = engine.playedChordName {
                        stat("Du greifst", played, .white)
                    }
                    if let dyn = engine.dynamicsLabel, !engine.pressed.isEmpty {
                        stat("Dynamik", dyn, .purple)
                    }
                    if engine.waiting && !engine.waitingNames.isEmpty {
                        Label("Spiel: " + engine.waitingNames.joined(separator: " + "), systemImage: "hand.point.down.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                    }
                    if !engine.isPlaying && !engine.finished {
                        Label("Leertaste = Start", systemImage: "play.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if engine.isRecording {
                        Label("REC", systemImage: "record.circle.fill").font(.caption.bold()).foregroundStyle(.red)
                    }
                }
                .frame(height: 40)
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(.headline, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct BannerOverlay: View {
    @ObservedObject var engine: PracticeEngine
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            if let b = engine.banner, CACurrentMediaTime() - b.time < 2.5 {
                Text(b.text)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.9)))
            }
        }
    }
}

struct CountdownOverlay: View {
    @ObservedObject var engine: PracticeEngine
    var body: some View {
        if let c = engine.countdown {
            Text("\(c)")
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 12)
                .transition(.scale)
                .id(c)
        }
    }
}

// MARK: - Ergebnis

struct ResultView: View {
    @ObservedObject var engine: PracticeEngine
    let best: Double?
    let saveRecording: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shownStars = 0
    @State private var saved = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Song geschafft").font(.title.bold())
            if let r = engine.lastResult, let a = r.accuracy {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { k in
                        Image(systemName: k < shownStars ? "star.fill" : "star")
                            .font(.system(size: 38))
                            .foregroundStyle(k < shownStars ? Color.gold : .gray)
                            .scaleEffect(k < shownStars ? 1.0 : 0.8)
                    }
                }
                Text("\(Int(a * 100)) %")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(a >= 0.9 ? Color.hitGreen : a >= 0.7 ? .yellow : .orange)
                Text(verdict(a)).foregroundStyle(.secondary)
                Grid(horizontalSpacing: 26, verticalSpacing: 8) {
                    GridRow {
                        cell("\(r.score)", "Punkte")
                        cell("×\(r.maxCombo)", "Beste Combo")
                        cell("\(Int((r.tempo * 100).rounded())) %", "Tempo")
                    }
                    GridRow {
                        cell("\(engine.hits)", "Treffer")
                        cell("\(engine.misses)", "Verpasst")
                        cell("\(engine.wrongCount)", "Falsch")
                    }
                    GridRow {
                        cell(r.rightAcc.map { "\(Int($0 * 100)) %" } ?? "–", "Rechte Hand")
                        cell(r.leftAcc.map { "\(Int($0 * 100)) %" } ?? "–", "Linke Hand")
                        cell(r.avgOffsetMs.map { String(format: "%+.0f ms", $0) } ?? "–", "Ø Timing")
                    }
                }
                if let off = r.avgOffsetMs {
                    Text(timingTip(off, early: r.early, late: r.late)).font(.callout).multilineTextAlignment(.center)
                }
                if let best { Text("Bisheriger Bestwert: \(Int(best * 100)) %").font(.caption).foregroundStyle(.secondary) }
                if a >= 0.9 && r.tempo < 1.0 {
                    Text("Nächster Schritt: Tempo auf \(Int(min(1.0, r.tempo + 0.1) * 100)) %.").font(.callout)
                }
            } else {
                Text("Durchgehört. Jetzt selbst spielen?").foregroundStyle(.secondary)
            }
            HStack {
                Button("Fertig") { dismiss() }
                if engine.hardestBar != nil {
                    Button("Problemstelle üben") {
                        dismiss()
                        engine.loopHardestSection()
                        engine.togglePlay()
                    }
                }
                if engine.hasRecording {
                    Button(saved ? "Gespeichert ✓" : "Aufnahme speichern") { saveRecording(); saved = true }
                        .disabled(saved)
                }
                Button("Nochmal") {
                    dismiss()
                    engine.restart()
                    engine.togglePlay()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(minWidth: 460)
        .onAppear {
            let target = engine.lastResult?.stars ?? 0
            for k in 0..<target {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(k + 1)) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { shownStars = k + 1 }
                    AppServices.shared.audio.preview(UInt8(72 + [0, 4, 7][k]), duration: 0.4, velocity: 80)
                }
            }
        }
    }

    private func cell(_ v: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold()).monospacedDigit()
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func verdict(_ a: Double) -> String {
        switch a {
        case 0.97...: return "Makellos. Nächstes Level."
        case 0.9..<0.97: return "Stark – fast sauber."
        case 0.7..<0.9: return "Solide. Problemstelle loopen, dann nochmal."
        default: return "Tempo runter, Warte-Modus, dann wieder hoch."
        }
    }

    private func timingTip(_ off: Double, early: Int, late: Int) -> String {
        if abs(off) < 25 { return "Timing sitzt: im Schnitt nur \(Int(abs(off))) ms daneben." }
        return off < 0
            ? "Du eilst: \(early)× zu früh. Metronom an und bewusst warten."
            : "Du schleppst: \(late)× zu spät. Vorausschauen – Blick eine Note weiter."
    }
}
