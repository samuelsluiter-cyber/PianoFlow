import AppKit

// Zeichnet das PianoFlow-Icon (1024 px): dunkler Verlauf, fallende Noten, Klaviatur
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let bg = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: size - 80, height: size - 80), xRadius: 200, yRadius: 200)
bg.addClip()
let grad = NSGradient(colors: [NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.18, alpha: 1),
                               NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.30, alpha: 1)])!
grad.draw(in: bg, angle: -90)

// Klaviatur unten
let kbTop = 330.0
let whiteW = (size - 80) / 8
for i in 0..<8 {
    let r = NSRect(x: 40 + Double(i) * whiteW + 4, y: 40, width: whiteW - 8, height: kbTop - 40)
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
}
for i in [0, 1, 3, 4, 5] {
    let x = 40 + Double(i + 1) * whiteW - whiteW * 0.3
    let r = NSRect(x: x, y: 40 + (kbTop - 40) * 0.38, width: whiteW * 0.6, height: (kbTop - 40) * 0.62)
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
}

// Fallende Noten
let blue = NSColor(calibratedRed: 0.30, green: 0.68, blue: 1.0, alpha: 1)
let orange = NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.22, alpha: 1)
let notes: [(Int, Double, Double, NSColor)] = [(1, 360, 230, orange), (3, 520, 300, blue), (5, 380, 160, blue), (6, 600, 250, blue), (2, 700, 160, orange)]
for (k, y, h, c) in notes {
    let r = NSRect(x: 40 + Double(k) * whiteW + 14, y: y, width: whiteW - 28, height: h)
    c.setFill()
    NSBezierPath(roundedRect: r, xRadius: 22, yRadius: 22).fill()
}

// Trefferlinie
ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.85).cgColor)
ctx.fill(CGRect(x: 40, y: kbTop + 6, width: size - 80, height: 10))
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
