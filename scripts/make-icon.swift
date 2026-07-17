import AppKit
import Foundation

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("No graphics context")
}

let backgroundRect = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius = CGFloat(size) * 0.22
let backgroundPath = CGPath(roundedRect: backgroundRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
context.addPath(backgroundPath)
context.setFillColor(NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor)
context.fillPath()

let pageWidth = CGFloat(size) * 0.42
let pageHeight = CGFloat(size) * 0.54
let pageCorner = CGFloat(size) * 0.03
let centerX = CGFloat(size) / 2
let centerY = CGFloat(size) / 2

let layers: [(CGFloat, CGFloat, NSColor)] = [
    (-18, -18, NSColor(calibratedWhite: 0.28, alpha: 1.0)),
    (0, 0, NSColor(calibratedWhite: 0.4, alpha: 1.0)),
    (18, 18, NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0))
]

for (dx, dy, color) in layers {
    let rect = CGRect(
        x: centerX - pageWidth / 2 + dx,
        y: centerY - pageHeight / 2 + dy,
        width: pageWidth,
        height: pageHeight
    )
    let path = CGPath(roundedRect: rect, cornerWidth: pageCorner, cornerHeight: pageCorner, transform: nil)
    context.addPath(path)
    context.setFillColor(color.cgColor)
    context.fillPath()
}

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not generate PNG data")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
