import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let pixels = Int(CommandLine.arguments[1]) else {
    fputs("Usage: make-icon.swift <pixels> <output.png>\n", stderr)
    exit(2)
}

let size = NSSize(width: pixels, height: pixels)
let image = NSImage(size: size)
image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
let radius = CGFloat(pixels) * 0.225
let background = NSBezierPath(roundedRect: canvas.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.15, alpha: 1),
    NSColor(calibratedRed: 0.075, green: 0.08, blue: 0.075, alpha: 1)
])!
gradient.draw(in: background, angle: -55)

let innerBorder = NSBezierPath(
    roundedRect: canvas.insetBy(dx: CGFloat(pixels) * 0.035, dy: CGFloat(pixels) * 0.035),
    xRadius: radius * 0.88,
    yRadius: radius * 0.88
)
NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
innerBorder.lineWidth = max(1, CGFloat(pixels) * 0.008)
innerBorder.stroke()

let lineWidth = CGFloat(pixels) * 0.115
let center = NSPoint(x: CGFloat(pixels) * 0.50, y: CGFloat(pixels) * 0.45)

let leftRibbon = NSBezierPath()
leftRibbon.move(to: NSPoint(x: CGFloat(pixels) * 0.23, y: CGFloat(pixels) * 0.22))
leftRibbon.line(to: NSPoint(x: CGFloat(pixels) * 0.23, y: CGFloat(pixels) * 0.78))
leftRibbon.line(to: center)
leftRibbon.lineWidth = lineWidth
leftRibbon.lineCapStyle = .round
leftRibbon.lineJoinStyle = .round
NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.84, alpha: 1).setStroke()
leftRibbon.stroke()

let rightRibbon = NSBezierPath()
rightRibbon.move(to: center)
rightRibbon.line(to: NSPoint(x: CGFloat(pixels) * 0.77, y: CGFloat(pixels) * 0.78))
rightRibbon.line(to: NSPoint(x: CGFloat(pixels) * 0.77, y: CGFloat(pixels) * 0.22))
rightRibbon.lineWidth = lineWidth
rightRibbon.lineCapStyle = .round
rightRibbon.lineJoinStyle = .round
NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.12, alpha: 1).setStroke()
rightRibbon.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
