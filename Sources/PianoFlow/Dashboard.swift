import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var library: LibraryStore
    let select: (NavItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Dein Klavier-Cockpit").font(.largeTitle.bold())

                HStack(spacing: 14) {
                    card {
                        HStack(spacing: 14) {
                            GoalRing(progress: library.todayMinutes / Double(max(library.dailyGoal, 1)))
                                .frame(width: 64, height: 64)
                            VStack(alignment: .leading) {
                                Text("Heute").font(.caption).foregroundStyle(.secondary)
                                Text("\(Int(library.todayMinutes)) / \(library.dailyGoal) min").font(.title2.bold())
                            }
                        }
                    }
                    card {
                        VStack(alignment: .leading) {
                            Text("Streak").font(.caption).foregroundStyle(.secondary)
                            Text("🔥 \(library.streak) Tage").font(.title2.bold())
                            Text("Rekord: \(library.bestStreak)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    card {
                        let lv = library.level
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Level \(lv.level)").font(.title2.bold())
                            ProgressView(value: lv.progress).tint(.gold)
                            Text("\(library.xp) / \(lv.nextXP) XP").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    card {
                        VStack(alignment: .leading) {
                            Text("Gesamt geübt").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.1f h", library.totalPracticeSeconds / 3600)).font(.title2.bold())
                            Text("\(library.songs.count) Songs · \(library.sessions.count) Einheiten").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    card {
                        VStack(alignment: .leading) {
                            Text("Übungsminuten (14 Tage)").font(.headline)
                            Chart(library.minutesPerDay(14)) { d in
                                BarMark(x: .value("Tag", d.day, unit: .day), y: .value("Minuten", d.minutes))
                                    .foregroundStyle(d.minutes >= Double(library.dailyGoal) ? Color.hitGreen : Color.rightHand)
                                RuleMark(y: .value("Ziel", library.dailyGoal))
                                    .foregroundStyle(.yellow.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            }
                            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) } }
                            .frame(height: 170)
                        }
                    }
                    card {
                        VStack(alignment: .leading) {
                            Text("Genauigkeit (letzte 30 Durchgänge)").font(.headline)
                            let pts = Array(library.sessions.filter { $0.accuracy != nil }.suffix(30).enumerated())
                            if pts.isEmpty {
                                Text("Noch keine gewerteten Durchgänge.").foregroundStyle(.secondary).frame(height: 170)
                            } else {
                                Chart(pts, id: \.offset) { k, s in
                                    LineMark(x: .value("Nr", k + 1), y: .value("%", (s.accuracy ?? 0) * 100))
                                        .interpolationMethod(.catmullRom)
                                    PointMark(x: .value("Nr", k + 1), y: .value("%", (s.accuracy ?? 0) * 100))
                                }
                                .chartYScale(domain: 0...100)
                                .frame(height: 170)
                            }
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aktivität (12 Wochen)").font(.headline)
                        ActivityGrid(values: library.minutesPerDay(84).map(\.minutes), goal: Double(library.dailyGoal))
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Weiter geht's").font(.headline)
                            if let s = library.continueSuggestion {
                                Button { select(.song(s.id)) } label: {
                                    Label("\(s.title) – \(s.mastery.label)", systemImage: "play.circle.fill")
                                }
                            } else {
                                Text("Importiere einen Song oder starte mit einer Übung.").foregroundStyle(.secondary)
                            }
                            Button { select(.exercises) } label: { Label("Aufwärmen: Tonleitern & Hanon", systemImage: "flame") }
                            Button { select(.reading) } label: { Label("5 Minuten Notenlesen", systemImage: "eye") }
                            Button { select(.ear) } label: { Label("Gehörtraining", systemImage: "ear") }
                            if !library.refreshSuggestions.isEmpty {
                                Divider()
                                Text("Auffrischen (länger nicht gespielt)").font(.subheadline.bold())
                                ForEach(library.refreshSuggestions.prefix(4)) { s in
                                    Button { select(.song(s.id)) } label: {
                                        Label("\(s.title) · \(daysAgo(s.lastPlayed))", systemImage: "arrow.counterclockwise")
                                    }
                                }
                            }
                        }
                        .buttonStyle(.link)
                    }
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Letzte Einheiten").font(.headline)
                            if library.sessions.isEmpty { Text("Noch nichts geübt – los geht's.").foregroundStyle(.secondary) }
                            ForEach(library.sessions.suffix(8).reversed()) { s in
                                HStack {
                                    Text(s.title).lineLimit(1)
                                    Spacer()
                                    if let a = s.accuracy { Text("\(Int(a * 100)) %").foregroundStyle(.secondary) }
                                    Text("\(max(1, Int(s.seconds / 60))) min").foregroundStyle(.secondary).monospacedDigit()
                                }
                                .font(.callout)
                            }
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Erfolge").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 10) {
                            ForEach(library.achievements) { a in
                                HStack(spacing: 10) {
                                    Image(systemName: a.icon)
                                        .font(.title2)
                                        .foregroundStyle(a.unlocked ? Color.gold : .gray)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(a.title).font(.callout.bold())
                                        Text(a.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .opacity(a.unlocked ? 1 : 0.45)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Übersicht")
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    private func daysAgo(_ d: Date?) -> String {
        guard let d else { return "nie" }
        let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
        return "vor \(days) Tagen"
    }
}

struct GoalRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, progress))
                .stroke(progress >= 1 ? Color.hitGreen : Color.rightHand, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress >= 1 ? "✓" : "\(Int(min(1, progress) * 100))%").font(.caption.bold())
        }
    }
}

struct ActivityGrid: View {
    let values: [Double]
    let goal: Double
    var body: some View {
        let weeks = values.count / 7
        HStack(spacing: 4) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let v = values[w * 7 + d]
                        RoundedRectangle(cornerRadius: 3)
                            .fill(v <= 0 ? Color.white.opacity(0.06) : Color.hitGreen.opacity(0.25 + 0.75 * min(1, v / max(goal, 1))))
                            .frame(width: 14, height: 14)
                            .help("\(Int(v)) min")
                    }
                }
            }
        }
    }
}

// MARK: - Einstellungen

struct SettingsView: View {
    @AppStorage("dailyGoal") private var dailyGoal = 15
    @AppStorage("simpleMode") private var simpleMode = true
    @AppStorage("obsidianLog") private var obsidianLog = true
    @AppStorage("latencyMs") private var latency = 0.0
    @AppStorage("micEnabled") private var micEnabled = false

    var body: some View {
        Form {
            Section("Oberfläche") {
                Toggle("Einfach-Modus (nur das Nötigste)", isOn: $simpleMode)
            }
            Section("Ziele") {
                Stepper("Tagesziel: \(dailyGoal) Minuten", value: $dailyGoal, in: 5...180, step: 5)
            }
            Section("Second Brain") {
                Toggle("Übungslog in Obsidian schreiben", isOn: $obsidianLog)
                Text("Notiz: Second Brain › Hobbys › PianoFlow – Übungslog").font(.caption).foregroundStyle(.secondary)
            }
            Section("Eingabe") {
                Toggle("Mikrofon-Erkennung (akustisches Klavier, einstimmig)", isOn: $micEnabled)
                    .onChange(of: micEnabled) { _, on in MicSwitch.apply(on) }
                VStack(alignment: .leading) {
                    Text("Latenz-Ausgleich: \(Int(latency)) ms")
                    Slider(value: $latency, in: 0...200, step: 5)
                }
            }
            Section("Tastenkürzel") {
                Text("Leertaste Play/Pause · R von vorn · ←/→ 5 s · ↑/↓ Tempo · M Metronom · B Problemstelle · N Aufnahme · X/C Oktave der Mac-Tastatur")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
    }
}

// MARK: - Menüleiste

struct MenuBarContent: View {
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        Text("Heute: \(Int(library.todayMinutes)) von \(library.dailyGoal) min")
        Text("Streak: \(library.streak) Tage · Level \(library.level.level)")
        Divider()
        Button("PianoFlow öffnen") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        Button("Beenden") { NSApp.terminate(nil) }
    }
}
