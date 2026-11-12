import SwiftUI

// MARK: - Musiktheorie zum Anfassen: Intervalle, Tonleitern, Akkorde, Quintenzirkel

enum TheoryTab: String, CaseIterable, Identifiable {
    case intervals = "Intervalle", scales = "Tonleitern", chords = "Akkorde", circle = "Quintenzirkel"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .intervals: return "arrow.up.and.down"
        case .scales: return "stairs"
        case .chords: return "square.stack.3d.up"
        case .circle: return "circle.dashed"
        }
    }
}

struct TheoryItem: Identifiable, Hashable {
    let id: String
    let steps: [Int]          // Halbtöne über dem Grundton
    let info: String
    var together = false      // Akkord: zusammen anschlagen
}

enum TheoryContent {
    static let roots = ["C", "Des", "D", "Es", "E", "F", "Fis", "G", "As", "A", "B", "H"]
    static let fifths = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5]

    static let intervals: [TheoryItem] = [
        .init(id: "Prime", steps: [0, 0], info: "Zweimal derselbe Ton – 0 Halbtöne."),
        .init(id: "Kleine Sekunde", steps: [0, 1], info: "1 Halbton – klingt spannend, wie die Musik aus „Der weiße Hai“."),
        .init(id: "Große Sekunde", steps: [0, 2], info: "2 Halbtöne – der Anfang von „Alle meine Entchen“ (C–D)."),
        .init(id: "Kleine Terz", steps: [0, 3], info: "3 Halbtöne – klingt traurig, Grundbaustein von Moll. Wie der Kuckucksruf (abwärts)."),
        .init(id: "Große Terz", steps: [0, 4], info: "4 Halbtöne – klingt fröhlich, Grundbaustein von Dur. „Oh When the Saints“."),
        .init(id: "Quarte", steps: [0, 5], info: "5 Halbtöne – „O Tannenbaum“ fängt so an."),
        .init(id: "Tritonus", steps: [0, 6], info: "6 Halbtöne – genau die halbe Oktave, klingt schräg. „Maria“ aus West Side Story."),
        .init(id: "Quinte", steps: [0, 7], info: "7 Halbtöne – stabil und offen. „Morgen kommt der Weihnachtsmann“ (C–G)."),
        .init(id: "Kleine Sexte", steps: [0, 8], info: "8 Halbtöne – sehnsüchtig, wie die „Love Story“-Melodie."),
        .init(id: "Große Sexte", steps: [0, 9], info: "9 Halbtöne – „My Bonnie Is Over the Ocean“."),
        .init(id: "Kleine Septime", steps: [0, 10], info: "10 Halbtöne – die Star-Trek-Melodie (Originalserie) beginnt so."),
        .init(id: "Große Septime", steps: [0, 11], info: "11 Halbtöne – ganz knapp unter der Oktave, will sich auflösen."),
        .init(id: "Oktave", steps: [0, 12], info: "12 Halbtöne – derselbe Ton, eine Etage höher. „Somewhere Over the Rainbow“."),
    ]

    static let scales: [TheoryItem] = [
        .init(id: "Dur", steps: [0, 2, 4, 5, 7, 9, 11, 12], info: "Fröhlich. Muster: Ganz – Ganz – Halb – Ganz – Ganz – Ganz – Halb. Auf C nur weiße Tasten."),
        .init(id: "Moll (natürlich)", steps: [0, 2, 3, 5, 7, 8, 10, 12], info: "Traurig/ernst. Muster: Ganz – Halb – Ganz – Ganz – Halb – Ganz – Ganz. Auf A nur weiße Tasten."),
        .init(id: "Moll (harmonisch)", steps: [0, 2, 3, 5, 7, 8, 11, 12], info: "Wie natürliches Moll, aber der 7. Ton ist erhöht – das gibt den orientalischen Sprung."),
        .init(id: "Moll (melodisch)", steps: [0, 2, 3, 5, 7, 9, 11, 12], info: "Aufwärts werden 6. und 7. Ton erhöht – klingt geschmeidig."),
        .init(id: "Dur-Pentatonik", steps: [0, 2, 4, 7, 9, 12], info: "Nur 5 Töne, klingt immer schön. Auf Fis sind das genau die schwarzen Tasten."),
        .init(id: "Moll-Pentatonik", steps: [0, 3, 5, 7, 10, 12], info: "Die Lieblingsskala für Rock und Blues-Soli."),
        .init(id: "Blues", steps: [0, 3, 5, 6, 7, 10, 12], info: "Moll-Pentatonik plus „Blue Note“ (verminderte Quinte)."),
        .init(id: "Chromatisch", steps: Array(0...12), info: "Alle 12 Töne nacheinander, jeder Schritt ein Halbton."),
    ]

    static let chords: [TheoryItem] = [
        .init(id: "Dur", steps: [0, 4, 7], info: "Grundton + große Terz + Quinte. Klingt hell und fröhlich.", together: true),
        .init(id: "Moll", steps: [0, 3, 7], info: "Grundton + kleine Terz + Quinte. Klingt weich und traurig.", together: true),
        .init(id: "Vermindert", steps: [0, 3, 6], info: "Zwei kleine Terzen übereinander – gespannt, unruhig.", together: true),
        .init(id: "Übermäßig", steps: [0, 4, 8], info: "Zwei große Terzen – schwebend, wie im Traum.", together: true),
        .init(id: "Sus4", steps: [0, 5, 7], info: "Statt der Terz die Quarte – offen, will zurück nach Dur.", together: true),
        .init(id: "Dominantseptakkord (7)", steps: [0, 4, 7, 10], info: "Dur + kleine Septime. Der Akkord, der nach Hause (zur Tonika) zieht.", together: true),
        .init(id: "Major 7 (maj7)", steps: [0, 4, 7, 11], info: "Dur + große Septime – jazzig und weich.", together: true),
        .init(id: "Moll 7 (m7)", steps: [0, 3, 7, 10], info: "Moll + kleine Septime – entspannt, typisch für Pop und Jazz.", together: true),
    ]

    /// Dreiklänge auf jeder Stufe der Dur-Tonleiter
    static let degrees: [(roman: String, offset: Int, quality: [Int], name: String)] = [
        ("I", 0, [0, 4, 7], "Tonika – Zuhause"),
        ("ii", 2, [0, 3, 7], "Subdominant-Parallele"),
        ("iii", 4, [0, 3, 7], "Dominant-Parallele"),
        ("IV", 5, [0, 4, 7], "Subdominante – weg von Zuhause"),
        ("V", 7, [0, 4, 7], "Dominante – Spannung, will zur I"),
        ("vi", 9, [0, 3, 7], "Tonika-Parallele (Moll)"),
        ("vii°", 11, [0, 3, 6], "Vermindert – sehr gespannt"),
    ]
}

struct TheoryView: View {
    @AppStorage("theoryTab") private var tab: TheoryTab = .intervals
    @State private var root = 0
    @State private var selected: TheoryItem = TheoryContent.intervals[4]
    @State private var lit: Set<Int> = []         // gerade klingende Tasten
    @State private var inversion = 0
    @State private var extraTitle: String?
    @State private var extraPitches: [Int]?

    private var audio: AudioEngine { AppServices.shared.audio }
    private var fifths: Int { TheoryContent.fifths[root] }

    private var items: [TheoryItem] {
        switch tab {
        case .intervals: return TheoryContent.intervals
        case .scales: return TheoryContent.scales
        case .chords: return TheoryContent.chords
        case .circle: return []
        }
    }

    /// Tonhöhen des aktuellen Elements (ab C4 + Grundton)
    private var pitches: [Int] {
        if let e = extraPitches { return e }
        var ps = selected.steps.map { 60 + root + $0 }
        if tab == .chords && inversion > 0 {
            for _ in 0..<min(inversion, ps.count - 1) { ps.append(ps.removeFirst() + 12) }
        }
        return ps
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("", selection: $tab) {
                    ForEach(TheoryTab.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 520)
                Spacer()
                Text("Grundton").font(.callout).foregroundStyle(.secondary)
                rootPicker
            }
            .padding(14)
            Divider()
            if tab == .circle {
                circleOfFifths
            } else {
                HStack(alignment: .top, spacing: 0) {
                    list.frame(width: 300)
                    Divider()
                    detail
                }
            }
        }
        .navigationTitle("Musiktheorie")
        .onChange(of: tab) { _, t in
            extraPitches = nil
            if t != .circle, let first = items.first(where: { $0.id == (t == .chords ? "Dur" : t == .scales ? "Dur" : "Große Terz") }) {
                selected = first
            }
        }
    }

    private var rootPicker: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { r in
                Button {
                    root = r
                    extraPitches = nil
                    play()
                } label: {
                    Text(TheoryContent.roots[r])
                        .font(.callout.weight(root == r ? .bold : .regular))
                        .frame(width: 34, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(root == r ? Color.accentColor : (KeyLayout.isBlack(r) ? Color.black.opacity(0.5) : Color.white.opacity(0.08))))
                        .foregroundStyle(root == r ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var list: some View {
        List(items, selection: Binding(get: { selected.id }, set: { id in
            if let it = items.first(where: { $0.id == id }) { selected = it; extraPitches = nil; inversion = 0; play() }
        })) { it in
            HStack {
                Text(it.id).font(.body.weight(.medium))
                Spacer()
                if tab == .intervals { Text("\(it.steps[1]) HT").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .tag(it.id)
            .padding(.vertical, 3)
        }
    }

    private func name(_ p: Int) -> String {
        let s = Score.spell(p, fifths: fifths)
        return Score.germanName(diatonic: s.diatonic, alter: s.alter)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(extraTitle ?? "\(TheoryContent.roots[root])-\(selected.id)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(extraPitches == nil ? selected.info : "")
                    .font(.title3).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Klaviatur mit markierten Tönen
                TheoryKeyboard(pitches: pitches, lit: lit, name: name)
                    .frame(height: 150)

                // Notennamen als große Kärtchen, mit Halb-/Ganzton-Schritten dazwischen
                HStack(spacing: 6) {
                    ForEach(Array(pitches.enumerated()), id: \.offset) { k, p in
                        if k > 0, tab == .scales {
                            let d = p - pitches[k - 1]
                            Text(d == 1 ? "½" : d == 2 ? "1" : "\(d)")
                                .font(.caption.bold())
                                .foregroundStyle(d == 1 ? .orange : .secondary)
                        }
                        Text(name(p))
                            .font(.title3.bold())
                            .frame(minWidth: 44, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 8).fill(lit.contains(p) ? Color.accentColor : Color.white.opacity(0.08)))
                    }
                }
                if tab == .scales { Text("1 = Ganztonschritt, ½ = Halbtonschritt").font(.caption).foregroundStyle(.secondary) }

                HStack(spacing: 10) {
                    Button { play() } label: {
                        Label(tab == .chords && extraPitches == nil ? "Nacheinander" : "Anhören", systemImage: "play.fill").frame(minWidth: 120, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    if tab != .scales {
                        Button { playTogether() } label: { Label("Zusammen", systemImage: "square.stack.3d.up.fill").frame(minWidth: 110, minHeight: 30) }
                            .buttonStyle(.bordered)
                    }
                    if tab == .chords && extraPitches == nil {
                        Picker("Umkehrung", selection: $inversion) {
                            Text("Grundstellung").tag(0)
                            Text("1. Umkehrung").tag(1)
                            Text("2. Umkehrung").tag(2)
                            if selected.steps.count > 3 { Text("3. Umkehrung").tag(3) }
                        }
                        .frame(width: 210)
                        .onChange(of: inversion) { _, _ in playTogether() }
                    }
                }

                if tab == .chords { degreesSection }
                if tab == .intervals {
                    Text("Tipp: Spiel das Intervall auf deinem Klavier nach und sing es mit – so merkst du es dir am schnellsten.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private var degreesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Akkorde in \(TheoryContent.roots[root])-Dur (Stufen)").font(.headline)
            Text("Aus den Tönen einer Tonleiter entstehen 7 Dreiklänge. I, IV und V sind die wichtigsten – damit kannst du viele Lieder begleiten.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(TheoryContent.degrees, id: \.roman) { d in
                    let ps = d.quality.map { 60 + root + d.offset + $0 }
                    Button {
                        extraTitle = "Stufe \(d.roman): \(name(ps[0]))\(d.quality == [0, 3, 7] ? "-Moll" : d.quality == [0, 3, 6] ? " vermindert" : "-Dur")"
                        extraPitches = ps
                        playTogether()
                    } label: {
                        VStack(spacing: 2) {
                            Text(d.roman).font(.title3.bold())
                            Text(name(ps[0]) + (d.quality == [0, 4, 7] ? "" : d.quality == [0, 3, 7] ? "m" : "°")).font(.caption)
                        }
                        .frame(width: 62, height: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(["I", "IV", "V"].contains(d.roman) ? .accentColor : .secondary)
                    .help(d.name)
                }
            }
            HStack(spacing: 8) {
                Text("Kadenz anhören:").font(.callout)
                Button("I – IV – V – I") { playProgression([0, 5, 7, 0], qualities: [[0, 4, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7]]) }
                Button("Pop: I – V – vi – IV") { playProgression([0, 7, 9, 5], qualities: [[0, 4, 7], [0, 4, 7], [0, 3, 7], [0, 4, 7]]) }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Quintenzirkel

    private var circleOfFifths: some View {
        HStack(alignment: .top, spacing: 30) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let c = CGPoint(x: geo.size.width / 2, y: size / 2)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1).frame(width: size * 0.86, height: size * 0.86).position(c)
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).frame(width: size * 0.52, height: size * 0.52).position(c)
                    ForEach(0..<12, id: \.self) { k in
                        let pc = (k * 7) % 12
                        let ang = Double(k) / 12 * 2 * .pi - .pi / 2
                        let outer = CGPoint(x: c.x + CGFloat(cos(ang)) * size * 0.43, y: c.y + CGFloat(sin(ang)) * size * 0.43)
                        let inner = CGPoint(x: c.x + CGFloat(cos(ang)) * size * 0.26, y: c.y + CGFloat(sin(ang)) * size * 0.26)
                        let minor = (pc + 9) % 12
                        Button { selectKey(pc) } label: {
                            Text(TheoryContent.roots[pc])
                                .font(.system(size: size * 0.05, weight: .bold, design: .rounded))
                                .frame(width: size * 0.12, height: size * 0.12)
                                .background(Circle().fill(root == pc ? Color.accentColor : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .position(outer)
                        Button { selectKey(minor, minorKey: true) } label: {
                            Text(TheoryContent.roots[minor].lowercased())
                                .font(.system(size: size * 0.035, weight: .semibold, design: .rounded))
                                .frame(width: size * 0.09, height: size * 0.09)
                                .background(Circle().fill(Color.white.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .position(inner)
                    }
                    Text("Dur außen\nmoll innen").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary).position(c)
                }
            }
            .frame(minWidth: 380, maxWidth: 520)

            VStack(alignment: .leading, spacing: 14) {
                Text("\(TheoryContent.roots[root])-Dur").font(.system(size: 30, weight: .bold, design: .rounded))
                let f = fifths
                Text(f == 0 ? "Keine Vorzeichen" : "\(abs(f)) \(f > 0 ? (abs(f) == 1 ? "Kreuz" : "Kreuze") : (abs(f) == 1 ? "B" : "Bs"))")
                    .font(.title2)
                if f != 0 {
                    let order = f > 0 ? ["Fis", "Cis", "Gis", "Dis", "Ais", "Eis"] : ["B", "Es", "As", "Des", "Ges", "Ces"]
                    Text("Vorzeichen: " + order.prefix(abs(f)).joined(separator: ", ")).font(.title3).foregroundStyle(.secondary)
                }
                Text("Paralleles Moll: \(TheoryContent.roots[(root + 9) % 12].lowercased())-Moll (gleiche Vorzeichen)")
                    .foregroundStyle(.secondary)
                TheoryKeyboard(pitches: TheoryContent.scales[0].steps.map { 60 + root + $0 }, lit: lit, name: name)
                    .frame(height: 130)
                Button { selected = TheoryContent.scales[0]; extraPitches = nil; play(TheoryContent.scales[0].steps.map { 60 + root + $0 }) } label: {
                    Label("Tonleiter anhören", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                Text("Merksatz: Im Uhrzeigersinn kommt mit jedem Schritt (eine Quinte höher) ein Kreuz dazu – gegen den Uhrzeigersinn ein B.\nKreuze: „Geh Du Alter Esel Hole Fische“ (G, D, A, E, H, Fis) · Bs: „Frische Brötchen Essen Asse Des Gesangs“")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    private func selectKey(_ pc: Int, minorKey: Bool = false) {
        root = minorKey ? (pc + 3) % 12 : pc
        let base = minorKey ? TheoryContent.scales[1].steps.map { 60 + pc + $0 } : TheoryContent.scales[0].steps.map { 60 + pc + $0 }
        play(base)
    }

    // MARK: Klang

    private func play(_ ps: [Int]? = nil) {
        let seq = ps ?? pitches
        let gap = tab == .scales || seq.count > 4 ? 0.28 : 0.45
        for (k, p) in seq.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * gap) {
                audio.preview(UInt8(p), duration: gap * 1.6)
                lit = [p]
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seq.count) * gap + 0.3) { lit = [] }
    }

    private func playTogether() {
        let ps = Array(Set(pitches)).sorted()
        for p in ps { audio.preview(UInt8(p), duration: 1.4) }
        lit = Set(ps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { lit = [] }
    }

    private func playProgression(_ offsets: [Int], qualities: [[Int]]) {
        for (k, o) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.9) {
                let ps = qualities[k].map { 60 + root + o + $0 }.map { $0 > 76 ? $0 - 12 : $0 }
                for p in ps { audio.preview(UInt8(p), duration: 0.85) }
                lit = Set(ps)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(offsets.count) * 0.9) { lit = [] }
    }
}

/// Klaviatur (C4–C6) mit hervorgehobenen Tönen und Namen
struct TheoryKeyboard: View {
    let pitches: [Int]
    let lit: Set<Int>
    let name: (Int) -> String

    var body: some View {
        Canvas { ctx, size in
            let lo = 60, hi = max(84, (pitches.max() ?? 72) + 1)
            let layout = KeyLayout(range: lo...hi, width: size.width)
            let set = Set(pitches)
            KeyboardPainter.draw(ctx, rect: CGRect(origin: .zero, size: size), layout: layout, color: { p in
                if lit.contains(p) { return Color.accentColor }
                if set.contains(p) { return p == pitches.first ? Color.orange.opacity(0.85) : Color.rightHand.opacity(0.7) }
                return nil
            }, label: { p in set.contains(p) ? name(p) : (p % 12 == 0 ? "C\(p / 12 - 1)" : nil) })
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Klaviatur: " + pitches.map(name).joined(separator: ", "))
    }
}
