import SwiftUI
import QuartzCore

extension Color {
    static let rightHand = Color(red: 0.30, green: 0.68, blue: 1.0)
    static let leftHand = Color(red: 1.0, green: 0.58, blue: 0.22)
    static let hitGreen = Color(red: 0.25, green: 0.90, blue: 0.45)
    static let missRed = Color(red: 1.0, green: 0.32, blue: 0.32)
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.3)
    static func hand(_ h: Hand) -> Color { h == .right ? .rightHand : .leftHand }
}

struct KeyLayout {
    let low: Int
    let high: Int
    let originX: CGFloat
    let whiteW: CGFloat
    private let whiteIndex: [Int: Int]

    init(range: ClosedRange<Int>, width: CGFloat, originX: CGFloat = 0) {
        // Beginnt der Bereich mit einer schwarzen Taste, die weiße Taste links davon mitnehmen
        let lowWhite = KeyLayout.isBlack(range.lowerBound) ? range.lowerBound - 1 : range.lowerBound
        low = lowWhite
        high = range.upperBound
        self.originX = originX
        var idx: [Int: Int] = [:]
        var c = 0
        for p in lowWhite...range.upperBound where !KeyLayout.isBlack(p) {
            idx[p] = c
            c += 1
        }
        whiteIndex = idx
        whiteW = width / CGFloat(max(c, 1))
    }

    static func isBlack(_ p: Int) -> Bool { [1, 3, 6, 8, 10].contains(((p % 12) + 12) % 12) }

    func frame(_ p: Int) -> (x: CGFloat, w: CGFloat)? {
        guard p >= low, p <= high else { return nil }
        if let i = whiteIndex[p] { return (originX + CGFloat(i) * whiteW, whiteW) }
        guard let prev = whiteIndex[p - 1] else { return nil }
        let bw = whiteW * 0.62
        return (originX + CGFloat(prev + 1) * whiteW - bw / 2, bw)
    }
}

/// Zeichnet eine Klaviatur mit farbigen Tasten
struct KeyboardPainter {
    static func draw(_ ctx: GraphicsContext, rect: CGRect, layout: KeyLayout,
                     color: (Int) -> Color?, label: (Int) -> String?) {
        ctx.fill(Path(rect), with: .color(Color(white: 0.15)))
        for p in layout.low...layout.high where !KeyLayout.isBlack(p) {
            guard let f = layout.frame(p) else { continue }
            let r = CGRect(x: f.x + 0.5, y: rect.minY, width: f.w - 1, height: rect.height - 1)
            let path = Path(roundedRect: r, cornerRadius: 3)
            ctx.fill(path, with: .color(Color(white: 0.96)))
            if let c = color(p) { ctx.fill(path, with: .color(c)) }
            if let l = label(p), f.w > 11 {
                ctx.draw(Text(l).font(.system(size: min(11, f.w * 0.45), weight: .semibold))
                            .foregroundColor(.black.opacity(0.6)),
                         at: CGPoint(x: r.midX, y: r.maxY - 11))
            }
        }
        for p in layout.low...layout.high where KeyLayout.isBlack(p) {
            guard let f = layout.frame(p) else { continue }
            let r = CGRect(x: f.x, y: rect.minY, width: f.w, height: rect.height * 0.62)
            let path = Path(roundedRect: r, cornerRadius: 2.5)
            ctx.fill(path, with: .color(Color(white: 0.1)))
            if let c = color(p) { ctx.fill(path, with: .color(c)) }
            if let l = label(p), f.w > 9 {
                ctx.draw(Text(l).font(.system(size: min(9, f.w * 0.5), weight: .bold)).foregroundColor(.white),
                         at: CGPoint(x: r.midX, y: r.maxY - 9))
            }
        }
    }
}

/// Wasserfall, Notenblatt, Klaviatur, Partikel – 60–120 fps
struct PianoStage: View {
    @ObservedObject var engine: PracticeEngine
    @State private var dragStartBar: Int? = nil
    @State private var pinchBase: Double? = nil

    static func keyboardHeight(_ size: CGSize) -> CGFloat { min(170, max(90, size.height * 0.2)) }

    private func sheetRect(for size: CGSize) -> CGRect? {
        let kbH = min(170, max(90, size.height * 0.2))
        let topH = size.height - kbH
        switch engine.viewMode {
        case .waterfall, .page: return nil
        case .sheet: return CGRect(x: 0, y: 0, width: size.width, height: topH)
        case .both:
            let sheetH = topH < 420 ? topH * 0.58 : min(topH * 0.45, 300)
            return CGRect(x: 0, y: 0, width: size.width, height: sheetH)
        }
    }

    private func barIndex(at x: CGFloat, in rect: CGRect) -> Int? {
        let song = engine.song
        guard !song.barTimes.isEmpty else { return nil }
        let playX = Self.sheetPlayX(engine, rect: rect)
        let secondsRight = engine.visibleSeconds * 1.8
        let pps = (rect.maxX - playX) / CGFloat(secondsRight)
        guard pps > 0 else { return nil }
        let t = engine.currentTime
        let time = t + Double((x - playX) / pps)
        let b = song.barIndex(at: time)
        if b >= 0 && b < song.barTimes.count {
            return b
        }
        return nil
    }

    var body: some View {
        if engine.viewMode == .page {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    ScorePageView(engine: engine)
                    TimelineView(.animation) { tl in
                        Canvas { ctx, cSize in
                            _ = tl.date
                            let layout = KeyLayout(range: engine.keyRange, width: cSize.width)
                            drawKeyboard(ctx, rect: CGRect(origin: .zero, size: cSize), layout: layout, listen: engine.mode == .listen)
                        }
                    }
                    .frame(height: Self.keyboardHeight(geo.size) * 0.8)
                }
            }
        } else {
            stage
        }
    }

    /// Spielansicht: Wasserfall / Laufband-Noten / beides
    private var stage: some View {
        GeometryReader { geo in
            let size = geo.size
            let sRect = sheetRect(for: size)

            ZStack(alignment: .topTrailing) {
                TimelineView(.animation) { tl in
                    Canvas { ctx, cSize in
                        _ = tl.date
                        draw(ctx, size: cSize)
                    }
                }

                // Schwebender Loop-Status & "Ganzer Song"-Button direkt über dem Notenblatt
                if engine.loopBarStart != nil, sRect != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "repeat")
                            .foregroundStyle(Color.orange)
                            .font(.caption.bold())
                        if let s = engine.loopBarStart, let e = engine.loopBarEnd {
                            Text(s == e ? "Takt \(s + 1)" : "Takt \(s + 1)–\(e + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        Button {
                            engine.clearLoop()
                            engine.showBanner("Ganzen Song aktiviert")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Ganzer Song")
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.95)).shadow(radius: 4))
                    .padding(.top, 26)
                    .padding(.trailing, 10)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        guard let sRect, val.startLocation.y <= sRect.maxY else { return }
                        if dragStartBar == nil {
                            dragStartBar = barIndex(at: val.startLocation.x, in: sRect)
                        }
                        if let start = dragStartBar, let curr = barIndex(at: val.location.x, in: sRect) {
                            let lo = min(start, curr)
                            let hi = max(start, curr)
                            if engine.loopBarStart != lo || engine.loopBarEnd != hi {
                                engine.loopBars(lo, hi)
                            }
                        }
                    }
                    .onEnded { val in
                        defer { dragStartBar = nil }
                        guard let sRect, val.startLocation.y <= sRect.maxY else { return }
                        let start = dragStartBar ?? barIndex(at: val.startLocation.x, in: sRect)
                        let end = barIndex(at: val.location.x, in: sRect) ?? start
                        if let s = start, let e = end {
                            let lo = min(s, e)
                            let hi = max(s, e)
                            engine.loopBars(lo, hi)
                            engine.showBanner(lo == hi ? "Takt \(lo + 1) geloopt" : "Takte \(lo + 1)–\(hi + 1) geloopt")
                        }
                    }
            )
            .simultaneousGesture(
                // Zwei Finger zusammen = rauszoomen (mehr Zeit sichtbar); ganz raus = ganzes Notenblatt
                MagnifyGesture()
                    .onChanged { v in
                        if pinchBase == nil { pinchBase = engine.visibleSeconds }
                        engine.visibleSeconds = min(12, max(1.5, (pinchBase ?? 3.5) / Double(v.magnification)))
                    }
                    .onEnded { v in
                        defer { pinchBase = nil }
                        if v.magnification < 0.5 && engine.viewMode != .waterfall {
                            pinchBase.map { engine.visibleSeconds = $0 }
                            engine.viewMode = .page
                            engine.showBanner("Ganzes Notenblatt")
                        }
                    }
            )
        }
    }

    private func noteLabel(_ i: Int) -> String? {
        let n = engine.song.notes[i]
        switch engine.labelMode {
        case .none: return nil
        case .names: return NoteNames.name(Int(n.pitch), octave: false)
        case .solfege: return NoteNames.solfege(Int(n.pitch))
        case .fingers:
            let f = i < engine.song.fingers.count ? engine.song.fingers[i] : 0
            return f > 0 ? "\(f)" : nil
        case .harmony:
            return i < engine.analysis.roles.count ? engine.analysis.roles[i] : nil
        }
    }

    private func noteColor(_ i: Int, listen: Bool) -> Color {
        let n = engine.song.notes[i]
        let base = Color.hand(n.hand)
        if listen { return base }
        if engine.isUserNote[i] {
            switch engine.noteStates[i] {
            case .hit: return .hitGreen
            case .missed: return .missRed.opacity(0.55)
            case .pending: return base
            }
        }
        return base.opacity(0.28)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let listen = engine.mode == .listen
        let kbH = min(170, max(90, size.height * 0.2))
        let topH = size.height - kbH
        let layout = KeyLayout(range: engine.keyRange, width: size.width)

        switch engine.viewMode {
        case .waterfall, .page:
            drawWaterfall(ctx, rect: CGRect(x: 0, y: 0, width: size.width, height: topH), layout: layout, listen: listen)
        case .sheet:
            drawSheet(ctx, rect: CGRect(x: 0, y: 0, width: size.width, height: topH), listen: listen)
        case .both:
            let sheetH = topH < 420 ? topH * 0.58 : min(topH * 0.45, 300)
            drawSheet(ctx, rect: CGRect(x: 0, y: 0, width: size.width, height: sheetH), listen: listen)
            drawWaterfall(ctx, rect: CGRect(x: 0, y: sheetH, width: size.width, height: topH - sheetH),
                          layout: layout, listen: listen)
        }

        drawKeyboard(ctx, rect: CGRect(x: 0, y: topH, width: size.width, height: kbH), layout: layout, listen: listen)
        drawEffects(ctx, hitY: topH, layout: layout)
    }

    // MARK: Wasserfall

    private func drawWaterfall(_ ctx: GraphicsContext, rect: CGRect, layout: KeyLayout, listen: Bool) {
        let song = engine.song
        let t = engine.currentTime
        let visible = engine.visibleSeconds
        let pps = rect.height / visible
        let bottom = rect.maxY
        func y(_ time: Double) -> CGFloat { bottom - CGFloat(time - t) * pps }

        ctx.fill(Path(rect), with: .color(Color(white: 0.07)))
        var c = ctx
        c.clip(to: Path(rect))

        for p in layout.low...layout.high {
            guard let f = layout.frame(p) else { continue }
            if p % 12 == 0 || p % 12 == 5 {
                c.fill(Path(CGRect(x: f.x, y: rect.minY, width: 1, height: rect.height)),
                       with: .color(.white.opacity(p % 12 == 0 ? 0.09 : 0.04)))
            }
        }

        // Takt- und Zählzeitlinien mit Taktnummern
        var k = song.pulseTimes.lowerBound(t)
        while k < song.pulseTimes.count, song.pulseTimes[k] <= t + visible {
            let yy = y(song.pulseTimes[k])
            let isBar = song.isBarPulse(k)
            c.fill(Path(CGRect(x: 0, y: yy, width: rect.width, height: isBar ? 1.5 : 0.5)),
                   with: .color(.white.opacity(isBar ? 0.17 : 0.05)))
            if isBar {
                c.draw(Text("\((k - song.pulseOffset) / max(song.pulsesPerBar, 1) + 1)").font(.caption2.monospacedDigit())
                        .foregroundColor(.white.opacity(0.35)),
                       at: CGPoint(x: rect.maxX - 14, y: yy - 8))
            }
            k += 1
        }

        // Akkordsymbole + Stufen am Beginn jeder Harmonie
        if engine.showChords && !engine.concertMode {
            for seg in engine.analysis.segments where seg.start >= t - 0.05 && seg.start <= t + visible && seg.rootPC != nil {
                let yy = y(seg.start)
                let label = Text("\(seg.chord)  ").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    + Text(seg.roman).font(.system(size: 11, weight: .semibold)).foregroundColor(.yellow)
                c.draw(label, at: CGPoint(x: 14, y: yy - 10), anchor: .leading)
            }
        }

        // Pedal-Spur
        for span in song.pedalSpans where span.upperBound >= t && span.lowerBound <= t + visible {
            let y1 = max(y(span.upperBound), rect.minY)
            let y2 = min(y(span.lowerBound), bottom)
            c.fill(Path(roundedRect: CGRect(x: 3, y: y1, width: 5, height: max(2, y2 - y1)), cornerRadius: 2),
                   with: .color(.purple.opacity(0.6)))
        }

        // Loop-Marker
        for (lt, label) in [(engine.loopStart, "A"), (engine.loopEnd, "B")] {
            guard let lt, lt >= t, lt <= t + visible else { continue }
            let yy = y(lt)
            c.fill(Path(CGRect(x: 0, y: yy - 1, width: rect.width, height: 2)), with: .color(.yellow.opacity(0.7)))
            c.draw(Text(label).font(.caption.bold()).foregroundColor(.yellow), at: CGPoint(x: rect.maxX - 34, y: yy - 9))
        }

        // Noten
        if !engine.concertMode {
            let startIdx = song.firstNoteIndex(startingAtOrAfter: t - 12)
            if startIdx < song.notes.count {
                for i in startIdx..<song.notes.count {
                    let n = song.notes[i]
                    if n.start > t + visible { break }
                    if n.end < t { continue }
                    if engine.hideOtherHand && !listen && !engine.isUserNote[i] { continue }
                    guard let f = layout.frame(Int(n.pitch)) else { continue }
                    let yTop = max(y(n.end), rect.minY - 10)
                    let yBot = min(y(n.start), bottom)
                    guard yBot - yTop > 0.5 else { continue }
                    let r = CGRect(x: f.x + 1.5, y: yTop, width: max(f.w - 3, 2), height: max(yBot - yTop, 5))
                    let shape = Path(roundedRect: r, cornerRadius: min(5, f.w / 3))
                    c.fill(shape, with: .color(noteColor(i, listen: listen)))
                    c.stroke(shape, with: .color(.white.opacity(0.18)), lineWidth: 0.8)
                    if let l = noteLabel(i), r.height > 18, f.w > 11 {
                        c.draw(Text(l).font(.system(size: min(11, f.w * 0.55), weight: .bold))
                                .foregroundColor(.black.opacity(0.75)),
                               at: CGPoint(x: r.midX, y: r.maxY - 9))
                    }
                }
            }
        } else {
            c.draw(Text("Konzert-Modus – keine Hilfen").font(.title3.bold()).foregroundColor(.white.opacity(0.25)),
                   at: CGPoint(x: rect.midX, y: rect.midY))
        }

        // Trefferlinie
        c.fill(Path(CGRect(x: 0, y: bottom - 3, width: rect.width, height: 3)),
               with: .linearGradient(Gradient(colors: [.rightHand.opacity(0.8), .white.opacity(0.6), .leftHand.opacity(0.8)]),
                                     startPoint: CGPoint(x: 0, y: bottom), endPoint: CGPoint(x: rect.width, y: bottom)))
    }

    // MARK: Akkord-Visualisierung (Mini-Klaviatur & Stufe)

    private func drawVisualChordBadge(_ ctx: GraphicsContext, seg: HarmonySegment, x: CGFloat, y: CGFloat) {
        let badgeW: CGFloat = 84
        let badgeH: CGFloat = 28
        let r = CGRect(x: x, y: y, width: badgeW, height: badgeH)

        // 1. Hintergrund-Pille mit Akzentrand
        let path = Path(roundedRect: r, cornerRadius: 6)
        ctx.fill(path, with: .color(Color(red: 0.11, green: 0.12, blue: 0.17).opacity(0.95)))
        ctx.stroke(path, with: .color(Color.orange.opacity(0.85)), lineWidth: 1.2)

        // 2. Akkordname & Stufe (links)
        ctx.draw(Text(seg.chord).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white),
                 at: CGPoint(x: x + 6, y: y + 9), anchor: .leading)
        ctx.draw(Text(seg.roman).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color.orange),
                 at: CGPoint(x: x + 6, y: y + 21), anchor: .leading)

        // 3. Mini-Klaviatur Visualisierung der Akkordtöne (rechts)
        let kbOrigin = CGPoint(x: x + badgeW - 38, y: y + 4.5)
        let kbW: CGFloat = 34
        let kbH: CGFloat = 19
        let whiteW = kbW / 7.0
        let whitePitches = [0, 2, 4, 5, 7, 9, 11]

        // Weiße Tasten
        for (i, p) in whitePitches.enumerated() {
            let kr = CGRect(x: kbOrigin.x + CGFloat(i) * whiteW, y: kbOrigin.y, width: whiteW - 0.5, height: kbH)
            let isChordTone = seg.tones.contains(p)
            ctx.fill(Path(roundedRect: kr, cornerRadius: 1.5),
                     with: .color(isChordTone ? Color(red: 1.0, green: 0.55, blue: 0.15) : Color(white: 0.92)))
            ctx.stroke(Path(roundedRect: kr, cornerRadius: 1.5),
                       with: .color(Color(white: 0.3)), lineWidth: 0.5)
        }

        // Schwarze Tasten
        let blackDefs: [(p: Int, offIdx: Int)] = [(1, 0), (3, 1), (6, 3), (8, 4), (10, 5)]
        let bw = whiteW * 0.64
        let bh = kbH * 0.62
        for (p, offIdx) in blackDefs {
            let bx = kbOrigin.x + CGFloat(offIdx + 1) * whiteW - bw / 2
            let br = CGRect(x: bx, y: kbOrigin.y, width: bw, height: bh)
            let isChordTone = seg.tones.contains(p)
            ctx.fill(Path(roundedRect: br, cornerRadius: 1),
                     with: .color(isChordTone ? Color(red: 1.0, green: 0.84, blue: 0.25) : Color(white: 0.2)))
            ctx.stroke(Path(roundedRect: br, cornerRadius: 1),
                       with: .color(Color(white: 0.1)), lineWidth: 0.4)
        }
    }

    // MARK: Notenblatt (Laufband mit echtem Notensatz)

    static let paper = Color(red: 0.995, green: 0.993, blue: 0.985)
    static let sheetInk = Color(white: 0.1)

    /// Farbe einer Note auf dem Papier: schwarz, aktuell = blau, getroffen = grün, verpasst = rot
    static func sheetColor(_ engine: PracticeEngine, _ i: Int, active: Set<Int>, listen: Bool) -> Color {
        let ink = sheetInk
        guard i < engine.noteStates.count else { return ink }
        if active.contains(i) { return Color(red: 0.08, green: 0.42, blue: 0.95) }
        if listen { return ink }
        if engine.isUserNote[i] {
            switch engine.noteStates[i] {
            case .hit: return Color(red: 0.05, green: 0.6, blue: 0.28)
            case .missed: return Color(red: 0.85, green: 0.15, blue: 0.15)
            case .pending: return ink
            }
        }
        return ink.opacity(0.32)
    }

    static func sheetLabel(_ engine: PracticeEngine, _ i: Int, diatonic: Int, alter: Int) -> String? {
        guard i < engine.song.notes.count else { return nil }
        switch engine.labelMode {
        case .none: return nil
        case .names: return Score.germanName(diatonic: diatonic, alter: alter)
        case .solfege: return NoteNames.solfege(Int(engine.song.notes[i].pitch))
        case .fingers:
            let f = i < engine.song.fingers.count ? engine.song.fingers[i] : 0
            return f > 0 ? "\(f)" : nil
        case .harmony:
            return i < engine.analysis.roles.count ? engine.analysis.roles[i] : nil
        }
    }

    static func sheetStyle(_ engine: PracticeEngine, listen: Bool) -> NotationPainter.Style {
        let active = Set(engine.activeSongNotes() + engine.waitGroup)
        return NotationPainter.Style(
            color: { sheetColor(engine, $0, active: active, listen: listen) },
            label: { i, d, a in engine.concertMode ? nil : sheetLabel(engine, i, diatonic: d, alter: a) },
            labelInHead: engine.kidNotes)
    }

    static func sheetPlayX(_ engine: PracticeEngine, rect: CGRect) -> CGFloat {
        let ls = max(5, min(15, rect.height / 26))
        let contentMinX = rect.minX + ls * 2.4 + NotationPainter.headerWidth(ls: ls, fifths: engine.notation.fifths, showTime: true)
        return min(rect.maxX - ls * 4, max(contentMinX + ls * 4, rect.minX + rect.width * 0.24))
    }

    private func drawSheet(_ ctx: GraphicsContext, rect: CGRect, listen: Bool) {
        let song = engine.song
        let score = engine.notation
        let t = engine.currentTime
        let ink = Self.sheetInk
        ctx.fill(Path(rect), with: .color(Self.paper))
        var c = ctx
        c.clip(to: Path(rect))

        let ls = max(5, min(15, rect.height / 26))
        let trebleTop = rect.minY + max(ls * 4.6, (rect.height - GrandStaff.height(ls: ls)) / 2 + ls * 4.6)
        let g = GrandStaff(ls: ls, trebleTop: trebleTop)
        let painter = NotationPainter(g: g, ink: ink)
        let x0 = rect.minX + ls * 2.4
        let headerW = NotationPainter.headerWidth(ls: ls, fifths: score.fifths, showTime: true)
        let contentMinX = x0 + headerW
        let playX = Self.sheetPlayX(engine, rect: rect)
        let secondsRight = engine.visibleSeconds * 1.8
        let pps = (rect.maxX - playX) / CGFloat(secondsRight)
        guard pps > 0.5 else { return }
        let secondsLeft = Double(max(0, playX - contentMinX) / pps)
        func x(_ time: Double) -> CGFloat { playX + CGFloat(time - t) * pps }

        painter.staffLines(c, from: x0, to: rect.maxX)

        // Bereich der sichtbaren Takte
        let tA = score.tick(for: t - secondsLeft - 0.5)
        let tB = score.tick(for: t + secondsRight + 0.5)
        let bA = score.barPosition(ofTick: tA), bB = score.barPosition(ofTick: tB)

        // Loop-Bereich
        if let a = engine.loopStart {
            let b = engine.loopEnd ?? song.duration
            let xa = max(contentMinX, x(a) - ls * 1.7), xb = min(rect.maxX, x(b) - ls * 1.7)
            if xb > xa {
                c.fill(Path(CGRect(x: xa, y: rect.minY, width: xb - xa, height: rect.height)), with: .color(Color.orange.opacity(0.12)))
                for (xx, s) in [(xa, CGFloat(1)), (xb, CGFloat(-1))] {
                    c.fill(Path(CGRect(x: xx - 1.5, y: rect.minY + 2, width: 3, height: rect.height - 4)), with: .color(.orange))
                    c.fill(Path(CGRect(x: s > 0 ? xx - 1.5 : xx - 12.5, y: rect.minY + 2, width: 14, height: 3)), with: .color(.orange))
                    c.fill(Path(CGRect(x: s > 0 ? xx - 1.5 : xx - 12.5, y: rect.maxY - 5, width: 14, height: 3)), with: .color(.orange))
                }
            }
        }

        var notes = c
        notes.clip(to: Path(CGRect(x: contentMinX, y: rect.minY, width: rect.maxX - contentMinX, height: rect.height)))

        // Taktstriche + Taktnummern
        if bA <= bB {
            for bp in bA...bB {
                let bar = score.bars[bp]
                let xs = x(score.time(for: bar.startTick))
                if bp > 0 { painter.barline(notes, x: xs - ls * 1.7) }
                if bp == score.bars.count - 1 { painter.barline(notes, x: x(score.time(for: bar.endTick)) - ls * 1.7, final: true) }
                guard bar.index >= 0 else { continue }
                let isLooped = engine.loopBarStart.map { bar.index >= $0 && bar.index <= (engine.loopBarEnd ?? $0) } ?? false
                let tagRect = CGRect(x: xs - ls * 1.7 + 3, y: rect.minY + 3, width: 46, height: 17)
                if tagRect.minX > contentMinX - 4 {
                    notes.fill(Path(roundedRect: tagRect, cornerRadius: 5), with: .color(isLooped ? Color.orange : ink.opacity(0.07)))
                    notes.draw(Text("Takt \(bar.index + 1)").font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(isLooped ? .white : ink.opacity(0.65)),
                               at: CGPoint(x: tagRect.midX, y: tagRect.midY))
                }
            }
        }

        // Akkordsymbole
        if engine.showChords && !engine.concertMode {
            var lastChord = ""
            for seg in engine.analysis.segments where seg.end >= t - secondsLeft && seg.start <= t + secondsRight {
                guard seg.rootPC != nil, seg.chord != lastChord else { lastChord = seg.chord; continue }
                lastChord = seg.chord
                let xx = x(score.time(for: score.tick(for: seg.start))) - ls * 0.6
                guard xx > contentMinX else { continue }
                if engine.kidNotes {
                    drawVisualChordBadge(notes, seg: seg, x: xx, y: max(rect.minY + 23, g.trebleTop - ls * 3.4 - 28))
                    notes.draw(Text("\(seg.roman) · \(seg.function)").font(.system(size: 10, weight: .semibold, design: .serif))
                                .foregroundColor(Color(red: 0.65, green: 0.35, blue: 0.15)),
                               at: CGPoint(x: xx + 2, y: min(rect.maxY - 8, g.bassBottom + 3.4 * ls)), anchor: .leading)
                } else {
                    // Klassisch: schlichtes Akkordsymbol über dem System
                    notes.draw(Text(seg.chord).font(.system(size: max(11, ls * 1.15), weight: .semibold, design: .serif))
                                .foregroundColor(ink.opacity(0.85)),
                               at: CGPoint(x: xx, y: max(rect.minY + 30, g.trebleTop - ls * 3.6)), anchor: .leading)
                }
            }
        }

        // Dynamik (p, mf, f …)
        if bA <= bB {
            for bp in bA...bB {
                if let m = score.dynamics[bp] {
                    let xx = x(score.time(for: score.bars[bp].startTick)) - ls * 0.3
                    if xx > contentMinX { painter.dynamic(notes, m, x: xx) }
                }
            }
        }

        // Noten
        do {
            var idx: [Int] = []
            if bA <= bB { for bp in bA...bB { idx.append(contentsOf: score.itemsByBar[bp]) } }
            if engine.hideOtherHand && !listen {
                let shown: Set<Hand> = engine.handSelection.hands
                idx = idx.filter { shown.contains(score.items[$0].hand) }
            }
            painter.drawItems(notes, score: score, indices: idx,
                              x: { x(score.time(for: score.items[$0].tick)) },
                              barCenter: { bp in
                                  let b = score.bars[bp]
                                  return (x(score.time(for: b.startTick)) + x(score.time(for: b.endTick))) / 2 - ls * 1.7
                              },
                              style: Self.sheetStyle(engine, listen: listen))
        }

        // Fester Kopf: Akkolade, Schlüssel, Vorzeichen, Taktart
        c.fill(Path(CGRect(x: rect.minX, y: rect.minY + 22, width: contentMinX - rect.minX, height: rect.height - 22)),
               with: .color(Self.paper))
        painter.staffLines(c, from: x0, to: contentMinX)
        painter.systemStart(c, x: x0)
        painter.clefsAndSignature(c, x: x0, fifths: score.fifths, num: score.num, den: score.den, showTime: true)

        // Abspielposition
        c.fill(Path(roundedRect: CGRect(x: playX - 1.5, y: g.trebleTop - ls * 2, width: 3, height: g.bassBottom - g.trebleTop + ls * 4),
                    cornerRadius: 1.5),
               with: .color(Color.accentColor.opacity(0.75)))
    }

    // MARK: Klaviatur

    private func drawKeyboard(_ ctx: GraphicsContext, rect: CGRect, layout: KeyLayout, listen: Bool) {
        let song = engine.song
        var expected: [Int: (hand: Hand, user: Bool, finger: Int)] = [:]
        if !engine.concertMode {
            for i in engine.activeSongNotes() {
                let n = song.notes[i]
                if engine.hideOtherHand && !listen && !engine.isUserNote[i] { continue }
                expected[Int(n.pitch)] = (n.hand, engine.isUserNote[i], i < song.fingers.count ? song.fingers[i] : 0)
            }
            for i in engine.waitGroup {
                let n = song.notes[i]
                expected[Int(n.pitch)] = (n.hand, true, i < song.fingers.count ? song.fingers[i] : 0)
            }
        }
        KeyboardPainter.draw(ctx, rect: rect, layout: layout, color: { p in
            let u = UInt8(p)
            if engine.pressed.contains(u) {
                if listen { return .purple.opacity(0.75) }
                return engine.pressedCorrect.contains(u) ? .hitGreen : .missRed
            }
            if let e = expected[p] {
                let base = Color.hand(e.hand)
                return (e.user || listen) ? base : base.opacity(0.45)
            }
            return nil
        }, label: { p in
            if engine.labelMode == .fingers, let e = expected[p], e.finger > 0 { return "\(e.finger)" }
            if engine.labelMode == .solfege && !KeyLayout.isBlack(p) { return NoteNames.solfege(p) }
            if engine.labelMode == .names && !KeyLayout.isBlack(p) { return p % 12 == 0 ? NoteNames.name(p) : NoteNames.name(p, octave: false) }
            return p % 12 == 0 ? NoteNames.name(p) : nil
        })
    }

    // MARK: Effekte

    private func drawEffects(_ ctx: GraphicsContext, hitY: CGFloat, layout: KeyLayout) {
        let now = CACurrentMediaTime()
        for pt in engine.particles {
            guard let f = layout.frame(pt.pitch) else { continue }
            let age = now - pt.born
            let a = max(0, 1 - age / 0.8)
            let cx = f.x + f.w / 2
            let color: Color = pt.kind == .perfect ? .gold : .hitGreen
            for k in 0..<8 {
                let ang = Double(k) / 8 * .pi * 2 + Double(pt.pitch)
                let dist = CGFloat(age) * 110
                let px = cx + CGFloat(cos(ang)) * dist * 0.6
                let py = hitY - 6 - CGFloat(abs(sin(ang))) * dist
                let r = CGFloat(3.5 * a + 0.5)
                ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r)),
                         with: .color(color.opacity(a)))
            }
            ctx.fill(Path(roundedRect: CGRect(x: f.x, y: hitY - 26, width: f.w, height: 24), cornerRadius: 4),
                     with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(0.5 * a)]),
                                           startPoint: CGPoint(x: 0, y: hitY - 26), endPoint: CGPoint(x: 0, y: hitY)))
        }
        if let j = engine.judgement, let f = layout.frame(j.pitch) {
            let age = now - j.time
            if age < 0.7 {
                let a = 1 - age / 0.7
                let col: Color = j.text.hasPrefix("Perfekt") ? .gold
                    : (j.text.hasPrefix("Falsch") || j.text.hasPrefix("Verpasst") ? .missRed : .hitGreen)
                ctx.draw(Text(j.text).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(col.opacity(a)),
                         at: CGPoint(x: min(max(f.x + f.w / 2, 60), layout.originX + layout.whiteW * 200), y: hitY - 40 - CGFloat(age) * 40))
            }
        }
    }
}

/// Kurzes Konfetti bei jedem Erfolg (trigger hochzählen)
struct ConfettiView: View {
    let trigger: Int
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            Canvas { ctx, size in
                guard let s = start else { return }
                let t = tl.date.timeIntervalSince(s)
                guard t < 2.2 else { return }
                let colors: [Color] = [.yellow, .pink, .green, .blue, .orange, .purple]
                for k in 0..<90 {
                    var rng = SplitMix(seed: UInt64(k * 7919 + trigger * 104729))
                    let x0 = Double(rng.next() % 1000) / 1000 * size.width
                    let vx = (Double(rng.next() % 200) - 100) * 0.6
                    let vy = -Double(rng.next() % 300) - 250
                    let x = x0 + vx * t
                    let y = size.height * 0.55 + vy * t + 420 * t * t
                    let a = max(0, 1 - t / 2.2)
                    let r = CGRect(x: x, y: y, width: 7, height: 11)
                    var c = ctx
                    c.translateBy(x: r.midX, y: r.midY)
                    c.rotate(by: .radians(t * Double(k % 7 + 2)))
                    c.fill(Path(CGRect(x: -3.5, y: -5.5, width: 7, height: 11)), with: .color(colors[k % colors.count].opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { start = nil }
        }
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
