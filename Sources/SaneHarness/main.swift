import Foundation
import CoreGraphics
import CoreText
import ImageIO
import ScannerCore

// Developer CLI to exercise ScannerCore against the real scanner without the GUI.
// Uses the vendor build output relative to this source file (dev machine only).

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let vendorOut = repoRoot.appendingPathComponent("vendor/out")

let scanner = SaneScanner(
    libraryDir: vendorOut.appendingPathComponent("lib"),
    configDir: vendorOut.appendingPathComponent("etc/sane.d")
)

func savePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "harness", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot create \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "harness", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("""
    usage: SaneHarness list
           SaneHarness scan [--duplex] [--mode color|gray|bw] [--dpi N] [--deskew] \
    [--skip-blank] [--paper a4|a5|letter|legal] [--out DIR]
    """)
    exit(2)
}

do {
    switch command {
    case "list":
        if let info = try scanner.probeForScanner() {
            print("found: \(info.name) (\(info.vendor) \(info.model))")
        } else {
            print("no scanner found")
            exit(1)
        }

    case "scan":
        var settings = ScanSettings()
        var outDir = FileManager.default.currentDirectoryPath
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--duplex": settings.duplex = true
            case "--auto-rotate": settings.autoRotate = true
            case "--deskew": settings.deskew = true
            case "--skip-blank": settings.skipBlankPages = true
            case "--mode":
                i += 1
                switch arguments[i] {
                case "color": settings.mode = .color
                case "gray": settings.mode = .gray
                case "bw": settings.mode = .blackAndWhite
                default: print("unknown mode \(arguments[i])"); exit(2)
                }
            case "--dpi":
                i += 1
                settings.resolution = Int(arguments[i]) ?? 300
            case "--paper":
                i += 1
                guard let size = PaperSize(rawValue: arguments[i]) else {
                    print("unknown paper \(arguments[i])"); exit(2)
                }
                settings.paperSize = size
            case "--out":
                i += 1
                outDir = arguments[i]
            default:
                print("unknown argument \(arguments[i])"); exit(2)
            }
            i += 1
        }

        let outURL = URL(fileURLWithPath: outDir)
        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        var lastReported = -1
        let count = try scanner.scan(settings: settings, onProgress: { page, fraction in
            let percent = Int(fraction * 100)
            if percent / 25 != lastReported {
                lastReported = percent / 25
                print("  page \(page): \(percent)%")
            }
        }, onPage: { page in
            let url = outURL.appendingPathComponent("page-\(page.index).png")
            do {
                try savePNG(page.image, to: url)
                print("saved \(url.path) (\(page.image.width)x\(page.image.height) @ \(page.dpi)dpi)")
            } catch {
                print("failed saving page \(page.index): \(error.localizedDescription)")
            }
        })
        print(count == 0 ? "feeder empty — no pages scanned" : "done: \(count) page(s)")

    case "convert":
        // convert <image...> --format pdf|searchablePDF|jpeg|png|tiff --out DIR [--dpi N]
        var files: [String] = []
        var format = OutputFormat.pdf
        var outDir = FileManager.default.currentDirectoryPath
        var dpi = 200
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--format":
                i += 1
                guard let f = OutputFormat(rawValue: arguments[i]) else {
                    print("unknown format \(arguments[i])"); exit(2)
                }
                format = f
            case "--out":
                i += 1
                outDir = arguments[i]
            case "--dpi":
                i += 1
                dpi = Int(arguments[i]) ?? 200
            default:
                files.append(arguments[i])
            }
            i += 1
        }
        var pages: [ScannedPage] = []
        for (n, file) in files.enumerated() {
            let url = URL(fileURLWithPath: file)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                print("cannot read \(file)"); exit(1)
            }
            pages.append(ScannedPage(image: image, dpi: dpi, index: n + 1))
        }
        let urls = try ScanWriter.write(
            pages: pages,
            format: format,
            directory: URL(fileURLWithPath: outDir),
            baseName: "Converted",
            onPageProcessed: { print("  processed page \($0)") }
        )
        for url in urls { print("wrote \(url.path)") }

    case "upright":
        // upright <in.png> <out.png> — run OrientationCorrector on one image.
        guard arguments.count >= 3 else { print("usage: upright <in> <out>"); exit(2) }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            print("cannot read \(arguments[1])"); exit(1)
        }
        let out = OrientationCorrector.uprightImage(img)
        try savePNG(out, to: URL(fileURLWithPath: arguments[2]))
        print("wrote \(arguments[2])")

    case "upright-pair":
        // upright-pair <frontIn> <backIn> <frontOut> <backOut> — duplex pairing
        guard arguments.count >= 5 else { print("usage: upright-pair <fIn> <bIn> <fOut> <bOut>"); exit(2) }
        func read(_ p: String) -> CGImage {
            guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
                  let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { print("cannot read \(p)"); exit(1) }
            return i
        }
        let (fOut, bOut) = OrientationCorrector.uprightPair(read(arguments[1]), read(arguments[2]))
        try savePNG(fOut, to: URL(fileURLWithPath: arguments[3]))
        try savePNG(bOut, to: URL(fileURLWithPath: arguments[4]))
        print("wrote \(arguments[3]) and \(arguments[4])")

    case "rotate-test":
        // Headless check of OrientationCorrector: upright text stays upright,
        // upside-down text is flipped back, blank pages are left untouched.
        func rgbContext(_ w: Int, _ h: Int) -> CGContext {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            return ctx
        }
        func textImage() -> CGImage {
            let w = 1000, h = 1400
            let ctx = rgbContext(w, h)
            let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
            var y = h - 160
            for line in ["SCANNER TEST", "orientation check", "fi-6110 2026", "the quick brown fox"] {
                let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attrs))
                ctx.textPosition = CGPoint(x: 90, y: CGFloat(y))
                CTLineDraw(ctLine, ctx)
                y -= 130
            }
            return ctx.makeImage()!
        }
        func flip180(_ image: CGImage) -> CGImage {
            let ctx = rgbContext(image.width, image.height)
            ctx.translateBy(x: CGFloat(image.width), y: CGFloat(image.height))
            ctx.rotate(by: .pi)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return ctx.makeImage()!
        }
        func readsUpright(_ image: CGImage) -> Bool {
            OCREngine.recognize(image).map { $0.text }.joined(separator: " ").uppercased().contains("SCANNER")
        }

        let upright = textImage()
        let blank = rgbContext(800, 1000).makeImage()!

        let keptUpright = readsUpright(OrientationCorrector.uprightImage(upright))
        let corrected = readsUpright(OrientationCorrector.uprightImage(flip180(upright)))
        let correctedBlank = OrientationCorrector.uprightImage(blank)
        let blankUntouched = correctedBlank.width == blank.width && correctedBlank.height == blank.height

        print("upright kept upright:   \(keptUpright ? "PASS" : "FAIL")")
        print("upside-down corrected:  \(corrected ? "PASS" : "FAIL")")
        print("blank left unchanged:   \(blankUntouched ? "PASS" : "FAIL")")
        exit(keptUpright && corrected && blankUntouched ? 0 : 1)

    default:
        print("unknown command \(command)")
        exit(2)
    }
} catch {
    print("error: \(error)")
    exit(1)
}
