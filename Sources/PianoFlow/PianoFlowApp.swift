import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .openMIDIFiles, object: urls)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppServices.shared
        if Prefs.bool("micEnabled", false) { MicSwitch.apply(true) }
    }
}

@main
struct PianoFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var library = LibraryStore()

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--parse"), i + 1 < args.count {
            do {
                let s = try MidiSong.load(url: URL(fileURLWithPath: args[i + 1]))
                let right = s.notes.filter { $0.hand == .right }.count
                let fingers = s.fingers.prefix(12).map(String.init).joined(separator: " ")
                var bad = 0, groups = 0
                var k = 0
                while k < s.notes.count {
                    var j = k + 1
                    while j < s.notes.count, s.notes[j].start - s.notes[k].start < 0.035 { j += 1 }
                    for h in [Hand.left, .right] {
                        let ps = s.notes[k..<j].filter { $0.hand == h }.map { Int($0.pitch) }
                        if let a = ps.min(), let b = ps.max(), b - a > 14 { bad += 1 }
                    }
                    groups += 1
                    k = j
                }
                print("Haende: \(bad) unspielbare Griffe in \(groups) Anschlaegen, Score \(String(format: "%.2f", s.difficultyScore))")
                print("OK \(s.title): \(s.notes.count) Noten (R \(right) / L \(s.notes.count - right)), \(String(format: "%.1f", s.duration)) s, \(s.timeSignature), \(Int(s.bpm)) BPM, \(s.barTimes.count) Takte, Schwierigkeit \(s.difficulty), Pedal \(s.pedalSpans.count), Finger: \(fingers)")
                exit(0)
            } catch {
                print("FEHLER: \(error.localizedDescription)")
                exit(1)
            }
        }
        if let i = args.firstIndex(of: "--analyze"), i + 1 < args.count {
            if let s = try? MidiSong.load(url: URL(fileURLWithPath: args[i + 1])) {
                let a = SongAnalyzer.analyze(s)
                print(a.summary(song: s, title: s.title))
                print("LH pro Takt: \(a.lhPatternPerBar.joined(separator: " | "))")
                print("Rollen: \(a.roles.prefix(20).joined(separator: " "))")
                for arr in Arrangement.allCases {
                    print("Fassung \(arr.rawValue): \(SongAnalyzer.arrangement(arr, song: s, analysis: a).notes.count) Noten")
                }
                print("Lernschritte: \(LessonPlan.steps(song: s, a: a).map(\.title).joined(separator: " → "))")
            }
            exit(0)
        }
        // Debug: Notenblatt als PNG rendern  --render <midi> <out.png> [zoom]
        // Übung rendern: --render-exercise <Nr> <out.png>
        if let i = args.firstIndex(of: "--render-exercise"), i + 2 < args.count, let k = Int(args[i + 1]),
           k < ExerciseKind.allCases.count {
            let kind = ExerciseKind.allCases[k]
            let s = ExerciseFactory.make(ExerciseConfig(kind: kind, root: 0, octaves: 1, hands: .both, bpm: 90))
            print(kind.rawValue)
            NotationRenderTool.render(song: s, out: URL(fileURLWithPath: args[i + 2]), zoom: 9)
            exit(0)
        }
        if let i = args.firstIndex(of: "--render"), i + 2 < args.count {
            if let s = try? MidiSong.load(url: URL(fileURLWithPath: args[i + 1])) {
                NotationRenderTool.render(song: s, out: URL(fileURLWithPath: args[i + 2]),
                                          zoom: i + 3 < args.count ? Double(args[i + 3]) ?? 9 : 9)
            }
            exit(0)
        }
        // Test: Katalog-Download in eine Bibliothek (PF_LIBRARY_DIR setzen!) und Persistenz prüfen
        if let i = args.firstIndex(of: "--catalog-test"), i + 1 < args.count, let k = Int(args[i + 1]) {
            MainActor.assumeIsolated {
                let lib = LibraryStore()
                let store = CatalogStore()
                guard k < store.songs.count else { print("Katalog leer"); exit(1) }
                let s = store.songs[k]
                var done = false
                Task { @MainActor in
                    let id = await store.download(s, into: lib)
                    print("Download \(s.title): \(id.map { "ok \($0)" } ?? "FEHLER \(store.failed[s.midi] ?? "")")")
                    done = true
                }
                while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                print("Im Speicher:", lib.songs.map(\.title))
                print("Von Platte:", LibraryStore().songs.map(\.title))
            }
            exit(0)
        }
        if args.contains("--selftest") {
            for kind in ExerciseKind.allCases {
                let s = ExerciseFactory.make(ExerciseConfig(kind: kind, root: 2, octaves: 2, hands: .both, bpm: 90))
                print("Übung \(kind.rawValue): \(s.notes.count) Noten, \(s.barTimes.count) Takte")
            }
            print("Akkorde:", ChordNamer.name(for: [60, 64, 67]) ?? "-", ChordNamer.name(for: [57, 60, 64]) ?? "-",
                  ChordNamer.name(for: [55, 59, 62, 65]) ?? "-", ChordNamer.name(for: [64, 67, 72]) ?? "-")
            let data = MidiWriter.data(notes: ExerciseFactory.make(ExerciseConfig()).notes, bpm: 100)
            let url = URL(fileURLWithPath: "/tmp/pf-selftest.mid")
            try? data.write(to: url)
            if let s = try? MidiSong.load(url: url) { print("MIDI-Roundtrip OK: \(s.notes.count) Noten, \(Int(s.bpm)) BPM") }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("PianoFlow") {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 1240, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(library)
        } label: {
            Label("\(Int(library.todayMinutes)) min", systemImage: "pianokeys")
        }
    }
}
