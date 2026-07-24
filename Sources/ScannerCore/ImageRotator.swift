import CoreGraphics

/// A quarter-turn (or half-turn) applied to a page by the user.
public enum PageRotation: Sendable {
    case left   // 90° counter-clockwise
    case right  // 90° clockwise
    case flip   // 180°
}

/// Rotates a scanned page image. Grayscale scans stay grayscale (so B/W pages
/// keep their small size); 90° turns swap width and height.
public enum ImageRotator {
    public static func rotate(_ image: CGImage, _ rotation: PageRotation) -> CGImage {
        // CGContext.rotate is counter-clockwise for positive angles.
        switch rotation {
        case .left:  return rotated(image, radians: .pi / 2, swapDimensions: true) ?? image
        case .right: return rotated(image, radians: -.pi / 2, swapDimensions: true) ?? image
        case .flip:  return rotated(image, radians: .pi, swapDimensions: false) ?? image
        }
    }

    private static func rotated(_ image: CGImage, radians: CGFloat, swapDimensions: Bool) -> CGImage? {
        let srcW = image.width
        let srcH = image.height
        let dstW = swapDimensions ? srcH : srcW
        let dstH = swapDimensions ? srcW : srcH

        let isGray = (image.colorSpace?.numberOfComponents ?? 3) == 1
        let colorSpace = isGray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = isGray
            ? CGImageAlphaInfo.none.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Rotate about the destination centre, then draw the source centred.
        context.translateBy(x: CGFloat(dstW) / 2, y: CGFloat(dstH) / 2)
        context.rotate(by: radians)
        context.draw(
            image,
            in: CGRect(x: -CGFloat(srcW) / 2, y: -CGFloat(srcH) / 2, width: CGFloat(srcW), height: CGFloat(srcH))
        )
        return context.makeImage()
    }
}
