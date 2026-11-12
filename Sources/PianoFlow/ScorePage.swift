import SwiftUI
import AppKit

// MARK: - Seitenlayout: ganzes Notenblatt in Zeilen

struct PageRow: Identifiable {
    let id: Int
    let bars: [Int]                  // Indizes in Score.bars
    let barX: [CGFloat]              // Startposition je Takt
    let barW: [CGFloat]
    let columns: [[(tick: Int, x: CGFloat)]]   // je Takt: Spalten (Tick → x des Notenkopfs)
    let headerW: CGFloat
    let showTime: Bool

    func x(forTick tk: Int, in k: Int) -> CGFloat {
        let cols = columns[k]
        guard let first = cols.first else { return barX[k] + barW[k] / 2 }
        if tk <= first.tick { return first.x }
        for j in 1..<cols.count where cols[j].tick >= tk {
            let a = cols[j - 1], b = cols[j]
            let f = CGFloat(tk - a.tick) / CGFloat(max(1, b.tick - a.tick))
            return a.x + f * (b.x - a.x)
        }
        return cols.last!.x
    }

    func barSlot(_ bar: Int) -> Int? { bars.firstIndex(of: bar) }
}

final class PageLayoutCache {
    private var key = ""
    private var rows: [PageRow] = []

    func rows(score: Score, version: Int, width: CGFloat, ls: CGFloat, margin: CGFloat) -> [PageRow] {
        let k = "\(version)|\(Int(width))|\(ls)"
        if k == key { return rows }
        key = k
        rows = Self.layout(score: score, width: width, ls: ls, margin: margin)
        return rows
    }

    static func layout(score: Score, width: CGFloat, ls: CGFloat, margin: CGFloat) -> [PageRow] {
        // Natürliche Breite und Spalten jedes Takts
        var natural: [CGFloat] = []
        var colRel: [[(tick: Int, x: CGFloat)]] = []
        let lead = ls * 1.6
        for (bp, bar) in score.bars.enumerated() {
            var ticks = Set<Int>()
            var accAt = Set<Int>()
            for i in score.itemsByBar[bp] {
                let it = score.items[i]
                if it.wholeBarRest { continue }
                ticks.insert(it.tick)
                if it.accidental.contains(where: { $0 != nil }) { accAt.insert(it.tick) }
            }
            if ticks.isEmpty { ticks.insert(bar.startTick) }
            let sorted = ticks.sorted()
            var x = lead
            var cols: [(Int, CGFloat)] = []
            for (j, tk) in sorted.enumerated() {
                if accAt.contains(tk) { x += ls * 1.1 }
                cols.append((tk, x))
                let next = j + 1 < sorted.count ? sorted[j + 1] : bar.endTick
                let d = Double(max(1, next - tk))
                x += ls * CGFloat(1.9 + 1.15 * log2(1 + d))
            }
            natural.append(max(ls * 7, x + ls * 0.4))
            colRel.append(cols)
        }

        var rows: [PageRow] = []
        var bp = 0
        while bp < score.bars.count {
            let first = rows.isEmpty
            let headerW = NotationPainter.headerWidth(ls: ls, fifths: score.fifths, showTime: first)
            let avail = max(ls * 10, width - margin * 2 - headerW)
            var sum: CGFloat = 0
            var bars: [Int] = []
            while bp < score.bars.count, bars.isEmpty || sum + natural[bp] <= avail {
                sum += natural[bp]
                bars.append(bp)
                bp += 1
            }
            let last = bp >= score.bars.count
            var scale = avail / max(sum, 1)
            if last { scale = min(scale, 1.3) }
            var x = margin + headerW
            var barX: [CGFloat] = [], barW: [CGFloat] = [], cols: [[(tick: Int, x: CGFloat)]] = []
            for b in bars {
                let w = natural[b] * scale
                barX.append(x)
                barW.append(w)
                cols.append(colRel[b].map { (tick: $0.tick, x: x + $0.x * scale) })
                x += w
            }
            rows.append(PageRow(id: rows.count, bars: bars, barX: barX, barW: barW, columns: cols,
                                headerW: headerW, showTime: first))
        }
        return rows
    }
}

// MARK: - Ganzes Notenblatt

struct ScorePageView: View {
    @ObservedObject var engine: PracticeEngine
    @AppStorage("pageZoom") private var zoom: Double = 11
    @AppStorage("pageFollow") private var follow = true
    @State private var cache = PageLayoutCache()
    @State private var pinchBase: Double?
    @State private var lastRow = -1
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private static let minZoom = 4.0, maxZoom = 18.0

    var body: some View {
        GeometryReader { geo in
            let ls = CGFloat(zoom)
            let margin = ls * 2.8
            let score = engine.notation
            let rows = cache.rows(score: score, version: engine.scoreVersion, width: geo.size.width, ls: ls, margin: margin)
            let rowH = GrandStaff.height(ls: ls) + ls * 1.5

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        Text(engine.song.title)
                            .font(.system(size: max(16, ls * 2), weight: .bold, design: .serif))
                            .foregroundStyle(PianoStage.sheetInk)
                            .padding(.top, 14)
                        ForEach(rows) { row in
                            PageRowView(engine: engine, row: row, ls: ls)
                                .frame(height: rowH)
                                .id(row.id)
                        }
                        Color.clear.frame(height: 70)
                    }
                }
                .background(PianoStage.paper)
                .onReceive(ticker) { _ in
                    guard follow else { return }
                    let tk = score.tick(for: max(0, engine.currentTime))
                    let bp = score.barPosition(ofTick: tk)
                    guard let r = rows.firstIndex(where: { $0.bars.contains(bp) }), r != lastRow else { return }
                    lastRow = r
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(r, anchor: UnitPoint(x: 0.5, y: 0.25)) }
                }
                .onChange(of: zoom) { _, _ in lastRow = -1 }
            }
            .overlay(alignment: .bottom) { controls.padding(.bottom, 12) }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { v in
                    if pinchBase == nil { pinchBase = zoom }
                    zoom = min(Self.maxZoom, max(Self.minZoom, (pinchBase ?? zoom) * v.magnification))
                }
                .onEnded { _ in pinchBase = nil }
        )
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { setZoom(zoom - 1.5) } label: {
                Image(systemName: "minus.magnifyingglass").font(.title3).frame(width: 38, height: 34)
            }
            .help("Verkleinern – mehr vom Blatt sehen (⌘ −)")
            .keyboardShortcut("-", modifiers: .command)

            Slider(value: $zoom, in: Self.minZoom...Self.maxZoom).frame(width: 120)

            Button { setZoom(zoom + 1.5) } label: {
                Image(systemName: "plus.magnifyingglass").font(.title3).frame(width: 38, height: 34)
            }
            .help("Vergrößern (⌘ +)")
            .keyboardShortcut("+", modifiers: .command)

            Divider().frame(height: 26)

            Toggle(isOn: $follow) { Label("Mitlaufen", systemImage: "arrow.down.forward.circle") }
                .toggleStyle(.button)
                .help("Blatt scrollt automatisch zur aktuellen Stelle")

            Button {
                engine.viewMode = engine.lastPlayView == .page ? .both : engine.lastPlayView
            } label: {
                Label("Zur Spielansicht", systemImage: "rectangle.split.2x1")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 6)
                    .frame(height: 34)
            }
            .buttonStyle(.borderedProminent)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.94)).shadow(radius: 6))
        .overlay(alignment: .top) {
            Text("Tipp: Takt anklicken = üben · über mehrere Takte ziehen = Bereich · ⇧-Klick = erweitern")
                .font(.caption.weight(.medium))
                .foregroundStyle(PianoStage.sheetInk.opacity(0.6))
                .fixedSize()
                .offset(y: -24)
        }
    }

    private func setZoom(_ z: Double) {
        withAnimation(.easeInOut(duration: 0.15)) { zoom = min(Self.maxZoom, max(Self.minZoom, z)) }
    }
}

// MARK: - Eine Zeile (System) des Notenblatts

struct PageRowView: View {
    @ObservedObject var engine: PracticeEngine
    let row: PageRow
    let ls: CGFloat
    @State private var dragStart: Int?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.isPlaying)) { tl in
            Canvas { ctx, size in
                _ = tl.date
                draw(ctx, size: size)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard let cur = songBar(at: v.location.x) else { return }
                    if dragStart == nil {
                        dragStart = songBar(at: v.startLocation.x)
                        if NSEvent.modifierFlags.contains(.shift), let s = engine.loopBarStart { dragStart = s }
                    }
                    if let s = dragStart, v.translation.width.magnitude > 4 || NSEvent.modifierFlags.contains(.shift) {
                        let lo = min(s, cur), hi = max(s, cur)
                        if engine.loopBarStart != lo || engine.loopBarEnd != hi { engine.loopBars(lo, hi) }
                    }
                }
                .onEnded { v in
                    defer { dragStart = nil }
                    guard let s = dragStart ?? songBar(at: v.startLocation.x) else { return }
                    let e = songBar(at: v.location.x) ?? s
                    let lo = min(s, e), hi = max(s, e)
                    if engine.isPlaying { engine.togglePlay() }
                    engine.loopBars(lo, hi)
                    engine.showBanner(lo == hi ? "Takt \(lo + 1) ausgewählt – Start drücken" : "Takte \(lo + 1)–\(hi + 1) ausgewählt")
                }
        )
    }

    private func songBar(at x: CGFloat) -> Int? {
        let score = engine.notation
        for (k, bp) in row.bars.enumerated() where x >= row.barX[k] - 2 && x <= row.barX[k] + row.barW[k] + 2 {
            return max(0, score.bars[bp].index)
        }
        if x < (row.barX.first ?? 0), let bp = row.bars.first { return max(0, score.bars[bp].index) }
        if let bp = row.bars.last { return max(0, score.bars[bp].index) }
        return nil
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let score = engine.notation
        let listen = engine.mode == .listen
        let ink = PianoStage.sheetInk
        let g = GrandStaff(ls: ls, trebleTop: ls * 5.2)
        let painter = NotationPainter(g: g, ink: ink)
        let x0 = (row.barX.first ?? ls * 6) - row.headerW
        let xEnd = (row.barX.last ?? 0) + (row.barW.last ?? 0)
        let staffTop = g.trebleTop - ls * 1.2, staffBot = g.bassBottom + ls * 1.2

        // Takt-Hintergründe: Loop (orange), aktueller Takt (blau)
        let tk = score.tick(for: max(0, engine.currentTime))
        let curBar = score.barPosition(ofTick: tk)
        for (k, bp) in row.bars.enumerated() {
            let idx = score.bars[bp].index
            let r = CGRect(x: row.barX[k], y: staffTop, width: row.barW[k], height: staffBot - staffTop)
            if let a = engine.loopBarStart, idx >= a, idx <= (engine.loopBarEnd ?? a) {
                ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(Color.orange.opacity(0.16)))
            }
            if bp == curBar && engine.currentTime >= 0 {
                ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(Color.accentColor.opacity(0.10)))
            }
        }

        painter.staffLines(ctx, from: x0, to: xEnd)
        painter.systemStart(ctx, x: x0)
        painter.clefsAndSignature(ctx, x: x0, fifths: score.fifths, num: score.num, den: score.den, showTime: row.showTime)

        for (k, bp) in row.bars.enumerated() {
            let bar = score.bars[bp]
            painter.barline(ctx, x: row.barX[k] + row.barW[k], final: bp == score.bars.count - 1)
            if bar.index >= 0 {
                ctx.draw(Text("\(bar.index + 1)").font(.system(size: max(9, ls * 0.95), weight: .semibold, design: .rounded))
                            .foregroundColor(ink.opacity(0.45)),
                         at: CGPoint(x: row.barX[k] + ls * 0.5, y: g.trebleTop - ls * 1.6), anchor: .leading)
            }
        }

        // Akkordnamen über dem System
        if engine.showChords && !engine.concertMode, let firstBar = row.bars.first, let lastBar = row.bars.last {
            let t0 = score.time(for: score.bars[firstBar].startTick), t1 = score.time(for: score.bars[lastBar].endTick)
            var lastChord = ""
            var lastX: CGFloat = -1000
            for seg in engine.analysis.segments where seg.start >= t0 - 0.01 && seg.start < t1 && seg.rootPC != nil {
                guard seg.chord != lastChord else { continue }
                lastChord = seg.chord
                let st = score.tick(for: seg.start)
                let bp = score.barPosition(ofTick: st)
                guard let k = row.barSlot(bp) else { continue }
                let xx = max(row.x(forTick: st, in: k) - ls * 0.5, lastX + ls * 3)
                lastX = xx
                ctx.draw(Text(seg.chord).font(.system(size: max(10, ls * 1.15), weight: .semibold, design: .serif))
                            .foregroundColor(engine.kidNotes ? Color(red: 0.75, green: 0.38, blue: 0.08) : ink.opacity(0.85)),
                         at: CGPoint(x: xx, y: ls * 1.1), anchor: .leading)
            }
        }

        // Dynamik
        for (k, bp) in row.bars.enumerated() {
            if let m = score.dynamics[bp] { painter.dynamic(ctx, m, x: row.barX[k] + ls * 0.4) }
        }

        // Noten
        var idx: [Int] = []
        for bp in row.bars { idx.append(contentsOf: score.itemsByBar[bp]) }
        if engine.hideOtherHand && !listen {
            let shown = engine.handSelection.hands
            idx = idx.filter { shown.contains(score.items[$0].hand) }
        }
        painter.drawItems(ctx, score: score, indices: idx,
                          x: { i in
                              let it = score.items[i]
                              guard let k = row.barSlot(it.bar) else { return 0 }
                              return row.x(forTick: it.tick, in: k)
                          },
                          barCenter: { bp in
                              guard let k = row.barSlot(bp) else { return 0 }
                              return row.barX[k] + row.barW[k] / 2
                          },
                          style: PianoStage.sheetStyle(engine, listen: listen))

        // Abspielposition
        if engine.currentTime >= 0, let k = row.barSlot(curBar) {
            let bar = score.bars[curBar]
            let exact = score.tick(for: engine.currentTime)
            let xp: CGFloat
            if exact >= bar.endTick { xp = row.barX[k] + row.barW[k] - 2 } else { xp = row.x(forTick: exact, in: k) }
            ctx.fill(Path(roundedRect: CGRect(x: xp - 1.5, y: staffTop - ls * 0.6, width: 3, height: staffBot - staffTop + ls * 1.2),
                          cornerRadius: 1.5),
                     with: .color(Color.accentColor.opacity(0.8)))
        }
    }
}

// MARK: - Debug-Render (Kommandozeile)

enum NotationRenderTool {
    @MainActor
    static func render(song: MidiSong, out: URL, zoom: Double) {
        let engine = PracticeEngine(song: song, audio: AppServices.shared.audio, midi: AppServices.shared.midi)
        engine.labelMode = LabelMode(rawValue: ProcessInfo.processInfo.environment["PF_LABEL"] ?? "") ?? .fingers
        engine.kidNotes = ProcessInfo.processInfo.environment["PF_KID"] != nil
        if ProcessInfo.processInfo.environment["PF_DUMP"] != nil {
            let sc = engine.notation
            for bp in 0..<min(3, sc.bars.count) {
                print("Takt", sc.bars[bp].index, sc.bars[bp].startTick, sc.bars[bp].endTick)
                for i in sc.itemsByBar[bp] {
                    let it = sc.items[i]
                    print("  ", it.kind, it.hand, "tick", it.tick, "dur", it.dur, it.pitches, it.tieToNext ? "tie" : "")
                }
            }
        }
        if let tab = ProcessInfo.processInfo.environment["PF_THEORY"], let t = TheoryTab(rawValue: tab) {
            UserDefaults.standard.set(t.rawValue, forKey: "theoryTab")
            let r = ImageRenderer(content: TheoryView().frame(width: 1100, height: 720).background(Color(white: 0.12)).preferredColorScheme(.dark))
            r.scale = 1.2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: out); print("OK theory") }
            return
        }
        if let v = ProcessInfo.processInfo.environment["PF_VIEW"], let mode = ViewMode(rawValue: v) {
            engine.viewMode = mode
            engine.loopBars(4, 5)
            engine.seek(to: (engine.song.barTimes.count > 5 ? engine.song.barTimes[5] : 1) + 0.2)
            let stage = PianoStage(engine: engine).frame(width: 1240, height: 720).background(Color.black)
            let r = ImageRenderer(content: stage)
            r.scale = 1.5
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: out); print("OK stage") }
            return
        }
        let width: CGFloat = 1240
        let ls = CGFloat(zoom)
        let rows = PageLayoutCache.layout(score: engine.notation, width: width, ls: ls, margin: ls * 2.8)
        let rowH = GrandStaff.height(ls: ls) + ls * 1.5
        let view = VStack(spacing: 0) {
            ForEach(rows.dropFirst(Int(ProcessInfo.processInfo.environment["PF_FROMROW"] ?? "0") ?? 0).prefix(6)) { row in
                PageRowView(engine: engine, row: row, ls: ls).frame(width: width, height: rowH)
            }
        }
        .background(PianoStage.paper)
        let r = ImageRenderer(content: view)
        r.scale = 1.5
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: out)
            print("OK \(rows.count) Zeilen, \(engine.notation.bars.count) Takte, Vorzeichen \(engine.notation.fifths)")
        } else { print("Render fehlgeschlagen") }
    }
}
