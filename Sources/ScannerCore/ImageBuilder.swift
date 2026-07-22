import Foundation
import CoreGraphics
import CSane

/// Converts raw SANE frame data into a CGImage.
enum ImageBuilder {
    static func makeImage(params: SANE_Parameters, data: Data) -> CGImage? {
        let bytesPerLine = Int(params.bytes_per_line)
        let width = Int(params.pixels_per_line)
        guard bytesPerLine > 0, width > 0 else { return nil }
        // params.lines is -1 when the backend doesn't know the height up front.
        let height = params.lines > 0
            ? min(Int(params.lines), data.count / bytesPerLine)
            : data.count / bytesPerLine
        guard height > 0 else { return nil }

        switch (params.format, Int(params.depth)) {
        case (SANE_FRAME_GRAY, 1):
            return data.withUnsafeBytes { raw -> CGImage? in
                let src = raw.bindMemory(to: UInt8.self)
                var pixels = [UInt8](repeating: 0, count: width * height)
                for y in 0..<height {
                    let row = y * bytesPerLine
                    for x in 0..<width {
                        let bit = (src[row + (x >> 3)] >> (7 - (x & 7))) & 1
                        pixels[y * width + x] = bit == 1 ? 0 : 255  // 1 = black
                    }
                }
                return grayImage(pixels, width: width, height: height)
            }

        case (SANE_FRAME_GRAY, 8):
            return data.withUnsafeBytes { raw -> CGImage? in
                let src = raw.bindMemory(to: UInt8.self)
                var pixels = [UInt8](repeating: 0, count: width * height)
                for y in 0..<height {
                    let row = y * bytesPerLine
                    pixels.replaceSubrange(y * width..<(y + 1) * width,
                                           with: src[row..<row + width])
                }
                return grayImage(pixels, width: width, height: height)
            }

        case (SANE_FRAME_RGB, 8):
            return data.withUnsafeBytes { raw -> CGImage? in
                let src = raw.bindMemory(to: UInt8.self)
                var pixels = [UInt8](repeating: 255, count: width * height * 4)
                for y in 0..<height {
                    let row = y * bytesPerLine
                    for x in 0..<width {
                        let s = row + x * 3
                        let d = (y * width + x) * 4
                        pixels[d] = src[s]
                        pixels[d + 1] = src[s + 1]
                        pixels[d + 2] = src[s + 2]
                    }
                }
                return rgbaImage(pixels, width: width, height: height)
            }

        default:
            return nil
        }
    }

    private static func grayImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = pixels
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }) else { return nil }
        return context.makeImage()
    }

    private static func rgbaImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = pixels
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        }) else { return nil }
        return context.makeImage()
    }
}
