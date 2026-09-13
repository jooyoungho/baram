import AppKit

let directory = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let shape = NSBezierPath(roundedRect: NSRect(x: 54, y: 54, width: 916, height: 916), xRadius: 208, yRadius: 208)
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.49, alpha: 1), ending: NSColor(calibratedRed: 0.41, green: 0.86, blue: 0.70, alpha: 1))!.draw(in: shape, angle: 55)
    NSColor.white.withAlphaComponent(0.94).setStroke()
    for (y, end) in [(640.0, 718.0), (486.0, 786.0), (332.0, 648.0)] {
        let wind = NSBezierPath()
        wind.lineWidth = 57
        wind.lineCapStyle = .round
        wind.move(to: NSPoint(x: 246, y: y))
        wind.line(to: NSPoint(x: end - 66, y: y))
        wind.curve(to: NSPoint(x: end, y: y + 84), controlPoint1: NSPoint(x: end + 26, y: y), controlPoint2: NSPoint(x: end + 34, y: y + 84))
        wind.stroke()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name)) }
}
