import Cocoa

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let pad: CGFloat = 88
let iconRect = rect.insetBy(dx: pad, dy: pad)
let cornerRadius: CGFloat = 190

// Squircle background with deep glass gradient
let bgPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
let bgGrad = NSGradient(colors: [
    NSColor(red: 0.09, green: 0.12, blue: 0.20, alpha: 1.0),
    NSColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1.0)
])!
bgGrad.draw(in: bgPath, angle: -60)

// Subtle top glass sheen
NSGraphicsContext.saveGraphicsState()
bgPath.addClip()
let sheenRect = NSRect(x: iconRect.minX, y: iconRect.midY, width: iconRect.width, height: iconRect.height * 0.55)
let sheenGrad = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.16),
    NSColor.white.withAlphaComponent(0.0)
])!
sheenGrad.draw(in: sheenRect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Outer glass rim
NSColor.white.withAlphaComponent(0.22).setStroke()
bgPath.lineWidth = 6
bgPath.stroke()

let center = NSPoint(x: size / 2, y: size / 2)

// Outer track ring
let outerRadius: CGFloat = 250
let trackOuter = NSBezierPath()
trackOuter.appendArc(withCenter: center, radius: outerRadius, startAngle: 0, endAngle: 360)
trackOuter.lineWidth = 44
NSColor.white.withAlphaComponent(0.09).setStroke()
trackOuter.stroke()

// Antigravity arc (cyan-blue, top-left to bottom)
let agyArc = NSBezierPath()
agyArc.appendArc(withCenter: center, radius: outerRadius, startAngle: 95, endAngle: 325, clockwise: false)
agyArc.lineCapStyle = .round
agyArc.lineWidth = 44
NSColor(red: 0.30, green: 0.72, blue: 1.0, alpha: 1.0).setStroke()
agyArc.stroke()

// Inner track ring
let innerRadius: CGFloat = 168
let trackInner = NSBezierPath()
trackInner.appendArc(withCenter: center, radius: innerRadius, startAngle: 0, endAngle: 360)
trackInner.lineWidth = 38
NSColor.white.withAlphaComponent(0.09).setStroke()
trackInner.stroke()

// WorkBuddy arc (emerald-mint)
let wbArc = NSBezierPath()
wbArc.appendArc(withCenter: center, radius: innerRadius, startAngle: 200, endAngle: 75, clockwise: false)
wbArc.lineCapStyle = .round
wbArc.lineWidth = 38
NSColor(red: 0.22, green: 0.88, blue: 0.66, alpha: 1.0).setStroke()
wbArc.stroke()

// Center lightning/pulse icon
let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: center.x + 14, y: center.y + 72))
bolt.line(to: NSPoint(x: center.x - 42, y: center.y - 6))
bolt.line(to: NSPoint(x: center.x + 4, y: center.y - 6))
bolt.line(to: NSPoint(x: center.x - 14, y: center.y - 72))
bolt.line(to: NSPoint(x: center.x + 42, y: center.y + 6))
bolt.line(to: NSPoint(x: center.x - 4, y: center.y + 6))
bolt.close()
NSColor.white.withAlphaComponent(0.95).setFill()
bolt.fill()

NSGraphicsContext.restoreGraphicsState()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon_1024.png"
if let png = rep.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: outPath))
}
