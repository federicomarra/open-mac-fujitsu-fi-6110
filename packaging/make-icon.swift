// Renders the app icon (a document scanner with a page emerging) at 1024x1024.
// Run by packaging/make-icon.sh; writes icon-1024.png to the given path.
import AppKit
import CoreGraphics

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

let s = CGFloat(size)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Big Sur-style squircle plate with a soft blue-gray vertical gradient.
let plate = CGRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
ctx.saveGState()
ctx.addPath(rounded(plate, s * 0.18))
ctx.clip()
let bgColors = [
    CGColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1),
    CGColor(red: 0.78, green: 0.83, blue: 0.89, alpha: 1),
] as CFArray
let bgGradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: s / 2, y: plate.maxY),
    end: CGPoint(x: s / 2, y: plate.minY),
    options: []
)
ctx.restoreGState()

// Emerging page (white, slightly above the scanner slot) with scan lines.
let page = CGRect(x: s * 0.30, y: s * 0.42, width: s * 0.40, height: s * 0.34)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
ctx.addPath(rounded(page, s * 0.012))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Text lines on the page.
ctx.setFillColor(CGColor(red: 0.55, green: 0.65, blue: 0.78, alpha: 1))
var lineY = page.maxY - s * 0.055
for i in 0..<5 {
    let widthFactor: CGFloat = i == 4 ? 0.55 : 0.78
    let lineRect = CGRect(
        x: page.minX + s * 0.045,
        y: lineY,
        width: (page.width - s * 0.09) * widthFactor,
        height: s * 0.018
    )
    ctx.addPath(rounded(lineRect, s * 0.009))
    ctx.fillPath()
    lineY -= s * 0.055
}

// A green "scan beam" line across the page at the slot.
ctx.setFillColor(CGColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 0.9))
ctx.fill(CGRect(x: page.minX - s * 0.02, y: s * 0.435, width: page.width + s * 0.04, height: s * 0.008))

// Scanner body: dark slate, slightly trapezoidal front (drawn over page bottom).
let bodyTop = s * 0.44
let bodyBottom = s * 0.175
let body = CGMutablePath()
body.move(to: CGPoint(x: s * 0.16, y: bodyBottom))
body.addLine(to: CGPoint(x: s * 0.84, y: bodyBottom))
body.addLine(to: CGPoint(x: s * 0.80, y: bodyTop))
body.addLine(to: CGPoint(x: s * 0.20, y: bodyTop))
body.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
ctx.addPath(body)
let bodyColors = [
    CGColor(red: 0.33, green: 0.38, blue: 0.45, alpha: 1),
    CGColor(red: 0.20, green: 0.24, blue: 0.30, alpha: 1),
] as CFArray
ctx.clip()
let bodyGradient = CGGradient(colorsSpace: space, colors: bodyColors, locations: [0, 1])!
ctx.drawLinearGradient(
    bodyGradient,
    start: CGPoint(x: s / 2, y: bodyTop),
    end: CGPoint(x: s / 2, y: bodyBottom),
    options: []
)
ctx.restoreGState()

// Feeder slot on the body.
ctx.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1))
let slot = CGRect(x: s * 0.27, y: s * 0.415, width: s * 0.46, height: s * 0.022)
ctx.addPath(rounded(slot, s * 0.011))
ctx.fillPath()

// Power light.
ctx.setFillColor(CGColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1))
ctx.fillEllipse(in: CGRect(x: s * 0.745, y: s * 0.245, width: s * 0.03, height: s * 0.03))

// Front ridge detail.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
ctx.fill(CGRect(x: s * 0.185, y: s * 0.30, width: s * 0.63, height: s * 0.012))

guard let image = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
