// Draws the app icon and writes a 1024×1024 PNG. Usage: swift make_icon.swift <output.png>
import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Background tile on the macOS icon grid (824pt square inside 1024).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
context.saveGState()
context.addPath(rounded(tile, 186))
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x7C8BFF), color(0x4B3BE0), color(0x2A1FA8)] as CFArray, locations: [0, 0.6, 1]
)!
context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
context.restoreGState()

// Three sorted "cards" peeking out behind an envelope.
let cards: [(CGRect, UInt32)] = [
    (CGRect(x: 292, y: 560, width: 440, height: 190), 0xFF6FAE),
    (CGRect(x: 252, y: 500, width: 520, height: 200), 0xFFB13D),
    (CGRect(x: 212, y: 440, width: 600, height: 210), 0x3DDC97),
]
for (rect, hex) in cards {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x000000, 0.22))
    context.addPath(rounded(rect, 44))
    context.setFillColor(color(hex))
    context.fillPath()
    context.restoreGState()
}

let envelope = CGRect(x: 172, y: 250, width: 680, height: 380)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.32))
context.addPath(rounded(envelope, 56))
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.restoreGState()

// Envelope flap.
context.saveGState()
context.addPath(rounded(envelope, 56))
context.clip()
context.move(to: CGPoint(x: envelope.minX + 34, y: envelope.maxY - 40))
context.addLine(to: CGPoint(x: envelope.midX, y: envelope.midY - 10))
context.addLine(to: CGPoint(x: envelope.maxX - 34, y: envelope.maxY - 40))
context.setStrokeColor(color(0xC3C8F4))
context.setLineWidth(24)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()
context.restoreGState()

context.flush()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
