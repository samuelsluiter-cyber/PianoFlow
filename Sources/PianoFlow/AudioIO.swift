import Foundation
import AVFoundation
import AudioToolbox
import CoreMIDI

enum PianoSound: Int, CaseIterable, Identifiable {
    case grand = 0, bright = 1, epiano = 4, epiano2 = 5, harpsichord = 6, vibes = 11,
         organ = 19, strings = 48, choir = 52, pad = 89
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .grand: return "Konzertflügel"
        case .bright: return "Heller Flügel"
        case .epiano: return "E-Piano (Rhodes)"
        case .epiano2: return "E-Piano (FM)"
        case .harpsichord: return "Cembalo"
        case .vibes: return "Vibraphon"
        case .organ: return "Kirchenorgel"
        case .strings: return "Streicher"
        case .choir: return "Chor"
        case .pad: return "Synth-Pad"
        }
    }
}

/// Klang für Begleitung, eigene Tasten (mit Pedal) und Metronom.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private let accomp = AVAudioUnitSampler()
    private let own = AVAudioUnitSampler()
    private let clicker = AVAudioUnitSampler()
    private let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")

    private var pedalDown = false
    private var held = Set<UInt8>()
    private var sustained = Set<UInt8>()

    var accompVolume: Float {
        get { accomp.volume }
        set { accomp.volume = newValue; Prefs.set("accompVolume", Double(newValue)) }
    }
    var ownVolume: Float {
        get { own.volume }
        set { own.volume = newValue; Prefs.set("ownVolume", Double(newValue)) }
    }
    var clickVolume: Float {
        get { clicker.volume }
        set { clicker.volume = newValue; Prefs.set("clickVolume", Double(newValue)) }
    }
    private(set) var sound: PianoSound = .grand

    init() {
        for n in [accomp, own, clicker] {
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: nil)
        }
        do { try engine.start() } catch { print("Audio-Start fehlgeschlagen: \(error)") }
        setSound(PianoSound(rawValue: Prefs.int("sound", 0)) ?? .grand)
        if FileManager.default.fileExists(atPath: bank.path) {
            try? clicker.loadSoundBankInstrument(at: bank, program: 0,
                                                 bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
                                                 bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        }
        accomp.volume = Float(Prefs.double("accompVolume", 0.8))
        own.volume = Float(Prefs.double("ownVolume", 1.0))
        clicker.volume = Float(Prefs.double("clickVolume", 0.8))
    }

    func setSound(_ s: PianoSound) {
        sound = s
        Prefs.set("sound", s.rawValue)
        guard FileManager.default.fileExists(atPath: bank.path) else { return }
        for n in [accomp, own] {
            try? n.loadSoundBankInstrument(at: bank, program: UInt8(s.rawValue),
                                           bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                           bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        }
    }

    // Begleitung
    func noteOn(_ p: UInt8, velocity: UInt8 = 90) { accomp.startNote(p, withVelocity: velocity, onChannel: 0) }
    func noteOff(_ p: UInt8) { accomp.stopNote(p, onChannel: 0) }
    func allOff() { for p in 0...127 { accomp.stopNote(UInt8(p), onChannel: 0) } }
    func preview(_ p: UInt8, duration: Double = 0.9, velocity: UInt8 = 95) {
        noteOn(p, velocity: velocity)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.noteOff(p) }
    }

    // Eigene Tasten
    func ownOn(_ p: UInt8, velocity: UInt8) {
        if sustained.contains(p) { own.stopNote(p, onChannel: 0); sustained.remove(p) }
        held.insert(p)
        own.startNote(p, withVelocity: max(velocity, 25), onChannel: 0)
    }
    func ownOff(_ p: UInt8) {
        held.remove(p)
        if pedalDown { sustained.insert(p) } else { own.stopNote(p, onChannel: 0) }
    }
    func setPedal(_ down: Bool) {
        pedalDown = down
        if !down {
            for p in sustained where !held.contains(p) { own.stopNote(p, onChannel: 0) }
            sustained.removeAll()
        }
    }

    func click(accent: Bool) {
        clicker.startNote(accent ? 76 : 77, withVelocity: accent ? 127 : 85, onChannel: 0)
    }
}

/// Liest alle angeschlossenen MIDI-Keyboards (USB / Bluetooth) automatisch ein.
final class MidiInput {
    var onNoteOn: ((UInt8, UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?
    var onSourcesChanged: (([String]) -> Void)?
    var onPedal: ((Bool) -> Void)?
    private(set) var sourceNames: [String] = []
    private(set) var pedalDown = false

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected = Set<MIDIEndpointRef>()
    private var micNote: UInt8?

    init() {
        MIDIClientCreateWithBlock("PianoFlow" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        MIDIInputPortCreateWithBlock(client, "PianoFlow In" as CFString, &port) { [weak self] list, _ in
            self?.parse(list)
        }
        refresh()
    }

    func refresh() {
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            if !connected.contains(src) {
                MIDIPortConnectSource(port, src, nil)
                connected.insert(src)
            }
            var cf: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &cf) == noErr,
               let s = cf?.takeRetainedValue() {
                names.append(s as String)
            }
        }
        sourceNames = names
        onSourcesChanged?(names)
    }

    /// Erkannte Mikrofon-Note einspeisen (einstimmig)
    func injectMic(_ note: UInt8?) {
        guard note != micNote else { return }
        if let old = micNote { onNoteOff?(old) }
        micNote = note
        if let n = note { onNoteOn?(n, 80) }
    }

    private func parse(_ list: UnsafePointer<MIDIPacketList>) {
        var events: [(kind: Int, a: UInt8, b: UInt8)] = []   // 1 = an, 0 = aus, 2 = Pedal
        var status: UInt8 = 0                                  // Running Status (DIN-MIDI)
        for packet in list.unsafeSequence() {
            let len = Int(packet.pointee.length)
            let bytes: [UInt8] = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(len)) }
            var i = 0
            while i < bytes.count {
                let s = bytes[i]
                if s >= 0xF8 { i += 1; continue }                  // Realtime
                if s >= 0xF0 { status = 0; i += 1; continue }      // SysEx / System Common
                var dataStart = i + 1
                if s < 0x80 {
                    guard status != 0 else { i += 1; continue }
                    dataStart = i                                  // Statusbyte fehlt
                } else {
                    status = s
                }
                let type = status & 0xF0
                let dataLen = (type == 0xC0 || type == 0xD0) ? 1 : 2
                guard dataStart + dataLen <= bytes.count else { break }
                let d1 = bytes[dataStart]
                let d2 = dataLen == 2 ? bytes[dataStart + 1] : 0
                switch type {
                case 0x90: events.append((d2 > 0 ? 1 : 0, d1, d2))
                case 0x80: events.append((0, d1, 0))
                case 0xB0 where d1 == 64: events.append((2, 64, d2))
                default: break
                }
                i = dataStart + dataLen
            }
        }
        guard !events.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for e in events {
                switch e.kind {
                case 1: self.onNoteOn?(e.a, e.b)
                case 0: self.onNoteOff?(e.a)
                default:
                    self.pedalDown = e.b >= 64
                    self.onPedal?(self.pedalDown)
                }
            }
        }
    }
}

/// Einstimmige Tonhöhenerkennung über das Mikrofon (YIN) – für akustische Klaviere.
final class MicInput {
    private let engine = AVAudioEngine()
    private(set) var running = false
    var onNote: ((UInt8?) -> Void)?
    private var current: UInt8?
    private var candidate: UInt8?
    private var candidateCount = 0
    private var diff: [Float] = []

    func start(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                guard granted else { completion(false); return }
                do {
                    let input = self.engine.inputNode
                    let fmt = input.outputFormat(forBus: 0)
                    let sr = fmt.sampleRate
                    input.removeTap(onBus: 0)
                    input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
                        self?.process(buf, sr: sr)
                    }
                    try self.engine.start()
                    self.running = true
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        current = nil
        onNote?(nil)
    }

    private func process(_ buf: AVAudioPCMBuffer, sr: Double) {
        guard let x = buf.floatChannelData?[0] else { return }
        let n = Int(buf.frameLength)
        guard n >= 1024 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += x[i] * x[i] }
        let rms = sqrt(sum / Float(n))
        var note: UInt8? = nil
        if rms > 0.008, let f = yin(x, n: n, sr: sr) {
            let m = 69 + 12 * log2(f / 440)
            if m > 20.5 && m < 108.5 { note = UInt8(m.rounded()) }
        }
        if note == candidate { candidateCount += 1 } else { candidate = note; candidateCount = 1 }
        if candidateCount >= 2 && candidate != current {
            current = candidate
            let c = current
            DispatchQueue.main.async { [weak self] in self?.onNote?(c) }
        }
    }

    private func yin(_ x: UnsafePointer<Float>, n: Int, sr: Double) -> Double? {
        let maxTau = min(n / 2, Int(sr / 30))
        let minTau = max(2, Int(sr / 4200))
        let w = n - maxTau
        guard maxTau > minTau + 2, w > 64 else { return nil }
        if diff.count != maxTau { diff = [Float](repeating: 0, count: maxTau) }
        for tau in 1..<maxTau {
            var s: Float = 0
            for j in 0..<w {
                let d = x[j] - x[j + tau]
                s += d * d
            }
            diff[tau] = s
        }
        diff[0] = 1
        var running: Float = 0
        for tau in 1..<maxTau {
            running += diff[tau]
            diff[tau] = running > 0 ? diff[tau] * Float(tau) / running : 1
        }
        var tau = minTau
        var found = false
        while tau < maxTau - 1 {
            if diff[tau] < 0.15 {
                while tau + 1 < maxTau - 1 && diff[tau + 1] < diff[tau] { tau += 1 }
                found = true
                break
            }
            tau += 1
        }
        guard found else { return nil }
        let a = diff[tau - 1], b = diff[tau], c = diff[tau + 1]
        let denom = 2 * (2 * b - a - c)
        let better = denom != 0 ? Float(tau) + (c - a) / denom : Float(tau)
        return sr / Double(better)
    }
}

final class AppServices {
    static let shared = AppServices()
    let audio = AudioEngine()
    let midi = MidiInput()
    let mic = MicInput()

    init() {
        midi.onPedal = { [weak self] down in self?.audio.setPedal(down) }
        mic.onNote = { [weak self] n in self?.midi.injectMic(n) }
    }
}
