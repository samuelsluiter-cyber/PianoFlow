import SwiftUI

// MARK: - Notensatz-Modell
//
// Wandelt die MIDI-Noten in "echte" Noten um: Rhythmus auf 16tel quantisiert,
// Akkorde mit gemeinsamem Hals, Pausen, Haltebögen über Taktstriche,
// Vorzeichen passend zur Tonart (Kreuz- bzw. B-Tonarten).
// 1 Tick = eine Sechzehntelnote.

struct ScoreBar {
    let index: Int        // Song-Taktindex (-1 = Auftakt)
    let startTick: Int
    let endTick: Int
    var length: Int { endTick - startTick }
}

struct ScoreItem {
    enum Kind { case chord, rest }
    let kind: Kind
    let hand: Hand
    let treble: Bool      // Violin- (true) oder Bassschlüssel
    let tick: Int
    let dur: Int          // darstellbarer Wert in 16teln (16, 12, 8, 6, 4, 3, 2, 1)
    let bar: Int          // Index in Score.bars
    var noteIdx: [Int] = []
    var pitches: [Int] = []
    var diatonic: [Int] = []
    var accidental: [Int?] = []   // anzuzeigendes Vorzeichen (+1 ♯, -1 ♭, 0 ♮)
    var tieToNext = false
    var wholeBarRest = false
}

struct Score {
    let tpp: Int                  // Ticks pro Zählzeit
    let barTicks: Int
    let beatGroup: Int            // Balkengruppe in Ticks
    let num: Int
    let den: Int
    let fifths: Int               // >0 Kreuze, <0 Bes
    let pulseTimes: [Double]
    private(set) var bars: [ScoreBar] = []
    private(set) var items: [ScoreItem] = []
    private(set) var itemsByBar: [[Int]] = []
    private(set) var barOfSongBar: [Int: Int] = [:]
    private(set) var dynamics: [Int: String] = [:]   // Index in bars -> pp … ff

    static let durations = [16, 12, 8, 6, 4, 3, 2, 1]

    init(song: MidiSong, analysis: SongAnalysis) {
        let parts = song.timeSignature.split(separator: "/").compactMap { Int($0) }
        num = max(1, parts.first ?? 4)
        den = max(1, parts.count > 1 ? parts[1] : 4)
        tpp = max(1, 16 / den)
        barTicks = max(1, num * tpp)
        let compound = den == 8 && num % 3 == 0 && num > 3
        beatGroup = compound ? 3 * tpp : (den >= 8 ? 4 : tpp)
        pulseTimes = song.pulseTimes
        let majorRoot = analysis.minor ? (analysis.keyRoot + 3) % 12 : analysis.keyRoot
        fifths = song.keyFifths ?? [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5][((majorRoot % 12) + 12) % 12]
        build(song)
    }

    // MARK: Zeit ↔ Tick

    func tick(for t: Double) -> Int {
        let p = pulseTimes
        guard p.count > 1 else { return Int((t * 2 * Double(tpp)).rounded()) }
        var k = p.lowerBound(t)
        k = min(max(1, k), p.count - 1)
        let a = p[k - 1], b = p[k]
        let pos = Double(k - 1) + (t - a) / max(b - a, 1e-6)
        return Int((pos * Double(tpp)).rounded())
    }

    func time(for tick: Int) -> Double {
        let p = pulseTimes
        let pos = Double(tick) / Double(tpp)
        guard p.count > 1 else { return pos * 0.5 }
        let k = Int(floor(pos))
        if k < 0 { return p[0] + pos * (p[1] - p[0]) }
        if k >= p.count - 1 { return p[p.count - 1] + (pos - Double(p.count - 1)) * (p[p.count - 1] - p[p.count - 2]) }
        return p[k] + (pos - Double(k)) * (p[k + 1] - p[k])
    }

    /// Index in `bars` für einen Tick
    func barPosition(ofTick tk: Int) -> Int {
        guard !bars.isEmpty else { return 0 }
        var lo = 0, hi = bars.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if bars[mid].startTick <= tk { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func beatGroupIndex(_ it: ScoreItem) -> Int {
        (it.tick - bars[it.bar].startTick) / max(beatGroup, 1)
    }

    // MARK: Schreibweise

    static func spell(_ p: Int, fifths: Int) -> (diatonic: Int, alter: Int) {
        let pc = NoteNames.pc(p)
        let oct = p >= 0 ? p / 12 : (p - 11) / 12
        if !Staff.isSharp(p) { return (oct * 7 + Staff.letterOf[pc], 0) }
        if fifths < 0 { return (oct * 7 + Staff.letterOf[pc] + 1, -1) }
        return (oct * 7 + Staff.letterOf[pc], 1)
    }

    /// Vorzeichen der Tonart je Stammton (0 = C … 6 = H)
    static func keyAlters(_ fifths: Int) -> [Int] {
        var a = [Int](repeating: 0, count: 7)
        let sharps = [3, 0, 4, 1, 5, 2, 6], flats = [6, 2, 5, 1, 4, 0, 3]
        if fifths > 0 { for l in sharps.prefix(min(7, fifths)) { a[l] = 1 } }
        if fifths < 0 { for l in flats.prefix(min(7, -fifths)) { a[l] = -1 } }
        return a
    }

    /// Deutscher Notenname passend zur Schreibweise (Cis, Es, B, H …)
    static func germanName(diatonic d: Int, alter: Int) -> String {
        let letters = ["C", "D", "E", "F", "G", "A", "H"]
        let l = ((d % 7) + 7) % 7
        switch alter {
        case 1: return letters[l] + "is"
        case -1:
            switch l {
            case 2: return "Es"
            case 5: return "As"
            case 6: return "B"
            default: return letters[l] + "es"
            }
        default: return letters[l]
        }
    }

    // MARK: Aufbau

    private mutating func build(_ song: MidiSong) {
        let firstBarTick = song.pulseOffset * tpp
        var lastTick = 0
        for n in song.notes { lastTick = max(lastTick, tick(for: n.end)) }

        if firstBarTick > 0 { bars.append(ScoreBar(index: -1, startTick: 0, endTick: firstBarTick)) }
        let count = max(song.barTimes.count, 1)
        for b in 0..<count {
            let s = firstBarTick + b * barTicks
            bars.append(ScoreBar(index: b, startTick: s, endTick: s + barTicks))
            barOfSongBar[b] = bars.count - 1
        }
        var extra = count
        while let last = bars.last, last.endTick < lastTick, extra < 5000 {
            bars.append(ScoreBar(index: extra, startTick: last.endTick, endTick: last.endTick + barTicks))
            barOfSongBar[extra] = bars.count - 1
            extra += 1
        }
        let scoreEnd = bars.last?.endTick ?? barTicks

        var out: [ScoreItem] = []
        for hand in [Hand.right, Hand.left] {
            var groups: [(tick: Int, end: Int, idx: [Int])] = []
            for i in song.notes.indices where song.notes[i].hand == hand {
                let n = song.notes[i]
                let s = min(max(0, tick(for: n.start)), scoreEnd - 1)
                let e = min(max(s + 1, tick(for: n.end)), scoreEnd)
                if let last = groups.last, last.tick == s {
                    groups[groups.count - 1].idx.append(i)
                    groups[groups.count - 1].end = max(last.end, e)
                } else {
                    groups.append((s, e, [i]))
                }
            }
            var cursor = 0
            for (g, grp) in groups.enumerated() {
                let next = g + 1 < groups.count ? groups[g + 1].tick : scoreEnd
                let end = max(grp.tick + 1, min(grp.end, next))
                if grp.tick > cursor { addRests(&out, hand: hand, from: cursor, to: grp.tick) }
                addChord(&out, song: song, hand: hand, idx: grp.idx, from: grp.tick, to: end)
                cursor = max(cursor, end)
            }
            if cursor < scoreEnd { addRests(&out, hand: hand, from: cursor, to: scoreEnd) }
        }
        // Pausen weglassen, wo die andere Hand ins gleiche System gewechselt ist
        var foreign = Set<Int>()   // bar*2 + (treble ? 1 : 0)
        for it in out where it.kind == .chord && it.treble != (it.hand == .right) {
            foreign.insert(it.bar * 2 + (it.treble ? 1 : 0))
        }
        if !foreign.isEmpty {
            out.removeAll { $0.kind == .rest && foreign.contains($0.bar * 2 + ($0.treble ? 1 : 0)) }
        }
        out.sort { ($0.tick, $0.hand == .right ? 0 : 1) < ($1.tick, $1.hand == .right ? 0 : 1) }

        // Vorzeichen setzen (gelten bis zum Taktende, je System und Tonhöhe)
        let keyA = Self.keyAlters(fifths)
        var state: [Int: Int] = [:]
        var currentBar = -1
        var tieCarry: [Hand: Set<Int>] = [.right: [], .left: []]
        for i in out.indices where out[i].kind == .chord {
            if out[i].bar != currentBar { currentBar = out[i].bar; state = [:] }
            let carry = tieCarry[out[i].hand] ?? []
            var accs: [Int?] = []
            var diats: [Int] = []
            for p in out[i].pitches {
                let sp = Self.spell(p, fifths: fifths)
                diats.append(sp.diatonic)
                let key = (out[i].treble ? 100_000 : 0) + sp.diatonic
                let current = state[key] ?? keyA[((sp.diatonic % 7) + 7) % 7]
                if carry.contains(p) {
                    accs.append(nil)
                } else {
                    accs.append(sp.alter != current ? sp.alter : nil)
                }
                state[key] = sp.alter
            }
            out[i].diatonic = diats
            out[i].accidental = accs
            tieCarry[out[i].hand] = out[i].tieToNext ? Set(out[i].pitches) : []
        }

        items = out
        dynamics = Self.dynamics(song, bars: bars, tickFor: { tick(for: $0) }, barPos: { barPosition(ofTick: $0) })
        itemsByBar = Array(repeating: [], count: bars.count)
        for (i, it) in items.enumerated() where it.bar < itemsByBar.count { itemsByBar[it.bar].append(i) }
    }

    /// Dynamik aus der Anschlagstärke: pro Takt mittlere Lautstärke, Zeichen nur bei Wechsel
    private static func dynamics(_ song: MidiSong, bars: [ScoreBar], tickFor: (Double) -> Int, barPos: (Int) -> Int) -> [Int: String] {
        let vels = song.notes.map { Double($0.velocity) }
        guard vels.count > 8 else { return [:] }
        let mean = vels.reduce(0, +) / Double(vels.count)
        let sd = (vels.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(vels.count)).squareRoot()
        var sum = [Double](repeating: 0, count: bars.count), cnt = [Int](repeating: 0, count: bars.count)
        for n in song.notes {
            let b = barPos(tickFor(n.start))
            guard b < bars.count else { continue }
            sum[b] += Double(n.velocity); cnt[b] += 1
        }
        func mark(_ v: Double) -> String {
            switch v { case ..<40: return "pp"; case ..<56: return "p"; case ..<70: return "mp"
                       case ..<86: return "mf"; case ..<104: return "f"; default: return "ff" }
        }
        var res: [Int: String] = [:]
        var last = ""
        // Gleichförmige Dateien (keine echte Dynamik) bekommen nur ein Startzeichen
        let varies = sd >= 6
        for b in bars.indices where cnt[b] > 0 {
            let m = mark(sum[b] / Double(cnt[b]))
            if m != last && (varies || last.isEmpty) { res[b] = m; last = m }
        }
        if !varies, mean > 85, mean < 104 { return [:] }   // Standard-Velocity (z. B. 90-100) ist keine Absicht
        return res
    }

    private func segments(from a: Int, to b: Int) -> [(bar: Int, from: Int, to: Int)] {
        var res: [(Int, Int, Int)] = []
        var pos = a
        while pos < b {
            let bi = barPosition(ofTick: pos)
            let barEnd = bars.isEmpty ? b : bars[bi].endTick
            let e = min(b, max(barEnd, pos + 1))
            res.append((bi, pos, e))
            pos = e
        }
        return res
    }

    private func addChord(_ out: inout [ScoreItem], song: MidiSong, hand: Hand, idx: [Int], from a: Int, to b: Int) {
        let sortedIdx = idx.sorted { song.notes[$0].pitch < song.notes[$1].pitch }
        var pitches: [Int] = []
        var noteIdx: [Int] = []
        for i in sortedIdx where !pitches.contains(Int(song.notes[i].pitch)) {
            pitches.append(Int(song.notes[i].pitch))
            noteIdx.append(i)
        }
        // System: normalerweise nach Hand, extreme Lagen wechseln das System
        var treble = hand == .right
        if hand == .left, (pitches.min() ?? 0) >= 67 { treble = true }
        if hand == .right, (pitches.max() ?? 127) < 53 { treble = false }

        var pieces: [ScoreItem] = []
        for seg in segments(from: a, to: b) {
            var pos = seg.from
            while pos < seg.to {
                let rem = seg.to - pos
                let d = Self.durations.first { $0 <= rem } ?? 1
                pieces.append(ScoreItem(kind: .chord, hand: hand, treble: treble, tick: pos, dur: d, bar: seg.bar,
                                        noteIdx: noteIdx, pitches: pitches))
                pos += d
            }
        }
        for k in pieces.indices { pieces[k].tieToNext = k < pieces.count - 1 }
        out.append(contentsOf: pieces)
    }

    private func addRests(_ out: inout [ScoreItem], hand: Hand, from a: Int, to b: Int) {
        for seg in segments(from: a, to: b) {
            let bar = bars[seg.bar]
            if seg.from == bar.startTick && seg.to == bar.endTick && bar.index >= 0 {
                var r = ScoreItem(kind: .rest, hand: hand, treble: hand == .right, tick: seg.from, dur: bar.length, bar: seg.bar)
                r.wholeBarRest = true
                out.append(r)
                continue
            }
            var pos = seg.from
            while pos < seg.to {
                let rel = pos - bar.startTick
                let rem = seg.to - pos
                let d = [16, 8, 4, 2, 1].first { $0 <= rem && rel % $0 == 0 } ?? 1
                out.append(ScoreItem(kind: .rest, hand: hand, treble: hand == .right, tick: pos, dur: d, bar: seg.bar))
                pos += d
            }
        }
    }
}

// MARK: - Großes Notensystem

struct GrandStaff {
    let ls: CGFloat          // Linienabstand
    let trebleTop: CGFloat   // y der obersten Linie im Violinsystem
    static let gap: CGFloat = 6.5
    static let trebleBottomD = 37   // E4
    static let bassBottomD = 25     // G2

    var trebleBottom: CGFloat { trebleTop + 4 * ls }
    var bassTop: CGFloat { trebleBottom + Self.gap * ls }
    var bassBottom: CGFloat { bassTop + 4 * ls }
    /// Gesamthöhe inkl. Rand für Hilfslinien
    static func height(ls: CGFloat) -> CGFloat { (4 + 4 + gap + 4 + 4.5) * ls }

    func y(_ d: Int, treble: Bool) -> CGFloat {
        treble ? trebleBottom - CGFloat(d - Self.trebleBottomD) * ls / 2
               : bassBottom - CGFloat(d - Self.bassBottomD) * ls / 2
    }
    func middleD(treble: Bool) -> Int { treble ? 41 : 29 }
    func middleY(treble: Bool) -> CGFloat { treble ? trebleTop + 2 * ls : bassTop + 2 * ls }
}

// MARK: - Zeichner

struct NotationPainter {
    let g: GrandStaff
    let ink: Color
    var ls: CGFloat { g.ls }
    var headW: CGFloat { ls * 1.18 }
    var stemW: CGFloat { max(1, ls * 0.11) }

    static func headerWidth(ls: CGFloat, fifths: Int, showTime: Bool) -> CGFloat {
        let n = CGFloat(min(7, abs(fifths)))
        return ls * (0.6 + 3.2 + n + (n > 0 ? 0.6 : 0) + (showTime ? 2.4 : 0) + 0.6)
    }

    // MARK: Systeme

    func staffLines(_ ctx: GraphicsContext, from x0: CGFloat, to x1: CGFloat) {
        let lw = max(0.8, ls * 0.08)
        for k in 0..<5 {
            for top in [g.trebleTop, g.bassTop] {
                let y = top + CGFloat(k) * ls
                ctx.fill(Path(CGRect(x: x0, y: y - lw / 2, width: x1 - x0, height: lw)), with: .color(ink.opacity(0.75)))
            }
        }
    }

    func systemStart(_ ctx: GraphicsContext, x: CGFloat) {
        let lw = max(1, ls * 0.12)
        ctx.fill(Path(CGRect(x: x, y: g.trebleTop, width: lw, height: g.bassBottom - g.trebleTop)), with: .color(ink))
        // Akkolade {
        let top = g.trebleTop, bot = g.bassBottom, mid = (top + bot) / 2
        let bx = x - ls * 0.5
        var brace = Path()
        brace.move(to: CGPoint(x: bx, y: top))
        brace.addCurve(to: CGPoint(x: bx - ls * 0.9, y: mid), control1: CGPoint(x: bx - ls * 1.1, y: top + (mid - top) * 0.3),
                       control2: CGPoint(x: bx + ls * 0.2, y: mid - ls * 1.2))
        brace.addCurve(to: CGPoint(x: bx, y: bot), control1: CGPoint(x: bx + ls * 0.2, y: mid + ls * 1.2),
                       control2: CGPoint(x: bx - ls * 1.1, y: bot - (bot - mid) * 0.3))
        brace.addCurve(to: CGPoint(x: bx - ls * 0.55, y: mid), control1: CGPoint(x: bx - ls * 0.7, y: bot - (bot - mid) * 0.3),
                       control2: CGPoint(x: bx + ls * 0.4, y: mid + ls * 1.4))
        brace.addCurve(to: CGPoint(x: bx, y: top), control1: CGPoint(x: bx + ls * 0.4, y: mid - ls * 1.4),
                       control2: CGPoint(x: bx - ls * 0.7, y: top + (mid - top) * 0.3))
        brace.closeSubpath()
        ctx.fill(brace, with: .color(ink))
    }

    /// Schlüssel, Vorzeichen, (optional) Taktart. Gibt die belegte Breite zurück.
    @discardableResult
    func clefsAndSignature(_ ctx: GraphicsContext, x: CGFloat, fifths: Int, num: Int, den: Int, showTime: Bool) -> CGFloat {
        var cx = x + ls * 0.6
        ctx.draw(Text("𝄞").font(.custom("Apple Symbols", size: ls * 6.6)).foregroundColor(ink),
                 at: CGPoint(x: cx + ls * 1.2, y: g.trebleTop + ls * 2.15))
        ctx.draw(Text("𝄢").font(.custom("Apple Symbols", size: ls * 4.2)).foregroundColor(ink),
                 at: CGPoint(x: cx + ls * 1.25, y: g.bassTop + ls * 1.55))
        cx += ls * 3.2
        // Vorzeichen der Tonart
        let sharpD = [45, 42, 46, 43, 40, 44, 41], flatD = [41, 44, 40, 43, 39, 42, 38]
        let n = min(7, abs(fifths))
        for k in 0..<n {
            let d = fifths > 0 ? sharpD[k] : flatD[k]
            for treble in [true, false] {
                let yy = g.y(treble ? d : d - 14, treble: treble)
                accidental(ctx, fifths > 0 ? 1 : -1, x: cx + CGFloat(k) * ls * 1.0 + ls * 0.4, y: yy)
            }
        }
        cx += CGFloat(n) * ls * 1.0 + (n > 0 ? ls * 0.6 : 0)
        if showTime {
            for top in [g.trebleTop, g.bassTop] {
                let f = Font.system(size: ls * 2.55, weight: .black, design: .serif)
                ctx.draw(Text("\(num)").font(f).foregroundColor(ink), at: CGPoint(x: cx + ls * 0.9, y: top + ls * 1.0))
                ctx.draw(Text("\(den)").font(f).foregroundColor(ink), at: CGPoint(x: cx + ls * 0.9, y: top + ls * 3.0))
            }
            cx += ls * 2.4
        }
        return cx - x + ls * 0.6
    }

    func barline(_ ctx: GraphicsContext, x: CGFloat, final: Bool = false) {
        let lw = max(1, ls * 0.11)
        ctx.fill(Path(CGRect(x: x - lw / 2, y: g.trebleTop, width: lw, height: g.bassBottom - g.trebleTop)), with: .color(ink))
        if final {
            ctx.fill(Path(CGRect(x: x + ls * 0.35, y: g.trebleTop, width: ls * 0.45, height: g.bassBottom - g.trebleTop)),
                     with: .color(ink))
        }
    }

    // MARK: Symbole

    func accidental(_ ctx: GraphicsContext, _ alter: Int, x: CGFloat, y: CGFloat, color: Color? = nil) {
        let c = color ?? ink
        let thin = max(0.9, ls * 0.11)
        switch alter {
        case 1: // Kreuz
            for dx in [-0.2, 0.2] {
                let xx = x + CGFloat(dx) * ls
                ctx.fill(Path(CGRect(x: xx - thin / 2, y: y - ls * 1.3 - CGFloat(dx) * ls * 0.2, width: thin, height: ls * 2.5)),
                         with: .color(c))
            }
            for dy in [-0.42, 0.42] {
                var p = Path()
                let yy = y + CGFloat(dy) * ls
                p.move(to: CGPoint(x: x - ls * 0.5, y: yy + ls * 0.12))
                p.addLine(to: CGPoint(x: x + ls * 0.5, y: yy - ls * 0.18))
                p.addLine(to: CGPoint(x: x + ls * 0.5, y: yy + ls * 0.12))
                p.addLine(to: CGPoint(x: x - ls * 0.5, y: yy + ls * 0.42))
                p.closeSubpath()
                ctx.fill(p, with: .color(c))
            }
        case -1: // B
            let sx = x - ls * 0.3
            ctx.fill(Path(CGRect(x: sx - thin / 2, y: y - ls * 1.75, width: thin, height: ls * 2.25)), with: .color(c))
            var p = Path()
            p.move(to: CGPoint(x: sx, y: y + ls * 0.5))
            p.addCurve(to: CGPoint(x: sx, y: y - ls * 0.2), control1: CGPoint(x: sx + ls * 1.05, y: y - ls * 0.05),
                       control2: CGPoint(x: sx + ls * 0.75, y: y - ls * 0.85))
            p.addCurve(to: CGPoint(x: sx, y: y + ls * 0.28), control1: CGPoint(x: sx + ls * 0.5, y: y - ls * 0.5),
                       control2: CGPoint(x: sx + ls * 0.55, y: y))
            p.closeSubpath()
            ctx.fill(p, with: .color(c))
        default: // Auflöser
            ctx.fill(Path(CGRect(x: x - ls * 0.25 - thin / 2, y: y - ls * 1.35, width: thin, height: ls * 1.95)), with: .color(c))
            ctx.fill(Path(CGRect(x: x + ls * 0.25 - thin / 2, y: y - ls * 0.6, width: thin, height: ls * 1.95)), with: .color(c))
            for dy in [-0.35, 0.45] {
                var p = Path()
                let yy = y + CGFloat(dy) * ls
                p.move(to: CGPoint(x: x - ls * 0.25, y: yy))
                p.addLine(to: CGPoint(x: x + ls * 0.25, y: yy - ls * 0.15))
                p.addLine(to: CGPoint(x: x + ls * 0.25, y: yy + ls * 0.13))
                p.addLine(to: CGPoint(x: x - ls * 0.25, y: yy + ls * 0.28))
                p.closeSubpath()
                ctx.fill(p, with: .color(c))
            }
        }
    }

    func notehead(_ ctx: GraphicsContext, center: CGPoint, hollow: Bool, whole: Bool, color: Color) {
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        let w = whole ? headW * 1.22 : headW
        let h = ls * (whole ? 0.95 : 0.86)
        if whole {
            var p = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            var inner = Path(ellipseIn: CGRect(x: -w * 0.2, y: -h * 0.36, width: w * 0.4, height: h * 0.72))
            inner = inner.applying(CGAffineTransform(rotationAngle: .pi / 3))
            p.addPath(inner)
            c.fill(p, with: .color(color), style: FillStyle(eoFill: true))
            return
        }
        c.rotate(by: .degrees(-20))
        var p = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        if hollow {
            p.addPath(Path(ellipseIn: CGRect(x: -w * 0.4, y: -h * 0.26, width: w * 0.8, height: h * 0.52)))
            c.fill(p, with: .color(color), style: FillStyle(eoFill: true))
        } else {
            c.fill(p, with: .color(color))
        }
    }

    func ledgerLines(_ ctx: GraphicsContext, d: Int, treble: Bool, x: CGFloat, color: Color) {
        let rel = d - (treble ? GrandStaff.trebleBottomD : GrandStaff.bassBottomD)
        var lines: [Int] = []
        if rel <= -2 { lines = Array(stride(from: -2, through: rel, by: -2)) }
        if rel >= 10 { lines = Array(stride(from: 10, through: rel, by: 2)) }
        let lw = max(0.9, ls * 0.1)
        for k in lines {
            let y = (treble ? g.trebleBottom : g.bassBottom) - CGFloat(k) * ls / 2
            ctx.fill(Path(CGRect(x: x - headW * 0.82, y: y - lw / 2, width: headW * 1.64, height: lw)), with: .color(color))
        }
    }

    func flag(_ ctx: GraphicsContext, x: CGFloat, tipY: CGFloat, down: Bool, count: Int, color: Color) {
        let s: CGFloat = down ? -1 : 1
        for k in 0..<count {
            let y0 = tipY + s * CGFloat(k) * ls * 0.85
            var p = Path()
            p.move(to: CGPoint(x: x, y: y0))
            p.addCurve(to: CGPoint(x: x + ls * 0.95, y: y0 + s * ls * 2.6),
                       control1: CGPoint(x: x + ls * 0.15, y: y0 + s * ls * 1.0),
                       control2: CGPoint(x: x + ls * 1.35, y: y0 + s * ls * 1.4))
            p.addCurve(to: CGPoint(x: x, y: y0 + s * ls * 1.0),
                       control1: CGPoint(x: x + ls * 1.05, y: y0 + s * ls * 1.7),
                       control2: CGPoint(x: x + ls * 0.3, y: y0 + s * ls * 1.35))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        }
    }

    func rest(_ ctx: GraphicsContext, dur: Int, wholeBar: Bool, x: CGFloat, treble: Bool, color: Color) {
        let mid = g.middleY(treble: treble)
        let lw = ls * 0.3
        let base = wholeBar ? 16 : (dur >= 16 ? 16 : dur >= 8 ? 8 : dur >= 4 ? 4 : dur >= 2 ? 2 : 1)
        switch base {
        case 16:
            ctx.fill(Path(CGRect(x: x - ls * 0.6, y: mid - ls, width: ls * 1.2, height: ls * 0.55)), with: .color(color))
        case 8:
            ctx.fill(Path(CGRect(x: x - ls * 0.6, y: mid - ls * 0.55, width: ls * 1.2, height: ls * 0.55)), with: .color(color))
        case 4:
            var p = Path()
            p.move(to: CGPoint(x: x - ls * 0.3, y: mid - ls * 1.5))
            p.addLine(to: CGPoint(x: x + ls * 0.35, y: mid - ls * 0.65))
            p.addLine(to: CGPoint(x: x - ls * 0.2, y: mid + ls * 0.05))
            p.addLine(to: CGPoint(x: x + ls * 0.35, y: mid + ls * 0.75))
            p.addCurve(to: CGPoint(x: x - ls * 0.05, y: mid + ls * 1.5),
                       control1: CGPoint(x: x - ls * 0.45, y: mid + ls * 0.45),
                       control2: CGPoint(x: x - ls * 0.5, y: mid + ls * 1.15))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        default:
            let hooks = base == 2 ? 1 : 2
            let top = mid - ls * 0.5
            var stem = Path()
            stem.move(to: CGPoint(x: x + ls * 0.45, y: top))
            stem.addLine(to: CGPoint(x: x - ls * 0.1, y: mid + ls * (hooks == 1 ? 1.0 : 2.0)))
            ctx.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: ls * 0.13, lineCap: .round))
            for k in 0..<hooks {
                let yy = top + CGFloat(k) * ls
                let xx = x + ls * 0.45 - CGFloat(k) * ls * 0.28
                ctx.fill(Path(ellipseIn: CGRect(x: xx - ls * 0.95, y: yy - ls * 0.12, width: ls * 0.5, height: ls * 0.5)),
                         with: .color(color))
                var hook = Path()
                hook.move(to: CGPoint(x: xx - ls * 0.7, y: yy + ls * 0.3))
                hook.addQuadCurve(to: CGPoint(x: xx, y: yy), control: CGPoint(x: xx - ls * 0.3, y: yy + ls * 0.45))
                ctx.stroke(hook, with: .color(color), style: StrokeStyle(lineWidth: ls * 0.13, lineCap: .round))
            }
        }
        if !wholeBar && (dur == 12 || dur == 6 || dur == 3) {
            ctx.fill(Path(ellipseIn: CGRect(x: x + ls * 0.75, y: mid - ls * 0.65, width: ls * 0.36, height: ls * 0.36)),
                     with: .color(color))
        }
    }

    // MARK: Akkorde, Balken, Haltebögen

    struct Style {
        var color: (Int) -> Color          // pro Noten-Index
        var label: (Int, Int, Int) -> String?  // (Noten-Index, Diatonik, Alter) -> Beschriftung
        var labelInHead: Bool              // true = Kindernoten (Name im Kopf), false = klassisch (über/unter der Note)
    }

    private struct Heads {
        var centers: [CGPoint] = []
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        var labels: [(pitch: Int, text: String, color: Color)] = []
    }

    /// Klassisch: Fingersatz/Namen gestapelt über (Violin-) bzw. unter (Bass-System) dem Akkord, frei vom Hals
    private func drawLabels(_ ctx: GraphicsContext, _ h: Heads, x: CGFloat, treble: Bool, down: Bool, tip: CGFloat?) {
        guard !h.labels.isEmpty else { return }
        let above = treble
        let sorted = h.labels.sorted { above ? $0.pitch < $1.pitch : $0.pitch > $1.pitch }
        var y: CGFloat
        if above {
            y = h.minY - ls * 1.25
            if let tip, !down { y = min(y, tip - ls * 0.75) }
            if treble { y = min(y, g.trebleTop - ls * 0.6) }
        } else {
            y = h.maxY + ls * 1.25
            if let tip, down { y = max(y, tip + ls * 0.75) }
            if !treble { y = max(y, min(g.bassBottom + ls * 0.6, h.maxY + ls * 1.25)) }
        }
        for l in sorted {
            let digits = l.text.allSatisfy(\.isNumber)
            let font: Font = digits
                ? .system(size: max(8, ls * 1.05), weight: .semibold, design: .serif).italic()
                : .system(size: max(7, ls * 0.8), weight: .medium, design: .rounded)
            ctx.draw(Text(l.text).font(font).foregroundColor(l.color), at: CGPoint(x: x, y: y))
            y += above ? -ls * 1.05 : ls * 1.05
        }
    }

    /// Dynamik-Zeichen (p, mf, f …) zwischen den Systemen
    func dynamic(_ ctx: GraphicsContext, _ mark: String, x: CGFloat) {
        let y = g.trebleBottom + ls * 2.4
        ctx.draw(Text(mark).font(.system(size: ls * 1.7, weight: .bold, design: .serif).italic()).foregroundColor(ink),
                 at: CGPoint(x: x, y: y), anchor: .leading)
    }

    private func stemDown(_ diat: [Int], treble: Bool) -> Bool {
        guard let lo = diat.min(), let hi = diat.max() else { return false }
        let m = g.middleD(treble: treble)
        return (hi - m) > (m - lo)
    }

    /// Notenköpfe, Hilfslinien, Vorzeichen und Punkte zeichnen (ohne Hals)
    private func drawHeads(_ ctx: GraphicsContext, _ it: ScoreItem, x: CGFloat, down: Bool, style: Style) -> Heads {
        var h = Heads()
        let order = Array(it.diatonic.indices).sorted { down ? it.diatonic[$0] > it.diatonic[$1] : it.diatonic[$0] < it.diatonic[$1] }
        var shifted = Set<Int>()
        var prevD: Int? = nil
        var prevShifted = false
        for k in order {
            let d = it.diatonic[k]
            var s = false
            if let pd = prevD, abs(d - pd) == 1, !prevShifted { s = true }
            if s { shifted.insert(k) }
            prevD = d
            prevShifted = s
        }
        let hollow = it.dur >= 8
        let whole = it.dur >= 16
        var accCol = 0
        for k in it.diatonic.indices.reversed() {
            let d = it.diatonic[k]
            let y = g.y(d, treble: it.treble)
            let dx: CGFloat = shifted.contains(k) ? (down ? -headW : headW) * 0.98 : 0
            let cx = x + dx
            let col = style.color(it.noteIdx[k])
            ledgerLines(ctx, d: d, treble: it.treble, x: cx, color: ink.opacity(0.85))
            notehead(ctx, center: CGPoint(x: cx, y: y), hollow: hollow, whole: whole, color: col)
            if k < it.accidental.count, let a = it.accidental[k] {
                let ax = x - headW * 0.5 - ls * 0.75 - CGFloat(accCol % 2) * ls * 1.05 - (shifted.contains(k) && down ? headW : 0)
                accidental(ctx, a, x: ax, y: y, color: col)
                accCol += 1
            }
            if it.dur == 12 || it.dur == 6 || it.dur == 3 {
                let onLine = (d - (it.treble ? GrandStaff.trebleBottomD : GrandStaff.bassBottomD)) % 2 == 0
                let dy = onLine ? -ls * 0.5 : 0
                let maxX = x + headW * (shifted.isEmpty || down ? 0.5 : 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: maxX + ls * 0.3, y: y + dy - ls * 0.19, width: ls * 0.38, height: ls * 0.38)),
                         with: .color(col))
            }
            let alter = Score.spellAlter(it.pitches[k], diatonic: d)
            if let l = style.label(it.noteIdx[k], d, alter) {
                let n = l.count
                let fs = ls * (n == 1 ? 0.82 : n == 2 ? 0.64 : 0.5)
                if style.labelInHead && n <= 3 && fs >= 4.5 {
                    // Kindernoten: Notenname direkt im Notenkopf
                    ctx.draw(Text(l).font(.system(size: fs, weight: .heavy, design: .rounded).width(.condensed))
                                .foregroundColor(hollow ? col : .white),
                             at: CGPoint(x: cx, y: y + ls * 0.02))
                } else {
                    h.labels.append((it.pitches[k], l, col == ink ? ink.opacity(0.8) : col))
                }
            }
            h.centers.append(CGPoint(x: cx, y: y))
            h.minY = min(h.minY, y)
            h.maxY = max(h.maxY, y)
        }
        return h
    }

    private func stemX(_ x: CGFloat, down: Bool) -> CGFloat {
        down ? x - headW / 2 + stemW / 2 : x + headW / 2 - stemW / 2
    }

    private func drawStem(_ ctx: GraphicsContext, x: CGFloat, from y0: CGFloat, to y1: CGFloat, color: Color) {
        ctx.fill(Path(CGRect(x: x - stemW / 2, y: min(y0, y1), width: stemW, height: abs(y1 - y0))), with: .color(color))
    }

    func drawSingle(_ ctx: GraphicsContext, _ it: ScoreItem, x: CGFloat, style: Style) {
        let down = stemDown(it.diatonic, treble: it.treble)
        let h = drawHeads(ctx, it, x: x, down: down, style: style)
        guard it.dur < 16, !h.centers.isEmpty else {
            drawLabels(ctx, h, x: x, treble: it.treble, down: down, tip: nil)
            return
        }
        let col = style.color(it.noteIdx.first ?? 0)
        let sx = stemX(x, down: down)
        let mid = g.middleY(treble: it.treble)
        let flags = it.dur <= 1 ? 2 : (it.dur <= 3 ? 1 : 0)
        let len = ls * (flags == 2 ? 3.9 : 3.4)
        if down {
            let tip = max(h.maxY + len, mid)
            drawStem(ctx, x: sx, from: h.minY + ls * 0.15, to: tip, color: col)
            if flags > 0 { flag(ctx, x: sx - stemW / 2, tipY: tip, down: true, count: flags, color: col) }
            drawLabels(ctx, h, x: x, treble: it.treble, down: true, tip: tip)
        } else {
            let tip = min(h.minY - len, mid)
            drawStem(ctx, x: sx, from: h.maxY - ls * 0.15, to: tip, color: col)
            if flags > 0 { flag(ctx, x: sx + stemW / 2 - 0.3, tipY: tip, down: false, count: flags, color: col) }
            drawLabels(ctx, h, x: x, treble: it.treble, down: false, tip: tip)
        }
    }

    private func drawBeamGroup(_ ctx: GraphicsContext, _ group: [ScoreItem], xs: [CGFloat], style: Style) {
        let allD = group.flatMap(\.diatonic)
        let treble = group[0].treble
        let down = stemDown(allD, treble: treble)
        var heads: [Heads] = []
        for (k, it) in group.enumerated() { heads.append(drawHeads(ctx, it, x: xs[k], down: down, style: style)) }
        let sxs = xs.map { stemX($0, down: down) }
        let len = ls * 3.3
        let minLen = ls * 2.6
        let tips = heads.map { down ? $0.maxY + len : $0.minY - len }
        guard let firstX = sxs.first, let lastX = sxs.last, lastX - firstX > 1 else { return }
        var slope = (tips[tips.count - 1] - tips[0]) / (lastX - firstX)
        slope = max(-0.18, min(0.18, slope))
        var y0 = tips[0]
        for k in sxs.indices {
            let ly = y0 + slope * (sxs[k] - firstX)
            if down {
                let need = heads[k].maxY + minLen
                if ly < need { y0 += need - ly }
            } else {
                let need = heads[k].minY - minLen
                if ly > need { y0 -= ly - need }
            }
        }
        func lineY(_ x: CGFloat) -> CGFloat { y0 + slope * (x - firstX) }
        let col = style.color(group[0].noteIdx.first ?? 0)
        for k in heads.indices {
            let beamEdge = lineY(sxs[k]) + (down ? ls * 0.5 : -ls * 0.5)
            drawLabels(ctx, heads[k], x: xs[k], treble: treble, down: down, tip: beamEdge)
        }
        for k in sxs.indices {
            let from = down ? heads[k].minY + ls * 0.15 : heads[k].maxY - ls * 0.15
            drawStem(ctx, x: sxs[k], from: from, to: lineY(sxs[k]), color: style.color(group[k].noteIdx.first ?? 0))
        }
        let th = ls * 0.48
        let dir: CGFloat = down ? -1 : 1   // Richtung zum Notenkopf
        func beam(_ xa: CGFloat, _ xb: CGFloat, level: Int) {
            let off = CGFloat(level) * ls * 0.78 * dir
            var p = Path()
            let a = CGPoint(x: xa - stemW / 2, y: lineY(xa) + off)
            let b = CGPoint(x: xb + stemW / 2, y: lineY(xb) + off)
            p.move(to: a)
            p.addLine(to: b)
            p.addLine(to: CGPoint(x: b.x, y: b.y + th * dir))
            p.addLine(to: CGPoint(x: a.x, y: a.y + th * dir))
            p.closeSubpath()
            ctx.fill(p, with: .color(col))
        }
        beam(firstX, lastX, level: 0)
        // Zweiter Balken für 16tel
        var k = 0
        while k < group.count {
            if group[k].dur == 1 {
                var e = k
                while e + 1 < group.count, group[e + 1].dur == 1 { e += 1 }
                if e > k {
                    beam(sxs[k], sxs[e], level: 1)
                } else {
                    let stub = ls * 1.1
                    if k == group.count - 1 || (k > 0 && group[k - 1].dur == 3) {
                        beam(sxs[k] - stub, sxs[k], level: 1)
                    } else {
                        beam(sxs[k], sxs[k] + stub, level: 1)
                    }
                }
                k = e + 1
            } else { k += 1 }
        }
    }

    private func tie(_ ctx: GraphicsContext, from a: ScoreItem, xa: CGFloat, to xb: CGFloat, style: Style) {
        let down = stemDown(a.diatonic, treble: a.treble)
        for (k, d) in a.diatonic.enumerated() {
            let y = g.y(d, treble: a.treble)
            let s: CGFloat = down ? -1 : 1      // Bogen auf der Seite gegenüber dem Hals
            let x0 = xa + headW * 0.55, x1 = xb - headW * 0.55
            guard x1 > x0 + 2 else { continue }
            let y0 = y + s * ls * 0.55
            let bend = min(ls * 1.0, (x1 - x0) * 0.18) + ls * 0.25
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y0))
            p.addQuadCurve(to: CGPoint(x: x1, y: y0), control: CGPoint(x: (x0 + x1) / 2, y: y0 + s * bend))
            p.addQuadCurve(to: CGPoint(x: x0, y: y0), control: CGPoint(x: (x0 + x1) / 2, y: y0 + s * (bend - ls * 0.28)))
            p.closeSubpath()
            ctx.fill(p, with: .color(style.color(a.noteIdx[k])))
        }
    }

    /// Einzelne Viertelnote zeichnen (z. B. Notenlese-Trainer)
    func drawLoneNote(_ ctx: GraphicsContext, pitch p: Int, x: CGFloat, treble: Bool, fifths: Int = 0, color: Color, label: String? = nil) {
        let sp = Score.spell(p, fifths: fifths)
        let keyAlter = Score.keyAlters(fifths)[((sp.diatonic % 7) + 7) % 7]
        let it = ScoreItem(kind: .chord, hand: treble ? .right : .left, treble: treble, tick: 0, dur: 4, bar: 0,
                           noteIdx: [0], pitches: [p], diatonic: [sp.diatonic],
                           accidental: [sp.alter != keyAlter ? sp.alter : nil])
        drawSingle(ctx, it, x: x, style: Style(color: { _ in color }, label: { _, _, _ in label }, labelInHead: false))
    }

    /// Zeichnet die Einträge `indices` (nach Tick sortiert) der Partitur.
    func drawItems(_ ctx: GraphicsContext, score: Score, indices: [Int], x: (Int) -> CGFloat,
                   barCenter: (Int) -> CGFloat, style: Style) {
        let items = score.items
        for hand in [Hand.right, Hand.left] {
            let seq = indices.filter { items[$0].hand == hand }
            var i = 0
            while i < seq.count {
                let it = items[seq[i]]
                if it.kind == .rest {
                    let rx = it.wholeBarRest ? barCenter(it.bar) : x(seq[i]) + headW * 0.2
                    rest(ctx, dur: it.dur, wholeBar: it.wholeBarRest, x: rx, treble: it.treble, color: ink.opacity(0.9))
                    i += 1
                    continue
                }
                var grp = [seq[i]]
                if it.dur < 4 {
                    var j = i + 1
                    while j < seq.count {
                        let a = items[grp[grp.count - 1]], b = items[seq[j]]
                        guard b.kind == .chord, b.dur < 4, b.tick == a.tick + a.dur, b.bar == a.bar,
                              b.treble == a.treble, score.beatGroupIndex(a) == score.beatGroupIndex(b) else { break }
                        grp.append(seq[j])
                        j += 1
                    }
                }
                if grp.count >= 2 {
                    drawBeamGroup(ctx, grp.map { items[$0] }, xs: grp.map { x($0) }, style: style)
                } else {
                    drawSingle(ctx, it, x: x(seq[i]), style: style)
                }
                for (gi, idx) in grp.enumerated() where items[idx].tieToNext {
                    let pos = i + gi
                    if pos + 1 < seq.count {
                        tie(ctx, from: items[idx], xa: x(idx), to: x(seq[pos + 1]), style: style)
                    }
                }
                i += grp.count
            }
        }
    }
}

extension Score {
    /// Alteration einer Tonhöhe bei gegebener Stammton-Stufe
    static func spellAlter(_ p: Int, diatonic d: Int) -> Int {
        let oct = d >= 0 ? d / 7 : (d - 6) / 7
        let letter = ((d % 7) + 7) % 7
        let natural = oct * 12 + [0, 2, 4, 5, 7, 9, 11][letter]
        return p - natural
    }
}
