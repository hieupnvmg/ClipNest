// Compose a compact README GIF from offscreen ClipNest previews with synthetic data.
// Usage: swift scripts/make-demo-gif.swift <frames directory> <output.gif>
import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
 guard arguments.count == 3 else { fatalError("Expected frames directory and output GIF") }
let folder = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let width = 1200
let height = 420
struct Scene {
  let file: String
  let instruction: String
  let delay: Double
  var alpha: CGFloat = 1
  var offset: CGFloat = 0
}
var scenes: [Scene] = []
for i in 1...8 {
  let t = CGFloat(i) / 8
  scenes.append(Scene(file: "open", instruction: "01   ⇧⌘V  ·  Open / Mở", delay: 0.06,
    alpha: t, offset: -22 * (1 - t)))
}
scenes.append(Scene(file: "open", instruction: "01   ⇧⌘V  ·  Open / Mở", delay: 1.3))
scenes.append(Scene(file: "search", instruction: "02   Type to search / Gõ để tìm", delay: 0.5))
for (index, query) in ["d", "de", "des", "desi", "desig", "design"].enumerated() {
  scenes.append(Scene(file: "query-\(index)", instruction: "02   Type to search / Gõ để tìm",
    delay: query == "design" ? 1.4 : 0.24))
}
scenes.append(Scene(file: "selected", instruction: "03   →  Select / Chọn   ·   ↩  Paste / Dán", delay: 2.2))
for i in 1...6 {
  let t = CGFloat(i) / 6
  scenes.append(Scene(file: "selected", instruction: "03   →  Select / Chọn   ·   ↩  Paste / Dán",
    delay: 0.07, alpha: 1 - t, offset: -22 * t))
}
scenes.append(Scene(file: "open", instruction: "⇧⌘V   Your clipboard, within reach.", delay: 0.7, alpha: 0))
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, scenes.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let colorSpace = CGColorSpaceCreateDeviceRGB()
var cache: [String: NSImage] = [:]
for scene in scenes {
  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.99, alpha: 1).setFill()
  NSRect(x: 0, y: 0, width: width, height: height).fill()
  func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
    weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
  }
  text("ClipNest", x: 30, y: 365, size: 27, weight: .bold, color: NSColor(calibratedWhite: 0.12, alpha: 1))
  text("Copy once. Find it whenever you need it.", x: 31, y: 342, size: 14,
    color: NSColor(calibratedWhite: 0.38, alpha: 1))
  text(scene.instruction, x: 660, y: 371, size: 15, weight: .medium,
    color: NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.65, alpha: 1))
  let sample = "Demo with sample content · Minh họa bằng dữ liệu mẫu"
  text(sample, x: 31, y: 14, size: 11, color: NSColor(calibratedWhite: 0.48, alpha: 1))
  let image = cache[scene.file] ?? NSImage(contentsOf: folder.appendingPathComponent(scene.file + ".png"))!
  cache[scene.file] = image
  let panelWidth: CGFloat = 1140
  let panelHeight = panelWidth * image.size.height / image.size.width
  image.draw(in: NSRect(x: 30, y: 46 + scene.offset, width: panelWidth, height: panelHeight),
    from: .zero, operation: .sourceOver, fraction: scene.alpha)
  NSGraphicsContext.restoreGraphicsState()
  CGImageDestinationAddImage(destination, context.makeImage()!, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: scene.delay]
  ] as CFDictionary)
}
precondition(CGImageDestinationFinalize(destination), "Failed to encode GIF")
print("Created \(scenes.count)-frame GIF: \(output.path)")
