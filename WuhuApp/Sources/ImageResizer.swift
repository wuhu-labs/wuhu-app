import CoreGraphics
import Foundation
import ImageIO

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Resizes images to fit within Anthropic's recommended limits before upload.
///
/// From the Anthropic docs:
/// > To improve time-to-first-token, consider resizing images to no more than
/// > 1.15 megapixels (and within 1568 pixels in both dimensions).
///
/// The 5 MB base64 hard limit is also respected — images are compressed to fit.
enum ImageResizer {
    /// Maximum dimension on either axis.
    static let maxDimension: CGFloat = 1568

    /// Maximum total megapixels.
    static let maxMegapixels: CGFloat = 1.15

    /// Target JPEG compression quality.
    static let jpegQuality: CGFloat = 0.85

    /// Prepare image data for upload: resize if needed, pick JPEG or PNG format.
    ///
    /// - Parameters:
    ///   - data: Raw image data (any format supported by ImageIO).
    ///   - sourceMimeType: Original MIME type hint.
    /// - Returns: Tuple of (resized data, mime type), or the original if no resize needed.
    static func prepare(data: Data, sourceMimeType: String) -> (data: Data, mimeType: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return (data, sourceMimeType)
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let megapixels = (width * height) / 1_000_000

        let needsResize = width > maxDimension || height > maxDimension || megapixels > maxMegapixels

        // Determine output format: keep PNG only if the source has alpha and is already small enough.
        let hasAlpha = imageHasAlpha(cgImage)
        let outputAsPNG = hasAlpha && !needsResize && data.count < 4 * 1024 * 1024

        if !needsResize, !outputAsPNG {
            // No resize needed. If it's already JPEG, pass through.
            // Otherwise re-encode as JPEG to stay under size limits.
            if sourceMimeType == "image/jpeg", data.count < 4 * 1024 * 1024 {
                return (data, sourceMimeType)
            }
            // Re-encode but don't resize
            if let encoded = encodeJPEG(cgImage, quality: jpegQuality) {
                return (encoded, "image/jpeg")
            }
            return (data, sourceMimeType)
        }

        if !needsResize, outputAsPNG {
            // Small PNG with alpha — keep as-is.
            return (data, sourceMimeType)
        }

        // Calculate target dimensions
        let scale = resizeScale(width: width, height: height)
        let newWidth = Int((width * scale).rounded(.down))
        let newHeight = Int((height * scale).rounded(.down))

        guard let resized = resizeImage(cgImage, to: CGSize(width: newWidth, height: newHeight)) else {
            return (data, sourceMimeType)
        }

        if hasAlpha {
            // Try PNG first for alpha images; fall back to JPEG if too large.
            if let pngData = encodePNG(resized), pngData.count < 4 * 1024 * 1024 {
                return (pngData, "image/png")
            }
        }

        if let jpegData = encodeJPEG(resized, quality: jpegQuality) {
            return (jpegData, "image/jpeg")
        }

        return (data, sourceMimeType)
    }

    // MARK: - Private

    private static func resizeScale(width: CGFloat, height: CGFloat) -> CGFloat {
        var scale: CGFloat = 1.0

        // Clamp to max dimension
        let longestSide = max(width, height)
        if longestSide > maxDimension {
            scale = min(scale, maxDimension / longestSide)
        }

        // Clamp to max megapixels
        let currentMP = (width * scale * height * scale) / 1_000_000
        if currentMP > maxMegapixels {
            let mpScale = sqrt(maxMegapixels / currentMP)
            scale *= mpScale
        }

        return scale
    }

    private static func imageHasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        default:
            false
        }
    }

    private static func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
